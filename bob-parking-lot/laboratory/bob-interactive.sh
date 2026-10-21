#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env

#====================================================================================
# This script uses IBM Bob to interactively ask questions based on the provided prompt.
#====================================================================================

BOB_BIN="${BOB_BIN:-bob}"

"$BOB_BIN" \
  --chat-mode ask \
  --accept-license true
