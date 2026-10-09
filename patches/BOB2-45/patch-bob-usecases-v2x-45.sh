#!/usr/bin/env bash
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
command -v python3 >/dev/null 2>&1 || { printf '%s\n' 'Python 3.9+ is required.' >&2; exit 2; }
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,9) else 2)' || { printf '%s\n' 'Python 3.9+ is required.' >&2; exit 2; }
exec python3 "$HERE/repair.py" "$@"
