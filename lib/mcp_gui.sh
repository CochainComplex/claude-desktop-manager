#!/bin/bash
# mcp_gui.sh - Python-based global MCP GUI launcher for Claude Desktop Manager
# This module provides functions to launch the MCP GUI.

# Launch the global MCP manager GUI
launch_mcp_gui() {
    # Check if Python and dependencies are installed
    if ! check_python_dependencies; then
        if ! install_python_dependencies; then
            echo "❌ Failed to install Python dependencies. MCP Manager cannot be launched."
            exit 1
        fi
    fi
    
    # Check if the main.py file exists
    if [ ! -f "${SCRIPT_DIR}/python/mcp_manager/main.py" ]; then
        echo "❌ MCP Manager main script not found at: ${SCRIPT_DIR}/python/mcp_manager/main.py"
        echo "Please ensure the project is properly installed."
        exit 1
    fi
    
    # Export necessary environment variables
    export CMGR_HOME="${CMGR_HOME}"
    export SANDBOX_BASE="${SANDBOX_BASE}"
    
    # Launch Python GUI in background
    echo "Launching MCP Manager..."
    
    # Launch and log output
    "${SCRIPT_DIR}/python/venv/bin/python" "${SCRIPT_DIR}/python/mcp_manager/main.py" > "${CMGR_HOME}/logs/mcp_gui.log" 2>&1 &
    PID=$!
    
    # Check if process started successfully
    if ! ps -p $PID > /dev/null 2>&1; then
        echo "❌ Failed to launch MCP Manager."
        echo "Please check the log file at: ${CMGR_HOME}/logs/mcp_gui.log"
        exit 1
    fi
    
    echo "✓ MCP Manager launched"
    echo "  Log file: ${CMGR_HOME}/logs/mcp_gui.log"
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
    
    # Run the dependency installer script if available
    if [ -f "${SCRIPT_DIR}/scripts/install_mcp_gui_deps.sh" ]; then
        echo "Using dependency installer script..."
        "${SCRIPT_DIR}/scripts/install_mcp_gui_deps.sh" || {
            echo "❌ Dependency installer script failed."
            echo "Falling back to manual installation."
        }
    fi
    
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
    
    # Get Python version
    PYTHON_VERSION=$(python3 --version | awk '{print $2}' | cut -d. -f1-2)
    
    # Check if python3-venv or python3.x-venv is installed
    if ! dpkg -l | grep -q "python3.*-venv"; then
        echo "❌ Python venv package is required but not installed."
        echo "Please install it with: sudo apt install python3-venv or python$PYTHON_VERSION-venv"
        return 1
    fi
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "${SCRIPT_DIR}/python/venv" ]; then
        echo "Creating Python virtual environment..."
        python3 -m venv "${SCRIPT_DIR}/python/venv" || {
            echo "❌ Failed to create virtual environment."
            echo "If you're using Python 3.12+, ensure python3.12-venv is installed:"
            echo "sudo apt install python$PYTHON_VERSION-venv"
            return 1
        }
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
