#!/bin/bash
# revert-apparmor-changes.sh - Revert AppArmor changes made by fix-apparmor.sh
# This script safely restores the original AppArmor configuration

set -eo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Claude Desktop Manager - AppArmor Revert Utility  ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (with sudo)${NC}"
    echo "Please run: sudo $(basename "$0")"
    exit 1
fi

# Function to check if our AppArmor changes are active
check_if_applied() {
    echo -e "${BLUE}Checking if AppArmor changes are applied...${NC}"
    
    if [ -f "/etc/apparmor.d/local/.cmgr-apparmor-fix-applied" ]; then
        echo -e "${GREEN}✓ Found marker file indicating AppArmor changes were applied${NC}"
        return 0
    elif [ -f "/etc/apparmor.d/local/unprivileged_userns" ]; then
        # Check if file contains our modifications
        if grep -q "Created by Claude Desktop Manager" "/etc/apparmor.d/local/unprivileged_userns"; then
            echo -e "${GREEN}✓ Found local override created by Claude Desktop Manager${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Found local override, but it wasn't created by Claude Desktop Manager${NC}"
            echo "Contents of local override:"
            cat "/etc/apparmor.d/local/unprivileged_userns"
            echo ""
            echo -e "${YELLOW}Removing this file might impact other applications.${NC}"
            echo "Do you want to continue? (y/n)"
            read -r response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                return 0
            else
                echo -e "${RED}Operation cancelled.${NC}"
                exit 0
            fi
        fi
    else
        echo -e "${YELLOW}⚠ No local override found for unprivileged_userns${NC}"
        echo -e "${YELLOW}  It appears that AppArmor changes were not applied or were already reverted.${NC}"
        return 1
    fi
}

# Function to find latest backup
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

# Function to revert changes
revert_changes() {
    echo -e "${BLUE}Reverting AppArmor changes...${NC}"
    
    # Remove local override
    if [ -f "/etc/apparmor.d/local/unprivileged_userns" ]; then
        rm -f "/etc/apparmor.d/local/unprivileged_userns"
        echo -e "${GREEN}✓ Removed local override for unprivileged_userns${NC}"
    fi
    
    # Remove marker file
    if [ -f "/etc/apparmor.d/local/.cmgr-apparmor-fix-applied" ]; then
        rm -f "/etc/apparmor.d/local/.cmgr-apparmor-fix-applied"
        echo -e "${GREEN}✓ Removed marker file${NC}"
    fi
    
    # Restore from backup if available
    if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/unprivileged_userns" ]; then
        # Only restore if original file exists and is different
        if [ -f "/etc/apparmor.d/unprivileged_userns" ]; then
            if ! cmp -s "$BACKUP_DIR/unprivileged_userns" "/etc/apparmor.d/unprivileged_userns"; then
                cp "$BACKUP_DIR/unprivileged_userns" "/etc/apparmor.d/"
                echo -e "${GREEN}✓ Restored original unprivileged_userns profile from backup${NC}"
            else
                echo -e "${GREEN}✓ Original profile unchanged, no restoration needed${NC}"
            fi
        else
            cp "$BACKUP_DIR/unprivileged_userns" "/etc/apparmor.d/"
            echo -e "${GREEN}✓ Restored original unprivileged_userns profile from backup${NC}"
        fi
    fi
    
    # Reload AppArmor to apply changes
    echo -e "${BLUE}Reloading AppArmor...${NC}"
    if systemctl reload apparmor; then
        echo -e "${GREEN}✓ AppArmor reloaded successfully${NC}"
    else
        echo -e "${RED}✗ Failed to reload AppArmor${NC}"
        echo "Please reload AppArmor manually with: sudo systemctl reload apparmor"
        return 1
    fi
    
    # Allow a moment for changes to take effect
    sleep 2
    
    return 0
}

# Function to validate revert
validate_revert() {
    echo -e "${BLUE}Validating revert...${NC}"
    
    # Check if local override is gone
    if [ -f "/etc/apparmor.d/local/unprivileged_userns" ]; then
        echo -e "${RED}✗ Local override still exists at /etc/apparmor.d/local/unprivileged_userns${NC}"
        return 1
    else
        echo -e "${GREEN}✓ Local override successfully removed${NC}"
    fi
    
    # Check if bubblewrap now fails as expected
    if ! su -c "bwrap --unshare-all --bind / / echo 'Bubblewrap test'" $SUDO_USER &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap correctly fails with unprivileged user namespaces${NC}"
        echo -e "${GREEN}  This confirms that AppArmor restrictions are back in place${NC}"
    else
        echo -e "${YELLOW}⚠ Bubblewrap still works with unprivileged user namespaces${NC}"
        echo -e "${YELLOW}  This might indicate that other system settings are allowing it${NC}"
        echo -e "${YELLOW}  (This is not necessarily a problem, just unexpected)${NC}"
    fi
    
    return 0
}

# Main execution
main() {
    # Banner
    echo -e "${BLUE}Starting AppArmor revert for Claude Desktop Manager${NC}"
    echo -e "${BLUE}---------------------------------------------------${NC}"
    echo "This script will revert the AppArmor changes made by fix-apparmor.sh."
    echo "Claude Desktop Manager's sandboxing functionality may not work after this operation."
    echo ""
    
    # Check if changes are applied
    if ! check_if_applied; then
        echo -e "${YELLOW}No AppArmor changes seem to be applied.${NC}"
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
    echo -e "${YELLOW}This script will revert your AppArmor configuration to its original state.${NC}"
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
    echo -e "${GREEN}  AppArmor changes successfully reverted!    ${NC}"
    echo -e "${GREEN}  System has been restored to original state.${NC}"
    echo -e "${GREEN}=============================================${NC}"
    
    echo ""
    echo -e "${YELLOW}Note: Claude Desktop Manager's sandboxing functionality may not work.${NC}"
    echo -e "${YELLOW}If you need to use Claude Desktop Manager, run:${NC}"
    echo "sudo $(dirname "$0")/fix-apparmor.sh"
    
    echo ""
    echo -e "${BLUE}For help or more information, see the README-APPARMOR.md file.${NC}"
}

# Run main function
main
