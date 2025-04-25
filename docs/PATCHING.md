# Claude Desktop Manager - Patching Process

This document explains how Claude Desktop Manager patches the Claude Desktop application to support multiple isolated instances.

## Overview

Claude Desktop Manager uses a patching system to:

1. Customize window titles with instance names
2. Fix `MaxListenersExceededWarning` issues
3. Enable better instance identification

## How Patching Works

The patching process:

1. Locates the Claude Desktop `app.asar` file
2. Extracts it to a temporary location
3. Modifies key files to add instance-specific customizations
4. Repacks the modified files
5. Applies the patched version back to the original location

## System vs. User Installations

### User Installations
For Claude Desktop installed in a user's home directory, patching happens automatically during instance creation.

### System Installations
For system-wide installations (in `/usr/lib/` or similar), the patching process:

1. Creates the patched file in the user's temporary directory (`~/.cmgr/temp/`)
2. Attempts to apply the patch using `sudo` if available
3. If automatic patching fails, provides options for manual application

## Manual Patch Application

If automatic patching fails for system installations, you can apply patches in two ways:

### Option 1: Using the system patch script:
```bash
sudo /path/to/claude-desktop-manager/scripts/apply-system-patches.sh
```

This script will find all pending patches and apply them to the correct system locations.

### Option 2: Direct copy:
```bash
sudo cp ~/.cmgr/temp/patched-INSTANCE_NAME.asar /usr/lib/claude-desktop/app.asar
```

Where `INSTANCE_NAME` is the name of your instance, and the target path matches your Claude Desktop installation.

## Customization Details

The patching process adds:

1. **Window Title Customization**: Adds the instance name to all window titles
2. **EventEmitter Fixes**: Increases the default max listeners to prevent warnings
3. **Package Name Customization**: Updates the app name to include the instance name

## Backup and Recovery

The original `app.asar` file is always backed up before patching:

- For user installations: The backup is stored alongside the original as `app.asar.original`
- For system installations: The backup is also created as `app.asar.original`

To restore the original:

```bash
# For user installations
cp ~/.local/lib/claude-desktop/app.asar.original ~/.local/lib/claude-desktop/app.asar

# For system installations
sudo cp /usr/lib/claude-desktop/app.asar.original /usr/lib/claude-desktop/app.asar
```
