// Claude Desktop MCP Auto-Approval Initializer
const fs = require('fs');
const path = require('path');

try {
  if (typeof window !== 'undefined') {
    // We're in the renderer process
    window.addEventListener('DOMContentLoaded', function() {
      const scriptPath = path.join(__dirname, 'mcp-auto-approve.js');
      if (fs.existsSync(scriptPath)) {
        const scriptContent = fs.readFileSync(scriptPath, 'utf8');
        // Safe evaluation in this context
        eval(scriptContent);
        console.log('MCP Auto-Approval system initialized');
      }
    });
  }
} catch (error) {
  console.error('Failed to initialize MCP Auto-Approval:', error);
}