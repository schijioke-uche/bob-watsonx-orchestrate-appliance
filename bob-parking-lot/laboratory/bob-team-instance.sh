#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
#===============================================================================
# Analyze workspace using IBM Bob with team and instance context
#===============================================================================

BOB_BIN="${BOB_BIN:-bob}"
: "${BOB_TEAM_ID:?Set BOB_TEAM_ID first}"
: "${BOB_INSTANCE_ID:?Set BOB_INSTANCE_ID first}"
PROMPT="${*:-Analyze this workspace.}"

"$BOB_BIN" "$PROMPT" \
  --team-id "$BOB_TEAM_ID" \
  --instance-id "$BOB_INSTANCE_ID" \
  --chat-mode code \
  --accept-license true \
  --hide-intermediary-output
