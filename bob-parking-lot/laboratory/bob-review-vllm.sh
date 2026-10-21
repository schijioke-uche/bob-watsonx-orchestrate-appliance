#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env
#===============================================================================
# Review deploy-vllm-openshift.sh for production safety using IBM Bob
#===============================================================================


BOB_BIN="${BOB_BIN:-bob}"
PROJECT_DIR="${1:-$PWD}"

cd "$PROJECT_DIR"

"$BOB_BIN" "Review deploy-vllm-openshift.sh for production safety. Focus on secrets, OpenShift resources, route names, Dockerfile selection, and rollback risk. Do not modify files unless asked." \
  --chat-mode code \
  --accept-license true \
  --trust \
  --hide-intermediary-output
