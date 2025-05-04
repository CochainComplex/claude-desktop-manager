#!/usr/bin/env python3
"""Access to cmgr instance registry and configurations"""

import os
import json
import subprocess
from pathlib import Path

class InstanceRegistry:
    """Handles access to cmgr instance registry and configurations"""
    
    def __init__(self):
        # Get CMGR_HOME from environment or use default
        self.cmgr_home = os.environ.get("CMGR_HOME", os.path.expanduser("~/.cmgr"))
        self.registry_path = os.path.join(self.cmgr_home, "registry.json")
        self.sandbox_base = os.environ.get("SANDBOX_BASE", os.path.expanduser("~/sandboxes"))
        
    def get_all_instances(self):
        """Get list of all registered instance names"""
        try:
            if not os.path.exists(self.registry_path):
                return []
                
            with open(self.registry_path, 'r') as f:
                registry = json.load(f)
                
            return list(registry.get("instances", {}).keys())
        except Exception as e:
            print(f"Error reading registry: {e}")
            return []
            
    def get_instance(self, instance_name):
        """Get instance data by name"""
        try:
            if not os.path.exists(self.registry_path):
                return None
                
            with open(self.registry_path, 'r') as f:
                registry = json.load(f)
                
            return registry.get("instances", {}).get(instance_name)
        except Exception as e:
            print(f"Error getting instance {instance_name}: {e}")
            return None
            
    def get_instance_config_path(self, instance_name):
        """Get path to instance MCP config file"""
        sandbox_home = os.path.join(self.sandbox_base, instance_name)
        return os.path.join(sandbox_home, ".config", "Claude", "claude_desktop_config.json")
        
    def get_instance_mcp_config(self, instance_name):
        """Get MCP configuration for an instance"""
        config_path = self.get_instance_config_path(instance_name)
        
        try:
            if not os.path.exists(config_path):
                return None
                
            with open(config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading MCP config for {instance_name}: {e}")
            return None
        
    def save_instance_mcp_config(self, instance_name, config_data):
        """Save MCP configuration for an instance"""
        config_path = self.get_instance_config_path(instance_name)
        
        try:
            # Create parent directory if it doesn't exist
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            
            with open(config_path, 'w') as f:
                json.dump(config_data, f, indent=2)
            return True
        except Exception as e:
            print(f"Error saving MCP config for {instance_name}: {e}")
            return False
            
    def is_instance_running(self, instance_name):
        """Check if instance is running by looking for bubblewrap process"""
        try:
            result = subprocess.run(
                ["pgrep", "-f", f"bubblewrap.*{instance_name}"],
                capture_output=True, text=True
            )
            
            return result.returncode == 0 and result.stdout.strip() != ""
        except Exception as e:
            print(f"Error checking if instance {instance_name} is running: {e}")
            return False
            
    def run_cmgr_command(self, command, instance_name, *args):
        """Run a cmgr command for an instance"""
        cmd = ["cmgr", command, instance_name]
        cmd.extend(args)
        
        try:
            return subprocess.run(cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            print(f"Error running cmgr {command} for {instance_name}: {e}")
            print(f"stderr: {e.stderr}")
            return None
