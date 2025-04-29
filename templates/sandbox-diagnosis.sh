#!/bin/bash
# sandbox-diagnosis.sh - Tool to diagnose sandbox isolation issues
# Place this in the sandbox instance to run diagnostics

set -e

echo "===== CLAUDE DESKTOP SANDBOX ISOLATION DIAGNOSTIC ====="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "Home: $HOME"

echo -e "\n--- Environment Variables ---"
echo "CLAUDE_INSTANCE: ${CLAUDE_INSTANCE:-Not set}"
echo "CLAUDE_CONFIG_PATH: ${CLAUDE_CONFIG_PATH:-Not set}"
echo "XDG_CONFIG_HOME: ${XDG_CONFIG_HOME:-Not set}"
echo "XDG_DATA_HOME: ${XDG_DATA_HOME:-Not set}"
echo "XDG_CACHE_HOME: ${XDG_CACHE_HOME:-Not set}"
echo "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-Not set}"
echo "DISPLAY: ${DISPLAY:-Not set}"
echo "XAUTHORITY: ${XAUTHORITY:-Not set}"

echo -e "\n--- Claude Configuration ---"
CLAUDE_CONFIG="${CLAUDE_CONFIG_PATH:-$HOME/.config/Claude/claude_desktop_config.json}"
if [ -f "$CLAUDE_CONFIG" ]; then
    echo "Config file exists: $CLAUDE_CONFIG"
    echo "Content:"
    cat "$CLAUDE_CONFIG"
else
    echo "Config file not found: $CLAUDE_CONFIG"
fi

echo -e "\n--- MCP Ports ---"
echo "Testing MCP server port connections..."
for port in $(seq 9000 9100); do
    if nc -z localhost $port 2>/dev/null; then
        echo "Port $port: OPEN"
    fi
done

echo -e "\n--- Real Home Access Test ---"
# Try to detect if we can access the real home directory
# Get current username dynamically
current_user="${SUDO_USER:-$(whoami)}"

real_home_paths=(
    "/home/${current_user}"  # Real username detected dynamically
    "/root"                  # Root's home
    "/home/ubuntu"           # Common username on cloud instances
    "/home/debian"           # Common username on Debian-based systems
)

for real_home in "${real_home_paths[@]}"; do
    if [ -d "$real_home" ]; then
        echo "WARNING: Can access $real_home"
        if [ -d "$real_home/.config/Claude" ]; then
            echo "CRITICAL: Can access real Claude config at $real_home/.config/Claude"
            ls -la "$real_home/.config/Claude"
        else
            echo "Cannot access Claude config in $real_home"
        fi
    else
        echo "Cannot access $real_home (Good)"
    fi
done

echo -e "\n--- Filesystem Permissions ---"
echo "Claude config directory permissions:"
ls -la "$HOME/.config/Claude"

echo -e "\n--- Process Information ---"
echo "Running processes for this user:"
ps -u $(whoami) -o pid,ppid,cmd

echo "===== DIAGNOSTIC COMPLETE ====="