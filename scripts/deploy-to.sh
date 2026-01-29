#!/bin/bash
# Deploy services to any VPS
# Usage: ./scripts/deploy-to.sh <ip> [service]
# Services: all, caddy, outline, kanbn, backups, scripts

set -e

# SOPS age key location
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

if [ -z "$1" ]; then
  echo "Usage: $0 <ip> [service]"
  echo "  ip: VPS IP address or hostname"
  echo "  service: all|caddy|outline|kanbn|backups|scripts (default: all)"
  exit 1
fi

IP=$1
SERVICE=${2:-all}
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE="ubuntu@$IP"

echo "Deploying to $REMOTE..."

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
    ssh $REMOTE "cd ~/apps/$svc && docker-compose pull && docker-compose up -d"
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

deploy_outline() {
    echo "Deploying Outline Wiki..."

    local OUTLINE_SECRETS="$REPO_ROOT/outline/secrets.yaml"

    # Check for secrets file
    if [ ! -f "$OUTLINE_SECRETS" ]; then
        echo "ERROR: outline/secrets.yaml not found"
        echo "Create it and encrypt with: sops -e -i outline/secrets.yaml"
        return 1
    fi

    # Generate .env from encrypted secrets
    echo "Generating .env from encrypted secrets..."
    sops -d "$OUTLINE_SECRETS" | yq -r '"# Outline Configuration (auto-generated from secrets.yaml)
OUTLINE_URL=\(.outline_url)

# Generated secrets
SECRET_KEY=\(.secret_key)
UTILS_SECRET=\(.utils_secret)

# Postgres
POSTGRES_PASSWORD=\(.postgres_password)

# MinIO (S3-compatible storage)
MINIO_ROOT_USER=\(.minio_root_user)
MINIO_ROOT_PASSWORD=\(.minio_root_password)
MINIO_URL=\(.minio_url)

# SMTP
SMTP_HOST=\(.smtp_host)
SMTP_PORT=\(.smtp_port)
SMTP_USERNAME=\(.smtp_username)
SMTP_PASSWORD=\(.smtp_password)
SMTP_FROM_EMAIL=\(.smtp_from_email)
SMTP_SECURE=\(.smtp_secure)"' > "$REPO_ROOT/outline/.env"

    # Deploy files
    ssh $REMOTE "mkdir -p ~/apps/outline"
    rsync -avz --delete --exclude 'secrets.yaml' "$REPO_ROOT/outline/" $REMOTE:~/apps/outline/

    # Clean up local .env
    rm -f "$REPO_ROOT/outline/.env"

    # Start Outline
    ssh $REMOTE "cd ~/apps/outline && docker-compose pull && docker-compose up -d"

    echo "Outline deployed!"
    echo "  URL: https://wiki.xdeca.com"
    echo "  Note: First user to sign in becomes admin"
}

deploy_kanbn() {
    echo "Deploying Kan.bn..."

    local KANBN_SECRETS="$REPO_ROOT/kanbn/secrets.yaml"

    # Check for secrets file
    if [ ! -f "$KANBN_SECRETS" ]; then
        echo "ERROR: kanbn/secrets.yaml not found"
        echo "Create it and encrypt with: sops -e -i kanbn/secrets.yaml"
        return 1
    fi

    # Generate .env from encrypted secrets
    echo "Generating .env from encrypted secrets..."
    sops -d "$KANBN_SECRETS" | yq -r '"# Kan.bn Configuration (auto-generated from secrets.yaml)
KANBN_URL=\(.kanbn_url)
AUTH_SECRET=\(.auth_secret)
POSTGRES_PASSWORD=\(.postgres_password)
SMTP_HOST=\(.smtp_host)
SMTP_PORT=\(.smtp_port)
SMTP_USERNAME=\(.smtp_username)
SMTP_PASSWORD=\(.smtp_password)
SMTP_FROM_EMAIL=\(.smtp_from_email)
TRELLO_API_KEY=\(.trello_api_key)
TRELLO_API_SECRET=\(.trello_api_secret)
S3_ENDPOINT=\(.s3_endpoint)
S3_ACCESS_KEY_ID=\(.s3_access_key_id)
S3_SECRET_ACCESS_KEY=\(.s3_secret_access_key)
NEXT_PUBLIC_STORAGE_URL=\(.next_public_storage_url)
WEBHOOK_URL=\(.webhook_url)
WEBHOOK_SECRET=\(.webhook_secret)"' > "$REPO_ROOT/kanbn/.env"

    # Deploy files
    ssh $REMOTE "mkdir -p ~/apps/kanbn"
    rsync -avz --delete --exclude 'secrets.yaml' "$REPO_ROOT/kanbn/" $REMOTE:~/apps/kanbn/

    # Clean up local .env
    rm -f "$REPO_ROOT/kanbn/.env"

    # Build and start Kan.bn (builds from 10xdeca/kan fork)
    ssh $REMOTE "cd ~/apps/kanbn && DOCKER_BUILDKIT=1 docker-compose build --pull && docker-compose up -d"

    echo "Kan.bn deployed!"
    echo "  URL: https://tasks.xdeca.com"
    echo "  Note: First user to sign up becomes admin"
}

case $SERVICE in
    all)
        deploy_scripts
        deploy_backups
        deploy_service caddy
        deploy_outline
        deploy_kanbn
        ;;
    scripts)
        deploy_scripts
        ;;
    backups)
        deploy_backups
        ;;
    caddy)
        deploy_service caddy
        ;;
    outline|wiki)
        deploy_outline
        ;;
    kanbn|tasks)
        deploy_kanbn
        ;;
    *)
        echo "Unknown service: $SERVICE"
        echo "Usage: $0 <ip> [all|caddy|outline|kanbn|backups|scripts]"
        exit 1
        ;;
esac

echo "Deployment complete!"
