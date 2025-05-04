#!/usr/bin/env python3
"""Instance view panel for displaying and controlling MCP servers for an instance"""

from PyQt5.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, 
    QLabel, QGroupBox, QTreeWidget, QTreeWidgetItem,
    QTextEdit, QSplitter, QMenu, QAction
)
from PyQt5.QtCore import Qt, QTimer, pyqtSignal
from PyQt5.QtGui import QIcon, QColor

class InstanceView(QWidget):
    """Panel showing running MCP servers for an instance"""
    
    # Signals
    server_selected = pyqtSignal(str)  # server_name
    
    def __init__(self, registry, server_manager, port_manager):
        super().__init__()
        self.registry = registry
        self.server_manager = server_manager
        self.port_manager = port_manager
        self.current_instance = None
        
        # Update timer
        self.update_timer = QTimer(self)
        self.update_timer.timeout.connect(self.update_server_status)
        self.update_timer.start(1000)  # Update every second
        
        # Set up UI
        self.init_ui()
        
    def init_ui(self):
        """Initialize the UI"""
        layout = QVBoxLayout(self)
        
        # Instance info section
        self.info_group = QGroupBox("Instance Information")
        info_layout = QVBoxLayout(self.info_group)
        
        self.instance_name_label = QLabel("No instance selected")
        self.instance_name_label.setStyleSheet("font-weight: bold")
        info_layout.addWidget(self.instance_name_label)
        
        self.instance_status_label = QLabel("Status: Unknown")
        info_layout.addWidget(self.instance_status_label)
        
        self.instance_path_label = QLabel("Path: ")
        info_layout.addWidget(self.instance_path_label)
        
        # Buttons
        btn_layout = QHBoxLayout()
        
        self.start_instance_btn = QPushButton("Start Instance")
        self.start_instance_btn.clicked.connect(self.start_instance)
        
        self.stop_instance_btn = QPushButton("Stop Instance")
        self.stop_instance_btn.clicked.connect(self.stop_instance)
        
        btn_layout.addWidget(self.start_instance_btn)
        btn_layout.addWidget(self.stop_instance_btn)
        info_layout.addLayout(btn_layout)
        
        layout.addWidget(self.info_group)
        
        # Server tree
        self.servers_group = QGroupBox("MCP Servers")
        servers_layout = QVBoxLayout(self.servers_group)
        
        self.server_tree = QTreeWidget()
        self.server_tree.setHeaderLabels(["Server", "Status", "Port"])
        self.server_tree.setContextMenuPolicy(Qt.CustomContextMenu)
        self.server_tree.customContextMenuRequested.connect(self.show_context_menu)
        self.server_tree.itemClicked.connect(self.on_server_clicked)
        servers_layout.addWidget(self.server_tree)
        
        # Server control buttons
        server_btn_layout = QHBoxLayout()
        
        self.start_server_btn = QPushButton("Start Server")
        self.start_server_btn.clicked.connect(self.start_selected_server)
        
        self.stop_server_btn = QPushButton("Stop Server")
        self.stop_server_btn.clicked.connect(self.stop_selected_server)
        
        server_btn_layout.addWidget(self.start_server_btn)
        server_btn_layout.addWidget(self.stop_server_btn)
        servers_layout.addLayout(server_btn_layout)
        
        layout.addWidget(self.servers_group)
        
        # Log view
        self.log_group = QGroupBox("Server Log")
        log_layout = QVBoxLayout(self.log_group)
        
        self.log_view = QTextEdit()
        self.log_view.setReadOnly(True)
        log_layout.addWidget(self.log_view)
        
        layout.addWidget(self.log_group)
        
        # Set initial state
        self.clear()
        
    def clear(self):
        """Clear the view"""
        self.current_instance = None
        self.instance_name_label.setText("No instance selected")
        self.instance_status_label.setText("Status: Unknown")
        self.instance_path_label.setText("Path: ")
        self.server_tree.clear()
        self.log_view.clear()
        
        # Disable buttons
        self.start_instance_btn.setEnabled(False)
        self.stop_instance_btn.setEnabled(False)
        self.start_server_btn.setEnabled(False)
        self.stop_server_btn.setEnabled(False)
        
    def load_instance(self, instance_name):
        """Load an instance"""
        self.current_instance = instance_name
        
        # Get instance data
        instance_data = self.registry.get_instance(instance_name)
        if not instance_data:
            self.clear()
            return
            
        # Update info section
        self.instance_name_label.setText(f"Instance: {instance_name}")
        
        # Check if instance is running
        is_running = self.registry.is_instance_running(instance_name)
        status_text = "Running" if is_running else "Stopped"
        self.instance_status_label.setText(f"Status: {status_text}")
        
        # Update path
        sandbox_path = instance_data.get("sandbox_path", "")
        self.instance_path_label.setText(f"Path: {sandbox_path}")
        
        # Enable buttons based on state
        self.start_instance_btn.setEnabled(not is_running)
        self.stop_instance_btn.setEnabled(is_running)
        
        # Load MCP servers
        self.load_servers(instance_name)
        
    def load_servers(self, instance_name):
        """Load MCP servers for an instance"""
        self.server_tree.clear()
        
        # Get MCP configuration
        config = self.registry.get_instance_mcp_config(instance_name)
        if not config or "mcpServers" not in config:
            return
            
        # Add each server to the tree
        for server_name, server_config in config["mcpServers"].items():
            # Get port
            port = 0
            args = server_config.get("args", [])
            try:
                port_index = args.index("--port") + 1
                if port_index < len(args):
                    port = args[port_index]
            except (ValueError, IndexError):
                pass
                
            # Fallback to port manager
            if port == 0 or port == "0":
                port = self.port_manager.get_tool_port(instance_name, server_name)
                
            # Check if server is running
            is_running = self.server_manager.is_server_running(instance_name, server_name)
            status = "Running" if is_running else "Stopped"
            
            # Create tree item
            item = QTreeWidgetItem([server_name, status, str(port)])
            if is_running:
                item.setForeground(1, QColor("green"))
            else:
                item.setForeground(1, QColor("red"))
                
            self.server_tree.addTopLevelItem(item)
            
        # Resize columns
        self.server_tree.resizeColumnToContents(0)
        self.server_tree.resizeColumnToContents(1)
        
    def refresh_current_instance(self):
        """Refresh the current instance view"""
        if self.current_instance:
            self.load_instance(self.current_instance)
            
    def start_instance(self):
        """Start the current instance"""
        if not self.current_instance:
            return
            
        # Run cmgr command
        result = self.registry.run_cmgr_command("start", self.current_instance)
        if result:
            self.refresh_current_instance()
            
    def stop_instance(self):
        """Stop the current instance"""
        if not self.current_instance:
            return
            
        # Run cmgr command
        result = self.registry.run_cmgr_command("stop", self.current_instance)
        if result:
            self.refresh_current_instance()
            
    def start_selected_server(self):
        """Start the selected server"""
        selected_items = self.server_tree.selectedItems()
        if not selected_items or not self.current_instance:
            return
            
        server_name = selected_items[0].text(0)
        if self.server_manager.start_server(self.current_instance, server_name):
            self.refresh_current_instance()
            
    def stop_selected_server(self):
        """Stop the selected server"""
        selected_items = self.server_tree.selectedItems()
        if not selected_items or not self.current_instance:
            return
            
        server_name = selected_items[0].text(0)
        if self.server_manager.stop_server(self.current_instance, server_name):
            self.refresh_current_instance()
            
    def update_server_status(self):
        """Update server status and logs"""
        if not self.current_instance:
            return
            
        # Check if instance status has changed
        is_running = self.registry.is_instance_running(self.current_instance)
        status_text = "Running" if is_running else "Stopped"
        self.instance_status_label.setText(f"Status: {status_text}")
        
        # Update buttons
        self.start_instance_btn.setEnabled(not is_running)
        self.stop_instance_btn.setEnabled(is_running)
        
        # Update server manager logs
        self.server_manager.update_server_logs()
        
        # Update server status in tree
        root = self.server_tree.invisibleRootItem()
        for i in range(root.childCount()):
            item = root.child(i)
            server_name = item.text(0)
            
            is_server_running = self.server_manager.is_server_running(
                self.current_instance, server_name)
            
            status = "Running" if is_server_running else "Stopped"
            item.setText(1, status)
            
            if is_server_running:
                item.setForeground(1, QColor("green"))
            else:
                item.setForeground(1, QColor("red"))
                
        # Enable/disable server buttons based on selection
        selected_items = self.server_tree.selectedItems()
        if selected_items:
            server_name = selected_items[0].text(0)
            is_server_running = self.server_manager.is_server_running(
                self.current_instance, server_name)
            
            self.start_server_btn.setEnabled(not is_server_running)
            self.stop_server_btn.setEnabled(is_server_running)
            
            # Update log for selected server
            if is_server_running:
                self.update_log_view(server_name)
        else:
            self.start_server_btn.setEnabled(False)
            self.stop_server_btn.setEnabled(False)
            
    def update_log_view(self, server_name):
        """Update log view with latest logs for selected server"""
        if not self.current_instance:
            return
            
        logs = self.server_manager.get_server_log(self.current_instance, server_name)
        if not logs:
            return
            
        # Check if we need to update
        log_text = self.log_view.toPlainText()
        last_log = logs[-1] if logs else ""
        
        # Only update if there are new logs to avoid flickering
        if not log_text or not log_text.endswith(last_log):
            self.log_view.clear()
            self.log_view.setPlainText("\n".join(logs))
            # Scroll to bottom
            cursor = self.log_view.textCursor()
            cursor.movePosition(cursor.End)
            self.log_view.setTextCursor(cursor)
            
    def on_server_clicked(self, item):
        """Handle click on server item"""
        server_name = item.text(0)
        self.server_selected.emit(server_name)
        
        # Update buttons
        is_running = self.server_manager.is_server_running(self.current_instance, server_name)
        self.start_server_btn.setEnabled(not is_running)
        self.stop_server_btn.setEnabled(is_running)
        
        # Clear log view
        self.log_view.clear()
        
    def show_context_menu(self, position):
        """Show context menu for server item"""
        selected_items = self.server_tree.selectedItems()
        if not selected_items or not self.current_instance:
            return
            
        server_name = selected_items[0].text(0)
        is_running = self.server_manager.is_server_running(self.current_instance, server_name)
        
        # Create menu
        menu = QMenu(self)
        
        if is_running:
            stop_action = QAction("Stop Server", self)
            stop_action.triggered.connect(self.stop_selected_server)
            menu.addAction(stop_action)
        else:
            start_action = QAction("Start Server", self)
            start_action.triggered.connect(self.start_selected_server)
            menu.addAction(start_action)
            
        menu.addSeparator()
        
        configure_action = QAction("Configure Server", self)
        configure_action.triggered.connect(lambda: self.server_selected.emit(server_name))
        menu.addAction(configure_action)
        
        # Show menu
        menu.exec_(self.server_tree.viewport().mapToGlobal(position))
