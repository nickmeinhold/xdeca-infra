#!/bin/bash
# Deploy services to any VPS
# Usage: ./scripts/deploy-to.sh <ip> [service]
# Services: all, caddy, openproject, twenty, calendar-sync, backups, scripts

set -e

# SOPS age key location
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

if [ -z "$1" ]; then
  echo "Usage: $0 <ip> [service]"
  echo "  ip: VPS IP address or hostname"
  echo "  service: all|caddy|openproject|twenty|scripts (default: all)"
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
        sops -d "$REPO_ROOT/twenty/secrets.yaml" | yq -r '"TWENTY_HOSTNAME=\(.hostname)\nPOSTGRES_PASSWORD=\(.postgres_password)\nAPP_SECRET=\(.app_secret)\nACCESS_TOKEN_SECRET=\(.access_token_secret)\nLOGIN_TOKEN_SECRET=\(.login_token_secret)\nREFRESH_TOKEN_SECRET=\(.refresh_token_secret)\nFILE_TOKEN_SECRET=\(.file_token_secret)"' > "$REPO_ROOT/twenty/.env"
    fi
}

deploy_scripts() {
    echo "Deploying backup scripts..."
    ssh $REMOTE "sudo mkdir -p /opt/scripts"
    rsync -avz "$REPO_ROOT/scripts/" $REMOTE:/tmp/scripts/
    ssh $REMOTE "sudo mv /tmp/scripts/* /opt/scripts/ && sudo chmod +x /opt/scripts/*.sh"
    echo "Backup scripts deployed to /opt/scripts/"
}

deploy_service() {
    local svc=$1
    echo "Deploying $svc..."
    ssh $REMOTE "mkdir -p ~/apps/$svc"
    rsync -avz --delete "$REPO_ROOT/$svc/" $REMOTE:~/apps/$svc/
    ssh $REMOTE "cd ~/apps/$svc && docker compose pull && docker compose up -d"
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
        return 0
    fi

    # Decrypt and extract S3 config
    echo "Extracting S3 configuration..."
    local S3_REGION=$(sops -d "$BACKUP_SECRETS" | yq -r '.s3_region')
    local S3_BUCKET=$(sops -d "$BACKUP_SECRETS" | yq -r '.s3_bucket')

    if [ -z "$S3_REGION" ] || [ "$S3_REGION" = "null" ]; then
        echo "ERROR: Invalid backup secrets. Check backups/secrets.yaml"
        return 1
    fi

    # Copy AWS credentials to remote server
    echo "Deploying AWS credentials..."
    ssh $REMOTE "mkdir -p ~/.aws"
    scp ~/.aws/credentials $REMOTE:~/.aws/credentials 2>/dev/null || true
    scp ~/.aws/config $REMOTE:~/.aws/config 2>/dev/null || true
    ssh $REMOTE "chmod 600 ~/.aws/*"

    # Generate rclone config for AWS S3
    echo "Generating rclone configuration (AWS S3)..."
    cat > /tmp/rclone.conf << EOF
[s3]
type = s3
provider = AWS
region = $S3_REGION
env_auth = true
EOF

    # Deploy rclone config
    ssh $REMOTE "mkdir -p ~/.config/rclone"
    scp /tmp/rclone.conf $REMOTE:~/.config/rclone/rclone.conf
    ssh $REMOTE "chmod 600 ~/.config/rclone/rclone.conf"
    rm /tmp/rclone.conf

    # Create S3 bucket if it doesn't exist
    echo "Ensuring S3 bucket exists..."
    ssh $REMOTE "aws s3 mb s3://$S3_BUCKET --region $S3_REGION 2>/dev/null || true"

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
    if ssh $REMOTE "rclone lsd s3: 2>/dev/null"; then
        echo "rclone connection successful!"
    else
        echo "Connection test failed - check AWS credentials"
    fi

    # Verify backup cron exists
    if ssh $REMOTE "grep -q backup.sh /etc/cron.d/backup 2>/dev/null"; then
        echo "Backup cron job already configured"
    else
        echo "Setting up backup cron job..."
        ssh $REMOTE "echo '0 4 * * * ubuntu /opt/scripts/backup.sh all >> /var/log/backup.log 2>&1' | sudo tee /etc/cron.d/backup > /dev/null"
    fi

    echo "Backup configuration complete!"
    echo "  - AWS credentials: ~/.aws/"
    echo "  - rclone config: ~/.config/rclone/rclone.conf"
    echo "  - Scripts: /opt/scripts/backup.sh, /opt/scripts/restore.sh"
    echo "  - Cron: Daily at 4 AM"
    echo ""
    echo "Test with: ssh $REMOTE 'rclone lsd s3:'"
}

auto_restore() {
    echo "Checking if restore from backup is needed..."

    # Check if rclone is configured
    if ! ssh $REMOTE "test -f ~/.config/rclone/rclone.conf"; then
        echo "rclone not configured, skipping auto-restore"
        return 0
    fi

    # Check if backups exist
    local has_backups=$(ssh $REMOTE "rclone ls s3:xdeca-backups/openproject/ 2>/dev/null | head -1")
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

}

restore_openproject() {
    echo "Restoring OpenProject from latest backup..."

    # Find latest backup
    local latest=$(ssh $REMOTE "rclone ls s3:xdeca-backups/openproject/ 2>/dev/null | sort -k2 | tail -1 | awk '{print \$2}'")
    if [ -z "$latest" ]; then
        echo "No OpenProject backup found"
        return 1
    fi

    echo "Downloading: $latest"
    ssh $REMOTE "rclone copy s3:xdeca-backups/openproject/$latest /tmp/"

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
    local latest_db=$(ssh $REMOTE "rclone ls s3:xdeca-backups/twenty/ 2>/dev/null | grep 'db' | sort -k2 | tail -1 | awk '{print \$2}'")
    if [ -z "$latest_db" ]; then
        echo "No Twenty backup found"
        return 1
    fi

    echo "Downloading: $latest_db"
    ssh $REMOTE "rclone copy s3:xdeca-backups/twenty/$latest_db /tmp/"

    echo "Restoring database..."
    ssh $REMOTE "gunzip -c /tmp/$latest_db | podman exec -i twenty_db_1 psql -U twenty twenty"
    ssh $REMOTE "rm /tmp/$latest_db"

    # Check for storage backup
    local latest_storage=$(ssh $REMOTE "rclone ls s3:xdeca-backups/twenty/ 2>/dev/null | grep 'storage' | sort -k2 | tail -1 | awk '{print \$2}'")
    if [ -n "$latest_storage" ]; then
        echo "Downloading storage: $latest_storage"
        ssh $REMOTE "rclone copy s3:xdeca-backups/twenty/$latest_storage /tmp/"
        ssh $REMOTE "podman run --rm -v twenty_server_data:/data -v /tmp:/backup alpine sh -c 'rm -rf /data/* && tar xzf /backup/$latest_storage -C /data'"
        ssh $REMOTE "rm /tmp/$latest_storage"
    fi

    echo "Restarting Twenty..."
    ssh $REMOTE "cd ~/apps/twenty && podman-compose restart"

    echo "Twenty restored!"
}

decrypt_secrets

case $SERVICE in
    all)
        deploy_scripts
        deploy_backups
        deploy_service caddy
        deploy_service openproject
        deploy_service twenty
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
    calendar-sync)
        deploy_calendar_sync
        ;;
    restore)
        restore_openproject
        restore_twenty
        echo "Restore complete!"
        ;;
    *)
        echo "Unknown service: $SERVICE"
        echo "Usage: $0 <ip> [all|caddy|openproject|twenty|calendar-sync|backups|scripts|restore]"
        exit 1
        ;;
esac

echo "Deployment complete!"
