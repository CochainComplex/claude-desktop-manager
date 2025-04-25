#!/bin/bash
# Helper script to download and extract Claude Desktop Windows package
# This script downloads the Windows package and extracts it to /tmp/claude-desktop-raw
# Created for Claude Desktop Manager project

set -e

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"

# Create a dedicated folder in /tmp
EXTRACT_DIR="/tmp/claude-desktop-raw"
rm -rf "$EXTRACT_DIR" 2>/dev/null || true
mkdir -p "$EXTRACT_DIR"
cd "$EXTRACT_DIR"
echo "Working directory: $EXTRACT_DIR"

# Check dependencies
if ! command -v 7z &> /dev/null; then
    echo "❌ 7z (p7zip-full) is required but not found."
    echo "Please install with: sudo apt install p7zip-full"
    exit 1
fi

echo "📥 Downloading Claude Desktop installer..."
if ! wget -q --show-progress -O "$EXTRACT_DIR/Claude-Setup-x64.exe" "$CLAUDE_DOWNLOAD_URL"; then
    echo "❌ Failed to download Claude Desktop installer"
    exit 1
fi
echo "✓ Download complete"

# Extract resources
echo "📦 Extracting installer resources..."
if ! 7z x -y "$EXTRACT_DIR/Claude-Setup-x64.exe" > /dev/null; then
    echo "❌ Failed to extract installer"
    exit 1
fi

# Find and extract the .nupkg file
NUPKG_FILE=$(find "$EXTRACT_DIR" -name "*.nupkg" | head -1)
if [ -z "$NUPKG_FILE" ]; then
    echo "❌ Failed to find .nupkg file"
    exit 1
fi

echo "📦 Extracting .nupkg file: $(basename "$NUPKG_FILE")"
if ! 7z x -y "$NUPKG_FILE" > /dev/null; then
    echo "❌ Failed to extract .nupkg"
    exit 1
fi
echo "✓ Resources extracted"

# Create a specific directory for the app.asar files
mkdir -p "$EXTRACT_DIR/app_files"

# Copy app.asar to a more accessible location
if [ -f "lib/net45/resources/app.asar" ]; then
    echo "📦 Copying app.asar to app_files directory..."
    cp "lib/net45/resources/app.asar" "$EXTRACT_DIR/app_files/"
    
    # Copy unpacked resources if they exist
    if [ -d "lib/net45/resources/app.asar.unpacked" ]; then
        cp -r "lib/net45/resources/app.asar.unpacked" "$EXTRACT_DIR/app_files/"
        echo "✓ app.asar and app.asar.unpacked copied"
    else
        echo "✓ app.asar copied (app.asar.unpacked not found)"
    fi
else
    echo "❌ Could not find app.asar in the expected location"
    echo "Searching for app.asar in extracted files..."
    ASAR_FILES=$(find "$EXTRACT_DIR" -name "*.asar" -type f)
    if [ -n "$ASAR_FILES" ]; then
        for file in $ASAR_FILES; do
            echo "Found: $file"
            cp "$file" "$EXTRACT_DIR/app_files/$(basename "$file")"
        done
        echo "✓ Copied found .asar files to app_files directory"
    else
        echo "❌ No .asar files found"
    fi
fi

echo -e "\n✅ Claude Desktop raw files extracted to: $EXTRACT_DIR"
echo -e "Key locations:"
echo " - App files: $EXTRACT_DIR/app_files/"
echo " - Full Windows app: $EXTRACT_DIR/lib/net45/"
echo " - Resources: $EXTRACT_DIR/lib/net45/resources/"

# List main directories and files for reference
echo -e "\nImportant files:"
find "$EXTRACT_DIR/app_files" -type f | sort | xargs -n1 echo " - "

exit 0