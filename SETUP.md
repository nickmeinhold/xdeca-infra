# Oracle Cloud Free Tier Setup Guide
## OpenProject + Discourse on Podman

This guide sets up self-hosted apps on Oracle's free ARM instance:
- **OpenProject** - Project management
- **Discourse** - Forum/community platform

**Total cost: $0/month**

---

## Step 1: Create Oracle Cloud Account

1. Go to https://www.oracle.com/cloud/free/
2. Sign up (credit card needed for verification, won't be charged)
3. Choose your **home region** (can't change later - pick one close to you)

---

## Step 2: Create ARM Instance

1. Go to **Compute → Instances → Create Instance**
2. Name it something like `apps-server`
3. Click **Edit** in the "Image and shape" section:
   - **Image**: Oracle Linux 9 (comes with Podman pre-installed)
   - **Shape**: Ampere → VM.Standard.A1.Flex
     - OCPUs: **4**
     - Memory: **24 GB**
4. Under **Networking**, ensure "Assign a public IPv4 address" is checked
5. Under **Add SSH keys**, upload your public key or let Oracle generate one (download it!)
6. Click **Create**

> ⚠️ **"Out of capacity" error?** Keep trying at different times. Early morning often works. You can also try different availability domains.

---

## Step 3: Configure Oracle Cloud Firewall

1. Go to **Networking → Virtual Cloud Networks**
2. Click your VCN → **Security Lists** → **Default Security List**
3. Click **Add Ingress Rules** and add:

| Source CIDR | Protocol | Dest Port | Description |
|-------------|----------|-----------|-------------|
| 0.0.0.0/0   | TCP      | 80        | HTTP        |
| 0.0.0.0/0   | TCP      | 443       | HTTPS       |

---

## Step 4: Connect to Your Instance

Find your instance's public IP in the Oracle Console, then:

```bash
ssh opc@<your-instance-ip>
```

(Use `opc` as the username for Oracle Linux)

---

## Step 5: Initial Server Setup

```bash
# Update system
sudo dnf update -y

# Podman is pre-installed on Oracle Linux 9, verify it:
podman --version

# Install podman-compose
sudo dnf install -y python3-pip
pip3 install --user podman-compose

# Add to PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Open firewall ports
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Enable lingering (keeps user containers running after logout)
sudo loginctl enable-linger opc
```

---

## Step 6: Set Up Directory Structure

```bash
mkdir -p ~/apps/{openproject,discourse,caddy}
cd ~/apps
```

---

## Step 7: Set Up OpenProject

```bash
cd ~/apps/openproject

# Generate a secret key
OPENPROJECT_SECRET=$(openssl rand -hex 64)
echo "Save this secret: $OPENPROJECT_SECRET"

cat > docker-compose.yml << 'EOF'
version: "3.8"

services:
  openproject:
    image: openproject/openproject:17
    restart: always
    ports:
      - "8080:80"
    environment:
      - OPENPROJECT_HOST__NAME=openproject.yourdomain.com
      - OPENPROJECT_HTTPS=true
      - OPENPROJECT_DEFAULT__LANGUAGE=en
      - SECRET_KEY_BASE=${OPENPROJECT_SECRET}
    volumes:
      - pgdata:/var/openproject/pgdata
      - assets:/var/openproject/assets

volumes:
  pgdata:
  assets:
EOF

# Create .env file
cat > .env << EOF
OPENPROJECT_SECRET=$OPENPROJECT_SECRET
EOF

# Start OpenProject
podman-compose up -d

# Check logs
podman-compose logs -f
```

**Default login:** admin / admin

---

## Step 8: Set Up Discourse (Podman)

```bash
cd ~/apps/discourse

# Clone the Podman-compatible Discourse repo
git clone https://github.com/Gelbpunkt/discourse_podman.git .

# Copy the standalone sample
cp samples/standalone.yml containers/app.yml

# Edit the config
nano containers/app.yml
```

Edit `app.yml` and update these values:

```yaml
env:
  DISCOURSE_HOSTNAME: 'discourse.yourdomain.com'
  DISCOURSE_DEVELOPER_EMAILS: 'your@email.com'
  DISCOURSE_SMTP_ADDRESS: smtp.your-email-provider.com
  DISCOURSE_SMTP_PORT: 587
  DISCOURSE_SMTP_USER_NAME: your-smtp-username
  DISCOURSE_SMTP_PASSWORD: your-smtp-password
```

Then bootstrap and start:

```bash
# Bootstrap (takes 5-10 minutes)
./launcher bootstrap app

# Start Discourse
./launcher start app
```

> ⚠️ **Discourse requires working SMTP** for email verification. Free options: Mailgun (free tier), Brevo, or Amazon SES.

---

## Step 9: Set Up Caddy Reverse Proxy

Caddy handles HTTPS automatically with Let's Encrypt.

```bash
cd ~/apps/caddy

cat > docker-compose.yml << 'EOF'
version: "3.8"

services:
  caddy:
    image: caddy:2-alpine
    restart: always
    network_mode: host
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config

volumes:
  caddy_data:
  caddy_config:
EOF

cat > Caddyfile << 'EOF'
openproject.yourdomain.com {
    reverse_proxy localhost:8080
}

discourse.yourdomain.com {
    reverse_proxy localhost:8888
}
EOF

podman-compose up -d
```

---

## Step 10: Configure DNS

Point your domains to your Oracle instance's public IP:

| Type | Name | Value |
|------|------|-------|
| A | openproject | <your-instance-ip> |
| A | discourse | <your-instance-ip> |

DNS propagation can take a few minutes to a few hours.

---

## Step 11: Verify Everything Works

Once DNS propagates:

- **OpenProject**: https://openproject.yourdomain.com (admin/admin)
- **Discourse**: https://discourse.yourdomain.com (follow setup wizard)

---

## Useful Commands

```bash
# Check running containers
podman ps

# View logs for a service
cd ~/apps/openproject && podman-compose logs -f

# Restart a service
cd ~/apps/openproject && podman-compose restart

# Stop a service
cd ~/apps/openproject && podman-compose down

# Update images
cd ~/apps/openproject && podman-compose pull && podman-compose up -d

# Check resource usage
podman stats
```

---

## Troubleshooting

### "Out of capacity" when creating instance
- Try at different times (early morning works best)
- Try a different availability domain in your region
- Use the OCI CLI with a retry script

### Can't connect to apps
1. Check Oracle security list rules
2. Check firewall: `sudo firewall-cmd --list-all`
3. Check if containers are running: `podman ps`
4. Check container logs: `podman-compose logs`

### Discourse bootstrap fails
- Ensure you have enough RAM (should be fine with 24GB)
- Check SMTP settings are correct
- Try `./launcher rebuild app`

### SSL certificate issues
- Ensure DNS is pointing to your server
- Check Caddy logs: `cd ~/apps/caddy && podman-compose logs`
- Caddy needs ports 80/443 accessible for ACME challenge

---

## Backups

```bash
# Create a backup script
cat > ~/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=~/backups/$(date +%Y%m%d)
mkdir -p $BACKUP_DIR

# OpenProject
podman exec openproject_openproject_1 pg_dump -U postgres openproject > $BACKUP_DIR/openproject.sql

# Discourse
cd ~/apps/discourse
./launcher enter app
# Inside container: pg_dump -U discourse discourse > /shared/discourse.sql
# Then copy from ~/apps/discourse/shared/standalone/discourse.sql

echo "Backups saved to $BACKUP_DIR"
EOF

chmod +x ~/backup.sh
```

---

## Resource Usage Estimate

| Service | RAM | CPU |
|---------|-----|-----|
| OpenProject | ~2GB | Low |
| Discourse | ~2GB | Low-Medium |
| Caddy | ~50MB | Minimal |
| **Total** | ~4GB | Plenty of headroom |

You have 24GB RAM, so you could add more services if needed!

---

## Optional: Auto-start on Boot

Podman with lingering enabled should auto-restart containers, but you can also use systemd:

```bash
# Generate systemd service files
cd ~/apps/openproject
podman-compose systemd -a create-unit

# Enable the services
systemctl --user enable pod-openproject.service
```

---

## Next Steps

- Set up regular backups (consider rclone to cloud storage)
- Configure email notifications in each app
- Set up monitoring (Uptime Kuma is lightweight and self-hostable)
- Consider adding Authentik or Keycloak for SSO across all apps
