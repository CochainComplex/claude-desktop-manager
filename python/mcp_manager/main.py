#!/usr/bin/env python3
"""
MCP Server Manager - GUI tool for managing Claude Desktop MCP servers
Part of Claude Desktop Manager (CMGR)

This tool provides a graphical interface for starting, stopping, and
configuring MCP servers for Claude Desktop instances.
"""

import sys
import os
import argparse
from PyQt5.QtWidgets import QApplication
from mcp_manager.ui.main_window import MainWindow

def main():
    """Main entry point for the application"""
    
    parser = argparse.ArgumentParser(description="Claude Desktop MCP Manager")
    parser.add_argument("--cmgr-home", help="CMGR home directory")
    parser.add_argument("--sandbox-base", help="Sandbox base directory")
    
    args = parser.parse_args()
    
    # Set environment variables if provided
    if args.cmgr_home:
        os.environ["CMGR_HOME"] = args.cmgr_home
    
    if args.sandbox_base:
        os.environ["SANDBOX_BASE"] = args.sandbox_base
    
    # Create and launch application
    app = QApplication(sys.argv)
    app.setApplicationName("Claude MCP Manager")
    app.setOrganizationName("ClaudeDesktopManager")
    
    window = MainWindow()
    window.show()
    
    sys.exit(app.exec_())

if __name__ == "__main__":
    main()
