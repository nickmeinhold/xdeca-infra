# Backup & Restore

All services backup to **Oracle Cloud Object Storage** (Archive tier).

## Overview

| Service | What's Backed Up | Schedule | Retention |
|---------|------------------|----------|-----------|
| OpenProject | PostgreSQL database | Daily 4 AM | 7 days |
| Twenty | PostgreSQL + local storage | Daily 4 AM | 7 days |
| Discourse | Built-in backup | Daily 3 AM | 7 days |

## Cost

- **First 10GB: Free** (Oracle Always Free tier)
- After 10GB: ~$0.0026/GB/month (Archive tier)
- Typical total: <1GB (well within free tier)

## Setup

Run once after VPS provisioning:

```bash
ssh ubuntu@<vps-ip>
cd ~/apps
./scripts/setup-backups.sh
```

The setup script will:
1. Install rclone
2. Guide you through OCI credential setup
3. Create the backup bucket (Archive tier)
4. Configure daily cron job at 4 AM

## Manual Operations

### Run Backup Now

```bash
# All services
sudo /opt/scripts/backup.sh all

# Single service
sudo /opt/scripts/backup.sh openproject
sudo /opt/scripts/backup.sh twenty
sudo /opt/scripts/backup.sh discourse
```

### List Remote Backups

```bash
rclone ls oci-archive:xdeca-backups/
rclone ls oci-archive:xdeca-backups/openproject/
rclone ls oci-archive:xdeca-backups/twenty/
rclone ls oci-archive:xdeca-backups/discourse/
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

### Important: Archive Storage Delay

Oracle Archive Storage requires **~1 hour** to restore objects before download. The restore script handles this automatically, but be aware of the delay.

### Restore Commands

```bash
# Restore latest backup
sudo /opt/scripts/restore.sh openproject
sudo /opt/scripts/restore.sh twenty

# Restore specific date
sudo /opt/scripts/restore.sh openproject 2024-01-15
sudo /opt/scripts/restore.sh twenty 2024-01-15

# Discourse (manual process)
sudo /opt/scripts/restore.sh discourse
```

### OpenProject Restore

1. Script stops OpenProject
2. Downloads and decompresses backup
3. Restores PostgreSQL database
4. Restarts OpenProject

```bash
sudo /opt/scripts/restore.sh openproject
```

### Twenty Restore

1. Script stops Twenty
2. Downloads database and storage backups
3. Restores PostgreSQL database
4. Restores local file storage
5. Restarts Twenty

```bash
sudo /opt/scripts/restore.sh twenty
```

### Discourse Restore

Discourse uses its own restore process:

1. **List backups**
   ```bash
   rclone ls oci-archive:xdeca-backups/discourse/
   ```

2. **Request archive restore** (~1 hour wait)
   ```bash
   NAMESPACE=$(oci os ns get --query 'data' --raw-output)
   oci os object restore \
     --namespace $NAMESPACE \
     --bucket-name xdeca-backups \
     --name "discourse/discourse-2024-01-15.tar.gz" \
     --hours 24
   ```

3. **Check status** (wait for "Available")
   ```bash
   oci os object head \
     --namespace $NAMESPACE \
     --bucket-name xdeca-backups \
     --name "discourse/discourse-2024-01-15.tar.gz" \
     --query 'archival-state'
   ```

4. **Download backup**
   ```bash
   rclone copy oci-archive:xdeca-backups/discourse/discourse-2024-01-15.tar.gz \
     /var/discourse/shared/standalone/backups/default/
   ```

5. **Restore via Discourse**

   Option A - Admin UI:
   - Go to Admin → Backups
   - Click "Restore" on the backup

   Option B - CLI:
   ```bash
   cd /var/discourse
   ./launcher enter app
   discourse restore discourse-2024-01-15.tar.gz
   exit
   ./launcher rebuild app
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
rclone lsd oci-archive:

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
| Twenty | `xdeca-backups/twenty/` | `twenty-db-YYYY-MM-DD.sql.gz`, `twenty-storage-YYYY-MM-DD.tar.gz` |
| Discourse | `xdeca-backups/discourse/` | `discourse-YYYY-MM-DD.tar.gz` |
