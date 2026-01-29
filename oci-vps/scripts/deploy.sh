#!/bin/bash
# Deploy services to OCI VPS (when provisioned)
# Usage: ./scripts/deploy.sh [service]
# Services: all, caddy, outline, kanbn, scripts

set -e

# Get repo root (one level up from oci-vps)
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OCI_VPS_DIR="$REPO_ROOT/oci-vps"

SERVICE=${1:-all}
REMOTE="ubuntu@$(terraform -chdir="$OCI_VPS_DIR/terraform" output -raw instance_public_ip)"

echo "Deploying to $REMOTE..."

deploy_scripts() {
    echo "Deploying backup scripts..."

    # Copy scripts to /opt/scripts
    ssh "$REMOTE" "sudo mkdir -p /opt/scripts"
    rsync -avz "$REPO_ROOT/scripts/" "$REMOTE":/tmp/scripts/
    ssh "$REMOTE" "sudo mv /tmp/scripts/* /opt/scripts/ && sudo chmod +x /opt/scripts/*.sh"

    echo "Backup scripts deployed to /opt/scripts/"
}

deploy_service() {
    local svc=$1
    echo "Deploying $svc..."

    ssh "$REMOTE" "mkdir -p ~/apps/$svc"
    rsync -avz --delete "$REPO_ROOT/$svc/" "$REMOTE":~/apps/"$svc"/
    ssh "$REMOTE" "cd ~/apps/$svc && docker-compose pull && docker-compose up -d"
}

deploy_outline() {
    echo "Deploying Outline Wiki..."

    local OUTLINE_SECRETS="$REPO_ROOT/outline/secrets.yaml"

    if [ ! -f "$OUTLINE_SECRETS" ]; then
        echo "ERROR: outline/secrets.yaml not found"
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
    ssh "$REMOTE" "cd ~/apps/outline && docker-compose pull && docker-compose up -d"

    echo "Outline deployed!"
}

deploy_kanbn() {
    echo "Deploying Kan.bn..."

    local KANBN_SECRETS="$REPO_ROOT/kanbn/secrets.yaml"

    if [ ! -f "$KANBN_SECRETS" ]; then
        echo "ERROR: kanbn/secrets.yaml not found"
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
    ssh "$REMOTE" "mkdir -p ~/apps/kanbn"
    rsync -avz --delete --exclude 'secrets.yaml' "$REPO_ROOT/kanbn/" "$REMOTE":~/apps/kanbn/

    # Clean up local .env
    rm -f "$REPO_ROOT/kanbn/.env"

    # Build and start Kan.bn
    ssh "$REMOTE" "cd ~/apps/kanbn && DOCKER_BUILDKIT=1 docker-compose build --pull && docker-compose up -d"

    echo "Kan.bn deployed!"
}

case $SERVICE in
    all)
        deploy_scripts
        deploy_service caddy
        deploy_outline
        deploy_kanbn
        ;;
    scripts)
        deploy_scripts
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
        echo "Usage: $0 [all|caddy|outline|kanbn|scripts]"
        exit 1
        ;;
esac

echo "Deployment complete!"
