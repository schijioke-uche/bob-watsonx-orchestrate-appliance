#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
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
