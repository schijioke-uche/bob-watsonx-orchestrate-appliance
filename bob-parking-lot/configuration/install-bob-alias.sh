#!/usr/bin/env bash

# Install Bob alias to permanently suppress warnings

echo "==================================="
echo "Installing Bob Clean Alias"
echo "==================================="
echo ""

# Detect shell
SHELL_RC=""
if [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
    SHELL_NAME="bash"
elif [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
    SHELL_NAME="zsh"
else
    echo "Detecting shell..."
    if [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
        SHELL_NAME="zsh"
    else
        SHELL_RC="$HOME/.bashrc"
        SHELL_NAME="bash"
    fi
fi

echo "Detected shell: $SHELL_NAME"
echo "Config file: $SHELL_RC"
echo ""

# Get the absolute path to bob-clean.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOB_CLEAN_PATH="$SCRIPT_DIR/bob-clean.sh"

# Check if alias already exists
if grep -q "alias bob=" "$SHELL_RC" 2>/dev/null; then
    echo "Bob alias already exists in $SHELL_RC"
    echo "Updating it..."
    # Remove old alias
    sed -i.bak '/alias bob=/d' "$SHELL_RC"
fi

# Add new alias
echo "" >> "$SHELL_RC"
echo "# Bob CLI - Clean output (no deprecation warnings)" >> "$SHELL_RC"
echo "alias bob='$BOB_CLEAN_PATH'" >> "$SHELL_RC"

echo "✓ Alias added to $SHELL_RC"
echo ""
echo "To activate now, run:"
echo "  source $SHELL_RC"
echo ""
echo "Or open a new terminal."
echo ""
echo "Then use bob normally:"
echo "  bob 'hello'"
echo ""
echo "The warnings will be suppressed automatically!"
echo ""
echo "==================================="

# Offer to source now
read -p "Apply changes now? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    source "$SHELL_RC"
    echo "✓ Changes applied!"
    echo ""
    echo "Try it now: bob 'hello'"
fi

# Made with Bob
