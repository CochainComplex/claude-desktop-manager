// preload.js - Script to fix common issues in Claude Desktop
// This script runs in the Electron main process

process.on('loaded', () => {
  // Increase default max listeners to prevent warnings
  require('events').EventEmitter.defaultMaxListeners = 20;
  
  console.log('Claude Desktop Manager: Preload script initialized');
});
