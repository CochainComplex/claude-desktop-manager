#!/bin/bash
# check-apparmor-status.sh - Check if unprivileged user namespaces are blocked
# This diagnostic script helps identify issues with Claude Desktop Manager sandboxing

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Claude Desktop Manager - Sandboxing Diagnostics  ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# Check Ubuntu version
ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")
echo -e "${BLUE}Checking system version...${NC}"
if [[ "$ubuntu_version" == "24.04" ]]; then
    echo -e "${YELLOW}⚠ Running on Ubuntu 24.04${NC}"
    echo "Ubuntu 24.04 restricts unprivileged user namespaces by default."
    echo "This is a security feature that affects bubblewrap's sandboxing."
else
    echo -e "${GREEN}✓ Running on system version: $ubuntu_version${NC}"
fi

# Check AppArmor status
echo -e "\n${BLUE}Checking AppArmor status...${NC}"
if systemctl is-active --quiet apparmor; then
    echo -e "${YELLOW}⚠ AppArmor is active${NC}"
else
    echo -e "${GREEN}✓ AppArmor is not active${NC}"
    echo "This is not likely to be your issue."
fi

# Check Ubuntu 24.04 AppArmor user namespace restrictions
echo -e "\n${BLUE}Checking AppArmor user namespace restrictions...${NC}"
if sysctl -a 2>/dev/null | grep -q "kernel.apparmor_restrict_unprivileged_userns"; then
    apparmor_restrict=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo "unknown")
    if [ "$apparmor_restrict" = "1" ]; then
        echo -e "${RED}✗ AppArmor unprivileged user namespace restrictions are enabled (value: 1)${NC}"
        echo -e "${YELLOW}This is preventing bubblewrap from creating user namespaces${NC}"
        echo -e "${YELLOW}This is the ROOT CAUSE of the issue${NC}"
    else
        echo -e "${GREEN}✓ AppArmor unprivileged user namespace restrictions are disabled (value: $apparmor_restrict)${NC}"
    fi
else
    echo -e "${GREEN}✓ This system does not have AppArmor user namespace restrictions${NC}"
fi

# Check if kernel allows unprivileged user namespaces
echo -e "\n${BLUE}Checking basic kernel configuration...${NC}"
if [ "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo 0)" = "1" ]; then
    echo -e "${GREEN}✓ kernel.unprivileged_userns_clone is enabled${NC}"
else
    echo -e "${RED}✗ kernel.unprivileged_userns_clone is not enabled${NC}"
    echo "This is required for bubblewrap to work properly."
    echo "Enable it with: echo 'kernel.unprivileged_userns_clone = 1' | sudo tee /etc/sysctl.d/99-userns.conf"
fi

# Test bubblewrap directly
echo -e "\n${BLUE}Testing bubblewrap with shared network (used by Claude Desktop Manager)...${NC}"
if bwrap --share-net --unshare-user --unshare-pid --bind / / echo 'Bubblewrap test' &>/dev/null; then
    echo -e "${GREEN}✓ Bubblewrap is working correctly with shared network!${NC}"
    echo "Claude Desktop Manager should work properly."
else
    echo -e "${RED}✗ Bubblewrap with shared network failed${NC}"
    
    # Get more detailed error information
    echo -e "${BLUE}Detailed error:${NC}"
    bwrap --share-net --unshare-user --unshare-pid --bind / / echo 'Bubblewrap test' 2>&1 | head -2
    
    # Check AppArmor logs for confirmation
    echo -e "\n${BLUE}Checking AppArmor logs for denials...${NC}"
    # Trigger a denial to capture in logs
    bwrap --share-net --unshare-user --unshare-pid --bind / / echo 'Test' &>/dev/null
    sleep 1
    
    # Display recent AppArmor denials
    echo -e "${BLUE}Recent AppArmor denials:${NC}"
    journalctl -k --since "30 seconds ago" | grep -i "apparmor.*denied" | head -3 || echo "No denial messages found"
fi

# Provide summary and next steps
echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}                Diagnosis Summary                  ${NC}"
echo -e "${BLUE}====================================================${NC}"

if [[ "$ubuntu_version" == "24.04" ]] && [ "$apparmor_restrict" = "1" ]; then
    echo -e "\n${YELLOW}ROOT CAUSE: AppArmor restrictions on unprivileged user namespaces${NC}"
    echo -e "On Ubuntu 24.04, the kernel parameter 'kernel.apparmor_restrict_unprivileged_userns'"
    echo -e "is set to 1 by default, which prevents bubblewrap from creating user namespaces."
    echo -e "The simplest solution is to disable this restriction with:"
    echo -e "  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0"
    echo -e "or run our fix script:"
else
    echo -e "\nBased on the tests above, take the appropriate action:"
fi

echo -e "\n${YELLOW}To fix the issue:${NC}"
echo "  sudo $(dirname "$0")/fix-apparmor.sh"

echo -e "\n${YELLOW}To revert changes later:${NC}"
echo "  sudo $(dirname "$0")/revert-apparmor-changes.sh"

echo -e "\n${YELLOW}For more information:${NC}"
echo "  Read the README-APPARMOR.md file in the project directory"

echo -e "\n${BLUE}====================================================${NC}"
