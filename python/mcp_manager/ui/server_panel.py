#!/usr/bin/env python3
"""Server configuration panel for managing MCP servers"""

from PyQt5.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, 
    QLabel, QGroupBox, QFormLayout, QLineEdit,
    QTextEdit, QComboBox, QCheckBox, QMessageBox,
    QSpinBox
)
from PyQt5.QtCore import Qt, pyqtSignal

class ServerPanel(QWidget):
    """Panel for configuring MCP servers"""
    
    # Signals
    config_saved = pyqtSignal()
    
    def __init__(self, registry, template_store, server_manager, port_manager):
        super().__init__()
        self.registry = registry
        self.template_store = template_store
        self.server_manager = server_manager
        self.port_manager = port_manager
        
        self.current_instance = None
        self.current_server = None
        
        self.init_ui()
        
    def init_ui(self):
        """Initialize the UI"""
        layout = QVBoxLayout(self)
        
        # Server selection section
        selection_group = QGroupBox("Server Selection")
        selection_layout = QFormLayout(selection_group)
        
        # Template dropdown
        self.template_combo = QComboBox()
        self.refresh_templates()
        selection_layout.addRow("Server Template:", self.template_combo)
        
        # Apply template button
        apply_btn = QPushButton("Apply Template")
        apply_btn.clicked.connect(self.apply_template)
        selection_layout.addRow("", apply_btn)
        
        layout.addWidget(selection_group)
        
        # Server configuration section
        config_group = QGroupBox("Server Configuration")
        config_layout = QFormLayout(config_group)
        
        # Server name
        self.server_name_edit = QLineEdit()
        config_layout.addRow("Server Name:", self.server_name_edit)
        
        # Command
        self.command_edit = QLineEdit()
        self.command_edit.setText("npx")
        config_layout.addRow("Command:", self.command_edit)
        
        # Arguments
        self.args_edit = QLineEdit()
        config_layout.addRow("Arguments:", self.args_edit)
        
        # Port
        self.port_spin = QSpinBox()
        self.port_spin.setMinimum(0)
        self.port_spin.setMaximum(65535)
        config_layout.addRow("Port:", self.port_spin)
        
        # Auto-start
        self.auto_start_check = QCheckBox("Start server automatically with Claude")
        config_layout.addRow("", self.auto_start_check)
        
        # Environment variables
        self.env_edit = QTextEdit()
        self.env_edit.setMaximumHeight(100)
        self.env_edit.setPlaceholderText("One variable per line, format: KEY=VALUE")
        config_layout.addRow("Environment Variables:", self.env_edit)
        
        layout.addWidget(config_group)
        
        # Buttons
        button_layout = QHBoxLayout()
        
        self.save_btn = QPushButton("Save Configuration")
        self.save_btn.clicked.connect(self.save_config)
        
        self.start_btn = QPushButton("Save & Start Server")
        self.start_btn.clicked.connect(self.save_and_start)
        
        self.revert_btn = QPushButton("Revert Changes")
        self.revert_btn.clicked.connect(self.load_server)
        
        button_layout.addWidget(self.save_btn)
        button_layout.addWidget(self.start_btn)
        button_layout.addWidget(self.revert_btn)
        
        layout.addLayout(button_layout)
        
        # Add spacer
        layout.addStretch(1)
        
        # Disable controls initially
        self.set_controls_enabled(False)
        
    def refresh_templates(self):
        """Refresh the templates dropdown"""
        self.template_combo.clear()
        
        for template in self.template_store.get_all_templates():
            self.template_combo.addItem(template.name)
            
    def set_instance(self, instance_name):
        """Set the current instance"""
        self.current_instance = instance_name
        self.current_server = None
        
        # Enable/disable controls
        self.set_controls_enabled(instance_name is not None)
        
        # Clear form
        self.clear_form()
        
    def set_controls_enabled(self, enabled):
        """Enable or disable controls"""
        self.template_combo.setEnabled(enabled)
        self.server_name_edit.setEnabled(enabled)
        self.command_edit.setEnabled(enabled)
        self.args_edit.setEnabled(enabled)
        self.port_spin.setEnabled(enabled)
        self.auto_start_check.setEnabled(enabled)
        self.env_edit.setEnabled(enabled)
        self.save_btn.setEnabled(enabled)
        self.start_btn.setEnabled(enabled)
        self.revert_btn.setEnabled(enabled)
        
    def clear_form(self):
        """Clear the form"""
        self.server_name_edit.clear()
        self.command_edit.setText("npx")
        self.args_edit.clear()
        self.port_spin.setValue(0)
        self.auto_start_check.setChecked(False)
        self.env_edit.clear()
        
    def load_server(self, server_name=None):
        """Load a server configuration"""
        if not self.current_instance:
            return
            
        if server_name is not None:
            self.current_server = server_name
            
        if not self.current_server:
            self.clear_form()
            return
            
        # Get MCP configuration
        config = self.registry.get_instance_mcp_config(self.current_instance)
        if not config or "mcpServers" not in config or self.current_server not in config["mcpServers"]:
            # Server doesn't exist in config, try to get from template
            template = self.template_store.get_template_by_server_name(self.current_server)
            if template:
                port = self.port_manager.get_tool_port(self.current_instance, self.current_server)
                server_config = template.get_config(port)
                
                self.server_name_edit.setText(self.current_server)
                self.command_edit.setText(server_config.get("command", "npx"))
                self.args_edit.setText(" ".join(server_config.get("args", [])))
                self.port_spin.setValue(port)
                self.auto_start_check.setChecked(server_config.get("autoStart", False))
                
                # Format environment variables
                env_text = "\n".join([f"{k}={v}" for k, v in server_config.get("env", {}).items()])
                self.env_edit.setPlainText(env_text)
            else:
                self.clear_form()
                self.server_name_edit.setText(self.current_server)
            return
            
        # Load configuration
        server_config = config["mcpServers"][self.current_server]
        
        self.server_name_edit.setText(self.current_server)
        self.command_edit.setText(server_config.get("command", "npx"))
        self.args_edit.setText(" ".join(server_config.get("args", [])))
        
        # Get port from args
        port = 0
        args = server_config.get("args", [])
        try:
            port_index = args.index("--port") + 1
            if port_index < len(args):
                port = int(args[port_index])
        except (ValueError, IndexError):
            pass
            
        if port == 0:
            # Get port from port manager
            port = self.port_manager.get_tool_port(self.current_instance, self.current_server)
            
        self.port_spin.setValue(port)
        self.auto_start_check.setChecked(server_config.get("autoStart", False))
        
        # Format environment variables
        env_text = "\n".join([f"{k}={v}" for k, v in server_config.get("env", {}).items()])
        self.env_edit.setPlainText(env_text)
        
    def apply_template(self):
        """Apply selected template"""
        if not self.current_instance:
            return
            
        template_name = self.template_combo.currentText()
        if not template_name:
            return
            
        template = self.template_store.get_template(template_name)
        if not template:
            return
            
        # Apply template to form
        self.current_server = template.server_name
        self.server_name_edit.setText(template.server_name)
        self.command_edit.setText(template.command)
        self.args_edit.setText(" ".join(template.args))
        
        # Get port from port manager
        port = self.port_manager.get_tool_port(self.current_instance, template.server_name)
        self.port_spin.setValue(port)
        
        self.auto_start_check.setChecked(template.auto_start)
        
        # Format environment variables
        env_text = "\n".join([f"{k}={v}" for k, v in template.env.items()])
        self.env_edit.setPlainText(env_text)
        
    def save_config(self):
        """Save the current configuration"""
        if not self.current_instance:
            return False
            
        # Get server name
        server_name = self.server_name_edit.text().strip()
        if not server_name:
            QMessageBox.warning(self, "Invalid Configuration", 
                               "Server name cannot be empty.")
            return False
            
        # Get command
        command = self.command_edit.text().strip()
        if not command:
            QMessageBox.warning(self, "Invalid Configuration", 
                               "Command cannot be empty.")
            return False
            
        # Get arguments
        args_text = self.args_edit.text().strip()
        args = args_text.split() if args_text else []
        
        # Ensure --port argument is present and valid
        port = self.port_spin.value()
        
        # Validate port
        if port <= 0 or port > 65535:
            # Get port from port manager if the current one is invalid
            port = self.port_manager.get_tool_port(self.current_instance, server_name)
            
        # Update port in args
        if "--port" in args:
            port_index = args.index("--port") + 1
            if port_index < len(args):
                args[port_index] = str(port)
            else:
                args.append(str(port))
        else:
            args.extend(["--port", str(port)])
            
        # Parse environment variables
        env = {}
        for line in self.env_edit.toPlainText().strip().split("\n"):
            line = line.strip()
            if not line:
                continue
                
            if "=" in line:
                key, value = line.split("=", 1)
                env[key.strip()] = value.strip()
                
        # Create server configuration
        server_config = {
            "command": command,
            "args": args,
            "autoStart": self.auto_start_check.isChecked(),
            "env": env
        }
        
        # Get existing MCP configuration
        config = self.registry.get_instance_mcp_config(self.current_instance)
        if not config:
            config = {
                "showTray": True,
                "electronInitScript": "/home/claude/.config/Claude/electron/preload.js"
            }
            
        if "mcpServers" not in config:
            config["mcpServers"] = {}
            
        # Update configuration
        config["mcpServers"][server_name] = server_config
        
        # Save configuration
        if not self.registry.save_instance_mcp_config(self.current_instance, config):
            QMessageBox.warning(self, "Save Failed", 
                               "Failed to save MCP configuration.")
            return False
            
        # Update current server name if it changed
        self.current_server = server_name
        
        # Emit signal
        self.config_saved.emit()
        
        return True
        
    def save_and_start(self):
        """Save configuration and start the server"""
        if self.save_config():
            if self.server_manager.start_server(self.current_instance, self.current_server):
                QMessageBox.information(self, "Server Started", 
                                       f"Server '{self.current_server}' started successfully.")
                self.config_saved.emit()
            else:
                QMessageBox.warning(self, "Start Failed", 
                                   f"Failed to start server '{self.current_server}'.")
