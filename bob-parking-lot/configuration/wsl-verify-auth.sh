#!/usr/bin/env bash

# WSL Ubuntu Compatible - Verify Bob CLI Authentication

echo "==================================="
echo "Bob CLI Authentication Verification (WSL)"
echo "==================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Project .env (git-ignored) is the single source of the API key
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/../load-env.sh"

# Check if Bob is installed
echo -e "${BLUE}1. Checking Bob installation...${NC}"
if command -v bob >/dev/null 2>&1; then
    BOB_VERSION=$(bob --version 2>&1 | head -1)
    echo -e "${GREEN}✓ Bob is installed: $BOB_VERSION${NC}"
else
    echo -e "${RED}✗ Bob CLI not found${NC}"
    echo "Install with: npm install -g bobshell"
    exit 1
fi
echo ""

# Check for API key in environment
echo -e "${BLUE}2. Checking for API key in environment...${NC}"
if [ -n "$BOB_API_KEY" ]; then
    echo -e "${GREEN}✓ BOB_API_KEY is set in environment${NC}"
    echo "   Key: ${BOB_API_KEY:0:3}***"
else
    echo -e "${YELLOW}⚠ BOB_API_KEY not set in environment${NC}"
    
    # Check config file
    if [ -f ~/.bob/config.json ]; then
        echo -e "${YELLOW}  Checking ~/.bob/config.json...${NC}"
        if grep -q "apiKey" ~/.bob/config.json 2>/dev/null; then
            echo -e "${GREEN}✓ API key found in config file${NC}"
        fi
    fi
    
    # Check .env file
    if [ -f ~/.bob/.env ]; then
        echo -e "${YELLOW}  Checking ~/.bob/.env...${NC}"
        if grep -q "BOB_API_KEY" ~/.bob/.env 2>/dev/null; then
            echo -e "${GREEN}✓ API key found in .env file${NC}"
            echo "  Run: source ~/.bob/.env"
        fi
    fi
fi
echo ""

# Check for token file
echo -e "${BLUE}3. Checking for authentication token...${NC}"
if [ -f ~/.bob/token.json ]; then
    echo -e "${GREEN}✓ Token file exists: ~/.bob/token.json${NC}"
    
    # Check if token is expired (if jq is available)
    if command -v jq >/dev/null 2>&1; then
        EXPIRES_AT=$(jq -r '.expires_at // 0' ~/.bob/token.json 2>/dev/null)
        CURRENT_TIME=$(date +%s)
        
        if [ "$EXPIRES_AT" -gt "$CURRENT_TIME" ] 2>/dev/null; then
            REMAINING=$((EXPIRES_AT - CURRENT_TIME))
            HOURS=$((REMAINING / 3600))
            echo -e "${GREEN}✓ Token is valid (expires in ${HOURS} hours)${NC}"
        else
            echo -e "${YELLOW}⚠ Token may be expired${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ No token file found${NC}"
fi
echo ""

# Test Bob API connectivity
echo -e "${BLUE}4. Testing Bob API connectivity...${NC}"

# Load environment if available
if [ -f ~/.bob/.env ]; then
    source ~/.bob/.env
fi

# Try to get API key from config if not in env
if [ -z "$BOB_API_KEY" ] && [ -f ~/.bob/config.json ]; then
    BOB_API_KEY=$(grep -o '"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"' ~/.bob/config.json 2>/dev/null | cut -d'"' -f4)
fi

if [ -n "$BOB_API_KEY" ]; then
    echo "Testing with API key..."
    
    # Test health endpoint
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $BOB_API_KEY" \
        -H "X-API-Key: $BOB_API_KEY" \
        --max-time 10 \
        --connect-timeout 5 \
        https://api.us-east.bob.ibm.com/health 2>/dev/null || echo "000")
    
    if [[ "$HTTP_CODE" =~ ^(200|204)$ ]]; then
        echo -e "${GREEN}✓ Successfully connected to Bob API (HTTP $HTTP_CODE)${NC}"
    elif [ "$HTTP_CODE" = "401" ]; then
        echo -e "${RED}✗ Authentication failed (HTTP 401)${NC}"
        echo "  Your API key may be invalid or expired"
    elif [ "$HTTP_CODE" = "403" ]; then
        echo -e "${RED}✗ Access forbidden (HTTP 403)${NC}"
        echo "  Your API key may not have proper permissions"
    elif [ "$HTTP_CODE" = "000" ]; then
        echo -e "${RED}✗ Cannot reach Bob API${NC}"
        echo "  Check VPN connection on Windows"
    else
        echo -e "${YELLOW}⚠ Unexpected response (HTTP $HTTP_CODE)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No API key available to test${NC}"
fi
echo ""

# Try running Bob with --help
echo -e "${BLUE}5. Testing Bob CLI command...${NC}"
if timeout 5 bob --help >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Bob CLI responds to commands${NC}"
else
    echo -e "${RED}✗ Bob CLI not responding${NC}"
fi
echo ""

# Check network connectivity
echo -e "${BLUE}6. Checking network connectivity...${NC}"
if timeout 2 ping -c 1 ibm.com >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Can reach IBM network${NC}"
else
    echo -e "${YELLOW}⚠ Cannot reach IBM network${NC}"
    echo "  Connect VPN on Windows (not in WSL)"
fi
echo ""

# Check Windows VPN status
echo -e "${BLUE}7. Checking Windows VPN status...${NC}"
if command -v powershell.exe >/dev/null 2>&1; then
    VPN_STATUS=$(powershell.exe -Command "Get-NetAdapter | Where-Object {(\$_.Status -eq 'Up') -and ((\$_.InterfaceDescription -like '*VPN*') -or (\$_.InterfaceDescription -like '*Cisco*') -or (\$_.InterfaceDescription -like '*Zscaler*'))} | Select-Object -First 1 -ExpandProperty Name" 2>/dev/null)
    
    if [ -n "$VPN_STATUS" ]; then
        echo -e "${GREEN}✓ VPN connected on Windows: $VPN_STATUS${NC}"
    else
        echo -e "${YELLOW}⚠ No VPN connection detected on Windows${NC}"
        echo "  Open VPN client on Windows and connect"
    fi
else
    echo -e "${YELLOW}⚠ Cannot check Windows VPN status${NC}"
fi
echo ""

# Summary
echo "==================================="
echo "Authentication Status Summary"
echo "==================================="
echo ""

# Determine overall status
AUTHENTICATED=false

if [ -n "$BOB_API_KEY" ] && [[ "$HTTP_CODE" =~ ^(200|204)$ ]]; then
    AUTHENTICATED=true
    echo -e "${GREEN}✓ YOU ARE AUTHENTICATED${NC}"
    echo ""
    echo "You can now use Bob CLI:"
    echo "  bob 'your task here'"
elif [ -f ~/.bob/token.json ]; then
    echo -e "${YELLOW}⚠ PARTIALLY AUTHENTICATED${NC}"
    echo ""
    echo "You have a token file, but API connectivity test failed."
    echo "Try running Bob to see if it works:"
    echo "  bob 'hello'"
else
    echo -e "${RED}✗ NOT AUTHENTICATED${NC}"
    echo ""
    echo "To authenticate, run:"
    echo "  ./wsl-configure-bob.sh"
    echo ""
    echo "Or set your API key manually:"
    echo "  # Add BOB_API_KEY to the project .env (use-cases/<project>/.env), then:"
    echo "  source $SCRIPT_DIR/../load-env.sh"
fi

echo ""
echo "==================================="
echo "WSL-Specific Notes"
echo "==================================="
echo ""
echo "• WSL uses Windows network stack"
echo "• VPN must be connected on Windows"
echo "• WSL automatically inherits Windows VPN"
echo "• If VPN works on Windows, it works in WSL"
echo ""

if [ "$AUTHENTICATED" = false ]; then
    echo "Next steps:"
    echo "  1. Connect VPN on Windows"
    echo "  2. Run: ./wsl-test-vpn.sh"
    echo "  3. Run: source ~/.bob/export-env.sh"
    echo "  4. Run: bob 'hello'"
fi

echo ""
echo "==================================="

# Exit with appropriate code
if [ "$AUTHENTICATED" = true ]; then
    exit 0
else
    exit 1
fi

# Made with Bob
