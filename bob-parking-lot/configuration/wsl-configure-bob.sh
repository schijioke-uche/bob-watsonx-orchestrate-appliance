#!/usr/bin/env bash

# WSL Ubuntu Compatible - Configure Bob CLI with API Key

echo "==================================="
echo "Bob CLI Configuration (WSL)"
echo "==================================="
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LOADER_PATH="$SCRIPT_DIR/../load-env.sh"
# Credentials are read from the project .env - never hardcode them here.
source "$LOADER_PATH"
if [ -z "${BOB_API_KEY:-}" ]; then
    echo "Error: BOB_API_KEY is not set. Add it to the project .env (use-cases/<project>/.env) or set BOB_ENV_FILE." >&2
    exit 1
fi
BOB_DIR="$HOME/.bob"

echo "Configuring Bob CLI for non-interactive mode in WSL..."
echo ""

# Create .bob directory
mkdir -p "$BOB_DIR"

# Method 1: Environment variable
echo -e "${GREEN}Setting environment variable...${NC}"
export BOB_API_KEY="$BOB_API_KEY"
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Method 2: Save to .env file
echo -e "${GREEN}Creating .env file...${NC}"
cat > "$BOB_DIR/.env" <<EOF
BOB_API_KEY=$BOB_API_KEY
NODE_TLS_REJECT_UNAUTHORIZED=0
EOF
chmod 600 "$BOB_DIR/.env"

# Method 3: Create export script
echo -e "${GREEN}Creating export script...${NC}"
cat > "$BOB_DIR/export-env.sh" <<EOF
#!/usr/bin/env bash
export BOB_API_KEY="$BOB_API_KEY"
export NODE_TLS_REJECT_UNAUTHORIZED=0
EOF
chmod 700 "$BOB_DIR/export-env.sh"

# Method 4: Create config.json
echo -e "${GREEN}Creating config.json...${NC}"
cat > "$BOB_DIR/config.json" <<EOF
{
  "apiKey": "$BOB_API_KEY",
  "apiEndpoint": "https://api.us-east.bob.ibm.com",
  "region": "us-east"
}
EOF
chmod 600 "$BOB_DIR/config.json"

# Method 5: Create wrapper script
echo -e "${GREEN}Creating wrapper script...${NC}"
cat > "$BOB_DIR/bob-cli.sh" <<'EOF'
#!/usr/bin/env bash
# Bob CLI wrapper with API key for WSL

# Load environment
if [ -f ~/.bob/.env ]; then
    source ~/.bob/.env
fi

# Run bob with all arguments
bob "$@"
EOF
chmod +x "$BOB_DIR/bob-cli.sh"

# Add to shell profile
echo ""
echo -e "${GREEN}Adding to shell profile...${NC}"

# Detect shell
SHELL_RC=""
if [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
else
    # Default to bashrc
    SHELL_RC="$HOME/.bashrc"
fi

if [ -f "$SHELL_RC" ]; then
    # Check if already added
    if ! grep -q "source ~/.bob/export-env.sh" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# Bob CLI Configuration" >> "$SHELL_RC"
        echo "source ~/.bob/export-env.sh" >> "$SHELL_RC"
        echo -e "${GREEN}✓ Added to $SHELL_RC${NC}"
    else
        echo -e "${YELLOW}Already configured in $SHELL_RC${NC}"
    fi
fi

echo ""
echo "==================================="
echo "Configuration Complete!"
echo "==================================="
echo ""
echo "Bob API Key: loaded from the project .env (${BOB_API_KEY:0:3}***)"
echo ""
echo "To use Bob CLI in WSL:"
echo ""
echo "Option 1: Source environment (recommended)"
echo "  source ~/.bob/export-env.sh"
echo "  bob 'your task here'"
echo ""
echo "Option 2: Use wrapper script"
echo "  ~/.bob/bob-cli.sh 'your task here'"
echo ""
echo "Option 3: Load the key from the project .env"
echo "  source $LOADER_PATH && bob 'your task here'"
echo ""
echo "Option 4: Reload shell (to apply profile changes)"
echo "  source ~/.bashrc  # or source ~/.zshrc"
echo "  bob 'your task here'"
echo ""
echo -e "${YELLOW}WSL Note: VPN must be connected on Windows (not in WSL)${NC}"
echo ""

# Test connectivity
echo "Testing connectivity from WSL..."
if timeout 2 ping -c 1 ibm.com >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Can reach IBM network${NC}"
    echo ""
    echo "Testing Bob CLI..."
    if command -v bob >/dev/null 2>&1; then
        BOB_VERSION=$(bob --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)
        if [ -n "$BOB_VERSION" ]; then
            echo -e "${GREEN}✓ Bob CLI is working (v$BOB_VERSION)${NC}"
            echo ""
            echo "Try it now:"
            echo "  source ~/.bob/export-env.sh"
            echo "  bob 'hello'"
        fi
    else
        echo -e "${YELLOW}⚠ Bob CLI not found in PATH${NC}"
        echo ""
        echo "To install Bob CLI:"
        echo "  npm install -g bobshell"
        echo ""
        echo "Or check if bob is installed:"
        echo "  which bob"
    fi
else
    echo -e "${YELLOW}⚠ Cannot reach IBM network${NC}"
    echo ""
    echo "Connect VPN on Windows first:"
    echo "  1. Open VPN client on Windows (Cisco AnyConnect/Zscaler)"
    echo "  2. Connect to IBM network"
    echo "  3. WSL will automatically use Windows VPN"
    echo "  4. Run: ./wsl-test-vpn.sh to verify"
fi

echo ""
echo "==================================="
echo "Quick Start Commands"
echo "==================================="
echo ""
echo "# Test VPN connection"
echo "./wsl-test-vpn.sh"
echo ""
echo "# Verify Bob authentication"
echo "./wsl-verify-auth.sh"
echo ""
echo "# Use Bob"
echo "source ~/.bob/export-env.sh && bob 'hello'"
echo ""

# Made with Bob
