#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
#===============================================================================
# Start interactive session with IBM Bob
#===============================================================================

BOB_BIN="${BOB_BIN:-bob}"
INITIAL_PROMPT="${*:-What quantum computing code should I write?}"

"$BOB_BIN" \
  --chat-mode code \
  --accept-license true \
  --prompt-interactive "$INITIAL_PROMPT"
