#!/usr/bin/env python3
"""MCP port allocation and management"""

import os
import json
import socket

class PortManager:
    """Manages port allocation for MCP servers"""
    
    # Base port for MCP servers
    MCP_BASE_PORT = 9000
    # Range size per instance
    MCP_PORT_RANGE = 100
    
    def __init__(self):
        # Get CMGR_HOME from environment or use default
        self.cmgr_home = os.environ.get("CMGR_HOME", os.path.expanduser("~/.cmgr"))
        self.port_registry_path = os.path.join(self.cmgr_home, "port_registry.json")
        
        # Initialize registry if needed
        self._initialize_registry()
        
    def _initialize_registry(self):
        """Initialize port registry if it doesn't exist"""
        if not os.path.exists(self.port_registry_path):
            try:
                os.makedirs(os.path.dirname(self.port_registry_path), exist_ok=True)
                with open(self.port_registry_path, 'w') as f:
                    json.dump({"allocated_ports": {}}, f, indent=2)
            except Exception as e:
                print(f"Error initializing port registry: {e}")
                
    def _load_registry(self):
        """Load port registry"""
        try:
            if not os.path.exists(self.port_registry_path):
                return {"allocated_ports": {}}
                
            with open(self.port_registry_path, 'r') as f:
                registry = json.load(f)
                
            return registry
        except Exception as e:
            print(f"Error loading port registry: {e}")
            return {"allocated_ports": {}}
            
    def _save_registry(self, registry):
        """Save port registry"""
        try:
            with open(self.port_registry_path, 'w') as f:
                json.dump(registry, f, indent=2)
            return True
        except Exception as e:
            print(f"Error saving port registry: {e}")
            return False
            
    def get_port_base(self, instance_name):
        """Get base port for an instance"""
        registry = self._load_registry()
        allocated_ports = registry.get("allocated_ports", {})
        
        # Check if instance already has a port base
        if instance_name in allocated_ports:
            return int(allocated_ports[instance_name])
            
        # Allocate a new port base
        return self.allocate_port_range(instance_name)
        
    def allocate_port_range(self, instance_name):
        """Allocate a port range for an instance"""
        registry = self._load_registry()
        allocated_ports = registry.get("allocated_ports", {})
        
        # Check if instance already has a port base
        if instance_name in allocated_ports:
            return int(allocated_ports[instance_name])
            
        # Find next available port base
        base_port = self._find_next_port_base()
        
        # Add to registry
        allocated_ports[instance_name] = base_port
        registry["allocated_ports"] = allocated_ports
        self._save_registry(registry)
        
        return base_port
        
    def _find_next_port_base(self):
        """Find next available port base"""
        registry = self._load_registry()
        allocated_ports = registry.get("allocated_ports", {})
        
        # Get highest currently allocated port
        highest_port = self.MCP_BASE_PORT
        for port in allocated_ports.values():
            highest_port = max(highest_port, int(port))
            
        # Start with the next port range
        next_base = highest_port + self.MCP_PORT_RANGE
        
        # Verify ports are available
        for i in range(10):
            port_base = next_base + (i * self.MCP_PORT_RANGE)
            if self._check_port_range_available(port_base):
                return port_base
                
        # If no good range found, return the next port anyway
        return next_base
        
    def _check_port_range_available(self, port_base):
        """Check if a port range is available by testing key ports"""
        test_ports = [
            port_base + 10,  # filesystem
            port_base + 20,  # sequential-thinking
            port_base + 30,  # memory
            port_base + 40   # desktop-commander
        ]
        
        for port in test_ports:
            if not self._is_port_available(port):
                return False
                
        return True
        
    def _is_port_available(self, port):
        """Check if a port is available"""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(0.5)
                result = s.connect_ex(('127.0.0.1', port))
                return result != 0  # If result is 0, port is in use
        except:
            return False  # Assume port is in use on error
            
    def get_tool_port(self, instance_name, tool_name):
        """Get port for a specific tool"""
        base_port = self.get_port_base(instance_name)
        
        # Calculate port offset based on tool name
        offsets = {
            "filesystem": 10,
            "sequential-thinking": 20,
            "memory": 30,
            "desktop-commander": 40,
            "repl": 50,
            "@executeautomation-playwright-mcp-server": 60
        }
        
        offset = offsets.get(tool_name, 90)  # Default to 90 if not in predefined list
        return base_port + offset
        
    def release_port_range(self, instance_name):
        """Release port range for an instance"""
        registry = self._load_registry()
        allocated_ports = registry.get("allocated_ports", {})
        
        if instance_name in allocated_ports:
            del allocated_ports[instance_name]
            registry["allocated_ports"] = allocated_ports
            self._save_registry(registry)
            return True
            
        return False
