#!/bin/bash
# utils.sh - Shared utility functions for Claude Desktop Manager
# Derived from the original emsi/claude-desktop project

# IMPORTANT: Within sandbox environments, home path is always /home/claude
# When referring to paths inside the sandbox, always use /home/claude explicitly
# rather than using $HOME substitution for clarity and consistency

# Find template directory with multiple fallback strategies
# Returns the path to the templates directory
find_template_dir() {
    local base_dir="${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
    
    # First attempt - relative to script directory
    local template_dir="${base_dir}/../templates"
    if [ -d "${template_dir}" ]; then
        echo "${template_dir}"
        return 0
    fi
    
    # Second attempt - use absolute path relative to script directory
    template_dir="$(cd "${base_dir}" 2>/dev/null && cd .. 2>/dev/null && pwd)/templates"
    if [ -d "${template_dir}" ]; then
        echo "${template_dir}"
        return 0
    fi
    
    # Third attempt - try from the current script's location
    template_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && cd .. 2>/dev/null && pwd)/templates"
    if [ -d "${template_dir}" ]; then
        echo "${template_dir}"
        return 0
    fi
    
    # If no template dir found, return empty and let the caller handle it
    echo ""
    return 1
}

# Find scripts directory with multiple fallback strategies
# Returns the path to the scripts directory
find_scripts_dir() {
    local base_dir="${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
    
    # First attempt - relative to script directory
    local scripts_dir="${base_dir}/../scripts"
    if [ -d "${scripts_dir}" ]; then
        echo "${scripts_dir}"
        return 0
    fi
    
    # Second attempt - use absolute path relative to script directory
    scripts_dir="$(cd "${base_dir}" 2>/dev/null && cd .. 2>/dev/null && pwd)/scripts"
    if [ -d "${scripts_dir}" ]; then
        echo "${scripts_dir}"
        return 0
    fi
    
    # Third attempt - try from the current script's location
    scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && cd .. 2>/dev/null && pwd)/scripts"
    if [ -d "${scripts_dir}" ]; then
        echo "${scripts_dir}"
        return 0
    fi
    
    # If no scripts dir found, return empty and let the caller handle it
    echo ""
    return 1
}

# Get standardized paths for sandbox and host configurations
# Returns the path to the Claude config directory in a sandbox
get_sandbox_config_path() {
    local sandbox_name="$1"
    local sandbox_home="${SANDBOX_BASE:-${HOME}/sandboxes}/${sandbox_name}"
    
    echo "${sandbox_home}/.config/Claude"
}

# Get the path to the Claude electron config directory in a sandbox
get_sandbox_electron_path() {
    local sandbox_name="$1"
    local config_dir="$(get_sandbox_config_path "$sandbox_name")"
    
    echo "${config_dir}/electron"
}

# Get the path to the Claude config file in a sandbox
get_sandbox_config_file() {
    local sandbox_name="$1"
    local config_dir="$(get_sandbox_config_path "$sandbox_name")"
    
    echo "${config_dir}/claude_desktop_config.json"
}

# Copy a template file to the destination or create it from inline content if template doesn't exist
# Usage: copy_or_create_template <template_file> <destination_file> <inline_content>
copy_or_create_template() {
    local template_file="$1"
    local destination_file="$2"
    local inline_content="$3"
    local description="${4:-template}"
    
    # Ensure destination directory exists
    mkdir -p "$(dirname "$destination_file")"
    
    if [ -f "$template_file" ]; then
        # Copy from template
        cp -f "$template_file" "$destination_file"
        echo "✓ Added $description from template to ${destination_file}"
        return 0
    else
        # Create from inline content
        echo "Template not found, creating $description directly..."
        echo "$inline_content" > "$destination_file"
        echo "✓ Created $description at ${destination_file}"
        return 0
    fi
}

# Update a JSON config file or create it if it doesn't exist
# Usage: update_config_file <config_file> <json_update_expression> <default_content>
update_config_file() {
    local config_file="$1"
    local json_expr="$2"
    local default_content="$3"
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$config_file")"
    
    if [ -f "$config_file" ]; then
        # Update existing config using jq
        if command -v jq &>/dev/null; then
            jq "$json_expr" "$config_file" > "${config_file}.tmp" && \
            mv "${config_file}.tmp" "$config_file"
            echo "✓ Updated configuration file: ${config_file}"
        else
            echo "Warning: jq not found, cannot update config file. Creating new one instead."
            echo "$default_content" > "$config_file"
            echo "✓ Created new configuration file: ${config_file}"
        fi
    else
        # Create new config
        echo "$default_content" > "$config_file"
        echo "✓ Created new configuration file: ${config_file}"
    fi
    
    return 0
}