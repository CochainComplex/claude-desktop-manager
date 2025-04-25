#!/bin/bash
# config.sh - Configuration management for Claude Desktop Manager

# Configure instance settings
configure_instance() {
    local instance_name="$1"
    shift
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --help)
                echo "Usage: cmgr config <instance> [options]"
                echo ""
                echo "Options:"
                echo "  --global-shortcut <shortcut>  Configure global shortcut"
                echo "  --hide-tray                   Hide system tray icon"
                echo "  --show-tray                   Show system tray icon"
                echo ""
                return 0
                ;;
            --global-shortcut)
                configure_global_shortcut "$instance_name" "$2"
                shift 2
                ;;
            --global-shortcut=*)
                configure_global_shortcut "$instance_name" "${1#*=}"
                shift
                ;;
            --hide-tray)
                configure_tray_icon "$instance_name" "hide"
                shift
                ;;
            --show-tray)
                configure_tray_icon "$instance_name" "show"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    return 0
}

# Configure global shortcut
configure_global_shortcut() {
    local instance_name="$1"
    local shortcut="$2"
    
    echo "Configuring global shortcut for instance '$instance_name' to '$shortcut'..."
    
    # Config file is inside the sandbox but from the user's perspective
    # it should be at the regular ~/.config path
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local config_dir="${sandbox_home}/.config/Claude"
    local config_file="${config_dir}/claude_desktop_config.json"
    
    # Ensure config directory exists
    mkdir -p "${config_dir}"
    
    # Create or update config file
    if [ -f "$config_file" ]; then
        # Update existing config
        jq --arg shortcut "$shortcut" '.globalShortcut = $shortcut' "$config_file" > "${config_file}.tmp" && \
        mv "${config_file}.tmp" "$config_file"
    else
        # Create new config
        cat > "$config_file" <<EOF
{
  "globalShortcut": "$shortcut"
}
EOF
    fi
    
    echo "Global shortcut configured."
    return 0
}

# Configure tray icon visibility
configure_tray_icon() {
    local instance_name="$1"
    local visibility="$2"
    
    echo "Configuring tray icon visibility for instance '$instance_name' to '$visibility'..."
    
    # Get config file path inside sandbox
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local config_file="${sandbox_home}/.config/Claude/claude_desktop_config.json"
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$config_file")"
    
    # Determine value based on visibility setting
    local show_tray="true"
    if [ "$visibility" = "hide" ]; then
        show_tray="false"
    fi
    
    # Create or update config file
    if [ -f "$config_file" ]; then
        # Update existing config
        jq --arg show "$show_tray" '.showTray = ($show == "true")' "$config_file" > "${config_file}.tmp" && \
        mv "${config_file}.tmp" "$config_file"
    else
        # Create new config
        cat > "$config_file" <<EOF
{
  "showTray": $show_tray
}
EOF
    fi
    
    echo "Tray icon visibility configured."
    return 0
}

# Configure MCP settings
configure_mcp() {
    local instance_name="$1"
    shift
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --help)
                echo "Usage: cmgr mcp <instance> [options]"
                echo ""
                echo "Options:"
                echo "  --auto-approve              Enable auto-approval for all MCP tools"
                echo "  --server <url>              Set custom MCP server URL"
                echo ""
                return 0
                ;;
            --auto-approve)
                configure_mcp_auto_approve "$instance_name"
                shift
                ;;
            --server)
                configure_mcp_server "$instance_name" "$2"
                shift 2
                ;;
            --server=*)
                configure_mcp_server "$instance_name" "${1#*=}"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    return 0
}

# Configure MCP auto-approval
configure_mcp_auto_approve() {
    local instance_name="$1"
    
    echo "Configuring MCP auto-approval for instance '$instance_name'..."
    
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local config_dir="${sandbox_home}/.config/Claude"
    local config_file="${config_dir}/claude_desktop_config.json"
    local electron_dir="${config_dir}/electron"
    
    # Ensure config directories exist
    mkdir -p "${config_dir}"
    mkdir -p "${electron_dir}"
    
    # Copy the MCP auto-approve script to the instance
    cp "${SCRIPT_DIR}/templates/mcp-auto-approve.js" "${electron_dir}/"
    
    # Create init script to inject the auto-approver
    cat > "${electron_dir}/init.js" <<EOF
// Claude Desktop MCP Auto-Approval Initializer
const fs = require('fs');
const path = require('path');

try {
  // Set up event listener for window creation
  app.on('browser-window-created', (event, window) => {
    window.webContents.on('did-finish-load', () => {
      // Inject auto-approval script
      const scriptPath = path.join(__dirname, 'mcp-auto-approve.js');
      if (fs.existsSync(scriptPath)) {
        const scriptContent = fs.readFileSync(scriptPath, 'utf8');
        window.webContents.executeJavaScript(scriptContent)
          .catch(err => console.error('Error injecting MCP auto-approver:', err));
      }
    });
  });
  console.log('MCP Auto-Approval system initialized from emsi/claude-desktop');
} catch (error) {
  console.error('Failed to initialize MCP Auto-Approval:', error);
}
EOF
    
    # Create or update config file
    if [ -f "$config_file" ]; then
        # Update existing config with the path as it would appear inside the sandbox
        jq '.autoApproveMCP = true | .electronInitScript = "$HOME/.config/Claude/electron/init.js"' "$config_file" > "${config_file}.tmp" && \
        mv "${config_file}.tmp" "$config_file"
    else
        # Create new config
        cat > "$config_file" <<EOF
{
  "autoApproveMCP": true,
  "electronInitScript": "$HOME/.config/Claude/electron/init.js"
}
EOF
    fi
    
    echo "MCP auto-approval configured."
    return 0
}

# Configure MCP server
configure_mcp_server() {
    local instance_name="$1"
    local server_url="$2"
    
    echo "Configuring MCP server for instance '$instance_name' to '$server_url'..."
    
    # Get config file path inside sandbox
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local config_file="${sandbox_home}/.config/Claude/claude_desktop_config.json"
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$config_file")"
    
    # Create or update config file
    if [ -f "$config_file" ]; then
        # Update existing config
        jq --arg url "$server_url" '.mcpServerURL = $url' "$config_file" > "${config_file}.tmp" && \
        mv "${config_file}.tmp" "$config_file"
    else
        # Create new config
        cat > "$config_file" <<EOF
{
  "mcpServerURL": "$server_url"
}
EOF
    fi
    
    echo "MCP server configured."
    return 0
}
