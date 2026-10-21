#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env
#===============================================================================
# Propose patch execution for IBM Bob
#===============================================================================

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Propose a minimal patch, but do not edit files. Show the diff only.}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode code \
  --accept-license true \
  --approval-mode default \
  --hide-intermediary-output
