// patch-app.js - Applies patches to Claude Desktop app.asar during installation
// Used by Claude Desktop Manager to customize instance name and fix warnings

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Get instance name and asar path from arguments
const instanceName = process.argv[2] || 'default';
const asarPath = process.argv[3];

if (!asarPath || !fs.existsSync(asarPath)) {
  console.error(`Error: app.asar not found at ${asarPath}`);
  process.exit(1);
}

console.log(`Patching app.asar for instance: ${instanceName}`);
console.log(`ASAR path: ${asarPath}`);

// Create extraction directory in a temp location in the user's home directory
const homeDir = process.env.HOME || '/tmp';
const tempDir = `${homeDir}/.cmgr/temp`;
fs.mkdirSync(tempDir, { recursive: true });

// Create a unique extraction directory for this instance
const extractionId = Date.now().toString(36) + Math.random().toString(36).substring(2);
const extractDir = `${tempDir}/app-extract-${instanceName}-${extractionId}`;

if (fs.existsSync(extractDir)) {
  console.log(`Removing existing extraction directory: ${extractDir}`);
  fs.rmSync(extractDir, { recursive: true, force: true });
}

fs.mkdirSync(extractDir, { recursive: true });

// Copy the asar file to our temp directory if it's in a system location
let asarWorkingPath = asarPath;
const needsElevatedPermissions = asarPath.startsWith('/usr/');

if (needsElevatedPermissions) {
  const tempAsarPath = path.join(tempDir, `app-${instanceName}.asar`);
  console.log(`Copying asar from system location to: ${tempAsarPath}`);
  fs.copyFileSync(asarPath, tempAsarPath);
  asarWorkingPath = tempAsarPath;
}

// Extract app.asar
try {
  console.log(`Extracting app.asar to: ${extractDir}`);
  execSync(`npx asar extract "${asarWorkingPath}" "${extractDir}"`);
} catch (error) {
  console.error(`Error extracting asar file: ${error.message}`);
  process.exit(1);
}

// Find main process files
const findMainProcessFiles = (dir) => {
  let results = [];
  
  try {
    const files = fs.readdirSync(dir);
    
    for (const file of files) {
      const filePath = path.join(dir, file);
      const stat = fs.lstatSync(filePath);
      
      if (stat.isDirectory()) {
        results = results.concat(findMainProcessFiles(filePath));
      } else if (
        file === 'main.js' || 
        file === 'electron.js' || 
        file === 'background.js' ||
        file === 'app.js'
      ) {
        console.log(`Found potential main process file: ${filePath}`);
        results.push(filePath);
      }
    }
  } catch (error) {
    console.error(`Error searching directory ${dir}:`, error);
  }
  
  return results;
};

const mainProcessFiles = findMainProcessFiles(extractDir);

if (mainProcessFiles.length === 0) {
  console.log(`No main process files found in ${extractDir}`);
  process.exit(1);
}

// Update package.json if it exists
try {
  const packageJsonPath = path.join(extractDir, 'package.json');
  if (fs.existsSync(packageJsonPath)) {
    console.log(`Updating package.json...`);
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    
    // Update app name with instance name
    if (packageJson.name) {
      packageJson.name = `claude-desktop-${instanceName}`;
    }
    
    // Update product name with instance name
    if (packageJson.productName) {
      packageJson.productName = `Claude (${instanceName})`;
    }
    
    // Write back updated package.json
    fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2));
    console.log(`Updated package.json with instance name: ${instanceName}`);
  }
} catch (error) {
  console.error(`Error updating package.json: ${error.message}`);
  // Continue even if package.json update fails
}

// Patch main process files
let patchedFiles = 0;
for (const filePath of mainProcessFiles) {
  try {
    console.log(`Patching file: ${filePath}`);
    
    // Backup the original file
    fs.copyFileSync(filePath, `${filePath}.bak`);
    
    // Read file content
    let content = fs.readFileSync(filePath, 'utf8');
    
    // Check if file already patched
    if (content.includes('// CMGR: Instance name customization') || 
        content.includes('// CMGR: MaxListenersExceededWarning fix')) {
      console.log(`File ${filePath} already patched. Skipping.`);
      continue;
    }
    
    // Create patch - simple and focused on the essential functionality
    const patch = `
// CMGR: MaxListenersExceededWarning fix
// CMGR: Instance name customization for ${instanceName}

// Fix EventEmitter memory leak warnings
const events = require('events');
events.EventEmitter.defaultMaxListeners = 30;

// Patch require to customize BrowserWindow titles
const originalModule = require('module');
const originalRequire = originalModule.prototype.require;

originalModule.prototype.require = function(path) {
  const result = originalRequire.apply(this, arguments);
  
  if (path === 'electron') {
    const electron = result;
    
    // Patch app for WebContents
    if (electron.app) {
      // Increase listeners for app
      if (electron.app.setMaxListeners) {
        electron.app.setMaxListeners(30);
      }
      
      // Patch WebContents when created
      electron.app.on('web-contents-created', (event, contents) => {
        if (contents.setMaxListeners) {
          contents.setMaxListeners(30);
        }
      });
    }
    
    // Customize BrowserWindow for instance name
    const originalBrowserWindow = electron.BrowserWindow;
    class CustomBrowserWindow extends originalBrowserWindow {
      constructor(options = {}) {
        // Add instance name to title
        if (options.title) {
          options.title = \`\${options.title} (${instanceName})\`;
        } else {
          options.title = \`Claude (${instanceName})\`;
        }
        
        // Call original constructor with modified options
        super(options);
        
        // Override setTitle to always include instance name
        const originalSetTitle = this.setTitle;
        this.setTitle = (title) => {
          if (!title.includes('(${instanceName})')) {
            return originalSetTitle.call(this, \`\${title} (${instanceName})\`);
          }
          return originalSetTitle.call(this, title);
        };
        
        // Increase max listeners
        if (this.setMaxListeners) {
          this.setMaxListeners(30);
        }
      }
    }
    
    // Replace BrowserWindow with our custom version
    electron.BrowserWindow = CustomBrowserWindow;
    
    return electron;
  }
  
  return result;
};

`;
    
    // Add the patch at the beginning of the file
    content = patch + content;
    
    // Write the modified content back to the file
    fs.writeFileSync(filePath, content);
    console.log(`Successfully patched ${filePath}`);
    patchedFiles++;
    
  } catch (error) {
    console.error(`Error patching file ${filePath}: ${error.message}`);
    // Continue with other files even if one fails
  }
}

if (patchedFiles === 0) {
  console.error('No files were patched. The installation customization failed.');
  process.exit(1);
}

// Repack the asar file
try {
  console.log(`Repacking app.asar...`);
  
  // Create backup of original asar in our temp directory
  const backupFileName = path.basename(asarPath) + '.original';
  const backupFile = `${tempDir}/${backupFileName}`;
  if (!fs.existsSync(backupFile)) {
    fs.copyFileSync(asarWorkingPath, backupFile);
    console.log(`Created backup of original asar: ${backupFile}`);
  }
  
  // Pack the modified files back into our working asar path
  const outputAsarPath = `${tempDir}/patched-${instanceName}.asar`;
  execSync(`npx asar pack "${extractDir}" "${outputAsarPath}"`); 
  
  if (needsElevatedPermissions) {
    // For system locations, we need to use sudo to copy back the file
    console.log(`Patched file created at: ${outputAsarPath}`);
    
    // Store the system path information for later use by apply-system-patches.sh
    const systemPathInfoFile = `${tempDir}/system-path-${instanceName}.txt`;
    fs.writeFileSync(systemPathInfoFile, asarPath);
    
    console.log(`System path information stored in: ${systemPathInfoFile}`);
    console.log(`To apply this patch to the system location, you can:`);
    console.log(`1. Run: sudo cp "${outputAsarPath}" "${asarPath}"`);
    console.log(`2. Or use: sudo $(which cmgr) apply-patches`);
  } else {
    // For user locations, we can directly copy the file back
    fs.copyFileSync(outputAsarPath, asarPath);
    console.log(`Successfully copied patched asar back to: ${asarPath}`);
  }
  
  console.log(`You can find the backup at: ${backupFile} if needed.`);
  console.log(`Successfully repacked app.asar`);
  
  // Clean up extraction directory
  fs.rmSync(extractDir, { recursive: true, force: true });
  console.log(`Removed extraction directory`);
  
  console.log(`Patching completed successfully!`);
} catch (error) {
  console.error(`Error repacking asar file: ${error.message}`);
  process.exit(1);
}
