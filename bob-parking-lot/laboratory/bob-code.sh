#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 


#==================================================================================
# This script uses IBM Bob to generate code based on the provided prompt.
#==================================================================================

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Write a bash function that checks whether oc is installed.}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode code \
  --accept-license true \
  --hide-intermediary-output
