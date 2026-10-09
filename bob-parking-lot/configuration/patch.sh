#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="patch-v7A.sh"
BOB_DIR="${BOB_DIR:-$HOME/.bob}"
BACKUP_ROOT="${BOB_BACKUP_ROOT:-$BOB_DIR/backups}"
PATTERN='^[[:space:]]*(export[[:space:]]+)?NODE_TLS_REJECT_UNAUTHORIZED=0[[:space:]]*$'

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

warn() {
  printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2
}

fail() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./patch.sh

Purpose:
  Removes insecure Node/Bob TLS bypass settings that cause this warning:
    NODE_TLS_REJECT_UNAUTHORIZED=0 makes TLS connections insecure

Behavior:
  - Scans ~/.bob by default.
  - Ignores backup folders.
  - Backs up changed files under ~/.bob/backups/<timestamp>/.
  - Removes only exact NODE_TLS_REJECT_UNAUTHORIZED=0 lines.
  - Unsets NODE_TLS_REJECT_UNAUTHORIZED in the current patch process.
  - Does not delete credentials or Bob session files.

Optional environment variables:
  BOB_DIR=/custom/path/.bob ./patch.sh
  BOB_BACKUP_ROOT=/custom/backup/path ./patch.sh
USAGE
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    fail "unknown argument: $1. Use --help."
    ;;
esac

[[ -d "$BOB_DIR" ]] || fail "Bob config directory not found: $BOB_DIR"

unset NODE_TLS_REJECT_UNAUTHORIZED

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$BACKUP_ROOT/$stamp"
changed_count=0
scanned_count=0

log "Scanning Bob config directory: $BOB_DIR"

while IFS= read -r -d '' file; do
  scanned_count=$((scanned_count + 1))

  if grep -Eq "$PATTERN" "$file"; then
    mkdir -p "$backup_dir"
    rel_path="${file#$BOB_DIR/}"
    mkdir -p "$backup_dir/$(dirname "$rel_path")"
    cp -p "$file" "$backup_dir/$rel_path"
    sed -i -E "/$PATTERN/d" "$file"
    changed_count=$((changed_count + 1))
    log "Cleaned: $file"
  fi
done < <(
  find "$BOB_DIR" \
    \( -path "$BOB_DIR/backup-*" -o -path "$BOB_DIR/backups" -o -path "$BOB_DIR/backups/*" \) -prune \
    -o -type f -print0
)

log "Scanned files: $scanned_count"
log "Changed files: $changed_count"

if (( changed_count > 0 )); then
  log "Backup saved to: $backup_dir"
else
  log "No active insecure TLS bypass lines found."
fi

remaining="$(grep -RIn "NODE_TLS_REJECT_UNAUTHORIZED" "$BOB_DIR" --exclude-dir='backup-*' --exclude-dir='backups' 2>/dev/null || true)"
if [[ -n "$remaining" ]]; then
  warn "NODE_TLS_REJECT_UNAUTHORIZED still appears in active Bob config:"
  printf '%s\n' "$remaining" >&2
  warn "Review these lines manually; this script only removes exact NODE_TLS_REJECT_UNAUTHORIZED=0 assignments."
else
  log "Verified: no active NODE_TLS_REJECT_UNAUTHORIZED entries remain under $BOB_DIR."
fi

if command -v bob >/dev/null 2>&1; then
  log "Bob path: $(command -v bob)"
else
  warn "bob command not found on PATH."
fi

log "Patch complete. Open a new shell or run: unset NODE_TLS_REJECT_UNAUTHORIZED"
