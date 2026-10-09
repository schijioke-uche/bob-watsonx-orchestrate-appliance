#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 

#====================================================================================
# Limited prompt execution for IBM Bob
#====================================================================================


BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Give a short answer only.}"
MAX_COINS="${MAX_COINS:-100}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode ask \
  --max-coins "$MAX_COINS" \
  --accept-license true \
  --hide-intermediary-output
