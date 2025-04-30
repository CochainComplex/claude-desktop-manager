#!/bin/bash
# dependencies.sh - Dependency management for Claude Desktop Manager

# Check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# Check if unprivileged user namespaces are enabled
check_userns_enabled() {
    local enabled
    enabled=$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo "unknown")
    
    if [ "$enabled" = "1" ]; then
        return 0  # Enabled
    elif [ "$enabled" = "0" ]; then
        return 1  # Disabled
    else
        # Some systems don't have this sysctl but still support unprivileged user namespaces
        # Try to create a user namespace as a test
        if unshare --user echo "User namespaces working" &>/dev/null; then
            return 0  # Enabled
        else
            return 1  # Disabled or not supported
        fi
    fi
}

# Enable unprivileged user namespaces with flexible authentication methods
enable_userns() {
    local parameter="kernel.unprivileged_userns_clone"
    
    # Check if already enabled
    if check_userns_enabled; then
        echo "✓ Unprivileged user namespaces already enabled"
        return 0
    fi
    
    echo "Unprivileged user namespaces are currently disabled"
    echo "This feature requires elevated privileges to enable"
    
    # Determine available authentication mechanism
    local auth_methods=()
    local auth_descriptions=()
    
    # Check for PolicyKit (graphical authentication)
    if command -v pkexec >/dev/null 2>&1; then
        auth_methods+=("pkexec")
        auth_descriptions+=("PolicyKit graphical authentication")
    fi
    
    # Check for sudo
    if command -v sudo >/dev/null 2>&1; then
        auth_methods+=("sudo")
        auth_descriptions+=("sudo terminal authentication")
    fi
    
    # Check for doas (OpenBSD's sudo alternative)
    if command -v doas >/dev/null 2>&1; then
        auth_methods+=("doas")
        auth_descriptions+=("doas terminal authentication")
    fi
    
    # Check if we have any authentication methods
    if [ ${#auth_methods[@]} -eq 0 ]; then
        echo "No supported authentication mechanism found (pkexec, sudo, or doas)"
        echo "Cannot enable user namespaces without authentication"
        provide_manual_instructions
        return 1
    fi
    
    # Show available authentication methods
    echo "Available authentication methods:"
    for i in "${!auth_methods[@]}"; do
        echo "  $((i+1)). ${auth_descriptions[$i]}"
    done
    
    # Use the first available method by default
    local auth_method="${auth_methods[0]}"
    
    # If we have multiple methods, let the user choose
    if [ ${#auth_methods[@]} -gt 1 ]; then
        echo
        echo "Select authentication method (1-${#auth_methods[@]}, default: 1):"
        read -r auth_choice
        
        # If user provided a choice, use it
        if [ -n "$auth_choice" ] && [ "$auth_choice" -le "${#auth_methods[@]}" ] && [ "$auth_choice" -ge 1 ]; then
            auth_method="${auth_methods[$((auth_choice-1))]}"
        fi
    fi
    
    echo "Using ${auth_method} for authentication..."
    
    # Create temporary directory for script
    local tmp_dir="${CMGR_HOME:-/tmp}/userns_config"
    mkdir -p "$tmp_dir"
    local tmp_script="${tmp_dir}/enable_userns.sh"
    
    # Create the script to be executed with elevated privileges
    cat > "$tmp_script" << 'EOF'
#!/bin/bash
# Script to enable unprivileged user namespaces

set -e

# Detect init system
init_system="unknown"
if [ -d "/run/systemd/system" ]; then
    init_system="systemd"
elif [ -f "/etc/init.d/cron" ] && [ ! -h "/etc/init.d/cron" ]; then
    init_system="sysvinit"
elif [ -f "/sbin/openrc" ]; then
    init_system="openrc"
fi

echo "Detected init system: $init_system"

# Set kernel parameter for current session
if ! sysctl -w kernel.unprivileged_userns_clone=1; then
    echo "Failed to set kernel parameter"
    exit 1
fi

echo "✓ Successfully enabled unprivileged user namespaces for current session"

# Function to make the change permanent
make_permanent() {
    # Create conf file in the appropriate location for the distro
    if [ -d "/etc/sysctl.d" ]; then
        echo "kernel.unprivileged_userns_clone = 1" > /etc/sysctl.d/99-userns.conf
        echo "✓ Created persistent configuration in /etc/sysctl.d/99-userns.conf"
    elif [ -f "/etc/sysctl.conf" ]; then
        # Check if the setting already exists in sysctl.conf
        if grep -q "^kernel.unprivileged_userns_clone" /etc/sysctl.conf; then
            # Update existing setting
            sed -i 's/^kernel.unprivileged_userns_clone.*/kernel.unprivileged_userns_clone = 1/' /etc/sysctl.conf
        else
            # Add new setting
            echo "kernel.unprivileged_userns_clone = 1" >> /etc/sysctl.conf
        fi
        echo "✓ Updated /etc/sysctl.conf with unprivileged user namespaces setting"
    else
        echo "⚠️ Could not find a suitable location for persistent configuration"
        return 1
    fi
    
    # For systemd systems, also enable through systemd-sysctl
    if [ "$init_system" = "systemd" ]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart systemd-sysctl.service 2>/dev/null || true
        fi
    fi
    
    # Verify the setting is applied
    if [ "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null)" = "1" ]; then
        echo "✓ Verified setting is active"
        return 0
    else
        echo "⚠️ Setting not applied correctly"
        return 1
    fi
}

# Ask if the user wants to make the change permanent
if [ "$1" = "--permanent" ]; then
    make_permanent
    exit $?
else
    exit 0
fi
EOF
    
    # Make the script executable
    chmod +x "$tmp_script"
    
    # Execute the script with the chosen authentication method
    if "$auth_method" "$tmp_script"; then
        echo "✓ Successfully enabled unprivileged user namespaces for this session"
        
        # Ask if user wants to make the change permanent
        echo
        echo "Would you like to make this change permanent? (y/n)"
        read -r make_permanent
        
        if [[ "$make_permanent" =~ ^[Yy] ]]; then
            echo "Making change permanent (requires authentication)..."
            if "$auth_method" "$tmp_script" "--permanent"; then
                echo "✓ Change is now permanent and will persist across reboots"
            else
                echo "⚠️ Failed to make change permanent"
                echo "Unprivileged user namespaces are still enabled for this session"
            fi
        else
            echo "✓ User namespaces enabled for this session only"
            echo "Note: You'll need to enable this feature again after reboot"
        fi
        
        # Verify the current session has the feature enabled
        if check_userns_enabled; then
            # Clean up
            rm -f "$tmp_script"
            
            # Inform the user that their current processes can use this feature
            echo
            echo "✓ All current and future processes can now use unprivileged user namespaces"
            
            # For sandboxed applications, recommend restarting them
            echo "Note: Any existing Claude Desktop instances should be restarted"
            echo "to take advantage of the newly enabled feature."
            
            return 0
        else
            echo "⚠️ Something went wrong. User namespaces appear to be disabled."
            # Clean up
            rm -f "$tmp_script"
            provide_manual_instructions
            return 1
        fi
    else
        echo "❌ Authentication failed or user canceled the operation"
        # Clean up
        rm -f "$tmp_script"
        provide_manual_instructions
        return 1
    fi
}

# Provide manual instructions for enabling user namespaces
provide_manual_instructions() {
    echo
    echo "Manual instructions to enable unprivileged user namespaces:"
    echo
    echo "For immediate effect (until next reboot):"
    echo "  sudo sysctl -w kernel.unprivileged_userns_clone=1"
    echo
    echo "To make the change permanent:"
    echo "  echo 'kernel.unprivileged_userns_clone = 1' | sudo tee /etc/sysctl.d/99-userns.conf"
    echo "  sudo sysctl --system"
    echo
    echo "Using kernel parameter (if using systemd-boot):"
    echo "  1. Edit your loader entry in /boot/loader/entries/..."
    echo "  2. Add 'sysctl.kernel.unprivileged_userns_clone=1' to the options line"
    echo "  3. Reboot your system"
    echo
}

# Check all required dependencies
check_dependencies() {
    local missing_deps=()
    
    # Essential dependencies
    if ! check_command "bwrap"; then
        missing_deps+=("bubblewrap")
    fi
    
    if ! check_command "jq"; then
        missing_deps+=("jq")
    fi
    
    if ! check_command "git"; then
        missing_deps+=("git")
    fi
    
    # Only needed for building/installing
    local check_type="${1:-basic}"
    if [ "$check_type" = "full" ]; then
        if ! check_command "p7zip"; then
            missing_deps+=("p7zip-full")
        fi
        
        if ! check_command "wget"; then
            missing_deps+=("wget")
        fi
        
        if ! check_command "npx"; then
            missing_deps+=("nodejs npm")
        fi
    fi
    
    # If any dependencies are missing, print a message and return error
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Missing dependencies: ${missing_deps[*]}"
        echo "Please install them with:"
        echo "sudo apt update && sudo apt install -y ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# Install dependencies if missing
install_dependencies() {
    local install_type="${1:-basic}"
    if ! check_dependencies "$install_type"; then
        echo "Attempting to install missing dependencies..."
        
        if ! sudo -v; then
            echo "❌ Failed to validate sudo credentials. Please ensure you can run sudo."
            return 1
        fi
        
        if ! sudo apt update; then
            echo "❌ Failed to run 'sudo apt update'."
            return 1
        fi
        
        if [ "$install_type" = "full" ]; then
            sudo apt install -y bubblewrap jq git p7zip-full wget nodejs npm
        else
            sudo apt install -y bubblewrap jq git
        fi
        
        echo "✓ Dependencies installed successfully."
        return 0
    fi
    
    echo "✓ All required dependencies are installed."
    return 0
}
