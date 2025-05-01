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
echo "📦 Searching for .nupkg file..."

# First try looking inside the .rsrc directory if it exists
if [ -d "$EXTRACT_DIR/.rsrc/DATA" ]; then
    echo "Looking in .rsrc/DATA directory..."
    DATA_FILES=$(find "$EXTRACT_DIR/.rsrc/DATA" -type f -name "*" | sort)
    
    # Look through each data file for a zip format that might contain the nupkg
    for data_file in $DATA_FILES; do
        echo "Checking data file: $(basename "$data_file")"
        if file "$data_file" | grep -q "Zip archive"; then
            echo "Found ZIP format in data file: $(basename "$data_file")"
            if ! 7z x -y "$data_file" > /dev/null; then
                echo "⚠️ Warning: Failed to extract from $(basename "$data_file"), trying other methods"
            else
                echo "✓ Extracted ZIP data file successfully"
            fi
        fi
    done
fi

# Now look for any .nupkg files in the extract directory
NUPKG_FILE=$(find "$EXTRACT_DIR" -name "*.nupkg" | head -1)
if [ -z "$NUPKG_FILE" ]; then
    echo "⚠️ No .nupkg file found directly, looking for any zip format files that might contain it"
    
    # Try looking for zip files
    ZIP_FILES=$(find "$EXTRACT_DIR" -type f -exec file {} \; | grep "Zip archive" | cut -d":" -f1)
    for zip_file in $ZIP_FILES; do
        echo "Attempting to extract from potential zip file: $(basename "$zip_file")"
        if ! 7z x -y "$zip_file" > /dev/null; then
            echo "⚠️ Warning: Failed to extract from $(basename "$zip_file")"
        else
            echo "✓ Extracted zip file successfully"
        fi
    done
    
    # Check again for nupkg after extraction attempts
    NUPKG_FILE=$(find "$EXTRACT_DIR" -name "*.nupkg" | head -1)
    if [ -z "$NUPKG_FILE" ]; then
        echo "❌ Failed to find .nupkg file after multiple extraction attempts"
        exit 1
    fi
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