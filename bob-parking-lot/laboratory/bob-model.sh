#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env
#===============================================================================
# Model execution for IBM Bob
#===============================================================================

BOB_BIN="${BOB_BIN:-bob}"
MODEL_NAME="${BOB_MODEL:-}"
PROMPT="${*:-Explain this project.}"

if [[ -n "$MODEL_NAME" ]]; then
  "$BOB_BIN" "$PROMPT" \
    --model "$MODEL_NAME" \
    --chat-mode ask \
    --accept-license true \
    --hide-intermediary-output
else
  "$BOB_BIN" "$PROMPT" \
    --chat-mode ask \
    --accept-license true \
    --hide-intermediary-output
fi
