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
  execute <n> [command]  Execute a Claude Desktop command in instance
  help                   Show this help message

Examples:
  cmgr create work               Create a new instance named "work"
  cmgr start work                Start the work instance
  cmgr alias work                Create an alias for the work instance
  cmgr execute work getWindowArguments []  Run a Claude command in instance

For more information, see the README.md file.
EOF
}
