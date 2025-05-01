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
    
    # Starting point for port search
    local start_base=$((MCP_BASE_PORT + (allocations + 1) * MCP_PORT_RANGE))
    local max_tries=10
    local next_base=$start_base
    
    # Try to find an available port range
    for ((i=0; i<max_tries; i++)); do
        # Test key tool ports in this range
        local test_ports=(
            $((next_base + 10))  # filesystem
            $((next_base + 20))  # sequential-thinking
            $((next_base + 30))  # memory
        )
        
        local ports_available=true
        for test_port in "${test_ports[@]}"; do
            if is_port_in_use "$test_port"; then
                ports_available=false
                break
            fi
        done
        
        if [ "$ports_available" = "true" ]; then
            # Found an available port range
            echo "$next_base"
            return 0
        fi
        
        # Try the next range
        next_base=$((next_base + MCP_PORT_RANGE))
    done
    
    # If we couldn't find an available range, return the starting point and log a warning
    echo "WARNING: Could not find a completely free port range after $max_tries attempts." >&2
    echo "Using base port $start_base, but some tools might have port conflicts." >&2
    echo "$start_base"
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
    local port_in_use=1  # Default to not in use (return 1 means port is free)
    
    # Try to bind to the port to see if it's available
    if command -v nc >/dev/null 2>&1; then
        # Use netcat if available - returns 0 if port is in use
        if nc -z localhost "$port" >/dev/null 2>&1; then
            port_in_use=0  # Port is in use
        fi
    elif command -v ss >/dev/null 2>&1; then
        # Use ss command - returns 0 if pattern is found (port in use)
        if ss -ltn | grep -q ":$port "; then
            port_in_use=0  # Port is in use
        fi
    elif command -v netstat >/dev/null 2>&1; then
        # Use netstat command - returns 0 if pattern is found (port in use)
        if netstat -tln | grep -q ":$port "; then
            port_in_use=0  # Port is in use
        fi
    else
        # Fallback to trying to create a socket
        # This will return non-zero if the port is in use
        if ! (echo > /dev/tcp/localhost/"$port") >/dev/null 2>&1; then
            port_in_use=0  # Port is in use
        fi
    fi
    
    # Return 0 if port is in use, 1 if port is free
    # This makes it consistent with standard Unix return values
    # and works correctly with the ! operator in find_available_port()
    return $port_in_use
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
    
    # Sandbox user home path - must match the path used in sandbox.sh
    local sandbox_user_home="/home/claude"
    
    # Get tool ports
    local filesystem_port=$(get_tool_port "$instance_name" "filesystem")
    local sequential_thinking_port=$(get_tool_port "$instance_name" "sequential-thinking")
    local memory_port=$(get_tool_port "$instance_name" "memory")
    local desktop_commander_port=$(get_tool_port "$instance_name" "desktop-commander")
    local repl_port=$(get_tool_port "$instance_name" "repl")
    local playwright_port=$(get_tool_port "$instance_name" "executeautomation-playwright-mcp-server")
    
    # Get template directory
    local template_dir="$(find_template_dir)"
    if [ -z "$template_dir" ]; then
        echo "Warning: Templates directory not found, using fallback paths"
        template_dir="${SCRIPT_DIR}/templates"
        if [ ! -d "$template_dir" ]; then
            template_dir="$(cd "${SCRIPT_DIR}" && cd .. && pwd)/templates"
        fi
    fi
    
    # Path to the MCP config template
    local template_file="${template_dir}/mcp-config.json.template"
    
    if [ -f "$template_file" ]; then
        echo "Using MCP config template from: $template_file"
        # Read template content and substitute variables
        sed -e "s|{instance_name}|$instance_name|g" \
            -e "s|{sandbox_user_home}|$sandbox_user_home|g" \
            -e "s|{base_port}|$base_port|g" \
            -e "s|{display}|${DISPLAY:-:0}|g" \
            -e "s|{filesystem_port}|$filesystem_port|g" \
            -e "s|{sequential_thinking_port}|$sequential_thinking_port|g" \
            -e "s|{memory_port}|$memory_port|g" \
            -e "s|{desktop_commander_port}|$desktop_commander_port|g" \
            -e "s|{repl_port}|$repl_port|g" \
            -e "s|{playwright_port}|$playwright_port|g" \
            "$template_file" > "$output_file"
    else
        echo "Warning: MCP config template not found at ${template_file}"
        echo "Creating MCP server configuration from inline content"
        # Fallback to inline generation
        cat > "$output_file" << EOF
{
  "showTray": true,
  "electronInitScript": "${sandbox_user_home}/.config/Claude/electron/preload.js",
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/filesystem",
        "--port",
        "$filesystem_port"
      ],
      "env": {
        "DISPLAY": "${DISPLAY:-:0}",
        "MCP_PORT": "$filesystem_port",
        "MCP_SERVER_PORT": "$filesystem_port",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name",
        "HOME": "${sandbox_user_home}"
      }
    },
    "sequential-thinking": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/sequential-thinking",
        "--port",
        "$sequential_thinking_port"
      ],
      "env": {
        "DISPLAY": "${DISPLAY:-:0}",
        "MCP_PORT": "$sequential_thinking_port",
        "MCP_SERVER_PORT": "$sequential_thinking_port",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name",
        "HOME": "${sandbox_user_home}" 
      }
    },
    "memory": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/memory",
        "--port",
        "$memory_port"
      ],
      "env": {
        "DISPLAY": "${DISPLAY:-:0}",
        "MCP_PORT": "$memory_port",
        "MCP_SERVER_PORT": "$memory_port",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name",
        "HOME": "${sandbox_user_home}"
      }
    },
    "desktop-commander": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/desktop-commander",
        "--port",
        "$desktop_commander_port"
      ],
      "env": {
        "DISPLAY": "${DISPLAY:-:0}",
        "MCP_PORT": "$desktop_commander_port",
        "MCP_SERVER_PORT": "$desktop_commander_port",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name",
        "HOME": "${sandbox_user_home}"
      }
    },
    "repl": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/repl",
        "--port",
        "$repl_port"
      ],
      "env": {
        "DISPLAY": "${DISPLAY:-:0}",
        "MCP_PORT": "$repl_port",
        "MCP_SERVER_PORT": "$repl_port",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name",
        "HOME": "${sandbox_user_home}"
      }
    },
    "@executeautomation-playwright-mcp-server": {
      "command": "npx",
      "args": [
        "-y",
        "@executeautomation/playwright-mcp-server",
        "--port",
        "$playwright_port"
      ],
      "env": {
        "DISPLAY": "${DISPLAY:-:0}",
        "MCP_PORT": "$playwright_port",
        "MCP_SERVER_PORT": "$playwright_port",
        "MCP_BASE_PORT": "$base_port",
        "CLAUDE_INSTANCE": "$instance_name",
        "HOME": "${sandbox_user_home}"
      }
    }
  }
}
EOF
    fi
    
    echo "Generated MCP server configuration for instance '$instance_name' with base port $base_port"
    echo "Using sandbox home path: ${sandbox_user_home}"
    return 0
}
