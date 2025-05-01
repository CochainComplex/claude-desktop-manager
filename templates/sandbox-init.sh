#!/bin/bash
# Sandbox initialization script for Claude Desktop Manager
set -e

echo "Initializing sandbox environment..."

# Create basic directories
mkdir -p ~/Documents
mkdir -p ~/Downloads
mkdir -p ~/.config/Claude
mkdir -p ~/.config/Claude/electron
mkdir -p ~/.config/claude-desktop
mkdir -p ~/.local/share/applications
mkdir -p ~/.local/bin

# Create a folder for custom code
mkdir -p ~/Documents/CODE

# This initialization doesn't install packages automatically
# It's safer to pre-install required tools if needed

# Confirm initialization is complete
touch ~/.cmgr_initialized
echo "✓ Sandbox initialization complete!"
