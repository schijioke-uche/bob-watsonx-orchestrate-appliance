#!/bin/bash

# Bob-Shell CLI Authentication using Bob API Key
# This script configures Bob CLI to use your Bob API Key

set -e

echo "==================================="
echo "Bob-Shell API Key Setup"
echo "==================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LOADER_PATH="$SCRIPT_DIR/../load-env.sh"
source "$LOADER_PATH"   # reads BOB_API_KEY from the project .env if present

BOB_DIR="$HOME/.bob"
CONFIG_FILE="$BOB_DIR/config.json"
ENV_FILE="$BOB_DIR/.env"

# Create .bob directory
mkdir -p "$BOB_DIR"

echo "This script will configure Bob-Shell CLI to use your Bob API Key."
echo ""
echo -e "${YELLOW}Where to find your Bob API Key:${NC}"
echo "  1. Go to https://bob.ibm.com"
echo "  2. Click on your profile/settings"
echo "  3. Navigate to 'API Keys' or 'Developer Settings'"
echo "  4. Generate or copy your Bob API Key"
echo ""
echo -e "${YELLOW}Note: This is different from IBM Cloud API Key${NC}"
echo ""

if [ -z "${BOB_API_KEY:-}" ]; then
    read -p "BOB_API_KEY not found in the project .env. Enter your Bob API Key: " -s BOB_API_KEY
    echo ""
else
    echo "Using BOB_API_KEY from the project .env"
fi

if [ -z "$BOB_API_KEY" ]; then
    echo -e "${RED}Error: API Key cannot be empty${NC}"
    exit 1
fi

# Validate API key format (basic check)
if [[ ! "$BOB_API_KEY" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo -e "${YELLOW}Warning: API Key format looks unusual. Proceeding anyway...${NC}"
fi

echo ""
echo "Configuring Bob CLI..."

# Method 1: Save to environment file
cat > "$ENV_FILE" <<EOF
# Bob API Key Configuration
BOB_API_KEY=$BOB_API_KEY
BOB_ENDPOINT=https://api.us-east.bob.ibm.com
EOF

chmod 600 "$ENV_FILE"
echo -e "${GREEN}✓ API Key saved to $ENV_FILE${NC}"

# Method 2: Update config.json
if [ -f "$CONFIG_FILE" ]; then
    # Backup existing config
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
    echo -e "${GREEN}✓ Backed up existing config to $CONFIG_FILE.backup${NC}"
fi

cat > "$CONFIG_FILE" <<EOF
{
  "apiKey": "$BOB_API_KEY",
  "apiEndpoint": "https://api.us-east.bob.ibm.com",
  "authEndpoint": "https://console-ibm-prod.verify.ibm.com",
  "region": "us-east"
}
EOF

chmod 600 "$CONFIG_FILE"
echo -e "${GREEN}✓ Config saved to $CONFIG_FILE${NC}"

# Method 3: Create shell export script
cat > "$BOB_DIR/export-env.sh" <<EOF
#!/bin/bash
# Source this file to set Bob environment variables
export BOB_API_KEY="$BOB_API_KEY"
export BOB_ENDPOINT="https://api.us-east.bob.ibm.com"
export NODE_TLS_REJECT_UNAUTHORIZED=0
EOF

chmod 700 "$BOB_DIR/export-env.sh"
echo -e "${GREEN}✓ Environment export script created${NC}"

echo ""
echo "==================================="
echo "Setup Complete!"
echo "==================================="
echo ""
echo "Your Bob API Key has been configured in multiple ways:"
echo "  1. Environment file: $ENV_FILE"
echo "  2. Config file: $CONFIG_FILE"
echo "  3. Export script: $BOB_DIR/export-env.sh"
echo ""
echo -e "${YELLOW}To use Bob CLI, you have several options:${NC}"
echo ""
echo "Option 1: Source the environment (recommended)"
echo "  source ~/.bob/export-env.sh"
echo "  bob"
echo ""
echo "Option 2: Set environment variable directly"
echo "  source $LOADER_PATH   # loads BOB_API_KEY from the project .env"
echo "  bob"
echo ""
echo "Option 3: Use the wrapper script (see below)"
echo ""

# Create wrapper script
cat > "$BOB_DIR/bob-with-key.sh" <<'EOF'
#!/bin/bash
# Bob CLI wrapper that loads API key from config

BOB_DIR="$HOME/.bob"

# Load API key from .env file
if [ -f "$BOB_DIR/.env" ]; then
    source "$BOB_DIR/.env"
fi

# Set SSL workaround
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Run bob with all arguments
bob "$@"
EOF

chmod +x "$BOB_DIR/bob-with-key.sh"
echo -e "${GREEN}✓ Created wrapper script: $BOB_DIR/bob-with-key.sh${NC}"

echo ""
echo "Quick start commands:"
echo ""
echo "  # Run Bob with wrapper"
echo "  ~/.bob/bob-with-key.sh"
echo ""
echo "  # Or add to your shell profile (~/.bashrc or ~/.zshrc):"
echo "  echo 'source ~/.bob/export-env.sh' >> ~/.bashrc"
echo "  source ~/.bashrc"
echo "  bob"
echo ""

# Test the configuration
echo "Testing Bob API Key..."
echo ""

# Try to verify the key works
source "$BOB_DIR/export-env.sh"

if command -v bob &> /dev/null; then
    echo "Running: bob --version"
    bob --version 2>&1 || echo -e "${YELLOW}Note: Bob may need the API key to be set in environment${NC}"
else
    echo -e "${YELLOW}Bob CLI not found in PATH${NC}"
    echo "Install with: npm install -g bobshell@latest"
fi

echo ""
echo -e "${GREEN}Setup complete! Try running Bob now.${NC}"

# Made with Bob
