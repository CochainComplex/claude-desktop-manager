#!/bin/bash
# update-window-titles.sh - Updates desktop entries and preload scripts to customize window titles
# This script runs inside the sandbox environment

set -e

# Use explicit sandbox path for consistency - do not use $HOME
SANDBOX_HOME="/home/claude"
INSTANCE_NAME="${CLAUDE_INSTANCE:-claude}"

echo "Updating window title configuration for instance: $INSTANCE_NAME"

# Update desktop entries
for desktop_file in "$SANDBOX_HOME/.local/share/applications/"*claude*.desktop; do
    if [ -f "$desktop_file" ]; then
        echo "Updating desktop entry: $desktop_file"
        
        # Add instance name to title
        sed -i "s/^Name=.*/Name=Claude Desktop ($INSTANCE_NAME)/" "$desktop_file"
        sed -i "s/^Comment=.*/Comment=Claude Desktop AI Assistant ($INSTANCE_NAME instance)/" "$desktop_file"
        
        # Update StartupWMClass
        sed -i "s/^StartupWMClass=.*/StartupWMClass=Claude-$INSTANCE_NAME/" "$desktop_file"
        
        # Add environment variable to Exec line if not already present
        if ! grep -q "CLAUDE_INSTANCE=$INSTANCE_NAME" "$desktop_file"; then
            sed -i "s/^Exec=.*/Exec=env CLAUDE_INSTANCE=$INSTANCE_NAME LIBVA_DRIVER_NAME=dummy &/" "$desktop_file"
        fi
        
        echo "✓ Desktop entry updated"
    fi
done

# Ensure preload script exists and contains window title code
for config_dir in "$SANDBOX_HOME/.config/claude-desktop" "$SANDBOX_HOME/.config/Claude/electron"; do
    mkdir -p "$config_dir"
    preload_file="$config_dir/preload.js"
    
    if [ -f "$preload_file" ]; then
        # Check if window title code is already in the preload script
        if ! grep -q "updateTitle" "$preload_file"; then
            echo "Updating preload script: $preload_file"
            cat >> "$preload_file" <<'PRELOADEOF'

// Window title customization for instance: $INSTANCE_NAME
if (typeof window !== 'undefined') {
  const updateTitle = () => {
    if (!document.title.includes('[$INSTANCE_NAME]')) {
      document.title = document.title + ' [$INSTANCE_NAME]';
    }
  };
  
  if (document.readyState === 'complete') {
    updateTitle();
  }
  
  window.addEventListener('load', updateTitle);
  
  // Check periodically for title changes
  setInterval(updateTitle, 1000);
}
PRELOADEOF
            echo "✓ Preload script updated"
        else
            echo "✓ Preload script already contains window title customization"
        fi
    else
        echo "Creating new preload script: $preload_file"
        cat > "$preload_file" <<'PRELOADEOF'
// Claude Desktop Manager preload script
// Custom preload script for instance: $INSTANCE_NAME

// Window title customization
if (typeof window !== 'undefined') {
  const updateTitle = () => {
    if (!document.title.includes('[$INSTANCE_NAME]')) {
      document.title = document.title + ' [$INSTANCE_NAME]';
    }
  };
  
  if (document.readyState === 'complete') {
    updateTitle();
  }
  
  window.addEventListener('load', updateTitle);
  
  // Check periodically for title changes
  setInterval(updateTitle, 1000);
}

// Fix for MaxListenersExceededWarning
if (typeof process !== 'undefined') {
  try {
    const events = require('events');
    events.EventEmitter.defaultMaxListeners = 30;
  } catch (error) {
    console.error('Error setting default max listeners:', error);
  }
}
PRELOADEOF
        echo "✓ New preload script created"
    fi
done

# Update configuration to use preload script
config_file="$SANDBOX_HOME/.config/Claude/claude_desktop_config.json"
mkdir -p "$(dirname "$config_file")"

if [ -f "$config_file" ]; then
    # Check if config already has preload script
    if ! grep -q "electronInitScript" "$config_file"; then
        echo "Updating Claude Desktop config to use preload script"
        # Use explicit sandbox path - do not use $HOME
        sed -i 's/{/{\"electronInitScript\": \"\/home\/claude\/.config\/Claude\/electron\/preload.js\", /' "$config_file"
        echo "✓ Configuration updated"
    else
        echo "✓ Configuration already contains preload script setting"
    fi
else
    echo "Creating new Claude Desktop config"
    cat > "$config_file" <<'CONFIGEOF'
{
  "electronInitScript": "/home/claude/.config/Claude/electron/preload.js"
}
CONFIGEOF
    echo "✓ New configuration created"
fi

echo "Window title customization complete for instance: $INSTANCE_NAME"
echo "Please restart Claude Desktop for changes to take effect."