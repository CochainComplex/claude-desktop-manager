#!/bin/bash
# init_mcp_gui.sh - Initialize MCP GUI directory structure
# Part of Claude Desktop Manager (CMGR)

set -e

# ANSI color codes
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${YELLOW}Claude Desktop Manager - MCP GUI Initialization${RESET}"
echo "================================================="

# Create directories if they don't exist
echo "Creating directory structure..."
mkdir -p "$PROJECT_DIR/python/mcp_manager/core"
mkdir -p "$PROJECT_DIR/python/mcp_manager/ui"

# Check if files already exist
if [ -f "$PROJECT_DIR/python/mcp_manager/main.py" ]; then
    echo -e "${GREEN}✓ MCP GUI files already exist${RESET}"
    echo "To reinstall or update, run: ${SCRIPT_DIR}/install_mcp_gui_deps.sh"
    exit 0
fi

# Create __init__ files
echo "Creating Python package structure..."
touch "$PROJECT_DIR/python/mcp_manager/__init__.py"
touch "$PROJECT_DIR/python/mcp_manager/core/__init__.py"
touch "$PROJECT_DIR/python/mcp_manager/ui/__init__.py"

echo -e "${GREEN}✓ MCP GUI directory structure created${RESET}"
echo "To complete the installation, run: cmgr mcp-gui"
echo "This will install dependencies and launch the GUI"
