#!/bin/bash
# fix-apparmor.sh - Apply fixes for bubblewrap on Ubuntu 24.04
# This script disables AppArmor restrictions on unprivileged user namespaces

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

# Test bubblewrap
check_bwrap() {
    echo -e "${BLUE}Testing bubblewrap functionality...${NC}"
    if bwrap --share-net --unshare-user --unshare-pid --bind / / echo 'Test' &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap is already working correctly!${NC}"
        return 0
    else
        echo -e "${YELLOW}✗ Bubblewrap cannot create user namespaces${NC}"
        # Get error details
        echo -e "${BLUE}Error details:${NC}"
        bwrap --share-net --unshare-user --unshare-pid --bind / / echo 'Test' 2>&1 | head -2
        return 1
    fi
}

# Create a backup
create_backup() {
    echo -e "${BLUE}Creating backup of current system settings...${NC}"
    local backup_dir="/var/backups/cmgr-apparmor-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup kernel parameters
    sysctl kernel.apparmor_restrict_unprivileged_userns 2>/dev/null > "$backup_dir/apparmor_restrict_unprivileged_userns" || true
    sysctl kernel.unprivileged_userns_clone 2>/dev/null > "$backup_dir/unprivileged_userns_clone" || true
    
    # Backup existing config files
    if [ -f "/etc/sysctl.d/60-cmgr-apparmor-namespace.conf" ]; then
        cp "/etc/sysctl.d/60-cmgr-apparmor-namespace.conf" "$backup_dir/"
    fi
    
    # Save metadata
    echo "Backup created by Claude Desktop Manager AppArmor fix script" > "$backup_dir/BACKUP_INFO"
    echo "Date: $(date)" >> "$backup_dir/BACKUP_INFO"
    echo "User: $SUDO_USER" >> "$backup_dir/BACKUP_INFO"
    
    # Save backup location for revert script
    echo "$backup_dir" > "/var/backups/cmgr-apparmor-latest"
    
    echo -e "${GREEN}✓ Backup created at $backup_dir${NC}"
    return 0
}

# Apply the fix
apply_fix() {
    echo -e "${BLUE}Applying fix for unprivileged user namespaces...${NC}"
    
    # Check for Ubuntu 24.04
    if [ -f "/etc/os-release" ] && grep -q "VERSION=\"24.04" "/etc/os-release"; then
        echo -e "${YELLOW}⚠ Detected Ubuntu 24.04${NC}"
        echo -e "${BLUE}Disabling AppArmor restrictions on unprivileged user namespaces...${NC}"
        
        # Create sysctl override
        cat > "/etc/sysctl.d/60-cmgr-apparmor-namespace.conf" << EOF
# Claude Desktop Manager - AppArmor user namespace restriction override
kernel.apparmor_restrict_unprivileged_userns = 0
EOF
        
        # Apply sysctl setting immediately
        if sysctl -p /etc/sysctl.d/60-cmgr-apparmor-namespace.conf; then
            echo -e "${GREEN}✓ Successfully disabled AppArmor restrictions on unprivileged user namespaces${NC}"
        else
            echo -e "${RED}✗ Failed to apply sysctl settings${NC}"
            return 1
        fi
    fi
    
    # Ensure unprivileged user namespaces are enabled
    echo -e "${BLUE}Ensuring unprivileged user namespaces are enabled...${NC}"
    echo "kernel.unprivileged_userns_clone = 1" > /etc/sysctl.d/99-userns.conf
    sysctl -p /etc/sysctl.d/99-userns.conf
    echo -e "${GREEN}✓ Unprivileged user namespaces enabled${NC}"
    
    # Create marker file
    echo "$(date)" > "/etc/apparmor.d/local/.cmgr-apparmor-fix-applied"
    
    return 0
}

# Validate the fix
validate_fix() {
    echo -e "${BLUE}Validating fix...${NC}"
    
    # Allow a moment for changes to take effect
    sleep 2
    
    # Test with shared network (used by Claude Desktop Manager)
    echo -e "${BLUE}Testing bubblewrap with shared network...${NC}"
    if bwrap --share-net --unshare-user --unshare-pid --unshare-uts --unshare-ipc --bind / / echo 'Test' &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap with shared network is working!${NC}"
        return 0
    else
        echo -e "${RED}✗ Bubblewrap with shared network still fails${NC}"
        echo -e "${BLUE}Error details:${NC}"
        bwrap --share-net --unshare-user --unshare-pid --unshare-uts --unshare-ipc --bind / / echo 'Test' 2>&1 | head -2
        
        # Check AppArmor logs
        echo -e "${BLUE}Checking AppArmor logs for denials...${NC}"
        journalctl -k --since "30 seconds ago" | grep -i "apparmor.*denied" | head -3
        
        return 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Starting fix for Claude Desktop Manager sandboxing${NC}"
    echo -e "${BLUE}---------------------------------------------------${NC}"
    echo "This script will modify system settings to allow bubblewrap to create user namespaces."
    echo "These changes are necessary for Claude Desktop Manager's sandboxing functionality."
    echo ""
    
    # Check if bubblewrap already works
    if check_bwrap; then
        echo ""
        echo -e "${GREEN}Bubblewrap is already working correctly!${NC}"
        echo -e "${GREEN}No changes needed.${NC}"
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}This script will modify your system settings.${NC}"
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
        echo -e "${GREEN}  Fix successfully applied!                  ${NC}"
        echo -e "${GREEN}  Claude Desktop Manager should now work.    ${NC}"
        echo -e "${GREEN}=============================================${NC}"
        
        echo ""
        echo "If you need to revert these changes, run:"
        echo "sudo $(dirname "$0")/revert-apparmor-changes.sh"
    else
        echo ""
        echo -e "${YELLOW}=============================================${NC}"
        echo -e "${YELLOW}  Fix was applied, but bubblewrap still fails.${NC}"
        echo -e "${YELLOW}=============================================${NC}"
        
        echo -e "\n${YELLOW}Recommended actions:${NC}"
        echo "1. Reboot your system to ensure all changes take effect"
        echo "2. Check for system updates that might fix this issue"
        echo "   sudo apt update && sudo apt upgrade"
        echo ""
    fi
}

# Run main function
main
