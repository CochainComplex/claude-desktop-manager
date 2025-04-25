#!/bin/bash
# patches.sh - System patch application functions for Claude Desktop Manager

# Apply system patches - to be run with elevated privileges
apply_system_patches() {
    local logs_dir="${CMGR_HOME}/logs"
    local temp_dir="${CMGR_HOME}/temp"
    
    # Create log file with timestamp
    mkdir -p "$logs_dir"
    local log_file="${logs_dir}/system-patches-$(date '+%Y%m%d-%H%M%S').log"
    touch "$log_file"
    
    # Make sure the log directory is writable by the original user
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown "${SUDO_USER}:$(id -gn "${SUDO_USER}")" "$log_file" 2>/dev/null || true
    fi
    
    # Log function
    local_log() {
        local level="$1"
        local message="$2"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [$level] $message" | tee -a "$log_file"
    }
    
    local_log_info() { local_log "INFO" "$1"; }
    local_log_error() { local_log "ERROR" "$1"; }
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        local_log_error "This command must be run as root (with sudo)"
        echo "Please run: sudo $(basename "$0") apply-patches"
        return 1
    fi
    
    # Find all pending patch files
    local_log_info "Searching for pending patch files in ${temp_dir}"
    
    # Check if temp directory exists
    if [ ! -d "$temp_dir" ]; then
        local_log_error "Temp directory not found: $temp_dir"
        return 1
    fi
    
    # Find all patched asar files
    local patched_files=$(find "$temp_dir" -name "patched-*.asar" -type f 2>/dev/null)
    
    if [ -z "$patched_files" ]; then
        local_log_info "No pending patches found."
        return 0
    fi
    
    # Process each patched file
    for patched_file in $patched_files; do
        local instance_name=$(basename "$patched_file" | sed -E 's/patched-(.+)\.asar/\1/')
        local_log_info "Found patch for instance: $instance_name"
        
        # Check if there's a corresponding system path info file
        local path_info_file="${temp_dir}/system-path-${instance_name}.txt"
        
        if [ -f "$path_info_file" ]; then
            local system_path=$(cat "$path_info_file")
            local_log_info "Target system path: $system_path"
            
            # Make sure system_path exists and is an app.asar file
            if [ -f "$system_path" ] && [[ "$system_path" == *.asar ]]; then
                local_log_info "Applying patch to $system_path"
                
                # Backup original if not already backed up
                local backup_file="${system_path}.original"
                if [ ! -f "$backup_file" ]; then
                    local_log_info "Creating backup: $backup_file"
                    cp "$system_path" "$backup_file"
                fi
                
                # Apply the patch
                cp "$patched_file" "$system_path"
                chmod --reference="$backup_file" "$system_path"
                chown --reference="$backup_file" "$system_path"
                
                local_log_info "✓ Successfully applied patch for instance: $instance_name"
                
                # Move processed files to done directory
                mkdir -p "${temp_dir}/done"
                mv "$patched_file" "${temp_dir}/done/"
                mv "$path_info_file" "${temp_dir}/done/"
            else
                local_log_error "System path does not exist or is not a valid asar file: $system_path"
            fi
        else
            local_log_info "No system path information found for: $instance_name"
            # Try to guess the system path
            local potential_paths=(
                "/usr/lib/claude-desktop/app.asar"
                "/usr/share/claude-desktop/app.asar"
                "/opt/claude-desktop/app.asar"
            )
            
            for path in "${potential_paths[@]}"; do
                if [ -f "$path" ]; then
                    local_log_info "Found potential system path: $path"
                    
                    # Ask for confirmation
                    echo -n "Apply patch to $path? (y/n): "
                    read -r response
                    
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        local_log_info "Applying patch to $path"
                        
                        # Backup original if not already backed up
                        local backup_file="${path}.original"
                        if [ ! -f "$backup_file" ]; then
                            local_log_info "Creating backup: $backup_file"
                            cp "$path" "$backup_file"
                        fi
                        
                        # Apply the patch
                        cp "$patched_file" "$path"
                        chmod --reference="$backup_file" "$path"
                        chown --reference="$backup_file" "$path"
                        
                        local_log_info "✓ Successfully applied patch for instance: $instance_name"
                        
                        # Create path info file for future reference
                        echo "$path" > "$path_info_file"
                        
                        # Move processed files to done directory
                        mkdir -p "${temp_dir}/done"
                        mv "$patched_file" "${temp_dir}/done/"
                        break
                    fi
                fi
            done
        fi
    done
    
    local_log_info "Patch application completed."
    local_log_info "Log file: $log_file"
    return 0
}
