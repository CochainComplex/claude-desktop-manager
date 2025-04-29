#!/bin/bash
# sandbox.sh - Enhanced sandbox management module for Claude Desktop Manager

# Get the sandbox home directory - can be used by other modules
get_sandbox_homedir() {
    # This now returns the consistent path inside the sandbox rather than on host
    echo "/home/claude"
}

# Get the sandbox username
get_sandbox_username() {
    echo "claude"
}

# Create a sandbox environment
create_sandbox() {
    local sandbox_name="$1"
    local sandbox_home="${SANDBOX_BASE}/${sandbox_name}"
    
    # Check if sandbox already exists
    if [ -d "$sandbox_home" ]; then
        echo "Sandbox '$sandbox_name' already exists."
        return 0
    fi
    
    # Create sandbox directory
    mkdir -p "$sandbox_home"
    
    # Create fake passwd file for consistent claude user
    grep "^${SUDO_USER:-$(whoami)}:" /etc/passwd | \
      sed "s|^${SUDO_USER:-$(whoami)}:|claude:|" | \
      sed "s|:${HOME}:|:/home/claude:|" > "${SANDBOX_BASE}/fake_passwd.${sandbox_name}"
    
    echo "Created fake passwd file with username 'claude' and home '/home/claude'"
    
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
    
    # Create .bashrc with custom prompt, but filter out problematic commands
    if [ -f ~/.bashrc ]; then
        # Copy .bashrc but filter out any pyenv or other potentially problematic lines
        grep -v "pyenv\|nvm\|rvm" ~/.bashrc > "${sandbox_home}/.bashrc"
    else
        # Create minimal .bashrc if it doesn't exist
        echo '# Generated .bashrc for Claude sandbox' > "${sandbox_home}/.bashrc"
    fi
    
    # Add custom prompt to identify the Claude instance
    echo 'PS1="\[\e[48;5;208m\e[97m\]claude-'"${sandbox_name}"'\[\e[0m\] \[\e[1;32m\]\h:\w\[\e[0m\]$ "' >> "${sandbox_home}/.bashrc"
    
    # Copy existing MCP configuration if available
    mkdir -p "${sandbox_home}/.config/Claude"
    if [ -f "${HOME}/.config/Claude/claude_desktop_config.json" ]; then
        echo "Copying existing MCP configuration to sandbox..."
        cp "${HOME}/.config/Claude/claude_desktop_config.json" "${sandbox_home}/.config/Claude/"
    else
        # Create default MCP configuration
        echo "Creating default MCP configuration in sandbox..."
        cat > "${sandbox_home}/.config/Claude/claude_desktop_config.json" <<EOF
{
  "showTray": true,
  "electronInitScript": "/home/claude/.config/Claude/electron/preload.js"
}
EOF
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
    
    # Use a consistent fake username across all sandboxes
    local sandbox_username="claude"
    local sandbox_user_home="/home/${sandbox_username}"
    
    # Print debug information
    echo "---- SANDBOX INFORMATION ----"
    echo "Sandbox name: $sandbox_name"
    echo "Host sandbox path: $sandbox_home"
    echo "Inside sandbox path: $sandbox_user_home"
    echo "Host user: $(whoami)"
    echo "Sandbox user: $sandbox_username"
    echo "----------------------------"
    
    # Handle X11 authentication for root/sudo specifically
    local xauth_file=""
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        # When running as root, we need to create a temporary Xauthority that root can use
        # Create it in SANDBOX_BASE so it's accessible to both host and sandbox
        mkdir -p "${SANDBOX_BASE}/tmp"
        xauth_file="${SANDBOX_BASE}/tmp/xauth.$(date +%s).$$"
        
        # Copy the original user's xauth data
        if [ -n "${XAUTHORITY:-}" ] && [ -f "${XAUTHORITY}" ]; then
            cp "${XAUTHORITY}" "$xauth_file"
        elif [ -f "/home/${SUDO_USER}/.Xauthority" ]; then
            cp "/home/${SUDO_USER}/.Xauthority" "$xauth_file"
        else
            # Try to extract the cookie for the current display
            su - "${SUDO_USER}" -c "xauth extract $xauth_file $DISPLAY" || true
        fi
        
        # Make sure it's accessible
        chmod 644 "$xauth_file"
        export XAUTHORITY="$xauth_file"
    fi
    
    # Debug info
    echo "Display info: DISPLAY=${DISPLAY:-unset}, XAUTHORITY=${XAUTHORITY:-unset}"
    
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
    
    # User-specific mounts for GUI apps
    bwrap_cmd+=(--bind /tmp/.X11-unix /tmp/.X11-unix)
    
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
    # First, mount tmpfs over the real home
    bwrap_cmd+=(--tmpfs "${HOME}")
    # Also try to block direct path to user home
    if [ "${HOME}" != "/home/awarth" ]; then
        bwrap_cmd+=(--tmpfs "/home/awarth")
    fi
    # Make sure all known paths to the real home are blocked
    for username in awarth root; do
        if [ -d "/home/$username" ] && [ "/home/$username" != "${sandbox_user_home}" ]; then
            bwrap_cmd+=(--tmpfs "/home/$username")
            echo "Blocking access to $username home: /home/$username"
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
    
    # Environment variables
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
    
    # Add X11 authentication environment variables if they exist
    if [ -n "${XAUTHORITY:-}" ]; then
        echo "Setting XAUTHORITY=${sandbox_user_home}/.Xauthority in sandbox"
        bwrap_cmd+=(--setenv XAUTHORITY "${sandbox_user_home}/.Xauthority")
    elif [ -f "${HOME}/.Xauthority" ]; then
        echo "Setting XAUTHORITY=${sandbox_user_home}/.Xauthority in sandbox"
        bwrap_cmd+=(--setenv XAUTHORITY "${sandbox_user_home}/.Xauthority")
    fi
    
    # Handle XDG_RUNTIME_DIR differently for sudo
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        # Get original user's ID
        local original_uid=$(id -u "${SUDO_USER}")
        
        # Try to use the original user's runtime directory
        if [ -d "/run/user/${original_uid}" ]; then
            echo "Using original user's XDG_RUNTIME_DIR: /run/user/${original_uid}"
            bwrap_cmd+=(--setenv XDG_RUNTIME_DIR "/run/user/${original_uid}")
            
            # Bind the runtime directory
            if [ -d "/run/user/${original_uid}" ]; then
                bwrap_cmd+=(--bind "/run/user/${original_uid}" "/run/user/${original_uid}")
            fi
        fi
    elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR}" ]; then
        # Standard case - use the current runtime dir
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
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ -n "${xauth_file:-}" ] && [ -f "${xauth_file}" ]; then
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