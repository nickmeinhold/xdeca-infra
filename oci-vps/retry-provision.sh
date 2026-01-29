#!/bin/bash
# OCI VPS auto-provisioning - multi-account
# Runs via cron every 5 minutes, tries all configured accounts

LOG=~/oci-provision.log
LOCK=/tmp/oci-provision.lock
NTFY_TOPIC="xdeca-oci-alerts"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ACCOUNTS_FILE="$SCRIPT_DIR/accounts.yaml"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519.pub"

log() { echo "$(date): $*" >> "$LOG"; }

notify() {
    local title="$1"
    local msg="$2"
    local priority="${3:-default}"
    curl -s -H "Title: $title" -H "Priority: $priority" -H "Tags: server" \
        -d "$msg" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1 || true
}

# Prevent concurrent runs
if [ -f "$LOCK" ]; then
    pid=$(cat "$LOCK" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

export PATH="$HOME/.local/bin:$PATH"

# Cloud-init script for keep-alive
CLOUD_INIT=$(cat << 'CLOUDINIT'
#!/bin/bash
cat > /opt/keep-alive.sh << 'KEEPALIVE'
#!/bin/bash
dd if=/dev/urandom bs=1M count=100 | md5sum > /dev/null 2>&1
echo "$(date): keep-alive ping" >> /var/log/keep-alive.log
KEEPALIVE
chmod +x /opt/keep-alive.sh
echo "0 */6 * * * root /opt/keep-alive.sh" > /etc/cron.d/keep-alive
apt-get update && apt-get install -y htop curl
CLOUDINIT
)

# Check if yq is available
if ! command -v yq &> /dev/null; then
    log "ERROR: yq not installed. Run: pip3 install yq"
    exit 1
fi

# Get number of accounts
NUM_ACCOUNTS=$(yq -r '.accounts | length' "$ACCOUNTS_FILE")

for i in $(seq 0 $((NUM_ACCOUNTS - 1))); do
    NAME=$(yq -r ".accounts[$i].name" "$ACCOUNTS_FILE")
    PROFILE=$(yq -r ".accounts[$i].profile" "$ACCOUNTS_FILE")
    # shellcheck disable=SC2034  # REGION used by OCI CLI via profile
    REGION=$(yq -r ".accounts[$i].region" "$ACCOUNTS_FILE")
    COMPARTMENT_ID=$(yq -r ".accounts[$i].compartment_id" "$ACCOUNTS_FILE")
    SUBNET_ID=$(yq -r ".accounts[$i].subnet_id" "$ACCOUNTS_FILE")
    IMAGE_ID=$(yq -r ".accounts[$i].image_id" "$ACCOUNTS_FILE")
    AVAILABILITY_DOMAIN=$(yq -r ".accounts[$i].availability_domain" "$ACCOUNTS_FILE")
    INSTANCE_NAME=$(yq -r ".accounts[$i].instance_name" "$ACCOUNTS_FILE")

    # Skip if not configured
    if [[ "$COMPARTMENT_ID" == *"REPLACE"* ]]; then
        log "[$NAME] Skipping - not configured"
        continue
    fi

    log "[$NAME] Checking for existing instance..."

    # Check if instance already exists
    INSTANCE_JSON=$(oci compute instance list \
        --profile "$PROFILE" \
        --compartment-id "$COMPARTMENT_ID" \
        --display-name "$INSTANCE_NAME" \
        --lifecycle-state RUNNING 2>/dev/null || echo "{}")
    EXISTING=$(echo "$INSTANCE_JSON" | grep -c '"id"' | head -1 || echo 0)

    if [ "${EXISTING:-0}" -gt 0 ]; then
        log "[$NAME] Instance already running!"

        # Get the IP
        INSTANCE_ID=$(oci compute instance list \
            --profile "$PROFILE" \
            --compartment-id "$COMPARTMENT_ID" \
            --display-name "$INSTANCE_NAME" \
            --lifecycle-state RUNNING 2>/dev/null | jq -r '.data[0].id')

        IP=$(oci compute instance list-vnics \
            --profile "$PROFILE" \
            --instance-id "$INSTANCE_ID" 2>/dev/null | jq -r '.data[0]["public-ip"]' || echo "unknown")

        notify "OCI $NAME Ready!" "Instance running at $IP" "high"
        continue
    fi

    log "[$NAME] Attempting provisioning..."

    # Create temp cloud-init file
    CLOUD_INIT_FILE=$(mktemp)
    echo "$CLOUD_INIT" > "$CLOUD_INIT_FILE"

    # Try to create instance
    OUTPUT=$(SUPPRESS_LABEL_WARNING=True oci compute instance launch \
        --profile "$PROFILE" \
        --compartment-id "$COMPARTMENT_ID" \
        --availability-domain "$AVAILABILITY_DOMAIN" \
        --shape "VM.Standard.A1.Flex" \
        --shape-config '{"ocpus": 4, "memoryInGBs": 24}' \
        --subnet-id "$SUBNET_ID" \
        --image-id "$IMAGE_ID" \
        --display-name "$INSTANCE_NAME" \
        --assign-public-ip true \
        --ssh-authorized-keys-file "$SSH_KEY_PATH" \
        --user-data-file "$CLOUD_INIT_FILE" \
        --boot-volume-size-in-gbs 50 2>&1)

    rm -f "$CLOUD_INIT_FILE"

    if echo "$OUTPUT" | grep -qi "Out of capacity\|out of host capacity"; then
        log "[$NAME] Out of capacity, will retry..."
    elif echo "$OUTPUT" | grep -qi "error\|failed\|ServiceError"; then
        ERROR_MSG=$(echo "$OUTPUT" | grep -i "message\|code" | head -2 | tr '\n' ' ')
        log "[$NAME] Error: $ERROR_MSG"
    else
        log "[$NAME] SUCCESS! Instance created."
        notify "OCI $NAME Provisioned!" "Instance created! Check console for IP." "high"
    fi
done

log "Provisioning cycle complete"
