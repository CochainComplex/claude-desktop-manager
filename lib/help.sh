#!/bin/bash
# help.sh - Help and usage information for Claude Desktop Manager

# Display help message
show_help() {
    cat <<EOF
Claude Desktop Manager (cmgr) - Manage multiple Claude Desktop instances

Usage: cmgr COMMAND [OPTIONS]

Commands:
  create <n> [options]   Create a new Claude instance
  list                   List all instances
  start <n>              Start a specific instance
  stop <n>               Stop a running instance
  remove <n>             Remove an instance
  config <n> [options]   Configure instance settings
  alias <n> [alias]      Create command alias for instance
  desktop <n>            Create desktop shortcut
  mcp <n> [options]      Configure MCP settings
  import-config <n> [source] Import MCP configuration from host or another instance
  execute <n> [command]  Execute a Claude Desktop command in instance
  fix-warnings <n>       Fix MaxListenersExceededWarning in an instance
  update-title <n>       Update window title to show instance name
  patch-app <n>          Patch app.asar directly with instance name and fix warnings
  help                   Show this help message

Create Options:
  --format=<deb|appimage>  Specify installation format (default: deb)
  --mcp-auto-approve       Enable automatic approval of MCP tools

MCP Options:
  --auto-approve           Enable automatic approval of MCP tools
  --server <url>           Set custom MCP server URL

Config Options:
  --global-shortcut <key>  Set global shortcut key
  --hide-tray              Hide system tray icon
  --show-tray              Show system tray icon

Examples:
  cmgr create work --mcp-auto-approve    Create a new instance with MCP auto-approval
  cmgr start work                         Start the work instance
  cmgr import-config work                 Import MCP config from host to work instance
  cmgr import-config work personal        Import MCP config from personal to work instance
  cmgr alias work                         Create an alias for the work instance
  cmgr fix-warnings work                  Fix MaxListenersExceededWarning in work instance
  cmgr update-title work                  Update window title to show the instance name
  cmgr mcp work --auto-approve            Configure work instance to auto-approve MCP tools

For more information, see the README.md file.
EOF
}
