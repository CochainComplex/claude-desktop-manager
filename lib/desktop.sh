#!/bin/bash
# desktop.sh - Desktop integration utilities for Claude Desktop Manager

# Create a shell alias for an instance
create_alias() {
    local instance_name="$1"
    local alias_name="${2:-claude-${instance_name}}"
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    echo "Creating shell alias '$alias_name' for instance '$instance_name'..."
    
    # Get script directory
    local script_path
    script_path="$(realpath "$0")"
    
    # Create alias in user's .bashrc or .bash_aliases
    local alias_file="$HOME/.bash_aliases"
    
    # Create .bash_aliases if it doesn't exist
    if [ ! -f "$alias_file" ]; then
        touch "$alias_file"
    fi
    
    # Check if alias already exists
    if grep -q "alias $alias_name=" "$alias_file"; then
        # Update existing alias
        sed -i "s|alias $alias_name=.*|alias $alias_name='$script_path start $instance_name'|" "$alias_file"
    else
        # Add new alias
        echo "alias $alias_name='$script_path start $instance_name'" >> "$alias_file"
    fi
    
    echo "Alias created. Run 'source ~/.bash_aliases' to enable it in the current shell."
    return 0
}

# Create a desktop shortcut for an instance
create_desktop_shortcut() {
    local instance_name="$1"
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    echo "Creating desktop shortcut for instance '$instance_name'..."
    
    # Get script directory and path
    local script_path
    script_path="$(realpath "$0")"
    
    # Create desktop entry
    local desktop_dir="$HOME/.local/share/applications"
    mkdir -p "$desktop_dir"
    
    local desktop_file="${desktop_dir}/claude-${instance_name}.desktop"
    
    cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=Claude ($instance_name)
Comment=Claude AI Assistant ($instance_name instance)
Exec=$script_path start $instance_name
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
StartupWMClass=Claude-$instance_name
X-CMGR-Instance=$instance_name
EOF
    
    chmod +x "$desktop_file"
    
    echo "Desktop shortcut created at $desktop_file"
    return 0
}
