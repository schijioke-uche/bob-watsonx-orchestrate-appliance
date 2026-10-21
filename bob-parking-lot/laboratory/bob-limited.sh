#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env

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
