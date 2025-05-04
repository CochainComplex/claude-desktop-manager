#!/bin/bash
# check-apparmor-status.sh - Check if AppArmor is blocking bubblewrap
# This diagnostic script helps identify if AppArmor is causing issues with Claude Desktop Manager

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Claude Desktop Manager - AppArmor Diagnostics    ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# Check AppArmor status
echo -e "${BLUE}Checking AppArmor status...${NC}"
if systemctl is-active --quiet apparmor; then
    echo -e "${YELLOW}⚠ AppArmor is active${NC}"
    echo "This could potentially block bubblewrap from creating user namespaces."
else
    echo -e "${GREEN}✓ AppArmor is not active${NC}"
    echo "This is not likely to be your issue."
fi

# Check if kernel allows unprivileged user namespaces
echo -e "\n${BLUE}Checking kernel configuration...${NC}"
if [ "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo 0)" = "1" ]; then
    echo -e "${GREEN}✓ kernel.unprivileged_userns_clone is enabled${NC}"
else
    echo -e "${RED}✗ kernel.unprivileged_userns_clone is not enabled${NC}"
    echo "This is required for bubblewrap to work properly."
    echo "Enable it with: echo 'kernel.unprivileged_userns_clone = 1' | sudo tee /etc/sysctl.d/99-userns.conf"
fi

# Check boot parameters
echo -e "\n${BLUE}Checking boot parameters...${NC}"
if grep -q "namespace.unpriv_enable=1" /proc/cmdline && grep -q "user_namespace.enable=1" /proc/cmdline; then
    echo -e "${GREEN}✓ Boot parameters for user namespaces are set correctly${NC}"
else
    echo -e "${YELLOW}⚠ Boot parameters for user namespaces might not be set correctly${NC}"
    echo -e "Current cmdline: $(cat /proc/cmdline)"
    echo -e "Recommended parameters: namespace.unpriv_enable=1 user_namespace.enable=1"
fi

# Test bubblewrap directly
echo -e "\n${BLUE}Testing bubblewrap with full isolation...${NC}"
if bwrap --unshare-all --bind / / echo 'Bubblewrap test' &>/dev/null; then
    echo -e "${GREEN}✓ Bubblewrap is working correctly with full isolation!${NC}"
    echo "This suggests that both AppArmor and kernel are properly configured."
else
    echo -e "${RED}✗ Bubblewrap with full isolation failed${NC}"
    
    # Get more detailed error information
    echo -e "${BLUE}Detailed error:${NC}"
    bwrap --unshare-all --bind / / echo 'Bubblewrap test' 2>&1 | head -2
    
    # Try with shared network namespace
    echo -e "\n${BLUE}Testing bubblewrap with shared network...${NC}"
    if bwrap --share-net --unshare-user --unshare-pid --unshare-uts --unshare-ipc --bind / / echo 'Bubblewrap test' &>/dev/null; then
        echo -e "${GREEN}✓ Bubblewrap works when sharing network namespace!${NC}"
        echo -e "${YELLOW}This indicates a network namespace permission issue.${NC}"
        echo -e "${YELLOW}Claude Desktop Manager has been configured to use --share-net for compatibility.${NC}"
    else
        echo -e "${RED}✗ Bubblewrap also fails with shared network${NC}"
        echo -e "${BLUE}Detailed error:${NC}"
        bwrap --share-net --unshare-user --unshare-pid --unshare-uts --unshare-ipc --bind / / echo 'Bubblewrap test' 2>&1 | head -2
    fi
    
    # Check if it's likely an AppArmor issue
    if bwrap --unshare-all --bind / / echo 'Test' 2>&1 | grep -q "Permission denied"; then
        echo -e "\n${YELLOW}This looks like an AppArmor restriction.${NC}"
        
        # Check AppArmor logs for confirmation
        echo -e "\n${BLUE}Checking AppArmor logs...${NC}"
        # We need to trigger a fresh denial to capture in the logs
        bwrap --unshare-all --bind / / echo 'Test' &>/dev/null
        sleep 1
        
        if journalctl -k --since "1 minute ago" | grep -i "apparmor.*bwrap.*denied"; then
            echo -e "\n${RED}Confirmed: AppArmor is blocking bubblewrap!${NC}"
            echo -e "${YELLOW}To fix this issue, run:${NC}"
            echo -e "  sudo $(dirname "$0")/fix-apparmor.sh"
        else
            echo "No specific AppArmor denial messages found. This might be a different issue."
            echo "Try running with sudo to see more logs:"
            echo "  sudo journalctl -k | grep -i apparmor | grep -i denied | grep -i bwrap"
        fi
    fi
fi

# Provide summary and next steps
echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}                Diagnosis Summary                  ${NC}"
echo -e "${BLUE}====================================================${NC}"

echo -e "\nIf the tests above indicate an AppArmor issue, you can use the following commands:"
echo -e "${YELLOW}To fix the issue:${NC}"
echo "  sudo $(dirname "$0")/fix-apparmor.sh"

echo -e "\n${YELLOW}To revert changes later:${NC}"
echo "  sudo $(dirname "$0")/revert-apparmor-changes.sh"

echo -e "\n${YELLOW}For more information:${NC}"
echo "  Read the README-APPARMOR.md file in the project directory"

echo -e "\n${BLUE}====================================================${NC}"
