#!/bin/bash
# verify-isolation.sh - Script to verify sandbox isolation is working correctly
# This script checks if the sandbox is properly isolated from the real home directory

# Bold text formatting
BOLD="\e[1m"
RESET="\e[0m"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"

echo -e "${BOLD}Claude Desktop Manager - Sandbox Isolation Verification${RESET}"
echo "============================================================"

# Check if HOME is set correctly
echo -e "\n${BOLD}1. Checking HOME environment variable:${RESET}"
if [ "$HOME" != "/home/claude" ]; then
    echo -e "${RED}✗ HOME is incorrectly set to: $HOME${RESET}"
    echo "  It should be: /home/claude"
else
    echo -e "${GREEN}✓ HOME environment variable is correctly set to /home/claude${RESET}"
fi

# Check if real home is accessible
echo -e "\n${BOLD}2. Checking if real user home directory is inaccessible:${RESET}"
if [ -d "/home/awarth" ]; then
    echo -e "${RED}✗ CRITICAL: Can access real home at /home/awarth${RESET}"
    echo "  This indicates isolation failure!"
    ls -la "/home/awarth" | head -5
else
    echo -e "${GREEN}✓ Cannot access real home at /home/awarth (expected behavior)${RESET}"
fi

# Check if only the sandbox home exists
echo -e "\n${BOLD}3. Checking if /home contains only the sandbox directory:${RESET}"
if [ ! -d "/home/claude" ]; then
    echo -e "${RED}✗ ERROR: Cannot access sandbox home at /home/claude!${RESET}"
elif [ "$(ls -la /home | grep -v claude | grep -c ^d)" -gt 0 ]; then
    echo -e "${YELLOW}⚠ WARNING: Additional directories found in /home besides claude:${RESET}"
    ls -la /home
else
    echo -e "${GREEN}✓ Only the sandbox home directory (/home/claude) is accessible${RESET}"
fi

# Check if MCP configuration is using correct paths
echo -e "\n${BOLD}4. Checking MCP configuration paths:${RESET}"
config_file="$HOME/.config/Claude/claude_desktop_config.json"
if [ -f "$config_file" ]; then
    echo -e "${GREEN}✓ MCP configuration file exists at: $config_file${RESET}"
    
    # Check for paths in MCP config
    if grep -q "/home/awarth" "$config_file"; then
        echo -e "${RED}✗ Found references to /home/awarth in MCP config!${RESET}"
        grep -n "/home/awarth" "$config_file"
    else
        echo -e "${GREEN}✓ No references to real home directory in MCP config${RESET}"
    fi
    
    # Check for environment path
    if grep -q "\"HOME\": \"/home/claude\"" "$config_file"; then
        echo -e "${GREEN}✓ HOME environment correctly set to /home/claude in MCP config${RESET}"
    else
        echo -e "${YELLOW}⚠ HOME environment may not be correctly set in MCP config${RESET}"
        grep -n "\"HOME\"" "$config_file" || echo "  No HOME environment entry found"
    fi
else
    echo -e "${YELLOW}⚠ MCP configuration file not found at: $config_file${RESET}"
fi

# Check access to real config
echo -e "\n${BOLD}5. Testing access to real MCP configuration:${RESET}"
if [ -d "/home/awarth/.config/Claude" ]; then
    echo -e "${RED}✗ CRITICAL: Can access real Claude config at /home/awarth/.config/Claude${RESET}"
else
    echo -e "${GREEN}✓ Cannot access real Claude config (expected behavior)${RESET}"
fi

# Summarize findings
echo -e "\n${BOLD}Summary:${RESET}"
if [ "$HOME" != "/home/claude" ] || [ -d "/home/awarth" ] || [ -d "/home/awarth/.config/Claude" ]; then
    echo -e "${RED}❌ Sandbox isolation FAILED - Please check the sandbox configuration${RESET}"
else
    echo -e "${GREEN}✅ Sandbox isolation appears to be working correctly${RESET}"
fi

echo -e "\nFor more information, see README-ISOLATION-FIX.md"
