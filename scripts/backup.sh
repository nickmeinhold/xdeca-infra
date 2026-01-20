#!/bin/bash
# Unified backup script for all services
# Backs up to Oracle Object Storage via rclone
# Usage: ./backup.sh [all|openproject|twenty|discourse]

set -e

SERVICE=${1:-all}
BACKUP_DIR="/tmp/backups"
DATE=$(date +%Y-%m-%d)
RCLONE_REMOTE="oci-archive"
BUCKET="xdeca-backups"
RETENTION_DAYS=7

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

backup_openproject() {
  log "Backing up OpenProject..."

  local backup_file="$BACKUP_DIR/openproject-$DATE.sql.gz"

  # Dump PostgreSQL (OpenProject uses internal postgres)
  podman exec openproject_openproject_1 \
    pg_dump -U postgres openproject | gzip > "$backup_file"

  # Upload to object storage
  rclone copy "$backup_file" "$RCLONE_REMOTE:$BUCKET/openproject/"

  log "OpenProject backup complete: openproject-$DATE.sql.gz"
}

backup_twenty() {
  log "Backing up Twenty..."

  local db_backup="$BACKUP_DIR/twenty-db-$DATE.sql.gz"
  local storage_backup="$BACKUP_DIR/twenty-storage-$DATE.tar.gz"

  # Dump PostgreSQL
  podman exec twenty_db_1 \
    pg_dump -U twenty twenty | gzip > "$db_backup"

  # Backup local storage
  podman run --rm \
    -v twenty_server_data:/data:ro \
    -v "$BACKUP_DIR:/backup" \
    alpine tar czf "/backup/twenty-storage-$DATE.tar.gz" -C /data .

  # Upload to object storage
  rclone copy "$db_backup" "$RCLONE_REMOTE:$BUCKET/twenty/"
  rclone copy "$storage_backup" "$RCLONE_REMOTE:$BUCKET/twenty/"

  log "Twenty backup complete: twenty-db-$DATE.sql.gz, twenty-storage-$DATE.tar.gz"
}

backup_discourse() {
  log "Backing up Discourse..."

  # Discourse creates its own backups, we just sync them
  local discourse_backup_dir="/var/discourse/shared/standalone/backups/default"

  if [ -d "$discourse_backup_dir" ]; then
    rclone sync "$discourse_backup_dir" "$RCLONE_REMOTE:$BUCKET/discourse/"
    log "Discourse backups synced"
  else
    error "Discourse backup directory not found: $discourse_backup_dir"
    return 1
  fi
}

cleanup_old_backups() {
  log "Cleaning up backups older than $RETENTION_DAYS days..."

  # Clean local temp backups
  find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

  # Clean remote backups (rclone delete with min-age)
  for service in openproject twenty; do
    rclone delete "$RCLONE_REMOTE:$BUCKET/$service/" \
      --min-age "${RETENTION_DAYS}d" 2>/dev/null || true
  done

  log "Cleanup complete"
}

# Run backups
case $SERVICE in
  all)
    backup_openproject
    backup_twenty
    backup_discourse
    cleanup_old_backups
    ;;
  openproject)
    backup_openproject
    ;;
  twenty)
    backup_twenty
    ;;
  discourse)
    backup_discourse
    ;;
  cleanup)
    cleanup_old_backups
    ;;
  *)
    echo "Usage: $0 [all|openproject|twenty|discourse|cleanup]"
    exit 1
    ;;
esac

log "Backup complete!"
