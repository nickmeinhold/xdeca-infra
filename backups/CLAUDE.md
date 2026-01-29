# Backups

Automated backups to AWS S3.

## Overview

| Service | What | Schedule | Retention |
|---------|------|----------|-----------|
| Kan.bn | PostgreSQL | Daily 4 AM | 7 days |
| Outline | PostgreSQL | Daily 4 AM | 7 days |

## Setup

### 1. Create and Encrypt Secrets

```bash
cd backups
cp secrets.yaml.example secrets.yaml
# Edit with your values
sops -e -i secrets.yaml
```

### 2. Deploy

```bash
./scripts/deploy-to.sh <ip> backups
```

This will:
- Deploy AWS credentials and rclone config
- Create the backup bucket (if it doesn't exist)
- Deploy backup/restore scripts
- Set up daily cron job

## Manual Operations

### Run Backup

```bash
ssh ubuntu@13.54.159.183
/opt/scripts/backup.sh all
```

### List Remote Backups

```bash
rclone ls s3:xdeca-backups/
rclone ls s3:xdeca-backups/kanbn/
rclone ls s3:xdeca-backups/outline/
```

### Restore

```bash
# Latest
/opt/scripts/restore.sh kanbn
/opt/scripts/restore.sh outline

# Specific date
/opt/scripts/restore.sh kanbn 2024-01-15
/opt/scripts/restore.sh outline 2024-01-15
```

See `docs/backups.md` for full restore procedures.

## Files

| File | Purpose |
|------|---------|
| `secrets.yaml` | AWS S3 credentials (encrypted) |
| `scripts/backup.sh` | Backup script |
| `scripts/restore.sh` | Restore script |
