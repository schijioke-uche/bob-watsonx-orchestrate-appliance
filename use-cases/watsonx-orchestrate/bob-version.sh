#!/usr/bin/env bash
set -Eeuo pipefail
# BOB2-41 MANAGED ENTRYPOINT - @Author: Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
_BOB2_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${_BOB2_ROOT}/.bob/runtime/bob-v2/load-env.sh"
bob2_load_environment "${_BOB2_ROOT}"
BOB_VERSION="$(python3 "${_BOB2_ROOT}/.bob/runtime/bob-v2/runtime.py" version --root "${_BOB2_ROOT}")"
export BOB_VERSION
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then printf '%s\n' "$BOB_VERSION"; fi
