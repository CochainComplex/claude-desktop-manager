# Claude Desktop Manager - Isolation Fix

This document explains the changes made to improve the sandboxing and isolation of Claude Desktop instances.

## Problem Description

The original Claude Desktop Manager had issues with sandbox isolation:

1. Claude Desktop instances could access the real user's home directory (`/home/${SUDO_USER:-$(whoami)}`), including MCP configurations
2. The sandbox was using a path mapping that maintained access to the real home directory
3. MCP configurations were using incorrect paths

## Key Fixes Implemented

### 1. Consistent Sandbox User Environment

- Changed sandbox to use a consistent user name (`claude`) and home path (`/home/claude`)
- Modified all path references to use this consistent naming scheme
- Added blocking of real user home via `--tmpfs` mount

### 2. Fixed Installation Process

- Rewrote the installation script to handle .deb extraction properly
- Added clear debugging information during installation
- Added fallback mechanisms when installation fails
- Improved error handling throughout the process

### 3. Enhanced MCP Configuration

- Updated MCP server configurations to use the sandbox home path
- Ensured all MCP tools receive the correct environment variables
- Properly isolated MCP configurations between instances

### 4. Improved Display Handling

- Added detection and configuration of the X11 display
- Set proper XAUTHORITY paths for display access
- Added diagnostics to help troubleshoot display issues

## Usage Notes

Even with these fixes, there may still be some limitations:

1. **X11 Display Access**: If the application fails to start with `Missing X server or $DISPLAY` errors, you may need to run:
   ```bash
   xhost +local:
   ```
   before starting Claude Desktop to allow local connections to the X server.

2. **Additional Isolation**: The improved sandbox isolation is now built directly into the sandbox.sh module and does not require a separate script.

3. **Creating New Instances**: Always prefer to create fresh instances rather than modifying existing ones:
   ```bash
   ./cmgr create <instance-name>
   ```

## Verification

To verify that the sandbox is properly isolated:

1. The output from executing commands should show:
   ```
   ✓ Cannot access real user's home directory (expected behavior)
   ```

2. If you still see access to the real home directory, create a new instance which will use the improved isolation.

3. Check that all paths in MCP configs use `/home/claude` rather than `/home/${SUDO_USER:-$(whoami)}`.

## Future Improvements

Future versions of Claude Desktop Manager could implement:

1. A dedicated X server for each sandbox instance
2. More aggressive sandbox isolation using user namespaces or other container technologies
3. Better handling of display and input for GUI applications

## Credits

These fixes were implemented to improve the original Claude Desktop Manager project.
