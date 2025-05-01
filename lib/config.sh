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
    
    # Get config file using utility function
    local config_file="$(get_sandbox_config_file "$instance_name")"
    
    # Use update_config_file utility function
    local json_expr=".globalShortcut = \"$shortcut\""
    local default_content="{
  \"globalShortcut\": \"$shortcut\"
}"
    
    update_config_file "$config_file" "$json_expr" "$default_content"
    
    echo "Global shortcut configured."
    return 0
}

# Configure tray icon visibility
configure_tray_icon() {
    local instance_name="$1"
    local visibility="$2"
    
    echo "Configuring tray icon visibility for instance '$instance_name' to '$visibility'..."
    
    # Get config file using utility function
    local config_file="$(get_sandbox_config_file "$instance_name")"
    
    # Determine value based on visibility setting
    local show_tray="true"
    if [ "$visibility" = "hide" ]; then
        show_tray="false"
    fi
    
    # Use update_config_file utility function
    local json_expr=".showTray = ($show_tray)"
    local default_content="{
  \"showTray\": $show_tray
}"
    
    update_config_file "$config_file" "$json_expr" "$default_content"
    
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
    
    # Get sandbox config paths using utility functions
    local config_file="$(get_sandbox_config_file "$instance_name")"
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$config_file")"
    
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
    
    # Get config file using utility function
    local config_file="$(get_sandbox_config_file "$instance_name")"
    
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
    
    # Get sandbox directory and paths using utility functions
    local config_dir="$(get_sandbox_config_path "$instance_name")"
    local config_file="$(get_sandbox_config_file "$instance_name")"
    local electron_dir="$(get_sandbox_electron_path "$instance_name")"
    
    # Sandbox user home path - must match the path used in sandbox.sh
    local sandbox_user_home="/home/claude"
    
    # Ensure config directories exist
    mkdir -p "${config_dir}"
    mkdir -p "${electron_dir}"
    
    # Get template directory using utility function
    local template_dir="$(find_template_dir)"
    if [ -z "$template_dir" ]; then
        echo "Warning: Could not find templates directory, using fallbacks"
        template_dir="${SCRIPT_DIR}/../templates"
    fi
    
    # Auto approve JS file content as fallback
    local auto_approve_js_content='// Auto approve script for MCP tools - Created by Claude Desktop Manager
// Derived from the original emsi/claude-desktop project

// Array of trusted tool names.
// If empty ALL tools are accepted!
const trustedTools = [
/*
    "list-allowed-directories",
    "list-denied-directories",
    "ls"
*/
];

// Cooldown tracking
let lastClickTime = 0;
const COOLDOWN_MS = 1000; // 1 second cooldown

const observer = new MutationObserver((mutations) => {
    // Check if we're still in cooldown
    const now = Date.now();
    if (now - lastClickTime < COOLDOWN_MS) {
        console.log("🕒 Still in cooldown period, skipping...");
        return;
    }

    console.log("🔍 Checking mutations...");
    
    const dialog = document.querySelector("[role=\"dialog\"]");
    if (!dialog) return;

    const buttonWithDiv = dialog.querySelector("button div");
    if (!buttonWithDiv) return;

    const toolText = buttonWithDiv.textContent;
    if (!toolText) return;

    console.log("📝 Found tool request:", toolText);
    
    const toolName = toolText.match(/Run (\\S+) from/)?.[1];
    if (!toolName) return;

    console.log("🛠️ Tool name:", toolName);
    
    if (trustedTools.length === 0 || trustedTools.includes(toolName)) {
        const allowButton = Array.from(dialog.querySelectorAll("button"))
            .find(button => button.textContent.includes("Allow for This Chat"));
        
        if (allowButton) {
            console.log("🚀 Auto-approving tool:", toolName);
            lastClickTime = now; // Set cooldown
            allowButton.click();
        }
    } else {
        console.log("❌ Tool not in trusted list:", toolName);
    }
});

// Start observing
console.log("👀 Starting observer for trusted tools:", trustedTools);
observer.observe(document.body, {
    childList: true,
    subtree: true
});'
    
    # Copy or create the auto-approve script using utility function
    copy_or_create_template "${template_dir}/mcp-auto-approve.js" "${electron_dir}/mcp-auto-approve.js" "$auto_approve_js_content" "auto-approve script"
    
    # Create init script to inject the auto-approver
    cat > "${electron_dir}/init.js" <<EOF
// Claude Desktop MCP Auto-Approval Initializer
const fs = require('fs');
const path = require('path');

try {
  // Check if we're in the main process with app available
  if (typeof app !== 'undefined') {
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
    console.log('MCP Auto-Approval system initialized from claude-desktop-manager (main process)');
  } else if (typeof window !== 'undefined' && window.require) {
    // In renderer process, try to get app via remote
    try {
      const { app } = window.require('electron').remote;
      if (app) {
        app.on('browser-window-created', (event, browserWindow) => {
          browserWindow.webContents.on('did-finish-load', () => {
            // Inject auto-approval script
            const scriptPath = path.join(__dirname, 'mcp-auto-approve.js');
            if (fs.existsSync(scriptPath)) {
              const scriptContent = fs.readFileSync(scriptPath, 'utf8');
              browserWindow.webContents.executeJavaScript(scriptContent)
                .catch(err => console.error('Error injecting MCP auto-approver:', err));
            }
          });
        });
        console.log('MCP Auto-Approval system initialized from claude-desktop-manager (renderer process)');
      } else {
        console.log('Could not access app object via remote. Auto-approval may not work properly.');
      }
    } catch (remoteError) {
      console.error('Failed to access remote module:', remoteError);
    }
  } else {
    console.log('Neither app nor window.require is available. Auto-approval will not work in this context.');
  }
} catch (error) {
  console.error('Failed to initialize MCP Auto-Approval:', error);
}
EOF
    
    # Update config file using utility functions
    local init_path="${sandbox_user_home}/.config/Claude/electron/init.js"
    local json_expr=".autoApproveMCP = true | .electronInitScript = \"$init_path\""
    local default_content="{
  \"autoApproveMCP\": true,
  \"electronInitScript\": \"$init_path\"
}"
    
    update_config_file "$config_file" "$json_expr" "$default_content"
    
    echo "MCP auto-approval configured using sandboxed path: ${init_path}"
    return 0
}

# Configure MCP server
configure_mcp_server() {
    local instance_name="$1"
    local server_url="$2"
    
    echo "Configuring MCP server for instance '$instance_name' to '$server_url'..."
    
    # Get config file using utility function
    local config_file="$(get_sandbox_config_file "$instance_name")"
    
    # Use update_config_file utility function
    local json_expr=".mcpServerURL = \"$server_url\""
    local default_content="{
  \"mcpServerURL\": \"$server_url\"
}"
    
    update_config_file "$config_file" "$json_expr" "$default_content"
    
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
    
    # Get config paths using utility functions
    local target_config_dir="$(get_sandbox_config_path "$instance_name")"
    local target_config_file="$(get_sandbox_config_file "$instance_name")"
    
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
        source_config="$(get_sandbox_config_file "$source")"
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
        # Update the electronInitScript path to point to the correct location in the sandbox
        jq --arg instance_dir "/home/claude/.config/Claude/electron" \
           '.electronInitScript = $instance_dir + "/preload.js"' \
           "$target_config_file" > "$tmpfile" && \
        mv "$tmpfile" "$target_config_file"
    fi
    
    echo "MCP configuration imported successfully to instance '$instance_name'."
    echo "You may need to add instance-specific settings such as auto-approve."
    return 0
}