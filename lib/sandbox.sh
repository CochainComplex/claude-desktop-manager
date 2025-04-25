#!/bin/bash
# sandbox.sh - Enhanced sandbox management module for Claude Desktop Manager

# Get the sandbox home directory - can be used by other modules
get_sandbox_homedir() {
    echo "/home/$(whoami)"
}

# Get the sandbox username
get_sandbox_username() {
    echo "$(whoami)"
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
    
    # Create fake passwd file for user mapping - keep the original user's entry
    grep "^$(whoami):" /etc/passwd > "${SANDBOX_BASE}/fake_passwd.${sandbox_name}"
    
    # Create initialization script
    cat > "${sandbox_home}/init.sh" <<EOF
#!/bin/bash
set -e

# Create basic directories
mkdir -p ~/Documents
mkdir -p ~/Downloads
mkdir -p ~/.config
mkdir -p ~/.local/share/applications

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
    
    # Base bubblewrap command
    local real_home_dir="$HOME"
    
    local bwrap_cmd=(
        bwrap
        --proc /proc
        --tmpfs /tmp
        --bind "${sandbox_home}" "${real_home_dir}"
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
            bwrap_cmd+=(--bind "${XAUTHORITY}" "${real_home_dir}/.Xauthority")
        fi
    elif [ -f "${HOME}/.Xauthority" ]; then
        echo "Using home Xauthority file: ${HOME}/.Xauthority"
        bwrap_cmd+=(--bind "${HOME}/.Xauthority" "${HOME}/.Xauthority")
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
    
    # Environment variables
    local real_home_dir="$HOME"
    
    bwrap_cmd+=(
        --clearenv
        --setenv HOME "${real_home_dir}"
        --setenv PATH "${real_home_dir}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
        --setenv DISPLAY "${DISPLAY:-:0}"
        --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-}"
        --setenv DBUS_SESSION_BUS_ADDRESS "${DBUS_SESSION_BUS_ADDRESS:-}"
        --setenv TERM "${TERM}"
        --setenv COLORTERM "${COLORTERM:-}"
        --setenv BASH_ENV "${real_home_dir}/.bashrc"
        --setenv CLAUDE_INSTANCE "${sandbox_name}"
    )
    
    # Add X11 authentication environment variables if they exist
    if [ -n "${XAUTHORITY:-}" ]; then
        echo "Setting XAUTHORITY=${XAUTHORITY} in sandbox"
        bwrap_cmd+=(--setenv XAUTHORITY "${XAUTHORITY}")
    elif [ -f "${HOME}/.Xauthority" ]; then
        echo "Setting XAUTHORITY=${HOME}/.Xauthority in sandbox"
        bwrap_cmd+=(--setenv XAUTHORITY "${HOME}/.Xauthority")
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
