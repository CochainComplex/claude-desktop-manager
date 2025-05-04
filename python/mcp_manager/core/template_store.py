#!/usr/bin/env python3
"""Store for MCP server templates"""

import os
import json
from pathlib import Path

class ServerTemplate:
    """Template for an MCP server configuration"""
    
    def __init__(self, name, server_name, command, args, env=None, auto_start=False):
        self.name = name
        self.server_name = server_name
        self.command = command
        self.args = args if isinstance(args, list) else args.split()
        self.env = env or {}
        self.auto_start = auto_start
        
    def get_config(self, port=0):
        """Get server configuration dictionary"""
        # Create a copy of args to avoid modifying the original
        args = list(self.args)
        
        # Replace port placeholder if needed
        if "--port" in args and port > 0:
            port_index = args.index("--port") + 1
            if port_index < len(args):
                args[port_index] = str(port)
        
        return {
            "command": self.command,
            "args": args,
            "autoStart": self.auto_start,
            "env": dict(self.env)  # Make a copy
        }
        
    @classmethod
    def from_dict(cls, data):
        """Create template from dictionary"""
        return cls(
            name=data.get("name", "Unknown"),
            server_name=data.get("server_name", ""),
            command=data.get("command", "npx"),
            args=data.get("args", []),
            env=data.get("env", {}),
            auto_start=data.get("auto_start", False)
        )

class TemplateStore:
    """Stores and manages MCP server templates"""
    
    def __init__(self):
        # Get CMGR_HOME from environment or use default
        self.cmgr_home = os.environ.get("CMGR_HOME", os.path.expanduser("~/.cmgr"))
        self.templates_dir = os.path.join(self.cmgr_home, "templates")
        self.templates_file = os.path.join(self.templates_dir, "mcp_templates.json")
        
        # Ensure directories exist
        os.makedirs(self.templates_dir, exist_ok=True)
        
        # Load templates
        self.templates = self._load_templates()
        
        # Add built-in templates if no templates exist
        if not self.templates:
            self._add_builtins()
            
    def _load_templates(self):
        """Load templates from file"""
        try:
            if not os.path.exists(self.templates_file):
                return []
                
            with open(self.templates_file, 'r') as f:
                templates_data = json.load(f)
                
            return [ServerTemplate.from_dict(data) for data in templates_data]
        except Exception as e:
            print(f"Error loading templates: {e}")
            return []
            
    def _save_templates(self):
        """Save templates to file"""
        try:
            templates_data = [
                {
                    "name": t.name,
                    "server_name": t.server_name,
                    "command": t.command,
                    "args": t.args,
                    "env": t.env,
                    "auto_start": t.auto_start
                }
                for t in self.templates
            ]
            
            with open(self.templates_file, 'w') as f:
                json.dump(templates_data, f, indent=2)
                
            return True
        except Exception as e:
            print(f"Error saving templates: {e}")
            return False
            
    def _add_builtins(self):
        """Add built-in templates for standard MCP tools"""
        built_ins = [
            ServerTemplate(
                name="Filesystem",
                server_name="filesystem",
                command="npx",
                args=["-y", "@modelcontextprotocol/filesystem", "--port", "0"],
                env={"HOME": "/home/claude"},
                auto_start=True
            ),
            ServerTemplate(
                name="Sequential Thinking",
                server_name="sequential-thinking",
                command="npx",
                args=["-y", "@modelcontextprotocol/sequential-thinking", "--port", "0"],
                env={"HOME": "/home/claude"},
                auto_start=True
            ),
            ServerTemplate(
                name="Memory",
                server_name="memory",
                command="npx",
                args=["-y", "@modelcontextprotocol/memory", "--port", "0"],
                env={"HOME": "/home/claude"},
                auto_start=False
            ),
            ServerTemplate(
                name="Desktop Commander",
                server_name="desktop-commander",
                command="npx",
                args=["-y", "@modelcontextprotocol/desktop-commander", "--port", "0"],
                env={"HOME": "/home/claude"},
                auto_start=True
            ),
            ServerTemplate(
                name="REPL",
                server_name="repl",
                command="npx",
                args=["-y", "@modelcontextprotocol/repl", "--port", "0"],
                env={"HOME": "/home/claude"},
                auto_start=False
            ),
            ServerTemplate(
                name="Playwright",
                server_name="@executeautomation-playwright-mcp-server",
                command="npx",
                args=["-y", "@executeautomation/playwright-mcp-server", "--port", "0"],
                env={"HOME": "/home/claude"},
                auto_start=False
            )
        ]
        
        for template in built_ins:
            self.add_template(template)
            
    def get_all_templates(self):
        """Get all templates"""
        return self.templates
        
    def get_template(self, name):
        """Get template by name"""
        for template in self.templates:
            if template.name == name:
                return template
        return None
        
    def get_template_by_server_name(self, server_name):
        """Get template by server name"""
        for template in self.templates:
            if template.server_name == server_name:
                return template
        return None
        
    def add_template(self, template):
        """Add a new template"""
        # Check if template with same name already exists
        existing = self.get_template(template.name)
        if existing:
            # Replace existing template
            self.templates.remove(existing)
            
        self.templates.append(template)
        self._save_templates()
        return True
        
    def remove_template(self, name):
        """Remove a template"""
        template = self.get_template(name)
        if template:
            self.templates.remove(template)
            self._save_templates()
            return True
        return False
