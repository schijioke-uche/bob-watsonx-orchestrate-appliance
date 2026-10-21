#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env
#===============================================================================
# Analyze the current repository using IBM Bob with trusted code
#===============================================================================

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Analyze the current repository and summarize the deployment flow.}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode code \
  --accept-license true \
  --trust \
  --hide-intermediary-output
