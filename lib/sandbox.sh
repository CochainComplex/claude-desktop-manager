#!/bin/bash
# sandbox.sh - Enhanced sandbox management module for Claude Desktop Manager

# IMPORTANT: Within sandbox environments, home path is always /home/claude
# When referring to paths inside the sandbox, always use /home/claude explicitly
# rather than using $HOME substitution for clarity and consistency
# Host path ${SANDBOX_BASE}/${instance_name} is mapped to /home/claude inside the sandbox

# Get the sandbox home directory - can be used by other modules
get_sandbox_homedir() {
    # This returns the consistent path inside the sandbox rather than on host
    # IMPORTANT: All code referring to paths inside the sandbox must use this function
    # or explicitly use /home/claude for consistency
    echo "/home/claude"
}

# Get the sandbox username
get_sandbox_username() {
    echo "claude"
}

# Create a sandbox environment - consolidated implementation with the original claude_sandbox.sh
create_sandbox() {
    local sandbox_name="$1"
    local sandbox_home="${SANDBOX_BASE}/${sandbox_name}"
    
    # Check if sandbox already exists
    if [ -d "$sandbox_home" ]; then
        echo "Sandbox '$sandbox_name' already exists."
        return 0
    fi
    
    # Check if user namespaces are enabled and report status
    local userns_status="disabled"
    if check_userns_enabled &>/dev/null; then
        userns_status="enabled"
    fi
    echo "User namespaces: $userns_status (sandbox will function either way)"
    
    # Offer to enable user namespaces if disabled and not currently root
    if [ "$userns_status" = "disabled" ] && ! is_running_as_root; then
        echo "Would you like to enable unprivileged user namespaces for better security? (y/n)"
        read -r -p "> " response
        if [[ "$response" =~ ^[Yy] ]]; then
            echo "Attempting to enable unprivileged user namespaces..."
            if enable_unprivileged_userns; then
                echo "✓ User namespaces enabled successfully"
                userns_status="enabled"
            else
                echo "Could not enable user namespaces. Continuing with limited isolation."
            fi
        else
            echo "Continuing with user namespaces disabled."
        fi
    fi
    
    # Create sandbox directory
    mkdir -p "$sandbox_home"
    
    # Create fake passwd file for consistent claude user
    grep "^${SUDO_USER:-$(whoami)}:" /etc/passwd | \
      sed "s|^${SUDO_USER:-$(whoami)}:|claude:|" | \
      sed "s|:${HOME}:|:/home/claude:|" > "${SANDBOX_BASE}/fake_passwd.${sandbox_name}"
    
    echo "Created fake passwd file with username 'claude' and home '/home/claude'"
    
    # Try to find the template directory
    local template_dir="$(find_template_dir)"
    if [ -z "$template_dir" ]; then
        template_dir="${SCRIPT_DIR}/../templates"
    fi
    
    # Check for sandbox initialization template
    local init_template="${template_dir}/sandbox-init.sh"
    
    if [ -f "$init_template" ]; then
        echo "Using sandbox initialization template from: $init_template"
        cp "$init_template" "${sandbox_home}/init.sh"
        chmod +x "${sandbox_home}/init.sh"
    else {
        echo "Creating sandbox initialization script inline"
        # Create initialization script
        cat > "${sandbox_home}/init.sh" <<EOF
#!/bin/bash
set -e

# Create basic directories
mkdir -p ~/Documents
mkdir -p ~/Downloads
mkdir -p ~/.config/Claude
mkdir -p ~/.config/claude-desktop
mkdir -p ~/.local/share/applications
mkdir -p ~/.local/bin

# No automatic package installation in init script
# It's safer to pre-install required tools if needed

# Confirm initialization is complete
touch ~/.cmgr_initialized
echo "Sandbox initialization complete!"
EOF
        chmod +x "${sandbox_home}/init.sh"
    }
    fi
    
    # Create .bashrc with custom prompt, but filter out problematic commands
    if [ -f ~/.bashrc ]; then
        # Copy .bashrc but filter out any pyenv or other potentially problematic lines
        grep -v "pyenv\|nvm\|rvm" ~/.bashrc > "${sandbox_home}/.bashrc"
    else
        # Create minimal .bashrc if it doesn't exist
        echo '# Generated .bashrc for Claude sandbox' > "${sandbox_home}/.bashrc"
    fi
    
    # Add custom prompt to identify the Claude instance with color
    echo 'PS1="\[\e[48;5;208m\e[97m\]claude-'"${sandbox_name}"'\[\e[0m\] \[\e[1;32m\]\h:\w\[\e[0m\]$ "' >> "${sandbox_home}/.bashrc"
    
    # MCP configuration template
    local mcp_config_template="${template_dir}/default-mcp-config.json"
    
    # Copy existing MCP configuration if available
    mkdir -p "${sandbox_home}/.config/Claude"
    if [ -f "${HOME}/.config/Claude/claude_desktop_config.json" ]; then
        echo "Copying existing MCP configuration from host to sandbox..."
        cp "${HOME}/.config/Claude/claude_desktop_config.json" "${sandbox_home}/.config/Claude/"
    elif [ -f "$mcp_config_template" ]; then
        echo "Using default MCP configuration from template..."
        cp "$mcp_config_template" "${sandbox_home}/.config/Claude/claude_desktop_config.json"
    else {
        echo "Creating default MCP configuration inline..."
        cat > "${sandbox_home}/.config/Claude/claude_desktop_config.json" <<EOF
{
  "showTray": true,
  "electronInitScript": "/home/claude/.config/Claude/electron/preload.js"
}
EOF
    }
    fi
    
    # Initialize sandbox
    run_in_sandbox "$sandbox_name" "./init.sh"
    
    echo "Sandbox '$sandbox_name' created successfully!"
    return 0
}

# Run a command in the sandbox
run_in_sandbox() {
    local sandbox_name="$1"
    shift
    local sandbox_home="${SANDBOX_BASE}/${sandbox_name}"
    
    # Check if sandbox exists
    if [ ! -d "$sandbox_home" ]; then
        echo "Error: Sandbox '$sandbox_name' does not exist."
        return 1
    fi
    
    # Use consistent sandbox user information from utility functions
    local sandbox_username="$(get_sandbox_username)"
    local sandbox_user_home="$(get_sandbox_homedir)"
    
    # Verify path consistency before proceeding
    if [ "$sandbox_user_home" != "/home/claude" ]; then
        echo "ERROR: Sandbox path inconsistency detected!"
        echo "Expected: /home/claude"
        echo "Got: $sandbox_user_home"
        echo "Please fix get_sandbox_homedir function to return correct path"
        return 1
    fi
    
    # Print debug information
    echo "---- SANDBOX INFORMATION ----"
    echo "Sandbox name: $sandbox_name"
    echo "Host sandbox path: $sandbox_home"
    echo "Inside sandbox path: $sandbox_user_home"
    echo "Host user: $(whoami)"
    echo "Sandbox user: $sandbox_username"
    echo "----------------------------"
    
    # Enhanced Wayland detection for Ubuntu 24.04 support
    local is_wayland=false
    local wayland_detection_method=""

    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        is_wayland=true
        wayland_detection_method="WAYLAND_DISPLAY environment variable: ${WAYLAND_DISPLAY}"
    elif [ -n "${XDG_SESSION_TYPE:-}" ] && [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        is_wayland=true
        wayland_detection_method="XDG_SESSION_TYPE environment variable"
    elif [ -S "${XDG_RUNTIME_DIR:-}/wayland-0" ]; then
        is_wayland=true
        wayland_detection_method="wayland-0 socket in XDG_RUNTIME_DIR"
    fi

    if [ "$is_wayland" = true ]; then
        echo "Detected Wayland session ($wayland_detection_method)"
    else
        echo "Detected X11 session (no Wayland indicators found)"
    fi

    # Create tmp directory for auth files
    mkdir -p "${SANDBOX_BASE}/tmp"
    
    # Handle X11 authentication with Wayland awareness
    local xauth_file="${SANDBOX_BASE}/tmp/xauth.$(date +%s).$$"
    
    if [ "$is_wayland" = true ]; then
        # For Wayland: create a dummy auth file since .Xauthority typically doesn't exist
        echo "Using Wayland session, creating dummy X auth file"
        touch "$xauth_file"
    else
        # For X11: try to use existing auth file with improved privilege management
        local xauth_source=""
        
        if [ -n "${XAUTHORITY:-}" ] && [ -f "${XAUTHORITY}" ]; then
            echo "Using XAUTHORITY from environment: ${XAUTHORITY}"
            xauth_source="${XAUTHORITY}"
        elif [ -f "${ORIGINAL_HOME}/.Xauthority" ]; then
            echo "Using .Xauthority from home: ${ORIGINAL_HOME}/.Xauthority"
            xauth_source="${ORIGINAL_HOME}/.Xauthority"
        fi
        
        # Copy the found Xauthority file, or create empty if none
        if [ -n "$xauth_source" ]; then
            cp "$xauth_source" "$xauth_file" 2>/dev/null || touch "$xauth_file"
        else
            # No auth file found, create empty one
            echo "No Xauthority file found, creating empty one"
            touch "$xauth_file"
        fi
    fi
    
    # Ensure file exists and has right permissions
    chmod 644 "$xauth_file" 2>/dev/null
    export XAUTHORITY="$xauth_file"
    
    echo "Display info: DISPLAY=${DISPLAY:-:0}, XAUTHORITY=${XAUTHORITY}, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
    
    # Base bubblewrap command - CHANGED: use different home path inside sandbox
    local bwrap_cmd=(
        bwrap
        --proc /proc
        --tmpfs /tmp
        # Map the sandbox directory to /home/claude inside the container
        --bind "${sandbox_home}" "${sandbox_user_home}"
    )
    
    # Common read-only mounts
    local ro_mounts=(
        "/sbin" "/bin" "/usr" "/lib" "/lib64" "/etc"
        "/run/dbus" "/run/systemd" "/run/resolvconf" "/snap" "/sys"
    )
    
    # Add read-only mounts if they exist
    for mount in "${ro_mounts[@]}"; do
        if [ -e "$mount" ]; then
            bwrap_cmd+=(--ro-bind "$mount" "$mount")
        fi
    done
    
    # Bind fake passwd file
    bwrap_cmd+=(--ro-bind "${SANDBOX_BASE}/fake_passwd.${sandbox_name}" /etc/passwd)
    
    # User-specific mounts for GUI apps - support both X11 and Wayland
    bwrap_cmd+=(--bind /tmp/.X11-unix /tmp/.X11-unix)
    
    # Enhanced Wayland socket binding for Ubuntu 24.04
    if [ "$is_wayland" = true ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        # Bind main Wayland socket
        local main_wayland=${WAYLAND_DISPLAY:-wayland-0}
        local wayland_path="${XDG_RUNTIME_DIR}/${main_wayland}"
        
        if [ -S "$wayland_path" ]; then
            echo "Binding main Wayland socket: $wayland_path"
            bwrap_cmd+=(--bind "$wayland_path" "$wayland_path")
        fi
        
        # Bind all additional wayland protocol sockets
        for socket in "${XDG_RUNTIME_DIR}"/wayland-*; do
            if [ -S "$socket" ] && [ "$socket" != "$wayland_path" ]; then
                echo "Binding additional Wayland socket: $socket"
                bwrap_cmd+=(--bind "$socket" "$socket")
            fi
        done
        
        # Bind pipewire sockets (commonly used with Wayland)
        for socket in "${XDG_RUNTIME_DIR}"/pipewire-* "${XDG_RUNTIME_DIR}"/pulse "${XDG_RUNTIME_DIR}"/pipewire/; do
            if [ -e "$socket" ]; then
                echo "Binding media socket: $socket"
                bwrap_cmd+=(--bind "$socket" "$socket")
            fi
        done
    fi
    
    # Bind our custom temporary directory to ensure scripts can access it
    if [ -d "${SANDBOX_BASE}/tmp" ]; then
        mkdir -p "${SANDBOX_BASE}/tmp"
        bwrap_cmd+=(--bind "${SANDBOX_BASE}/tmp" "${SANDBOX_BASE}/tmp")
    fi
    
    # X11 authorization - critical for display access
    if [ -n "${XAUTHORITY:-}" ] && [ -f "${XAUTHORITY}" ]; then
        echo "Using Xauthority file: ${XAUTHORITY}"
        bwrap_cmd+=(--bind "${XAUTHORITY}" "${XAUTHORITY}")
        
        # For root/sudo case, we need to ensure the sandbox sees this file
        if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            # Also bind to standard location within sandbox
            bwrap_cmd+=(--bind "${XAUTHORITY}" "${sandbox_user_home}/.Xauthority")
        fi
    elif [ -f "${HOME}/.Xauthority" ]; then
        echo "Using home Xauthority file: ${HOME}/.Xauthority"
        bwrap_cmd+=(--bind "${HOME}/.Xauthority" "${sandbox_user_home}/.Xauthority")
    fi
    
    # Handle user runtime directory
    if [ -d "/run/user/${UID}" ]; then
        for item in bus docker.pid docker.sock docker; do
            if [ -e "/run/user/${UID}/$item" ]; then
                bwrap_cmd+=(--bind "/run/user/${UID}/$item" "/run/user/${UID}/$item")
            fi
        done
    fi
    
    # Device access
    bwrap_cmd+=(--dev-bind /dev /dev)
    
    # Explicitly bind DRI device for graphics acceleration if it exists
    if [ -d "/dev/dri" ]; then
        echo "Binding graphics device: /dev/dri"
        bwrap_cmd+=(--dev-bind "/dev/dri" "/dev/dri")
    fi
    
    # Explicitly bind nvidia devices if they exist
    for nvidia_dev in /dev/nvidia*; do
        if [ -e "$nvidia_dev" ]; then
            echo "Binding NVIDIA device: $nvidia_dev"
            bwrap_cmd+=(--dev-bind "$nvidia_dev" "$nvidia_dev")
        fi
    done
    
    # CRITICAL: Block access to real user's home directory - Use multiple approaches to ensure blocking
    # First, mount tmpfs over the real home - this is the most important protection
    bwrap_cmd+=(--tmpfs "${HOME}")
    echo "Blocking access to real home: ${HOME}"
    
    # Get current username dynamically
    local current_user="${SUDO_USER:-$(whoami)}"
    
    # Block access to standard home directory paths
    # This handles cases where $HOME might not be in /home/username (non-standard configurations)
    if [ "${HOME}" != "/home/${current_user}" ] && [ -d "/home/${current_user}" ]; then
        bwrap_cmd+=(--tmpfs "/home/${current_user}")
        echo "Blocking standard home path: /home/${current_user}"
    fi
    
    # Block various possible home directory paths
    # This handles both standard and non-standard home directory configurations
    for dir in "/home" "/root" "/var/lib" "/opt/home"; do
        if [ -d "$dir" ] && [[ "$dir" != "${sandbox_user_home}"* ]]; then
            # If HOME is in this directory, make sure we block the specific directory
            if [[ "${HOME}" == "${dir}/"* ]]; then
                local real_home_dir="${HOME}"
                bwrap_cmd+=(--tmpfs "${real_home_dir}")
                echo "Blocking real home directory: ${real_home_dir}"
            fi
            
            # Block user-specific directories
            if [ -d "${dir}/${current_user}" ] && [ "${dir}/${current_user}" != "${sandbox_user_home}" ]; then
                bwrap_cmd+=(--tmpfs "${dir}/${current_user}")
                echo "Blocking user directory: ${dir}/${current_user}"
            fi
        fi
    done
    
    # Block known common usernames for extra security
    for username in "${current_user}" root ubuntu debian linuxbrew admin ec2-user vagrant; do
        # Only block if the path exists and is not our sandbox home
        if [ -d "/home/$username" ] && [ "/home/$username" != "${sandbox_user_home}" ]; then
            bwrap_cmd+=(--tmpfs "/home/$username")
            echo "Blocking potential user home: /home/$username"
        fi
    done
    
    echo "Blocking access to real user home directories"
    
    # Try to determine the correct display
    local display_to_use="${DISPLAY:-:0}"
    # If running with sudo, try to get DISPLAY from the real user
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        local real_user_display
        real_user_display=$(su - "${SUDO_USER}" -c 'echo $DISPLAY')
        if [ -n "$real_user_display" ]; then
            display_to_use="$real_user_display"
        fi
    fi
    echo "Using DISPLAY=$display_to_use for sandbox"
    
    # Environment variables with enhanced Wayland support for Ubuntu 24.04
    bwrap_cmd+=(
        --clearenv
        --setenv HOME "${sandbox_user_home}"
        --setenv USER "${sandbox_username}"
        --setenv LOGNAME "${sandbox_username}"
        --setenv PATH "${sandbox_user_home}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
        --setenv DISPLAY "$display_to_use"
        --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-}"
        --setenv DBUS_SESSION_BUS_ADDRESS "${DBUS_SESSION_BUS_ADDRESS:-}"
        --setenv TERM "${TERM}"
        --setenv COLORTERM "${COLORTERM:-}"
        --setenv BASH_ENV "${sandbox_user_home}/.bashrc"
        --setenv CLAUDE_INSTANCE "${sandbox_name}"
        --setenv CLAUDE_CONFIG_PATH "${sandbox_user_home}/.config/Claude/claude_desktop_config.json"
        # Explicitly set XDG variables to ensure all applications use the correct paths
        --setenv XDG_CONFIG_HOME "${sandbox_user_home}/.config"
        --setenv XDG_DATA_HOME "${sandbox_user_home}/.local/share"
        --setenv XDG_CACHE_HOME "${sandbox_user_home}/.cache"
    )
    
    # Add Wayland-specific environment variables if running in Wayland
    if [ "$is_wayland" = true ]; then
        # Set XDG_SESSION_TYPE for proper Wayland detection
        bwrap_cmd+=(--setenv XDG_SESSION_TYPE "wayland")
        
        # For wlroots-based Wayland compositors (common in Ubuntu 24.04)
        if [ -n "${_JAVA_AWT_WM_NONREPARENTING:-}" ]; then
            bwrap_cmd+=(--setenv _JAVA_AWT_WM_NONREPARENTING "${_JAVA_AWT_WM_NONREPARENTING}")
        else
            bwrap_cmd+=(--setenv _JAVA_AWT_WM_NONREPARENTING "1")
        fi
        
        # For newer GTK applications on Wayland
        if [ -n "${GDK_BACKEND:-}" ]; then
            bwrap_cmd+=(--setenv GDK_BACKEND "${GDK_BACKEND}")
        else
            bwrap_cmd+=(--setenv GDK_BACKEND "wayland,x11")
        fi
        
        # For Qt applications on Wayland
        bwrap_cmd+=(--setenv QT_QPA_PLATFORM "wayland;xcb")
        
        # For electron applications (like Claude Desktop)
        bwrap_cmd+=(--setenv ELECTRON_OZONE_PLATFORM_HINT "auto")
        
        # To prevent Electron apps from falling back to X11 too quickly
        bwrap_cmd+=(--setenv ELECTRON_ENABLE_LOGGING "1")
    fi
    
    # Add X11 authentication environment variables if they exist
    if [ -n "${XAUTHORITY:-}" ]; then
        echo "Setting XAUTHORITY=${sandbox_user_home}/.Xauthority in sandbox"
        bwrap_cmd+=(--setenv XAUTHORITY "${sandbox_user_home}/.Xauthority")
    elif [ -f "${HOME}/.Xauthority" ]; then
        echo "Setting XAUTHORITY=${sandbox_user_home}/.Xauthority in sandbox"
        bwrap_cmd+=(--setenv XAUTHORITY "${sandbox_user_home}/.Xauthority")
    fi
    
    # Handle XDG_RUNTIME_DIR with improved privilege management
    # Get effective user ID regardless of sudo status
    local effective_uid
    if is_running_as_root; then
        effective_uid=$(id -u "${ORIGINAL_USER}")
    else
        effective_uid=$(id -u)
    fi
    
    # Use runtime directory based on effective user
    if [ -d "/run/user/${effective_uid}" ]; then
        echo "Using runtime directory: /run/user/${effective_uid}"
        bwrap_cmd+=(--setenv XDG_RUNTIME_DIR "/run/user/${effective_uid}")
        
        # Bind the runtime directory
        bwrap_cmd+=(--bind "/run/user/${effective_uid}" "/run/user/${effective_uid}")
    elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR}" ]; then
        # Fallback - use the current runtime dir if available
        bwrap_cmd+=(--setenv XDG_RUNTIME_DIR "${XDG_RUNTIME_DIR}")
    fi
    
    # Add any other X11-related variables that might be needed
    for xvar in $(env | grep -i '^X' | cut -d= -f1); do
        if [ -n "${!xvar}" ]; then
            bwrap_cmd+=(--setenv "$xvar" "${!xvar}")
        fi
    done
    
    # Print final command for debugging
    echo "Running command in sandbox with the following environment:"
    echo "HOME=${sandbox_user_home}"
    echo "USER=${sandbox_username}"
    echo "CLAUDE_CONFIG_PATH=${sandbox_user_home}/.config/Claude/claude_desktop_config.json"
    
    # Execute command in sandbox
    "${bwrap_cmd[@]}" "$@"
    local result=$?
    
    # Clean up temporary Xauthority file if we created one
    if [ -n "${xauth_file:-}" ] && [ -f "${xauth_file}" ]; then
        rm -f "${xauth_file}"
        # Clean up any old auth files (older than 1 day)
        find "${SANDBOX_BASE}/tmp" -name "xauth.*" -mtime +1 -delete 2>/dev/null || true
    fi
    
    return $result
}

# Copy a file to a system location with proper permissions
# Uses elevated privileges if needed for system directories
copy_to_system_location() {
    local source_file="$1"
    local target_path="$2"
    
    # Check if target path is a system location
    if [[ "$target_path" == /usr/* ]] || [[ "$target_path" == /opt/* ]]; then
        echo "Attempting to copy to system location: $target_path"
        
        # Try using sudo
        if command -v sudo >/dev/null 2>&1; then
            # Create a temporary script to run with sudo
            local tmp_script="${CMGR_HOME}/tmp/copy_script.$.sh"
            mkdir -p "${CMGR_HOME}/tmp"
            
            cat > "$tmp_script" << EOF
#!/bin/bash
set -e
cp "$source_file" "$target_path"
chmod --reference="${target_path}.original" "$target_path" 2>/dev/null || true
chown --reference="${target_path}.original" "$target_path" 2>/dev/null || true
echo "✓ Successfully copied file to system location"
EOF
            
            chmod +x "$tmp_script"
            sudo "$tmp_script"
            local result=$?
            rm -f "$tmp_script"
            return $result
        else
            echo "ERROR: Sudo not available, cannot copy to system location"
            echo "To manually complete the operation, run as root:"
            echo "cp \"$source_file\" \"$target_path\""
            return 1
        fi
    else
        # Regular copy for non-system locations
        cp "$source_file" "$target_path"
        return $?
    fi
}