#!/bin/bash
# installer.sh - Installation and caching utilities for Claude Desktop Manager

# Build and cache Claude Desktop
build_and_cache_claude() {
    local build_format="${1:-deb}"
    local cache_dir="${CMGR_CACHE}"
    
    echo "Building and caching Claude Desktop (${build_format})..."
    
    # Ensure cache directory exists
    mkdir -p "${cache_dir}"
    
    # Create temporary directory for building
    local build_dir
    build_dir="$(mktemp -d)"
    
    # Clone the claude-desktop repository
    if ! git clone https://github.com/emsi/claude-desktop.git "$build_dir"; then
        echo "Error: Failed to clone repository."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Execute build script in a subshell to ensure proper directory handling
    if ! (cd "$build_dir" && ./build.sh --build "$build_format" --clean no); then
        echo "Error: Failed to build Claude Desktop."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Find the built package
    local package_file=""
    if [ "$build_format" = "deb" ]; then
        package_file=$(find "$build_dir" -maxdepth 1 -name "claude-desktop_*.deb" | head -1)
    else
        package_file=$(find "$build_dir" -maxdepth 1 -name "claude-desktop-*.AppImage" | head -1)
    fi
    
    if [ -z "$package_file" ]; then
        echo "Error: No ${build_format} package found after build."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Extract version from filename
    local version=""
    if [ "$build_format" = "deb" ]; then
        version=$(echo "$(basename "$package_file")" | grep -oP 'claude-desktop_\K[0-9]+\.[0-9]+\.[0-9]+(?=_)' || echo "unknown")
    else
        version=$(echo "$(basename "$package_file")" | grep -oP 'claude-desktop-\K[0-9]+\.[0-9]+\.[0-9]+(?=-)' || echo "unknown")
    fi
    
    # Copy package to cache
    if ! cp "$package_file" "${cache_dir}/"; then
        echo "Error: Failed to copy package to cache directory."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Create metadata file
    if ! cat > "${cache_dir}/metadata.json" <<EOF
{
    "version": "${version}",
    "format": "${build_format}",
    "file": "$(basename "$package_file")",
    "build_date": "$(date -Iseconds)"
}
EOF
    then
        echo "Error: Failed to create metadata file."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Clean up build directory
    rm -rf "$build_dir"
    
    echo "Claude Desktop ${version} (${build_format}) cached successfully!"
    return 0
}

# Install Claude Desktop in a sandbox
install_claude_in_sandbox() {
    local sandbox_name="$1"
    local build_format="${2:-deb}"
    
    # Check if cache exists
    local cache_dir="${CMGR_CACHE}"
    local metadata_file="${cache_dir}/metadata.json"
    
    # Ensure cache directory exists
    mkdir -p "${cache_dir}"
    
    # Build Claude Desktop if no cached version exists
    if [ ! -f "$metadata_file" ]; then
        echo "No cached Claude Desktop build found. Building now..."
        if ! build_and_cache_claude "$build_format"; then
            echo "Error: Failed to build Claude Desktop."
            return 1
        fi
    fi
    
    # Read metadata - with error handling
    if [ ! -f "$metadata_file" ]; then
        echo "Error: Metadata file not found after build."
        return 1
    fi
    
    # Check if metadata file exists and is readable
    local cached_format=""
    if [ -f "$metadata_file" ]; then
        cached_format=$(grep -o '"format": "[^"]*"' "$metadata_file" 2>/dev/null | cut -d'"' -f4)
    fi
    
    # If metadata is unreadable or format doesn't match, rebuild
    if [ -z "$cached_format" ] || [ "$cached_format" != "$build_format" ]; then
        echo "Cached format (${cached_format:-unknown}) doesn't match requested format (${build_format}). Building..."
        if ! build_and_cache_claude "$build_format"; then
            echo "Error: Failed to build Claude Desktop with format ${build_format}."
            return 1
        fi
        
        # Verify metadata file was created
        if [ ! -f "$metadata_file" ]; then
            echo "Error: Metadata file not found after rebuild."
            return 1
        fi
        
        # Read format again
        cached_format=$(grep -o '"format": "[^"]*"' "$metadata_file" 2>/dev/null | cut -d'"' -f4)
    fi
    
    # Read package file from metadata
    local package_file=""
    if [ -f "$metadata_file" ]; then
        package_file=$(grep -o '"file": "[^"]*"' "$metadata_file" 2>/dev/null | cut -d'"' -f4)
    fi
    
    if [ -z "$package_file" ]; then
        echo "Error: Could not determine package file from metadata."
        return 1
    fi
    
    local package_path="${cache_dir}/${package_file}"
    
    # Verify package exists
    if [ ! -f "$package_path" ]; then
        echo "Cached package file not found. Rebuilding..."
        if ! build_and_cache_claude "$build_format"; then
            echo "Error: Failed to rebuild Claude Desktop."
            return 1
        fi
        
        # Read package file from metadata again
        if [ -f "$metadata_file" ]; then
            package_file=$(grep -o '"file": "[^"]*"' "$metadata_file" 2>/dev/null | cut -d'"' -f4)
            package_path="${cache_dir}/${package_file}"
        else
            echo "Error: Metadata file not found after rebuild."
            return 1
        fi
        
        # Final verification
        if [ ! -f "$package_path" ]; then
            echo "Error: Package file still not found after rebuild: ${package_path}"
            return 1
        fi
    fi
    
    # Install in sandbox
    echo "Installing Claude Desktop in sandbox '${sandbox_name}'..."
    
    # Copy package to sandbox
    local sandbox_home="${SANDBOX_BASE}/${sandbox_name}"
    mkdir -p "${sandbox_home}/Downloads"
    
    if ! cp -f "$package_path" "${sandbox_home}/Downloads/"; then
        echo "Error: Failed to copy package to sandbox."
        return 1
    fi
    
    # Install the package in the sandbox
    local install_success=false
    if [ "$build_format" = "deb" ]; then
        if run_in_sandbox "$sandbox_name" dpkg -i "/home/agent/Downloads/$(basename "$package_path")"; then
            install_success=true
        fi
    else
        local appimage_file="/home/agent/Downloads/$(basename "$package_path")"
        if run_in_sandbox "$sandbox_name" chmod +x "$appimage_file"; then
            
            # Create desktop entry for AppImage
            local desktop_dir="/home/agent/.local/share/applications"
            run_in_sandbox "$sandbox_name" mkdir -p "$desktop_dir"
            
            # Run in sandbox to create desktop entry
            if run_in_sandbox "$sandbox_name" bash -c "cat > ${desktop_dir}/claude-desktop.desktop << EOF
[Desktop Entry]
Name=Claude Desktop
Comment=Claude Desktop AI Assistant
Exec=${appimage_file} %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
EOF"; then
                install_success=true
            fi
        fi
    fi
    
    if [ "$install_success" = "true" ]; then
        echo "Claude Desktop installed successfully in sandbox '${sandbox_name}'!"
        return 0
    else
        echo "Error: Failed to install Claude Desktop in sandbox."
        return 1
    fi
}
