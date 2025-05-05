#!/bin/bash
# mcp_filesystem.sh - MCP Filesystem management for Claude Desktop Manager

# Function to configure the MCP filesystem server with a custom path
configure_mcp_filesystem() {
    local instance_name="$1"
    local host_path="$2"
    
    # Check if instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Normalize host path (remove trailing slash)
    host_path=$(echo "$host_path" | sed 's:/*$::')
    
    # Verify host path exists
    if [ ! -d "$host_path" ]; then
        echo "Error: Host path '$host_path' does not exist."
        return 1
    fi
    
    # Make sure the path is added to the host paths registry for mounting
    if ! add_host_path "$instance_name" "$host_path"; then
        echo "Warning: Failed to register host path in registry."
    fi
    
    # Get config file path
    local sandbox_home="${SANDBOX_BASE}/${instance_name}"
    local config_file="${sandbox_home}/.config/Claude/claude_desktop_config.json"
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$config_file")"
    
    # Get port information for MCP
    if ! command -v get_port_base &>/dev/null; then
        source "${SCRIPT_DIR}/lib/mcp_ports.sh"
    fi
    
    local base_port=$(get_port_base "$instance_name")
    local filesystem_port=$(get_tool_port "$instance_name" "filesystem")
    
    # Check if config file exists
    if [ -f "$config_file" ]; then
        # Update the filesystem server configuration
        local temp_file="${config_file}.tmp"
        
        # First check if mcpServers exists
        if jq -e '.mcpServers' "$config_file" > /dev/null 2>&1; then
            # Update the filesystem server configuration
            jq --arg path "$host_path" \
               --arg port "$filesystem_port" \
               --arg base_port "$base_port" \
               --arg instance "$instance_name" \
               '.mcpServers.filesystem.args = ["-y", "@modelcontextprotocol/server-filesystem", $path] |
                .mcpServers.filesystem.autoStart = false |
                .mcpServers.filesystem.env.MCP_PORT = $port |
                .mcpServers.filesystem.env.MCP_SERVER_PORT = $port |
                .mcpServers.filesystem.env.MCP_BASE_PORT = $base_port |
                .mcpServers.filesystem.env.CLAUDE_INSTANCE = $instance |
                .mcpServers.filesystem.env.HOME = $path' \
                "$config_file" > "$temp_file" && \
            mv "$temp_file" "$config_file"
        else
            # Create mcpServers configuration from scratch
            jq --arg path "$host_path" \
               --arg port "$filesystem_port" \
               --arg base_port "$base_port" \
               --arg instance "$instance_name" \
               --arg display "${DISPLAY:-:0}" \
               '. + {
                  "mcpServers": {
                    "filesystem": {
                      "command": "npx",
                      "args": ["-y", "@modelcontextprotocol/server-filesystem", $path],
                      "autoStart": false,
                      "env": {
                        "DISPLAY": $display,
                        "MCP_PORT": $port,
                        "MCP_SERVER_PORT": $port,
                        "MCP_BASE_PORT": $base_port,
                        "CLAUDE_INSTANCE": $instance,
                        "HOME": $path
                      }
                    }
                  }
                }' \
                "$config_file" > "$temp_file" && \
            mv "$temp_file" "$config_file"
        fi
    else
        # Create new config file with filesystem configuration
        local sandbox_user_home="/home/claude"
        
        cat > "$config_file" << EOF
{
  "showTray": true,
  "electronInitScript": "${sandbox_user_home}/.config/Claude/electron/preload.js",
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "${host_path}"
      ],
      "autoStart": false,
      "env": {
        "DISPLAY": "${DISPLAY:-:0}",
        "MCP_PORT": "${filesystem_port}",
        "MCP_SERVER_PORT": "${filesystem_port}",
        "MCP_BASE_PORT": "${base_port}",
        "CLAUDE_INSTANCE": "${instance_name}",
        "HOME": "${host_path}"
      }
    }
  }
}
EOF
    fi
    
    echo "MCP filesystem server configured to use host path: ${host_path}"
    echo "Filesystem MCP server port: ${filesystem_port}"
    
    # Remind the user to restart the instance
    echo "Please restart the instance for the changes to take effect."
    return 0
}
