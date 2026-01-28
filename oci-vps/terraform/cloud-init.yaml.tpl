#cloud-config

package_update: true
package_upgrade: true

packages:
  - podman
  - podman-compose
  - git
  - curl
  - htop
  - netcat-openbsd

runcmd:
  # Enable lingering for ubuntu user (keeps containers running)
  - loginctl enable-linger ubuntu

  # Set up apps directory
  - mkdir -p /home/ubuntu/apps
  - chown ubuntu:ubuntu /home/ubuntu/apps

  # Set up scripts directory
  - mkdir -p /opt/scripts
  - chown ubuntu:ubuntu /opt/scripts

  # Install rclone for backups
  - curl https://rclone.org/install.sh | bash

  # Set up keep-alive to prevent idle reclamation
  - |
    cat > /opt/scripts/keep-alive.sh << 'KEEPALIVE'
    #!/bin/bash
    # Generate CPU activity to prevent Oracle from reclaiming idle instance
    dd if=/dev/urandom bs=1M count=100 | md5sum > /dev/null 2>&1
    echo "$(date): keep-alive ping" >> /var/log/keep-alive.log
    KEEPALIVE
  - chmod +x /opt/scripts/keep-alive.sh
  - echo "0 */6 * * * root /opt/scripts/keep-alive.sh" > /etc/cron.d/keep-alive

  # Set up backup cron (runs daily at 4 AM, requires rclone config)
  - echo "0 4 * * * ubuntu /opt/scripts/backup.sh all >> /var/log/backup.log 2>&1" > /etc/cron.d/backup

  # Open firewall ports
  - ufw allow 22/tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw --force enable

  # Log completion
  - echo "Cloud-init setup complete at $(date)" >> /var/log/cloud-init-complete.log

write_files:
  - path: /home/ubuntu/README.md
    owner: ubuntu:ubuntu
    permissions: '0644'
    content: |
      # xdeca VPS

      ## Services
      - OpenProject: https://openproject.${domain}
      - Discourse: https://discourse.${domain}

      ## Directory Structure
      ~/apps/
        caddy/       - Reverse proxy
        openproject/ - Project management
        discourse/   - Forum

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

      Restore:
        /opt/scripts/restore.sh <service> [date]

      ## Keep-alive
      Cron runs every 6 hours to prevent Oracle reclaiming idle instance.
      Check: cat /var/log/keep-alive.log
