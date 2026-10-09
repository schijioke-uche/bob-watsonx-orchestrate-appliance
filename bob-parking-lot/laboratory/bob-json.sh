#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 

#====================================================================================
# This script uses IBM Bob to return a JSON summary of the repository.
#====================================================================================

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${*:-Return a JSON summary of this repository.}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode ask \
  --accept-license true \
  --output-format json
