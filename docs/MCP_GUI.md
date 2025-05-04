# MCP GUI Manager

The MCP GUI Manager is a graphical user interface for managing MCP (Model Context Protocol) servers in Claude Desktop Manager. It allows you to monitor, configure, and control MCP servers across all your Claude Desktop instances.

## Features

- **Global Instance Management**: Manage all your Claude Desktop instances from a single interface
- **Server Templates**: Create and save MCP server templates for easy reuse
- **Centralized Configuration**: Configure MCP servers for any instance
- **Live Monitoring**: View real-time status and logs of running MCP servers
- **One-Click Deployment**: Deploy server templates to one or all instances
- **Port Management**: Automatic port allocation to prevent conflicts

## Installation

The MCP GUI Manager is included with Claude Desktop Manager. To install the required dependencies, run:

```bash
cmgr mcp-gui
```

This will check for dependencies, install them if needed, and launch the GUI.

If you encounter issues with dependencies, you can run the dependency installer script directly:

```bash
/path/to/claude-desktop-manager/scripts/install_mcp_gui_deps.sh
```

## Usage

### Launching the MCP GUI

To launch the MCP GUI Manager:

```bash
cmgr mcp-gui
```

### Managing Instances

1. Use the instance selector at the top of the window to switch between instances
2. The left panel shows the running MCP servers for the selected instance
3. Click "Start Instance" or "Stop Instance" to control the Claude Desktop application

### Managing MCP Servers

1. Select a server from the list to view its status and logs
2. Click "Start Server" or "Stop Server" to control individual servers
3. Use the "MCP Servers" tab to configure server settings
4. Apply server templates to quickly set up common configurations

### Creating Server Templates

1. Go to the "Server Templates" tab
2. Click "New Template" to create a template
3. Fill in the template details and click "Save Template"
4. Templates can be applied to any instance

### Deploying Templates to All Instances

1. Select a template from the dropdown
2. Go to Tools > Deploy Template to All Instances
3. Confirm the deployment
4. The template will be applied to all instances with proper port management

## Troubleshooting

### Python Dependencies

If you encounter issues with Python dependencies:

1. Make sure Python 3 is installed
2. Install the python3-venv package:
   ```bash
   sudo apt install python3-venv
   ```
3. For Python 3.12+, you need to install python3.12-venv:
   ```bash
   sudo apt install python3.12-venv
   ```

### PyQt5 Installation Issues

If you have issues installing PyQt5:

1. Install system packages:
   ```bash
   sudo apt install python3-pyqt5 python3-pyqt5.qtwebengine qt5-qmake
   ```
2. Reinstall the Python dependencies:
   ```bash
   /path/to/claude-desktop-manager/scripts/install_mcp_gui_deps.sh
   ```

### Port Conflicts

If you see "Server disconnected" errors:

1. Check if the ports are in use by other applications
2. Reset the port configuration:
   ```bash
   cmgr mcp my-instance --reset-ports
   ```
3. Restart the instance:
   ```bash
   cmgr stop my-instance
   cmgr start my-instance
   ```

## Advanced Configuration

### Custom MCP Servers

To add a custom MCP server:

1. Create a new template in the "Server Templates" tab
2. Set the server name, command, and arguments
3. Save the template and apply it to your instances

### Environment Variables

Each server can have custom environment variables:

- Set variables in the "Environment Variables" field
- Use one variable per line in KEY=VALUE format
- Special variables:
  - `MCP_PORT`: The port for this server (set automatically)
  - `CLAUDE_INSTANCE`: The instance name (set automatically)
  - `HOME`: The sandbox home path (set automatically)

### Log Files

Logs for the MCP GUI are stored in:
```
~/.cmgr/logs/mcp_gui.log
```

You can view these logs to troubleshoot issues with the GUI application.
