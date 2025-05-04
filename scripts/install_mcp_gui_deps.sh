#!/bin/bash
# install_mcp_gui_deps.sh - Install system dependencies for MCP GUI
# Part of Claude Desktop Manager (CMGR)

set -e

# ANSI color codes
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

echo -e "${YELLOW}Claude Desktop Manager - MCP GUI Dependencies${RESET}"
echo "================================================="

# Check for Python and get version
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1-2)
    echo -e "${GREEN}✓ Python ${PYTHON_VERSION} found${RESET}"
else
    echo -e "${RED}✗ Python 3 not found${RESET}"
    echo "Installing Python 3..."
    sudo apt update
    sudo apt install -y python3
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1-2)
fi

# Check for Python venv
if dpkg -l | grep -q "python3.*-venv"; then
    echo -e "${GREEN}✓ Python venv package found${RESET}"
else
    echo -e "${RED}✗ Python venv package not found${RESET}"
    echo "Installing python${PYTHON_VERSION}-venv..."
    sudo apt update
    sudo apt install -y "python${PYTHON_VERSION}-venv"
fi

# Check for pip
if command -v pip3 &>/dev/null; then
    echo -e "${GREEN}✓ pip found${RESET}"
else
    echo -e "${RED}✗ pip not found${RESET}"
    echo "Installing pip..."
    sudo apt update
    sudo apt install -y python3-pip
fi

# Check for Qt dependencies
if dpkg -l | grep -q "python3-pyqt5"; then
    echo -e "${GREEN}✓ PyQt5 system package found${RESET}"
else
    echo -e "${YELLOW}! PyQt5 system package not found${RESET}"
    echo "Installing PyQt5 system dependencies..."
    sudo apt update
    sudo apt install -y python3-pyqt5 python3-pyqt5.qtwebengine qt5-qmake
fi

# Additional system dependencies for PyQt
if dpkg -l | grep -q "qttools5-dev-tools"; then
    echo -e "${GREEN}✓ Qt tools found${RESET}"
else
    echo -e "${YELLOW}! Qt tools not found${RESET}"
    echo "Installing Qt development tools..."
    sudo apt update
    sudo apt install -y qttools5-dev-tools qttools5-dev
fi

echo -e "\n${GREEN}✓ All system dependencies for MCP GUI are installed${RESET}"
echo "You can now run 'cmgr mcp-gui' to launch the MCP GUI"
