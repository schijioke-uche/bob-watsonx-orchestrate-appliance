#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env

#====================================================================================
# This script uses IBM Bob to perform a clean operation based on the provided prompt.
#====================================================================================

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Say hello from IBM Bob.}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode ask \
  --accept-license true \
  --hide-intermediary-output
