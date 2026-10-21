#!/usr/bin/env bash

# WSL Bob CLI Wrapper - Easy way to run Bob with API key

# Project .env (git-ignored) is the primary source of the API key
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/../load-env.sh"

# Fallback: per-user Bob environment
if [ -z "${BOB_API_KEY:-}" ] && [ -f ~/.bob/.env ]; then
    source ~/.bob/.env
fi

# If API key not in environment, try to load from config
if [ -z "$BOB_API_KEY" ] && [ -f ~/.bob/config.json ]; then
    BOB_API_KEY=$(grep -o '"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"' ~/.bob/config.json 2>/dev/null | cut -d'"' -f4)
    export BOB_API_KEY
fi

# Set SSL workaround
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Check if Bob is installed
if ! command -v bob >/dev/null 2>&1; then
    echo "Error: Bob CLI not found"
    echo "Install with: npm install -g bobshell"
    exit 1
fi

# Check if API key is set
if [ -z "$BOB_API_KEY" ]; then
    echo "Error: BOB_API_KEY not set"
    echo "Run: ./wsl-configure-bob.sh"
    exit 1
fi

# Run bob with all arguments
bob "$@"

# Made with Bob
