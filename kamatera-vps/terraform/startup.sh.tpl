#!/bin/bash
# Startup script for xdeca VPS on Kamatera
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install packages
apt-get install -y podman podman-compose git curl htop netcat-openbsd ufw make

# Install Node.js 20 (for calendar-sync webhook server)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install SOPS and age for secrets decryption
curl -LO https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.amd64
mv sops-v3.9.4.linux.amd64 /usr/local/bin/sops
chmod +x /usr/local/bin/sops
curl -LO https://github.com/FiloSottile/age/releases/download/v1.2.0/age-v1.2.0-linux-amd64.tar.gz
tar -xzf age-v1.2.0-linux-amd64.tar.gz
mv age/age age/age-keygen /usr/local/bin/
rm -rf age age-v1.2.0-linux-amd64.tar.gz
apt-get install -y yq

# Allow rootless containers to bind to low ports (for Caddy on 80/443)
echo 'net.ipv4.ip_unprivileged_port_start=80' >> /etc/sysctl.conf
sysctl -p

# Create 2GB swap file
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Create ubuntu user if not exists
id ubuntu &>/dev/null || useradd -m -s /bin/bash -G sudo ubuntu
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu

# Set up SSH key for ubuntu user
mkdir -p /home/ubuntu/.ssh
echo "${ssh_public_key}" > /home/ubuntu/.ssh/authorized_keys
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

# Enable lingering for ubuntu user (keeps containers running)
loginctl enable-linger ubuntu

# Set up directories
mkdir -p /home/ubuntu/apps
chown ubuntu:ubuntu /home/ubuntu/apps
mkdir -p /opt/scripts
chown ubuntu:ubuntu /opt/scripts

# Install rclone for backups
curl https://rclone.org/install.sh | bash

# Set up keep-alive (for consistency with OCI setup, though not needed for Kamatera)
cat > /opt/scripts/keep-alive.sh << 'KEEPALIVE'
#!/bin/bash
echo "$(date): keep-alive ping" >> /var/log/keep-alive.log
KEEPALIVE
chmod +x /opt/scripts/keep-alive.sh
echo "0 */6 * * * root /opt/scripts/keep-alive.sh" > /etc/cron.d/keep-alive

# Set up backup cron (runs daily at 4 AM, requires rclone config)
echo "0 4 * * * ubuntu /opt/scripts/backup.sh all >> /var/log/backup.log 2>&1" > /etc/cron.d/backup

# Open firewall ports
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Create README
cat > /home/ubuntu/README.md << 'README'
# xdeca VPS (Kamatera)

## Services
- OpenProject: https://openproject.${domain}
- Twenty CRM: https://twenty.${domain}
- Discourse: https://discourse.${domain}

## Directory Structure
~/apps/
  caddy/         - Reverse proxy
  openproject/   - Project management
  twenty/        - CRM
  discourse/     - Forum
  calendar-sync/ - OpenProject ↔ Google Calendar sync

## Commands
cd ~/apps/<service>
podman-compose up -d      # Start
podman-compose logs -f    # Logs
podman-compose restart    # Restart

## Backups
Daily at 4 AM to Oracle Object Storage.

Setup (one-time):
  /opt/scripts/setup-backups.sh

Manual backup:
  /opt/scripts/backup.sh all
README
chown ubuntu:ubuntu /home/ubuntu/README.md

echo "Startup script complete at $(date)" >> /var/log/startup-complete.log
