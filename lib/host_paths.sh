#!/bin/bash
# host_paths.sh - Manage host path mappings for Claude Desktop Manager

# Initialize host paths registry
initialize_host_paths_registry() {
    local instance_name="$1"
    local paths_registry="${CMGR_HOME}/host_paths_registry.json"
    
    # Create if doesn't exist
    if [ ! -f "$paths_registry" ]; then
        echo '{"instances": {}}' > "$paths_registry"
        return 0
    fi
    
    # Validate JSON content
    if ! jq empty "$paths_registry" 2>/dev/null; then
        echo "WARNING: Host paths registry is corrupted. Creating backup and reinitializing." >&2
        cp "$paths_registry" "${paths_registry}.corrupted.$(date +%s)" 2>/dev/null || true
        echo '{"instances": {}}' > "$paths_registry"
    fi
}

# Add a host path mapping for an instance
add_host_path() {
    local instance_name="$1"
    local host_path="$2"
    
    # Verify instance exists
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
    
    # Initialize registry
    local paths_registry="${CMGR_HOME}/host_paths_registry.json"
    initialize_host_paths_registry "$instance_name"
    
    # Check if instance entry exists in registry
    local has_instance
    has_instance=$(jq -r --arg name "$instance_name" '.instances | has($name)' "$paths_registry")
    
    if [ "$has_instance" = "false" ]; then
        # Create instance entry with new path
        jq --arg name "$instance_name" \
           --arg path "$host_path" \
           '.instances[$name] = {"paths": [$path]}' \
           "$paths_registry" > "${paths_registry}.tmp" && \
        mv "${paths_registry}.tmp" "$paths_registry"
    else
        # Check if path already exists for instance
        local has_path
        has_path=$(jq -r --arg name "$instance_name" \
                      --arg path "$host_path" \
                      '.instances[$name].paths | contains([$path])' \
                      "$paths_registry")
        
        if [ "$has_path" = "true" ]; then
            echo "Host path '$host_path' is already mapped for instance '$instance_name'."
            return 0
        fi
        
        # Add new path to existing instance
        jq --arg name "$instance_name" \
           --arg path "$host_path" \
           '.instances[$name].paths += [$path]' \
           "$paths_registry" > "${paths_registry}.tmp" && \
        mv "${paths_registry}.tmp" "$paths_registry"
    fi
    
    echo "Added host path '$host_path' to instance '$instance_name'."
    return 0
}

# Remove a host path mapping for an instance
remove_host_path() {
    local instance_name="$1"
    local host_path="$2"
    
    # Verify instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Normalize host path (remove trailing slash)
    host_path=$(echo "$host_path" | sed 's:/*$::')
    
    # Initialize registry
    local paths_registry="${CMGR_HOME}/host_paths_registry.json"
    initialize_host_paths_registry "$instance_name"
    
    # Check if instance has any paths
    local has_instance
    has_instance=$(jq -r --arg name "$instance_name" '.instances | has($name)' "$paths_registry")
    
    if [ "$has_instance" = "false" ]; then
        echo "No host paths are mapped for instance '$instance_name'."
        return 0
    fi
    
    # Remove path from instance
    jq --arg name "$instance_name" \
       --arg path "$host_path" \
       '.instances[$name].paths = (.instances[$name].paths | map(select(. != $path)))' \
       "$paths_registry" > "${paths_registry}.tmp" && \
    mv "${paths_registry}.tmp" "$paths_registry"
    
    echo "Removed host path '$host_path' from instance '$instance_name'."
    return 0
}

# List host path mappings for an instance
list_host_paths() {
    local instance_name="$1"
    
    # Verify instance exists
    if ! instance_exists "$instance_name"; then
        echo "Error: Instance '$instance_name' does not exist."
        return 1
    fi
    
    # Initialize registry
    local paths_registry="${CMGR_HOME}/host_paths_registry.json"
    initialize_host_paths_registry "$instance_name"
    
    # Get paths for instance
    local paths
    paths=$(jq -r --arg name "$instance_name" '.instances[$name].paths // []' "$paths_registry")
    
    # Check if instance has any paths
    if [ "$paths" = "[]" ]; then
        echo "No host paths are mapped for instance '$instance_name'."
        return 0
    fi
    
    # Display paths
    echo "Host paths mapped for instance '$instance_name':"
    jq -r --arg name "$instance_name" '.instances[$name].paths[]' "$paths_registry" | 
    while read -r path; do
        echo "  - $path"
    done
    
    return 0
}

# Get host paths for an instance (for use in sandbox creation)
get_host_paths() {
    local instance_name="$1"
    
    # Initialize registry
    local paths_registry="${CMGR_HOME}/host_paths_registry.json"
    initialize_host_paths_registry "$instance_name"
    
    # Return paths as JSON array
    jq -r --arg name "$instance_name" '.instances[$name].paths // []' "$paths_registry"
}

# Clean up host paths for an instance
cleanup_host_paths() {
    local instance_name="$1"
    
    # Initialize registry
    local paths_registry="${CMGR_HOME}/host_paths_registry.json"
    initialize_host_paths_registry "$instance_name"
    
    # Remove instance from registry
    jq --arg name "$instance_name" 'del(.instances[$name])' "$paths_registry" > "${paths_registry}.tmp" && \
    mv "${paths_registry}.tmp" "$paths_registry"
    
    return 0
}
