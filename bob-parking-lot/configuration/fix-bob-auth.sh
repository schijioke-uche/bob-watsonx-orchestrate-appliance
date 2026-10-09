#!/bin/bash

echo "=== Bob Authentication Fix ==="
echo ""

# Check if bob-limited.sh exists
if [ ! -f "./bob-limited.sh" ]; then
    echo "Error: bob-limited.sh not found in current directory"
    echo "Please run this script from the ibm-bob-operations directory"
    exit 1
fi

echo "Attempting to fix Bob authentication..."
echo ""

# Option 1: Try with NODE_TLS_REJECT_UNAUTHORIZED
echo "Method 1: Running with SSL workaround..."
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Check if we need to update Bob
echo "Checking Bob version..."
bob --version 2>/dev/null || echo "Bob CLI not found in PATH"

echo ""
echo "Trying to authenticate with Bob..."
echo ""

# Try running bob with proper environment
NODE_TLS_REJECT_UNAUTHORIZED=0 ./bob-limited.sh

echo ""
echo "If authentication still fails, try these alternatives:"
echo ""
echo "1. Update Bob to latest version:"
echo "   npm install -g bobshell@latest"
echo ""
echo "2. Clear Bob cache and try again:"
echo "   rm -rf ~/.bob/cache"
echo "   ./bob-limited.sh"
echo ""
echo "3. Use full Bob instead of bob-limited:"
echo "   bob"
echo ""
echo "4. Check if you're on IBM network/VPN"
echo "   The authentication requires access to IBM internal services"

# Made with Bob
