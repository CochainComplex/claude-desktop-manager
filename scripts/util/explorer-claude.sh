#!/bin/bash
# Claude Desktop Explorer - Utility script to download, extract, and investigate
# Claude Desktop Windows app structure
#
# This script will:
# 1. Download the Claude Desktop Windows installer
# 2. Extract the installer contents
# 3. Find and extract the app.asar file
# 4. Explore the structure and key files within app.asar
# 5. Search for version information in relevant files

set -euo pipefail

# Create working directory
WORK_DIR="$(mktemp -d -t claude-explorer-XXXXXXXX)"
cd "$WORK_DIR"
echo "Working directory: $WORK_DIR"

# Download Claude Desktop Windows Installer
CLAUDE_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
CLAUDE_EXE="Claude-Setup-x64.exe"

echo "Downloading Claude Desktop Windows installer..."
wget -O "$CLAUDE_EXE" "$CLAUDE_URL" || curl -L -o "$CLAUDE_EXE" "$CLAUDE_URL"
echo "✅ Download complete"

# Check if 7z is installed
if ! command -v 7z &> /dev/null; then
    echo "❌ 7z is required but not found. Please install p7zip-full with:"
    echo "   sudo apt install p7zip-full"
    exit 1
fi

# Extract installer contents
echo "Extracting installer contents..."
7z x -y "$CLAUDE_EXE"
echo "✅ Installer extracted"

# Find and extract the .nupkg file
echo "Looking for the package file..."
NUPKG_FILE=$(find . -name "*.nupkg" | grep -i "AnthropicClaude" | head -1)

if [ -z "$NUPKG_FILE" ]; then
    # Fallback: try to find any .nupkg file
    NUPKG_FILE=$(find . -name "*.nupkg" | head -1)
fi

if [ -z "$NUPKG_FILE" ]; then
    echo "❌ Failed to find any .nupkg file after extraction"
    exit 1
fi

echo "Found package file: $NUPKG_FILE"
7z x -y "$NUPKG_FILE"
echo "✅ Package extracted"

# Find app.asar file
echo "Looking for app.asar file..."
APP_ASAR=$(find . -name "app.asar" | grep -v "app.asar.unpacked" | head -1)

if [ -z "$APP_ASAR" ]; then
    echo "❌ app.asar not found. Showing available files:"
    find . -type f -name "*.asar" || echo "No asar files found"
    exit 1
fi

echo "Found app.asar at: $APP_ASAR"

# Check if asar is installed, otherwise use npx
ASAR_CMD="asar"
if ! command -v asar &> /dev/null; then
    echo "asar command not found, using npx instead"
    ASAR_CMD="npx asar"
    
    # Check if npx/nodejs is installed
    if ! command -v npx &> /dev/null; then
        echo "❌ Neither asar nor npx is available. Installing nodejs/npm..."
        sudo apt update && sudo apt install -y nodejs npm
    fi
fi

# Create extraction directory for app.asar
mkdir -p "app-extract"
$ASAR_CMD extract "$APP_ASAR" "app-extract"
echo "✅ app.asar extracted to app-extract/"

# Print extracted app structure
echo -e "\n📁 Extracted app.asar structure:"
find app-extract -type f -name "*.js" | sort

# Check for package.json files and print their content
echo -e "\n📄 Found package.json files:"
find app-extract -name "package.json" -exec echo {} \; -exec cat {} \; -exec echo -e "\n---\n" \;

# Search for version information in various files
echo -e "\n🔍 Searching for version information in files..."
grep -r "version" --include="*.json" --include="*.js" app-extract | grep -v "node_modules" | head -20

# Specifically look for files with "about" in the name
echo -e "\n📄 Looking for about.js or similar files:"
find app-extract -type f -name "*about*" | while read -r file; do
    echo -e "\nFile: $file"
    cat "$file"
    echo -e "\n---"
done

# Check for any hardcoded version numbers
echo -e "\n🔍 Checking for specific version patterns (e.g., 0.9.2, 0.9.3):"
grep -r "0\.9\.[0-9]" --include="*.json" --include="*.js" app-extract | grep -v "node_modules" || echo "No specific version patterns found"

# Look in main.js and similar important files
echo -e "\n📄 Examining main process files:"
MAIN_FILES=$(find app-extract -name "main.js" -o -name "electron.js" -o -name "app.js")
for file in $MAIN_FILES; do
    echo -e "\nFile: $file"
    grep -n "version\|Version\|getVersion" "$file" || echo "No version information found in $file"
    echo -e "\n---"
done

# Create a summary report
echo -e "\n📋 Summary Report:"
echo "1. Installer downloaded from: $CLAUDE_URL"
echo "2. app.asar location: $APP_ASAR"
echo "3. Package structure examined - see above for details"
echo "4. Working directory with all extracted files: $WORK_DIR"
echo -e "\nThe version information appears to be managed through:"
echo "- package.json for the app version"
echo "- Possibly through electron-updater or custom version management"

# Give instructions on how to further investigate
echo -e "\n🔍 Next Steps for Investigation:"
echo "1. Examine the package.json file for version information"
echo "2. Look at how the About dialog is implemented"
echo "3. Check any updater logic in the main process files"
echo "4. Run the following to get a complete file list:"
echo "   find \"$WORK_DIR/app-extract\" -type f | sort > file_list.txt"
echo -e "\nYou can also manually explore the files at: $WORK_DIR"

# Keep the extracted files for further investigation
echo -e "\n✅ Script completed. Files have been preserved in $WORK_DIR for manual inspection."
echo "When you're done investigating, you can remove them with:"
echo "rm -rf \"$WORK_DIR\""
