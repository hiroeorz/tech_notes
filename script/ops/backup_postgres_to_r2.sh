#!/usr/bin/env bash
set -euo pipefail

SERVICE_LABEL="${SERVICE_LABEL:-tech_notes-db}"
POSTGRES_USER="${POSTGRES_USER:?POSTGRES_USER is required}"
RCLONE_REMOTE="${RCLONE_REMOTE:-r2}"
R2_BUCKET="${R2_BUCKET:?R2_BUCKET is required}"
R2_PREFIX="${R2_PREFIX:-postgresql}"
S3_NO_CHECK_BUCKET="${S3_NO_CHECK_BUCKET:-1}"

DEFAULT_DATABASES=(
  tech_notes_production
  tech_notes_production_cache
  tech_notes_production_queue
  tech_notes_production_cable
)

if [ "${BACKUP_DATABASES:-}" != "" ]; then
  # Space-separated override for emergency/manual use.
  read -r -a DATABASES <<< "$BACKUP_DATABASES"
else
  DATABASES=("${DEFAULT_DATABASES[@]}")
fi

dump_file=""

cleanup() {
  if [ -n "$dump_file" ] && [ -f "$dump_file" ]; then
    rm -f "$dump_file"
  fi
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "ERROR: required command not found: $1"
    exit 1
  fi
}

trap cleanup EXIT

require_command docker
require_command rclone
require_command mktemp

STAMP="$(date +%Y%m%d_%H%M%S)"
CONTAINER="$(docker ps --filter "label=service=${SERVICE_LABEL}" --format '{{.Names}}' | head -n 1)"

if [ -z "$CONTAINER" ]; then
  log "ERROR: DB container not found for Docker label service=${SERVICE_LABEL}"
  exit 1
fi

log "Starting PostgreSQL backup: container=${CONTAINER}, stamp=${STAMP}"

for DB in "${DATABASES[@]}"; do
  dump_file="$(mktemp "/tmp/${DB}_${STAMP}.XXXXXX.dump")"
  remote_path="${RCLONE_REMOTE}:${R2_BUCKET}/${R2_PREFIX}/${STAMP}/${DB}_${STAMP}.dump"

  log "Dumping ${DB} to ${dump_file}"
  docker exec "$CONTAINER" pg_dump -U "$POSTGRES_USER" -Fc -d "$DB" > "$dump_file"

  dump_size="$(wc -c < "$dump_file")"
  log "Uploading ${DB} (${dump_size} bytes) to ${remote_path}"

  if [ "$S3_NO_CHECK_BUCKET" = "1" ]; then
    rclone copyto "$dump_file" "$remote_path" --s3-no-check-bucket
  else
    rclone copyto "$dump_file" "$remote_path"
  fi

  rm -f "$dump_file"
  dump_file=""
  log "Completed ${DB}"
done

log "PostgreSQL backup completed successfully"
