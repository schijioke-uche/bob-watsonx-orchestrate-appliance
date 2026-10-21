#!/usr/bin/env bash

# Direct Bob API Calls - Bypass CLI completely
# Works on all Linux distributions without browser

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LOADER_PATH="$SCRIPT_DIR/../load-env.sh"
# Credentials are read from the project .env - never hardcode them here.
source "$LOADER_PATH"
API_KEY="${BOB_API_KEY:-}"
API_ENDPOINT="https://api.us-east.bob.ibm.com"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: $0 'your message' [mode]"
    echo ""
    echo "Modes:"
    echo "  code  - Code generation and modification"
    echo "  ask   - Questions and explanations"
    echo "  plan  - Planning and design"
    echo "  debug - Debugging assistance"
    echo ""
    echo "Examples:"
    echo "  $0 'create a hello world app' code"
    echo "  $0 'explain quantum computing' ask"
    echo "  $0 'design a REST API' plan"
    exit 1
fi

if [ -z "$API_KEY" ]; then
    echo "Error: BOB_API_KEY is not set. Add it to the project .env (use-cases/<project>/.env) or set BOB_ENV_FILE." >&2
    exit 1
fi

MESSAGE="$1"
MODE="${2:-code}"

echo -e "${BLUE}Calling Bob API directly (no CLI, no browser)...${NC}"
echo ""
echo "Message: $MESSAGE"
echo "Mode: $MODE"
echo ""

# Make API call
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    "$API_ENDPOINT/v1/chat" \
    -H "Authorization: Bearer $API_KEY" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"message\": \"$MESSAGE\",
        \"mode\": \"$MODE\",
        \"stream\": false
    }" 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

echo "==================================="
echo "Bob Response"
echo "==================================="
echo ""

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Success${NC}"
    echo ""
    
    # Try to parse JSON response
    if command -v jq >/dev/null 2>&1; then
        echo "$BODY" | jq -r '.response // .message // .content // .'
    else
        echo "$BODY"
    fi
elif [ "$HTTP_CODE" = "401" ]; then
    echo -e "${RED}✗ Authentication Failed (HTTP 401)${NC}"
    echo ""
    echo "Your API key may be invalid or not authorized for direct API access."
    echo "API Key: ${API_KEY:0:3}***"
    echo ""
    echo "Contact #bob-support for:"
    echo "  - Verify API key is active"
    echo "  - Request API key with direct API access"
    echo "  - Get updated Bob CLI that supports API keys"
elif [ "$HTTP_CODE" = "403" ]; then
    echo -e "${RED}✗ Access Forbidden (HTTP 403)${NC}"
    echo ""
    echo "Your API key doesn't have permission for this operation."
elif [ "$HTTP_CODE" = "404" ]; then
    echo -e "${RED}✗ Endpoint Not Found (HTTP 404)${NC}"
    echo ""
    echo "The API endpoint may be incorrect or the API version changed."
    echo "Current endpoint: $API_ENDPOINT/v1/chat"
else
    echo -e "${YELLOW}⚠ Unexpected Response (HTTP $HTTP_CODE)${NC}"
    echo ""
    echo "Response:"
    echo "$BODY"
fi

echo ""
echo "==================================="

exit $([ "$HTTP_CODE" = "200" ] && echo 0 || echo 1)

# Made with Bob
