#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 

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
