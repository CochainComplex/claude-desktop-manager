#!/bin/bash
# fix-home-access.sh - Script to fix sandbox isolation issues
# This script tries various methods to block access to the real user's home

set -e

echo "===== SANDBOX ISOLATION FIX ====="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "Home: $HOME"

# Test if we have access to the real user's home
# Get current username dynamically
CURRENT_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="/home/${CURRENT_USER}"
if [ -d "$REAL_HOME" ]; then
    echo "WARNING: Can access real user's home: $REAL_HOME"
    
    # Try several methods to block access
    
    # Method 1: Create an empty directory and use bind mount
    if command -v mount >/dev/null 2>&1; then
        echo "Trying bind mount method..."
        mkdir -p /tmp/empty_dir
        
        # Try mount with sudo if available
        if command -v sudo >/dev/null 2>&1; then
            sudo mount --bind /tmp/empty_dir "$REAL_HOME" || echo "Bind mount failed"
        else
            mount --bind /tmp/empty_dir "$REAL_HOME" || echo "Bind mount failed (no sudo)"
        fi
    fi
    
    # Method 2: Use unshare to create a new mount namespace
    if command -v unshare >/dev/null 2>&1; then
        echo "Trying unshare method..."
        if command -v sudo >/dev/null 2>&1; then
            sudo unshare -m bash -c "mount -t tmpfs none $REAL_HOME" || echo "Unshare failed"
        else
            unshare -m bash -c "mount -t tmpfs none $REAL_HOME" || echo "Unshare failed (no sudo)"
        fi
    fi
    
    # Method 3: Simple chmod to remove permissions (not ideal but might help)
    if command -v chmod >/dev/null 2>&1; then
        echo "Trying chmod method..."
        if command -v sudo >/dev/null 2>&1; then
            sudo chmod 0 "$REAL_HOME" || echo "Chmod failed"
        else
            chmod 0 "$REAL_HOME" || echo "Chmod failed (no sudo)"
        fi
    fi
    
    # Check if any method worked
    if [ ! -d "$REAL_HOME" ] || ! ls -la "$REAL_HOME" &>/dev/null; then
        echo "✓ Successfully blocked access to real user's home"
    else
        echo "❌ All methods failed. Real user's home is still accessible."
        echo "This is a security risk - the sandbox is not properly isolated."
        
        # Create empty placeholder files to prevent access to sensitive configs
        if [ -d "$REAL_HOME/.config/Claude" ]; then
            echo "Attempting to protect real Claude config..."
            mkdir -p /tmp/empty_claude_config
            
            if command -v sudo >/dev/null 2>&1; then
                sudo mount --bind /tmp/empty_claude_config "$REAL_HOME/.config/Claude" || true
            fi
        fi
    fi
else
    echo "✓ Already prevented access to real user's home"
fi

echo "===== FIX COMPLETE ====="
