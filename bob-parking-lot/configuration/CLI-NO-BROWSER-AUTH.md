# Bob CLI - Terminal-Only Authentication (No Browser)

Complete guide for authenticating Bob CLI directly in the terminal without browser redirect.

## The Challenge

Bob CLI v1.0.4 tries to open a browser for OAuth authentication. We need to bypass this and authenticate purely in the terminal.

## Solutions

### Solution 1: Direct Authentication Script (Recommended)

This script attempts multiple methods to authenticate without browser:

```bash
chmod +x bob-cli-direct-auth.sh
./bob-cli-direct-auth.sh
```

**What it does:**
1. Tries to exchange API key for access token
2. Tests multiple authentication endpoints
3. Creates token file for Bob CLI
4. Sets up wrapper scripts
5. Configures environment variables

### Solution 2: No-Browser Wrapper

Use this wrapper to run Bob without browser redirect:

```bash
chmod +x bob-no-browser.sh
./bob-no-browser.sh "your task here"
```

**Example:**
```bash
./bob-no-browser.sh "create a hello world app"
./bob-no-browser.sh "explain quantum computing"
```

### Solution 3: Environment Variables

Set these environment variables to prevent browser opening:

```bash
# BOB_API_KEY is read from the project .env (use-cases/<project>/.env) - never hardcode it
source ../load-env.sh
export NODE_TLS_REJECT_UNAUTHORIZED=0
export BOB_NO_BROWSER=1
export BOB_AUTH_METHOD="apikey"
export BROWSER=none
export DISPLAY=

bob "your task here"
```

### Solution 4: Create Permanent Alias

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Bob CLI without browser
alias bob-cli='source /path/to/bob-parking-lot/load-env.sh && BOB_NO_BROWSER=1 BROWSER=none bob'
```

Then use:
```bash
bob-cli "your task here"
```

### Solution 5: Modify Bob Configuration

Create `~/.bob/config.json`:

```json
{
  "apiKey": "<value of BOB_API_KEY from the project .env>",
  "apiEndpoint": "https://api.us-east.bob.ibm.com",
  "authMethod": "apikey",
  "noBrowser": true,
  "region": "us-east"
}
```

## If Bob Still Opens Browser

If Bob CLI v1.0.4 still tries to open browser despite these settings, it means:

1. **The CLI doesn't support API key authentication**
   - v1.0.4 may only support OAuth
   - API key might be for web/API only

2. **You need a different approach:**

### Alternative: Use Bob API Directly

Create a script that calls Bob API directly without using the CLI:

```bash
#!/usr/bin/env bash
# direct-bob-api.sh

source ../load-env.sh
API_KEY="${BOB_API_KEY:?Set BOB_API_KEY in the project .env}"
MESSAGE="$1"
MODE="${2:-code}"

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 'your message' [mode]"
    echo "Modes: code, ask, plan, debug"
    exit 1
fi

echo "Calling Bob API directly..."
echo ""

RESPONSE=$(curl -s -X POST \
    "https://api.us-east.bob.ibm.com/v1/chat" \
    -H "Authorization: Bearer $API_KEY" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"message\": \"$MESSAGE\",
        \"mode\": \"$MODE\",
        \"stream\": false
    }")

if [ $? -eq 0 ]; then
    echo "$RESPONSE" | jq -r '.response // .message // .'
else
    echo "Error calling Bob API"
    echo "$RESPONSE"
fi
```

Usage:
```bash
chmod +x direct-bob-api.sh
./direct-bob-api.sh "create a hello world app" "code"
./direct-bob-api.sh "explain quantum computing" "ask"
```

## Testing Authentication

After running any solution, test with:

```bash
# Test 1: Check if token file exists
ls -la ~/.bob/token.json

# Test 2: Check environment
echo $BOB_API_KEY

# Test 3: Try Bob
bob "hello"

# Test 4: Check if browser opens
# If browser doesn't open = SUCCESS!
```

## For Different Linux Distributions

### WSL Ubuntu
```bash
./bob-cli-direct-auth.sh
./bob-no-browser.sh "hello"
```

### RHEL/CentOS
```bash
chmod +x bob-cli-direct-auth.sh
./bob-cli-direct-auth.sh
```

### Fedora
```bash
chmod +x bob-cli-direct-auth.sh
./bob-cli-direct-auth.sh
```

All scripts work the same across distributions.

## Troubleshooting

### "Bob still opens browser"

**Problem:** Bob CLI v1.0.4 ignores API key and environment variables

**Solution:** Use direct API calls instead of CLI:
```bash
./direct-bob-api.sh "your message"
```

### "API returns 401"

**Problem:** API key not accepted

**Possible causes:**
1. API key is for web interface only
2. API key expired
3. API key not activated
4. Wrong API endpoint

**Solution:** Contact #bob-support for correct API key type

### "Command not found: bob"

**Problem:** Bob CLI not installed

**Solution:**
```bash
npm install -g bobshell
```

### "Cannot reach Bob API"

**Problem:** Not on VPN

**Solution:**
```bash
# Test VPN
./wsl-test-vpn.sh

# Connect VPN on Windows (for WSL)
# Or connect VPN on Linux
```

## Environment Variables Reference

| Variable | Purpose | Value |
|----------|---------|-------|
| `BOB_API_KEY` | Your API key | from the project `.env` |
| `BOB_NO_BROWSER` | Disable browser | `1` |
| `BOB_AUTH_METHOD` | Auth method | `apikey` |
| `BROWSER` | Browser command | `none` |
| `DISPLAY` | X11 display | `` (empty) |
| `NODE_TLS_REJECT_UNAUTHORIZED` | SSL workaround | `0` |

## Complete Setup Script

```bash
#!/usr/bin/env bash
# complete-setup.sh

# Run direct authentication
./bob-cli-direct-auth.sh

# Add alias to bashrc
echo 'alias bob-cli="source /path/to/bob-parking-lot/load-env.sh && BOB_NO_BROWSER=1 BROWSER=none bob"' >> ~/.bashrc

# Reload shell
source ~/.bashrc

# Test
bob-cli "hello"
```

## Summary

**Scripts Created:**
- `bob-cli-direct-auth.sh` - Attempts direct authentication
- `bob-no-browser.sh` - Wrapper to prevent browser
- `direct-bob-api.sh` - Direct API calls (if CLI fails)

**Best Approach:**
1. Run `./bob-cli-direct-auth.sh`
2. Use `./bob-no-browser.sh "message"`
3. If still opens browser, use direct API calls

**Key Point:**
If Bob CLI v1.0.4 doesn't support API key authentication, you'll need to either:
- Use direct API calls (bypass CLI)
- Wait for updated CLI from IBM
- Use web interface

## Support

If none of these work, contact:
- **Slack:** #bob-support
- **Email:** bob-support@ibm.com
- **Request:** CLI that supports API key authentication without browser