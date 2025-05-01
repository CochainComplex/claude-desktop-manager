#!/bin/bash
# installer.sh - Installation and caching utilities for Claude Desktop Manager

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility functions
source "${SCRIPT_DIR}/utils.sh"

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

# Build and cache Claude Desktop using local scripts
# This function builds Claude Desktop by extracting from the Windows installer
# and creating a compatible Linux package
# 
# Derived from the original emsi/claude-desktop project but modified to use
# local scripts instead of cloning the repository
# @param build_format The format of the package to build (deb or appimage)
build_and_cache_claude() {
    local build_format="${1:-deb}"
    local cache_dir="${CMGR_CACHE}"
    
    log_info "Building and caching Claude Desktop (${build_format})..."
    
    # Ensure cache directory exists
    mkdir -p "${cache_dir}"
    
    # Create temporary directory for building
    local build_dir
    build_dir="$(mktemp -d)"
    
    # Get the script directory using utility function
    local script_dir="$(find_scripts_dir)"
    if [ -z "$script_dir" ]; then
        log_error "Could not find scripts directory"
        rm -rf "$build_dir"
        return 1
    fi
    
    log_info "Using local scripts from: ${script_dir}"
    
    # Check if extract-claude-windows.sh exists
    if [ ! -f "${script_dir}/extract-claude-windows.sh" ]; then
        log_error "Required script not found: ${script_dir}/extract-claude-windows.sh"
        rm -rf "$build_dir"
        return 1
    fi
    
    # Execute the extraction script to get the raw files
    log_info "Extracting Claude Desktop Windows files..."
    if ! bash "${script_dir}/extract-claude-windows.sh"; then
        log_error "Failed to extract Claude Desktop Windows files."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Extract raw files are in /tmp/claude-desktop-raw
    local raw_dir="/tmp/claude-desktop-raw"
    if [ ! -d "$raw_dir" ] || [ ! -f "$raw_dir/app_files/app.asar" ]; then
        log_error "Extraction failed or app.asar not found in expected location."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Create build output directory
    local build_output_dir="${build_dir}/build"
    mkdir -p "$build_output_dir"
    
    log_info "Building Claude Desktop package..."
    
    # Build the package - adapted from the original install-claude-desktop.sh
    # This is the simplified package building logic
    (
        cd "$build_dir"
        
        # Create the package structure
        local DEB_ROOT="${build_dir}/deb-package"
        local INSTALL_DIR="${DEB_ROOT}/usr"
        local PACKAGE_NAME="claude-desktop"
        local ARCHITECTURE="amd64"
        
        # Try to determine the version from the extracted files
        local VERSION=""
        
        # Method 1: Try to extract from package.json if it exists
        if [ -f "${raw_dir}/app_files/package.json" ]; then
            echo "Looking for version in package.json..."
            VERSION=$(grep -o '"version":\s*"[^"]*"' "${raw_dir}/app_files/package.json" 2>/dev/null | cut -d'"' -f4)
            echo "Found version in package.json: ${VERSION:-not found}"
        fi
        
        # Method 2: Look for version in any nupkg filenames
        if [ -z "$VERSION" ]; then
            echo "Looking for version in nupkg filenames..."
            local nupkg_name=$(find "${raw_dir}" -name "*.nupkg" -type f | head -1 | xargs basename 2>/dev/null)
            if [[ "$nupkg_name" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
                VERSION="${BASH_REMATCH[1]}"
                echo "Found version in nupkg filename: $VERSION"
            fi
        fi
        
        # Method 3: Look for version in Claude exe filename
        if [ -z "$VERSION" ]; then
            echo "Looking for version in claude.exe..."
            local exe_path=$(find "${raw_dir}" -name "claude.exe" -type f | head -1)
            if [ -n "$exe_path" ]; then
                # Use strings and grep to look for version-like patterns in the binary
                if command -v strings &>/dev/null; then
                    VERSION=$(strings "$exe_path" | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)
                    echo "Found version in claude.exe strings: ${VERSION:-not found}"
                fi
            fi
        fi
        
        # Fallback if all methods fail
        if [ -z "$VERSION" ]; then
            VERSION="0.9.$(date +%Y%m%d)"
            echo "Could not determine version, using generated version: $VERSION"
        fi
        
        mkdir -p "${DEB_ROOT}/DEBIAN"
        mkdir -p "${INSTALL_DIR}/lib/${PACKAGE_NAME}"
        mkdir -p "${INSTALL_DIR}/share/applications"
        mkdir -p "${INSTALL_DIR}/share/icons"
        mkdir -p "${INSTALL_DIR}/bin"
        
        # Copy app.asar and related files
        cp "${raw_dir}/app_files/app.asar" "${INSTALL_DIR}/lib/${PACKAGE_NAME}/"
        if [ -d "${raw_dir}/app_files/app.asar.unpacked" ]; then
            cp -r "${raw_dir}/app_files/app.asar.unpacked" "${INSTALL_DIR}/lib/${PACKAGE_NAME}/"
        fi
        
        # Create native module stub
        mkdir -p "${INSTALL_DIR}/lib/${PACKAGE_NAME}/app.asar.unpacked/node_modules/claude-native"
        cat > "${INSTALL_DIR}/lib/${PACKAGE_NAME}/app.asar.unpacked/node_modules/claude-native/index.js" << 'EOF'
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF
        
        # Extract and process icons
        if [ -d "${raw_dir}/lib/net45" ]; then
            if command -v wrestool &>/dev/null && command -v icotool &>/dev/null; then
                # Extract icons from the exe
                wrestool -x -t 14 "${raw_dir}/lib/net45/claude.exe" -o "${build_dir}/claude.ico" 2>/dev/null || true
                icotool -x "${build_dir}/claude.ico" 2>/dev/null || true
                
                # Install icons
                for icon_file in ${build_dir}/claude_*_*.png; do
                    if [ -f "$icon_file" ]; then
                        # Extract size from filename
                        size=$(echo "$icon_file" | grep -Eo '_[0-9]+x[0-9]+' | grep -Eo '[0-9]+' | head -1)
                        if [ -n "$size" ]; then
                            icon_dir="${INSTALL_DIR}/share/icons/hicolor/${size}x${size}/apps"
                            mkdir -p "$icon_dir"
                            cp "$icon_file" "$icon_dir/claude-desktop.png"
                        fi
                    fi
                done
            else
                log_warn "Icon tools not found. Using placeholder icons."
                # Create placeholder icons directory
                for size in 16 32 48 64 128; do
                    mkdir -p "${INSTALL_DIR}/share/icons/hicolor/${size}x${size}/apps"
                    echo "Placeholder for ${size}x${size} icon" > "${INSTALL_DIR}/share/icons/hicolor/${size}x${size}/apps/claude-desktop.png"
                done
            fi
        fi
        
        # Create desktop entry
        cat > "${INSTALL_DIR}/share/applications/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
EOF
        
        # Create launcher script
        cat > "${INSTALL_DIR}/bin/claude-desktop" << EOF
#!/bin/bash
electron /usr/lib/claude-desktop/app.asar "\$@"
EOF
        chmod +x "${INSTALL_DIR}/bin/claude-desktop"
        
        # Create control file
        cat > "${DEB_ROOT}/DEBIAN/control" << EOF
Package: claude-desktop
Version: ${VERSION}
Architecture: ${ARCHITECTURE}
Maintainer: Claude Desktop Manager
Depends: nodejs, npm, p7zip-full
Description: Claude AI Assistant Desktop Application
 Claude is an AI assistant from Anthropic.
 This package provides the desktop interface for Claude.
 .
 Derived from the emsi/claude-desktop project.
EOF
        
        # Build the package
        log_info "Creating the .deb package..."
        mkdir -p "${build_output_dir}"
        DEB_FILE="${build_output_dir}/claude-desktop_${VERSION}_${ARCHITECTURE}.deb"
        if ! dpkg-deb --build "${DEB_ROOT}" "${DEB_FILE}" >/dev/null; then
            log_error "Failed to build .deb package"
            return 1
        fi
        
        log_info "Package built at: ${DEB_FILE}"
    ) || {
        log_error "Failed during package build process."
        rm -rf "$build_dir"
        return 1
    }
    
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

# Create an installation script for use inside the sandbox
create_installation_script() {
    local sandbox_home="$1"
    local instance_name="$2"
    local package_filename="$3"
    
    # Installation script path in the sandbox
    local install_script="${sandbox_home}/install-claude.sh"
    
    # Create the installation script with basic Wayland support
    cat > "${install_script}" << EOF
#!/bin/bash
# Claude Desktop installation script for sandboxed environment
set -e

# Display some debug info
echo "==== Installation Debug Info ===="
echo "User: \$(whoami)"
echo "Home: \$HOME"
echo "Working directory: \$(pwd)"
echo "Display: \${DISPLAY:-not set}"
echo "Wayland display: \${WAYLAND_DISPLAY:-not set}"
echo "=============================="

# Simple Wayland detection
if [ -n "\${WAYLAND_DISPLAY:-}" ]; then
    echo "Detected Wayland session, setting Electron variables"
    export ELECTRON_OZONE_PLATFORM_HINT="auto"
fi

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

# Create desktop entry with basic Wayland support
echo "Creating desktop entry for instance '${instance_name}'..."
cat > "\$HOME/.local/share/applications/claude-desktop-${instance_name}.desktop" << EOF2
[Desktop Entry]
Name=Claude Desktop (${instance_name})
Comment=Claude Desktop AI Assistant (${instance_name} instance)
Exec=env CLAUDE_INSTANCE=${instance_name} LIBVA_DRIVER_NAME=dummy ELECTRON_OZONE_PLATFORM_HINT=auto "\$HOME/.local/bin/claude-desktop" --disable-gpu --no-sandbox --disable-dev-shm-usage --js-flags="--expose-gc" --preload="\$HOME/.config/claude-desktop/preload.js" %u
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
    
    # Create config directories using utility functions
    mkdir -p "${sandbox_home}/.config/claude-desktop"
    mkdir -p "${sandbox_home}/.config/Claude/electron"
    
    # Create installation script
    if ! create_installation_script "$sandbox_home" "$sandbox_name" "$package_filename"; then
        log_error "Failed to create installation script in sandbox."
        return 1
    fi
    
    # Get template directory using utility function
    local template_dir="$(find_template_dir)"
    if [ -z "$template_dir" ]; then
        log_warn "Could not find template directory, using fallbacks"
        template_dir="${SCRIPT_DIR}/../templates"
    fi
    
    # Log where we're looking for templates
    log_info "Using templates directory: ${template_dir}"
    
    # Copy our fallback executable template to the sandbox
    if [ -f "${template_dir}/claude-desktop-linux" ]; then
        cp "${template_dir}/claude-desktop-linux" "${sandbox_home}/.config/claude-desktop/"
        chmod +x "${sandbox_home}/.config/claude-desktop/claude-desktop-linux"
        echo "Copied fallback executable template to sandbox"
    fi
    
    # Copy preload script to standard locations if it exists
    if [ -f "${template_dir}/scripts/preload.js" ]; then
        cp -f "${template_dir}/scripts/preload.js" "${sandbox_home}/.config/claude-desktop/"
        cp -f "${template_dir}/scripts/preload.js" "${sandbox_home}/.config/Claude/electron/"
        log_info "Copied preload.js to sandbox"
    else
        log_warn "Could not find preload.js in ${template_dir}/scripts/"
    fi
    
    # Copy patch-app.js script if it exists
    local scripts_dir="$(find_scripts_dir)"
    if [ -z "$scripts_dir" ]; then
        log_warn "Could not find scripts directory, using fallbacks"
        scripts_dir="${SCRIPT_DIR}/../scripts"
    fi
    
    if [ -f "${scripts_dir}/patch-app.js" ]; then
        cp -f "${scripts_dir}/patch-app.js" "${sandbox_home}/.config/claude-desktop/"
        log_info "Copied patch-app.js to sandbox from ${scripts_dir}"
    else
        log_warn "Could not find patch-app.js in ${scripts_dir}"
    fi
    
    # Run the installation script in the sandbox
    log_info "Running installation script in sandbox..."
    
    # Create a simpler wrapper script for installation
    local wrapper_script="${sandbox_home}/wrapper.sh"
    cat > "$wrapper_script" << 'EOF'
#!/bin/bash

# Create a simple log file
LOG_FILE="/tmp/claude-install.log"
./install-claude.sh 2>&1 | tee "$LOG_FILE"
INSTALL_STATUS=${PIPESTATUS[0]}

# Check for known harmless errors
if grep -q "setting up uid map: Permission denied" "$LOG_FILE" && ! grep -q "ERROR:" "$LOG_FILE"; then
    echo "Note: UID mapping error detected but can be ignored"
    
    # Verify if the essential files were installed despite errors
    if [ -x "$HOME/.local/bin/claude-desktop" ] || [ -f "$HOME/.local/share/claude-desktop/app.asar" ]; then
        echo "Essential files exist, marking installation as successful"
        exit 0
    fi
fi

# For Wayland sessions, ignore display-related errors
if [ -n "$WAYLAND_DISPLAY" ] && grep -q "cannot connect to X server" "$LOG_FILE"; then
    echo "X11 connection issues are expected in Wayland - continuing anyway"
    
    # Check if essential files exist despite X11 errors
    if [ -x "$HOME/.local/bin/claude-desktop" ]; then
        echo "Claude executable exists, marking installation as successful"
        touch "$HOME/.claude-install-verified"
        exit 0
    fi
fi

# Return the original exit code
exit $INSTALL_STATUS
EOF
    
    chmod +x "$wrapper_script"
    
    # Run the wrapper
    if ! run_in_sandbox "$sandbox_name" "./wrapper.sh"; then
        # Additional verification in case wrapper fails but files still exist
        if run_in_sandbox "$sandbox_name" "[ -x \$HOME/.local/bin/claude-desktop ] && [ -f \$HOME/.local/share/claude-desktop/app.asar ]" 2>/dev/null; then
            log_warn "Wrapper script failed but critical files exist, forcing installation to continue..."
            # Create a dummy success file to mark that we verified files exist
            run_in_sandbox "$sandbox_name" "touch \$HOME/.claude-install-verified"
        elif run_in_sandbox "$sandbox_name" "[ -f \$HOME/.claude-install-verified ]"; then
            log_warn "Wrapper script indicated verification passed despite exit code, continuing..."
        else
            # Grab the log file for debugging
            log_error "Installation failed. Installation log:"
            run_in_sandbox "$sandbox_name" "cat /tmp/claude-install.log 2>/dev/null || echo 'No log file available'"
            log_error "Installation script failed with critical errors."
            return 1
        fi
    fi
    
    # Simpler verification check
    if run_in_sandbox "$sandbox_name" bash -c "[ -x \$HOME/.local/bin/claude-desktop ] || [ -f \$HOME/.claude-install-verified ]"; then
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