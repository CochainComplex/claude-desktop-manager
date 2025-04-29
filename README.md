# Claude Desktop Manager

A utility for creating and managing multiple isolated instances of Claude Desktop on Linux systems.

## Overview

Claude Desktop Manager (`cmgr`) enables users to maintain different Claude Desktop environments with separate settings, conversations, and MCP configurations. Each instance is sandboxed using bubblewrap to ensure complete isolation.

This project extends [emsi/claude-desktop](https://github.com/emsi/claude-desktop), an unofficial Linux port of Anthropic's Claude Desktop application.

## Features

- Create isolated Claude Desktop instances using bubblewrap sandboxing
- Run multiple instances simultaneously with independent MCP tools
- Automatic port management to prevent tool conflicts between instances
- Generate and manage quick-access aliases for each instance
- Launch, list, and remove instances with simple commands
- Support auto-approval of MCP (Model Context Protocol) tools
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

# Create instance without port management (not recommended)
cmgr create legacy --no-ports

# Configure global shortcut for an instance
cmgr config work --global-shortcut="CommandOrControl+Shift+A"

# Hide system tray icon for an instance
cmgr config personal --hide-tray

# Update window title to show the instance name
cmgr update-title research

# Create a command alias for quick access
cmgr alias work work-claude

# Create a desktop shortcut
cmgr desktop personal

# Configure MCP auto-approval for all tools
cmgr mcp research --auto-approve

# Configure unique ports for an existing instance
cmgr mcp legacy --ports

# Reset port configuration if having issues
cmgr mcp work --reset-ports

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

## Window Title Customization

Claude Desktop Manager now includes window title customization to help you identify different instances more easily. Each Claude Desktop window will show its instance name in the title bar (e.g., "Claude [work]"), making it easier to distinguish between multiple open instances.

This feature is automatically enabled for new instances created with the latest version. For existing instances, you can enable it with:

```bash
cmgr update-title my-instance
```

The window title customization works through several complementary mechanisms:

1. **Environment Variables**: Each instance is launched with a `CLAUDE_INSTANCE` environment variable
2. **Preload Script**: A script monitors and updates the window title to include the instance name
3. **Desktop Entry**: The `StartupWMClass` is set to `Claude-<instance-name>` for proper window manager integration
4. **Application Title**: The application title shown in the desktop environment includes the instance name

This helps you keep track of which instance is which, especially when working with multiple Claude personas or projects.

## Max Listeners Warning Fix

Claude Desktop Manager implements a comprehensive approach to prevent the common `MaxListenersExceededWarning` error:

1. **Code Patching**: During installation, the application automatically patches the Electron application code to increase event listener limits
2. **Environment Variables**: Sets `NODE_OPTIONS=--no-warnings` and `ELECTRON_NO_WARNINGS=1` to suppress warnings
3. **Enhanced Preload Script**: Uses a sophisticated preload script that patches EventEmitter and DOM event handling
4. **Console Redirection**: Intercepts and filters console warnings related to MaxListenersExceededWarning

These fixes work together to ensure you won't see the annoying warning:
```
MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 destroyed listeners added to [WebContents]. MaxListeners is 10.
```

If you still experience this warning, you can:

1. Reinstall the instance with the latest fixes:
   ```bash
   cmgr remove problem-instance
   cmgr create problem-instance
   ```

2. Manually apply the fix to an existing instance:
   ```bash
   cmgr execute my-instance 'node ~/.config/claude-desktop/fix-listeners.js ~/.local/share/claude-desktop'
   ```

## Application Patching

Claude Desktop Manager automatically patches the Claude Desktop application during installation to enable multiple instances with separate configurations. For system-wide installations (in `/usr/lib/`), special handling is required.

See the [Patching Documentation](docs/PATCHING.md) for details on:

- How the patching process works
- Handling system vs. user installations
- Manual patch application when needed
- Backup and recovery options

## MCP Tool Integration

Claude Desktop Manager provides robust support for MCP (Model Context Protocol) tools, which enable Claude to interact with your computer.

### Multiple Instance Support with Port Management

One of the key features of Claude Desktop Manager is its ability to run multiple Claude instances simultaneously with fully functional MCP tools. This is achieved through an intelligent port management system that:

1. **Assigns unique port ranges** to each instance (no port conflicts)
2. **Configures MCP servers** to use their designated ports
3. **Tracks port allocations** to prevent overlaps
4. **Sets environment variables** to ensure proper tool operation

Port allocation is automatic and requires no user intervention:

```bash
# Creating two instances (each gets its own port range)
cmgr create work
cmgr create personal

# Run both instances simultaneously
cmgr start work
cmgr start personal

# Now you can use all MCP tools in both instances without conflicts!
```

Port ranges are allocated as follows:
- Base port starts at 9000
- Each instance gets a 100-port range (instance1: 9000-9099, instance2: 9100-9199, etc.)
- Tools are assigned specific offsets within each range:
  - filesystem: +10
  - sequential-thinking: +20
  - memory: +30
  - desktop-commander: +40
  - repl: +50
  - etc.

For more details, see [MCP Port Management](docs/MCP_PORT_MANAGEMENT.md).

### MCP Configuration Management

Each Claude Desktop instance has its own isolated MCP configuration stored within its sandbox. When you create a new instance:

1. The system creates the necessary config directories in the sandbox
2. It copies any existing MCP configuration from your host system or creates a default one
3. The sandbox environment includes the `CLAUDE_CONFIG_PATH` environment variable that points Claude Desktop to the correct configuration file
4. Port assignments are configured automatically to prevent conflicts

All configuration files are automatically created in:
```
~/sandboxes/<instance-name>/.config/Claude/
```

This ensures Claude Desktop always uses the correct configuration files for each instance, maintaining complete isolation between different Claude environments.

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

### Unprivileged User Namespaces

On Ubuntu 24.04 and newer systems, unprivileged user namespaces are disabled by default for security reasons. This may cause the following error when creating sandboxes:

```
bwrap: setting up uid map: Permission denied
```

This error is non-fatal - the sandbox will still be created and function properly despite this message. To eliminate this error message, you can enable unprivileged user namespaces with the following command:

```bash
cmgr enable-userns
```

This will attempt to enable unprivileged user namespaces system-wide. If you don't have sudo privileges, you can ask your system administrator to run:

```bash
sudo sysctl -w kernel.unprivileged_userns_clone=1
echo 'kernel.unprivileged_userns_clone = 1' | sudo tee /etc/sysctl.d/00-local-userns.conf
```

### System Permissions for Patching

If you encounter errors during instance creation related to patching the `app.asar` file in system directories (e.g., `/usr/lib/claude-desktop/`), follow these steps:

1. Complete the instance creation process (it will continue despite patching errors)
2. Apply the pending patch with elevated privileges:

   ```bash
   sudo /path/to/claude-desktop-manager/scripts/apply-system-patches.sh
   ```
   
This script will safely apply all pending patches to system locations. If multiple instances need patching, the script will handle them all in one execution.

For more details on the patching process and troubleshooting, see the [Patching Documentation](docs/PATCHING.md).

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

### MCP Connection Issues

If you experience "Server disconnected" errors or other MCP connection issues:

1. Make sure you're using the latest port management system:
   ```bash
   cmgr mcp my-instance --ports
   ```

2. Check what ports are currently in use:
   ```bash
   cmgr execute my-instance bash -c 'ss -tulpn | grep -E "9[0-9]{3}"'
   ```

3. If you suspect port conflicts, reset the port configuration:
   ```bash
   cmgr mcp my-instance --reset-ports
   cmgr stop my-instance
   cmgr start my-instance
   ```

4. For persistent issues, try restarting with no nodejs warnings:
   ```bash
   cmgr execute my-instance bash -c 'NODE_OPTIONS="--no-warnings" ELECTRON_NO_WARNINGS=1 $HOME/.local/bin/claude-desktop'
   ```

## Uninstallation

### Using the Purge Script (Recommended)

A purge script is provided for completely removing Claude Desktop Manager and all associated files:

```bash
# Download the purge script
wget -O purge-claude-manager.sh https://raw.githubusercontent.com/your-username/claude-desktop-manager/main/scripts/purge-claude-manager.sh

# Make it executable
chmod +x purge-claude-manager.sh

# Run the script
./purge-claude-manager.sh
```

The script will:
1. Remove all Claude Desktop instances
2. Remove all configuration files and cache
3. Remove command-line aliases
4. Remove desktop shortcuts
5. Optionally remove system-wide installation
6. Optionally remove Claude Desktop application files

For safety, the script requires you to type 'PURGE ALL CLAUDE DATA' to confirm deletion.

### Manual Uninstallation

If you prefer to manually uninstall, follow these steps:

```bash
# Remove all instances
for instance in $(cmgr list | grep -oP '^\w+'); do
  cmgr remove $instance
done

# Remove the cmgr directories
rm -rf ~/.cmgr

# Remove all sandbox directories
rm -rf ~/sandboxes

# Remove aliases from bash_aliases
sed -i '/alias claude-/d' ~/.bash_aliases

# Remove desktop shortcuts
rm -f ~/.local/share/applications/claude-*.desktop

# Remove system-wide installation (if installed)
sudo rm -f /usr/local/bin/cmgr
```

This will completely remove Claude Desktop Manager and all its associated files from your system.

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