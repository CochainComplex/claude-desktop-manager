#!/bin/bash
# apply-system-patches.sh - Apply Claude Desktop Manager patches to system locations
# This script should be run with sudo when the app.asar is in a system location

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (with sudo)"
    echo "Please run: sudo $0"
    exit 1
fi

# Get the original user who ran sudo
ORIGINAL_USER="${SUDO_USER:-$(logname)}"
ORIGINAL_HOME=$(eval echo ~${ORIGINAL_USER})
TEMP_DIR="${ORIGINAL_HOME}/.cmgr/temp"
LOGS_DIR="${ORIGINAL_HOME}/.cmgr/logs"

# Create log file
mkdir -p "$LOGS_DIR"
LOG_FILE="${LOGS_DIR}/system-patches-$(date '+%Y%m%d-%H%M%S').log"
touch "$LOG_FILE"
chown "$ORIGINAL_USER:$(id -gn "$ORIGINAL_USER")" "$LOG_FILE"

# Log function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_error() { log "ERROR" "$1"; }

# Find all pending patch files
log_info "Searching for pending patch files in ${TEMP_DIR}"

# Check if temp directory exists
if [ ! -d "$TEMP_DIR" ]; then
    log_error "Temp directory not found: $TEMP_DIR"
    exit 1
fi

# Find all patched asar files
PATCHED_FILES=$(find "$TEMP_DIR" -name "patched-*.asar" -type f 2>/dev/null)

if [ -z "$PATCHED_FILES" ]; then
    log_info "No pending patches found."
    exit 0
fi

# Process each patched file
for patched_file in $PATCHED_FILES; do
    instance_name=$(basename "$patched_file" | sed -E 's/patched-(.+)\.asar/\1/')
    log_info "Found patch for instance: $instance_name"
    
    # Check if there's a corresponding system path info file
    path_info_file="${TEMP_DIR}/system-path-${instance_name}.txt"
    
    if [ -f "$path_info_file" ]; then
        system_path=$(cat "$path_info_file")
        log_info "Target system path: $system_path"
        
        # Make sure system_path exists and is an app.asar file
        if [ -f "$system_path" ] && [[ "$system_path" == *.asar ]]; then
            log_info "Applying patch to $system_path"
            
            # Backup original if not already backed up
            backup_file="${system_path}.original"
            if [ ! -f "$backup_file" ]; then
                log_info "Creating backup: $backup_file"
                cp "$system_path" "$backup_file"
            fi
            
            # Apply the patch
            cp "$patched_file" "$system_path"
            chmod --reference="$backup_file" "$system_path"
            chown --reference="$backup_file" "$system_path"
            
            log_info "✓ Successfully applied patch for instance: $instance_name"
            
            # Move processed files to done directory
            mkdir -p "${TEMP_DIR}/done"
            mv "$patched_file" "${TEMP_DIR}/done/"
            mv "$path_info_file" "${TEMP_DIR}/done/"
        else
            log_error "System path does not exist or is not a valid asar file: $system_path"
        fi
    else
        log_info "No system path information found for: $instance_name"
        # Try to guess the system path
        potential_paths=(
            "/usr/lib/claude-desktop/app.asar"
            "/usr/share/claude-desktop/app.asar"
            "/opt/claude-desktop/app.asar"
        )
        
        for path in "${potential_paths[@]}"; do
            if [ -f "$path" ]; then
                log_info "Found potential system path: $path"
                
                # Ask for confirmation
                echo -n "Apply patch to $path? (y/n): "
                read -r response
                
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    log_info "Applying patch to $path"
                    
                    # Backup original if not already backed up
                    backup_file="${path}.original"
                    if [ ! -f "$backup_file" ]; then
                        log_info "Creating backup: $backup_file"
                        cp "$path" "$backup_file"
                    fi
                    
                    # Apply the patch
                    cp "$patched_file" "$path"
                    chmod --reference="$backup_file" "$path"
                    chown --reference="$backup_file" "$path"
                    
                    log_info "✓ Successfully applied patch for instance: $instance_name"
                    
                    # Create path info file for future reference
                    echo "$path" > "$path_info_file"
                    
                    # Move processed files to done directory
                    mkdir -p "${TEMP_DIR}/done"
                    mv "$patched_file" "${TEMP_DIR}/done/"
                    break
                fi
            fi
        done
    fi
done

log_info "Patch application completed."
log_info "Log file: $LOG_FILE"
