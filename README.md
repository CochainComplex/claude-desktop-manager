# Claude Desktop Manager

A utility for creating and managing multiple isolated instances of Claude Desktop on Linux systems.

## Overview

Claude Desktop Manager (`cmgr`) enables users to maintain different Claude Desktop environments with separate settings, conversations, and MCP configurations. Each instance is sandboxed using bubblewrap to ensure complete isolation.

This project extends [emsi/claude-desktop](https://github.com/emsi/claude-desktop), an unofficial Linux port of Anthropic's Claude Desktop application.

## Features

- Create isolated Claude Desktop instances using bubblewrap sandboxing
- Generate and manage quick-access aliases for each instance
- Launch, list, and remove instances with simple commands
- Support auto-approval of MCP (Machine-Computer Protocol) tools
- Generate desktop shortcuts for system integration

## Requirements

- Debian-based Linux system (Ubuntu, Pop!_OS, etc.)
- claude-desktop (base application)
- bubblewrap (for sandboxing)
- electron (for application runtime)
- jq (for JSON processing)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/claude-desktop-manager.git
   cd claude-desktop-manager
   ```

2. Ensure dependencies are installed:
   ```bash
   sudo apt update
   sudo apt install bubblewrap jq git p7zip-full wget nodejs npm
   ```

3. Make the main script executable:
   ```bash
   chmod +x cmgr
   ```

4. Optionally, install system-wide:
   ```bash
   sudo ln -s $(pwd)/cmgr /usr/local/bin/cmgr
   ```

5. Run the tool to automatically build and cache Claude Desktop:
   ```bash
   ./cmgr create my-first-instance
   ```
   
   This will clone the Claude Desktop repository, build it, and create your first instance.

## Usage

### Basic Commands

```bash
# Create a new Claude Desktop instance
cmgr create my-instance

# Launch an instance
cmgr start my-instance

# List all instances
cmgr list

# Stop a running instance
cmgr stop my-instance

# Remove an instance
cmgr remove my-instance

# Get help
cmgr help
```

The `cmgr` tool provides a set of commands for managing Claude Desktop instances. Each command is designed to be simple and intuitive:

- `create`: Create a new isolated Claude Desktop instance
- `list`: Display all available instances with status information
- `start`: Launch a specific instance
- `stop`: Terminate a running instance
- `remove`: Completely remove an instance and its data
- `config`: Configure instance settings like shortcuts and tray icon
- `alias`: Create command aliases for quick access
- `desktop`: Generate desktop shortcuts for easy launching
- `mcp`: Configure MCP tool settings and auto-approval
- `execute`: Run commands within an instance's sandbox
- `help`: Display usage information

### Advanced Usage

```bash
# Create instance with specific format and auto-approved MCP tools
cmgr create research --format=appimage --mcp-auto-approve

# Configure global shortcut for an instance
cmgr config work --global-shortcut="CommandOrControl+Shift+A"

# Hide system tray icon for an instance
cmgr config personal --hide-tray

# Create a command alias for quick access
cmgr alias work work-claude

# Create a desktop shortcut
cmgr desktop personal

# Configure MCP auto-approval for all tools
cmgr mcp research --auto-approve

# Execute a command in the Claude Desktop instance
cmgr execute work getWindowArguments []
```

## Directory Structure

The Claude Desktop Manager uses the following directory structure:

- `~/.cmgr/` - Main configuration directory
- `~/.cmgr/registry.json` - Instance registry
- `~/.cmgr/cache/` - Cache directory
- `~/.cmgr/logs/` - Log files
- `~/sandboxes/` - Base directory for sandbox environments
- `~/sandboxes/<instance-name>/` - Sandbox for a specific instance

## Graphics Hardware Notes

Claude Desktop Manager implements several techniques to ensure compatibility with different graphics hardware configurations:

1. **Hardware Acceleration Disabled**: All instances run with `--disable-gpu` flag to prevent common rendering issues
2. **LIBVA Driver Management**: Uses `LIBVA_DRIVER_NAME=dummy` to prevent Intel graphics errors
3. **Device Access**: Explicitly binds graphics devices in the sandbox environment
4. **SwiftShader Support**: Enables software rendering fallback with the `--enable-unsafe-swiftshader` flag

These measures prevent common errors like:
- `libva error: i965_drv_video.so init failed`
- `Automatic fallback to software WebGL has been deprecated`
- `MaxListenersExceededWarning` related to Electron's EventEmitter

## MCP Tool Integration

Claude Desktop Manager provides robust support for MCP (Machine-Computer Protocol) tools, which enable Claude to interact with your computer.

### Auto-approval Configuration

The auto-approval system can be configured in two ways:

1. During instance creation:
   ```bash
   cmgr create my-instance --mcp-auto-approve
   ```

2. For an existing instance:
   ```bash
   cmgr mcp my-instance --auto-approve
   ```

This automatically configures the instance to approve MCP tool requests without prompting, which is useful for productivity workflows.

### How the Auto-approval Works

The auto-approval system works by:

1. Installing a JavaScript observer script in the sandbox that monitors for tool approval dialogs
2. When a dialog appears, it automatically clicks the "Allow for This Chat" button
3. Implements a 1-second cooldown to prevent rapid approval of multiple tools

You can view the script at `templates/mcp-auto-approve.js`. It uses DOM observation to detect and interact with the MCP approval dialogs.

### Trusted Tools Configuration

By default, the auto-approval system will approve all MCP tool requests. You can restrict approvals to specific tools by modifying the `.config/Claude/electron/mcp-auto-approve.js` file within the sandbox:

```javascript
const trustedTools = [
    'list-allowed-directories',
    'list_directory',
    'read_file',
    'search_files',
    'sequentialthinking',
    'execute_command'
];
```

When the trusted tools array is empty, all tools are automatically approved. When specific tools are listed, only those tools will be auto-approved.

### Accessing the Auto-approval Script

You can edit the auto-approval script directly:

```bash
# Edit using your preferred editor
cmgr execute my-instance nano ~/.config/Claude/electron/mcp-auto-approve.js
```

### Using MCP Tools in Claude

Claude Desktop supports several powerful MCP tools, including:

- **Sequential Thinking**: Break down complex problems into steps
- **File System Tools**: Read, write, and manipulate files
- **Code Analysis**: Execute code and analyze results
- **Knowledge Graph**: Create and manipulate knowledge graphs

These tools can be accessed within Claude conversations when approved.

## Troubleshooting

### Display Issues

If you encounter display issues:

1. Make sure X11 is properly configured
2. Check if the `DISPLAY` and `XAUTHORITY` environment variables are correctly set
3. Ensure the sandbox has access to the graphics devices

```bash
# Check X11 connection
xdpyinfo

# See if graphics devices are accessible
ls -la /dev/dri

# Check for NVIDIA devices
ls -la /dev/nvidia*
```

The Claude Desktop Manager implements several measures to prevent common graphics errors:

- Sets `LIBVA_DRIVER_NAME=dummy` to avoid Intel graphics driver errors
- Uses the `--disable-gpu` flag to prevent rendering issues
- Enables software rendering fallback with `--enable-unsafe-swiftshader`
- Explicitly binds graphics devices into the sandbox

### Starting Claude Desktop Manually

If you're having trouble starting Claude Desktop, you can try launching it manually:

```bash
# For .deb installations in the sandbox
cmgr execute my-instance bash -c 'LIBVA_DRIVER_NAME=dummy $HOME/.local/bin/claude-desktop --disable-gpu --no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader'

# For AppImage installations in the sandbox
cmgr execute my-instance bash -c 'LIBVA_DRIVER_NAME=dummy $(find $HOME/Downloads -name "*.AppImage" | head -1) --disable-gpu --no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader'
```

### Sandbox Access

If you need to debug sandbox issues:

```bash
# Get a shell in the sandbox environment
cmgr execute my-instance bash
```

You can also inspect the sandbox environment more directly:

```bash
# Get a shell with direct bubblewrap access
bwrap --bind ~/sandboxes/my-instance /home/$(whoami) \
      --proc /proc --dev /dev --tmpfs /tmp \
      --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib \
      --ro-bind /etc /etc --bind /tmp/.X11-unix /tmp/.X11-unix \
      --setenv DISPLAY "$DISPLAY" \
      /bin/bash
```

### Logs

Check logs for detailed information:

```bash
# Main installer logs
cat ~/.cmgr/logs/installer.log

# Check sandbox initialization
ls -la ~/sandboxes/my-instance/.cmgr_initialized

# List processes to see if Claude is running
ps aux | grep claude
```

### MCP Auto-Approval Issues

If MCP tools aren't being auto-approved:

1. Check if the auto-approve script is properly installed:
   ```bash
   cmgr execute my-instance ls -la ~/.config/Claude/electron/mcp-auto-approve.js
   ```

2. Make sure the preload script is configured:
   ```bash
   cmgr execute my-instance cat ~/.config/Claude/claude_desktop_config.json
   ```

3. Update the auto-approval configuration:
   ```bash
   cmgr mcp my-instance --auto-approve
   ```

## Uninstallation

To completely remove Claude Desktop Manager:

```bash
# Remove all instances
for instance in $(cmgr list | grep -oP '^\w+'); do
  cmgr remove $instance
done

# Remove the cmgr directory
rm -rf ~/.cmgr

# Remove sandbox directories
rm -rf ~/sandboxes

# Remove symlink (if installed system-wide)
sudo rm /usr/local/bin/cmgr
```

## License

Claude Desktop Manager is dual-licensed under both the MIT license and the Apache License (Version 2.0).

This means you can choose either license, depending on which better suits your needs:

- **MIT License**: A permissive license with very few restrictions
- **Apache License 2.0**: A permissive license with patent grants and contribution terms

See [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE) for the full license texts.

### Copyright

Copyright (c) 2025 Alexander Warth - Claude Desktop Manager  
Portions Copyright (c) 2024 aaddrick (claude-desktop-debian)  
Portions Copyright (c) 2024 emsi (claude-desktop)  
Portions Copyright (c) 2024 Claude Desktop Linux Maintainers  
Portions Copyright (c) 2019 k3d3

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in this work by you shall be dual-licensed as above, without any additional terms or conditions.

## Development

### Code Organization

- `cmgr` - Main entry point script
- `lib/` - Core functionality modules
  - `dependencies.sh` - Dependency checking
  - `sandbox.sh` - Bubblewrap sandbox management
  - `installer.sh` - Claude Desktop installation
  - `instance.sh` - Instance management
  - `config.sh` - Configuration management
  - `desktop.sh` - Desktop integration
  - `help.sh` - Help and usage information
- `templates/` - Template files
  - `mcp-auto-approve.js` - MCP auto-approval script
  - `bash_alias.template` - Template for bash aliases
  - `desktop_entry.desktop` - Template for desktop entries
- `src/` - Source code for additional tools
- `scripts/` - Utility scripts
- `tests/` - Test scripts

### Adding New Features

When adding new features:
1. Follow the existing code organization
2. Use appropriate error handling
3. Update documentation
4. Test thoroughly with different hardware configurations

### Using MCP Tools for Development

When developing with Claude Desktop, you can use the MCP tools to:

1. **Sequential Thinking**: Break down complex problems and plan implementation steps
2. **Desktop Commander**: Navigate and manipulate the codebase efficiently

## Attribution

This project is derived from two key sources:

1. The original [aaddrick/claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) project, which created the first Debian/Ubuntu build scripts for Claude Desktop

2. The [emsi/claude-desktop](https://github.com/emsi/claude-desktop) fork, which expanded on the original project with additional features

Both projects are unofficial Linux ports of Anthropic's Claude Desktop application and are dual-licensed under MIT and Apache 2.0.

## Disclaimer

This is an unofficial utility not affiliated with Anthropic. All code focuses on managing the Claude Desktop application, not modifying it. The sandbox security is designed to protect users' systems while providing access to necessary resources.