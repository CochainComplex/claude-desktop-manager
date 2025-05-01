#!/bin/bash
# privileges.sh - Privilege management for Claude Desktop Manager
# Handles elevation of privileges only when necessary
# Derived from the original emsi/claude-desktop project

# Check if the script is already running with elevated privileges
is_running_as_root() {
    [ "$(id -u)" -eq 0 ]
}

# Check if sudo is available
is_sudo_available() {
    command -v sudo &>/dev/null
}

# Get current effective username
get_effective_username() {
    if is_running_as_root && [ -n "${SUDO_USER:-}" ]; then
        echo "$SUDO_USER"
    else
        whoami
    fi
}

# Get the original home directory (regardless of whether running as root)
get_original_home() {
    if is_running_as_root && [ -n "${SUDO_USER:-}" ]; then
        eval echo "~${SUDO_USER}"
    else
        echo "$HOME"
    fi
}

# Execute a command with elevated privileges if needed
# Returns: success/failure of the command
run_with_sudo() {
    local command_description="$1"
    shift
    
    if is_running_as_root; then
        # Already running as root, just execute the command
        "$@"
        return $?
    else
        # Need to elevate - check if sudo is available
        if ! is_sudo_available; then
            echo "ERROR: Cannot execute privileged operation: sudo not available"
            echo "To perform this operation, run as root or install sudo"
            echo "Operation: $command_description"
            echo "Command: $*"
            return 1
        fi
        
        # Prompt the user with the operation description
        echo "The following operation requires elevated privileges:"
        echo "  $command_description"
        echo "You'll be prompted for your password to continue."
        echo
        
        # Execute with sudo
        sudo "$@"
        return $?
    fi
}

# Run a command with elevated privileges only if the path requires it
# Usage: run_path_operation "description" command arg1 arg2...
# Returns: success/failure of the command
run_path_operation() {
    local command_description="$1"
    shift
    local command_name="$1"
    shift
    local target_path="$1"
    
    # Check if target path is in a system location requiring privileges
    if [[ "$target_path" == /usr/* ]] || [[ "$target_path" == /opt/* ]] || [[ "$target_path" == /etc/* ]] || [[ "$target_path" == /var/* ]]; then
        # System location - needs privileges
        run_with_sudo "$command_description" "$command_name" "$target_path" "$@"
    else
        # Regular location - no privileges needed
        "$command_name" "$target_path" "$@"
    fi
}

# Create a temporary script to run with sudo privileges
# Usage: run_sudo_script "description" script_content
# Returns: success/failure of the script execution
run_sudo_script() {
    local command_description="$1"
    local script_content="$2"
    
    # Already running as root
    if is_running_as_root; then
        # Create a temporary script
        local tmp_script="/tmp/cmgr_sudo_script.$$.sh"
        echo "$script_content" > "$tmp_script"
        chmod +x "$tmp_script"
        
        # Execute the script
        "$tmp_script"
        local result=$?
        
        # Clean up
        rm -f "$tmp_script"
        return $result
    else
        # Need to elevate with sudo
        if ! is_sudo_available; then
            echo "ERROR: Cannot execute privileged operation: sudo not available"
            echo "To perform this operation, run as root or install sudo"
            echo "Operation: $command_description"
            return 1
        fi
        
        # Create a temporary script
        local tmp_script="/tmp/cmgr_sudo_script.$$.sh"
        echo "$script_content" > "$tmp_script"
        chmod +x "$tmp_script"
        
        # Prompt the user with the operation description
        echo "The following operation requires elevated privileges:"
        echo "  $command_description"
        echo "You'll be prompted for your password to continue."
        echo
        
        # Execute with sudo
        sudo "$tmp_script"
        local result=$?
        
        # Clean up
        rm -f "$tmp_script"
        return $result
    fi
}

# Enable unprivileged user namespaces (requires sudo)
enable_unprivileged_userns() {
    if check_userns_enabled; then
        echo "Unprivileged user namespaces are already enabled."
        return 0
    fi
    
    echo "Enabling unprivileged user namespaces (requires elevated privileges)..."
    
    # Create script content to enable user namespaces
    local script_content=$(cat <<EOF
#!/bin/bash
set -e
# Enable unprivileged user namespaces for the current session
sysctl -w kernel.unprivileged_userns_clone=1

# Persist the setting across reboots
mkdir -p /etc/sysctl.d
echo 'kernel.unprivileged_userns_clone = 1' > /etc/sysctl.d/00-local-userns.conf
echo "✓ Unprivileged user namespaces enabled successfully"
EOF
)
    
    # Run the script with sudo
    run_sudo_script "Enable unprivileged user namespaces" "$script_content"
}

# Check if unprivileged user namespaces are enabled
check_userns_enabled() {
    # Check the kernel parameter
    if [ -f /proc/sys/kernel/unprivileged_userns_clone ]; then
        if [ "$(cat /proc/sys/kernel/unprivileged_userns_clone)" = "1" ]; then
            return 0  # Enabled
        fi
    fi
    
    # Also check if we can create a user namespace (some distros don't use the sysctl)
    unshare --user --map-root-user echo "Testing user namespace" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        return 0  # Enabled - works through actual test
    fi
    
    return 1  # Disabled
}

# Restore original owner for files/directories when running as sudo
restore_ownership() {
    local path="$1"
    
    if is_running_as_root && [ -n "${SUDO_USER:-}" ]; then
        local original_user="${SUDO_USER}"
        local original_group=$(id -gn "${SUDO_USER}")
        
        chown -R "${original_user}:${original_group}" "$path"
        echo "Restored ownership to ${original_user}:${original_group} for $path"
    fi
    
    return 0
}

# Copy a file to a system location, using sudo if necessary
# Usage: copy_to_system_location source_file target_path
# Returns: success/failure of the copy operation
copy_to_system_location() {
    local source_file="$1"
    local target_path="$2"
    
    # Check if target path is a system location
    if [[ "$target_path" == /usr/* ]] || [[ "$target_path" == /opt/* ]]; then
        echo "Attempting to copy to system location: $target_path"
        
        # Create script content to copy the file
        local script_content=$(cat <<EOF
#!/bin/bash
set -e
mkdir -p "$(dirname "$target_path")"
cp "$source_file" "$target_path"
if [ -f "${target_path}.original" ]; then
    chmod --reference="${target_path}.original" "$target_path" 2>/dev/null || true
    chown --reference="${target_path}.original" "$target_path" 2>/dev/null || true
else
    chmod 644 "$target_path"
fi
echo "✓ Successfully copied file to system location: $target_path"
EOF
)
        
        # Run the script with sudo
        run_sudo_script "Copy file to system location: $target_path" "$script_content"
    else
        # Regular copy for non-system locations
        mkdir -p "$(dirname "$target_path")"
        cp "$source_file" "$target_path"
        echo "✓ File copied to: $target_path"
    fi
    
    return $?
}

# Create a symlink in a system location, using sudo if necessary
# Usage: create_system_symlink target link_name
# Returns: success/failure of the symlink creation
create_system_symlink() {
    local target="$1"
    local link_name="$2"
    
    # Check if link path is a system location
    if [[ "$link_name" == /usr/* ]] || [[ "$link_name" == /opt/* ]] || [[ "$link_name" == /bin/* ]]; then
        echo "Attempting to create symlink in system location: $link_name"
        
        # Create script content to create the symlink
        local script_content=$(cat <<EOF
#!/bin/bash
set -e
mkdir -p "$(dirname "$link_name")"
ln -sf "$target" "$link_name"
echo "✓ Successfully created symlink: $link_name -> $target"
EOF
)
        
        # Run the script with sudo
        run_sudo_script "Create symlink: $link_name -> $target" "$script_content"
    else
        # Regular symlink for non-system locations
        mkdir -p "$(dirname "$link_name")"
        ln -sf "$target" "$link_name"
        echo "✓ Created symlink: $link_name -> $target"
    fi
    
    return $?
}