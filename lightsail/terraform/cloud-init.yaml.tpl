#cloud-config

package_update: true
package_upgrade: true

packages:
  - docker.io
  - docker-compose
  - htop
  - curl
  - jq
  - rclone

users:
  - name: ubuntu
    groups: docker
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}

runcmd:
  # Enable Docker
  - systemctl enable docker
  - systemctl start docker

  # Create apps directory
  - mkdir -p /home/ubuntu/apps
  - chown ubuntu:ubuntu /home/ubuntu/apps

  # Log completion
  - echo "Cloud-init complete at $(date)" >> /var/log/cloud-init-complete.log
