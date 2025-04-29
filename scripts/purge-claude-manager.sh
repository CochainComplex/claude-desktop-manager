#!/bin/bash
# purge-claude-manager.sh - Script to completely remove Claude Desktop Manager and all its data
#
# This script will remove:
# 1. All Claude Desktop Manager instances and their sandboxes
# 2. All configuration files and cache
# 3. Command-line aliases for Claude instances
# 4. Desktop shortcuts
# 5. System-wide executable (if installed)

set -e  # Exit on error

# ANSI color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print banner
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Claude Desktop Manager - Complete Purge           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Display warning
echo -e "${YELLOW}WARNING: This script will completely remove all Claude Desktop Manager data${NC}"
echo -e "${YELLOW}including all instances, configurations, and related files.${NC}"
echo -e "${YELLOW}This action is IRREVERSIBLE.${NC}"
echo ""

# Check if cmgr is installed and accessible
CMGR_PATH=$(which cmgr 2>/dev/null || echo "")
if [ -z "$CMGR_PATH" ]; then
    if [ -f "/usr/local/bin/cmgr" ]; then
        CMGR_PATH="/usr/local/bin/cmgr"
    else
        echo -e "${YELLOW}Warning: Could not find the cmgr executable.${NC}"
        echo -e "Will proceed with removing directories and files anyway."
        CMGR_PATH=""
    fi
fi

if [ -n "$CMGR_PATH" ]; then
    echo -e "Found cmgr at: ${CYAN}$CMGR_PATH${NC}"
fi

# Ask for confirmation with specific text to avoid accidental purge
echo ""
echo -e "${RED}To confirm deletion, please type 'PURGE ALL CLAUDE DATA' (in all caps):${NC}"
read -r confirmation

if [ "$confirmation" != "PURGE ALL CLAUDE DATA" ]; then
    echo "Purge aborted. No changes were made."
    exit 1
fi

echo -e "\n${CYAN}Starting complete purge of Claude Desktop Manager...${NC}\n"

# Function to display step header
step_header() {
    echo -e "\n${CYAN}▶ $1${NC}"
}

# Function to display success message
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to display warning message
warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to display error message
error() {
    echo -e "${RED}✗ $1${NC}"
}

# Step 1: Remove all instances
step_header "Step 1: Removing all Claude Desktop instances"

if [ -n "$CMGR_PATH" ]; then
    # Get list of instances
    instances=$($CMGR_PATH list 2>/dev/null | grep -oP '^\w+' || echo "")
    
    if [ -n "$instances" ]; then
        for instance in $instances; do
            echo "Removing instance: $instance"
            $CMGR_PATH remove "$instance" || warning "Failed to remove instance $instance normally, will remove files directly"
        done
        success "All instances removed through cmgr"
    else
        warning "No instances found with cmgr"
    fi
else
    warning "Skipping cmgr-based instance removal (cmgr not found)"
fi

# Step 2: Remove configuration directories
step_header "Step 2: Removing configuration directories"

if [ -d "$HOME/.cmgr" ]; then
    echo "Removing $HOME/.cmgr"
    rm -rf "$HOME/.cmgr"
    success "Removed cmgr configuration directory"
else
    warning "cmgr configuration directory not found at $HOME/.cmgr"
fi

# Step 3: Remove sandbox directories
step_header "Step 3: Removing sandbox directories"

if [ -d "$HOME/sandboxes" ]; then
    # Check if there are claude-related sandboxes only
    claude_sandboxes=$(find "$HOME/sandboxes" -maxdepth 1 -type d -name "*claude*" 2>/dev/null || echo "")
    sandbox_count=$(find "$HOME/sandboxes" -maxdepth 1 -type d | wc -l)
    
    if [ "$sandbox_count" -gt 1 ] && [ -z "$claude_sandboxes" ]; then
        # Sandboxes exist but none are claude-related, ask for confirmation
        echo -e "${YELLOW}Warning: The sandboxes directory contains non-Claude sandboxes.${NC}"
        echo "Do you want to remove the entire sandboxes directory anyway? (yes/no)"
        read -r remove_all_sandboxes
        
        if [ "$remove_all_sandboxes" = "yes" ]; then
            echo "Removing all sandboxes: $HOME/sandboxes"
            rm -rf "$HOME/sandboxes"
            success "Removed all sandboxes"
        else
            warning "Skipping sandbox removal to preserve non-Claude sandboxes"
        fi
    else
        # Either only claude sandboxes exist or no sandboxes exist
        echo "Removing sandboxes directory: $HOME/sandboxes"
        rm -rf "$HOME/sandboxes"
        success "Removed sandboxes directory"
    fi
else
    warning "Sandboxes directory not found at $HOME/sandboxes"
fi

# Step 4: Remove aliases from bash_aliases
step_header "Step 4: Removing Claude aliases from bash configuration"

BASH_ALIASES_FILES=(
    "$HOME/.bash_aliases"
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
)

aliases_removed=false

for alias_file in "${BASH_ALIASES_FILES[@]}"; do
    if [ -f "$alias_file" ]; then
        if grep -q "alias claude-" "$alias_file"; then
            echo "Removing Claude aliases from $alias_file"
            sed -i '/alias claude-/d' "$alias_file"
            aliases_removed=true
        fi
    fi
done

if [ "$aliases_removed" = true ]; then
    success "Removed Claude aliases from bash configuration"
else
    warning "No Claude aliases found in bash configuration files"
fi

# Step 5: Remove desktop shortcuts
step_header "Step 5: Removing desktop shortcuts"

desktop_files=$(find "$HOME/.local/share/applications" -name "claude-*.desktop" 2>/dev/null || echo "")

if [ -n "$desktop_files" ]; then
    echo "Removing Claude desktop shortcuts"
    rm -f "$HOME/.local/share/applications/claude-"*.desktop
    success "Removed Claude desktop shortcuts"
else
    warning "No Claude desktop shortcuts found"
fi

# Step 6: Remove system-wide installation (if installed)
step_header "Step 6: Checking for system-wide installation"

SYSTEM_LOCATIONS=(
    "/usr/local/bin/cmgr"
    "/usr/bin/cmgr"
    "/opt/claude-desktop-manager/cmgr"
)

system_found=false

for location in "${SYSTEM_LOCATIONS[@]}"; do
    if [ -f "$location" ] || [ -L "$location" ]; then
        system_found=true
        echo "Found system installation at $location"
        
        echo -e "${YELLOW}Warning: Removing system-wide installation requires sudo privileges.${NC}"
        echo "Do you want to remove the system-wide installation? (yes/no)"
        read -r remove_system
        
        if [ "$remove_system" = "yes" ]; then
            echo "Removing system installation: $location"
            sudo rm -f "$location" && success "Removed system installation" || error "Failed to remove system installation (permission denied)"
        else
            warning "Skipping system installation removal"
        fi
    fi
done

if [ "$system_found" = false ]; then
    warning "No system-wide installation found"
fi

# Step 7: Clean up possible Claude Desktop installation in ~/.local
step_header "Step 7: Cleaning up Claude Desktop from local installation"

if [ -d "$HOME/.local/share/claude-desktop" ]; then
    echo "Found Claude Desktop installation at $HOME/.local/share/claude-desktop"
    echo "Do you want to remove the Claude Desktop application? (yes/no)"
    read -r remove_claude
    
    if [ "$remove_claude" = "yes" ]; then
        echo "Removing Claude Desktop from $HOME/.local/share/claude-desktop"
        rm -rf "$HOME/.local/share/claude-desktop"
        success "Removed Claude Desktop local installation"
        
        # Also remove bin symlink if it exists
        if [ -f "$HOME/.local/bin/claude-desktop" ] || [ -L "$HOME/.local/bin/claude-desktop" ]; then
            echo "Removing Claude Desktop binary symlink"
            rm -f "$HOME/.local/bin/claude-desktop"
            success "Removed Claude Desktop symlink"
        fi
    else
        warning "Skipping Claude Desktop removal"
    fi
else
    warning "No Claude Desktop local installation found"
fi

# Step 8: Clean up global Claude configuration
step_header "Step 8: Cleaning up global Claude configuration"

if [ -d "$HOME/.config/Claude" ]; then
    echo "Found Claude configuration at $HOME/.config/Claude"
    echo "Do you want to remove Claude configuration? (yes/no)"
    echo -e "${YELLOW}Warning: This might affect other Claude applications if you have any.${NC}"
    read -r remove_config
    
    if [ "$remove_config" = "yes" ]; then
        echo "Removing Claude configuration from $HOME/.config/Claude"
        rm -rf "$HOME/.config/Claude"
        success "Removed Claude configuration"
    else
        warning "Skipping Claude configuration removal"
    fi
else
    warning "No Claude configuration found"
fi

# Final message
echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║ Claude Desktop Manager has been completely removed from your ║${NC}"
echo -e "${GREEN}║ system. All instances, configurations, and related files     ║${NC}"
echo -e "${GREEN}║ have been deleted.                                           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"

# Source changes (optional)
echo -e "\nYou may want to restart your terminal or run 'source ~/.bashrc' to apply bash alias changes."
