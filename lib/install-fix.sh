#!/bin/bash
# Simple script to install Claude Desktop in a sandbox
# This is designed to be run from within the sandbox environment

set -e

# Check if we have the package file
if [ ! -f "$HOME/Downloads/claude-desktop_0.9.2_amd64.deb" ]; then
    echo "Package not found in $HOME/Downloads"
    exit 1
fi

# Create extraction directory
echo "Creating extraction directory..."
mkdir -p $HOME/temp-extract
cd $HOME/temp-extract

# Extract the package
echo "Extracting package..."
if command -v dpkg-deb &> /dev/null; then
    dpkg-deb -x "$HOME/Downloads/claude-desktop_0.9.2_amd64.deb" .
else
    # Use ar and tar as fallback
    echo "dpkg-deb not found, using ar and tar..."
    ar x "$HOME/Downloads/claude-desktop_0.9.2_amd64.deb"
    
    # Extract data archive
    if [ -f "data.tar.xz" ]; then
        tar -xf data.tar.xz
    elif [ -f "data.tar.gz" ]; then
        tar -xf data.tar.gz
    elif [ -f "data.tar.zst" ]; then
        tar --use-compress-program=unzstd -xf data.tar.zst
    elif [ -f "data.tar" ]; then
        tar -xf data.tar
    else
        echo "No data archive found!"
        exit 1
    fi
fi

# Check if extraction succeeded
if [ ! -d "./usr" ]; then
    echo "Extraction failed - usr directory not found"
    exit 1
fi

# Install the executable
echo "Installing executable..."
mkdir -p $HOME/.local/bin
if [ -f "./usr/bin/claude-desktop" ]; then
    cp "./usr/bin/claude-desktop" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/claude-desktop"
    echo "Successfully installed claude-desktop from package"
else
    # Create fallback executable
    echo "Creating fallback executable..."
    cat > "$HOME/.local/bin/claude-desktop" << 'EOF'
#!/bin/bash
# Fallback launcher for Claude Desktop
exec electron --no-sandbox --disable-dev-shm-usage $HOME/.local/share/claude-desktop/app.asar "$@"
EOF
    chmod +x "$HOME/.local/bin/claude-desktop"
    
    # Copy app.asar if found
    if [ -d "./usr/lib/claude-desktop" ]; then
        mkdir -p "$HOME/.local/share/claude-desktop"
        cp -r ./usr/lib/claude-desktop/* "$HOME/.local/share/claude-desktop/"
        echo "Copied app.asar from package"
    else
        echo "Warning: app.asar not found in package"
    fi
fi

# Copy resources
if [ -d "./usr/share/claude-desktop" ]; then
    mkdir -p "$HOME/.local/share/claude-desktop"
    cp -r ./usr/share/claude-desktop/* "$HOME/.local/share/claude-desktop/"
    echo "Copied application resources"
fi

# Create desktop entry
echo "Creating desktop entry..."
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude Desktop
Comment=Claude Desktop AI Assistant
Exec=env LIBVA_DRIVER_NAME=dummy $HOME/.local/bin/claude-desktop --disable-gpu --no-sandbox --disable-dev-shm-usage %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
EOF

# Cleanup
cd "$HOME"
rm -rf "$HOME/temp-extract"

echo "Installation completed successfully!"
exit 0
