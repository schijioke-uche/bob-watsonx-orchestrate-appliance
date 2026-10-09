#!/bin/bash

# Test IBM VPN Connection from CLI

echo "==================================="
echo "IBM VPN Connection Test"
echo "==================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VPN_CONNECTED=false
SCORE=0
TOTAL_TESTS=8

echo -e "${BLUE}Testing IBM network connectivity...${NC}"
echo ""

# Test 1: Ping w3.ibm.com
echo -n "1. Testing w3.ibm.com (IBM Intranet)... "
if ping -c 1 -W 3 w3.ibm.com &> /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((SCORE++))
    VPN_CONNECTED=true
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 2: Ping ibm.com
echo -n "2. Testing ibm.com (Public IBM)... "
if ping -c 1 -W 3 ibm.com &> /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 3: DNS resolution for IBM internal
echo -n "3. Testing DNS resolution (w3.ibm.com)... "
if nslookup w3.ibm.com &> /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 4: HTTPS to w3.ibm.com
echo -n "4. Testing HTTPS to w3.ibm.com... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://w3.ibm.com 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    echo -e "${GREEN}✓ PASS (HTTP $HTTP_CODE)${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
fi

# Test 5: Bob API endpoint
echo -n "5. Testing Bob API (api.us-east.bob.ibm.com)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://api.us-east.bob.ibm.com 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo -e "${GREEN}✓ PASS (HTTP $HTTP_CODE)${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
fi

# Test 6: IBM Cloud
echo -n "6. Testing IBM Cloud (cloud.ibm.com)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://cloud.ibm.com 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    echo -e "${GREEN}✓ PASS (HTTP $HTTP_CODE)${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
fi

# Test 7: IBM SSO endpoint
echo -n "7. Testing IBM SSO (console-ibm-prod.verify.ibm.com)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://console-ibm-prod.verify.ibm.com 2>/dev/null || echo "000")
if [ "$HTTP_CODE" != "000" ]; then
    echo -e "${GREEN}✓ PASS (HTTP $HTTP_CODE)${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
fi

# Test 8: Check for VPN interface
echo -n "8. Checking for VPN network interface... "
if ip addr show 2>/dev/null | grep -E "tun|tap|ppp|vpn" &> /dev/null || \
   ifconfig 2>/dev/null | grep -E "tun|tap|ppp|vpn" &> /dev/null || \
   ipconfig 2>/dev/null | grep -i "cisco\|vpn\|zscaler" &> /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((SCORE++))
else
    echo -e "${YELLOW}⚠ UNKNOWN${NC}"
fi

echo ""
echo "==================================="
echo "Test Results"
echo "==================================="
echo ""
echo "Score: $SCORE/$TOTAL_TESTS tests passed"
echo ""

# Determine VPN status
if [ $SCORE -ge 6 ]; then
    echo -e "${GREEN}✓ VPN STATUS: CONNECTED${NC}"
    echo ""
    echo "You are connected to IBM network!"
    echo "You can now use Bob CLI:"
    echo "  bob 'hello'"
    VPN_CONNECTED=true
elif [ $SCORE -ge 3 ]; then
    echo -e "${YELLOW}⚠ VPN STATUS: PARTIAL CONNECTION${NC}"
    echo ""
    echo "Some IBM services are reachable, but not all."
    echo "This might indicate:"
    echo "  - Split tunnel VPN (only some traffic routed)"
    echo "  - VPN connection issues"
    echo "  - Firewall blocking some services"
    echo ""
    echo "Try reconnecting to VPN with full tunnel mode."
else
    echo -e "${RED}✗ VPN STATUS: NOT CONNECTED${NC}"
    echo ""
    echo "You are NOT connected to IBM network."
    echo ""
    echo "To connect:"
    echo "  1. Open your VPN client (Cisco AnyConnect, Zscaler, etc.)"
    echo "  2. Connect to IBM corporate network"
    echo "  3. Run this test again: ./test-vpn-connection.sh"
fi

echo ""
echo "==================================="
echo "Additional Information"
echo "==================================="
echo ""

# Show current IP
echo "Your current IP address:"
curl -s ifconfig.me 2>/dev/null || echo "Unable to determine"
echo ""

# Show DNS servers
echo ""
echo "DNS servers in use:"
if [ -f /etc/resolv.conf ]; then
    grep nameserver /etc/resolv.conf | head -3
elif command -v ipconfig &> /dev/null; then
    ipconfig /all | grep -i "DNS Servers" | head -3
else
    echo "Unable to determine"
fi

# Show routing
echo ""
echo "Default gateway:"
if command -v ip &> /dev/null; then
    ip route | grep default | head -1
elif command -v route &> /dev/null; then
    route -n | grep "^0.0.0.0" | head -1
elif command -v netstat &> /dev/null; then
    netstat -rn | grep "^0.0.0.0" | head -1
else
    echo "Unable to determine"
fi

echo ""
echo "==================================="
echo "Troubleshooting Tips"
echo "==================================="
echo ""

if [ "$VPN_CONNECTED" = false ]; then
    echo "If you're having trouble connecting to VPN:"
    echo ""
    echo "1. Check VPN client is installed:"
    echo "   - Cisco AnyConnect"
    echo "   - Zscaler"
    echo "   - IBM VPN client"
    echo ""
    echo "2. Verify VPN credentials:"
    echo "   - Use your w3ID"
    echo "   - Check password hasn't expired"
    echo ""
    echo "3. Try different VPN endpoint:"
    echo "   - vpn.ibm.com"
    echo "   - ztunnel.ibm.com"
    echo ""
    echo "4. Contact IBM IT Help Desk if issues persist"
    echo ""
    echo "5. Alternative: Use Bob Web Interface"
    echo "   - Go to: https://bob.ibm.com"
    echo "   - Works from anywhere (no VPN needed for web)"
fi

echo ""
echo "==================================="

# Exit with appropriate code
if [ "$VPN_CONNECTED" = true ]; then
    exit 0
else
    exit 1
fi

# Made with Bob
