#!/usr/bin/env bash
set -Eeuo pipefail

#===============================================================================
# @Author: Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
# @Description: Post-upgrade shell-profile cleaner for IBM Bob Shell 2.x
# @Version: 1.0.0
#===============================================================================

readonly SCRIPT_NAME="${0##*/}"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly LEGACY_PATTERN='^[[:space:]]*(source|\.)[[:space:]]+.*\.bob/export-env\.sh'

DRY_RUN=0
REQUESTED_SHELL="auto"

usage() {
  cat <<USAGE
Usage:
  ${SCRIPT_NAME} [--shell auto|zsh|bash|all] [--dry-run]

Purpose:
  Remove the obsolete IBM Bob 1.x line that sources ~/.bob/export-env.sh
  after upgrading to IBM Bob Shell 2.x.

Behavior:
  --shell auto   Detect the active parent/login shell and clean its RC file.
  --shell zsh    Clean ~/.zshrc.
  --shell bash   Clean ~/.bashrc.
  --shell all    Clean both ~/.zshrc and ~/.bashrc when present.
  --dry-run      Show what would change without modifying files.

Safety:
  - Creates a timestamped backup before editing.
  - Validates the updated RC file with zsh -n or bash -n.
  - Restores the backup automatically if validation fails.
USAGE
}

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --shell)
      (($# >= 2)) || fail "--shell requires auto, zsh, bash, or all"
      REQUESTED_SHELL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

case "${REQUESTED_SHELL}" in
  auto|zsh|bash|all) ;;
  *) fail "Unsupported shell selection: ${REQUESTED_SHELL}" ;;
esac

detect_active_shell() {
  local parent_shell=""
  local login_shell=""

  if command -v ps >/dev/null 2>&1; then
    parent_shell="$(ps -p "${PPID}" -o comm= 2>/dev/null | awk '{print $1}' | sed 's/^-//' || true)"
    parent_shell="${parent_shell##*/}"
    case "${parent_shell}" in
      zsh|bash)
        printf '%s\n' "${parent_shell}"
        return 0
        ;;
    esac
  fi

  login_shell="${SHELL:-}"
  login_shell="${login_shell##*/}"
  case "${login_shell}" in
    zsh|bash)
      printf '%s\n' "${login_shell}"
      return 0
      ;;
  esac

  return 1
}

validate_rc() {
  local shell_name="$1"
  local rc_file="$2"

  case "${shell_name}" in
    zsh)
      command -v zsh >/dev/null 2>&1 || fail "zsh is required to validate ${rc_file}"
      zsh -n "${rc_file}"
      ;;
    bash)
      command -v bash >/dev/null 2>&1 || fail "bash is required to validate ${rc_file}"
      bash -n "${rc_file}"
      ;;
    *)
      fail "Internal error: unsupported validator shell ${shell_name}"
      ;;
  esac
}

clean_rc() {
  local shell_name="$1"
  local rc_file="$2"
  local backup_file="${rc_file}.backup-${TIMESTAMP}"

  if [[ ! -e "${rc_file}" ]]; then
    log "Skipping ${shell_name}: file not found: ${rc_file}"
    return 0
  fi

  if [[ ! -f "${rc_file}" ]]; then
    fail "Expected a regular file: ${rc_file}"
  fi

  if ! grep -Eq "${LEGACY_PATTERN}" "${rc_file}"; then
    log "No obsolete Bob 1.x export-env.sh source line found in ${rc_file}"
    return 0
  fi

  if ((DRY_RUN)); then
    log "Would back up ${rc_file} to ${backup_file}"
    log "Would remove obsolete ~/.bob/export-env.sh source line from ${rc_file}"
    return 0
  fi

  cp -p "${rc_file}" "${backup_file}"
  log "Backup created: ${backup_file}"

  sed -i -E '/^[[:space:]]*(source|\.)[[:space:]]+.*\.bob\/export-env\.sh/d' "${rc_file}"

  if validate_rc "${shell_name}" "${rc_file}"; then
    log "Cleaned and validated: ${rc_file}"
  else
    cp -p "${backup_file}" "${rc_file}"
    fail "Validation failed for ${rc_file}; original file restored from ${backup_file}"
  fi
}

selected_shell="${REQUESTED_SHELL}"
if [[ "${selected_shell}" == "auto" ]]; then
  selected_shell="$(detect_active_shell || true)"
  [[ -n "${selected_shell}" ]] || fail "Unable to detect zsh or bash. Re-run with --shell zsh, --shell bash, or --shell all."
  log "Detected active shell: ${selected_shell}"
fi

case "${selected_shell}" in
  zsh)
    clean_rc zsh "${HOME}/.zshrc"
    ;;
  bash)
    clean_rc bash "${HOME}/.bashrc"
    ;;
  all)
    clean_rc zsh "${HOME}/.zshrc"
    clean_rc bash "${HOME}/.bashrc"
    ;;
esac

log "Post-upgrade cleanup completed successfully."
