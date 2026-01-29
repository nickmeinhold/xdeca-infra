#!/bin/bash
# Restore script for all services
# Restores from AWS S3 via rclone
# Usage: ./restore.sh <service> [date]
#   service: kanbn, outline
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
  echo "  service: kanbn, outline"
  echo "  date: YYYY-MM-DD (optional)"
  echo ""
  echo "Examples:"
  echo "  $0 kanbn              # Restore latest"
  echo "  $0 outline 2024-01-15 # Restore specific date"
  exit 1
fi

mkdir -p "$RESTORE_DIR"

list_backups() {
  local service=$1
  log "Available backups for $service:"
  rclone ls "$RCLONE_REMOTE:$BUCKET/$service/" | sort -r | head -20
}

restore_kanbn() {
  log "Restoring Kan.bn..."

  # Find backup file
  if [ -n "$DATE" ]; then
    BACKUP_FILE="kanbn-$DATE.sql.gz"
  else
    BACKUP_FILE=$(rclone ls "$RCLONE_REMOTE:$BUCKET/kanbn/" | sort -r | head -1 | awk '{print $2}')
  fi

  if [ -z "$BACKUP_FILE" ]; then
    error "No backup found"
    list_backups kanbn
    exit 1
  fi

  log "Restoring from: $BACKUP_FILE"

  # Download backup
  log "Downloading backup from S3..."
  rclone copy "$RCLONE_REMOTE:$BUCKET/kanbn/$BACKUP_FILE" "$RESTORE_DIR/"

  # Ensure Kan.bn postgres is running
  cd ~/apps/kanbn
  docker-compose up -d kanbn_postgres
  log "Waiting for PostgreSQL to start..."
  sleep 10

  # Drop and recreate database
  log "Dropping existing database..."
  docker exec -i kanbn_postgres bash -c "psql -U kanbn -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'kanbn' AND pid <> pg_backend_pid();\" postgres && dropdb -U kanbn kanbn && createdb -U kanbn kanbn"

  # Restore database
  log "Restoring database..."
  gunzip -c "$RESTORE_DIR/$BACKUP_FILE" | \
    docker exec -i kanbn_postgres psql -U kanbn kanbn

  log "Restarting Kan.bn..."
  docker-compose restart

  # Cleanup
  rm -f "$RESTORE_DIR/$BACKUP_FILE"

  log "Kan.bn restore complete!"
}

restore_outline() {
  log "Restoring Outline..."

  # Find backup file
  if [ -n "$DATE" ]; then
    BACKUP_FILE="outline-$DATE.sql.gz"
  else
    BACKUP_FILE=$(rclone ls "$RCLONE_REMOTE:$BUCKET/outline/" | sort -r | head -1 | awk '{print $2}')
  fi

  if [ -z "$BACKUP_FILE" ]; then
    error "No backup found"
    list_backups outline
    exit 1
  fi

  log "Restoring from: $BACKUP_FILE"

  # Download backup
  log "Downloading backup from S3..."
  rclone copy "$RCLONE_REMOTE:$BUCKET/outline/$BACKUP_FILE" "$RESTORE_DIR/"

  # Ensure Outline postgres is running
  cd ~/apps/outline
  docker-compose up -d outline_postgres
  log "Waiting for PostgreSQL to start..."
  sleep 10

  # Drop and recreate database
  log "Dropping existing database..."
  docker exec -i outline_postgres bash -c "psql -U outline -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'outline' AND pid <> pg_backend_pid();\" postgres && dropdb -U outline outline && createdb -U outline outline"

  # Restore database
  log "Restoring database..."
  gunzip -c "$RESTORE_DIR/$BACKUP_FILE" | \
    docker exec -i outline_postgres psql -U outline outline

  log "Restarting Outline..."
  docker-compose restart

  # Cleanup
  rm -f "$RESTORE_DIR/$BACKUP_FILE"

  log "Outline restore complete!"
}

# Run restore
case $SERVICE in
  kanbn)
    restore_kanbn
    ;;
  outline)
    restore_outline
    ;;
  list)
    list_backups "${DATE:-kanbn}"
    ;;
  *)
    error "Unknown service: $SERVICE"
    echo "Valid services: kanbn, outline, list"
    exit 1
    ;;
esac
