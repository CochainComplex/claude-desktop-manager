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
    
    echo -e "${BLUE}Trying multiple approaches to fix AppArmor restrictions:${NC}"
    echo -e "${BLUE}1. Creating comprehensive local override for unprivileged_userns${NC}"
    
    # Create local override for unprivileged_userns
    cat > "/etc/apparmor.d/local/unprivileged_userns" << EOF
# Local modifications for Claude Desktop Manager to allow bubblewrap to work
# This file allows capabilities needed by bubblewrap for user namespaces
# Created by Claude Desktop Manager AppArmor fix script

# Allow full capability access (more permissive but ensures it works)
allow capability,

# Allow all networking
allow network,

# Allow writing to uid_map and gid_map files
allow owner /proc/*/uid_map rw,
allow owner /proc/*/gid_map rw,
allow owner /proc/*/setgroups rw,

# Log that we're using a modified profile
audit allow capability,
EOF
    
    echo -e "${GREEN}✓ Created comprehensive local override for unprivileged_userns${NC}"
    
    echo -e "${BLUE}2. Creating force-complain entry to make profile non-enforcing${NC}"
    # Also put the profile in complain mode which is more permissive
    mkdir -p "/etc/apparmor.d/force-complain"
    if [ ! -e "/etc/apparmor.d/force-complain/unprivileged_userns" ]; then
        ln -s "/etc/apparmor.d/unprivileged_userns" "/etc/apparmor.d/force-complain/"
        echo -e "${GREEN}✓ Added unprivileged_userns to force-complain directory${NC}"
    else
        echo -e "${GREEN}✓ Profile already in complain mode${NC}"
    fi
    
    # Reload AppArmor to apply changes
    echo -e "${BLUE}Reloading AppArmor...${NC}"
    if systemctl reload apparmor; then
        echo -e "${GREEN}✓ AppArmor reloaded successfully${NC}"
    else
        echo -e "${RED}✗ Failed to reload AppArmor${NC}"
        echo "Trying to restart AppArmor instead..."
        if systemctl restart apparmor; then
            echo -e "${GREEN}✓ AppArmor restarted successfully${NC}"
        else
            echo -e "${RED}✗ Failed to restart AppArmor${NC}"
            echo "Please reload or restart AppArmor manually with:"
            echo "sudo systemctl restart apparmor"
            return 1
        fi
    fi
    
    # Verify that profiles were correctly loaded
    echo -e "${BLUE}Verifying AppArmor profile status...${NC}"
    if aa-status | grep -q "unprivileged_userns.*complain"; then
        echo -e "${GREEN}✓ unprivileged_userns profile is now in complain mode${NC}"
    else
        echo -e "${YELLOW}⚠ Could not verify profile status - requires sudo privileges${NC}"
        echo "Run 'sudo aa-status' to verify"
    fi
    
    # For good measure, update kernel parameters as well
    echo -e "${BLUE}Updating kernel parameters for user namespaces...${NC}"
    echo "kernel.unprivileged_userns_clone = 1" > /etc/sysctl.d/99-userns.conf
    sysctl -p /etc/sysctl.d/99-userns.conf
    echo -e "${GREEN}✓ Kernel parameters updated${NC}"
    
    # Create marker file to indicate we've applied the fix
    echo "$(date)" > "/etc/apparmor.d/local/.cmgr-apparmor-fix-applied"
    
    # Allow a moment for changes to take effect
    echo -e "${BLUE}Waiting for changes to take effect...${NC}"
    sleep 3
    
    return 0
}

# Function to validate fix
validate_fix() {
    echo -e "${BLUE}Validating fix...${NC}"
    
    # First try with full isolation
    local full_test_success=false
    echo -e "${BLUE}Testing bubblewrap with full isolation...${NC}"
    if bwrap --unshare-all --bind / / echo 'Bubblewrap test with full isolation' &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap with full isolation is now working!${NC}"
        full_test_success=true
    else
        echo -e "${YELLOW}⚠ Bubblewrap with full isolation still fails${NC}"
        bwrap --unshare-all --bind / / echo 'Test' 2>&1 | head -2
    fi
    
    # Now try with shared network
    echo -e "${BLUE}Testing bubblewrap with shared network...${NC}"
    if bwrap --share-net --unshare-user --unshare-pid --unshare-uts --unshare-ipc --bind / / echo 'Bubblewrap test with shared network' &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap with shared network is working!${NC}"
        
        if [ "$full_test_success" = "false" ]; then
            echo -e "${YELLOW}⚠ NOTE: Only the shared network mode is working${NC}"
            echo -e "${YELLOW}   This is still OK because Claude Desktop Manager${NC}"
            echo -e "${YELLOW}   is configured to use --share-net by default.${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}✗ Bubblewrap with shared network also fails${NC}"
        bwrap --share-net --unshare-user --unshare-pid --unshare-uts --unshare-ipc --bind / / echo 'Test' 2>&1 | head -2
    fi
    
    # Now try a minimal unshare to see what's working
    echo -e "${BLUE}Testing bubblewrap with minimal unshare...${NC}"
    if bwrap --unshare-pid --unshare-ipc --unshare-uts --bind / / echo 'Minimal unshare test' &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap with minimal unshare works${NC}"
        echo -e "${YELLOW}⚠ User namespace still not working, but other isolation is OK${NC}"
        
        # Try to analyze what specific capability is still missing
        echo -e "${BLUE}Checking AppArmor logs for specific denials...${NC}"
        # Trigger a denied operation to capture in logs
        bwrap --unshare-all --bind / / echo 'Test for AppArmor logs' &>/dev/null
        
        # Check recent AppArmor denials
        journalctl -k --since "30 seconds ago" | grep -i "apparmor.*denied" | head -3
        
        echo -e "${YELLOW}\nAdditional AppArmor customization may be needed for your system.${NC}"
        echo -e "${YELLOW}However, Claude Desktop Manager will still work with --share-net.${NC}"
        
        return 1
    else
        echo -e "${RED}✗ Even minimal unshare fails${NC}"
        
        echo -e "\n${RED}AppArmor fix did not fully resolve the issue.${NC}"
        echo -e "${YELLOW}Potential solutions:${NC}"
        echo "1. Reboot your system to ensure all changes take effect"
        echo "2. Try temporarily disabling AppArmor with: sudo systemctl stop apparmor"
        echo "3. Verify kernel parameters: sysctl kernel.unprivileged_userns_clone"
        
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
    local validation_result=$?
    
    if [ $validation_result -eq 0 ]; then
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
        echo -e "${YELLOW}  Standard fix was applied, but additional steps may be needed.${NC}"
        echo -e "${YELLOW}=============================================${NC}"
        
        echo -e "\n${BLUE}Would you like to try more aggressive fixes? (y/n)${NC}"
        read -r aggressive_response
        
        if [[ "$aggressive_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            echo -e "${BLUE}Applying more aggressive AppArmor modifications...${NC}"
            
            echo -e "${BLUE}1. Putting AppArmor in complain mode...${NC}"
            if command -v aa-complain &>/dev/null; then
                aa-complain /etc/apparmor.d/unprivileged_userns || echo -e "${YELLOW}Failed to set complain mode with aa-complain${NC}"
            fi
            
            echo -e "${BLUE}2. Temporarily disabling AppArmor...${NC}"
            echo -e "${YELLOW}NOTE: This is temporary and will be reverted on reboot${NC}"
            echo "Do you want to temporarily disable AppArmor? (y/n)"
            read -r disable_response
            
            if [[ "$disable_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                systemctl stop apparmor
                echo -e "${GREEN}AppArmor temporarily stopped${NC}"
                echo "AppArmor will be re-enabled on system reboot."
            fi
            
            echo -e "${BLUE}Testing bubblewrap after aggressive changes...${NC}"
            if bwrap --share-net --unshare-user --unshare-pid --unshare-uts --unshare-ipc --bind / / echo 'Final test' &>/dev/null; then
                echo -e "${GREEN}Success! Bubblewrap is now working with shared network.${NC}"
                echo "Claude Desktop Manager should now function correctly."
            else
                echo -e "${RED}Still unable to get bubblewrap working.${NC}"
                echo "A system reboot may be required for changes to take effect."
                echo "After rebooting, try using Claude Desktop Manager again."
            fi
        else
            echo ""
            echo "As a last resort, you can try the following:"
            echo "1. Reboot your system to ensure all changes take effect"
            echo "2. Temporarily disable AppArmor with: sudo systemctl stop apparmor"
        fi
    fi
    
    echo ""
    echo -e "${BLUE}For help or more information, see the README-APPARMOR.md file.${NC}"
}

# Run main function
main
