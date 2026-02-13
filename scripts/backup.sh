#!/bin/bash
# Unified backup script for all services
# Backs up to Google Cloud Storage via rclone + redundant copies to GitHub
# Usage: ./backup.sh [all|kanbn|outline]

set -e

SERVICE=${1:-all}
BACKUP_DIR="/tmp/backups"
DATE=$(date +%Y-%m-%d)
RCLONE_REMOTE="gcs"
BUCKET="xdeca-backups"
RETENTION_DAYS=7

# GitHub backup config
GITHUB_BACKUP_REPO="git@github-backups:10xdeca/xdeca-backups.git"
GITHUB_BACKUP_DIR="/tmp/xdeca-backups"

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

backup_kanbn() {
  log "Backing up Kan.bn..."

  local backup_file="$BACKUP_DIR/kanbn-$DATE.sql.gz"

  # Dump PostgreSQL
  docker exec kanbn_postgres \
    pg_dump -U kanbn kanbn | gzip > "$backup_file"

  # Upload to object storage
  rclone copy "$backup_file" "$RCLONE_REMOTE:$BUCKET/kanbn/"

  log "Kan.bn backup complete: kanbn-$DATE.sql.gz"
}

backup_pm_bot() {
  log "Backing up xdeca-pm-bot..."

  local backup_file="$BACKUP_DIR/pm-bot-$DATE.db"

  # Copy SQLite database from container volume
  docker cp xdeca-pm-bot:/app/data/kan-bot.db "$backup_file"

  # Upload to object storage
  rclone copy "$backup_file" "$RCLONE_REMOTE:$BUCKET/pm-bot/"

  log "xdeca-pm-bot backup complete: pm-bot-$DATE.db"
}

backup_outline() {
  log "Backing up Outline..."

  local backup_file="$BACKUP_DIR/outline-$DATE.sql.gz"

  # Dump PostgreSQL
  docker exec outline_postgres \
    pg_dump -U outline outline | gzip > "$backup_file"

  # Upload to object storage
  rclone copy "$backup_file" "$RCLONE_REMOTE:$BUCKET/outline/"

  log "Outline backup complete: outline-$DATE.sql.gz"
}

backup_to_github() {
  local services=("$@")

  # Check prerequisites
  if ! command -v git &> /dev/null; then
    error "git not installed, skipping GitHub backup"
    return 0
  fi
  if [ ! -f "$HOME/.ssh/xdeca-backups-deploy" ]; then
    error "Deploy key not found at ~/.ssh/xdeca-backups-deploy, skipping GitHub backup"
    return 0
  fi

  log "Pushing backups to GitHub..."

  # Clone or pull the backup repo (shallow)
  if [ -d "$GITHUB_BACKUP_DIR/.git" ]; then
    git -C "$GITHUB_BACKUP_DIR" pull --rebase 2>/dev/null || {
      rm -rf "$GITHUB_BACKUP_DIR"
      git clone --depth 1 "$GITHUB_BACKUP_REPO" "$GITHUB_BACKUP_DIR"
    }
  else
    rm -rf "$GITHUB_BACKUP_DIR"
    git clone --depth 1 "$GITHUB_BACKUP_REPO" "$GITHUB_BACKUP_DIR" 2>/dev/null || {
      # First push — repo may be empty
      mkdir -p "$GITHUB_BACKUP_DIR"
      git -C "$GITHUB_BACKUP_DIR" init -b main
      git -C "$GITHUB_BACKUP_DIR" remote add origin "$GITHUB_BACKUP_REPO"
    }
  fi

  # Copy each service dump
  for svc in "${services[@]}"; do
    local dump="$BACKUP_DIR/${svc}-${DATE}.sql.gz"
    local dest="$GITHUB_BACKUP_DIR/${svc}.sql.gz"

    if [ ! -f "$dump" ]; then
      error "Dump file not found: $dump"
      continue
    fi

    cp "$dump" "$dest"
    log "Copied $svc backup → ${svc}.sql.gz"
  done

  # Commit and push
  git -C "$GITHUB_BACKUP_DIR" add -A
  if git -C "$GITHUB_BACKUP_DIR" diff --cached --quiet; then
    log "No changes to push to GitHub"
  else
    git -C "$GITHUB_BACKUP_DIR" \
      -c user.name="xdeca-backup" \
      -c user.email="backup@xdeca.com" \
      commit -m "backup $DATE"
    git -C "$GITHUB_BACKUP_DIR" push origin HEAD 2>/dev/null || \
      git -C "$GITHUB_BACKUP_DIR" push --set-upstream origin main
    log "Backups pushed to GitHub"
  fi
}

cleanup_old_backups() {
  log "Cleaning up backups older than $RETENTION_DAYS days..."

  # Clean local temp backups
  find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

  # Clean remote backups (rclone delete with min-age)
  rclone delete "$RCLONE_REMOTE:$BUCKET/kanbn/" \
    --min-age "${RETENTION_DAYS}d" 2>/dev/null || true
  rclone delete "$RCLONE_REMOTE:$BUCKET/outline/" \
    --min-age "${RETENTION_DAYS}d" 2>/dev/null || true
  rclone delete "$RCLONE_REMOTE:$BUCKET/pm-bot/" \
    --min-age "${RETENTION_DAYS}d" 2>/dev/null || true

  log "Cleanup complete"
}

# Run backups
case $SERVICE in
  all)
    backup_kanbn
    backup_outline
    backup_pm_bot
    backup_to_github kanbn outline
    cleanup_old_backups
    ;;
  kanbn)
    backup_kanbn
    backup_to_github kanbn
    ;;
  outline)
    backup_outline
    backup_to_github outline
    ;;
  pm-bot)
    backup_pm_bot
    ;;
  cleanup)
    cleanup_old_backups
    ;;
  *)
    echo "Usage: $0 [all|kanbn|outline|pm-bot|cleanup]"
    exit 1
    ;;
esac

log "Backup complete!"
