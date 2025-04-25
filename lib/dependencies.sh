#!/bin/bash
# dependencies.sh - Dependency management for Claude Desktop Manager

# Check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
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
    if [ "$1" = "full" ]; then
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
    if ! check_dependencies "$1"; then
        echo "Attempting to install missing dependencies..."
        
        if ! sudo -v; then
            echo "❌ Failed to validate sudo credentials. Please ensure you can run sudo."
            return 1
        fi
        
        if ! sudo apt update; then
            echo "❌ Failed to run 'sudo apt update'."
            return 1
        fi
        
        if [ "$1" = "full" ]; then
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
