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

# Enable unprivileged user namespaces if possible
enable_userns() {
    if check_userns_enabled; then
        echo "✓ Unprivileged user namespaces already enabled"
        return 0
    fi
    
    echo "Attempting to enable unprivileged user namespaces..."
    
    # Create a temporary script to run with sudo
    local tmp_script="${CMGR_HOME:-/tmp}/enable_userns.sh"
    mkdir -p "$(dirname "$tmp_script")"
    
    cat > "$tmp_script" << 'EOF'
#!/bin/bash
set -e

# Check if we're running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Enable unprivileged user namespaces
sysctl -w kernel.unprivileged_userns_clone=1

# Make it permanent
if [ -d "/etc/sysctl.d" ]; then
    echo "kernel.unprivileged_userns_clone = 1" > /etc/sysctl.d/00-local-userns.conf
    echo "✓ Permanently enabled unprivileged user namespaces"
else
    echo "kernel.unprivileged_userns_clone = 1" >> /etc/sysctl.conf
    echo "✓ Added setting to /etc/sysctl.conf"
fi

# Check if we succeeded
if [ "$(sysctl -n kernel.unprivileged_userns_clone)" = "1" ]; then
    echo "✓ Successfully enabled unprivileged user namespaces"
    exit 0
else
    echo "Failed to enable unprivileged user namespaces"
    exit 1
fi
EOF
    
    chmod +x "$tmp_script"
    
    # Try to run with sudo
    if command -v sudo &>/dev/null; then
        echo "Running with sudo to enable unprivileged user namespaces"
        if sudo "$tmp_script"; then
            rm -f "$tmp_script"
            return 0
        fi
    else
        echo "Cannot enable unprivileged user namespaces: sudo not available"
    fi
    
    # Clean up
    rm -f "$tmp_script"
    
    # Print alternative instructions
    echo "Please run the following command with root privileges to enable unprivileged user namespaces:"
    echo "  sudo sysctl -w kernel.unprivileged_userns_clone=1"
    echo "  echo 'kernel.unprivileged_userns_clone = 1' | sudo tee /etc/sysctl.d/00-local-userns.conf"
    
    return 1
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
