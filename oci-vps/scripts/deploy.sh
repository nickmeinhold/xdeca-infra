#!/bin/bash
# Deploy services to xdeca VPS
# Usage: ./scripts/deploy.sh [service]
# Services: all, caddy, openproject, discourse, scripts

set -e

# Get repo root (one level up from oci-vps)
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OCI_VPS_DIR="$REPO_ROOT/oci-vps"

SERVICE=${1:-all}
REMOTE="ubuntu@$(terraform -chdir="$OCI_VPS_DIR/terraform" output -raw instance_public_ip)"

echo "Deploying to $REMOTE..."

# Decrypt secrets and generate .env files
decrypt_secrets() {
    echo "Decrypting secrets..."

    if [ -f "$REPO_ROOT/openproject/secrets.yaml" ]; then
        sops -d "$REPO_ROOT/openproject/secrets.yaml" | yq -r '"OPENPROJECT_HOSTNAME=\(.hostname)\nOPENPROJECT_SECRET_KEY_BASE=\(.secret_key_base)"' > "$REPO_ROOT/openproject/.env"
    fi
}

deploy_scripts() {
    echo "Deploying backup scripts..."

    # Copy scripts to /opt/scripts
    rsync -avz "$REPO_ROOT/scripts/" $REMOTE:/opt/scripts/
    ssh $REMOTE "chmod +x /opt/scripts/*.sh"

    echo "Backup scripts deployed to /opt/scripts/"
    echo "Run '/opt/scripts/setup-backups.sh' to configure rclone credentials"
}

deploy_service() {
    local svc=$1
    echo "Deploying $svc..."

    rsync -avz --delete "$REPO_ROOT/$svc/" $REMOTE:~/apps/$svc/
    ssh $REMOTE "cd ~/apps/$svc && podman-compose pull && podman-compose up -d"
}

deploy_discourse() {
    echo "Deploying Discourse..."

    # Discourse uses its own launcher, not podman-compose
    # First time: clone discourse_docker repo on server
    ssh $REMOTE "test -d ~/apps/discourse || git clone https://github.com/discourse/discourse_docker.git ~/apps/discourse"

    # Copy app.yml config
    if [ -f "$REPO_ROOT/discourse/secrets.yaml" ]; then
        # Generate app.yml from template and secrets
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
    fi

    echo "Discourse config deployed. To bootstrap (first time only):"
    echo "  ssh $REMOTE 'cd ~/apps/discourse && ./launcher bootstrap app'"
    echo "To start/restart:"
    echo "  ssh $REMOTE 'cd ~/apps/discourse && ./launcher start app'"
}

decrypt_secrets

case $SERVICE in
    all)
        deploy_scripts
        deploy_service caddy
        deploy_service openproject
        deploy_discourse
        ;;
    scripts)
        deploy_scripts
        ;;
    caddy|openproject)
        deploy_service $SERVICE
        ;;
    discourse)
        deploy_discourse
        ;;
    *)
        echo "Unknown service: $SERVICE"
        echo "Usage: $0 [all|caddy|openproject|discourse|scripts]"
        exit 1
        ;;
esac

echo "Deployment complete!"
