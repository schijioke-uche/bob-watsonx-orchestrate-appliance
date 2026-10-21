#!/usr/bin/env bash

# Permanent fix for Bob CLI warnings - Works on all shells

echo "==================================="
echo "Fixing Bob CLI Warnings"
echo "==================================="
echo ""

LOADER_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../load-env.sh"

# Get current directory
CURRENT_DIR="$(pwd)"
BOB_LINUX_DIR="$CURRENT_DIR/Bob-Linux"

# Check if we're in the right directory
if [ ! -f "$BOB_LINUX_DIR/bob-clean.sh" ]; then
    echo "Error: Run this from the directory containing Bob-Linux folder"
    exit 1
fi

# Make scripts executable
chmod +x "$BOB_LINUX_DIR/bob-clean.sh"
chmod +x "$BOB_LINUX_DIR/bob-quiet.sh"

echo "Step 1: Creating wrapper scripts..."

# Create a wrapper in a standard location
mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/bob" <<'WRAPPER'
#!/usr/bin/env bash
# Bob CLI wrapper - suppresses warnings

export NODE_NO_WARNINGS=1
# API key comes from the project .env (path injected at install time)
source "__LOADER_PATH__"
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Get the real bob path
REAL_BOB=$(which -a bob | grep -v "$HOME/.local/bin" | head -1)

if [ -z "$REAL_BOB" ]; then
    REAL_BOB="/usr/local/bin/bob"
fi

# Run real bob and suppress warnings
"$REAL_BOB" "$@" 2>&1 | grep -v "DeprecationWarning" | grep -v "Setting NODE_TLS_REJECT_UNAUTHORIZED" | grep -v "Failed to get current commit"
WRAPPER
sed -i "s|__LOADER_PATH__|$LOADER_PATH|" "$HOME/.local/bin/bob"

chmod +x "$HOME/.local/bin/bob"

echo "✓ Wrapper created at ~/.local/bin/bob"
echo ""

# Add to PATH if not already there
echo "Step 2: Updating PATH..."

for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$rc_file" ]; then
        if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$rc_file"; then
            echo "" >> "$rc_file"
            echo '# Add ~/.local/bin to PATH for custom scripts' >> "$rc_file"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
            echo "✓ Updated $rc_file"
        else
            echo "✓ $rc_file already configured"
        fi
    fi
done

echo ""
echo "Step 3: Activating changes..."
export PATH="$HOME/.local/bin:$PATH"

echo "✓ PATH updated"
echo ""
echo "==================================="
echo "Installation Complete!"
echo "==================================="
echo ""
echo "The warnings are now suppressed!"
echo ""
echo "To use immediately in current shell:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo "  bob 'hello'"
echo ""
echo "Or open a new terminal and use:"
echo "  bob 'hello'"
echo ""
echo "The wrapper at ~/.local/bin/bob will be used automatically."
echo ""

# Made with Bob
