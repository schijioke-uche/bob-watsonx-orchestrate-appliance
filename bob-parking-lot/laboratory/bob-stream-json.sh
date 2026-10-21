#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env
#===============================================================================
# Stream project analysis as JSON using IBM Bob
#===============================================================================

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Analyze this project and stream progress as JSON.}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode code \
  --accept-license true \
  --output-format stream-json
