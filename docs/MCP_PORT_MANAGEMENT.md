# MCP Port Management in Claude Desktop Manager

This document describes how Claude Desktop Manager handles port management for Model Context Protocol (MCP) tools across multiple Claude Desktop instances.

## Problem

When running multiple Claude Desktop instances simultaneously, MCP tools like filesystem, sequential-thinking, and memory may try to use the same ports, causing connection conflicts. This leads to:

- "Server disconnected" errors for MCP tools
- Toast notification timeouts
- Unresponsive UI elements
- MCP tools failing to function properly

## Solution

Claude Desktop Manager implements a port management system that:

1. Allocates a unique port range for each Claude instance
2. Configures all MCP servers to use ports within their assigned range
3. Tracks allocated ports to prevent conflicts
4. Sets required environment variables to ensure proper MCP server operation

## Implementation

### Port Allocation Strategy

- Base port starts at 9000
- Each instance gets a 100-port range:
  - Instance 1: 9000-9099
  - Instance 2: 9100-9199
  - Instance 3: 9200-9299
  - And so on...

### Tool-Specific Port Assignments

Each MCP tool is assigned a specific offset within the instance's port range:

| Tool                   | Offset | Example (Instance 1) |
|------------------------|--------|---------------------|
| filesystem             | +10    | 9010                |
| sequential-thinking    | +20    | 9020                |
| memory                 | +30    | 9030                |
| desktop-commander      | +40    | 9040                |
| repl                   | +50    | 9050                |
| playwright-mcp-server  | +60    | 9060                |
| Other tools            | +10-99 | 9010-9099           |

### MCP Configuration

The port assignments are automatically applied through:

1. Custom `claude_desktop_config.json` for each instance
2. Environment variables set during instance startup
3. Command-line arguments when starting MCP servers

### Commands

The following commands manage MCP port configuration:

- `cmgr create <instance> [--no-ports]` - Create an instance with automatic port allocation (default)
- `cmgr mcp <instance> --ports` - Configure unique MCP ports for an existing instance
- `cmgr mcp <instance> --reset-ports` - Reset the port configuration to defaults

## Troubleshooting

If you still experience connection issues:

1. Check for port conflicts with `ss -tulpn | grep <port>` (replace `<port>` with the actual port number)
2. Reset port allocation with `cmgr mcp <instance> --reset-ports`
3. Restart the instance with `cmgr stop <instance>` followed by `cmgr start <instance>`

## Advanced Configuration

For advanced users who need to customize port allocation:

1. Edit the `~/.cmgr/port_registry.json` file to see current port allocations
2. Modify the `MCP_BASE_PORT` and `MCP_PORT_RANGE` variables in `lib/mcp_ports.sh` if needed
3. Use `cmgr mcp <instance> --ports` to regenerate the configuration after changes

## Technical Details

The port management system is implemented in:

- `lib/mcp_ports.sh` - Core port allocation functions
- `lib/config.sh` - Configuration integration
- `lib/instance.sh` - Instance startup with port environment setup

Port configuration is stored in:
- `~/.cmgr/port_registry.json` - Global port registry
- `~/sandboxes/<instance>/.config/Claude/claude_desktop_config.json` - Instance-specific MCP configuration
