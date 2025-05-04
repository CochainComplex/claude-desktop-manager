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
    
    log_info "Creating build directory at: ${build_dir}"
    
    # Use our local implementation instead of cloning the repository
    log_info "Building Claude Desktop package..."
    
    # Update this URL when a new version of Claude Desktop is released
    local CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
    
    # Create working directories
    local WORK_DIR="${build_dir}"
    local DEB_ROOT="${WORK_DIR}/deb-package"
    local INSTALL_DIR="${DEB_ROOT}/usr"
    
    mkdir -p "${DEB_ROOT}/DEBIAN"
    mkdir -p "${INSTALL_DIR}/lib/claude-desktop"
    mkdir -p "${INSTALL_DIR}/share/applications"
    mkdir -p "${INSTALL_DIR}/share/icons"
    mkdir -p "${INSTALL_DIR}/bin"
    
    # Download Claude Windows installer
    log_info "Downloading Claude Desktop installer..."
    local CLAUDE_EXE="${WORK_DIR}/Claude-Setup-x64.exe"
    if ! wget -O "${CLAUDE_EXE}" "${CLAUDE_DOWNLOAD_URL}"; then
        log_error "Failed to download Claude Desktop installer"
        rm -rf "${build_dir}"
        return 1
    fi
    log_info "Download complete"
    
    # Extract version from the installer filename - dynamically determine it
    # Use a timestamp-based version if we can't extract it from the filename
    local VERSION
    if [[ "${CLAUDE_DOWNLOAD_URL}" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        # Extract version using regex match if it's in the URL
        VERSION="${BASH_REMATCH[1]}"
    else
        # Try to find from nested files later
        VERSION="1.0.0-$(date +%Y%m%d)"
    fi
    
    # Log the detected version
    log_info "Using Claude Desktop version: ${VERSION}"
    local PACKAGE_NAME="claude-desktop"
    local ARCHITECTURE="amd64"
    local MAINTAINER="Claude Desktop Linux Maintainers"
    local DESCRIPTION="Claude Desktop for Linux"
    
    # Extract resources
    log_info "Extracting resources..."
    cd "${WORK_DIR}"
    if ! 7z x -y "${CLAUDE_EXE}"; then
        log_error "Failed to extract installer"
        rm -rf "${build_dir}"
        return 1
    fi
    
    # Find the .nupkg file dynamically instead of hardcoding the name
    local nupkg_file=$(find . -name "*.nupkg" | grep -i "AnthropicClaude" | head -1)
    if [ -z "$nupkg_file" ]; then
        # Fallback: try to find any .nupkg file
        nupkg_file=$(find . -name "*.nupkg" | head -1)
    fi
    
    if [ -z "$nupkg_file" ]; then
        log_error "Failed to find any .nupkg file after extraction"
        rm -rf "${build_dir}"
        return 1
    fi
    
    log_info "Found package file: $nupkg_file"
    
    if ! 7z x -y "$nupkg_file"; then
        log_error "Failed to extract nupkg: $nupkg_file"
        rm -rf "${build_dir}"
        return 1
    fi
    log_info "Resources extracted"
    
    # Find claude.exe or similar dynamically and extract icons
    log_info "Processing icons..."
    local claude_exe_path=$(find . -name "claude.exe" | head -1)
    
    # If not found, try to find any .exe file that might contain the icons
    if [ -z "$claude_exe_path" ]; then
        claude_exe_path=$(find . -name "*.exe" | grep -v "Claude-Setup" | head -1)
    fi
    
    if [ -z "$claude_exe_path" ]; then
        log_warn "Could not find claude.exe or similar. Looking for icons elsewhere..."
        # Try to find .ico files directly
        local ico_file=$(find . -name "*.ico" | head -1)
        if [ -n "$ico_file" ]; then
            log_info "Found icon file: $ico_file"
            cp "$ico_file" claude.ico
        else
            log_warn "No .ico files found. Creating default icon."
            # Create a simple placeholder icon
            echo -e "\x00\x00\x01\x00\x01\x00\x10\x10\x00\x00\x01\x00\x04\x00\x28\x01\x00\x00\x16\x00\x00\x00\x28\x00\x00\x00\x10\x00\x00\x00\x20\x00\x00\x00\x01\x00\x04\x00\x00\x00\x00\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80\x00\x00\x80\x00\x00\x00\x80\x80\x00\x80\x00\x00\x00\x80\x00\x80\x00\x80\x80\x00\x00\xc0\xc0\xc0\x00\x80\x80\x80\x00\x00\x00\xff\x00\x00\xff\x00\x00\x00\xff\xff\x00\xff\x00\x00\x00\xff\x00\xff\x00\xff\xff\x00\x00\xff\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" > claude.ico
        fi
    else
        log_info "Found executable for icon extraction: $claude_exe_path"
        if ! wrestool -x -t 14 "$claude_exe_path" -o claude.ico; then
            log_warn "Failed to extract icons from exe using wrestool, trying alternative methods..."
            # Try to find .ico files directly as fallback
            local ico_file=$(find . -name "*.ico" | head -1)
            if [ -n "$ico_file" ]; then
                log_info "Found icon file: $ico_file"
                cp "$ico_file" claude.ico
            else
                log_warn "No .ico files found. Installation will continue without proper icons."
                # Create an empty icon file to prevent later steps from failing
                echo -e "\x00\x00\x01\x00" > claude.ico
            fi
        fi
    fi
    
    # Make icon conversion more resilient
    if ! icotool -x claude.ico; then
        log_warn "Failed to convert icons with icotool, trying alternate approach..."
        
        # Create basic PNGs for different sizes
        for size in 16 24 32 48 64 256; do
            convert -size ${size}x${size} xc:transparent -fill darkblue -draw "circle $((size/2)),$((size/2)) $((size/2)),$((size-5))" "claude_$((14-size/16))_${size}x${size}x32.png" 2>/dev/null || \
            echo "P3
$size $size
255
" > "claude_$((14-size/16))_${size}x${size}x32.ppm" && \
            for ((i=0; i<size*size; i++)); do 
                echo "128 128 255 "; 
            done >> "claude_$((14-size/16))_${size}x${size}x32.ppm" && \
            convert "claude_$((14-size/16))_${size}x${size}x32.ppm" "claude_$((14-size/16))_${size}x${size}x32.png" 2>/dev/null || true
            
            # If files still don't exist, create empty ones to prevent later failures
            if [ ! -f "claude_$((14-size/16))_${size}x${size}x32.png" ]; then
                log_warn "Failed to create ${size}x${size} icon, using placeholder"
                echo "P3
1 1
255
0 0 255" > "claude_$((14-size/16))_${size}x${size}x32.ppm"
                convert "claude_$((14-size/16))_${size}x${size}x32.ppm" "claude_$((14-size/16))_${size}x${size}x32.png" 2>/dev/null || touch "claude_$((14-size/16))_${size}x${size}x32.png"
            fi
        done
    fi
    log_info "Icons processed"
    
    # Map icon sizes to their corresponding extracted files
    declare -A icon_files=(
        ["16"]="claude_13_16x16x32.png"
        ["24"]="claude_11_24x24x32.png"
        ["32"]="claude_10_32x32x32.png"
        ["48"]="claude_8_48x48x32.png"
        ["64"]="claude_7_64x64x32.png"
        ["256"]="claude_6_256x256x32.png"
    )
    
    # Install icons
    for size in 16 24 32 48 64 256; do
        icon_dir="${INSTALL_DIR}/share/icons/hicolor/${size}x${size}/apps"
        mkdir -p "${icon_dir}"
        if [ -f "${icon_files[$size]}" ]; then
            log_info "Installing ${size}x${size} icon..."
            install -Dm 644 "${icon_files[$size]}" "${icon_dir}/claude-desktop.png"
        else
            log_warn "Missing ${size}x${size} icon"
        fi
    done
    
    # Process app.asar - find the correct paths dynamically
    mkdir -p electron-app
    
    # Find app.asar and app.asar.unpacked dynamically
    local app_asar_path=$(find . -name "app.asar" | grep -v "electron-app" | head -1)
    local app_asar_unpacked_path=$(find . -name "app.asar.unpacked" -type d | grep -v "electron-app" | head -1)
    
    if [ -z "$app_asar_path" ]; then
        log_error "Could not find app.asar file"
        log_info "Searching for any .asar files:"
        find . -name "*.asar" | xargs -I{} log_info "Found: {}"
        rm -rf "${build_dir}"
        return 1
    fi
    
    log_info "Found app.asar at: $app_asar_path"
    cp "$app_asar_path" electron-app/
    
    # Copy app.asar.unpacked if it exists
    if [ -n "$app_asar_unpacked_path" ] && [ -d "$app_asar_unpacked_path" ]; then
        log_info "Found app.asar.unpacked at: $app_asar_unpacked_path"
        cp -r "$app_asar_unpacked_path" electron-app/
    else
        log_warn "app.asar.unpacked directory not found, continuing anyway"
    fi
    
    cd electron-app
    npx asar extract app.asar app.asar.contents
    
    # Replace native module with stub implementation
    log_info "Creating stub native module..."
    cat > app.asar.contents/node_modules/claude-native/index.js << EOF
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
    
    # Copy Tray icons
    mkdir -p app.asar.contents/resources
    mkdir -p app.asar.contents/resources/i18n
    
    cp ../lib/net45/resources/Tray* app.asar.contents/resources/
    cp ../lib/net45/resources/*-*.json app.asar.contents/resources/i18n/
    
    log_info "Creating main window patch..."
    cd app.asar.contents
    
    # Create patch directly instead of downloading
    cat > main.js << 'EOF'
// main_window patch for Claude Desktop Linux
const { app, BrowserWindow, shell, Menu, Tray, nativeImage, ipcMain, globalShortcut, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const os = require('os');
const url = require('url');

// Fix process.env.NODE_ENV for development detection
process.env.NODE_ENV = process.env.NODE_ENV || 'production';

// Check for developer mode
let isDev = false;
try {
  const cfgPath = path.join(app.getPath('userData'), 'developer_settings.json');
  if (fs.existsSync(cfgPath)) {
    const devSettings = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    isDev = !!devSettings.allowDevTools;
  }
} catch (error) {
  console.error('Failed to read developer settings:', error);
}

// Set app name based on instance
if (process.env.CLAUDE_INSTANCE) {
  app.name = `Claude Desktop (${process.env.CLAUDE_INSTANCE})`;
}

// Create a singleton instance through file lock
const gotSingleInstanceLock = !process.env.CLAUDE_INSTANCE && app.requestSingleInstanceLock();
if (!gotSingleInstanceLock && !process.env.CLAUDE_INSTANCE) {
  app.quit();
  process.exit(0);
}

// Configure app behavior
app.on('window-all-closed', () => {
  // Keep app running on macOS when windows close
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

// Prepare main window
let mainWindow = null;

// Handles for renderer preload script
global.handles = {
  getWindowArguments: () => {
    return {
      isDev,
      instanceName: process.env.CLAUDE_INSTANCE || 'default'
    };
  },
  relaunch: () => {
    app.relaunch();
    app.exit(0);
  }
};

function createMainWindow() {
  // Configure Electron Security for Linux compatibility
  app.commandLine.appendSwitch('no-sandbox');
  app.commandLine.appendSwitch('disable-features', 'OutOfBlinkCors');
  app.commandLine.appendSwitch('disable-background-timer-throttling');
  app.commandLine.appendSwitch('disable-renderer-backgrounding');
  app.commandLine.appendSwitch('js-flags', '--expose-gc');
  
  // Fix for swiftshader issues
  app.commandLine.appendSwitch('enable-unsafe-swiftshader');
  app.commandLine.appendSwitch('use-gl', 'desktop');
  app.commandLine.appendSwitch('disable-software-rasterizer');
  app.commandLine.appendSwitch('disable-gpu');
  app.commandLine.appendSwitch('disable-dev-shm-usage');
  
  // Create the browser window
  const windowOptions = {
    width: 1400,
    height: 900,
    minWidth: 800,
    minHeight: 600,
    show: false,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      enableRemoteModule: false,
      preload: path.join(__dirname, 'preload.js'),
      spellcheck: true,
      devTools: isDev,
    },
    // Linux specific settings
    icon: path.join(__dirname, 'resources', 'icon.png'),
    autoHideMenuBar: true,
  };
  
  mainWindow = new BrowserWindow(windowOptions);
  mainWindow.setTitle(`Claude Desktop ${process.env.CLAUDE_INSTANCE ? '[' + process.env.CLAUDE_INSTANCE + ']' : ''}`);
  
  // Load the app
  mainWindow.loadURL('https://claude.ai/');
  
  // Show window when ready
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    
    // Check for dev mode
    try {
      if (isDev) {
        mainWindow.webContents.openDevTools();
        console.log('Developer mode activated - DevTools enabled');
      }
    } catch (err) {
      console.error('Failed to open devtools:', err);
    }
  });
  
  // Open external links in browser
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    // Check if this is a claude.ai URL
    if (url.startsWith('https://claude.ai')) {
      return { action: 'allow' };
    }
    
    // All other URLs open in external browser
    shell.openExternal(url).catch(err => {
      console.error('Failed to open external URL:', url, err);
    });
    return { action: 'deny' };
  });
  
  // Fix for clearing progress bar
  mainWindow.on('focus', () => {
    mainWindow.setProgressBar(-1);
  });
  
  // Handle window close
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
  
  return mainWindow;
}

// Create main window when Electron app is ready
app.whenReady()
  .then(() => {
    createMainWindow();
    
    // Second instance launch handler (focus existing window)
    app.on('second-instance', (event, commandLine, workingDirectory) => {
      if (mainWindow) {
        if (mainWindow.isMinimized()) mainWindow.restore();
        mainWindow.focus();
      }
    });
    
    // Create window if activated and no windows are open (macOS)
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        createMainWindow();
      }
    });
  })
  .catch(err => {
    console.error('Failed to initialize application:', err);
    app.quit();
  });
EOF
    
    # Go back to electron-app directory
    cd ..
    
    # Repackage app.asar
    npx asar pack app.asar.contents app.asar
    
    # Create native module with keyboard constants
    mkdir -p "${INSTALL_DIR}/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native"
    cat > "${INSTALL_DIR}/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native/index.js" << EOF
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
    
    # Copy app files
    cp app.asar "${INSTALL_DIR}/lib/$PACKAGE_NAME/"
    cp -r app.asar.unpacked "${INSTALL_DIR}/lib/$PACKAGE_NAME/"
    
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
Version: $VERSION
Architecture: $ARCHITECTURE
Maintainer: $MAINTAINER
Depends: nodejs, npm, p7zip-full
Description: $DESCRIPTION
 Claude is an AI assistant from Anthropic.
 This package provides the desktop interface for Claude.
 .
 Supported on Debian-based Linux distributions (Debian, Ubuntu, Linux Mint, MX Linux, etc.)
 Requires: nodejs (>= 12.0.0), npm
EOF
    
    # Build .deb package
    log_info "Building .deb package..."
    local DEB_FILE="${WORK_DIR}/claude-desktop_${VERSION}_${ARCHITECTURE}.deb"
    if ! dpkg-deb --build "${DEB_ROOT}" "${DEB_FILE}"; then
        log_error "Failed to build .deb package"
        rm -rf "${build_dir}"
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
Name=Claude (${instance_name})
Comment=Claude Desktop AI Assistant (${instance_name} instance)
Exec=env CLAUDE_INSTANCE=${instance_name} LIBVA_DRIVER_NAME=dummy "\$HOME/.local/bin/claude-desktop" --disable-gpu --no-sandbox --disable-dev-shm-usage --js-flags="--expose-gc" --preload="\$HOME/.config/claude-desktop/preload.js" %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude-${instance_name}
X-CMGR-Instance=${instance_name}
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
    local force_rebuild="${3:-false}"
    
    # Check if cache exists
    local cache_dir="${CMGR_CACHE}"
    local metadata_file="${cache_dir}/metadata.json"
    
    # Ensure cache directory exists
    mkdir -p "${cache_dir}"
    
    # Build Claude Desktop if no cached version exists or force rebuild is true
    if [ ! -f "$metadata_file" ] || [ "$force_rebuild" = "true" ]; then
        if [ "$force_rebuild" = "true" ]; then
            log_info "Force rebuilding Claude Desktop..."
        else
            log_info "No cached Claude Desktop build found. Building now..."
        fi
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
    if ! run_in_sandbox "$sandbox_name" "./install-claude.sh"; then
        log_error "Installation script failed."
        return 1
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
