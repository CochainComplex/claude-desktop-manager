#!/bin/bash
# instance.sh - Instance registry and management for Claude Desktop Manager

# Read instance registry
read_registry() {
    cat "${CMGR_REGISTRY}"
}

# Write to instance registry
write_registry() {
    cat > "${CMGR_REGISTRY}"
}

# Get instance data
get_instance() {
    local instance_name="$1"
    read_registry | jq -r ".instances[\"$instance_name\"] // empty"
}

# Check if instance exists
instance_exists() {
    local instance_name="$1"
    local instance
    instance=$(get_instance "$instance_name")
    [ -n "$instance" ]
}

# Add instance to registry
add_instance() {
    local instance_name="$1"
    local sandbox_path="${SANDBOX_BASE}/${instance_name}"
    local build_format="${2:-deb}"
    
    # Check if instance already exists
    if instance_exists "$instance_name"; then
        echo "Instance '$instance_name' already exists."
        return 1
    fi
    
    # Create metadata for instance
    local created_date
    created_date=$(date -Iseconds)
    
    # Add to registry
    local registry
    registry=$(read_registry)
    
    echo "$registry" | jq --arg name "$instance_name" \
                         --arg sandbox "$sandbox_path" \
                         --arg created "$created_date" \
                         --arg format "$build_format" \
                         '.instances[$name] = {
                             "name": $name,
                             "sandbox_path": $sandbox,
                             "created_date": $created,
                             "build_format": $format,
                             "running": false
                         }' | write_registry
    
    echo "Instance '$instance_name' added to registry."
    return 0
}

# Update instance status
update_instance_status() {
    local instance_name="$1"
    local status="$2"
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Update registry
    local registry
    registry=$(read_registry)
    
    echo "$registry" | jq --arg name "$instance_name" \
                         --arg status "$status" \
                         '.instances[$name].running = ($status == "running")' | write_registry
    
    return 0
}

# Remove instance from registry
remove_instance_from_registry() {
    local instance_name="$1"
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Update registry
    local registry
    registry=$(read_registry)
    
    echo "$registry" | jq --arg name "$instance_name" \
                         'del(.instances[$name])' | write_registry
    
    echo "Instance '$instance_name' removed from registry."
    return 0
}

# List all instances
list_instances() {
    local registry
    registry=$(read_registry)
    
    # Pretty print instances
    echo "Claude Desktop Instances:"
    echo "------------------------"
    echo "$registry" | jq -r '.instances | to_entries[] | "\(.value.name) (\(.value.build_format)) - Created: \(.value.created_date) - Running: \(.value.running)"'
    
    return 0
}

# Create a new instance
create_instance() {
    local instance_name="$1"
    shift
    
    # Parse options
    local build_format="deb"
    local mcp_auto_approve="false"
    local configure_ports="true"
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --format)
                build_format="$2"
                shift 2
                ;;
            --format=*)
                build_format="${1#*=}"
                shift
                ;;
            --mcp-auto-approve)
                mcp_auto_approve="true"
                shift
                ;;
            --no-ports)
                configure_ports="false"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Validate build format
    if [ "$build_format" != "deb" ] && [ "$build_format" != "appimage" ]; then
        echo "Error: Invalid build format '$build_format'. Must be 'deb' or 'appimage'."
        return 1
    fi
    
    # Check if instance already exists
    if instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' already exists."
        return 1
    fi
    
    # Check for user namespace support before creating sandbox
    if ! check_userns_enabled &>/dev/null; then
        echo "Warning: Unprivileged user namespaces are not enabled on this system."
        echo "You might see 'setting up uid map: Permission denied' errors, but the sandbox should still function."
        echo "To enable unprivileged user namespaces, run: cmgr enable-userns"
        echo "Continuing with sandbox creation..."
    fi
    
    # Create sandbox
    if ! create_sandbox "$instance_name"; then
        echo "Error: Failed to create sandbox for instance '$instance_name'."
        return 1
    fi
    
    # Add to registry
    if ! add_instance "$instance_name" "$build_format"; then
        echo "Error: Failed to add instance to registry."
        # Clean up sandbox since we failed
        remove_sandbox "$instance_name"
        return 1
    fi
    
    # Check for user namespace support before attempting to install
    # If we detect UID mapping errors, use a minimal installation approach
    local minimal_install=false
    if run_in_sandbox "$instance_name" "command -v bwrap" 2>&1 | grep -q "setting up uid map: Permission denied"; then
        echo "Warning: UID mapping error detected during sandbox check."
        echo "Using minimal installation approach for Claude Desktop."
        minimal_install=true
    fi
    
    # Try to determine if we have UID mapping issues
    local sandbox_test_output
    sandbox_test_output=$(run_in_sandbox "$instance_name" "echo 'Testing sandbox'" 2>&1)
    echo "Sandbox test output: $sandbox_test_output"
    
    if echo "$sandbox_test_output" | grep -q "setting up uid map: Permission denied"; then
        echo "Warning: UID mapping errors detected. Creating a minimal Claude Desktop installation."
        
        # Manual installation approach for systems with user namespace issues
        local sandbox_home="${SANDBOX_BASE}/${instance_name}"
        
        # Create required directories
        mkdir -p "${sandbox_home}/.local/bin"
        mkdir -p "${sandbox_home}/.local/share/claude-desktop"
        mkdir -p "${sandbox_home}/.local/share/applications"
        mkdir -p "${sandbox_home}/.config/Claude/electron"
        
        # Create minimal executable
        cat > "${sandbox_home}/.local/bin/claude-desktop" << 'EOF'
#!/bin/bash
# Minimal Claude Desktop launcher created by CMGR
electron --no-sandbox --disable-dev-shm-usage --js-flags="--expose-gc" "$HOME/.local/share/claude-desktop/app.asar" "$@"
EOF
        chmod +x "${sandbox_home}/.local/bin/claude-desktop"
        
        # Create minimal app.asar
        echo "// Placeholder app.asar for Claude Desktop" > "${sandbox_home}/.local/share/claude-desktop/app.asar"
        
        # Create preload script
        cat > "${sandbox_home}/.config/Claude/electron/preload.js" << 'EOF'
// Preload script for Claude Desktop
console.log('Claude Desktop Manager preload script loaded');

// Set window title based on instance name
if (typeof window !== 'undefined') {
  const instanceName = process.env.CLAUDE_INSTANCE || 'claude';
  
  const updateTitle = () => {
    if (!document.title.includes(`[${instanceName}]`)) {
      document.title = document.title + ` [${instanceName}]`;
    }
  };
  
  if (document.readyState === 'complete') {
    updateTitle();
  }
  
  window.addEventListener('load', updateTitle);
}
EOF
        
        # Create MCP config
        cat > "${sandbox_home}/.config/Claude/claude_desktop_config.json" << 'EOF'
{
  "electronInitScript": "/home/claude/.config/Claude/electron/preload.js",
  "showTray": true
}
EOF
        
        # Create desktop entry
        cat > "${sandbox_home}/.local/share/applications/claude-desktop-${instance_name}.desktop" << EOF
[Desktop Entry]
Name=Claude Desktop (${instance_name})
Comment=Claude Desktop AI Assistant (${instance_name} instance)
Exec=env CLAUDE_INSTANCE=${instance_name} LIBVA_DRIVER_NAME=dummy ${sandbox_home}/.local/bin/claude-desktop --disable-gpu --no-sandbox --disable-dev-shm-usage
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;
StartupWMClass=Claude-${instance_name}
EOF

        # Create verification file
        touch "${sandbox_home}/.claude-install-verified"
        
        echo "✓ Minimal Claude Desktop installation created successfully"
    else
        # Install Claude Desktop using the regular method
        if ! install_claude_in_sandbox "$instance_name" "$build_format"; then
            echo "Error: Failed to install Claude Desktop in sandbox."
            # Clean up the instance from registry and remove sandbox
            remove_instance_from_registry "$instance_name"
            remove_sandbox "$instance_name"
            return 1
        fi
    fi
    
    # Configure MCP auto-approve if requested
    if [ "$mcp_auto_approve" = "true" ]; then
        if ! configure_mcp "$instance_name" --auto-approve; then
            echo "Warning: Failed to configure MCP auto-approve for instance '$instance_name'."
            # Continue since this is not critical
        fi
    fi
    
    # Configure unique MCP ports if requested
    if [ "$configure_ports" = "true" ]; then
        if ! configure_mcp_ports "$instance_name"; then
            echo "Warning: Failed to configure unique MCP ports for instance '$instance_name'."
            # Continue since this is not critical
        fi
    fi
    
    echo "Instance '$instance_name' created successfully!"
    return 0
}

# Helper function to remove sandbox
remove_sandbox() {
    local instance_name="$1"
    local sandbox_path="${SANDBOX_BASE}/${instance_name}"
    
    if [ -d "$sandbox_path" ]; then
        rm -rf "$sandbox_path"
        rm -f "${SANDBOX_BASE}/fake_passwd.${instance_name}"
        echo "Sandbox for instance '$instance_name' removed."
    fi
    
    return 0
}

# Start an instance
start_instance() {
    local instance_name="$1"
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Get instance data
    local instance
    instance=$(get_instance "$instance_name")
    local build_format
    build_format=$(echo "$instance" | jq -r '.build_format')
    
    # Enhanced debug display information before starting with Wayland support
    if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
        echo "Starting instance in Wayland session:"
        echo "  WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
        echo "  XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}"
        echo "  XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
        echo "  DISPLAY=${DISPLAY:-unset} (may be used as fallback)"
    else
        echo "Starting instance in X11 session:"
        echo "  DISPLAY=${DISPLAY:-unset}"
        echo "  XAUTHORITY=${XAUTHORITY:-unset}"
    fi
    
    # Validate sandbox path mapping for consistency
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local sandbox_user_home="$(get_sandbox_homedir)"
    echo "Sandbox path mapping:"
    echo "  Host path: ${sandbox_home}"
    echo "  Sandbox path: ${sandbox_user_home}"
    
    # Check if MCP config exists in the sandbox
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local mcp_config_file="${sandbox_home}/.config/Claude/claude_desktop_config.json"
    
    # Ensure MCP configuration with unique port assignment
    if [ ! -f "$mcp_config_file" ] || ! grep -q "mcpServers" "$mcp_config_file"; then
        echo "Setting up MCP configuration with unique ports..."
        # Load port management module if not already loaded
        if ! command -v configure_mcp_ports &>/dev/null; then
            source "${SCRIPT_DIR}/mcp_ports.sh"
        fi
        configure_mcp_ports "$instance_name"
    fi
    
    # Get the port base for this instance
    local base_port
    base_port=$(get_port_base "$instance_name")
    
    # Get sandbox user info for path consistency
    local sandbox_username="claude"  # Must match the username in sandbox.sh
    local sandbox_user_home="/home/${sandbox_username}" # Must match the path in sandbox.sh
    
    # Execute directly in the sandbox using a bash one-liner
    if [ "$build_format" = "deb" ]; then
        run_in_sandbox "$instance_name" bash -c "
            echo \"Inside sandbox: DISPLAY=\$DISPLAY, XAUTHORITY=\$XAUTHORITY\"
            echo \"MCP configuration path: \$CLAUDE_CONFIG_PATH\"
            echo \"Sandbox username: \$USER\"
            echo \"Sandbox home: \$HOME\"
            
            # Test X11 connection
            if command -v xdpyinfo >/dev/null 2>&1; then
                if ! xdpyinfo >/dev/null 2>&1; then
                    echo \"WARNING: Cannot connect to X server - check X11 configuration\"
                else
                    echo \"X11 connection test successful\"
                fi
            fi
            
            # Set environment variables to suppress Node.js warnings
            export NODE_OPTIONS=\"--no-warnings\"
            export ELECTRON_NO_WARNINGS=1
            
            # Set MCP port environment variables
            export MCP_BASE_PORT=\"$base_port\"
            export FILESYSTEM_PORT=\"$(get_tool_port "$instance_name" "filesystem")\"
            export SEQUENTIAL_THINKING_PORT=\"$(get_tool_port "$instance_name" "sequential-thinking")\"
            export MEMORY_PORT=\"$(get_tool_port "$instance_name" "memory")\"
            export DESKTOP_COMMANDER_PORT=\"$(get_tool_port "$instance_name" "desktop-commander")\"
            export REPL_PORT=\"$(get_tool_port "$instance_name" "repl")\"
            export PLAYWRIGHT_PORT=\"$(get_tool_port "$instance_name" "executeautomation-playwright-mcp-server")\"
            
            echo \"MCP ports configured:\"
            echo \"  Base port: \$MCP_BASE_PORT\"
            echo \"  Filesystem: \$FILESYSTEM_PORT\"
            echo \"  Sequential Thinking: \$SEQUENTIAL_THINKING_PORT\"
            echo \"  Memory: \$MEMORY_PORT\"
            echo \"  Desktop Commander: \$DESKTOP_COMMANDER_PORT\"
            echo \"  REPL: \$REPL_PORT\"
            echo \"  Playwright: \$PLAYWRIGHT_PORT\"
            
            # Set Electron flags with Wayland/X11 compatibility for Ubuntu 24.04
            if [ -n \"\${WAYLAND_DISPLAY:-}\" ] || [ \"\${XDG_SESSION_TYPE:-}\" = \"wayland\" ]; then
                echo \"Configuring Electron for Wayland session\"
                export ELECTRON_FLAGS=\"--no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader --ozone-platform=wayland --enable-features=WaylandWindowDecorations\"
            else
                echo \"Configuring Electron for X11 session\"
                export ELECTRON_FLAGS=\"--disable-gpu --no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader\"
            fi
            
            # Check if preload script exists in either location
            if [ -f \"\$HOME/.config/Claude/electron/preload.js\" ]; then
                ELECTRON_FLAGS=\"\$ELECTRON_FLAGS --js-flags=\\\"--expose-gc\\\" --preload=\$HOME/.config/Claude/electron/preload.js\"
                echo \"Using preload script: \$HOME/.config/Claude/electron/preload.js\"
            elif [ -f \"\$HOME/.config/claude-desktop/preload.js\" ]; then
                ELECTRON_FLAGS=\"\$ELECTRON_FLAGS --js-flags=\\\"--expose-gc\\\" --preload=\$HOME/.config/claude-desktop/preload.js\"
                echo \"Using preload script: \$HOME/.config/claude-desktop/preload.js\"
            else
                echo \"WARNING: Preload script not found\"
            fi
            
            # Export LIBVA_DRIVER_NAME to avoid libva errors
            export LIBVA_DRIVER_NAME=dummy
            
            # Set the CLAUDE_INSTANCE environment variable for window title
            export CLAUDE_INSTANCE=\"$instance_name\"
            
            # Verify config path
            echo \"Checking if config file exists: \$CLAUDE_CONFIG_PATH\"
            if [ -f \"\$CLAUDE_CONFIG_PATH\" ]; then
                echo \"✓ Config file exists\"
                echo \"Config file content:\"
                cat \"\$CLAUDE_CONFIG_PATH\"
            else
                echo \"❌ Config file does not exist: \$CLAUDE_CONFIG_PATH\"
            fi
            
            # Add MCP configuration flag if environment variable is set
            if [ -n \"\$CLAUDE_CONFIG_PATH\" ] && [ -f \"\$CLAUDE_CONFIG_PATH\" ]; then
                echo \"Using MCP configuration from: \$CLAUDE_CONFIG_PATH\"
                # Add config path to electron flags if supported by Claude desktop
                ELECTRON_FLAGS=\"\$ELECTRON_FLAGS --configPath=\$CLAUDE_CONFIG_PATH\"
            fi
            
            # These paths should not be accessible in the sandbox
            if [ -d \"${HOME}\" ] || [ -d \"/home/${SUDO_USER:-$(whoami)}\" ]; then
                # Add debug information if we can still access real home
                echo \"WARNING: Still have access to real user's home directory!\"
                echo \"Sandbox is not fully isolated.\"
                if [ -d \"${HOME}/.config/Claude\" ]; then
                    echo \"CRITICAL: Can access real Claude config at: ${HOME}/.config/Claude\"
                fi
                
                # Try to fix access by mounting a temporary filesystem over the real home
                if [ -d \"/home/${SUDO_USER:-$(whoami)}\" ]; then
                    echo \"Attempting to block access to /home/${SUDO_USER:-$(whoami)} with tmpfs...\"
                    mkdir -p /tmp/empty
                    if ! mount -t tmpfs none \"/home/${SUDO_USER:-$(whoami)}\" 2>/dev/null; then
                        echo \"Mount failed, no permission. Sandboxing may be incomplete.\"
                    else
                        echo \"Successfully blocked access to real home with tmpfs.\"
                    fi
                fi
            else
                echo \"✓ Cannot access real user's home directory (expected behavior)\"
            fi
            
            if [ -x \"\$HOME/.local/bin/claude-desktop\" ]; then
                echo \"Starting Claude Desktop (deb format) with flags: \$ELECTRON_FLAGS\"
                echo \"Instance name: \$CLAUDE_INSTANCE\"
                \$HOME/.local/bin/claude-desktop \$ELECTRON_FLAGS
            else
                echo \"Error: Claude Desktop not found at \$HOME/.local/bin/claude-desktop\"
                exit 1
            fi
        " &
    else
        run_in_sandbox "$instance_name" bash -c "
            echo \"Inside sandbox: DISPLAY=\$DISPLAY, XAUTHORITY=\$XAUTHORITY\"
            echo \"MCP configuration path: \$CLAUDE_CONFIG_PATH\"
            echo \"Sandbox username: \$USER\"
            echo \"Sandbox home: \$HOME\"
            
            # Test X11 connection
            if command -v xdpyinfo >/dev/null 2>&1; then
                if ! xdpyinfo >/dev/null 2>&1; then
                    echo \"WARNING: Cannot connect to X server - check X11 configuration\"
                else
                    echo \"X11 connection test successful\"
                fi
            fi
            
            # Set environment variables to suppress Node.js warnings
            export NODE_OPTIONS=\"--no-warnings\"
            export ELECTRON_NO_WARNINGS=1
            
            # Set MCP port environment variables
            export MCP_BASE_PORT=\"$base_port\"
            export FILESYSTEM_PORT=\"$(get_tool_port "$instance_name" "filesystem")\"
            export SEQUENTIAL_THINKING_PORT=\"$(get_tool_port "$instance_name" "sequential-thinking")\"
            export MEMORY_PORT=\"$(get_tool_port "$instance_name" "memory")\"
            export DESKTOP_COMMANDER_PORT=\"$(get_tool_port "$instance_name" "desktop-commander")\"
            export REPL_PORT=\"$(get_tool_port "$instance_name" "repl")\"
            export PLAYWRIGHT_PORT=\"$(get_tool_port "$instance_name" "executeautomation-playwright-mcp-server")\"
            
            echo \"MCP ports configured:\"
            echo \"  Base port: \$MCP_BASE_PORT\"
            echo \"  Filesystem: \$FILESYSTEM_PORT\"
            echo \"  Sequential Thinking: \$SEQUENTIAL_THINKING_PORT\"
            echo \"  Memory: \$MEMORY_PORT\"
            echo \"  Desktop Commander: \$DESKTOP_COMMANDER_PORT\"
            echo \"  REPL: \$REPL_PORT\"
            echo \"  Playwright: \$PLAYWRIGHT_PORT\"
            
            # Set Electron flags with Wayland/X11 compatibility for Ubuntu 24.04
            if [ -n \"\${WAYLAND_DISPLAY:-}\" ] || [ \"\${XDG_SESSION_TYPE:-}\" = \"wayland\" ]; then
                echo \"Configuring Electron for Wayland session\"
                export ELECTRON_FLAGS=\"--no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader --ozone-platform=wayland --enable-features=WaylandWindowDecorations\"
            else
                echo \"Configuring Electron for X11 session\"
                export ELECTRON_FLAGS=\"--disable-gpu --no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader\"
            fi
            
            # Check if preload script exists in either location
            if [ -f \"\$HOME/.config/Claude/electron/preload.js\" ]; then
                ELECTRON_FLAGS=\"\$ELECTRON_FLAGS --js-flags=\\\"--expose-gc\\\" --preload=\$HOME/.config/Claude/electron/preload.js\"
                echo \"Using preload script: \$HOME/.config/Claude/electron/preload.js\"
            elif [ -f \"\$HOME/.config/claude-desktop/preload.js\" ]; then
                ELECTRON_FLAGS=\"\$ELECTRON_FLAGS --js-flags=\\\"--expose-gc\\\" --preload=\$HOME/.config/claude-desktop/preload.js\"
                echo \"Using preload script: \$HOME/.config/claude-desktop/preload.js\"
            else
                echo \"WARNING: Preload script not found\"
            fi
            
            # Export LIBVA_DRIVER_NAME to avoid libva errors
            export LIBVA_DRIVER_NAME=dummy
            # Set the CLAUDE_INSTANCE environment variable for window title
            export CLAUDE_INSTANCE=\"$instance_name\"
            
            # Verify config path
            echo \"Checking if config file exists: \$CLAUDE_CONFIG_PATH\"
            if [ -f \"\$CLAUDE_CONFIG_PATH\" ]; then
                echo \"✓ Config file exists\"
                echo \"Config file content:\"
                cat \"\$CLAUDE_CONFIG_PATH\"
            else
                echo \"❌ Config file does not exist: \$CLAUDE_CONFIG_PATH\"
            fi
            
            # Check if we can access the real user's home directory (should fail)
            if [ -d \"${HOME}\" ]; then
                echo \"WARNING: Still have access to real user's home directory: ${HOME}\"
                ls -la \"${HOME}/.config/Claude\" 2>/dev/null && echo \"Can access real user's Claude config!\"
            else
                echo \"✓ Cannot access real user's home directory (expected behavior)\"
            fi
            
            # Add MCP configuration flag if environment variable is set
            if [ -n \"\$CLAUDE_CONFIG_PATH\" ] && [ -f \"\$CLAUDE_CONFIG_PATH\" ]; then
                echo \"Using MCP configuration from: \$CLAUDE_CONFIG_PATH\"
                # Add config path to electron flags if supported by Claude desktop
                ELECTRON_FLAGS=\"\$ELECTRON_FLAGS --configPath=\$CLAUDE_CONFIG_PATH\"
            fi
            
            # Find Claude-specific AppImage first, then fall back to any AppImage
            appimage_file=\$(find \"\$HOME/Downloads\" -type f -name \"*[Cc]laude*.AppImage\" 2>/dev/null | head -1)
            if [ -z \"\$appimage_file\" ]; then
                # Fallback to any AppImage if no Claude-specific one is found
                appimage_file=\$(find \"\$HOME/Downloads\" -type f -name \"*.AppImage\" 2>/dev/null | head -1)
            fi
            
            if [ -n \"\$appimage_file\" ] && [ -x \"\$appimage_file\" ]; then
                echo \"Starting Claude Desktop (AppImage format) with flags: \$ELECTRON_FLAGS\"
                echo \"Instance name: \$CLAUDE_INSTANCE\"
                \$appimage_file \$ELECTRON_FLAGS
            else
                echo \"Error: AppImage not found or not executable\"
                exit 1
            fi
        " &
    fi
    
    # Small delay to allow process to start
    sleep 1
    
    # Update instance status
    update_instance_status "$instance_name" "running"
    
    echo "Instance '$instance_name' started with MCP base port: $base_port"
    echo "You can now use MCP tools with this instance without port conflicts."
    return 0
}

# Stop an instance
stop_instance() {
    local instance_name="$1"
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Find and kill Claude Desktop process in the sandbox
    local pid
    pid=$(ps aux | grep "bwrap.*${instance_name}" | grep -v grep | awk '{print $2}')
    
    if [ -n "$pid" ]; then
        kill "$pid"
        echo "Stopping instance '$instance_name'..."
        sleep 2
        
        # Check if process is still running
        if ps -p "$pid" > /dev/null; then
            echo "Process is still running, sending SIGKILL..."
            kill -9 "$pid"
        fi
    else
        echo "Instance '$instance_name' is not running."
    fi
    
    # Update instance status
    update_instance_status "$instance_name" "stopped"
    
    echo "Instance '$instance_name' stopped."
    return 0
}

# Execute a Claude Desktop command in an instance
execute_claude_command() {
    local instance_name="$1"
    shift
    local command="$@"
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Get instance data
    local instance
    instance=$(get_instance "$instance_name")
    local build_format
    build_format=$(echo "$instance" | jq -r '.build_format')
    
    echo "Executing command '$command' in instance '$instance_name'"
    
    # Execute directly with bash -c to avoid temp file issues
    if [ "$build_format" = "deb" ]; then
        run_in_sandbox "$instance_name" bash -c "
            # Add display debugging info
            echo \"Debug: DISPLAY=\$DISPLAY\"
            echo \"Debug: XAUTHORITY=\$XAUTHORITY\"
            
            # Execute Claude Desktop command
            if [ -x \"\$HOME/.local/bin/claude-desktop\" ]; then
                \"\$HOME/.local/bin/claude-desktop\" $command
            else
                echo \"Claude Desktop executable not found at \$HOME/.local/bin/claude-desktop\"
                exit 1
            fi
        "
        local result=$?
    else
        run_in_sandbox "$instance_name" bash -c "
            # Add display debugging info
            echo \"Debug: DISPLAY=\$DISPLAY\"
            echo \"Debug: XAUTHORITY=\$XAUTHORITY\"
            
            # For AppImage format
            appimage_file=\$(find \"\$HOME/Downloads\" -name \"*.AppImage\" | head -1)
            if [ -n \"\$appimage_file\" ] && [ -x \"\$appimage_file\" ]; then
                \"\$appimage_file\" $command
            else
                echo \"Claude Desktop AppImage not found or not executable\"
                exit 1
            fi
        "
        local result=$?
    fi
    
    return $result
}

# Remove an instance
remove_instance() {
    local instance_name="$1"
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Stop instance if running
    local instance
    instance=$(get_instance "$instance_name")
    local is_running
    is_running=$(echo "$instance" | jq -r '.running')
    
    if [ "$is_running" = "true" ]; then
        stop_instance "$instance_name"
    fi
    
    # Release allocated port range
    if command -v release_port_range &>/dev/null; then
        release_port_range "$instance_name"
        echo "Port allocation for instance '$instance_name' released."
    else
        # Load port management module if not already loaded
        source "${SCRIPT_DIR}/mcp_ports.sh"
        release_port_range "$instance_name"
        echo "Port allocation for instance '$instance_name' released."
    fi
    
    # Remove sandbox
    local sandbox_path
    sandbox_path=$(echo "$instance" | jq -r '.sandbox_path')
    
    if [ -d "$sandbox_path" ]; then
        rm -rf "$sandbox_path"
        echo "Sandbox for instance '$instance_name' removed."
    fi
    
    # Remove fake passwd file
    rm -f "${SANDBOX_BASE}/fake_passwd.${instance_name}"
    
    # Remove from registry
    remove_instance_from_registry "$instance_name"
    
    echo "Instance '$instance_name' removed successfully."
    return 0
}
