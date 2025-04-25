#!/bin/bash
# installer.sh - Installation and caching utilities for Claude Desktop Manager

# Build and cache Claude Desktop
build_and_cache_claude() {
    local build_format="${1:-deb}"
    local cache_dir="${CMGR_CACHE}"
    
    echo "Building and caching Claude Desktop (${build_format})..."
    
    # Create temporary directory for building
    local build_dir
    build_dir="$(mktemp -d)"
    
    # Clone the claude-desktop repository
    git clone https://github.com/emsi/claude-desktop.git "$build_dir"
    cd "$build_dir"
    
    # Build Claude Desktop
    ./build.sh --build "$build_format" --clean no
    
    # Find the built package
    local package_file=""
    if [ "$build_format" = "deb" ]; then
        package_file=$(find . -maxdepth 1 -name "claude-desktop_*.deb" | head -1)
    else
        package_file=$(find . -maxdepth 1 -name "claude-desktop-*.AppImage" | head -1)
    fi
    
    if [ -z "$package_file" ]; then
        echo "Error: No ${build_format} package found after build."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Extract version from filename
    local version=""
    if [ "$build_format" = "deb" ]; then
        version=$(echo "$package_file" | grep -oP 'claude-desktop_\K[0-9]+\.[0-9]+\.[0-9]+(?=_)')
    else
        version=$(echo "$package_file" | grep -oP 'claude-desktop-\K[0-9]+\.[0-9]+\.[0-9]+(?=-)')
    fi
    
    # Copy package to cache
    cp "$package_file" "${cache_dir}/"
    
    # Create metadata file
    cat > "${cache_dir}/metadata.json" <<EOF
{
    "version": "${version}",
    "format": "${build_format}",
    "file": "$(basename "$package_file")",
    "build_date": "$(date -Iseconds)"
}
EOF
    
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
    
    if [ ! -f "$metadata_file" ]; then
        echo "No cached Claude Desktop build found. Building now..."
        build_and_cache_claude "$build_format"
    fi
    
    # Read metadata
    local cached_format
    cached_format=$(grep -o '"format": "[^"]*"' "$metadata_file" | cut -d'"' -f4)
    
    if [ "$cached_format" != "$build_format" ]; then
        echo "Cached format (${cached_format}) doesn't match requested format (${build_format}). Building..."
        build_and_cache_claude "$build_format"
    fi
    
    local package_file
    package_file=$(grep -o '"file": "[^"]*"' "$metadata_file" | cut -d'"' -f4)
    local package_path="${cache_dir}/${package_file}"
    
    if [ ! -f "$package_path" ]; then
        echo "Cached package file not found. Rebuilding..."
        build_and_cache_claude "$build_format"
        package_file=$(grep -o '"file": "[^"]*"' "$metadata_file" | cut -d'"' -f4)
        package_path="${cache_dir}/${package_file}"
    fi
    
    # Install in sandbox
    echo "Installing Claude Desktop in sandbox '${sandbox_name}'..."
    
    # Copy package to sandbox
    local sandbox_home="${SANDBOX_BASE}/${sandbox_name}"
    mkdir -p "${sandbox_home}/Downloads"
    cp "$package_path" "${sandbox_home}/Downloads/"
    
    # Install the package in the sandbox
    if [ "$build_format" = "deb" ]; then
        run_in_sandbox "$sandbox_name" dpkg -i "/home/agent/Downloads/$(basename "$package_path")"
    else
        local appimage_file="/home/agent/Downloads/$(basename "$package_path")"
        run_in_sandbox "$sandbox_name" chmod +x "$appimage_file"
        
        # Create desktop entry for AppImage
        local desktop_dir="/home/agent/.local/share/applications"
        run_in_sandbox "$sandbox_name" mkdir -p "$desktop_dir"
        
        # Run in sandbox to create desktop entry
        run_in_sandbox "$sandbox_name" bash -c "cat > ${desktop_dir}/claude-desktop.desktop << EOF
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
EOF"
    fi
    
    echo "Claude Desktop installed successfully in sandbox '${sandbox_name}'!"
    return 0
}
