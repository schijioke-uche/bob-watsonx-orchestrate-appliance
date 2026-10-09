#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 

#====================================================================================
# This script uses IBM Bob to interactively ask questions based on the provided prompt.
#====================================================================================

BOB_BIN="${BOB_BIN:-bob}"

"$BOB_BIN" \
  --chat-mode ask \
  --accept-license true
