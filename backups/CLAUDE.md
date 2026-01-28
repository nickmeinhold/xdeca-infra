# Backups

Automated backups to AWS S3.

## Overview

| Service | What | Schedule | Retention |
|---------|------|----------|-----------|
| OpenProject | PostgreSQL | Daily 4 AM | 7 days |

## Setup

### 1. Create OCI Customer Secret Key

```bash
# Get namespace
oci os ns get

# Then in OCI Console:
# Identity → Users → Your User → Customer Secret Keys → Generate
# Name: rclone-backups
# COPY THE SECRET KEY (shown only once!)
```

### 2. Create and Encrypt Secrets

```bash
cd backups
cp secrets.yaml.example secrets.yaml
# Edit with your values
sops -e -i secrets.yaml
```

### 3. Deploy

```bash
cd kamatera-vps
make deploy-backups
```

This will:
- Generate rclone config from secrets
- Create the backup bucket (if it doesn't exist)
- Deploy backup/restore scripts

## Manual Operations

### Run Backup

```bash
ssh ubuntu@103.125.218.210
sudo /opt/scripts/backup.sh all
```

### List Remote Backups

```bash
rclone ls oci-archive:xdeca-backups/
```

### Restore

```bash
# Latest
sudo /opt/scripts/restore.sh openproject

# Specific date
sudo /opt/scripts/restore.sh openproject 2024-01-15
```

See `docs/backups.md` for full restore procedures.

## Files

| File | Purpose |
|------|---------|
| `secrets.yaml` | OCI credentials (encrypted) |
| `scripts/backup.sh` | Backup script |
| `scripts/restore.sh` | Restore script |
| `scripts/setup-backups.sh` | Manual setup (superseded by IaC) |
