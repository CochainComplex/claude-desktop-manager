#!/bin/bash
# mcp_gui.sh - Python-based global MCP GUI launcher for Claude Desktop Manager
# This module provides functions to launch the MCP GUI.

# Launch the global MCP manager GUI
launch_mcp_gui() {
    # Check if the main.py file exists
    if [ ! -f "${SCRIPT_DIR}/python/mcp_manager/main.py" ]; then
        echo "❌ MCP Manager main script not found at: ${SCRIPT_DIR}/python/mcp_manager/main.py"
        echo "Please ensure the project is properly installed."
        return 1
    fi
    
    # Export necessary environment variables
    export CMGR_HOME="${CMGR_HOME}"
    export SANDBOX_BASE="${SANDBOX_BASE}"
    # Set Python module path for proper importing
    export PYTHONPATH="${SCRIPT_DIR}"
    
    # Create logs directory if it doesn't exist
    mkdir -p "${CMGR_HOME}/logs"
    
    # Launch Python GUI in background
    echo "Launching MCP Manager..."
    
    # Launch and log output using system Python with correct import path
    cd "${SCRIPT_DIR}/python" && python3 -m mcp_manager.main > "${CMGR_HOME}/logs/mcp_gui.log" 2>&1 &
    PID=$!
    
    # Check if process started successfully
    if ! ps -p $PID > /dev/null 2>&1; then
        echo "❌ Failed to launch MCP Manager."
        echo "Please check the log file at: ${CMGR_HOME}/logs/mcp_gui.log"
        return 1
    fi
    
    echo "✓ MCP Manager launched"
    echo "  Log file: ${CMGR_HOME}/logs/mcp_gui.log"
}
