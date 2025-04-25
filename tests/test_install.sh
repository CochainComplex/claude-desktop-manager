#!/bin/bash
# Test script for Claude Desktop Manager installation

set -euo pipefail

# Load required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "${PARENT_DIR}/lib/dependencies.sh"
source "${PARENT_DIR}/lib/sandbox.sh"
source "${PARENT_DIR}/lib/installer.sh"
source "${PARENT_DIR}/lib/instance.sh"
source "${PARENT_DIR}/lib/config.sh"
source "${PARENT_DIR}/lib/desktop.sh"

# Global variables
CMGR_HOME="${HOME}/.cmgr"
CMGR_CACHE="${CMGR_HOME}/cache"
CMGR_REGISTRY="${CMGR_HOME}/registry.json"
SANDBOX_BASE="${HOME}/sandboxes"

# Test instance name
TEST_INSTANCE="test_instance"

echo "=== Claude Desktop Manager Installation Test ==="
echo "Setting up test environment..."

# Create necessary directories
mkdir -p "${CMGR_HOME}" "${CMGR_CACHE}" "${SANDBOX_BASE}" "${CMGR_HOME}/logs"

# Initialize registry if it doesn't exist
if [ ! -f "${CMGR_REGISTRY}" ]; then
    echo '{"instances": {}}' > "${CMGR_REGISTRY}"
fi

echo "Creating test instance: ${TEST_INSTANCE}"

# Ensure instance doesn't already exist
if instance_exists "${TEST_INSTANCE}"; then
    echo "Removing existing test instance..."
    remove_instance "${TEST_INSTANCE}"
fi

# Create sandbox
if ! create_sandbox "${TEST_INSTANCE}"; then
    echo "ERROR: Failed to create sandbox"
    exit 1
fi

# Add to registry
if ! add_instance "${TEST_INSTANCE}" "deb"; then
    echo "ERROR: Failed to add instance to registry"
    remove_sandbox "${TEST_INSTANCE}"
    exit 1
fi

# Install Claude Desktop
if ! install_claude_in_sandbox "${TEST_INSTANCE}" "deb"; then
    echo "ERROR: Failed to install Claude Desktop in sandbox"
    remove_instance_from_registry "${TEST_INSTANCE}"
    remove_sandbox "${TEST_INSTANCE}"
    exit 1
fi

echo "Testing if Claude Desktop binary exists in sandbox..."
if ! run_in_sandbox "${TEST_INSTANCE}" test -f /home/agent/.local/bin/claude-desktop; then
    echo "ERROR: Claude Desktop binary not found in sandbox"
    remove_instance "${TEST_INSTANCE}"
    exit 1
fi

echo "Testing if desktop file exists in sandbox..."
if ! run_in_sandbox "${TEST_INSTANCE}" test -f /home/agent/.local/share/applications/claude-desktop.desktop; then
    echo "ERROR: Desktop file not found in sandbox"
    remove_instance "${TEST_INSTANCE}"
    exit 1
fi

# Clean up
echo "Cleaning up test instance..."
remove_instance "${TEST_INSTANCE}"

echo "=== Test completed successfully! ==="
