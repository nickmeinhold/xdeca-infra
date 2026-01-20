#!/bin/bash
# Deploy services to any VPS
# Usage: ./scripts/deploy-to.sh <ip> [service]
# Services: all, caddy, openproject, twenty, discourse, scripts

set -e

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
        sops -d "$REPO_ROOT/openproject/secrets.yaml" | yq -r '"OPENPROJECT_HOSTNAME=\(.hostname)\nOPENPROJECT_SECRET_KEY_BASE=\(.secret_key_base)"' > "$REPO_ROOT/openproject/.env"
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
    fi

    echo "Discourse config deployed."
    echo "To bootstrap: ssh $REMOTE 'cd ~/apps/discourse && ./launcher bootstrap app'"
}

decrypt_secrets

case $SERVICE in
    all)
        deploy_scripts
        deploy_service caddy
        deploy_service openproject
        deploy_service twenty
        deploy_discourse
        ;;
    scripts)
        deploy_scripts
        ;;
    caddy|openproject|twenty)
        deploy_service $SERVICE
        ;;
    discourse)
        deploy_discourse
        ;;
    *)
        echo "Unknown service: $SERVICE"
        echo "Usage: $0 <ip> [all|caddy|openproject|twenty|discourse|scripts]"
        exit 1
        ;;
esac

echo "Deployment complete!"
