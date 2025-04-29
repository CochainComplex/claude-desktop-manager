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
    
    # Install Claude Desktop
    if ! install_claude_in_sandbox "$instance_name" "$build_format"; then
        echo "Error: Failed to install Claude Desktop in sandbox."
        # Clean up the instance from registry and remove sandbox
        remove_instance_from_registry "$instance_name"
        remove_sandbox "$instance_name"
        return 1
    fi
    
    # Configure MCP auto-approve if requested
    if [ "$mcp_auto_approve" = "true" ]; then
        if ! configure_mcp "$instance_name" --auto-approve; then
            echo "Warning: Failed to configure MCP auto-approve for instance '$instance_name'."
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
    
    # Debug display information before starting
    echo "Starting instance with DISPLAY=${DISPLAY:-unset}, XAUTHORITY=${XAUTHORITY:-unset}"
    
    # Check if MCP config exists in the sandbox
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local mcp_config_file="${sandbox_home}/.config/Claude/claude_desktop_config.json"
    
    if [ ! -f "$mcp_config_file" ]; then
        echo "Warning: MCP configuration file not found in sandbox. Creating default config..."
        mkdir -p "${sandbox_home}/.config/Claude"
        cat > "$mcp_config_file" <<EOF
{
  "showTray": true,
  "electronInitScript": "$HOME/.config/Claude/electron/preload.js"
}
EOF
    fi
    
    # Execute directly in the sandbox using a bash one-liner
    if [ "$build_format" = "deb" ]; then
        run_in_sandbox "$instance_name" bash -c '
            echo "Inside sandbox: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY"
            echo "MCP configuration path: $CLAUDE_CONFIG_PATH"
            
            # Test X11 connection
            if command -v xdpyinfo >/dev/null 2>&1; then
                if ! xdpyinfo >/dev/null 2>&1; then
                    echo "WARNING: Cannot connect to X server - check X11 configuration"
                else
                    echo "X11 connection test successful"
                fi
            fi
            
            # Set environment variables to suppress Node.js warnings
            export NODE_OPTIONS="--no-warnings"
            export ELECTRON_NO_WARNINGS=1
            
            # Set Electron flags to prevent common graphics issues
            export ELECTRON_FLAGS="--disable-gpu --no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader"
            
            # Check if preload script exists in either location
            if [ -f "$HOME/.config/Claude/electron/preload.js" ]; then
                ELECTRON_FLAGS="$ELECTRON_FLAGS --js-flags=\"--expose-gc\" --preload=$HOME/.config/Claude/electron/preload.js"
                echo "Using preload script: $HOME/.config/Claude/electron/preload.js"
            elif [ -f "$HOME/.config/claude-desktop/preload.js" ]; then
                ELECTRON_FLAGS="$ELECTRON_FLAGS --js-flags=\"--expose-gc\" --preload=$HOME/.config/claude-desktop/preload.js"
                echo "Using preload script: $HOME/.config/claude-desktop/preload.js"
            else
                echo "WARNING: Preload script not found"
            fi
            
            # Export LIBVA_DRIVER_NAME to avoid libva errors
            export LIBVA_DRIVER_NAME=dummy
            
            # Set the CLAUDE_INSTANCE environment variable for window title
            export CLAUDE_INSTANCE="$CLAUDE_INSTANCE"
            
            # Add MCP configuration flag if environment variable is set
            if [ -n "$CLAUDE_CONFIG_PATH" ] && [ -f "$CLAUDE_CONFIG_PATH" ]; then
                echo "Using MCP configuration from: $CLAUDE_CONFIG_PATH"
                # Add config path to electron flags if supported by Claude desktop
                if grep -q "configPath" "$HOME/.local/bin/claude-desktop" 2>/dev/null; then
                    ELECTRON_FLAGS="$ELECTRON_FLAGS --configPath=$CLAUDE_CONFIG_PATH"
                fi
            fi
            
            if [ -x "$HOME/.local/bin/claude-desktop" ]; then
                echo "Starting Claude Desktop (deb format) with flags: $ELECTRON_FLAGS"
                echo "Instance name: $CLAUDE_INSTANCE"
                $HOME/.local/bin/claude-desktop $ELECTRON_FLAGS
            else
                echo "Error: Claude Desktop not found at $HOME/.local/bin/claude-desktop"
                exit 1
            fi
        ' &
    else
        run_in_sandbox "$instance_name" bash -c '
            echo "Inside sandbox: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY"
            echo "MCP configuration path: $CLAUDE_CONFIG_PATH"
            
            # Test X11 connection
            if command -v xdpyinfo >/dev/null 2>&1; then
                if ! xdpyinfo >/dev/null 2>&1; then
                    echo "WARNING: Cannot connect to X server - check X11 configuration"
                else
                    echo "X11 connection test successful"
                fi
            fi
            
            # Set environment variables to suppress Node.js warnings
            export NODE_OPTIONS="--no-warnings"
            export ELECTRON_NO_WARNINGS=1
            
            # Set Electron flags to prevent common graphics issues
            export ELECTRON_FLAGS="--disable-gpu --no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader"
            
            # Check if preload script exists in either location
            if [ -f "$HOME/.config/Claude/electron/preload.js" ]; then
                ELECTRON_FLAGS="$ELECTRON_FLAGS --js-flags=\"--expose-gc\" --preload=$HOME/.config/Claude/electron/preload.js"
                echo "Using preload script: $HOME/.config/Claude/electron/preload.js"
            elif [ -f "$HOME/.config/claude-desktop/preload.js" ]; then
                ELECTRON_FLAGS="$ELECTRON_FLAGS --js-flags=\"--expose-gc\" --preload=$HOME/.config/claude-desktop/preload.js"
                echo "Using preload script: $HOME/.config/claude-desktop/preload.js"
            else
                echo "WARNING: Preload script not found"
            fi
            
            # Export LIBVA_DRIVER_NAME to avoid libva errors
            export LIBVA_DRIVER_NAME=dummy
            # Set the CLAUDE_INSTANCE environment variable for window title
            export CLAUDE_INSTANCE="$CLAUDE_INSTANCE"
            
            # Add MCP configuration flag if environment variable is set
            if [ -n "$CLAUDE_CONFIG_PATH" ] && [ -f "$CLAUDE_CONFIG_PATH" ]; then
                echo "Using MCP configuration from: $CLAUDE_CONFIG_PATH"
                # Add config path to electron flags if supported by Claude desktop
                ELECTRON_FLAGS="$ELECTRON_FLAGS --configPath=$CLAUDE_CONFIG_PATH"
            fi
            
            # Find AppImage
            appimage_file=$(find "$HOME/Downloads" -type f -name "*.AppImage" | head -1)
            if [ -n "$appimage_file" ] && [ -x "$appimage_file" ]; then
                echo "Starting Claude Desktop (AppImage format) with flags: $ELECTRON_FLAGS"
                echo "Instance name: $CLAUDE_INSTANCE"
                $appimage_file $ELECTRON_FLAGS
            else
                echo "Error: AppImage not found or not executable"
                exit 1
            fi
        ' &
    fi
    
    # Small delay to allow process to start
    sleep 1
    
    # Update instance status
    update_instance_status "$instance_name" "running"
    
    echo "Instance '$instance_name' started."
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
    pid=$(ps aux | grep "bubblewrap.*${instance_name}" | grep -v grep | awk '{print $2}')
    
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
