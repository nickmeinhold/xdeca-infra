#cloud-config

package_update: true
package_upgrade: true

packages:
  - docker.io
  - docker-compose
  - git
  - curl
  - htop
  - netcat-openbsd
  - rclone

runcmd:
  # Enable Docker
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ubuntu

  # Set up apps directory
  - mkdir -p /home/ubuntu/apps
  - chown ubuntu:ubuntu /home/ubuntu/apps

  # Set up scripts directory
  - mkdir -p /opt/scripts
  - chown ubuntu:ubuntu /opt/scripts

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
      - Kan.bn: https://tasks.xdeca.com
      - Outline: https://wiki.xdeca.com
      - MinIO: https://storage.xdeca.com

      ## Directory Structure
      ~/apps/
        caddy/   - Reverse proxy
        kanbn/   - Task management
        outline/ - Team wiki

      ## Commands
      cd ~/apps/<service>
      docker-compose up -d      # Start
      docker-compose logs -f    # Logs
      docker-compose restart    # Restart

      ## Backups
      Daily at 4 AM to AWS S3.

      Manual backup:
        /opt/scripts/backup.sh all

      Restore:
        /opt/scripts/restore.sh <service> [date]

      ## Keep-alive
      Cron runs every 6 hours to prevent Oracle reclaiming idle instance.
      Check: cat /var/log/keep-alive.log
