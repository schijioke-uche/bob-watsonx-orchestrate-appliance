#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
#===============================================================================
# Analyze the current repository using IBM Bob with extra directories
#===============================================================================

BOB_BIN="${BOB_BIN:-bob}"
PROMPT="${1:-Analyze the deployment scripts and Dockerfiles.}"
BOB_INCLUDED_DIRECTORY="${2:-${HOME}/VLLM/vllm-on-redhat-openshift/CPU}"

"$BOB_BIN" "$PROMPT" \
  --chat-mode code \
  --accept-license true \
  --include-directories "$BOB_INCLUDED_DIRECTORY" \
  --hide-intermediary-output
