#!/bin/bash
# fix-apparmor.sh - Apply AppArmor fixes for bubblewrap in Claude Desktop Manager
# This script creates a local AppArmor override to allow bubblewrap to use user namespaces

set -eo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Claude Desktop Manager - AppArmor Fix Utility    ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (with sudo)${NC}"
    echo "Please run: sudo $(basename "$0")"
    exit 1
fi

# Function to check if bubblewrap can create user namespaces
check_bwrap() {
    echo -e "${BLUE}Testing bubblewrap functionality...${NC}"
    if su -c "bwrap --unshare-all --bind / / echo 'Bubblewrap test'" $SUDO_USER &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap is working correctly${NC}"
        return 0
    else
        echo -e "${YELLOW}✗ Bubblewrap cannot create user namespaces${NC}"
        return 1
    fi
}

# Function to check if kernel parameters are set correctly
check_kernel_params() {
    echo -e "${BLUE}Checking kernel parameters...${NC}"
    local unprivileged_userns=$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo "0")
    
    if [ "$unprivileged_userns" = "1" ]; then
        echo -e "${GREEN}✓ kernel.unprivileged_userns_clone is enabled${NC}"
    else
        echo -e "${YELLOW}✗ kernel.unprivileged_userns_clone is not enabled${NC}"
        echo -e "${YELLOW}  This needs to be enabled for bubblewrap to work${NC}"
        echo "Would you like to enable it now? (y/n)"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            echo "kernel.unprivileged_userns_clone = 1" > /etc/sysctl.d/99-userns.conf
            sysctl -p /etc/sysctl.d/99-userns.conf
            echo -e "${GREEN}✓ kernel.unprivileged_userns_clone has been enabled${NC}"
        else
            echo -e "${YELLOW}Warning: Continuing without enabling kernel.unprivileged_userns_clone${NC}"
            echo "You may need to enable it manually with:"
            echo "echo 'kernel.unprivileged_userns_clone = 1' | sudo tee /etc/sysctl.d/99-userns.conf"
            echo "sudo sysctl -p /etc/sysctl.d/99-userns.conf"
        fi
    fi
    
    # Check boot parameters
    if grep -q "namespace.unpriv_enable=1" /proc/cmdline && grep -q "user_namespace.enable=1" /proc/cmdline; then
        echo -e "${GREEN}✓ Boot parameters for user namespaces are set correctly${NC}"
    else
        echo -e "${YELLOW}⚠ Boot parameters for user namespaces might not be set correctly${NC}"
        echo -e "${YELLOW}  The following parameters are recommended in GRUB:${NC}"
        echo -e "${YELLOW}  namespace.unpriv_enable=1 user_namespace.enable=1${NC}"
        echo "This has already been set in your system configuration, but might need a reboot to take effect."
    fi
}

# Function to check AppArmor status
check_apparmor() {
    echo -e "${BLUE}Checking AppArmor status...${NC}"
    if systemctl is-active --quiet apparmor; then
        echo -e "${GREEN}✓ AppArmor is active${NC}"
        
        # Check if unprivileged_userns profile exists
        if [ -f "/etc/apparmor.d/unprivileged_userns" ]; then
            echo -e "${GREEN}✓ Found AppArmor profile for unprivileged_userns${NC}"
            
            # Check if we already have a local override
            if [ -f "/etc/apparmor.d/local/unprivileged_userns" ]; then
                echo -e "${GREEN}✓ Local override for unprivileged_userns already exists${NC}"
                echo "Contents of local override:"
                cat "/etc/apparmor.d/local/unprivileged_userns"
                return 0
            else
                echo -e "${YELLOW}✗ No local override for unprivileged_userns${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}⚠ AppArmor profile for unprivileged_userns not found${NC}"
            echo -e "${YELLOW}  This is unusual for Ubuntu 24.04. AppArmor configuration might be non-standard.${NC}"
            return 2
        fi
    else
        echo -e "${YELLOW}⚠ AppArmor is not active${NC}"
        return 3
    fi
}

# Function to create a backup
create_backup() {
    echo -e "${BLUE}Creating backup of AppArmor configuration...${NC}"
    local backup_dir="/var/backups/cmgr-apparmor-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [ -f "/etc/apparmor.d/unprivileged_userns" ]; then
        cp "/etc/apparmor.d/unprivileged_userns" "$backup_dir/"
        echo -e "${GREEN}✓ Backed up unprivileged_userns profile${NC}"
    fi
    
    if [ -d "/etc/apparmor.d/local" ]; then
        if [ -f "/etc/apparmor.d/local/unprivileged_userns" ]; then
            cp "/etc/apparmor.d/local/unprivileged_userns" "$backup_dir/"
            echo -e "${GREEN}✓ Backed up local override${NC}"
        fi
    fi
    
    # Save metadata about the backup
    echo "Backup created by Claude Desktop Manager AppArmor fix script" > "$backup_dir/BACKUP_INFO"
    echo "Date: $(date)" >> "$backup_dir/BACKUP_INFO"
    echo "User: $SUDO_USER" >> "$backup_dir/BACKUP_INFO"
    
    # Save the backup location to a known file for the revert script
    echo "$backup_dir" > "/var/backups/cmgr-apparmor-latest"
    
    echo -e "${GREEN}✓ Backup created at $backup_dir${NC}"
    return 0
}

# Function to apply AppArmor fix
apply_fix() {
    echo -e "${BLUE}Applying AppArmor fix for bubblewrap...${NC}"
    
    # Create local directory if it doesn't exist
    mkdir -p "/etc/apparmor.d/local"
    
    # Create local override for unprivileged_userns
    cat > "/etc/apparmor.d/local/unprivileged_userns" << EOF
# Local modifications for Claude Desktop Manager to allow bubblewrap to work
# This file allows capabilities needed by bubblewrap for user namespaces
# Created by Claude Desktop Manager AppArmor fix script

# Allow specific capabilities needed by bubblewrap
allow capability setpcap,
allow capability setuid,
allow capability setgid,
allow capability sys_admin,
allow capability net_admin,

# Allow network operations
allow network netlink raw,

# Allow writing to uid_map and gid_map files
allow owner /proc/*/uid_map rw,
allow owner /proc/*/gid_map rw,
allow owner /proc/*/setgroups rw,

# Log that we're using a modified profile
audit allow capability,
EOF
    
    echo -e "${GREEN}✓ Created local override for unprivileged_userns${NC}"
    
    # Reload AppArmor to apply changes
    echo -e "${BLUE}Reloading AppArmor...${NC}"
    if systemctl reload apparmor; then
        echo -e "${GREEN}✓ AppArmor reloaded successfully${NC}"
    else
        echo -e "${RED}✗ Failed to reload AppArmor${NC}"
        echo "Please reload AppArmor manually with: sudo systemctl reload apparmor"
        return 1
    fi
    
    # Create marker file to indicate we've applied the fix
    echo "$(date)" > "/etc/apparmor.d/local/.cmgr-apparmor-fix-applied"
    
    # Allow a moment for changes to take effect
    sleep 2
    
    return 0
}

# Function to validate fix
validate_fix() {
    echo -e "${BLUE}Validating fix...${NC}"
    
    # Try running bubblewrap as the original user
    if su -c "bwrap --unshare-all --bind / / echo 'Bubblewrap test'" $SUDO_USER &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap is now working correctly!${NC}"
        return 0
    else
        echo -e "${RED}✗ Bubblewrap is still not working${NC}"
        echo "There might be additional system configuration needed."
        
        # Check AppArmor logs for clues
        echo -e "${BLUE}Checking AppArmor logs for clues...${NC}"
        if journalctl -k | grep -i "apparmor.*bwrap.*denied" | tail -5; then
            echo -e "${YELLOW}⚠ Found AppArmor denial messages. More permissions might be needed.${NC}"
        else
            echo -e "${YELLOW}No specific AppArmor denial messages found for bubblewrap.${NC}"
        fi
        
        return 1
    fi
}

# Main execution
main() {
    # Banner
    echo -e "${BLUE}Starting AppArmor fix for Claude Desktop Manager${NC}"
    echo -e "${BLUE}---------------------------------------------------${NC}"
    echo "This script will modify AppArmor configuration to allow bubblewrap to create user namespaces."
    echo "These changes are necessary for Claude Desktop Manager's sandboxing functionality."
    echo ""
    
    # Check current status
    check_kernel_params
    check_apparmor
    check_bwrap
    
    echo ""
    echo -e "${YELLOW}This script will modify your AppArmor configuration.${NC}"
    echo -e "${YELLOW}A backup will be created before making any changes.${NC}"
    echo "Do you want to continue? (y/n)"
    read -r response
    
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "${RED}Operation cancelled.${NC}"
        exit 0
    fi
    
    # Create backup
    create_backup
    
    # Apply fix
    apply_fix
    
    # Validate fix
    validate_fix
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}=============================================${NC}"
        echo -e "${GREEN}  AppArmor fix successfully applied!        ${NC}"
        echo -e "${GREEN}  Claude Desktop Manager should now work.    ${NC}"
        echo -e "${GREEN}=============================================${NC}"
        
        echo ""
        echo "If you need to revert these changes, run:"
        echo "sudo $(dirname "$0")/revert-apparmor-changes.sh"
    else
        echo ""
        echo -e "${YELLOW}=============================================${NC}"
        echo -e "${YELLOW}  AppArmor fix applied, but validation failed.${NC}"
        echo -e "${YELLOW}  You might need additional configuration.    ${NC}"
        echo -e "${YELLOW}=============================================${NC}"
        
        echo ""
        echo "Please try the following:"
        echo "1. Reboot your system to ensure all changes take effect"
        echo "2. Check your kernel parameters with 'sysctl kernel.unprivileged_userns_clone'"
        echo "3. If problems persist, consider temporarily disabling AppArmor with:"
        echo "   sudo systemctl stop apparmor"
    fi
    
    echo ""
    echo -e "${BLUE}For help or more information, see the README-APPARMOR.md file.${NC}"
}

# Run main function
main
