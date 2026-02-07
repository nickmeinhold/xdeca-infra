#!/bin/bash
# Sync Outline wiki content to Obsidian vault (one-way, read-only mirror)
# Runs locally as a cron job — destination is iCloud-synced Obsidian vault
# Usage: ./scripts/sync-outline-obsidian.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${OUTLINE_API_BASE:-https://wiki.xdeca.com/api}"
VAULT_DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/xdeca"
PAGE_LIMIT=25

# SOPS age key location
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

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

# Get API token from env var or decrypt from secrets
get_api_token() {
  if [ -n "$OUTLINE_API_TOKEN" ]; then
    echo "$OUTLINE_API_TOKEN"
    return
  fi

  local secrets_file="$REPO_ROOT/outline/secrets.yaml"
  if [ ! -f "$secrets_file" ]; then
    error "No OUTLINE_API_TOKEN env var and outline/secrets.yaml not found"
    exit 1
  fi

  local token
  token=$(sops -d "$secrets_file" | yq -r '.outline_api_token')
  if [ -z "$token" ] || [ "$token" = "null" ]; then
    error "outline_api_token not found in outline/secrets.yaml"
    error "Generate a token in Outline (Settings → API) and add it with: sops outline/secrets.yaml"
    exit 1
  fi
  echo "$token"
}

# Make an Outline API call (POST-based RPC)
api_call() {
  local endpoint="$1"
  local data="${2:-}"

  local curl_args=(-s -w "\n%{http_code}" -X POST
    -H "Authorization: Bearer $API_TOKEN"
    -H "Content-Type: application/json")

  if [ -n "$data" ]; then
    curl_args+=(-d "$data")
  fi

  local response
  response=$(curl "${curl_args[@]}" "$API_BASE/$endpoint")

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" -ne 200 ]; then
    error "API call $endpoint failed (HTTP $http_code): $body"
    return 1
  fi

  echo "$body"
}

# Sanitize a string for use as a filename
sanitize_filename() {
  echo "$1" | sed 's/[\/\\:*?"<>|]/-/g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//'
}

# Main sync logic
main() {
  API_TOKEN=$(get_api_token)
  log "Starting Outline → Obsidian sync"

  # Create vault directory if needed
  mkdir -p "$VAULT_DIR"

  # Temp files for doc data and link map
  local manifest doc_data link_map
  manifest=$(mktemp)
  doc_data=$(mktemp -d)
  link_map=$(mktemp)
  trap 'rm -f "$manifest" "$link_map"; rm -rf "$doc_data"' EXIT

  # Phase 1: Fetch all documents and build link map
  log "Fetching collections..."
  local collections
  collections=$(api_call "collections.list")
  local collection_count
  collection_count=$(echo "$collections" | jq '.data | length')
  log "Found $collection_count collections"

  echo "$collections" | jq -r '.data[] | "\(.id)\t\(.name)"' | while IFS=$'\t' read -r col_id col_name; do
    local safe_name
    safe_name=$(sanitize_filename "$col_name")

    log "Fetching collection: $col_name"

    local offset=0
    local has_more=true

    while [ "$has_more" = "true" ]; do
      local docs_response
      docs_response=$(api_call "documents.list" "{\"collectionId\": \"$col_id\", \"offset\": $offset, \"limit\": $PAGE_LIMIT}")

      local batch_count
      batch_count=$(echo "$docs_response" | jq '.data | length')

      if [ "$batch_count" -eq 0 ]; then
        break
      fi

      local doc_ids
      doc_ids=$(echo "$docs_response" | jq -r '.data[] | .id')

      for doc_id in $doc_ids; do
        local doc_info
        doc_info=$(api_call "documents.info" "{\"id\": \"$doc_id\"}")

        local doc_title doc_text doc_url_id
        doc_title=$(echo "$doc_info" | jq -r '.data.title')
        doc_text=$(echo "$doc_info" | jq -r '.data.text')
        doc_url_id=$(echo "$doc_info" | jq -r '.data.url // empty' | sed 's|^/doc/||')

        local safe_title
        safe_title=$(sanitize_filename "$doc_title")
        safe_title="${safe_title%.md}"

        # Save doc content to temp file
        echo "$doc_text" > "$doc_data/$doc_id"
        # Save metadata: id, collection dir, safe title
        printf '%s\t%s\t%s\n' "$doc_id" "$safe_name" "$safe_title" >> "$doc_data/index"

        # Build link map: doc_id → safe_title, url_id → safe_title
        printf '%s\t%s\n' "$doc_id" "$safe_title" >> "$link_map"
        if [ -n "$doc_url_id" ]; then
          printf '%s\t%s\n' "$doc_url_id" "$safe_title" >> "$link_map"
        fi
      done

      offset=$((offset + PAGE_LIMIT))
      if [ "$batch_count" -lt "$PAGE_LIMIT" ]; then
        has_more=false
      fi
    done
  done

  # Phase 2: Write files with rewritten links
  log "Writing files with rewritten links..."

  if [ ! -f "$doc_data/index" ]; then
    log "No documents found"
    return
  fi

  while IFS=$'\t' read -r doc_id col_dir safe_title; do
    local file_dir="$VAULT_DIR/$col_dir"
    mkdir -p "$file_dir"
    local file_path="$file_dir/$safe_title.md"

    local content
    content=$(cat "$doc_data/$doc_id")

    # Rewrite Outline internal links [Text](/doc/<id-or-slug>) to Obsidian wikilinks [[Text]]
    while IFS=$'\t' read -r map_key _; do
      content=$(printf '%s' "$content" | sed "s|\[\\([^]]*\\)\](/doc/$map_key)|[[\\1]]|g")
    done < "$link_map"

    printf '%s\n' "$content" > "$file_path"
    echo "$file_path" >> "$manifest"
  done < "$doc_data/index"

  # Clean up stale files not written during this sync
  log "Cleaning up stale files..."
  local stale_count=0
  while IFS= read -r -d '' existing_file; do
    if ! grep -qFx "$existing_file" "$manifest"; then
      rm "$existing_file"
      stale_count=$((stale_count + 1))
    fi
  done < <(find "$VAULT_DIR" -name '*.md' -print0)

  if [ "$stale_count" -gt 0 ]; then
    log "Removed $stale_count stale files"
  fi

  # Remove empty collection directories
  find "$VAULT_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true

  log "Sync complete!"
}

main
