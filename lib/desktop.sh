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
    
    echo "Creating shell aliases for instance '$instance_name'..."
    
    # Get script directory and template file
    local script_path
    script_path="$(realpath "$0")"
    local template_file="${SCRIPT_DIR}/templates/bash_alias.template"
    
    # Check if template exists
    if [ ! -f "$template_file" ]; then
        echo "Warning: Alias template not found at ${template_file}, using minimal template."
        template_file=""
    fi
    
    # Create alias in user's .bash_aliases
    local alias_file="$HOME/.bash_aliases"
    
    # Create .bash_aliases if it doesn't exist
    if [ ! -f "$alias_file" ]; then
        touch "$alias_file"
    fi
    
    # Check if alias already exists
    if grep -q "alias $alias_name=" "$alias_file"; then
        # Remove all existing aliases for this instance
        sed -i "/alias $alias_name/d" "$alias_file"
        echo "Removed existing aliases for '$alias_name'."
    fi
    
    # Create a temporary file for the new aliases
    local temp_file
    temp_file="$(mktemp)"
    
    if [ -f "$template_file" ]; then
        # Use the template file
        cat "$template_file" > "$temp_file"
        
        # Replace template variables
        sed -i "s|{alias_name}|$alias_name|g" "$temp_file"
        sed -i "s|{script_path}|$script_path|g" "$temp_file"
        sed -i "s|{instance}|$instance_name|g" "$temp_file"
    else
        # Create minimal alias if template not found
        echo "alias $alias_name='$script_path start $instance_name'" > "$temp_file"
    fi
    
    # Append to .bash_aliases
    cat "$temp_file" >> "$alias_file"
    rm -f "$temp_file"
    
    echo "Aliases created. Run 'source ~/.bash_aliases' to enable them in the current shell."
    
    # Show the new aliases
    echo "Created aliases:"
    grep -n "$alias_name" "$alias_file" | sed 's/^/  /'
    
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
    
    # Get template directory
    local template_dir="$(find_template_dir)"
    if [ -z "$template_dir" ]; then
        echo "Warning: Templates directory not found, using fallback paths"
        template_dir="${SCRIPT_DIR}/templates"
        if [ ! -d "$template_dir" ]; then
            template_dir="$(cd "${SCRIPT_DIR}" && cd .. && pwd)/templates"
        fi
    fi
    
    # Try to use the desktop entry template
    local template_file="${template_dir}/desktop_entry.desktop"
    
    if [ -f "$template_file" ]; then
        echo "Using desktop entry template from: $template_file"
        # Read template content and substitute variables
        sed -e "s|{instance}|$instance_name|g" \
            -e "s|{script_path}|$script_path|g" \
            "$template_file" > "$desktop_file"
    else
        echo "Warning: Desktop entry template not found at ${template_file}"
        echo "Creating desktop entry from inline content"
        # Fallback to inline generation
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
    fi
    
    chmod +x "$desktop_file"
    
    echo "Desktop shortcut created at $desktop_file"
    return 0
}
