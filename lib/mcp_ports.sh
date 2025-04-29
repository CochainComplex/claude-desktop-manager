#!/bin/bash
# mcp_ports.sh - MCP port management for Claude Desktop Manager
# 
# This module handles port allocation and tracking for MCP servers
# to ensure multiple Claude Desktop instances can run simultaneously
# without port conflicts.

# Base port for MCP servers
MCP_BASE_PORT=9000
# Range size per instance
MCP_PORT_RANGE=100

# Initialize the port registry if it doesn't exist
initialize_port_registry() {
    local port_registry="${CMGR_HOME}/port_registry.json"
    
    if [ ! -f "$port_registry" ]; then
        echo '{"allocated_ports": {}}' > "$port_registry"
    fi
}

# Get the next available port range
get_next_port_range() {
    local port_registry="${CMGR_HOME}/port_registry.json"
    initialize_port_registry
    
    # Read existing allocations
    local allocations
    allocations=$(jq -r '.allocated_ports | keys | map(tonumber) | sort | .[-1] // 0' "$port_registry")
    
    # Calculate next base port
    local next_base=$((MCP_BASE_PORT + (allocations + 1) * MCP_PORT_RANGE))
    
    echo "$next_base"
}

# Allocate port range for instance
allocate_port_range() {
    local instance_name="$1"
    local port_registry="${CMGR_HOME}/port_registry.json"
    initialize_port_registry
    
    # Check if instance already has a port range
    local existing_base
    existing_base=$(jq -r --arg name "$instance_name" '.allocated_ports[$name] // 0' "$port_registry")
    
    if [ "$existing_base" != "0" ]; then
        echo "Instance '$instance_name' already has allocated port range starting at $existing_base"
        return 0
    fi
    
    # Get next available port range
    local base_port
    base_port=$(get_next_port_range)
    
    # Update registry
    jq --arg name "$instance_name" \
       --arg port "$base_port" \
       '.allocated_ports[$name] = ($port | tonumber)' \
       "$port_registry" > "${port_registry}.tmp" && \
    mv "${port_registry}.tmp" "$port_registry"
    
    echo "Allocated port range for '$instance_name' starting at $base_port"
    echo "$base_port"
}

# Get port base for instance
get_port_base() {
    local instance_name="$1"
    local port_registry="${CMGR_HOME}/port_registry.json"
    initialize_port_registry
    
    # Get base port for instance
    local base_port
    base_port=$(jq -r --arg name "$instance_name" '.allocated_ports[$name] // 0' "$port_registry")
    
    # If instance doesn't have a port range yet, allocate one
    if [ "$base_port" = "0" ]; then
        base_port=$(allocate_port_range "$instance_name")
    fi
    
    echo "$base_port"
}

# Get specific tool port for instance
get_tool_port() {
    local instance_name="$1"
    local tool_name="$2"
    
    # Get base port for instance
    local base_port
    base_port=$(get_port_base "$instance_name")
    
    # Calculate port offset based on tool name
    local offset=0
    case "$tool_name" in
        filesystem)
            offset=10
            ;;
        sequential-thinking)
            offset=20
            ;;
        memory)
            offset=30
            ;;
        desktop-commander)
            offset=40
            ;;
        repl)
            offset=50
            ;;
        executeautomation-playwright-mcp-server)
            offset=60
            ;;
        *)
            # Default offset based on hash of tool name
            offset=$(($(echo "$tool_name" | cksum | cut -d' ' -f1) % 90 + 10))
            ;;
    esac
    
    echo $((base_port + offset))
}

# Release port range for instance
release_port_range() {
    local instance_name="$1"
    local port_registry="${CMGR_HOME}/port_registry.json"
    initialize_port_registry
    
    # Update registry
    jq --arg name "$instance_name" \
       'del(.allocated_ports[$name])' \
       "$port_registry" > "${port_registry}.tmp" && \
    mv "${port_registry}.tmp" "$port_registry"
    
    echo "Released port range for '$instance_name'"
}

# Check if a port is in use
is_port_in_use() {
    local port="$1"
    
    # Try to bind to the port to see if it's available
    if command -v nc >/dev/null 2>&1; then
        # Use netcat if available
        nc -z localhost "$port" >/dev/null 2>&1
        return $?
    elif command -v ss >/dev/null 2>&1; then
        # Use ss command
        ss -ltn | grep -q ":$port "
        return $?
    elif command -v netstat >/dev/null 2>&1; then
        # Use netstat command
        netstat -tln | grep -q ":$port "
        return $?
    else
        # Fallback to trying to create a socket
        (echo > /dev/tcp/localhost/"$port") >/dev/null 2>&1
        return $?
    fi
}

# Find available port in a range
find_available_port() {
    local start_port="$1"
    local num_ports="${2:-10}"
    
    for ((i=0; i<num_ports; i++)); do
        local port=$((start_port + i))
        if ! is_port_in_use "$port"; then
            echo "$port"
            return 0
        fi
    done
    
    # If no available port found, return the start port and hope for the best
    echo "$start_port"
    return 1
}

# Generate MCP server configuration with unique ports
generate_mcp_server_config() {
    local instance_name="$1"
    local output_file="$2"
    
    # Get base port for instance
    local base_port
    base_port=$(get_port_base "$instance_name")
    
    # Create MCP server configuration
    cat > "$output_file" << EOF
{
  "showTray": true,
  "electronInitScript": "\$HOME/.config/Claude/electron/preload.js",
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/filesystem",
        "--port",
        "$(get_tool_port "$instance_name" "filesystem")"
      ],
      "env": {
        "DISPLAY": ":0",
        "MCP_PORT": "$(get_tool_port "$instance_name" "filesystem")",
        "MCP_SERVER_PORT": "$(get_tool_port "$instance_name" "filesystem")",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name"
      }
    },
    "sequential-thinking": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/sequential-thinking",
        "--port",
        "$(get_tool_port "$instance_name" "sequential-thinking")"
      ],
      "env": {
        "DISPLAY": ":0",
        "MCP_PORT": "$(get_tool_port "$instance_name" "sequential-thinking")",
        "MCP_SERVER_PORT": "$(get_tool_port "$instance_name" "sequential-thinking")",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name"
      }
    },
    "memory": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/memory",
        "--port",
        "$(get_tool_port "$instance_name" "memory")"
      ],
      "env": {
        "DISPLAY": ":0",
        "MCP_PORT": "$(get_tool_port "$instance_name" "memory")",
        "MCP_SERVER_PORT": "$(get_tool_port "$instance_name" "memory")",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name"
      }
    },
    "desktop-commander": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/desktop-commander",
        "--port",
        "$(get_tool_port "$instance_name" "desktop-commander")"
      ],
      "env": {
        "DISPLAY": ":0",
        "MCP_PORT": "$(get_tool_port "$instance_name" "desktop-commander")",
        "MCP_SERVER_PORT": "$(get_tool_port "$instance_name" "desktop-commander")",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name"
      }
    },
    "repl": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/repl",
        "--port",
        "$(get_tool_port "$instance_name" "repl")"
      ],
      "env": {
        "DISPLAY": ":0",
        "MCP_PORT": "$(get_tool_port "$instance_name" "repl")",
        "MCP_SERVER_PORT": "$(get_tool_port "$instance_name" "repl")",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name"
      }
    },
    "@executeautomation-playwright-mcp-server": {
      "command": "npx",
      "args": [
        "-y",
        "@executeautomation/playwright-mcp-server",
        "--port",
        "$(get_tool_port "$instance_name" "executeautomation-playwright-mcp-server")"
      ],
      "env": {
        "DISPLAY": ":0",
        "MCP_PORT": "$(get_tool_port "$instance_name" "executeautomation-playwright-mcp-server")",
        "MCP_SERVER_PORT": "$(get_tool_port "$instance_name" "executeautomation-playwright-mcp-server")",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name"
      }
    }
  }
}
EOF

    echo "Generated MCP server configuration for instance '$instance_name' with base port $base_port"
    return 0
}
