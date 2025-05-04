#!/usr/bin/env python3
"""Main window for the MCP Server Manager"""

import os
import json
from PyQt5.QtWidgets import (
    QMainWindow, QTabWidget, QWidget, QVBoxLayout, 
    QComboBox, QPushButton, QLabel, QSplitter,
    QHBoxLayout, QMessageBox, QAction, QStatusBar,
    QDialog, QDialogButtonBox, QFormLayout
)
from PyQt5.QtCore import Qt, QSettings
from PyQt5.QtGui import QIcon

from mcp_manager.core.registry import InstanceRegistry
from mcp_manager.core.template_store import TemplateStore
from mcp_manager.core.server_manager import ServerManager
from mcp_manager.core.port_manager import PortManager
from mcp_manager.ui.instance_view import InstanceView
from mcp_manager.ui.server_panel import ServerPanel
from mcp_manager.ui.templates_panel import TemplatesPanel

class MainWindow(QMainWindow):
    """Main window for the MCP Server Manager"""
    
    def __init__(self):
        super().__init__()
        self.settings = QSettings("ClaudeDesktopManager", "MCPManager")
        
        # Core components
        self.registry = InstanceRegistry()
        self.template_store = TemplateStore()
        self.port_manager = PortManager()
        self.server_manager = ServerManager(self.registry)
        
        # UI setup
        self.init_ui()
        
        # Load instances
        self.load_instances()
        
    def init_ui(self):
        """Initialize the UI"""
        self.setWindowTitle("Claude Desktop MCP Manager")
        self.setMinimumSize(1000, 700)
        
        # Main widget and layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        
        # Top bar with instance selector
        top_bar = QWidget()
        top_layout = QHBoxLayout(top_bar)
        top_layout.setContentsMargins(5, 5, 5, 5)
        
        instance_label = QLabel("Select Instance:")
        self.instance_selector = QComboBox()
        self.instance_selector.setMinimumWidth(200)
        self.instance_selector.currentIndexChanged.connect(self.on_instance_changed)
        
        refresh_btn = QPushButton("Refresh Instances")
        refresh_btn.clicked.connect(self.load_instances)
        
        top_layout.addWidget(instance_label)
        top_layout.addWidget(self.instance_selector)
        top_layout.addStretch(1)
        top_layout.addWidget(refresh_btn)
        
        main_layout.addWidget(top_bar)
        
        # Main content - splitter with panels
        self.splitter = QSplitter(Qt.Horizontal)
        
        # Left panel - Instance view (running servers)
        self.instance_view = InstanceView(self.registry, self.server_manager, self.port_manager)
        self.splitter.addWidget(self.instance_view)
        
        # Right panel - Tabbed interface
        tabs = QTabWidget()
        
        # MCP Server configuration tab
        self.server_panel = ServerPanel(
            self.registry, 
            self.template_store, 
            self.server_manager,
            self.port_manager
        )
        tabs.addTab(self.server_panel, "MCP Servers")
        
        # Templates tab
        self.templates_panel = TemplatesPanel(self.template_store)
        self.templates_panel.template_updated.connect(self.server_panel.refresh_templates)
        tabs.addTab(self.templates_panel, "Server Templates")
        
        self.splitter.addWidget(tabs)
        self.splitter.setSizes([400, 600])  # Set initial sizes
        
        main_layout.addWidget(self.splitter)
        
        # Status bar
        self.statusBar().showMessage("Ready")
        
        # Menu
        self.create_menus()
        
        # Set up connections
        self.instance_view.server_selected.connect(self.server_panel.load_server)
        self.server_panel.config_saved.connect(self.instance_view.refresh_current_instance)
        
    def create_menus(self):
        """Create application menus"""
        menubar = self.menuBar()
        
        # File menu
        file_menu = menubar.addMenu("&File")
        
        refresh_action = QAction("&Refresh Instances", self)
        refresh_action.setShortcut("F5")
        refresh_action.triggered.connect(self.load_instances)
        file_menu.addAction(refresh_action)
        
        file_menu.addSeparator()
        
        exit_action = QAction("E&xit", self)
        exit_action.setShortcut("Ctrl+Q")
        exit_action.triggered.connect(self.close)
        file_menu.addAction(exit_action)
        
        # Tools menu
        tools_menu = menubar.addMenu("&Tools")
        
        deploy_action = QAction("&Deploy Template to All Instances", self)
        deploy_action.triggered.connect(self.deploy_template_to_all)
        tools_menu.addAction(deploy_action)
        
        tools_menu.addSeparator()
        
        start_all_action = QAction("Start &All Servers", self)
        start_all_action.triggered.connect(self.start_all_servers)
        tools_menu.addAction(start_all_action)
        
        stop_all_action = QAction("Stop A&ll Servers", self)
        stop_all_action.triggered.connect(self.stop_all_servers)
        tools_menu.addAction(stop_all_action)
        
    def load_instances(self):
        """Load all Claude Desktop instances from registry"""
        self.instance_selector.clear()
        instances = self.registry.get_all_instances()
        
        if not instances:
            self.statusBar().showMessage("No Claude Desktop instances found")
            self.instance_selector.setEnabled(False)
            self.instance_view.clear()
            self.server_panel.set_instance(None)
            return
        
        self.instance_selector.setEnabled(True)
        for instance_name in sorted(instances):
            self.instance_selector.addItem(instance_name)
        
        # Try to restore last selected instance
        last_instance = self.settings.value("last_instance", "")
        index = self.instance_selector.findText(last_instance)
        if index >= 0:
            self.instance_selector.setCurrentIndex(index)
        else:
            self.instance_selector.setCurrentIndex(0)
            
    def on_instance_changed(self, index):
        """Handle instance selection change"""
        if index < 0:
            return
            
        instance_name = self.instance_selector.currentText()
        self.statusBar().showMessage(f"Loaded instance: {instance_name}")
        
        # Save as last selected instance
        self.settings.setValue("last_instance", instance_name)
        
        # Load instance data
        instance_data = self.registry.get_instance(instance_name)
        if not instance_data:
            return
            
        # Update panels
        self.instance_view.load_instance(instance_name)
        self.server_panel.set_instance(instance_name)
        
    def deploy_template_to_all(self):
        """Deploy selected template to all instances"""
        # Get templates
        templates = self.template_store.get_all_templates()
        if not templates:
            QMessageBox.information(self, "No Templates", 
                                   "No server templates available to deploy.")
            return
        
        # Create dialog
        dialog = QDialog(self)
        dialog.setWindowTitle("Deploy Template")
        layout = QVBoxLayout(dialog)
        
        form = QFormLayout()
        template_combo = QComboBox()
        for template in templates:
            template_combo.addItem(template.name)
        form.addRow("Select template:", template_combo)
        layout.addLayout(form)
        
        # Buttons
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(dialog.accept)
        buttons.rejected.connect(dialog.reject)
        layout.addWidget(buttons)
        
        # Show dialog
        if dialog.exec_() != QDialog.Accepted:
            return
            
        template_name = template_combo.currentText()
        template = self.template_store.get_template(template_name)
        if not template:
            return
            
        # Deploy to all instances
        instances = self.registry.get_all_instances()
        count = 0
        
        for instance_name in instances:
            # Get port for this instance/server
            port = self.port_manager.get_tool_port(instance_name, template.server_name)
            
            # Deploy template with port
            if self.server_manager.deploy_template(instance_name, template, port):
                count += 1
                
        QMessageBox.information(self, "Deployment Complete", 
                               f"Template '{template_name}' deployed to {count} instances.")
        
        # Refresh current instance view
        self.instance_view.refresh_current_instance()
    
    def start_all_servers(self):
        """Start all servers for the current instance"""
        instance_name = self.instance_selector.currentText()
        if not instance_name:
            return
            
        if self.server_manager.start_all_servers(instance_name):
            self.statusBar().showMessage(f"Started all servers for {instance_name}")
        else:
            self.statusBar().showMessage(f"Error starting servers for {instance_name}")
            
        # Refresh view
        self.instance_view.refresh_current_instance()
    
    def stop_all_servers(self):
        """Stop all servers for the current instance"""
        instance_name = self.instance_selector.currentText()
        if not instance_name:
            return
            
        if self.server_manager.stop_all_servers(instance_name):
            self.statusBar().showMessage(f"Stopped all servers for {instance_name}")
        else:
            self.statusBar().showMessage(f"Error stopping servers for {instance_name}")
            
        # Refresh view
        self.instance_view.refresh_current_instance()
