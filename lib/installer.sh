#!/bin/bash
# installer.sh - Installation and caching utilities for Claude Desktop Manager

# Set up logging
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_file="${CMGR_HOME}/logs/installer.log"
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$log_file")"
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$log_file"
    
    # Log to console if not INFO
    if [ "$level" != "INFO" ]; then
        echo "[$level] $message"
    fi
}

log_info() { log_message "INFO" "$1"; }
log_warn() { log_message "WARN" "$1"; }
log_error() { log_message "ERROR" "$1"; }

# Build and cache Claude Desktop
build_and_cache_claude() {
    local build_format="${1:-deb}"
    local cache_dir="${CMGR_CACHE}"
    
    log_info "Building and caching Claude Desktop (${build_format})..."
    
    # Ensure cache directory exists
    mkdir -p "${cache_dir}"
    
    # Create temporary directory for building
    local build_dir
    build_dir="$(mktemp -d)"
    
    # Clone the claude-desktop repository
    if ! git clone https://github.com/emsi/claude-desktop.git "$build_dir"; then
        log_error "Failed to clone repository."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Execute the installation script in a subshell to ensure proper directory handling
    # Create a temporary directory for the build output
    local build_output_dir="${build_dir}/build"
    mkdir -p "$build_output_dir"
    
    log_info "Using install-claude-desktop.sh to build Claude Desktop..."
    
    # Modify the script to only build and not install
    if ! (cd "$build_dir" && chmod +x ./install-claude-desktop.sh && \
         sed -i 's/sudo dpkg -i "$DEB_FILE"/echo "Package built at: $DEB_FILE"/g' ./install-claude-desktop.sh && \
         ./install-claude-desktop.sh); then
        log_error "Failed to build Claude Desktop."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Find the built package with more robust search
    local package_file=""
    if [ "$build_format" = "deb" ]; then
        # First try the exact pattern
        package_file=$(find "$build_dir" -type f -name "claude-desktop_*.deb" | head -1)
        
        # If not found, try a more generic search
        if [ -z "$package_file" ]; then
            package_file=$(find "$build_dir" -type f -name "*.deb" | grep -i claude | head -1)
        fi
    else
        # Currently the install script only supports deb packages
        log_warn "AppImage format not directly supported by the installer. Using .deb format instead."
        package_file=$(find "$build_dir" -type f -name "*.deb" | grep -i claude | head -1)
    fi
    
    if [ -z "$package_file" ]; then
        log_error "No package found after build."
        log_info "Searching for any .deb files in the build directory:"
        find "$build_dir" -type f -name "*.deb" | xargs -I{} log_info "Found: {}"
        rm -rf "$build_dir"
        return 1
    fi
    
    log_info "Found package: $package_file"
    
    # Extract version from filename with more robust pattern matching
    local version=""
    local package_basename=$(basename "$package_file")
    
    # Try different version extraction patterns
    if [[ "$package_basename" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        # Extract version using regex match
        version="${BASH_REMATCH[1]}"
    elif [ "$build_format" = "deb" ]; then
        # Try specific deb pattern
        version=$(echo "$package_basename" | grep -oP 'claude-desktop_\K[0-9]+\.[0-9]+\.[0-9]+(?=_)' || echo "")
    else
        # Try specific AppImage pattern
        version=$(echo "$package_basename" | grep -oP 'claude-desktop-\K[0-9]+\.[0-9]+\.[0-9]+(?=-)' || echo "")
    fi
    
    # If all else fails, use a timestamp as the version
    if [ -z "$version" ]; then
        version="0.0.1-$(date +%Y%m%d%H%M%S)"
        log_warn "Could not extract version from filename, using generated version: $version"
    fi
    
    # Copy package to cache
    if ! cp "$package_file" "${cache_dir}/"; then
        log_error "Failed to copy package to cache directory."
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
        log_error "Failed to create metadata file."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Clean up build directory
    rm -rf "$build_dir"
    
    log_info "Claude Desktop ${version} (${build_format}) cached successfully!"
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
        log_info "No cached Claude Desktop build found. Building now..."
        if ! build_and_cache_claude "$build_format"; then
            log_error "Failed to build Claude Desktop."
            return 1
        fi
    fi
    
    # Read metadata - with error handling
    if [ ! -f "$metadata_file" ]; then
        log_error "Metadata file not found after build."
        return 1
    fi
    
    # Check if metadata file exists and is readable
    local cached_format=""
    if [ -f "$metadata_file" ]; then
        cached_format=$(grep -o '"format": "[^"]*"' "$metadata_file" 2>/dev/null | cut -d'"' -f4)
    fi
    
    # If metadata is unreadable or format doesn't match, rebuild
    if [ -z "$cached_format" ] || [ "$cached_format" != "$build_format" ]; then
        log_info "Cached format (${cached_format:-unknown}) doesn't match requested format (${build_format}). Building..."
        if ! build_and_cache_claude "$build_format"; then
            log_error "Failed to build Claude Desktop with format ${build_format}."
            return 1
        fi
        
        # Verify metadata file was created
        if [ ! -f "$metadata_file" ]; then
            log_error "Metadata file not found after rebuild."
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
        log_error "Could not determine package file from metadata."
        return 1
    fi
    
    local package_path="${cache_dir}/${package_file}"
    
    # Verify package exists
    if [ ! -f "$package_path" ]; then
        log_info "Cached package file not found. Rebuilding..."
        if ! build_and_cache_claude "$build_format"; then
            log_error "Failed to rebuild Claude Desktop."
            return 1
        fi
        
        # Read package file from metadata again
        if [ -f "$metadata_file" ]; then
            package_file=$(grep -o '"file": "[^"]*"' "$metadata_file" 2>/dev/null | cut -d'"' -f4)
            package_path="${cache_dir}/${package_file}"
        else
            log_error "Metadata file not found after rebuild."
            return 1
        fi
        
        # Final verification
        if [ ! -f "$package_path" ]; then
            log_error "Package file still not found after rebuild: ${package_path}"
            return 1
        fi
    fi
    
    # Install in sandbox
    log_info "Installing Claude Desktop in sandbox '${sandbox_name}'..."
    
    # Copy package to sandbox
    local sandbox_home="${SANDBOX_BASE}/${sandbox_name}"
    mkdir -p "${sandbox_home}/Downloads"
    
    if ! cp -f "$package_path" "${sandbox_home}/Downloads/"; then
        log_error "Failed to copy package to sandbox."
        return 1
    fi
    
    # Install the package in the sandbox
    local install_success=false
    if [ "$build_format" = "deb" ]; then
        # Extract the .deb package in the sandbox instead of using dpkg
        if run_in_sandbox "$sandbox_name" bash -c "cd $HOME && ar x $HOME/Downloads/$(basename "$package_path") && \
         ([ -f data.tar.xz ] && tar xf data.tar.xz || \
          [ -f data.tar.gz ] && tar xf data.tar.gz || \
          [ -f data.tar.zst ] && tar --use-compress-program=unzstd -xf data.tar.zst || \
          [ -f data.tar ] && tar xf data.tar) && \
         rm -f data.tar.xz data.tar.gz data.tar.zst data.tar control.tar.* debian-binary && \
         mkdir -p $HOME/.local/bin && cp -r usr/bin/claude-desktop $HOME/.local/bin/"; then
            # Create desktop entry file in the sandbox
            run_in_sandbox "$sandbox_name" bash -c "mkdir -p $HOME/.local/share/applications && cat > $HOME/.local/share/applications/claude-desktop.desktop << EOF
[Desktop Entry]
Name=Claude Desktop
Comment=Claude Desktop AI Assistant
Exec=$HOME/.local/bin/claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
EOF"
            
            # Also copy any application resources from the extracted package
            run_in_sandbox "$sandbox_name" bash -c "mkdir -p $HOME/.local/share/claude-desktop && [ -d usr/share/claude-desktop ] && cp -r usr/share/claude-desktop/* $HOME/.local/share/claude-desktop/ || true"
            
            install_success=true
        fi
    else
        local appimage_file="$HOME/Downloads/$(basename "$package_path")"
        
        if run_in_sandbox "$sandbox_name" chmod +x "$appimage_file"; then
            
            # Create desktop entry for AppImage
            local desktop_dir="$HOME/.local/share/applications"
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
        log_info "Claude Desktop installed successfully in sandbox '${sandbox_name}'!"
        return 0
    else
        log_error "Failed to install Claude Desktop in sandbox."
        return 1
    fi
}
