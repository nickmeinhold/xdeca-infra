#!/bin/bash
# Set up backup infrastructure on VPS
# Run this once after provisioning

set -e

echo "=== xdeca Backup Setup ==="
echo ""

# Install rclone if not present
if ! command -v rclone &> /dev/null; then
  echo "Installing rclone..."
  curl https://rclone.org/install.sh | sudo bash
fi

# Check for OCI CLI
if ! command -v oci &> /dev/null; then
  echo "ERROR: OCI CLI not installed. Install it first:"
  echo "  https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
  exit 1
fi

echo ""
echo "=== Create Customer Secret Key for S3 API ==="
echo ""
echo "1. Go to OCI Console → Identity → Users → Your User"
echo "2. Resources → Customer Secret Keys → Generate Secret Key"
echo "3. Name it 'rclone-backups'"
echo "4. COPY THE SECRET KEY NOW (it won't be shown again)"
echo ""
read -p "Press Enter when you have the Access Key and Secret Key..."

echo ""
read -p "Enter Access Key: " ACCESS_KEY
read -sp "Enter Secret Key: " SECRET_KEY
echo ""

# Get namespace
NAMESPACE=$(oci os ns get --query 'data' --raw-output)
echo "OCI Namespace: $NAMESPACE"

# Configure rclone
echo ""
echo "Configuring rclone..."

mkdir -p ~/.config/rclone

cat > ~/.config/rclone/rclone.conf << EOF
[oci-archive]
type = s3
provider = Other
access_key_id = $ACCESS_KEY
secret_access_key = $SECRET_KEY
endpoint = https://$NAMESPACE.compat.objectstorage.ap-melbourne-1.oraclecloud.com
acl = private
EOF

echo "rclone configured!"

# Create bucket (Archive tier for cost savings)
echo ""
echo "Creating backup bucket..."

BUCKET_NAME="xdeca-backups"

oci os bucket create \
  --compartment-id "$(oci iam compartment list --query 'data[0].id' --raw-output)" \
  --name "$BUCKET_NAME" \
  --storage-tier Archive \
  2>/dev/null || echo "Bucket may already exist, continuing..."

echo "Bucket ready: $BUCKET_NAME"

# Test rclone connection
echo ""
echo "Testing rclone connection..."
rclone lsd oci-archive: && echo "Connection successful!" || echo "Connection failed - check credentials"

# Set up backup script
echo ""
echo "Setting up backup script..."

sudo mkdir -p /opt/scripts
sudo cp "$(dirname "$0")/backup.sh" /opt/scripts/backup.sh
sudo chmod +x /opt/scripts/backup.sh

# Set up cron job (runs at 4 AM daily)
echo ""
echo "Setting up daily backup cron job (4 AM)..."

CRON_LINE="0 4 * * * /opt/scripts/backup.sh all >> /var/log/backup.log 2>&1"
(crontab -l 2>/dev/null | grep -v "backup.sh"; echo "$CRON_LINE") | crontab -

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Backups will run daily at 4 AM"
echo "Retention: 7 days"
echo ""
echo "Manual commands:"
echo "  sudo /opt/scripts/backup.sh all       # Run all backups"
echo "  sudo /opt/scripts/backup.sh openproject  # Backup OpenProject only"
echo "  rclone ls oci-archive:xdeca-backups   # List remote backups"
echo "  tail -f /var/log/backup.log           # Watch backup logs"
