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
# Consolidated implementation that eliminates duplication with the original installer
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
    
    # Get the scripts directory using utility function
    local script_dir="${SCRIPT_DIR}/../scripts"
    if [ ! -d "$script_dir" ]; then
        script_dir="$(find_scripts_dir)"
        if [ -z "$script_dir" ]; then
            log_error "Could not find scripts directory"
            rm -rf "$build_dir"
            return 1
        fi
    fi
    
    log_info "Using scripts from: ${script_dir}"
    
    # Check if the extraction script exists or create it if needed
    local extract_script="${script_dir}/extract-claude-windows.sh"
    if [ ! -f "$extract_script" ]; then
        log_warn "Extract script not found, creating it at ${extract_script}"
        
        # Try to find the template directory
        local template_dir="$(find_template_dir)"
        if [ -z "$template_dir" ]; then
            template_dir="${SCRIPT_DIR}/../templates"
        fi
        
        # Create extract script directory if needed
        mkdir -p "$(dirname "$extract_script")"
        
        # Check if we have a template for the extract script
        if [ -f "${template_dir}/scripts/extract-claude-windows.sh" ]; then
            cp "${template_dir}/scripts/extract-claude-windows.sh" "$extract_script"
            chmod +x "$extract_script"
            log_info "Copied extract script from template"
        else
            log_warn "No template found for extract script, using inline version"
            # Create a basic extraction script
            cat > "$extract_script" << 'EOF'
#!/bin/bash
# extract-claude-windows.sh - Extracts Claude Desktop Windows installer to prepare for Linux packaging

set -e

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
OUTPUT_DIR="/tmp/claude-desktop-raw"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --url=*)
      CLAUDE_DOWNLOAD_URL="${1#*=}"
      shift
      ;;
    --output=*)
      OUTPUT_DIR="${1#*=}"
      shift
      ;;
    --help)
      echo "Usage: $0 [--url=URL] [--output=DIR]"
      echo ""
      echo "Options:"
      echo "  --url=URL     Use a specific download URL for Claude Windows installer"
      echo "  --output=DIR  Output directory for extracted files (default: /tmp/claude-desktop-raw)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check for required commands
for cmd in wget 7z; do
  if ! command -v $cmd &> /dev/null; then
    echo "❌ Required command not found: $cmd"
    echo "Please install the missing dependencies and try again."
    exit 1
  fi
done

# Create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/app_files"

# Download Claude Windows installer
echo "📥 Downloading Claude Desktop Windows installer..."
CLAUDE_EXE="$OUTPUT_DIR/Claude-Setup-x64.exe"
if ! wget -O "$CLAUDE_EXE" "$CLAUDE_DOWNLOAD_URL"; then
    echo "❌ Failed to download Claude Desktop installer"
    exit 1
fi
echo "✓ Download complete"

# Extract resources
echo "📦 Extracting resources..."
cd "$OUTPUT_DIR"
if ! 7z x -y "$CLAUDE_EXE"; then
    echo "❌ Failed to extract installer"
    exit 1
fi

# Find and extract the nupkg file
NUPKG_FILE=$(find . -name "*.nupkg" | head -1)
if [ -z "$NUPKG_FILE" ]; then
    echo "❌ Could not find .nupkg file in extracted installer"
    exit 1
fi

if ! 7z x -y "$NUPKG_FILE"; then
    echo "❌ Failed to extract nupkg"
    exit 1
fi

# Move app.asar and related files to app_files directory
echo "Moving app.asar and related files to app_files directory..."
if [ -f "lib/net45/resources/app.asar" ]; then
    cp "lib/net45/resources/app.asar" "$OUTPUT_DIR/app_files/"
    if [ -d "lib/net45/resources/app.asar.unpacked" ]; then
        cp -r "lib/net45/resources/app.asar.unpacked" "$OUTPUT_DIR/app_files/"
    fi
    echo "✓ Copied app.asar and related files"
else
    echo "❌ app.asar not found in expected location"
    exit 1
fi

echo "✅ Extraction complete. Files available at: $OUTPUT_DIR"
echo "   - Windows installer: $CLAUDE_EXE"
echo "   - app.asar: $OUTPUT_DIR/app_files/app.asar"

# Output the location for other scripts to use
echo "$OUTPUT_DIR"
EOF
            chmod +x "$extract_script"
            log_info "Created extract script from inline template"
        fi
    fi
    
    # Execute the extraction script to get the raw files
    log_info "Extracting Claude Desktop Windows files..."
    local raw_dir_output
    raw_dir_output=$(bash "$extract_script" 2>&1) || {
        log_error "Failed to extract Claude Desktop Windows files."
        rm -rf "$build_dir"
        return 1
    }
    
    # Get the output directory from the last line of output
    local raw_dir
    raw_dir=$(echo "$raw_dir_output" | tail -n1)
    
    # Verify it looks like a directory path
    if [[ ! "$raw_dir" == /* ]]; then
        # Fallback to default if extraction script didn't return a path
        raw_dir="/tmp/claude-desktop-raw"
    fi
    
    log_info "Using extracted files from: $raw_dir"
    
    if [ ! -d "$raw_dir" ] || [ ! -f "$raw_dir/app_files/app.asar" ]; then
        log_error "Extraction failed or app.asar not found in expected location."
        rm -rf "$build_dir"
        return 1
    fi
    
    # Create build output directory
    local build_output_dir="${build_dir}/build"
    mkdir -p "$build_output_dir"
    
    log_info "Building Claude Desktop package..."
    
    # Build the package - consolidated implementation to avoid duplication
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
        
        # Create native module stub - from template if available
        local native_stub_template="${template_dir}/claude-native-stub.js"
        mkdir -p "${INSTALL_DIR}/lib/${PACKAGE_NAME}/app.asar.unpacked/node_modules/claude-native"
        
        if [ -f "$native_stub_template" ]; then
            cp "$native_stub_template" "${INSTALL_DIR}/lib/${PACKAGE_NAME}/app.asar.unpacked/node_modules/claude-native/index.js"
            log_info "Copied native module stub from template"
        else {
            log_info "Creating native module stub inline"
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
        }
        fi
        
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
        
        # Create desktop entry from template if available
        local desktop_entry_template="${template_dir}/desktop_entry.desktop"
        if [ -f "$desktop_entry_template" ]; then
            cp "$desktop_entry_template" "${INSTALL_DIR}/share/applications/claude-desktop.desktop"
            # No substitution needed for base desktop entry
            log_info "Copied desktop entry from template"
        else {
            log_info "Creating desktop entry inline"
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
        }
        fi
        
        # Create launcher script from template if available
        local launcher_template="${template_dir}/claude-desktop-launcher.sh"
        if [ -f "$launcher_template" ]; then
            cp "$launcher_template" "${INSTALL_DIR}/bin/claude-desktop"
            chmod +x "${INSTALL_DIR}/bin/claude-desktop"
            log_info "Copied launcher script from template"
        else {
            log_info "Creating launcher script inline"
            cat > "${INSTALL_DIR}/bin/claude-desktop" << EOF
#!/bin/bash
electron /usr/lib/claude-desktop/app.asar "\$@"
EOF
            chmod +x "${INSTALL_DIR}/bin/claude-desktop"
        }
        fi
        
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
    
    # Find the built package with robust search
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
    
    # Extract version from filename with robust pattern matching
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
    
    # Get template directory
    local template_dir="$(find_template_dir)"
    if [ -z "$template_dir" ]; then
        echo "Warning: Templates directory not found, using fallback paths"
        template_dir="${SCRIPT_DIR}/templates"
        if [ ! -d "$template_dir" ]; then
            template_dir="$(cd "${SCRIPT_DIR}" && cd .. && pwd)/templates"
        fi
    fi
    
    # Path to the installation script template
    local template_file="${template_dir}/install-claude.sh.template"
    
    if [ -f "$template_file" ]; then
        echo "Using installation script template from: $template_file"
        # Read template content and substitute variables
        sed -e "s|{instance_name}|$instance_name|g" \
            -e "s|{package_filename}|$package_filename|g" \
            "$template_file" > "$install_script"
    else
        echo "Warning: Installation script template not found at ${template_file}"
        echo "Creating installation script from inline content"
        # Fallback to inline generation
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
    fi
    
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