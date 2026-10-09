#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
#===============================================================================
# Resume latest execution for IBM Bob
#===============================================================================

BOB_BIN="${BOB_BIN:-bob}"

"$BOB_BIN" --resume latest
