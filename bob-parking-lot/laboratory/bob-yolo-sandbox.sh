#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env
#===============================================================================
# Analyze the current repository using IBM Bob in YOLO sandbox mode
#===============================================================================

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Create a throwaway test script and run it.}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode code \
  --accept-license true \
  --sandbox \
  --approval-mode yolo \
  --trust
