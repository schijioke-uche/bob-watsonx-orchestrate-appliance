#!/usr/bin/env bash
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$HERE/../BOB2-45/patch-bob-usecases-v2x-45.sh" --only WXA "$@"
