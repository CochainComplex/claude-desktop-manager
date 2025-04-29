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
                echo "  --ports                     Configure unique ports for MCP tools"
                echo "  --reset-ports               Reset port configuration"
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
            --ports)
                configure_mcp_ports "$instance_name"
                shift
                ;;
            --reset-ports)
                reset_mcp_ports "$instance_name"
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

# Configure unique ports for MCP tools
configure_mcp_ports() {
    local instance_name="$1"
    
    echo "Configuring unique MCP ports for instance '$instance_name'..."
    
    # Get sandbox directory
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local config_dir="${sandbox_home}/.config/Claude"
    local config_file="${config_dir}/claude_desktop_config.json"
    
    # Ensure config directory exists
    mkdir -p "${config_dir}"
    
    # Load port management module if not already loaded
    if ! command -v get_port_base &>/dev/null; then
        source "${SCRIPT_DIR}/lib/mcp_ports.sh"
    fi
    
    # Allocate port range if not already allocated
    local base_port
    base_port=$(get_port_base "$instance_name")
    
    # Generate MCP server configuration with unique ports
    generate_mcp_server_config "$instance_name" "$config_file"
    
    echo "MCP ports configured for instance '$instance_name' (base port: $base_port)"
    echo "The following MCP tools have been configured with unique ports:"
    echo "  - filesystem:            $(get_tool_port "$instance_name" "filesystem")"
    echo "  - sequential-thinking:   $(get_tool_port "$instance_name" "sequential-thinking")"
    echo "  - memory:                $(get_tool_port "$instance_name" "memory")"
    echo "  - desktop-commander:     $(get_tool_port "$instance_name" "desktop-commander")"
    echo "  - repl:                  $(get_tool_port "$instance_name" "repl")"
    echo "  - playwright-mcp-server: $(get_tool_port "$instance_name" "executeautomation-playwright-mcp-server")"
    
    return 0
}

# Reset port configuration
reset_mcp_ports() {
    local instance_name="$1"
    
    echo "Resetting MCP port configuration for instance '$instance_name'..."
    
    # Load port management module if not already loaded
    if ! command -v release_port_range &>/dev/null; then
        source "${SCRIPT_DIR}/lib/mcp_ports.sh"
    fi
    
    # Release allocated port range
    release_port_range "$instance_name"
    
    # Get sandbox directory
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local config_dir="${sandbox_home}/.config/Claude"
    local config_file="${config_dir}/claude_desktop_config.json"
    
    # Check if config file exists
    if [ -f "$config_file" ]; then
        # Remove mcpServers configuration if present
        jq 'del(.mcpServers)' "$config_file" > "${config_file}.tmp" && \
        mv "${config_file}.tmp" "$config_file"
    fi
    
    echo "MCP port configuration reset. The instance will use default ports."
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
  console.log('MCP Auto-Approval system initialized from claude-desktop-manager');
} catch (error) {
  console.error('Failed to initialize MCP Auto-Approval:', error);
}
EOF
    
    # Create or update config file
    if [ -f "$config_file" ]; then
        # Update existing config with the absolute path to avoid $HOME expansion issues
        local absolute_init_path="${config_dir}/electron/init.js"
        absolute_init_path="${absolute_init_path/#$HOME/\$HOME}" # Replace real home with $HOME variable for portability
        
        jq --arg initpath "$absolute_init_path" '.autoApproveMCP = true | .electronInitScript = $initpath' "$config_file" > "${config_file}.tmp" && \
        mv "${config_file}.tmp" "$config_file"
    else
        # Create new config with absolute path
        local absolute_init_path="${config_dir}/electron/init.js"
        absolute_init_path="${absolute_init_path/#$HOME/\$HOME}" # Replace real home with $HOME variable for portability
        
        cat > "$config_file" <<EOF
{
  "autoApproveMCP": true,
  "electronInitScript": "${absolute_init_path}"
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

# Import MCP configuration from host or another instance
import_mcp_config() {
    local instance_name="$1"
    local source="${2:-host}"
    
    # Check if target instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    local target_sandbox="${SANDBOX_BASE}/${instance_name}"
    local target_config_dir="${target_sandbox}/.config/Claude"
    local target_config_file="${target_config_dir}/claude_desktop_config.json"
    
    # Ensure target config directory exists
    mkdir -p "${target_config_dir}"
    
    # Determine source config path
    local source_config
    if [ "$source" = "host" ]; then
        # Import from host system
        source_config="${HOME}/.config/Claude/claude_desktop_config.json"
        echo "Importing MCP configuration from host system..."
    else
        # Import from another instance
        if ! instance_exists "$source"; then
            echo "Error: Source instance '$source' does not exist."
            return 1
        fi
        source_config="${SANDBOX_BASE}/${source}/.config/Claude/claude_desktop_config.json"
        echo "Importing MCP configuration from instance '$source'..."
    fi
    
    # Check if source config exists
    if [ ! -f "$source_config" ]; then
        echo "Error: Source configuration not found at ${source_config}"
        return 1
    fi
    
    # Copy the configuration file
    cp "$source_config" "$target_config_file"
    
    # Update paths in the configuration to reflect the target instance
    local tmpfile="${target_config_file}.tmp"
    
    # If electron init script path exists, update it
    if grep -q "electronInitScript" "$target_config_file"; then
        # Update the electronInitScript path to point to the correct location
        jq --arg instance "$instance_name" \
           '.electronInitScript = .electronInitScript | 
            sub("/Claude/"; "/Claude/")' \
           "$target_config_file" > "$tmpfile" && \
        mv "$tmpfile" "$target_config_file"
    fi
    
    echo "MCP configuration imported successfully to instance '$instance_name'."
    echo "You may need to add instance-specific settings such as auto-approve."
    return 0
}
