#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env

#====================================================================================
# This script uses IBM Bob to perform an automatic edit based on the provided prompt.
#====================================================================================

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Make a minimal safe edit and explain the diff.}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode code \
  --accept-license true \
  --approval-mode auto_edit \
  --trust
