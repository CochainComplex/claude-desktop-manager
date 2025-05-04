#!/bin/bash
# revert-apparmor-changes.sh - Revert system changes made by fix-apparmor.sh

set -eo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Claude Desktop Manager - Change Revert Utility   ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (with sudo)${NC}"
    echo "Please run: sudo $(basename "$0")"
    exit 1
fi

# Check if our changes are active
check_if_applied() {
    echo -e "${BLUE}Checking if changes are applied...${NC}"
    
    if [ -f "/etc/sysctl.d/60-cmgr-apparmor-namespace.conf" ]; then
        echo -e "${GREEN}✓ Found sysctl override created by Claude Desktop Manager${NC}"
        return 0
    elif [ -f "/etc/apparmor.d/local/.cmgr-apparmor-fix-applied" ]; then
        echo -e "${GREEN}✓ Found marker file indicating changes were applied${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ No changes appear to be applied${NC}"
        echo -e "${YELLOW}  System may already be in its original state${NC}"
        return 1
    fi
}

# Find the latest backup
find_backup() {
    echo -e "${BLUE}Looking for backup...${NC}"
    
    if [ -f "/var/backups/cmgr-apparmor-latest" ]; then
        BACKUP_DIR=$(cat "/var/backups/cmgr-apparmor-latest")
        if [ -d "$BACKUP_DIR" ]; then
            echo -e "${GREEN}✓ Found backup at $BACKUP_DIR${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Backup directory $BACKUP_DIR not found${NC}"
        fi
    fi
    
    # Try to find latest backup
    local latest_backup=$(find /var/backups -maxdepth 1 -name "cmgr-apparmor-*" -type d -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$latest_backup" ] && [ -d "$latest_backup" ]; then
        BACKUP_DIR="$latest_backup"
        echo -e "${GREEN}✓ Found latest backup at $BACKUP_DIR${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ No backup found${NC}"
        echo -e "${YELLOW}  Will proceed with clean removal of changes${NC}"
        BACKUP_DIR=""
        return 1
    fi
}

# Revert changes
revert_changes() {
    echo -e "${BLUE}Reverting system changes...${NC}"
    
    # Remove the sysctl override for AppArmor user namespace restrictions
    if [ -f "/etc/sysctl.d/60-cmgr-apparmor-namespace.conf" ]; then
        rm -f "/etc/sysctl.d/60-cmgr-apparmor-namespace.conf"
        echo -e "${GREEN}✓ Removed sysctl override for AppArmor user namespace restrictions${NC}"
        
        # Apply system sysctl settings to restore defaults
        echo -e "${BLUE}Restoring default sysctl settings...${NC}"
        sysctl --system
    fi
    
    # Remove kernel parameter config if requested
    if [ -f "/etc/sysctl.d/99-userns.conf" ] && grep -q "unprivileged_userns_clone" "/etc/sysctl.d/99-userns.conf"; then
        echo -e "${BLUE}Found unprivileged user namespaces configuration file.${NC}"
        echo -e "${YELLOW}Do you want to remove it and restore default kernel parameters? (y/n)${NC}"
        read -r kernel_response
        if [[ "$kernel_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            rm -f "/etc/sysctl.d/99-userns.conf"
            echo -e "${GREEN}✓ Removed kernel parameter configuration${NC}"
            sysctl --system
        else
            echo -e "${YELLOW}Keeping kernel parameter configuration${NC}"
        fi
    fi
    
    # Clean up any remaining AppArmor changes
    if [ -f "/etc/apparmor.d/local/.cmgr-apparmor-fix-applied" ]; then
        rm -f "/etc/apparmor.d/local/.cmgr-apparmor-fix-applied"
        echo -e "${GREEN}✓ Removed marker file${NC}"
    fi
    
    # Restore from backup if available
    if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/apparmor_restrict_unprivileged_userns" ]; then
        echo -e "${BLUE}Restoring AppArmor restrictions from backup...${NC}"
        local restriction_value=$(grep -o "[01]" "$BACKUP_DIR/apparmor_restrict_unprivileged_userns" || echo "1")
        echo "kernel.apparmor_restrict_unprivileged_userns = $restriction_value" | sysctl -p -
        echo -e "${GREEN}✓ Restored original AppArmor restriction value: $restriction_value${NC}"
    else
        echo -e "${BLUE}Re-enabling default AppArmor restrictions...${NC}"
        echo "kernel.apparmor_restrict_unprivileged_userns = 1" | sysctl -p -
        echo -e "${GREEN}✓ Reset AppArmor restrictions to default (enabled)${NC}"
    fi
    
    return 0
}

# Validate the revert
validate_revert() {
    echo -e "${BLUE}Validating revert...${NC}"
    sleep 2
    
    # Check if sysctl override is gone
    if [ -f "/etc/sysctl.d/60-cmgr-apparmor-namespace.conf" ]; then
        echo -e "${RED}✗ sysctl override still exists${NC}"
        return 1
    else
        echo -e "${GREEN}✓ sysctl override successfully removed${NC}"
    fi
    
    # Check if AppArmor restrictions are restored
    local current_restriction=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo "unknown")
    if [ "$current_restriction" = "1" ]; then
        echo -e "${GREEN}✓ AppArmor restrictions have been restored${NC}"
    else
        echo -e "${YELLOW}⚠ AppArmor restrictions are still disabled (value: $current_restriction)${NC}"
        echo -e "${YELLOW}  You may need to reboot your system for changes to take full effect${NC}"
    fi
    
    # Check if bubblewrap now fails as expected
    echo -e "${BLUE}Testing bubblewrap with shared network...${NC}"
    if ! bwrap --share-net --unshare-user --unshare-pid --bind / / echo 'Test' &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap with shared network correctly fails${NC}"
        echo -e "${GREEN}  This confirms that the system is restored to its original state${NC}"
    else
        echo -e "${YELLOW}⚠ Bubblewrap with shared network still works${NC}"
        echo -e "${YELLOW}  Consider rebooting your system for changes to take full effect${NC}"
    fi
    
    return 0
}

# Main execution
main() {
    echo -e "${BLUE}Starting revert for Claude Desktop Manager sandboxing changes${NC}"
    echo -e "${BLUE}---------------------------------------------------${NC}"
    echo "This script will revert the system changes made by fix-apparmor.sh."
    echo "Claude Desktop Manager's sandboxing functionality will not work after this operation."
    echo ""
    
    # Check if changes are applied
    if ! check_if_applied; then
        echo -e "${YELLOW}No changes seem to be applied.${NC}"
        echo "Do you want to continue anyway? (y/n)"
        read -r response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            echo -e "${RED}Operation cancelled.${NC}"
            exit 0
        fi
    fi
    
    # Find backup
    find_backup
    
    echo ""
    echo -e "${YELLOW}This script will revert your system to its original state.${NC}"
    echo -e "${YELLOW}Claude Desktop Manager may not work correctly after this operation.${NC}"
    echo "Do you want to continue? (y/n)"
    read -r response
    
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "${RED}Operation cancelled.${NC}"
        exit 0
    fi
    
    # Revert changes
    revert_changes
    
    # Validate revert
    validate_revert
    
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  System changes successfully reverted!      ${NC}"
    echo -e "${GREEN}  System has been restored to original state.${NC}"
    echo -e "${GREEN}=============================================${NC}"
    
    echo ""
    echo -e "${YELLOW}Note: Claude Desktop Manager's sandboxing functionality will not work.${NC}"
    echo -e "${YELLOW}If you need to use Claude Desktop Manager, run:${NC}"
    echo "sudo $(dirname "$0")/fix-apparmor.sh"
    
    echo ""
    echo -e "${BLUE}For help or more information, see the README-APPARMOR.md file.${NC}"
}

# Run main function
main
