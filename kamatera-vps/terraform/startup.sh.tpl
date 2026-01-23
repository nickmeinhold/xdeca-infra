#!/bin/bash
# Minimal startup script - just enable SSH access
# Full configuration happens via deploy-to.sh

# Create ubuntu user if not exists
id ubuntu &>/dev/null || useradd -m -s /bin/bash -G sudo ubuntu
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu

# Set up SSH key for ubuntu user
mkdir -p /home/ubuntu/.ssh
echo "${ssh_public_key}" > /home/ubuntu/.ssh/authorized_keys
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

# Open SSH port
ufw allow 22/tcp
ufw --force enable

echo "Startup script complete at $(date)" >> /var/log/startup-complete.log
