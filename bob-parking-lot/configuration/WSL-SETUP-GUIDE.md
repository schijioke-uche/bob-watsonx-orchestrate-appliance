# Bob CLI Setup Guide for WSL Ubuntu

Complete guide for setting up and using Bob CLI in WSL (Windows Subsystem for Linux) Ubuntu.

## Quick Start

```bash
# 1. Test VPN connection
chmod +x wsl-test-vpn.sh
./wsl-test-vpn.sh

# 2. Configure Bob CLI
chmod +x wsl-configure-bob.sh
./wsl-configure-bob.sh

# 3. Verify authentication
chmod +x wsl-verify-auth.sh
./wsl-verify-auth.sh

# 4. Use Bob
source ~/.bob/export-env.sh
bob "hello"
```

## WSL-Specific Scripts

All scripts are optimized for WSL Ubuntu:

| Script | Purpose |
|--------|---------|
| `wsl-test-vpn.sh` | Test VPN connectivity from WSL |
| `wsl-configure-bob.sh` | Configure Bob with API key |
| `wsl-verify-auth.sh` | Verify authentication status |
| `wsl-bob-wrapper.sh` | Wrapper script for easy Bob usage |

## Important WSL Notes

### VPN Connection

**VPN must be connected on Windows, not in WSL:**

1. Open VPN client on **Windows** (not in WSL terminal)
   - Cisco AnyConnect
   - Zscaler
   - IBM VPN client

2. Connect to IBM corporate network

3. WSL automatically inherits Windows network connection

4. Verify in WSL:
   ```bash
   ./wsl-test-vpn.sh
   ```

### Network Behavior

- WSL uses Windows network stack
- All network traffic goes through Windows
- VPN connections on Windows apply to WSL
- DNS settings from Windows are used in WSL

## Installation Steps

### Step 1: Test VPN Connection

```bash
chmod +x wsl-test-vpn.sh
./wsl-test-vpn.sh
```

**Expected output if VPN is connected:**
```
✓ VPN STATUS: CONNECTED
You are connected to IBM network!
```

**If not connected:**
1. Open VPN client on Windows
2. Connect to IBM network
3. Run test again

### Step 2: Configure Bob CLI

```bash
chmod +x wsl-configure-bob.sh
./wsl-configure-bob.sh
```

This will:
- Read your API key (`BOB_API_KEY`) from the project `.env` (`use-cases/<project>/.env`, git-ignored)
- Create configuration files in `~/.bob/`
- Add Bob to your shell profile
- Create wrapper scripts

### Step 3: Verify Authentication

```bash
chmod +x wsl-verify-auth.sh
./wsl-verify-auth.sh
```

**Expected output:**
```
✓ YOU ARE AUTHENTICATED
You can now use Bob CLI
```

### Step 4: Use Bob CLI

**Option 1: Source environment (recommended)**
```bash
source ~/.bob/export-env.sh
bob "create a hello world app"
```

**Option 2: Use wrapper script**
```bash
chmod +x wsl-bob-wrapper.sh
./wsl-bob-wrapper.sh "explain quantum computing"
```

**Option 3: Reload shell**
```bash
source ~/.bashrc
bob "your task here"
```

**Option 4: One-time inline**
```bash
source ../load-env.sh && bob "hello"
```

## Configuration Files

After setup, you'll have:

```
~/.bob/
├── .env                    # Environment variables
├── config.json             # Bob configuration
├── export-env.sh           # Script to export variables
├── bob-cli.sh              # Wrapper script
└── token.json              # Auth token (if OAuth used)
```

## Troubleshooting

### "Cannot reach IBM network"

**Problem:** VPN not connected on Windows

**Solution:**
1. Open VPN client on Windows (not WSL)
2. Connect to IBM corporate network
3. Verify: `./wsl-test-vpn.sh`

### "Bob CLI not found"

**Problem:** Bob not installed

**Solution:**
```bash
# Install Node.js if needed
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Bob CLI
npm install -g bobshell
```

### "Authentication failed (HTTP 401)"

**Problem:** API key invalid or VPN not connected

**Solution:**
1. Verify VPN: `./wsl-test-vpn.sh`
2. Check API key: `cat ~/.bob/config.json`
3. Reconfigure: `./wsl-configure-bob.sh`

### "Bob hangs or times out"

**Problem:** Network connectivity issues

**Solution:**
```bash
# Check DNS
cat /etc/resolv.conf

# Test connectivity
ping ibm.com
curl -I https://api.us-east.bob.ibm.com

# Restart WSL (from PowerShell on Windows)
wsl --shutdown
# Then reopen WSL terminal
```

### WSL Network Issues

**Problem:** WSL cannot reach internet or IBM network

**Solution:**
```bash
# Check WSL networking
ip addr show eth0

# Check Windows host IP
cat /etc/resolv.conf | grep nameserver

# Restart WSL networking (from PowerShell on Windows)
wsl --shutdown
# Reopen WSL terminal
```

## Testing Commands

```bash
# Test VPN
./wsl-test-vpn.sh

# Test Bob API
curl -I https://api.us-east.bob.ibm.com

# Test Bob CLI
bob --version

# Test authentication
./wsl-verify-auth.sh

# Test Bob with simple command
source ~/.bob/export-env.sh
bob "hello"
```

## Common WSL Commands

```bash
# Check WSL version
wsl --version

# Check WSL status (from PowerShell on Windows)
wsl --status

# Restart WSL (from PowerShell on Windows)
wsl --shutdown

# Update WSL (from PowerShell on Windows)
wsl --update

# Check WSL IP address
ip addr show eth0

# Check Windows host IP from WSL
cat /etc/resolv.conf | grep nameserver
```

## Environment Variables

Bob CLI uses these environment variables:

```bash
# API Key (required) - read from the project .env, never hardcoded
source ../load-env.sh   # exports BOB_API_KEY

# SSL workaround (recommended)
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Bob API endpoint (optional)
export BOB_ENDPOINT="https://api.us-east.bob.ibm.com"
```

## Shell Profile Setup

The configuration script automatically adds to your `~/.bashrc`:

```bash
# Bob CLI Configuration
source ~/.bob/export-env.sh
```

To manually add:
```bash
echo 'source ~/.bob/export-env.sh' >> ~/.bashrc
source ~/.bashrc
```

## Usage Examples

```bash
# Simple greeting
bob "hello"

# Code generation
bob "create a Python script that calculates fibonacci numbers"

# Code explanation
bob "explain this code: $(cat myfile.py)"

# Ask questions
bob "what is the difference between REST and GraphQL?"

# Use specific mode
bob --mode code "implement a binary search tree"
bob --mode ask "explain quantum computing"
```

## Performance Tips

1. **Keep VPN connected:** Reconnecting takes time
2. **Use wrapper script:** Faster than sourcing each time
3. **Add to PATH:** Create alias for wrapper script
4. **Cache responses:** Bob may cache some responses

## Security Notes

1. **API Key Security:**
   - Never commit `~/.bob/` to git
   - Keep API key private
   - Rotate keys periodically

2. **File Permissions:**
   - Config files are set to 600 (owner read/write only)
   - Scripts are set to 700 (owner execute only)

3. **SSL Workaround:**
   - `NODE_TLS_REJECT_UNAUTHORIZED=0` is needed for corporate proxies
   - Only use on trusted networks

## Support

- **Bob Issues:** #bob-support (IBM Slack)
- **WSL Issues:** https://github.com/microsoft/WSL/issues
- **VPN Issues:** IBM IT Help Desk

## Additional Resources

- Bob Web Interface: https://bob.ibm.com
- Bob Documentation: https://bob.ibm.com/docs
- WSL Documentation: https://docs.microsoft.com/en-us/windows/wsl/

## Summary

**Setup Flow:**
1. Connect VPN on Windows → 2. Configure Bob → 3. Verify → 4. Use Bob

**Key Points:**
- VPN must be on Windows, not WSL
- WSL inherits Windows network
- API key is pre-configured
- Scripts are WSL-optimized

**Quick Commands:**
```bash
./wsl-test-vpn.sh          # Test VPN
./wsl-configure-bob.sh     # Configure
./wsl-verify-auth.sh       # Verify
source ~/.bob/export-env.sh && bob "hello"  # Use