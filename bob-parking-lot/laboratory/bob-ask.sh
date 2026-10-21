#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Explain what vLLM is in one paragraph.}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode ask \
  --max-coins "${MAX_COINS:-100}" \
  --accept-license true \
  --hide-intermediary-output
