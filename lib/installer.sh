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
    
    # Copy scripts to sandbox
    mkdir -p "${sandbox_home}/.config/claude-desktop"
    mkdir -p "${sandbox_home}/.config/Claude/electron"
    
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
    
    if ! cp -f "$package_path" "${sandbox_home}/Downloads/"; then
        log_error "Failed to copy package to sandbox."
        return 1
    fi
    
    # Install the package in the sandbox
    local install_success=false
    if [ "$build_format" = "deb" ]; then
        # Extract the .deb package in the sandbox instead of using dpkg
        if run_in_sandbox "$sandbox_name" bash -c "cd $HOME && \
            ar x $HOME/Downloads/$(basename "$package_path") && \
            # Support multiple compression formats (xz, gz, zst, uncompressed)
            if [ -f data.tar.xz ]; then 
                tar xf data.tar.xz
            elif [ -f data.tar.gz ]; then 
                tar xf data.tar.gz
            elif [ -f data.tar.zst ]; then 
                tar --use-compress-program=unzstd -xf data.tar.zst
            elif [ -f data.tar ]; then 
                tar xf data.tar
            else
                # If no recognized format, try to find any data archive
                for data_file in \$(find . -name 'data.tar*'); do
                    case \$data_file in
                        *.xz)  tar xf \$data_file ;;
                        *.gz)  tar xf \$data_file ;;
                        *.zst) tar --use-compress-program=unzstd -xf \$data_file ;;
                        *)     tar xf \$data_file ;;
                    esac
                    break
                done
            fi && \
            # Clean up archive files
            rm -f data.tar* control.tar* debian-binary && \
            mkdir -p $HOME/.local/bin && \
            # Copy the executable
            if [ -f usr/bin/claude-desktop ]; then
                cp -r usr/bin/claude-desktop $HOME/.local/bin/
            else
                # If not in the standard location, try to find it
                executable=\$(find . -type f -name 'claude-desktop' | head -1)
                if [ -n \"\$executable\" ]; then
                    mkdir -p \$(dirname \"$HOME/.local/bin/claude-desktop\")
                    cp \$executable $HOME/.local/bin/
                else
                    echo 'Error: Claude Desktop executable not found'
                    exit 1
                fi
            fi"; then
            # Create desktop entry file in the sandbox
            run_in_sandbox "$sandbox_name" bash -c "mkdir -p $HOME/.local/share/applications && cat > $HOME/.local/share/applications/claude-desktop.desktop << EOF
[Desktop Entry]
Name=Claude Desktop ($sandbox_name)
Comment=Claude Desktop AI Assistant ($sandbox_name instance)
Exec=env CLAUDE_INSTANCE=$sandbox_name LIBVA_DRIVER_NAME=dummy $HOME/.local/bin/claude-desktop --disable-gpu --no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader --js-flags=\"--expose-gc\" --preload=$HOME/.config/claude-desktop/preload.js %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude-$sandbox_name
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
Name=Claude Desktop ($sandbox_name)
Comment=Claude Desktop AI Assistant ($sandbox_name instance)
Exec=env CLAUDE_INSTANCE=$sandbox_name LIBVA_DRIVER_NAME=dummy ${appimage_file} --disable-gpu --no-sandbox --disable-dev-shm-usage --enable-unsafe-swiftshader --js-flags=\"--expose-gc\" --preload=$HOME/.config/claude-desktop/preload.js %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude-$sandbox_name
EOF"; then
                install_success=true
            fi
        fi
    fi
    
    if [ "$install_success" = "true" ]; then
        log_info "Claude Desktop installed successfully in sandbox '${sandbox_name}'!"
        
        # Apply instance customization and MaxListenersExceededWarning fix
        log_info "Applying instance customization and MaxListenersExceededWarning fix..."
        
        # Ensure patch-app.js is in the sandbox
        sandbox_script="${sandbox_home}/.config/claude-desktop/patch-app.js"
        if [ ! -f "$sandbox_script" ]; then
            mkdir -p "$(dirname "$sandbox_script")"
            
            # Use absolute path for script
            local patcher_script="/home/awarth/Devstuff/claude-desktop-manager/scripts/patch-app.js"
            
            # Check if file exists before copying
            if [ -f "$patcher_script" ]; then
                cp -f "$patcher_script" "$sandbox_script" || \
                log_warn "Failed to copy patch-app.js to sandbox"
            else
                # Create the script directly in the sandbox (inline)
                cat > "$sandbox_script" << 'PATCHSCRIPT'
// patch-app.js - Applies patches to Claude Desktop app.asar during installation
// Used by Claude Desktop Manager to customize instance name and fix warnings

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Get instance name and asar path from arguments
const instanceName = process.argv[2] || 'default';
const asarPath = process.argv[3];

if (!asarPath || !fs.existsSync(asarPath)) {
  console.error(`Error: app.asar not found at ${asarPath}`);
  process.exit(1);
}

console.log(`Patching app.asar for instance: ${instanceName}`);
console.log(`ASAR path: ${asarPath}`);

// Create extraction directory
const extractDir = `${asarPath}-extracted`;
if (fs.existsSync(extractDir)) {
  console.log(`Removing existing extraction directory: ${extractDir}`);
  fs.rmSync(extractDir, { recursive: true, force: true });
}

fs.mkdirSync(extractDir, { recursive: true });

// Extract app.asar
try {
  console.log(`Extracting app.asar to: ${extractDir}`);
  execSync(`npx asar extract "${asarPath}" "${extractDir}"`);
} catch (error) {
  console.error(`Error extracting asar file: ${error.message}`);
  process.exit(1);
}

// Find main process files
const findMainProcessFiles = (dir) => {
  let results = [];
  
  try {
    const files = fs.readdirSync(dir);
    
    for (const file of files) {
      const filePath = path.join(dir, file);
      const stat = fs.lstatSync(filePath);
      
      if (stat.isDirectory()) {
        results = results.concat(findMainProcessFiles(filePath));
      } else if (
        file === 'main.js' || 
        file === 'electron.js' || 
        file === 'background.js' ||
        file === 'app.js'
      ) {
        console.log(`Found potential main process file: ${filePath}`);
        results.push(filePath);
      }
    }
  } catch (error) {
    console.error(`Error searching directory ${dir}:`, error);
  }
  
  return results;
};

const mainProcessFiles = findMainProcessFiles(extractDir);

if (mainProcessFiles.length === 0) {
  console.log(`No main process files found in ${extractDir}`);
  process.exit(1);
}

// Update package.json if it exists
try {
  const packageJsonPath = path.join(extractDir, 'package.json');
  if (fs.existsSync(packageJsonPath)) {
    console.log(`Updating package.json...`);
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    
    // Update app name with instance name
    if (packageJson.name) {
      packageJson.name = `claude-desktop-${instanceName}`;
    }
    
    // Update product name with instance name
    if (packageJson.productName) {
      packageJson.productName = `Claude (${instanceName})`;
    }
    
    // Write back updated package.json
    fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2));
    console.log(`Updated package.json with instance name: ${instanceName}`);
  }
} catch (error) {
  console.error(`Error updating package.json: ${error.message}`);
  // Continue even if package.json update fails
}

// Patch main process files
let patchedFiles = 0;
for (const filePath of mainProcessFiles) {
  try {
    console.log(`Patching file: ${filePath}`);
    
    // Backup the original file
    fs.copyFileSync(filePath, `${filePath}.bak`);
    
    // Read file content
    let content = fs.readFileSync(filePath, 'utf8');
    
    // Check if file already patched
    if (content.includes('// CMGR: Instance name customization') || 
        content.includes('// CMGR: MaxListenersExceededWarning fix')) {
      console.log(`File ${filePath} already patched. Skipping.`);
      continue;
    }
    
    // Create patch - simple and focused on the essential functionality
    const patch = `
// CMGR: MaxListenersExceededWarning fix
// CMGR: Instance name customization for ${instanceName}

// Fix EventEmitter memory leak warnings
const events = require('events');
events.EventEmitter.defaultMaxListeners = 30;

// Patch require to customize BrowserWindow titles
const originalModule = require('module');
const originalRequire = originalModule.prototype.require;

originalModule.prototype.require = function(path) {
  const result = originalRequire.apply(this, arguments);
  
  if (path === 'electron') {
    const electron = result;
    
    // Patch app for WebContents
    if (electron.app) {
      // Increase listeners for app
      if (electron.app.setMaxListeners) {
        electron.app.setMaxListeners(30);
      }
      
      // Patch WebContents when created
      electron.app.on('web-contents-created', (event, contents) => {
        if (contents.setMaxListeners) {
          contents.setMaxListeners(30);
        }
      });
    }
    
    // Customize BrowserWindow for instance name
    const originalBrowserWindow = electron.BrowserWindow;
    class CustomBrowserWindow extends originalBrowserWindow {
      constructor(options = {}) {
        // Add instance name to title
        if (options.title) {
          options.title = \`\${options.title} (${instanceName})\`;
        } else {
          options.title = \`Claude (${instanceName})\`;
        }
        
        // Call original constructor with modified options
        super(options);
        
        // Override setTitle to always include instance name
        const originalSetTitle = this.setTitle;
        this.setTitle = (title) => {
          if (!title.includes('(${instanceName})')) {
            return originalSetTitle.call(this, \`\${title} (${instanceName})\`);
          }
          return originalSetTitle.call(this, title);
        };
        
        // Increase max listeners
        if (this.setMaxListeners) {
          this.setMaxListeners(30);
        }
      }
    }
    
    // Replace BrowserWindow with our custom version
    electron.BrowserWindow = CustomBrowserWindow;
    
    return electron;
  }
  
  return result;
};

`;
    
    // Add the patch at the beginning of the file
    content = patch + content;
    
    // Write the modified content back to the file
    fs.writeFileSync(filePath, content);
    console.log(`Successfully patched ${filePath}`);
    patchedFiles++;
    
  } catch (error) {
    console.error(`Error patching file ${filePath}: ${error.message}`);
    // Continue with other files even if one fails
  }
}

if (patchedFiles === 0) {
  console.error('No files were patched. The installation customization failed.');
  process.exit(1);
}

// Repack the asar file
try {
  console.log(`Repacking app.asar...`);
  
  // Create backup of original asar if it doesn't exist
  const backupFile = `${asarPath}.original`;
  if (!fs.existsSync(backupFile)) {
    fs.copyFileSync(asarPath, backupFile);
    console.log(`Created backup of original asar: ${backupFile}`);
  }
  
  // Pack the modified files back into app.asar
  execSync(`npx asar pack "${extractDir}" "${asarPath}"`);
  console.log(`Successfully repacked app.asar`);
  
  // Clean up extraction directory
  fs.rmSync(extractDir, { recursive: true, force: true });
  console.log(`Removed extraction directory`);
  
  console.log(`Patching completed successfully!`);
} catch (error) {
  console.error(`Error repacking asar file: ${error.message}`);
  process.exit(1);
}
PATCHSCRIPT
                chmod +x "$sandbox_script"
                log_info "Created patch-app.js directly in sandbox"
            fi
        fi
        
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
            
            # Find app.asar files
            APP_DIRS=(~/.local/share/claude-desktop ~/.local/lib/claude-desktop /usr/lib/claude-desktop ~/.local/bin)
            
            for dir in \"\${APP_DIRS[@]}\"; do
                if [ -d \"\$dir\" ]; then
                    ASAR_FILE=\$(find \"\$dir\" -name 'app.asar' | head -1)
                    if [ -n \"\$ASAR_FILE\" ]; then
                        echo \"Found app.asar at \$ASAR_FILE\"
                        
                        # Run the patcher script with instance name and asar path
                        echo \"Patching app.asar for instance '$sandbox_name'...\"
                        node ~/.config/claude-desktop/patch-app.js \"$sandbox_name\" \"\$ASAR_FILE\"
                        break
                    fi
                fi
            done
            
            # If no ASAR found in standard locations, do a system-wide search
            if [ -z \"\$ASAR_FILE\" ]; then
                echo \"Searching for app.asar in various locations...\"
                ASAR_FILE=\$(find ~/.local -name 'app.asar' | grep -i claude | head -1)
                
                if [ -n \"\$ASAR_FILE\" ]; then
                    echo \"Found app.asar at \$ASAR_FILE\"
                    node ~/.config/claude-desktop/patch-app.js \"$sandbox_name\" \"\$ASAR_FILE\"
                else
                    echo \"Could not find app.asar, skipping patching\"
                fi
            fi
            
            echo 'Installation and patching completed!'
        " || log_warn "Failed to apply patches to app.asar, but installation completed."
        
        return 0
    else
        log_error "Failed to install Claude Desktop in sandbox."
        return 1
    fi
}
