# Claude Desktop Manager (cmgr)

Claude Desktop Manager is a utility for creating and managing multiple isolated instances of Claude Desktop on Linux systems. It allows users to maintain different Claude Desktop environments with separate settings, conversations, and MCP configurations.

## Features

- Create isolated Claude Desktop instances using bubblewrap sandboxing
- Generate and manage quick-access aliases for each instance
- Launch, list, and remove instances with simple commands
- Support auto-approval of MCP tools per instance
- Configure custom MCP servers for different instances
- Generate desktop shortcuts for system integration

## Prerequisites

- A Debian-based Linux distribution (Ubuntu, Pop!_OS, Mint, etc.)
- bubblewrap (for sandboxing)
- jq (for JSON processing)
- Basic build dependencies for Claude Desktop

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/claude-desktop-manager.git
   cd claude-desktop-manager
   ```

2. Make the main script executable:
   ```bash
   chmod +x cmgr
   ```

3. Install dependencies:
   ```bash
   sudo apt update
   sudo apt install -y bubblewrap jq git
   ```

## Usage

### Creating a new instance

```bash
./cmgr create work
```

This will:
1. Create a new sandbox for the instance
2. Build and cache Claude Desktop (if not already cached)
3. Install Claude Desktop in the sandbox
4. Register the instance in the manager

Options:
- `--format deb|appimage` - Specify package format (default: deb)
- `--mcp-auto-approve` - Enable auto-approval for MCP tools

### Listing instances

```bash
./cmgr list
```

Shows all registered instances with their status.

### Starting an instance

```bash
./cmgr start work
```

Starts the Claude Desktop instance named "work".

### Stopping an instance

```bash
./cmgr stop work
```

Stops a running instance.

### Removing an instance

```bash
./cmgr remove work
```

Completely removes an instance, including its sandbox and registration.

### Creating an alias

```bash
./cmgr alias work
```

Creates a shell alias (`claude-work`) for quickly starting the instance.

### Creating a desktop shortcut

```bash
./cmgr desktop work
```

Creates a desktop entry for launching the instance.

### Configuring MCP settings

```bash
# Enable auto-approval for all MCP tools
./cmgr mcp work --auto-approve

# Set custom MCP server
./cmgr mcp work --server http://localhost:8000
```

### Configuring instance settings

```bash
# Change global shortcut
./cmgr config work --global-shortcut "CommandOrControl+Alt+W"

# Hide tray icon
./cmgr config work --hide-tray
```

## How It Works

Claude Desktop Manager uses several technologies to manage isolated instances:

1. **Bubblewrap (bwrap)** for creating secure sandboxes with:
   - Separate home directories
   - Process isolation
   - Controlled system access
   - X11 forwarding for GUI

2. **Instance Management**:
   - Each instance has its own sandbox
   - Instances are registered in a central registry
   - Instances can be started, stopped, and configured independently

3. **MCP Integration**:
   - Each instance can have different MCP settings
   - Auto-approval can be configured per instance
   - Custom MCP servers can be specified

## Technical Architecture

```
/
├── cmgr                    # Main executable script
├── lib/                    # Core libraries
│   ├── sandbox.sh          # Bubblewrap sandbox creation utilities
│   ├── installer.sh        # Claude Desktop installation functions
│   ├── instance.sh         # Instance management functions
│   ├── config.sh           # Configuration management
│   └── desktop.sh          # Desktop integration utilities
├── templates/              # Configuration templates
│   ├── desktop_entry.desktop   # Desktop shortcut template
│   └── bash_alias.template     # Bash alias template
└── ~/.cmgr/                # User data directory (created at runtime)
    ├── cache/              # Claude Desktop package cache
    └── registry.json       # Instance registry
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is dual-licensed under the MIT License and Apache License 2.0, maintaining compatibility with the claude-desktop project.

## Acknowledgements

- Based on [emsi/claude-desktop](https://github.com/emsi/claude-desktop)
- Inspired by the original work from [aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian)
