#!/bin/bash
# Deploy services to any VPS
# Usage: ./scripts/deploy-to.sh <ip> [service]
# Services: all, caddy, openproject, twenty, discourse, calendar-sync, backups, scripts

set -e

# SOPS age key location
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

if [ -z "$1" ]; then
  echo "Usage: $0 <ip> [service]"
  echo "  ip: VPS IP address or hostname"
  echo "  service: all|caddy|openproject|twenty|discourse|scripts (default: all)"
  exit 1
fi

IP=$1
SERVICE=${2:-all}
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE="ubuntu@$IP"

echo "Deploying to $REMOTE..."

# Decrypt secrets and generate .env files
decrypt_secrets() {
    echo "Decrypting secrets..."

    if [ -f "$REPO_ROOT/openproject/secrets.yaml" ]; then
        sops -d "$REPO_ROOT/openproject/secrets.yaml" | yq -r '"OPENPROJECT_HOSTNAME=\(.hostname)
OPENPROJECT_SECRET_KEY_BASE=\(.secret_key_base)
OPENPROJECT_SMTP_ADDRESS=\(.smtp_address)
OPENPROJECT_SMTP_PORT=\(.smtp_port)
OPENPROJECT_SMTP_USER=\(.smtp_user)
OPENPROJECT_SMTP_PASSWORD=\(.smtp_password)
OPENPROJECT_SMTP_DOMAIN=\(.smtp_domain)
OPENPROJECT_MAIL_FROM=\(.mail_from)"' > "$REPO_ROOT/openproject/.env"
    fi

    if [ -f "$REPO_ROOT/twenty/secrets.yaml" ]; then
        sops -d "$REPO_ROOT/twenty/secrets.yaml" | yq -r '"TWENTY_HOSTNAME=\(.hostname)\nPOSTGRES_PASSWORD=\(.postgres_password)\nACCESS_TOKEN_SECRET=\(.access_token_secret)\nLOGIN_TOKEN_SECRET=\(.login_token_secret)\nREFRESH_TOKEN_SECRET=\(.refresh_token_secret)\nFILE_TOKEN_SECRET=\(.file_token_secret)"' > "$REPO_ROOT/twenty/.env"
    fi
}

deploy_scripts() {
    echo "Deploying backup scripts..."
    rsync -avz "$REPO_ROOT/scripts/" $REMOTE:/opt/scripts/
    ssh $REMOTE "chmod +x /opt/scripts/*.sh"
    echo "Backup scripts deployed to /opt/scripts/"
}

deploy_service() {
    local svc=$1
    echo "Deploying $svc..."
    rsync -avz --delete "$REPO_ROOT/$svc/" $REMOTE:~/apps/$svc/
    ssh $REMOTE "cd ~/apps/$svc && podman-compose pull && podman-compose up -d"
}

deploy_discourse() {
    echo "Deploying Discourse..."

    # Install Docker if not present (Discourse requires Docker, not Podman)
    if ! ssh $REMOTE "command -v docker &> /dev/null"; then
        echo "Installing Docker for Discourse..."
        ssh $REMOTE "curl -fsSL https://get.docker.com | sudo sh"
        ssh $REMOTE "sudo usermod -aG docker ubuntu"
        # Need to reconnect for group membership to take effect
        echo "Docker installed. Reconnecting..."
    fi

    # Clone discourse_docker if not present
    ssh $REMOTE "test -d ~/apps/discourse || git clone https://github.com/discourse/discourse_docker.git ~/apps/discourse"

    if [ -f "$REPO_ROOT/discourse/secrets.yaml" ]; then
        echo "Generating Discourse config from secrets..."
        HOSTNAME=$(sops -d "$REPO_ROOT/discourse/secrets.yaml" | yq -r '.hostname')
        DEV_EMAIL=$(sops -d "$REPO_ROOT/discourse/secrets.yaml" | yq -r '.developer_email')
        SMTP_ADDR=$(sops -d "$REPO_ROOT/discourse/secrets.yaml" | yq -r '.smtp_address')
        SMTP_PORT=$(sops -d "$REPO_ROOT/discourse/secrets.yaml" | yq -r '.smtp_port')
        SMTP_USER=$(sops -d "$REPO_ROOT/discourse/secrets.yaml" | yq -r '.smtp_user')
        SMTP_PASS=$(sops -d "$REPO_ROOT/discourse/secrets.yaml" | yq -r '.smtp_password')
        SMTP_DOMAIN=$(sops -d "$REPO_ROOT/discourse/secrets.yaml" | yq -r '.smtp_domain')
        NOTIF_EMAIL=$(sops -d "$REPO_ROOT/discourse/secrets.yaml" | yq -r '.notification_email')

        cat "$REPO_ROOT/discourse/app.yml.example" | \
            sed "s/discourse.example.com/$HOSTNAME/g" | \
            sed "s/admin@example.com/$DEV_EMAIL/g" | \
            sed "s/smtp.mailgun.org/$SMTP_ADDR/g" | \
            sed "s/587/$SMTP_PORT/g" | \
            sed "s/postmaster@mg.example.com/$SMTP_USER/g" | \
            sed "s/your-smtp-password/$SMTP_PASS/g" | \
            sed "s/example.com/$SMTP_DOMAIN/g" | \
            sed "s/noreply@example.com/$NOTIF_EMAIL/g" \
            > /tmp/discourse-app.yml

        ssh $REMOTE "mkdir -p ~/apps/discourse/containers"
        scp /tmp/discourse-app.yml $REMOTE:~/apps/discourse/containers/app.yml
        rm /tmp/discourse-app.yml
    else
        echo "WARNING: No discourse/secrets.yaml found. Skipping config generation."
        return 1
    fi

    # Check if Discourse container exists and is running
    if ssh $REMOTE "sudo docker ps --format '{{.Names}}' | grep -q '^app$'"; then
        echo "Discourse is already running. Use 'sudo ./launcher rebuild app' to update."
    else
        echo "Bootstrapping Discourse (this takes several minutes)..."
        ssh $REMOTE "cd ~/apps/discourse && sudo ./launcher bootstrap app && sudo ./launcher start app"
    fi

    echo "Discourse deployment complete."
}

deploy_calendar_sync() {
    echo "Deploying calendar-sync..."
    local SYNC_DIR="$REPO_ROOT/openproject/openproject-calendar-sync"
    local REMOTE_DIR="~/apps/calendar-sync"

    # Sync files (exclude node_modules, will npm install on remote)
    ssh $REMOTE "mkdir -p $REMOTE_DIR"
    rsync -avz --exclude 'node_modules' "$SYNC_DIR/" $REMOTE:$REMOTE_DIR/

    # Copy secrets if they exist locally
    if [ -f "$SYNC_DIR/secrets.yaml" ]; then
        echo "Copying encrypted secrets.yaml..."
        scp "$SYNC_DIR/secrets.yaml" $REMOTE:$REMOTE_DIR/secrets.yaml
    else
        echo "WARNING: No secrets.yaml found. You'll need to create it on the VPS:"
        echo "  ssh $REMOTE"
        echo "  cd $REMOTE_DIR"
        echo "  cp secrets.yaml.example secrets.yaml"
        echo "  # Edit with your values, then: sops -e -i secrets.yaml"
    fi

    # Install npm dependencies
    echo "Installing npm dependencies..."
    ssh $REMOTE "cd $REMOTE_DIR && npm install"

    # Generate and install systemd service
    echo "Installing systemd service..."
    cat > /tmp/calendar-sync.service << 'EOF'
[Unit]
Description=OpenProject Calendar Sync Webhook Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/apps/calendar-sync
ExecStart=/usr/bin/make run
Restart=always
RestartSec=10
Environment=HOME=/home/ubuntu
Environment=SOPS_AGE_KEY_FILE=/home/ubuntu/.config/sops/age/keys.txt

[Install]
WantedBy=multi-user.target
EOF
    scp /tmp/calendar-sync.service $REMOTE:/tmp/calendar-sync.service
    ssh $REMOTE "sudo mv /tmp/calendar-sync.service /etc/systemd/system/calendar-sync.service"
    ssh $REMOTE "sudo systemctl daemon-reload"
    rm /tmp/calendar-sync.service

    # Check if secrets exist before starting
    if ssh $REMOTE "test -f $REMOTE_DIR/secrets.yaml"; then
        echo "Enabling and starting calendar-sync service..."
        ssh $REMOTE "sudo systemctl enable calendar-sync"
        ssh $REMOTE "sudo systemctl restart calendar-sync"
        echo "Calendar-sync service started. Check status: ssh $REMOTE 'sudo systemctl status calendar-sync'"
    else
        echo "Secrets not configured. Service installed but not started."
        echo "After configuring secrets, run: sudo systemctl enable --now calendar-sync"
    fi
}

deploy_backups() {
    echo "Deploying backup configuration..."

    local BACKUP_SECRETS="$REPO_ROOT/backups/secrets.yaml"

    if [ ! -f "$BACKUP_SECRETS" ]; then
        echo "WARNING: No backups/secrets.yaml found. Skipping backup setup."
        echo "To enable backups:"
        echo "  cd backups"
        echo "  cp secrets.yaml.example secrets.yaml"
        echo "  # Edit with OCI credentials"
        echo "  sops -e -i secrets.yaml"
        return 0
    fi

    # Decrypt and extract values
    echo "Extracting OCI credentials..."
    local NAMESPACE=$(sops -d "$BACKUP_SECRETS" | yq -r '.oci_namespace')
    local REGION=$(sops -d "$BACKUP_SECRETS" | yq -r '.oci_region')
    local BUCKET=$(sops -d "$BACKUP_SECRETS" | yq -r '.bucket_name')
    local OCI_USER=$(sops -d "$BACKUP_SECRETS" | yq -r '.oci_user')
    local OCI_TENANCY=$(sops -d "$BACKUP_SECRETS" | yq -r '.oci_tenancy')
    local OCI_FINGERPRINT=$(sops -d "$BACKUP_SECRETS" | yq -r '.oci_fingerprint')
    local OCI_KEY_BASE64=$(sops -d "$BACKUP_SECRETS" | yq -r '.oci_api_key_base64')

    if [ -z "$NAMESPACE" ] || [ "$NAMESPACE" = "null" ]; then
        echo "ERROR: Invalid backup secrets. Check backups/secrets.yaml"
        return 1
    fi

    # Deploy OCI config and key
    echo "Deploying OCI configuration..."
    ssh $REMOTE "mkdir -p ~/.oci && chmod 700 ~/.oci"

    # Generate OCI config
    cat > /tmp/oci_config << EOF
[DEFAULT]
user=$OCI_USER
fingerprint=$OCI_FINGERPRINT
tenancy=$OCI_TENANCY
region=$REGION
key_file=/home/ubuntu/.oci/oci_api_key.pem
EOF
    scp /tmp/oci_config $REMOTE:~/.oci/config
    ssh $REMOTE "chmod 600 ~/.oci/config"
    rm /tmp/oci_config

    # Deploy OCI API key
    echo "$OCI_KEY_BASE64" | base64 -d > /tmp/oci_api_key.pem
    scp /tmp/oci_api_key.pem $REMOTE:~/.oci/oci_api_key.pem
    ssh $REMOTE "chmod 600 ~/.oci/oci_api_key.pem"
    rm /tmp/oci_api_key.pem

    # Generate rclone config using native OCI backend
    echo "Generating rclone configuration (native OCI backend)..."
    cat > /tmp/rclone.conf << EOF
[oci-archive]
type = oracleobjectstorage
namespace = $NAMESPACE
compartment = $OCI_TENANCY
region = $REGION
provider = user_principal_auth
config_file = /home/ubuntu/.oci/config
config_profile = DEFAULT
EOF

    # Deploy rclone config
    ssh $REMOTE "mkdir -p ~/.config/rclone"
    scp /tmp/rclone.conf $REMOTE:~/.config/rclone/rclone.conf
    ssh $REMOTE "chmod 600 ~/.config/rclone/rclone.conf"
    rm /tmp/rclone.conf

    # Deploy backup scripts
    echo "Deploying backup scripts..."
    ssh $REMOTE "sudo mkdir -p /opt/scripts"
    scp "$REPO_ROOT/scripts/backup.sh" $REMOTE:/tmp/backup.sh
    scp "$REPO_ROOT/scripts/restore.sh" $REMOTE:/tmp/restore.sh
    ssh $REMOTE "sudo mv /tmp/backup.sh /tmp/restore.sh /opt/scripts/"
    ssh $REMOTE "sudo chmod +x /opt/scripts/backup.sh /opt/scripts/restore.sh"
    ssh $REMOTE "sudo chown ubuntu:ubuntu /opt/scripts/*.sh"

    # Test rclone connection
    echo "Testing rclone connection..."
    if ssh $REMOTE "rclone lsd oci-archive: 2>/dev/null"; then
        echo "rclone connection successful!"
    else
        echo "Connection test failed - bucket may not exist yet or permission issue"
    fi

    # Verify backup cron exists
    if ssh $REMOTE "grep -q backup.sh /etc/cron.d/backup 2>/dev/null"; then
        echo "Backup cron job already configured"
    else
        echo "Setting up backup cron job..."
        ssh $REMOTE "echo '0 4 * * * ubuntu /opt/scripts/backup.sh all >> /var/log/backup.log 2>&1' | sudo tee /etc/cron.d/backup > /dev/null"
    fi

    echo "Backup configuration complete!"
    echo "  - OCI config: ~/.oci/config"
    echo "  - rclone config: ~/.config/rclone/rclone.conf"
    echo "  - Scripts: /opt/scripts/backup.sh, /opt/scripts/restore.sh"
    echo "  - Cron: Daily at 4 AM"
    echo ""
    echo "Test with: ssh $REMOTE 'rclone lsd oci-archive:'"
}

auto_restore() {
    echo "Checking if restore from backup is needed..."

    # Check if rclone is configured
    if ! ssh $REMOTE "test -f ~/.config/rclone/rclone.conf"; then
        echo "rclone not configured, skipping auto-restore"
        return 0
    fi

    # Check if backups exist
    local has_backups=$(ssh $REMOTE "rclone ls oci-archive:xdeca-backups/openproject/ 2>/dev/null | head -1")
    if [ -z "$has_backups" ]; then
        echo "No backups found, skipping auto-restore"
        return 0
    fi

    # Check OpenProject - if fresh install, users table has only 1 row (admin)
    echo "Checking OpenProject database..."
    local op_user_count=$(ssh $REMOTE "podman exec -u postgres openproject_openproject_1 psql -t -c 'SELECT COUNT(*) FROM users;' openproject 2>/dev/null | tr -d ' '" || echo "0")

    if [ "$op_user_count" = "1" ] || [ "$op_user_count" = "0" ]; then
        echo "OpenProject appears fresh (user count: $op_user_count), restoring from backup..."
        restore_openproject
    else
        echo "OpenProject has data (user count: $op_user_count), skipping restore"
    fi

    # Check Twenty - if fresh install, workspace table is empty
    echo "Checking Twenty database..."
    local twenty_workspace_count=$(ssh $REMOTE "podman exec twenty_db_1 psql -U twenty -t -c 'SELECT COUNT(*) FROM core.workspace;' twenty 2>/dev/null | tr -d ' '" || echo "error")

    if [ "$twenty_workspace_count" = "0" ]; then
        echo "Twenty appears fresh (no workspaces), restoring from backup..."
        restore_twenty
    elif [ "$twenty_workspace_count" = "error" ]; then
        echo "Twenty not running or table doesn't exist, skipping restore"
    else
        echo "Twenty has data (workspace count: $twenty_workspace_count), skipping restore"
    fi

    # Check Discourse - if fresh install, only has system user and welcome topic
    echo "Checking Discourse..."
    local discourse_topic_count=$(ssh $REMOTE "cd ~/apps/discourse && sudo ./launcher enter app bash -c 'rails r \"puts Topic.count\"' 2>/dev/null" || echo "error")

    if [ "$discourse_topic_count" = "2" ] || [ "$discourse_topic_count" = "1" ] || [ "$discourse_topic_count" = "0" ]; then
        echo "Discourse appears fresh (topic count: $discourse_topic_count), restoring from backup..."
        restore_discourse
    elif [ "$discourse_topic_count" = "error" ]; then
        echo "Discourse not running or not installed, skipping restore"
    else
        echo "Discourse has data (topic count: $discourse_topic_count), skipping restore"
    fi
}

restore_openproject() {
    echo "Restoring OpenProject from latest backup..."

    # Find latest backup
    local latest=$(ssh $REMOTE "rclone ls oci-archive:xdeca-backups/openproject/ 2>/dev/null | sort -k2 | tail -1 | awk '{print \$2}'")
    if [ -z "$latest" ]; then
        echo "No OpenProject backup found"
        return 1
    fi

    echo "Downloading: $latest"
    ssh $REMOTE "rclone copy oci-archive:xdeca-backups/openproject/$latest /tmp/"

    echo "Restoring database..."
    ssh $REMOTE "gunzip -c /tmp/$latest | podman exec -i -u postgres openproject_openproject_1 psql openproject"
    ssh $REMOTE "rm /tmp/$latest"

    echo "Restarting OpenProject..."
    ssh $REMOTE "cd ~/apps/openproject && podman-compose restart"

    echo "OpenProject restored!"
}

restore_twenty() {
    echo "Restoring Twenty from latest backup..."

    # Find latest DB backup
    local latest_db=$(ssh $REMOTE "rclone ls oci-archive:xdeca-backups/twenty/ 2>/dev/null | grep 'db' | sort -k2 | tail -1 | awk '{print \$2}'")
    if [ -z "$latest_db" ]; then
        echo "No Twenty backup found"
        return 1
    fi

    echo "Downloading: $latest_db"
    ssh $REMOTE "rclone copy oci-archive:xdeca-backups/twenty/$latest_db /tmp/"

    echo "Restoring database..."
    ssh $REMOTE "gunzip -c /tmp/$latest_db | podman exec -i twenty_db_1 psql -U twenty twenty"
    ssh $REMOTE "rm /tmp/$latest_db"

    # Check for storage backup
    local latest_storage=$(ssh $REMOTE "rclone ls oci-archive:xdeca-backups/twenty/ 2>/dev/null | grep 'storage' | sort -k2 | tail -1 | awk '{print \$2}'")
    if [ -n "$latest_storage" ]; then
        echo "Downloading storage: $latest_storage"
        ssh $REMOTE "rclone copy oci-archive:xdeca-backups/twenty/$latest_storage /tmp/"
        ssh $REMOTE "podman run --rm -v twenty_server_data:/data -v /tmp:/backup alpine sh -c 'rm -rf /data/* && tar xzf /backup/$latest_storage -C /data'"
        ssh $REMOTE "rm /tmp/$latest_storage"
    fi

    echo "Restarting Twenty..."
    ssh $REMOTE "cd ~/apps/twenty && podman-compose restart"

    echo "Twenty restored!"
}

restore_discourse() {
    echo "Restoring Discourse from latest backup..."

    # Find latest backup
    local latest=$(ssh $REMOTE "rclone ls oci-archive:xdeca-backups/discourse/ 2>/dev/null | sort -k2 | tail -1 | awk '{print \$2}'")
    if [ -z "$latest" ]; then
        echo "No Discourse backup found"
        return 1
    fi

    echo "Downloading: $latest"
    local backup_dir="/var/discourse/shared/standalone/backups/default"
    ssh $REMOTE "sudo mkdir -p $backup_dir"
    ssh $REMOTE "rclone copy oci-archive:xdeca-backups/discourse/$latest /tmp/"
    ssh $REMOTE "sudo mv /tmp/$latest $backup_dir/"

    echo "Restoring Discourse (this may take a few minutes)..."
    # Enable restore mode and restore
    ssh $REMOTE "cd ~/apps/discourse && sudo ./launcher enter app bash -c 'discourse enable_restore && discourse restore $latest --location=default'"

    echo "Rebuilding Discourse..."
    ssh $REMOTE "cd ~/apps/discourse && sudo ./launcher rebuild app"

    echo "Discourse restored!"
}

decrypt_secrets

case $SERVICE in
    all)
        deploy_scripts
        deploy_backups
        deploy_service caddy
        deploy_service openproject
        deploy_service twenty
        deploy_discourse
        deploy_calendar_sync
        auto_restore
        ;;
    scripts)
        deploy_scripts
        ;;
    backups)
        deploy_backups
        ;;
    caddy|openproject|twenty)
        deploy_service $SERVICE
        ;;
    discourse)
        deploy_discourse
        ;;
    calendar-sync)
        deploy_calendar_sync
        ;;
    restore)
        restore_openproject
        restore_twenty
        restore_discourse
        echo "Restore complete!"
        ;;
    *)
        echo "Unknown service: $SERVICE"
        echo "Usage: $0 <ip> [all|caddy|openproject|twenty|discourse|calendar-sync|backups|scripts|restore]"
        exit 1
        ;;
esac

echo "Deployment complete!"
