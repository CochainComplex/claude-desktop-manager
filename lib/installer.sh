#!/bin/bash
# installer.sh - Installation and caching utilities for Claude Desktop Manager

# Set up logging
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_file="${CMGR_HOME}/logs/installer.log"
    
    # Create log directory if it doesn't exist
    log_dir="$(dirname "$log_file")"
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi
    
    # Log to file (only if directory exists and is writable)
    if [ -d "$log_dir" ] && [ -w "$log_dir" ]; then
        echo "[$timestamp] [$level] $message" >> "$log_file" 2>/dev/null || true
    fi
    
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

# Create a simple installation script for use inside the sandbox
create_installation_script() {
    local sandbox_home="$1"
    local instance_name="$2"
    local package_filename="$3"
    
    # Installation script path in the sandbox
    local install_script="${sandbox_home}/install-claude.sh"
    
    # Create the installation script
    cat > "${install_script}" << EOF
#!/bin/bash
# Claude Desktop installation script for sandboxed environment
set -e

# Display some debug info
echo "==== Installation Debug Info ===="
echo "User: \$(whoami)"
echo "Home: \$HOME"
echo "Working directory: \$(pwd)"
echo "=============================="

# Check if the package exists
if [ ! -f "\$HOME/Downloads/${package_filename}" ]; then
    echo "ERROR: Package file not found at \$HOME/Downloads/${package_filename}"
    ls -la "\$HOME/Downloads"
    exit 1
fi

# Create temp directory for extraction
echo "Creating temporary extraction directory..."
mkdir -p "\$HOME/temp-extract"
cd "\$HOME/temp-extract"

# Extract the .deb package
echo "Extracting .deb package..."
if command -v dpkg-deb &> /dev/null; then
    echo "Using dpkg-deb for extraction"
    dpkg-deb -x "\$HOME/Downloads/${package_filename}" .
elif command -v ar &> /dev/null; then
    echo "Using ar and tar for extraction"
    ar x "\$HOME/Downloads/${package_filename}"
    
    # Find and extract the data archive
    if [ -f "data.tar.xz" ]; then
        echo "Extracting data.tar.xz"
        tar -xf data.tar.xz
    elif [ -f "data.tar.gz" ]; then
        echo "Extracting data.tar.gz"
        tar -xf data.tar.gz
    elif [ -f "data.tar.zst" ] && command -v unzstd &> /dev/null; then
        echo "Extracting data.tar.zst"
        tar --use-compress-program=unzstd -xf data.tar.zst
    elif [ -f "data.tar" ]; then
        echo "Extracting data.tar"
        tar -xf data.tar
    else
        echo "ERROR: Couldn't find a suitable data archive to extract"
        ls -la
        exit 1
    fi
else
    echo "ERROR: Neither dpkg-deb nor ar found. Cannot extract package."
    exit 1
fi

# Check if extraction was successful
echo "Checking extraction results..."
if [ ! -d "usr" ]; then
    echo "ERROR: Extraction failed - usr directory not found"
    ls -la
    exit 1
fi

# Show extracted content
echo "Extracted package contents:"
find . -name "claude-desktop" -o -name "app.asar"

# Create necessary directories
echo "Setting up application directories..."
mkdir -p "\$HOME/.local/bin"
mkdir -p "\$HOME/.local/share/applications"
mkdir -p "\$HOME/.local/share/claude-desktop"

# Install executable
if [ -f "usr/bin/claude-desktop" ]; then
    echo "Installing claude-desktop executable..."
    cp "usr/bin/claude-desktop" "\$HOME/.local/bin/"
    chmod +x "\$HOME/.local/bin/claude-desktop"
else
    echo "Creating fallback executable..."
    cat > "\$HOME/.local/bin/claude-desktop" << 'EXECEOF'
#!/bin/bash
# Fallback launcher for Claude Desktop
exec electron --no-sandbox --disable-dev-shm-usage --js-flags="--expose-gc" "\$HOME/.local/share/claude-desktop/app.asar" "\$@"
EXECEOF
    chmod +x "\$HOME/.local/bin/claude-desktop"
fi

# Copy app resources
if [ -d "usr/lib/claude-desktop" ]; then
    echo "Copying application resources..."
    cp -r usr/lib/claude-desktop/* "\$HOME/.local/share/claude-desktop/"
fi

# Copy desktop entries and icons if available
if [ -d "usr/share/applications" ]; then
    cp -r usr/share/applications/* "\$HOME/.local/share/applications/"
fi

if [ -d "usr/share/claude-desktop" ]; then
    cp -r usr/share/claude-desktop/* "\$HOME/.local/share/claude-desktop/"
fi

if [ -d "usr/share/icons" ]; then
    mkdir -p "\$HOME/.local/share/icons"
    cp -r usr/share/icons/* "\$HOME/.local/share/icons/"
fi

# Create desktop entry
echo "Creating desktop entry for instance '${instance_name}'..."
cat > "\$HOME/.local/share/applications/claude-desktop-${instance_name}.desktop" << EOF2
[Desktop Entry]
Name=Claude Desktop (${instance_name})
Comment=Claude Desktop AI Assistant (${instance_name} instance)
Exec=env CLAUDE_INSTANCE=${instance_name} LIBVA_DRIVER_NAME=dummy "\$HOME/.local/bin/claude-desktop" --disable-gpu --no-sandbox --disable-dev-shm-usage --js-flags="--expose-gc" --preload="\$HOME/.config/claude-desktop/preload.js" %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude-${instance_name}
EOF2

# Cleanup
echo "Cleaning up..."
cd "\$HOME"
rm -rf "\$HOME/temp-extract"

# Verify installation
if [ -x "\$HOME/.local/bin/claude-desktop" ]; then
    echo "✅ Claude Desktop installation complete!"
    echo "Executable: \$HOME/.local/bin/claude-desktop"
    
    if [ -f "\$HOME/.local/share/claude-desktop/app.asar" ]; then
        echo "✅ App resources installed: \$HOME/.local/share/claude-desktop/app.asar"
    else
        echo "⚠️ Warning: app.asar not found"
    fi
    
    echo "Desktop entry created: \$HOME/.local/share/applications/claude-desktop-${instance_name}.desktop"
    
    exit 0
else
    echo "❌ Installation failed: Executable not found at \$HOME/.local/bin/claude-desktop"
    exit 1
fi
EOF
    
    # Make the installation script executable
    chmod +x "${install_script}"
    
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
    
    # Debug info about package
    ls -l "$package_path"
    echo "Copying package from $package_path to ${SANDBOX_BASE}/${sandbox_name}/Downloads/"
    
    # Copy package to sandbox
    local sandbox_home="${SANDBOX_BASE}/${sandbox_name}"
    mkdir -p "${sandbox_home}/Downloads"
    
    # Ensure the package file is copied correctly
    if ! cp -f "$package_path" "${sandbox_home}/Downloads/"; then
        log_error "Failed to copy package to sandbox Downloads directory."
        return 1
    fi
    
    # Make sure the file has proper permissions
    chmod 644 "${sandbox_home}/Downloads/$(basename "$package_path")"
    
    # Verify the file was copied correctly
    if [ ! -f "${sandbox_home}/Downloads/$(basename "$package_path")" ]; then
        log_error "Package file not found in sandbox after copying."
        return 1
    fi
    
    # Get the package filename
    local package_filename=$(basename "$package_path")
    
    # Copy scripts to sandbox
    mkdir -p "${sandbox_home}/.config/claude-desktop"
    mkdir -p "${sandbox_home}/.config/Claude/electron"
    
    # Create installation script
    if ! create_installation_script "$sandbox_home" "$sandbox_name" "$package_filename"; then
        log_error "Failed to create installation script in sandbox."
        return 1
    fi
    
    # Copy our fallback executable template to the sandbox
    if [ -f "${SCRIPT_DIR}/../templates/claude-desktop-linux" ]; then
        cp "${SCRIPT_DIR}/../templates/claude-desktop-linux" "${sandbox_home}/.config/claude-desktop/"
        chmod +x "${sandbox_home}/.config/claude-desktop/claude-desktop-linux"
        echo "Copied fallback executable template to sandbox"
    fi
    
    # Use absolute path for template files
    local template_dir="${SCRIPT_DIR}/../templates"
    if [ ! -d "${template_dir}" ]; then
        # Try to find the templates directory using absolute path
        template_dir="$(cd "${SCRIPT_DIR}" && cd .. && pwd)/templates"
        # For safety, check if we're in the project root
        if [ ! -d "${template_dir}" ]; then
            # Last resort, use the path directly
            template_dir="/home/awarth/Devstuff/claude-desktop-manager/templates"
        fi
    fi
    
    # Log where we're looking for templates
    log_info "Using templates directory: ${template_dir}"
    
    # Copy preload script to standard locations if it exists
    if [ -f "${template_dir}/scripts/preload.js" ]; then
        cp -f "${template_dir}/scripts/preload.js" "${sandbox_home}/.config/claude-desktop/"
        cp -f "${template_dir}/scripts/preload.js" "${sandbox_home}/.config/Claude/electron/"
        log_info "Copied preload.js to sandbox"
    else
        log_warn "Could not find preload.js in ${template_dir}/scripts/"
    fi
    
    # Copy patch-app.js script if it exists
    local scripts_dir="${SCRIPT_DIR}/../scripts"
    
    # Use absolute path if needed
    if [ ! -d "${scripts_dir}" ] || [ ! -f "${scripts_dir}/patch-app.js" ]; then
        scripts_dir="/home/awarth/Devstuff/claude-desktop-manager/scripts"
    fi
    
    if [ -f "${scripts_dir}/patch-app.js" ]; then
        cp -f "${scripts_dir}/patch-app.js" "${sandbox_home}/.config/claude-desktop/"
        log_info "Copied patch-app.js to sandbox from ${scripts_dir}"
    else
        log_warn "Could not find patch-app.js in ${scripts_dir}"
    fi
    
    # Run the installation script in the sandbox
    log_info "Running installation script in sandbox..."
    
    # Create a wrapper script to ignore the UID mapping error
    local wrapper_script="${sandbox_home}/wrapper.sh"
    cat > "$wrapper_script" << 'EOF'
#!/bin/bash

# Run the install script and capture its output and exit status
./install-claude.sh 2>&1 | tee /tmp/install-output.log

# Check if the only error was the UID mapping error
if grep -q "setting up uid map: Permission denied" /tmp/install-output.log && ! grep -q "ERROR:" /tmp/install-output.log; then
    # Success - ignore the UID mapping error
    exit 0
fi

# Otherwise, preserve the original exit code
exit ${PIPESTATUS[0]}
EOF
    
    chmod +x "$wrapper_script"
    
    # Run the wrapper
    if ! run_in_sandbox "$sandbox_name" "./wrapper.sh"; then
        # Even if the script failed, check if the executable was installed anyway
        if run_in_sandbox "$sandbox_name" "[ -x \$HOME/.local/bin/claude-desktop ]" 2>/dev/null; then
            log_warn "Install script reported error but claude-desktop executable exists, continuing..."
        else
            log_error "Installation script failed."
            return 1
        fi
    fi
    
    # Verify installation by checking for executable
    if run_in_sandbox "$sandbox_name" bash -c "[ -x \$HOME/.local/bin/claude-desktop ]"; then
        log_info "Claude Desktop installed successfully in sandbox '${sandbox_name}'!"
        
        # Apply instance customization and MaxListenersExceededWarning fix
        log_info "Applying instance customization and MaxListenersExceededWarning fix..."
        
        # Run the patcher script in the sandbox
        run_in_sandbox "$sandbox_name" bash -c "
            # First check if nodejs is installed
            if ! command -v node &>/dev/null; then
                echo 'Installing Node.js for patching...'
                mkdir -p ~/.local/share/nodejs
                curl -sL https://nodejs.org/dist/v18.16.0/node-v18.16.0-linux-x64.tar.gz | tar xz -C ~/.local/share/nodejs --strip-components=1
                export PATH=~/.local/share/nodejs/bin:\$PATH
            fi
            
            # Install asar if needed
            if ! command -v asar &>/dev/null && ! command -v npx &>/dev/null; then
                echo 'Installing asar...'
                mkdir -p ~/.local/share/npm
                npm config set prefix ~/.local/share/npm
                export PATH=~/.local/share/npm/bin:\$PATH
                npm install -g asar
            fi
            
            # Find app.asar files - search in user and system directories
            APP_DIRS=(~/.local/share/claude-desktop ~/.local/lib/claude-desktop /usr/lib/claude-desktop ~/.local/bin)
            
            for dir in \"\${APP_DIRS[@]}\"; do
                if [ -d \"\$dir\" ]; then
                    ASAR_FILE=\$(find \"\$dir\" -name 'app.asar' | head -1)
                    if [ -n \"\$ASAR_FILE\" ]; then
                        echo \"Found app.asar at \$ASAR_FILE\"
                        
                        # Run the patcher script with instance name and asar path
                        echo \"Patching app.asar for instance '$sandbox_name'...\"
                        node ~/.config/claude-desktop/patch-app.js \"$sandbox_name\" \"\$ASAR_FILE\" || echo \"Warning: Patching failed, but continuing\"
                        break
                    fi
                fi
            done
            
            echo 'Installation and patching completed!'
        " || log_warn "Failed to apply patches to app.asar, but installation completed."
        
        return 0
    else
        log_error "Claude Desktop installation verification failed."
        return 1
    fi
}
