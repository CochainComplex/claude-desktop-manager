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
  host-path <cmd> <n> [path] Manage host filesystem paths for sandbox access
  filesystem <n> <path>   Configure MCP filesystem to use a host path
  fix-warnings <n>       Fix MaxListenersExceededWarning in an instance
  update-title <n>       Update window title to show instance name
  verify-isolation <n>   Verify that sandbox isolation is working correctly
  patch-app <n>          Patch app.asar directly with instance name and fix warnings
  build                  Build the latest Claude Desktop .deb package
  mcp-gui                Launch the global MCP manager GUI
  help                   Show this help message

Create Options:
  --format=<deb|appimage>  Specify installation format (default: deb)
  --mcp-auto-approve       Enable automatic approval of MCP tools
  --no-ports               Don't configure unique MCP ports (not recommended)
  --force-rebuild          Force rebuild of Claude Desktop package even if cached

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
  cmgr create work --force-rebuild       Create instance and rebuild package (ignores cache)
  cmgr host-path add work /home/awarth/Projects   Add access to a host directory
  cmgr host-path list work               List all accessible host paths for an instance
  cmgr filesystem work /home/awarth/Devstuff   Configure MCP filesystem with host path
  cmgr start work                         Start the work instance
  cmgr import-config work                 Import MCP config from host to work instance
  cmgr import-config work personal        Import MCP config from personal to work instance
  cmgr alias work                         Create an alias for the work instance
  cmgr fix-warnings work                  Fix MaxListenersExceededWarning in work instance
  cmgr update-title work                  Update window title to show the instance name
  cmgr verify-isolation work              Verify that sandbox isolation is working correctly
  cmgr mcp work --auto-approve            Configure work instance to auto-approve MCP tools
  cmgr mcp work --ports                   Configure unique MCP ports for work instance
  cmgr mcp work --reset-ports             Reset MCP port configuration for work instance
  cmgr build                              Build the latest Claude Desktop .deb package
  cmgr mcp-gui                            Launch the global MCP server manager

Multiple Instance Management:
  By default, each Claude Desktop instance is created with unique port ranges for MCP tools
  to avoid conflicts when running multiple instances simultaneously. This allows you to use
  tools like filesystem, sequential-thinking, and memory in each instance independently.

  Base port assignment:
    - Default port range starts at 9000
    - Each instance gets a 100-port range (instance1: 9000-9099, instance2: 9100-9199, etc.)
    - Tool-specific ports are assigned within each range

Host Path Management:
  The Claude Desktop Manager can expose specific host directories to the sandboxed instances
  while maintaining isolation for the rest of the system. This is particularly useful for 
  MCP tools like the filesystem server that need to access real files.

  Commands for managing host paths:
    - host-path add <instance> <path>:   Add a host directory to be accessible in sandbox
    - host-path remove <instance> <path>: Remove a previously added host path
    - host-path list <instance>:         List all accessible host paths
    - filesystem <instance> <path>:      Configure MCP filesystem to use a specific host path

For more information, see the README.md file.
EOF
}
