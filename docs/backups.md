# Backup & Restore

All services backup to **AWS S3**.

## Overview

| Service | What's Backed Up | Schedule | Retention |
|---------|------------------|----------|-----------|
| Kan.bn | PostgreSQL database | Daily 4 AM | 7 days |
| Outline | PostgreSQL database | Daily 4 AM | 7 days |

## Manual Operations

### Run Backup Now

```bash
# All services
/opt/scripts/backup.sh all

# Single service
/opt/scripts/backup.sh kanbn
/opt/scripts/backup.sh outline
```

### List Remote Backups

```bash
rclone ls s3:xdeca-backups/
rclone ls s3:xdeca-backups/kanbn/
rclone ls s3:xdeca-backups/outline/
```

### Check Backup Logs

```bash
tail -f /var/log/backup.log
```

## Restore

### Manual Restore

```bash
# Restore latest backup
/opt/scripts/restore.sh kanbn
/opt/scripts/restore.sh outline

# Restore specific date
/opt/scripts/restore.sh kanbn 2024-01-15
/opt/scripts/restore.sh outline 2024-01-15
```

### Restore Process

1. Script downloads backup from S3
2. Stops the service
3. Drops and recreates database
4. Restores PostgreSQL dump
5. Restarts the service

## Backup File Locations

| Service | Remote Path | Contents |
|---------|-------------|----------|
| Kan.bn | `xdeca-backups/kanbn/` | `kanbn-YYYY-MM-DD.sql.gz` |
| Outline | `xdeca-backups/outline/` | `outline-YYYY-MM-DD.sql.gz` |

## Troubleshooting

### Backup not running?

```bash
# Check cron
cat /etc/cron.d/backup

# Check logs
tail -50 /var/log/backup.log
```

### rclone connection issues?

```bash
# Test connection
rclone lsd s3:

# Check config
cat ~/.config/rclone/rclone.conf
```
