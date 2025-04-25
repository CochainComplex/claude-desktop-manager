// preload.js - Script to fix common issues in Claude Desktop
// This script runs in the Electron process context

// Fix for MaxListenersExceededWarning
if (typeof process !== 'undefined') {
  const events = require('events');
  
  // Increase max listeners to a higher value (20 is often too low)
  events.EventEmitter.defaultMaxListeners = 30;
  
  // Patch individual emitters when they're created
  const originalEmit = events.EventEmitter.prototype.emit;
  events.EventEmitter.prototype.emit = function(type, ...args) {
    if (type === 'newListener' && this.listenerCount('newListener') === 0) {
      // When a WebContents object is created, increase its limit
      if (this.constructor && this.constructor.name === 'WebContents') {
        this.setMaxListeners(30);
      }
    }
    return originalEmit.apply(this, [type, ...args]);
  };

  console.log('Claude Desktop Manager: Preload script initialized - EventEmitter patched');
}

// Expose the script status to the window object so the renderer can verify it loaded
if (typeof window !== 'undefined') {
  window.claudeDesktopManager = {
    preloadLoaded: true,
    version: '0.2.0'
  };
}
