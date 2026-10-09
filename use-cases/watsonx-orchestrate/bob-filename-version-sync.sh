#!/usr/bin/env bash
set -Eeuo pipefail
# BOB2-41 MANAGED ENTRYPOINT - @Author: Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
_BOB2_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${_BOB2_ROOT}/.bob/runtime/bob-v2/load-env.sh"
bob2_load_environment "${_BOB2_ROOT}"
case "${1:---sync}" in
  --sync|--print-version) exec python3 "${_BOB2_ROOT}/.bob/runtime/bob-v2/runtime.py" sync --root "${_BOB2_ROOT}" ;;
  --check|--dry-run) exec python3 "${_BOB2_ROOT}/.bob/runtime/bob-v2/runtime.py" sync --root "${_BOB2_ROOT}" --check ;;
  --help|-h) printf '%s\n' 'Usage: bob-filename-version-sync.sh [--sync|--check|--print-version]' ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac
