#!/bin/bash
# help.sh - Help and usage information for Claude Desktop Manager

# IMPORTANT: Within sandbox environments, home path is always /home/claude
# When referring to paths inside the sandbox, always use /home/claude explicitly
# rather than using $HOME substitution for clarity and consistency

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
  enable-userns        Enable unprivileged user namespaces (needed for sandboxing)
  patch-app <n>          Patch app.asar directly with instance name and fix warnings
  help                   Show this help message

Create Options:
  --format=<deb|appimage>  Specify installation format (default: deb)
  --mcp-auto-approve       Enable automatic approval of MCP tools
  --no-ports               Don't configure unique MCP ports (not recommended)

MCP Options:
  --auto-approve           Enable automatic approval of MCP tools
  --server <url>           Set custom MCP server URL
  --ports                  Configure unique ports for MCP tools
  --reset-ports            Reset port configuration

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
  cmgr enable-userns                      Enable unprivileged user namespaces (on Ubuntu 24.04+)
  cmgr fix-warnings work                  Fix MaxListenersExceededWarning in work instance
  cmgr update-title work                  Update window title to show the instance name
  cmgr mcp work --auto-approve            Configure work instance to auto-approve MCP tools
  cmgr mcp work --ports                   Configure unique MCP ports for work instance
  cmgr mcp work --reset-ports             Reset MCP port configuration for work instance

Multiple Instance Management:
  By default, each Claude Desktop instance is created with unique port ranges for MCP tools
  to avoid conflicts when running multiple instances simultaneously. This allows you to use
  tools like filesystem, sequential-thinking, and memory in each instance independently.

  Base port assignment:
    - Default port range starts at 9000
    - Each instance gets a 100-port range (instance1: 9000-9099, instance2: 9100-9199, etc.)
    - Tool-specific ports are assigned within each range

For more information, see the README.md file.
EOF
}
