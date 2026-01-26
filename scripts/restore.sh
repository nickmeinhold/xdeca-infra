#!/bin/bash
# Restore script for all services
# Restores from Oracle Object Storage via rclone
# Usage: ./restore.sh <service> [date]
#   service: openproject|twenty
#   date: YYYY-MM-DD (optional, defaults to latest)

set -e

SERVICE=$1
DATE=${2:-""}
RESTORE_DIR="/tmp/restore"
RCLONE_REMOTE="s3"
BUCKET="xdeca-backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2; }

if [ -z "$SERVICE" ]; then
  echo "Usage: $0 <service> [date]"
  echo "  service: openproject|twenty"
  echo "  date: YYYY-MM-DD (optional)"
  echo ""
  echo "Examples:"
  echo "  $0 openproject           # Restore latest"
  echo "  $0 twenty 2024-01-15     # Restore specific date"
  exit 1
fi

mkdir -p "$RESTORE_DIR"

# Oracle Archive Storage requires restore request before download
request_archive_restore() {
  local object_name=$1
  local bucket_path=$2

  log "Requesting restore from archive storage..."
  log "Object: $object_name"

  # Get namespace
  NAMESPACE=$(oci os ns get --query 'data' --raw-output)

  # Request restore (24 hours availability)
  oci os object restore \
    --namespace "$NAMESPACE" \
    --bucket-name "$BUCKET" \
    --name "$bucket_path/$object_name" \
    --hours 24 2>/dev/null || true

  # Check status
  local status=""
  local attempts=0
  local max_attempts=60  # 1 hour max wait

  while [ "$status" != "Available" ] && [ $attempts -lt $max_attempts ]; do
    status=$(oci os object head \
      --namespace "$NAMESPACE" \
      --bucket-name "$BUCKET" \
      --name "$bucket_path/$object_name" \
      --query 'archival-state' --raw-output 2>/dev/null || echo "Unknown")

    case $status in
      Available)
        log "Object is available for download"
        return 0
        ;;
      Restoring)
        echo -n "."
        sleep 60
        ;;
      Archived)
        log "Waiting for restore to begin..."
        sleep 30
        ;;
      *)
        warn "Unknown status: $status"
        sleep 30
        ;;
    esac
    attempts=$((attempts + 1))
  done

  if [ "$status" != "Available" ]; then
    error "Restore timed out. Object may still be restoring."
    error "Check status and try again in ~1 hour."
    exit 1
  fi
}

list_backups() {
  local service=$1
  log "Available backups for $service:"
  rclone ls "$RCLONE_REMOTE:$BUCKET/$service/" | sort -r | head -20
}

restore_openproject() {
  log "Restoring OpenProject..."

  # Find backup file
  if [ -n "$DATE" ]; then
    BACKUP_FILE="openproject-$DATE.sql.gz"
  else
    BACKUP_FILE=$(rclone ls "$RCLONE_REMOTE:$BUCKET/openproject/" | sort -r | head -1 | awk '{print $2}')
  fi

  if [ -z "$BACKUP_FILE" ]; then
    error "No backup found"
    list_backups openproject
    exit 1
  fi

  log "Restoring from: $BACKUP_FILE"

  # Request archive restore
  request_archive_restore "$BACKUP_FILE" "openproject"

  # Download backup
  log "Downloading backup..."
  rclone copy "$RCLONE_REMOTE:$BUCKET/openproject/$BACKUP_FILE" "$RESTORE_DIR/"

  # Stop OpenProject
  warn "Stopping OpenProject..."
  cd ~/apps/openproject
  podman-compose down

  # Restore database
  log "Restoring database..."
  podman-compose up -d openproject
  sleep 10  # Wait for postgres to start

  gunzip -c "$RESTORE_DIR/$BACKUP_FILE" | \
    podman exec -i openproject_openproject_1 psql -U postgres openproject

  log "OpenProject restored! Restarting..."
  podman-compose restart

  log "OpenProject restore complete"
}

restore_twenty() {
  log "Restoring Twenty..."

  # Find backup files
  if [ -n "$DATE" ]; then
    DB_FILE="twenty-db-$DATE.sql.gz"
    STORAGE_FILE="twenty-storage-$DATE.tar.gz"
  else
    DB_FILE=$(rclone ls "$RCLONE_REMOTE:$BUCKET/twenty/" | grep "db" | sort -r | head -1 | awk '{print $2}')
    STORAGE_FILE=$(rclone ls "$RCLONE_REMOTE:$BUCKET/twenty/" | grep "storage" | sort -r | head -1 | awk '{print $2}')
  fi

  if [ -z "$DB_FILE" ]; then
    error "No database backup found"
    list_backups twenty
    exit 1
  fi

  log "Restoring from: $DB_FILE, $STORAGE_FILE"

  # Request archive restore for both files
  request_archive_restore "$DB_FILE" "twenty"
  [ -n "$STORAGE_FILE" ] && request_archive_restore "$STORAGE_FILE" "twenty"

  # Download backups
  log "Downloading backups..."
  rclone copy "$RCLONE_REMOTE:$BUCKET/twenty/$DB_FILE" "$RESTORE_DIR/"
  [ -n "$STORAGE_FILE" ] && rclone copy "$RCLONE_REMOTE:$BUCKET/twenty/$STORAGE_FILE" "$RESTORE_DIR/"

  # Stop Twenty
  warn "Stopping Twenty..."
  cd ~/apps/twenty
  podman-compose down

  # Restore database
  log "Restoring database..."
  podman-compose up -d db
  sleep 10  # Wait for postgres to start

  gunzip -c "$RESTORE_DIR/$DB_FILE" | \
    podman exec -i twenty_db_1 psql -U twenty twenty

  # Restore local storage if backup exists
  if [ -f "$RESTORE_DIR/$STORAGE_FILE" ]; then
    log "Restoring local storage..."
    podman run --rm \
      -v twenty_server_data:/data \
      -v "$RESTORE_DIR:/backup:ro" \
      alpine sh -c "rm -rf /data/* && tar xzf /backup/$STORAGE_FILE -C /data"
  fi

  log "Starting Twenty..."
  podman-compose up -d

  log "Twenty restore complete"
}

# Run restore
case $SERVICE in
  openproject)
    restore_openproject
    ;;
  twenty)
    restore_twenty
    ;;
  list)
    list_backups "${DATE:-openproject}"
    ;;
  *)
    error "Unknown service: $SERVICE"
    echo "Valid services: openproject, twenty"
    exit 1
    ;;
esac
