#!/usr/bin/env bash
set -Eeuo pipefail

# Security: never allow Bob/Node to run with TLS verification disabled.
# Bob CLI - No Browser Authentication
# Pure terminal authentication for WSL Ubuntu, RHEL, CentOS, Fedora

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

source "$SCRIPT_DIR/tls-control.sh"

# Your Bob API Key
set -a
source "$SCRIPT_DIR/.env"
set +a

export BOB_API_KEY="${BOB_API_KEY}"

# Bob configuration
export BOB_ENDPOINT="${BOB_ENDPOINT}"
export BOB_NO_BROWSER=1
export BOB_AUTH_METHOD="apikey"

# Disable browser opening
export BROWSER=none
export DISPLAY=

# Run bob with all arguments
exec bob "$@"

# Made with Bob
