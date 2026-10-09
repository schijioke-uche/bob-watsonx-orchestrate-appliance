#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
source "$SCRIPT_DIR/tls-control.sh" 

#===============================================================================
# Clean model execution for IBM Bob
#===============================================================================

export NODE_OPTIONS=" \
