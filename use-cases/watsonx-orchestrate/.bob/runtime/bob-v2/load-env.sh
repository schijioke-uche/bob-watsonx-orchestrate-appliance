#!/usr/bin/env bash
# Environment is trusted project configuration. The installer never sources it.
# This file is sourced by managed root wrappers, not executed by the patch.
bob2_load_environment() {
  local root="$1" saved_bin="${BOB2_BIN:-${BOB_BIN:-}}"
  if [[ "${BOB2_ENV_LOADED_FOR:-}" != "$root" ]]; then
    [[ -f "$root/.env" ]] || { printf '%s\n' 'ERROR: This appliance requires its existing .env file.' >&2; return 1; }
    if [[ -f "$root/.env" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "$root/.env"
      set +a
    fi
    if [[ -f "$root/.bob/bob-v2.env" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "$root/.bob/bob-v2.env"
      set +a
    fi
    export BOB2_ENV_LOADED_FOR="$root"
  fi
  if [[ -n "$saved_bin" ]]; then export BOB_BIN="$saved_bin"; fi
  # Match the benchmark's source-once guard without importing quantum settings.
  export BOB2_PROJECT_ENV_LOADED=1
  export SCRIPT_DIR="$root"
  export PYTHONDONTWRITEBYTECODE=1
  command -v python3 >/dev/null 2>&1 || { printf '%s\n' 'ERROR: Python 3.9+ is required.' >&2; return 1; }
}
