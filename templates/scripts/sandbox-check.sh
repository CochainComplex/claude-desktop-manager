#!/bin/bash
# Sandbox diagnostic and fix script
# This script checks if the sandbox is properly isolated from the host

echo "===== SANDBOX ISOLATION DIAGNOSTIC ====="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "Home: $HOME"

# Check if we can access the real user's home directory
# Get current username dynamically
current_user="${SUDO_USER:-$(whoami)}"
real_user_home="/home/${current_user}"
if [ -d "$real_user_home" ]; then
    echo "WARNING: Can access real user's home directory: $real_user_home"
    
    # Check if we can access the real user's Claude config
    if [ -d "$real_user_home/.config/Claude" ]; then
        echo "CRITICAL: Can access real user's Claude config!"
        ls -la "$real_user_home/.config/Claude"
    fi
    
    echo "Attempting to fix sandbox isolation..."
    # Create a simple C program to mount the tmpfs
    cat > /tmp/mount_tmpfs.c << 'EOC'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mount.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <path>\n", argv[0]);
        return 1;
    }
    
    // Mount a tmpfs over the path
    if (mount("none", argv[1], "tmpfs", 0, NULL) != 0) {
        perror("Failed to mount tmpfs");
        return 1;
    }
    
    printf("Successfully mounted tmpfs on %s\n", argv[1]);
    return 0;
}
EOC
    
    # Compile and run the program
    if command -v gcc >/dev/null 2>&1; then
        gcc -o /tmp/mount_tmpfs /tmp/mount_tmpfs.c
        # Try running with sudo
        if command -v sudo >/dev/null 2>&1; then
            sudo /tmp/mount_tmpfs "$real_user_home"
        else
            echo "Cannot fix isolation: sudo not available"
        fi
    else
        echo "Cannot fix isolation: gcc not available"
    fi
    
    # Check if the fix worked
    if [ -d "$real_user_home" ]; then
        echo "WARNING: Still have access to real user's home!"
    else
        echo "✓ Fixed: Real user's home is no longer accessible"
    fi
else
    echo "✓ Cannot access real user's home directory (correct behavior)"
fi

# Check environment variables
echo -e "\n--- Environment Variables ---"
echo "DISPLAY: ${DISPLAY:-Not set}"
echo "XAUTHORITY: ${XAUTHORITY:-Not set}"

# Verify display access
echo -e "\n--- Display Access ---"
if command -v xdpyinfo >/dev/null 2>&1; then
    if xdpyinfo >/dev/null 2>&1; then
        echo "✓ Can connect to X server"
    else
        echo "WARNING: Cannot connect to X server"
        # Try to fix X11 display access
        export DISPLAY=":0"
        if xdpyinfo >/dev/null 2>&1; then
            echo "✓ Fixed: X11 display access working with DISPLAY=:0"
        else
            echo "WARNING: Still cannot connect to X server. Try other display values:"
            for i in 1 2 3; do
                export DISPLAY=":$i"
                if xdpyinfo >/dev/null 2>&1; then
                    echo "✓ Working display: DISPLAY=:$i"
                    break
                fi
            done
        fi
    fi
else
    echo "Cannot check display: xdpyinfo not available"
fi

echo "===== DIAGNOSTIC COMPLETE ====="
