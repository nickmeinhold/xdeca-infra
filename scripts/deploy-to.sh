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
    echo "Deploying scripts..."
    ssh "$REMOTE" "sudo mkdir -p /opt/scripts"
    rsync -avz "$REPO_ROOT/scripts/" "$REMOTE":/tmp/scripts/
    ssh "$REMOTE" "sudo mv /tmp/scripts/* /opt/scripts/ && sudo chmod +x /opt/scripts/*.sh"

    # Set up health check cron
    local PM_BOT_SECRETS="$REPO_ROOT/xdeca-pm-bot/secrets.yaml"
    if [ -f "$PM_BOT_SECRETS" ]; then
        echo "Setting up health check cron..."
        local BOT_TOKEN
        BOT_TOKEN=$(sops -d "$PM_BOT_SECRETS" | yq -r '.telegram_bot_token')
        ssh "$REMOTE" "echo '0 * * * * ubuntu TELEGRAM_BOT_TOKEN=$BOT_TOKEN TELEGRAM_CHAT_ID=-1003454984262 TELEGRAM_THREAD_ID=1953 /opt/scripts/health-check.sh >> /var/log/health-check.log 2>&1' | sudo tee /etc/cron.d/health-check > /dev/null"
        echo "Health check cron installed (hourly)"
    else
        echo "WARNING: xdeca-pm-bot/secrets.yaml not found, skipping health check cron"
    fi

    echo "Scripts deployed to /opt/scripts/"
}

deploy_service() {
    local svc=$1
    echo "Deploying $svc..."
    ssh "$REMOTE" "mkdir -p ~/apps/$svc"
    rsync -avz --delete "$REPO_ROOT/$svc/" "$REMOTE":~/apps/"$svc"/
    ssh "$REMOTE" "cd ~/apps/$svc && docker compose pull && docker compose up -d"
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
    local S3_REGION
    local S3_BUCKET
    S3_REGION=$(sops -d "$BACKUP_SECRETS" | yq -r '.s3_region')
    S3_BUCKET=$(sops -d "$BACKUP_SECRETS" | yq -r '.s3_bucket')

    if [ -z "$S3_REGION" ] || [ "$S3_REGION" = "null" ]; then
        echo "ERROR: Invalid backup secrets. Check backups/secrets.yaml"
        return 1
    fi

    # Copy AWS credentials to remote server
    echo "Deploying AWS credentials..."
    ssh "$REMOTE" "mkdir -p ~/.aws"
    scp ~/.aws/credentials "$REMOTE":~/.aws/credentials 2>/dev/null || true
    scp ~/.aws/config "$REMOTE":~/.aws/config 2>/dev/null || true
    ssh "$REMOTE" "chmod 600 ~/.aws/*"

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
    ssh "$REMOTE" "mkdir -p ~/.config/rclone"
    scp /tmp/rclone.conf "$REMOTE":~/.config/rclone/rclone.conf
    ssh "$REMOTE" "chmod 600 ~/.config/rclone/rclone.conf"
    rm /tmp/rclone.conf

    # Create S3 bucket if it doesn't exist
    echo "Ensuring S3 bucket exists..."
    ssh "$REMOTE" "aws s3 mb s3://$S3_BUCKET --region $S3_REGION 2>/dev/null || true"

    # Deploy backup scripts
    echo "Deploying backup scripts..."
    ssh "$REMOTE" "sudo mkdir -p /opt/scripts"
    scp "$REPO_ROOT/scripts/backup.sh" "$REMOTE":/tmp/backup.sh
    scp "$REPO_ROOT/scripts/restore.sh" "$REMOTE":/tmp/restore.sh
    ssh "$REMOTE" "sudo mv /tmp/backup.sh /tmp/restore.sh /opt/scripts/"
    ssh "$REMOTE" "sudo chmod +x /opt/scripts/backup.sh /opt/scripts/restore.sh"
    ssh "$REMOTE" "sudo chown ubuntu:ubuntu /opt/scripts/*.sh"

    # Test rclone connection
    echo "Testing rclone connection..."
    if ssh "$REMOTE" "rclone lsd s3: 2>/dev/null"; then
        echo "rclone connection successful!"
    else
        echo "Connection test failed - check AWS credentials"
    fi

    # Verify backup cron exists
    if ssh "$REMOTE" "grep -q backup.sh /etc/cron.d/backup 2>/dev/null"; then
        echo "Backup cron job already configured"
    else
        echo "Setting up backup cron job..."
        ssh "$REMOTE" "echo '0 4 * * * ubuntu /opt/scripts/backup.sh all >> /var/log/backup.log 2>&1' | sudo tee /etc/cron.d/backup > /dev/null"
    fi

    # --- GitHub backup setup ---
    echo ""
    echo "Setting up GitHub backup..."

    # Generate SSH deploy key if not present
    if ! ssh "$REMOTE" "test -f ~/.ssh/xdeca-backups-deploy"; then
        echo "Generating SSH deploy key for xdeca-backups..."
        ssh "$REMOTE" 'ssh-keygen -t ed25519 -f ~/.ssh/xdeca-backups-deploy -N "" -C "xdeca-backups-deploy"'
    fi

    # Configure SSH to use deploy key for the backup repo
    ssh "$REMOTE" 'mkdir -p ~/.ssh/config.d && cat > ~/.ssh/config.d/xdeca-backups << '\''SSHEOF'\''
Host github-backups
    HostName github.com
    User git
    IdentityFile ~/.ssh/xdeca-backups-deploy
    IdentitiesOnly yes
SSHEOF'
    # Ensure main SSH config includes config.d
    ssh "$REMOTE" 'grep -q "Include config.d/\*" ~/.ssh/config 2>/dev/null || printf "Include config.d/*\n\n" | cat - ~/.ssh/config 2>/dev/null > /tmp/ssh_config_tmp && mv /tmp/ssh_config_tmp ~/.ssh/config || printf "Include config.d/*\n" > ~/.ssh/config'
    ssh "$REMOTE" "chmod 600 ~/.ssh/config ~/.ssh/config.d/xdeca-backups"

    # Ensure GitHub host key is trusted
    ssh "$REMOTE" 'ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null'

    # Print deploy key for operator
    echo ""
    echo "============================================"
    echo "  GitHub Deploy Key (add to 10xdeca/xdeca-backups with WRITE access)"
    echo "============================================"
    ssh "$REMOTE" "cat ~/.ssh/xdeca-backups-deploy.pub"
    echo "============================================"
    echo ""

    echo "Backup configuration complete!"
    echo "  - AWS credentials: ~/.aws/"
    echo "  - rclone config: ~/.config/rclone/rclone.conf"
    echo "  - GitHub backup: 10xdeca/xdeca-backups (private repo)"
    echo "  - Deploy key: ~/.ssh/xdeca-backups-deploy"
    echo "  - Scripts: /opt/scripts/backup.sh, /opt/scripts/restore.sh"
    echo "  - Cron: Daily at 4 AM"
    echo ""
    echo "Test with: ssh $REMOTE '/opt/scripts/backup.sh all'"
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
    ssh "$REMOTE" "mkdir -p ~/apps/outline"
    rsync -avz --delete --exclude 'secrets.yaml' "$REPO_ROOT/outline/" "$REMOTE":~/apps/outline/

    # Clean up local .env
    rm -f "$REPO_ROOT/outline/.env"

    # Start Outline
    ssh "$REMOTE" "cd ~/apps/outline && docker compose pull && docker compose up -d"

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

    local KAN_SRC="$REPO_ROOT/../kan"

    # Check for source code
    if [ ! -d "$KAN_SRC" ]; then
        echo "ERROR: kan source not found at $KAN_SRC"
        echo "Clone it with: git clone git@github.com:10xdeca/kan.git $KAN_SRC"
        return 1
    fi

    # Deploy files
    ssh "$REMOTE" "mkdir -p ~/apps/kanbn/kan-source"
    rsync -avz --delete --exclude 'secrets.yaml' "$REPO_ROOT/kanbn/" "$REMOTE":~/apps/kanbn/ --exclude 'kan-source'

    # Copy kan source code
    rsync -avz --delete --exclude 'node_modules' --exclude '.next' --exclude 'dist' --exclude '.env' --exclude '.git' "$KAN_SRC/" "$REMOTE":~/apps/kanbn/kan-source/

    # Clean up local .env
    rm -f "$REPO_ROOT/kanbn/.env"

    # Build and start Kan.bn (builds from local source)
    ssh "$REMOTE" "cd ~/apps/kanbn && DOCKER_BUILDKIT=1 docker compose build --pull && docker compose up -d"

    echo "Kan.bn deployed!"
    echo "  URL: https://tasks.xdeca.com"
    echo "  Note: First user to sign up becomes admin"
}

deploy_pm_bot() {
    echo "Deploying xdeca-pm-bot (Telegram)..."

    local PM_BOT_SECRETS="$REPO_ROOT/xdeca-pm-bot/secrets.yaml"
    local PM_BOT_SRC="$REPO_ROOT/../telegram-bots/xdeca-pm-bot"

    # Check for secrets file
    if [ ! -f "$PM_BOT_SECRETS" ]; then
        echo "ERROR: xdeca-pm-bot/secrets.yaml not found"
        echo "Create it from secrets.yaml.example and encrypt with: sops -e -i xdeca-pm-bot/secrets.yaml"
        return 1
    fi

    # Check for source code
    if [ ! -d "$PM_BOT_SRC" ]; then
        echo "ERROR: xdeca-pm-bot source not found at $PM_BOT_SRC"
        return 1
    fi

    # Generate .env from encrypted secrets
    echo "Generating .env from encrypted secrets..."
    sops -d "$PM_BOT_SECRETS" | yq -r '"# xdeca-pm-bot Configuration (auto-generated from secrets.yaml)
TELEGRAM_BOT_TOKEN=\(.telegram_bot_token)
KAN_SERVICE_API_KEY=\(.kan_service_api_key)
ANTHROPIC_API_KEY=\(.anthropic_api_key)
KAN_BASE_URL=\(.kan_base_url)
SPRINT_START_DATE=\(.sprint_start_date)
REMINDER_INTERVAL_HOURS=\(.reminder_interval_hours)
ADMIN_USER_IDS=\(.admin_user_ids)"' > "$REPO_ROOT/xdeca-pm-bot/.env"

    # Deploy files
    ssh "$REMOTE" "mkdir -p ~/apps/xdeca-pm-bot/src"

    # Copy docker compose and .env
    rsync -avz --exclude 'secrets.yaml' "$REPO_ROOT/xdeca-pm-bot/" "$REMOTE":~/apps/xdeca-pm-bot/

    # Copy source code
    rsync -avz --exclude 'node_modules' --exclude 'dist' --exclude '.env' --exclude 'data' "$PM_BOT_SRC/" "$REMOTE":~/apps/xdeca-pm-bot/src/

    # Clean up local .env
    rm -f "$REPO_ROOT/xdeca-pm-bot/.env"

    # Build and start
    ssh "$REMOTE" "cd ~/apps/xdeca-pm-bot && DOCKER_BUILDKIT=1 docker compose build --pull && docker compose up -d"

    echo "xdeca-pm-bot deployed!"
    echo "  Check logs: ssh $REMOTE 'docker logs -f xdeca-pm-bot'"
}

case $SERVICE in
    all)
        deploy_scripts
        deploy_backups
        deploy_service caddy
        deploy_outline
        deploy_kanbn
        deploy_pm_bot
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
    xdeca-pm-bot|pm-bot|telegram)
        deploy_pm_bot
        ;;
    *)
        echo "Unknown service: $SERVICE"
        echo "Usage: $0 <ip> [all|caddy|outline|kanbn|xdeca-pm-bot|backups|scripts]"
        exit 1
        ;;
esac

echo "Deployment complete!"
