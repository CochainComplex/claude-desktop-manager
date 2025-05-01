#!/bin/bash
# extract-claude-windows.sh - Extracts Claude Desktop Windows installer to prepare for Linux packaging
# This script is used by both the direct installer and the cmgr package builder

set -e

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
OUTPUT_DIR="/tmp/claude-desktop-raw"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --url=*)
      CLAUDE_DOWNLOAD_URL="${1#*=}"
      shift
      ;;
    --output=*)
      OUTPUT_DIR="${1#*=}"
      shift
      ;;
    --help)
      echo "Usage: $0 [--url=URL] [--output=DIR]"
      echo ""
      echo "Options:"
      echo "  --url=URL     Use a specific download URL for Claude Windows installer"
      echo "  --output=DIR  Output directory for extracted files (default: /tmp/claude-desktop-raw)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check for required commands
for cmd in wget 7z; do
  if ! command -v $cmd &> /dev/null; then
    echo "❌ Required command not found: $cmd"
    echo "Please install the missing dependencies and try again."
    exit 1
  fi
done

# Create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/app_files"

# Download Claude Windows installer
echo "📥 Downloading Claude Desktop Windows installer..."
CLAUDE_EXE="$OUTPUT_DIR/Claude-Setup-x64.exe"
if ! wget -O "$CLAUDE_EXE" "$CLAUDE_DOWNLOAD_URL"; then
    echo "❌ Failed to download Claude Desktop installer"
    exit 1
fi
echo "✓ Download complete"

# Extract resources
echo "📦 Extracting resources..."
cd "$OUTPUT_DIR"
if ! 7z x -y "$CLAUDE_EXE"; then
    echo "❌ Failed to extract installer"
    exit 1
fi

# Find and extract the nupkg file
NUPKG_FILE=$(find . -name "*.nupkg" | head -1)
if [ -z "$NUPKG_FILE" ]; then
    echo "❌ Could not find .nupkg file in extracted installer"
    exit 1
fi

if ! 7z x -y "$NUPKG_FILE"; then
    echo "❌ Failed to extract nupkg"
    exit 1
fi

# Move app.asar and related files to app_files directory
echo "Moving app.asar and related files to app_files directory..."
if [ -f "lib/net45/resources/app.asar" ]; then
    cp "lib/net45/resources/app.asar" "$OUTPUT_DIR/app_files/"
    if [ -d "lib/net45/resources/app.asar.unpacked" ]; then
        cp -r "lib/net45/resources/app.asar.unpacked" "$OUTPUT_DIR/app_files/"
    fi
    echo "✓ Copied app.asar and related files"
else
    echo "❌ app.asar not found in expected location"
    exit 1
fi

echo "✅ Extraction complete. Files available at: $OUTPUT_DIR"
echo "   - Windows installer: $CLAUDE_EXE"
echo "   - app.asar: $OUTPUT_DIR/app_files/app.asar"

# Output the location for other scripts to use
echo "$OUTPUT_DIR"
