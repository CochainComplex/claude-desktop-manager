#!/usr/bin/env python3
"""Templates panel for managing MCP server templates"""

from PyQt5.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, 
    QLabel, QGroupBox, QFormLayout, QLineEdit,
    QTextEdit, QListWidget, QListWidgetItem, QMessageBox,
    QDialog, QDialogButtonBox, QCheckBox
)
from PyQt5.QtCore import Qt, pyqtSignal

from mcp_manager.core.template_store import ServerTemplate

class TemplatesPanel(QWidget):
    """Panel for managing MCP server templates"""
    
    # Signals
    template_updated = pyqtSignal()  # Emitted when a template is added, updated, or removed
    
    def __init__(self, template_store):
        super().__init__()
        self.template_store = template_store
        self.current_template = None
        self.init_ui()
        
    def init_ui(self):
        """Initialize the UI"""
        layout = QHBoxLayout(self)
        
        # Left panel - template list
        list_panel = QWidget()
        list_layout = QVBoxLayout(list_panel)
        
        list_label = QLabel("Available Templates:")
        list_layout.addWidget(list_label)
        
        self.template_list = QListWidget()
        self.template_list.currentItemChanged.connect(self.on_template_selected)
        list_layout.addWidget(self.template_list)
        
        # Template list buttons
        btn_layout = QHBoxLayout()
        
        self.add_btn = QPushButton("New Template")
        self.add_btn.clicked.connect(self.create_template)
        
        self.delete_btn = QPushButton("Delete")
        self.delete_btn.clicked.connect(self.delete_template)
        self.delete_btn.setEnabled(False)
        
        btn_layout.addWidget(self.add_btn)
        btn_layout.addWidget(self.delete_btn)
        list_layout.addLayout(btn_layout)
        
        layout.addWidget(list_panel, 1)
        
        # Right panel - template editor
        editor_panel = QWidget()
        editor_layout = QVBoxLayout(editor_panel)
        
        # Template details section
        details_group = QGroupBox("Template Details")
        details_layout = QFormLayout(details_group)
        
        # Template name
        self.name_edit = QLineEdit()
        details_layout.addRow("Template Name:", self.name_edit)
        
        # Server name
        self.server_name_edit = QLineEdit()
        details_layout.addRow("Server Name:", self.server_name_edit)
        
        # Command
        self.command_edit = QLineEdit()
        self.command_edit.setText("npx")
        details_layout.addRow("Command:", self.command_edit)
        
        # Arguments
        self.args_edit = QLineEdit()
        details_layout.addRow("Arguments:", self.args_edit)
        
        # Auto-start
        self.auto_start_check = QCheckBox("Start server automatically with Claude")
        details_layout.addRow("", self.auto_start_check)
        
        # Environment variables
        self.env_edit = QTextEdit()
        self.env_edit.setMaximumHeight(100)
        self.env_edit.setPlaceholderText("One variable per line, format: KEY=VALUE")
        details_layout.addRow("Environment Variables:", self.env_edit)
        
        editor_layout.addWidget(details_group)
        
        # Editor buttons
        editor_btn_layout = QHBoxLayout()
        
        self.save_btn = QPushButton("Save Template")
        self.save_btn.clicked.connect(self.save_template)
        self.save_btn.setEnabled(False)
        
        self.revert_btn = QPushButton("Revert Changes")
        self.revert_btn.clicked.connect(self.load_template)
        self.revert_btn.setEnabled(False)
        
        editor_btn_layout.addWidget(self.save_btn)
        editor_btn_layout.addWidget(self.revert_btn)
        
        editor_layout.addLayout(editor_btn_layout)
        editor_layout.addStretch(1)
        
        layout.addWidget(editor_panel, 2)
        
        # Load templates
        self.load_templates()
        
    def load_templates(self):
        """Load templates into the list"""
        self.template_list.clear()
        
        templates = self.template_store.get_all_templates()
        for template in sorted(templates, key=lambda t: t.name):
            item = QListWidgetItem(template.name)
            item.setData(Qt.UserRole, template.name)  # Store template name as data
            self.template_list.addItem(item)
            
    def on_template_selected(self, current, previous):
        """Handle template selection change"""
        if not current:
            self.current_template = None
            self.clear_form()
            self.save_btn.setEnabled(False)
            self.revert_btn.setEnabled(False)
            self.delete_btn.setEnabled(False)
            return
            
        template_name = current.data(Qt.UserRole)
        self.current_template = template_name
        self.load_template()
        
        self.save_btn.setEnabled(True)
        self.revert_btn.setEnabled(True)
        self.delete_btn.setEnabled(True)
        
    def clear_form(self):
        """Clear the form"""
        self.name_edit.clear()
        self.server_name_edit.clear()
        self.command_edit.setText("npx")
        self.args_edit.clear()
        self.auto_start_check.setChecked(False)
        self.env_edit.clear()
        
    def load_template(self):
        """Load the selected template"""
        if not self.current_template:
            return
            
        template = self.template_store.get_template(self.current_template)
        if not template:
            return
            
        # Load template data into form
        self.name_edit.setText(template.name)
        self.server_name_edit.setText(template.server_name)
        self.command_edit.setText(template.command)
        self.args_edit.setText(" ".join(template.args))
        self.auto_start_check.setChecked(template.auto_start)
        
        # Format environment variables
        env_text = "\n".join([f"{k}={v}" for k, v in template.env.items()])
        self.env_edit.setPlainText(env_text)
        
    def save_template(self):
        """Save the current template"""
        name = self.name_edit.text().strip()
        server_name = self.server_name_edit.text().strip()
        command = self.command_edit.text().strip()
        args_text = self.args_edit.text().strip()
        auto_start = self.auto_start_check.isChecked()
        
        # Validate
        if not name:
            QMessageBox.warning(self, "Invalid Template", 
                               "Template name cannot be empty.")
            return
            
        if not server_name:
            QMessageBox.warning(self, "Invalid Template", 
                               "Server name cannot be empty.")
            return
            
        if not command:
            QMessageBox.warning(self, "Invalid Template", 
                               "Command cannot be empty.")
            return
            
        # Parse arguments
        args = args_text.split() if args_text else []
        
        # Parse environment variables
        env = {}
        for line in self.env_edit.toPlainText().strip().split("\n"):
            line = line.strip()
            if not line:
                continue
                
            if "=" in line:
                key, value = line.split("=", 1)
                env[key.strip()] = value.strip()
                
        # Create template
        template = ServerTemplate(
            name=name,
            server_name=server_name,
            command=command,
            args=args,
            env=env,
            auto_start=auto_start
        )
        
        # Check if name changed and it's a new template
        is_new = (not self.current_template) or (name != self.current_template)
        
        # Save template
        if self.template_store.add_template(template):
            # If name changed, select the new template
            if is_new:
                self.load_templates()
                # Select the newly added template
                for i in range(self.template_list.count()):
                    item = self.template_list.item(i)
                    if item.text() == name:
                        self.template_list.setCurrentItem(item)
                        break
            
            self.current_template = name
            self.template_updated.emit()  # Emit signal so other components know a template was updated
            QMessageBox.information(self, "Template Saved", 
                                   f"Template '{name}' saved successfully.")
        else:
            QMessageBox.warning(self, "Save Failed", 
                               "Failed to save template.")
        
    def create_template(self):
        """Create a new template"""
        self.current_template = None
        self.clear_form()
        self.save_btn.setEnabled(True)
        self.revert_btn.setEnabled(False)
        self.delete_btn.setEnabled(False)
        
        # Set focus to name field
        self.name_edit.setFocus()
        
    def delete_template(self):
        """Delete the current template"""
        if not self.current_template:
            return
            
        # Confirm deletion
        reply = QMessageBox.question(
            self, "Confirm Deletion",
            f"Are you sure you want to delete template '{self.current_template}'?",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )
        
        if reply != QMessageBox.Yes:
            return
            
        # Delete template
        if self.template_store.remove_template(self.current_template):
            self.load_templates()
            self.clear_form()
            self.current_template = None
            self.save_btn.setEnabled(False)
            self.revert_btn.setEnabled(False)
            self.delete_btn.setEnabled(False)
            self.template_updated.emit()  # Emit signal so other components know a template was removed
        else:
            QMessageBox.warning(self, "Delete Failed", 
                               "Failed to delete template.")
