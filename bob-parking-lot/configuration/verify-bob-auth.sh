#!/bin/bash

# Script to verify Bob CLI authentication status

echo "==================================="
echo "Bob CLI Authentication Verification"
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
if command -v bob &> /dev/null; then
    BOB_VERSION=$(bob --version 2>&1)
    echo -e "${GREEN}✓ Bob is installed: $BOB_VERSION${NC}"
else
    echo -e "${RED}✗ Bob CLI not found${NC}"
    echo "Install with: npm install -g bobshell@latest"
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
        if grep -q "apiKey" ~/.bob/config.json; then
            echo -e "${GREEN}✓ API key found in config file${NC}"
        fi
    fi
    
    # Check .env file
    if [ -f ~/.bob/.env ]; then
        echo -e "${YELLOW}  Checking ~/.bob/.env...${NC}"
        if grep -q "BOB_API_KEY" ~/.bob/.env; then
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
    
    # Check if token is expired
    if command -v python3 &> /dev/null; then
        EXPIRES_AT=$(python3 -c "import json; print(json.load(open('$HOME/.bob/token.json')).get('expires_at', 0))" 2>/dev/null)
        CURRENT_TIME=$(date +%s)
        
        if [ -n "$EXPIRES_AT" ] && [ "$EXPIRES_AT" -gt "$CURRENT_TIME" ]; then
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
    BOB_API_KEY=$(grep -o '"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"' ~/.bob/config.json | cut -d'"' -f4)
fi

if [ -n "$BOB_API_KEY" ]; then
    echo "Testing with API key..."
    
    # Test health endpoint
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $BOB_API_KEY" \
        -H "X-API-Key: $BOB_API_KEY" \
        --max-time 10 \
        https://api.us-east.bob.ibm.com/health 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
        echo -e "${GREEN}✓ Successfully connected to Bob API (HTTP $HTTP_CODE)${NC}"
    elif [ "$HTTP_CODE" = "401" ]; then
        echo -e "${RED}✗ Authentication failed (HTTP 401)${NC}"
        echo "  Your API key may be invalid or expired"
    elif [ "$HTTP_CODE" = "403" ]; then
        echo -e "${RED}✗ Access forbidden (HTTP 403)${NC}"
        echo "  Your API key may not have proper permissions"
    elif [ "$HTTP_CODE" = "000" ]; then
        echo -e "${RED}✗ Cannot reach Bob API${NC}"
        echo "  Check your network connection and VPN"
    else
        echo -e "${YELLOW}⚠ Unexpected response (HTTP $HTTP_CODE)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No API key available to test${NC}"
fi
echo ""

# Try running Bob with --help
echo -e "${BLUE}5. Testing Bob CLI command...${NC}"
if bob --help &> /dev/null; then
    echo -e "${GREEN}✓ Bob CLI responds to commands${NC}"
else
    echo -e "${RED}✗ Bob CLI not responding${NC}"
fi
echo ""

# Check network connectivity
echo -e "${BLUE}6. Checking network connectivity...${NC}"
if ping -c 1 w3.ibm.com &> /dev/null; then
    echo -e "${GREEN}✓ Can reach IBM network${NC}"
else
    echo -e "${YELLOW}⚠ Cannot reach IBM network${NC}"
    echo "  You may need to connect to VPN"
fi
echo ""

# Summary
echo "==================================="
echo "Authentication Status Summary"
echo "==================================="
echo ""

# Determine overall status
AUTHENTICATED=false

if [ -n "$BOB_API_KEY" ] && [ "$HTTP_CODE" = "200" -o "$HTTP_CODE" = "204" ]; then
    AUTHENTICATED=true
    echo -e "${GREEN}✓ YOU ARE AUTHENTICATED${NC}"
    echo ""
    echo "You can now use Bob CLI:"
    echo "  bob"
    echo "  bob 'your task here'"
elif [ -f ~/.bob/token.json ]; then
    echo -e "${YELLOW}⚠ PARTIALLY AUTHENTICATED${NC}"
    echo ""
    echo "You have a token file, but API connectivity test failed."
    echo "Try running Bob to see if it works:"
    echo "  bob"
else
    echo -e "${RED}✗ NOT AUTHENTICATED${NC}"
    echo ""
    echo "To authenticate, run:"
    echo "  ./setup-bob-api-key.sh"
    echo ""
    echo "Or set your API key manually:"
    echo "  # Add BOB_API_KEY to the project .env (use-cases/<project>/.env), then:"
    echo "  source $SCRIPT_DIR/../load-env.sh"
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
