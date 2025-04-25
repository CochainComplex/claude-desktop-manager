#!/bin/bash
# sandbox.sh - Enhanced sandbox management module for Claude Desktop Manager

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
    
    # Create fake passwd file for user mapping
    grep "^$(whoami)" /etc/passwd | \
        sed "s#[^\:]*:x:\([0-9\:]*\).*#agent:x:\1Agent:/home/agent:/bin/bash#" > \
        "${SANDBOX_BASE}/fake_passwd.${sandbox_name}"
    
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
    
    # Create .bashrc with custom prompt
    cp -a ~/.bashrc "${sandbox_home}/"
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
    
    # Base bubblewrap command
    local bwrap_cmd=(
        bwrap
        --proc /proc
        --tmpfs /tmp
        --bind "${sandbox_home}" /home/agent
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
    
    # Environment variables
    bwrap_cmd+=(
        --clearenv
        --setenv HOME /home/agent
        --setenv PATH "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/home/agent/.local/bin"
        --setenv DISPLAY "${DISPLAY}"
        --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-}"
        --setenv DBUS_SESSION_BUS_ADDRESS "${DBUS_SESSION_BUS_ADDRESS:-}"
        --setenv XDG_RUNTIME_DIR "${XDG_RUNTIME_DIR:-}"
        --setenv TERM "${TERM}"
        --setenv COLORTERM "${COLORTERM:-}"
        --setenv BASH_ENV "/home/agent/.bashrc"
        --setenv CLAUDE_INSTANCE "${sandbox_name}"
    )
    
    # Execute command in sandbox
    "${bwrap_cmd[@]}" "$@"
    return $?
}
