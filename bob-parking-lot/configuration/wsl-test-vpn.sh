#!/usr/bin/env bash

# WSL Ubuntu Compatible - Test IBM VPN Connection

echo "==================================="
echo "IBM VPN Connection Test (WSL)"
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

echo -e "${BLUE}Testing IBM network connectivity from WSL...${NC}"
echo ""

# Test 1: Ping w3.ibm.com
echo -n "1. Testing w3.ibm.com (IBM Intranet)... "
if timeout 3 ping -c 1 w3.ibm.com >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((SCORE++))
    VPN_CONNECTED=true
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 2: Ping ibm.com
echo -n "2. Testing ibm.com (Public IBM)... "
if timeout 3 ping -c 1 ibm.com >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 3: DNS resolution
echo -n "3. Testing DNS resolution (w3.ibm.com)... "
if host w3.ibm.com >/dev/null 2>&1 || nslookup w3.ibm.com >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 4: HTTPS to w3.ibm.com
echo -n "4. Testing HTTPS to w3.ibm.com... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 https://w3.ibm.com 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    echo -e "${GREEN}✓ PASS (HTTP $HTTP_CODE)${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
fi

# Test 5: Bob API endpoint
echo -n "5. Testing Bob API (api.us-east.bob.ibm.com)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 https://api.us-east.bob.ibm.com 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|400|401|403)$ ]]; then
    echo -e "${GREEN}✓ PASS (HTTP $HTTP_CODE)${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
fi

# Test 6: IBM Cloud
echo -n "6. Testing IBM Cloud (cloud.ibm.com)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 https://cloud.ibm.com 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    echo -e "${GREEN}✓ PASS (HTTP $HTTP_CODE)${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
fi

# Test 7: IBM SSO
echo -n "7. Testing IBM SSO (console-ibm-prod.verify.ibm.com)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 https://console-ibm-prod.verify.ibm.com 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" != "000" ]]; then
    echo -e "${GREEN}✓ PASS (HTTP $HTTP_CODE)${NC}"
    ((SCORE++))
else
    echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
fi

# Test 8: Check Windows VPN status (WSL specific)
echo -n "8. Checking Windows VPN status... "
if powershell.exe -Command "Get-NetAdapter | Where-Object {(\$_.InterfaceDescription -like '*VPN*') -or (\$_.InterfaceDescription -like '*Cisco*') -or (\$_.InterfaceDescription -like '*Zscaler*')}" 2>/dev/null | grep -q "Up"; then
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
    echo "  source ~/.bob/export-env.sh"
    echo "  bob 'hello'"
    VPN_CONNECTED=true
elif [ $SCORE -ge 3 ]; then
    echo -e "${YELLOW}⚠ VPN STATUS: PARTIAL CONNECTION${NC}"
    echo ""
    echo "Some IBM services are reachable."
    echo "This is usually sufficient for Bob CLI to work."
    echo ""
    echo "Try using Bob:"
    echo "  source ~/.bob/export-env.sh"
    echo "  bob 'hello'"
else
    echo -e "${RED}✗ VPN STATUS: NOT CONNECTED${NC}"
    echo ""
    echo "You are NOT connected to IBM network."
    echo ""
    echo "To connect VPN on Windows (for WSL):"
    echo "  1. Open VPN client on Windows (not in WSL)"
    echo "  2. Connect to IBM corporate network"
    echo "  3. WSL will automatically use Windows network"
    echo "  4. Run this test again: ./wsl-test-vpn.sh"
fi

echo ""
echo "==================================="
echo "WSL Network Information"
echo "==================================="
echo ""

# Show WSL IP
echo "WSL IP address:"
ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' || echo "Unable to determine"

# Show Windows host IP
echo ""
echo "Windows host IP (from WSL):"
cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | head -1

# Show DNS
echo ""
echo "DNS servers:"
cat /etc/resolv.conf | grep nameserver | head -3

echo ""
echo "==================================="
echo "WSL-Specific Notes"
echo "==================================="
echo ""
echo "• WSL uses Windows network stack"
echo "• VPN must be connected on Windows, not in WSL"
echo "• WSL automatically inherits Windows VPN connection"
echo "• If VPN works on Windows, it works in WSL"
echo ""

if [ "$VPN_CONNECTED" = false ] && [ $SCORE -lt 3 ]; then
    echo "Troubleshooting for WSL:"
    echo ""
    echo "1. Connect VPN on Windows (not WSL):"
    echo "   - Open Cisco AnyConnect on Windows"
    echo "   - Or Zscaler on Windows"
    echo "   - Connect to IBM network"
    echo ""
    echo "2. Verify VPN on Windows:"
    echo "   - Open PowerShell on Windows"
    echo "   - Run: Test-Connection w3.ibm.com"
    echo ""
    echo "3. If VPN works on Windows but not WSL:"
    echo "   - Restart WSL: wsl --shutdown (in PowerShell)"
    echo "   - Reopen WSL terminal"
    echo ""
    echo "4. Check WSL networking:"
    echo "   - Run: cat /etc/resolv.conf"
    echo "   - Should show Windows DNS server"
    echo ""
fi

exit $([ "$VPN_CONNECTED" = true ] && echo 0 || echo 1)

# Made with Bob
