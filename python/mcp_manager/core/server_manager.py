#!/usr/bin/env python3
"""MCP Server process management"""

import os
import signal
import subprocess
import json
import time
from pathlib import Path
import logging
from PyQt5.QtCore import QObject, pyqtSignal

class ServerManager(QObject):
    """Manages MCP server processes"""
    
    # Signals
    server_started = pyqtSignal(str)  # server_name
    server_stopped = pyqtSignal(str)  # server_name
    server_output = pyqtSignal(str, str)  # server_name, output
    
    def __init__(self, registry):
        super().__init__()
        self.registry = registry
        self.servers = {}  # instance_name -> {server_name -> process}
        self.server_logs = {}  # instance_name -> {server_name -> [log lines]}
        
    def get_port_from_args(self, args):
        """Extract port from arguments list"""
        try:
            port_index = args.index("--port") + 1
            if port_index < len(args):
                return int(args[port_index])
        except (ValueError, IndexError):
            pass
        return 0
        
    def start_server(self, instance_name, server_name):
        """Start a specific MCP server for an instance"""
        # Make sure instance dict exists
        if instance_name not in self.servers:
            self.servers[instance_name] = {}
            self.server_logs[instance_name] = {}
            
        # Check if server is already running
        if server_name in self.servers[instance_name]:
            process = self.servers[instance_name][server_name]
            if process.poll() is None:
                print(f"Server {server_name} is already running for {instance_name}")
                return True
                
        # Get MCP configuration
        config = self.registry.get_instance_mcp_config(instance_name)
        if not config or "mcpServers" not in config or server_name not in config["mcpServers"]:
            print(f"No configuration found for {server_name} in {instance_name}")
            return False
            
        server_config = config["mcpServers"][server_name]
        command = server_config.get("command", "npx")
        args = server_config.get("args", [])
        
        # Get port from arguments
        port = self.get_port_from_args(args)
        
        # Set up environment variables
        env = os.environ.copy()
        for key, value in server_config.get("env", {}).items():
            env[key] = value
            
        env["MCP_PORT"] = str(port)
        env["MCP_SERVER_PORT"] = str(port)
        env["CLAUDE_INSTANCE"] = instance_name
        
        # Start the process
        try:
            full_command = [command] + args
            print(f"Starting {server_name} server for {instance_name} with command: {' '.join(full_command)}")
            
            process = subprocess.Popen(
                full_command,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            self.servers[instance_name][server_name] = process
            self.server_logs[instance_name][server_name] = []
            
            print(f"Started {server_name} server with PID {process.pid}")
            self.server_started.emit(server_name)
            return True
        except Exception as e:
            print(f"Failed to start {server_name} server: {e}")
            return False
            
    def stop_server(self, instance_name, server_name):
        """Stop a specific MCP server"""
        if instance_name not in self.servers or server_name not in self.servers[instance_name]:
            print(f"Server {server_name} is not running for {instance_name}")
            return False
            
        process = self.servers[instance_name][server_name]
        if process.poll() is None:
            try:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=1)
                    
                print(f"Stopped {server_name} server for {instance_name}")
                self.server_stopped.emit(server_name)
                return True
            except Exception as e:
                print(f"Error stopping {server_name} server: {e}")
                return False
        
        # Remove from tracking
        del self.servers[instance_name][server_name]
        return True
        
    def start_all_servers(self, instance_name):
        """Start all configured MCP servers for an instance"""
        config = self.registry.get_instance_mcp_config(instance_name)
        if not config or "mcpServers" not in config:
            print(f"No MCP servers configured for {instance_name}")
            return False
            
        server_names = config["mcpServers"].keys()
        success = True
        
        for server_name in server_names:
            server_config = config["mcpServers"][server_name]
            # Only auto-start if configured
            if server_config.get("autoStart", False):
                success = success and self.start_server(instance_name, server_name)
                
        return success
        
    def stop_all_servers(self, instance_name):
        """Stop all running MCP servers for an instance"""
        if instance_name not in self.servers:
            return True
            
        success = True
        for server_name in list(self.servers[instance_name].keys()):
            success = success and self.stop_server(instance_name, server_name)
            
        return success
        
    def is_server_running(self, instance_name, server_name):
        """Check if a specific server is running"""
        if instance_name not in self.servers or server_name not in self.servers[instance_name]:
            return False
            
        process = self.servers[instance_name][server_name]
        return process.poll() is None
        
    def get_running_servers(self, instance_name):
        """Get list of running servers for an instance"""
        if instance_name not in self.servers:
            return []
            
        return [
            server_name for server_name, process in self.servers[instance_name].items()
            if process.poll() is None
        ]
        
    def get_server_log(self, instance_name, server_name):
        """Get log output for a server"""
        if (instance_name not in self.server_logs or 
            server_name not in self.server_logs[instance_name]):
            return []
            
        return self.server_logs[instance_name][server_name]
        
    def update_server_logs(self):
        """Update logs from running servers"""
        for instance_name, instance_servers in self.servers.items():
            for server_name, process in instance_servers.items():
                if process.poll() is None:  # Only read from running processes
                    self._read_process_output(instance_name, server_name, process)
                    
    def _read_process_output(self, instance_name, server_name, process):
        """Read available output from a process"""
        while True:
            line = self._read_line_nonblock(process)
            if not line:
                break
                
            if instance_name not in self.server_logs:
                self.server_logs[instance_name] = {}
                
            if server_name not in self.server_logs[instance_name]:
                self.server_logs[instance_name][server_name] = []
                
            self.server_logs[instance_name][server_name].append(line)
            # Keep log size reasonable
            if len(self.server_logs[instance_name][server_name]) > 1000:
                self.server_logs[instance_name][server_name] = self.server_logs[instance_name][server_name][-1000:]
                
            self.server_output.emit(server_name, line)
            
    def _read_line_nonblock(self, process):
        """Read a line from process output without blocking"""
        # Check if process is still running and has data available
        import select
        if process.stdout in select.select([process.stdout], [], [], 0)[0]:
            line = process.stdout.readline()
            if line:
                return line.strip()
        return None
        
    def deploy_template(self, instance_name, template, port=0):
        """Deploy a template to an instance"""
        config = self.registry.get_instance_mcp_config(instance_name)
        if not config:
            config = {
                "showTray": True, 
                "electronInitScript": "/home/claude/.config/Claude/electron/preload.js"
            }
            
        if "mcpServers" not in config:
            config["mcpServers"] = {}
            
        # Apply template
        server_name = template.server_name
        config["mcpServers"][server_name] = template.get_config(port)
        
        # Save config
        return self.registry.save_instance_mcp_config(instance_name, config)
