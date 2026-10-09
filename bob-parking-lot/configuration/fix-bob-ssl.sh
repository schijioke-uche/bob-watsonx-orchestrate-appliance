#!/bin/bash
# Fix Bob SSL Certificate Issues

echo "=== Bob SSL Certificate Fix ==="
echo ""
echo "This script helps configure Node.js to trust your corporate certificates."
echo ""

# Check if running in corporate network
echo "Step 1: Locate your corporate CA certificate"
echo "Common locations:"
echo "  - /etc/ssl/certs/ca-certificates.crt (Linux)"
echo "  - /etc/pki/tls/certs/ca-bundle.crt (RHEL/CentOS)"
echo "  - C:/Users/$USER/AppData/Local/mitmproxy/mitmproxy-ca-cert.pem (Windows with proxy)"
echo ""

# Option 1: Use system certificates
echo "Option 1: Use system CA bundle"
echo "Run: export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt"
echo ""

# Option 2: Disable SSL verification (NOT RECOMMENDED)
echo "Option 2: Disable SSL verification (NOT RECOMMENDED for production)"
echo "Run: export NODE_TLS_REJECT_UNAUTHORIZED=0"
echo ""

# Option 3: Add to shell profile
echo "Option 3: Make it permanent by adding to ~/.bashrc or ~/.zshrc:"
echo "echo 'export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt' >> ~/.bashrc"
echo ""

echo "After setting the environment variable, run Bob again:"
echo "./bob-limited.sh"

# Made with Bob
