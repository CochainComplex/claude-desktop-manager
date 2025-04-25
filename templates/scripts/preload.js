// Enhanced preload.js - Fixes for common issues in Claude Desktop
// This script runs in the Electron process context

// Log that preload script is running
console.log('CMGR: Enhanced preload script initializing');

// Fix for MaxListenersExceededWarning
if (typeof process !== 'undefined') {
  try {
    const events = require('events');
    
    // Increase max listeners to a higher value (default is 10)
    events.EventEmitter.defaultMaxListeners = 30;
    console.log('CMGR: Set default max listeners to 30');
    
    // Patch individual emitters when they're created
    const originalEmit = events.EventEmitter.prototype.emit;
    events.EventEmitter.prototype.emit = function(type, ...args) {
      if (type === 'newListener' && this.listenerCount('newListener') === 0) {
        // When a new emitter gets its first listener, increase its limit
        if (this.setMaxListeners) {
          this.setMaxListeners(30);
        }
      }
      return originalEmit.apply(this, [type, ...args]);
    };
    
    // Load electron conditionally
    let electron;
    try {
      electron = require('electron');
      
      // Handle WebContents specifically
      if (electron.app) {
        // This runs in the main process
        console.log('CMGR: Running in main process, patching app.on(web-contents-created)');
        
        // Patch app when web contents are created
        electron.app.on('web-contents-created', (event, contents) => {
          console.log('CMGR: New WebContents created, increasing its max listeners');
          contents.setMaxListeners(30);
        });
      } else if (electron.remote && electron.remote.app) {
        // This runs in the renderer process with remote module
        console.log('CMGR: Running in renderer with remote, patching remote.app');
        
        electron.remote.app.on('web-contents-created', (event, contents) => {
          contents.setMaxListeners(30);
        });
      }
    } catch (electronError) {
      console.log('CMGR: Electron module not available in this context:', electronError.message);
    }
    
    console.log('CMGR: EventEmitter patching complete');
  } catch (error) {
    console.error('CMGR: Error patching EventEmitter:', error);
  }
}

// Get the instance name from environment variable
let instanceName = '';
if (typeof process !== 'undefined' && process.env && process.env.CLAUDE_INSTANCE) {
  instanceName = process.env.CLAUDE_INSTANCE;
  console.log('CMGR: Instance name detected:', instanceName);
}

// Set the window title to include the instance name
if (typeof window !== 'undefined' && instanceName) {
  // Function to update the title
  const updateTitle = () => {
    const originalTitle = document.title;
    
    // Only update if the title doesn't already contain our instance name
    if (!originalTitle.includes(`[${instanceName}]`)) {
      document.title = `${originalTitle} [${instanceName}]`;
      console.log('CMGR: Updated window title to:', document.title);
    }
  };
  
  // Update immediately if the document is already loaded
  if (document.readyState === 'complete') {
    updateTitle();
  }
  
  // Otherwise wait for the document to load
  window.addEventListener('load', updateTitle);
  
  // Set up a MutationObserver to detect title changes
  const titleObserver = new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
      if (document.title && !document.title.includes(`[${instanceName}]`)) {
        updateTitle();
      }
    });
  });
  
  // Start observing the title element once it exists
  const observeTitleElement = () => {
    const titleElement = document.querySelector('title');
    if (titleElement) {
      titleObserver.observe(titleElement, { childList: true, subtree: true });
      console.log('CMGR: Title observer attached');
    } else {
      // If title element doesn't exist yet, try again later
      setTimeout(observeTitleElement, 500);
    }
  };
  
  // Start looking for the title element
  setTimeout(observeTitleElement, 500);
  
  // Also observe the document body for changes that might affect the title
  const bodyObserver = new MutationObserver(() => {
    updateTitle();
  });
  
  // Start observing once the body exists
  if (document.body) {
    bodyObserver.observe(document.body, { childList: true, subtree: true });
  } else {
    window.addEventListener('DOMContentLoaded', () => {
      bodyObserver.observe(document.body, { childList: true, subtree: true });
    });
  }
}

// Suppress specific warnings by overriding console.warn
if (typeof console !== 'undefined') {
  const originalWarn = console.warn;
  console.warn = function(...args) {
    // Check if this is a MaxListenersExceededWarning
    if (args[0] && typeof args[0] === 'string' && 
        (args[0].includes('MaxListenersExceededWarning') || 
         args[0].includes('Possible EventEmitter memory leak'))) {
      // Suppress this warning
      return;
    }
    
    // Pass through other warnings
    return originalWarn.apply(this, args);
  };
  
  console.log('CMGR: Console warnings for MaxListenersExceededWarning suppressed');
}

// Print a reminder at the end for verification
console.log('CMGR: Preload script initialization complete!');
