# Backup & Restore

All services backup to **AWS S3**.

## Overview

| Service | What's Backed Up | Schedule | Retention |
|---------|------------------|----------|-----------|
| OpenProject | PostgreSQL database | Daily 4 AM | 7 days |

## Cost

- **First 10GB: Free** (Oracle Always Free tier)
- After 10GB: ~$0.026/GB/month (Standard tier)
- Typical total: <1GB (well within free tier)

## Setup (IaC)

### 1. Create OCI Customer Secret Key

```bash
# Get your namespace
oci os ns get

# In OCI Console:
# Identity → Users → Your User → Customer Secret Keys → Generate
# Name: rclone-backups
# COPY THE SECRET KEY (shown only once!)
```

### 2. Create Secrets File

```bash
cd backups
cp secrets.yaml.example secrets.yaml
# Edit with your OCI credentials
sops -e -i secrets.yaml
```

### 3. Deploy

```bash
cd kamatera-vps
make deploy-backups
```

This deploys:
- rclone config with OCI credentials
- Backup/restore scripts to `/opt/scripts/`
- Creates bucket if needed
- Verifies cron job (4 AM daily)

## Manual Operations

### Run Backup Now

```bash
# All services
sudo /opt/scripts/backup.sh all

# Single service
sudo /opt/scripts/backup.sh openproject
```

### List Remote Backups

```bash
rclone ls s3:xdeca-backups/
rclone ls s3:xdeca-backups/openproject/
```

### Check Backup Logs

```bash
tail -f /var/log/backup.log
```

### Manual Cleanup

```bash
sudo /opt/scripts/backup.sh cleanup
```

## Restore

Using Standard tier storage - **no restore delay**, objects are immediately available.

### Auto-Restore on Deploy

When running `make deploy`, the system automatically:
1. Checks if OpenProject is empty (fresh install)
2. If empty AND backups exist, restores from latest backup
3. Skips restore if data already exists

This means disaster recovery is automatic:
```bash
make apply    # Provision new VPS
make deploy   # Deploy services + auto-restore from backup
```

### Fresh Install Detection

| Service | Fresh Install Detected When |
|---------|----------------------------|
| OpenProject | `users` table has ≤1 row |

### Manual Restore

To force restore (overwrites existing data):
```bash
make restore
```

### Restore Commands

```bash
# Restore latest backup
sudo /opt/scripts/restore.sh openproject

# Restore specific date
sudo /opt/scripts/restore.sh openproject 2024-01-15
```

### OpenProject Restore

1. Script stops OpenProject
2. Downloads and decompresses backup
3. Restores PostgreSQL database
4. Restarts OpenProject

```bash
sudo /opt/scripts/restore.sh openproject
```

## Troubleshooting

### Backup not running?

```bash
# Check cron
crontab -l | grep backup

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

### Archive restore taking too long?

Archive-tier objects need ~1 hour to restore. Check status:

```bash
NAMESPACE=$(oci os ns get --query 'data' --raw-output)
oci os object head \
  --namespace $NAMESPACE \
  --bucket-name xdeca-backups \
  --name "openproject/openproject-2024-01-15.sql.gz" \
  --query 'archival-state'
```

Status meanings:
- `Archived` - Still in cold storage
- `Restoring` - Retrieval in progress (~1 hour)
- `Available` - Ready to download (24 hour window)

## Backup File Locations

| Service | Remote Path | Contents |
|---------|-------------|----------|
| OpenProject | `xdeca-backups/openproject/` | `openproject-YYYY-MM-DD.sql.gz` |
