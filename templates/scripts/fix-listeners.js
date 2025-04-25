// Node.js script to patch Electron app code to fix MaxListenersExceededWarning
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Function to find .asar files (Electron app archives)
function findAsarFiles(startPath) {
  console.log(`Searching for asar files in: ${startPath}`);
  let results = [];
  
  try {
    // Check if the directory exists
    if (!fs.existsSync(startPath)) {
      console.log(`Directory not found: ${startPath}`);
      return results;
    }
    
    const files = fs.readdirSync(startPath);
    
    for (let file of files) {
      const filename = path.join(startPath, file);
      const stat = fs.lstatSync(filename);
      
      if (stat.isDirectory()) {
        // Recursively search directories
        results = results.concat(findAsarFiles(filename));
      } else if (filename.endsWith('.asar')) {
        // Found an asar file
        console.log(`Found asar file: ${filename}`);
        results.push(filename);
      }
    }
  } catch (error) {
    console.error(`Error searching directory ${startPath}:`, error);
  }
  
  return results;
}

// Main function to patch app files
async function patchAppFiles() {
  const appDir = process.argv[2] || process.cwd();
  console.log(`Starting app patching process in: ${appDir}`);
  
  try {
    // Find all asar files
    const asarFiles = findAsarFiles(appDir);
    
    if (asarFiles.length === 0) {
      console.log('No .asar files found. Trying to find loose app files...');
      
      // Try to find main process files directly
      const mainJsFiles = findMainJsFiles(appDir);
      
      if (mainJsFiles.length > 0) {
        for (const mainJsFile of mainJsFiles) {
          patchMainFile(mainJsFile);
        }
      } else {
        console.log('Could not find any main process files to patch.');
      }
      
      // Also look for electron.js, main.js, etc.
      const appFiles = [
        path.join(appDir, 'electron.js'),
        path.join(appDir, 'main.js'),
        path.join(appDir, 'app.js'),
        path.join(appDir, 'background.js'),
        path.join(appDir, 'dist', 'electron.js'),
        path.join(appDir, 'dist', 'main.js')
      ];
      
      for (const file of appFiles) {
        if (fs.existsSync(file)) {
          console.log(`Found app file: ${file}`);
          patchMainFile(file);
        }
      }
      
      return;
    }
    
    // Process each asar file
    for (const asarFile of asarFiles) {
      await processAsarFile(asarFile);
    }
    
    console.log('Patching process completed!');
  } catch (error) {
    console.error('Error in patching process:', error);
  }
}

// Find main.js files directly in the file system
function findMainJsFiles(startPath) {
  console.log(`Searching for main process JS files in: ${startPath}`);
  let results = [];
  
  try {
    if (!fs.existsSync(startPath)) {
      return results;
    }
    
    const files = fs.readdirSync(startPath);
    
    for (let file of files) {
      const filename = path.join(startPath, file);
      const stat = fs.lstatSync(filename);
      
      if (stat.isDirectory()) {
        results = results.concat(findMainJsFiles(filename));
      } else if (
        file === 'main.js' || 
        file === 'electron.js' || 
        file === 'background.js' ||
        file === 'app.js'
      ) {
        console.log(`Found potential main process file: ${filename}`);
        results.push(filename);
      }
    }
  } catch (error) {
    console.error(`Error searching directory ${startPath}:`, error);
  }
  
  return results;
}

// Process an asar file
async function processAsarFile(asarFile) {
  console.log(`Processing asar file: ${asarFile}`);
  
  // Create extraction directory
  const extractDir = `${asarFile}-extracted`;
  if (fs.existsSync(extractDir)) {
    console.log(`Removing existing extraction directory: ${extractDir}`);
    fs.rmSync(extractDir, { recursive: true, force: true });
  }
  
  fs.mkdirSync(extractDir, { recursive: true });
  
  try {
    // Extract asar file
    console.log(`Extracting asar to: ${extractDir}`);
    execSync(`npx asar extract "${asarFile}" "${extractDir}"`);
    
    // Find main.js files
    const mainJsFiles = findMainJsFiles(extractDir);
    
    if (mainJsFiles.length === 0) {
      console.log(`No main process files found in ${asarFile}`);
      return;
    }
    
    // Patch each main file
    for (const mainJsFile of mainJsFiles) {
      patchMainFile(mainJsFile);
    }
    
    // Re-pack the asar file
    console.log(`Repacking asar file: ${asarFile}`);
    
    // Create backup of original asar
    const backupFile = `${asarFile}.bak`;
    if (!fs.existsSync(backupFile)) {
      fs.copyFileSync(asarFile, backupFile);
      console.log(`Created backup of original asar: ${backupFile}`);
    }
    
    execSync(`npx asar pack "${extractDir}" "${asarFile}"`);
    console.log(`Repacked asar file: ${asarFile}`);
    
    // Clean up
    fs.rmSync(extractDir, { recursive: true, force: true });
    console.log(`Removed extraction directory: ${extractDir}`);
  } catch (error) {
    console.error(`Error processing asar file ${asarFile}:`, error);
  }
}

// Patch a main process file
function patchMainFile(filePath) {
  console.log(`Patching file: ${filePath}`);
  
  try {
    let content = fs.readFileSync(filePath, 'utf8');
    
    // Check if file already patched
    if (content.includes('// CMGR PATCH: MaxListenersExceededWarning fix')) {
      console.log(`File ${filePath} already patched. Skipping.`);
      return;
    }
    
    // Add patching code at the beginning of the file
    const patch = `
// CMGR PATCH: MaxListenersExceededWarning fix
const events = require('events');
events.EventEmitter.defaultMaxListeners = 30;

// Patch WebContents to increase listeners
const { app, webContents } = require('electron');
app.on('web-contents-created', (event, contents) => {
  contents.setMaxListeners(30);
});

// Patch any emitter creation
const originalEmit = events.EventEmitter.prototype.emit;
events.EventEmitter.prototype.emit = function(type, ...args) {
  if (type === 'newListener' && this.listenerCount('newListener') === 0) {
    this.setMaxListeners(30);
  }
  return originalEmit.apply(this, [type, ...args]);
};

console.log('CMGR: Applied MaxListenersExceededWarning fix');

`;
    
    // Insert the patch at the beginning of the file
    content = patch + content;
    
    // Write the patched file
    fs.writeFileSync(filePath, content);
    console.log(`Successfully patched ${filePath}`);
  } catch (error) {
    console.error(`Error patching file ${filePath}:`, error);
  }
}

// Run the patching process
patchAppFiles();
