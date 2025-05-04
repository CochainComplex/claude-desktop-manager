#!/bin/bash
# mcp_gui.sh - Python-based global MCP GUI launcher for Claude Desktop Manager
# This module provides functions to launch the MCP GUI.

# Launch the global MCP manager GUI
launch_mcp_gui() {
    # Check if Python and dependencies are installed
    if ! check_python_dependencies; then
        install_python_dependencies
    fi
    
    # Export necessary environment variables
    export CMGR_HOME="${CMGR_HOME}"
    export SANDBOX_BASE="${SANDBOX_BASE}"
    
    # Launch Python GUI in background
    echo "Launching MCP Manager..."
    "${SCRIPT_DIR}/python/venv/bin/python" "${SCRIPT_DIR}/python/mcp_manager/main.py" &
    
    echo "✓ MCP Manager launched"
}

# Check if Python dependencies are installed
check_python_dependencies() {
    if [ ! -d "${SCRIPT_DIR}/python/venv" ]; then
        return 1
    fi
    
    # Check if PyQt5 is installed
    if ! "${SCRIPT_DIR}/python/venv/bin/pip" list | grep -q "PyQt5"; then
        return 1
    fi
    
    return 0
}

# Install Python dependencies
install_python_dependencies() {
    echo "Installing Python dependencies for MCP GUI..."
    
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python 3 is required but not installed."
        echo "Please install Python 3 and try again."
        return 1
    fi
    
    # Check if pip is available
    if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
        echo "❌ pip is required but not installed."
        echo "Please install pip and try again."
        return 1
    fi
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "${SCRIPT_DIR}/python/venv" ]; then
        echo "Creating Python virtual environment..."
        python3 -m venv "${SCRIPT_DIR}/python/venv"
    fi
    
    # Make sure pip is up to date in the venv
    "${SCRIPT_DIR}/python/venv/bin/pip" install --upgrade pip
    
    # Install dependencies
    echo "Installing required packages..."
    "${SCRIPT_DIR}/python/venv/bin/pip" install -r "${SCRIPT_DIR}/python/requirements.txt"
    
    if [ $? -eq 0 ]; then
        echo "✓ Python dependencies installed successfully"
        return 0
    else
        echo "❌ Failed to install Python dependencies"
        return 1
    fi
}
