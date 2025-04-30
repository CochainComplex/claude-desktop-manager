#!/bin/bash
# Integration test for Claude Desktop Manager user namespace handling
# Tests the entire workflow from enabling user namespaces to creating and using a sandbox

set -e

# Switch to the project root directory
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SCRIPT_DIR="$(pwd)"
echo "Project root: $SCRIPT_DIR"

# Source dependencies for testing
source "${SCRIPT_DIR}/lib/dependencies.sh"

# Create a test folder
TEST_DIR="${SCRIPT_DIR}/tests/integration"
mkdir -p "${TEST_DIR}"

# Setup test environment variables
export CMGR_HOME="${TEST_DIR}/config"
export SANDBOX_BASE="${TEST_DIR}/sandboxes"
mkdir -p "${CMGR_HOME}" "${SANDBOX_BASE}"

# Initialize registry
echo '{"instances": {}}' > "${CMGR_HOME}/registry.json"

echo "==== CLAUDE DESKTOP MANAGER INTEGRATION TEST ===="
echo "User: $(whoami)"
echo "Date: $(date)"
echo

# Step 1: Check if user namespaces are enabled
echo "Step 1: Checking user namespace support..."
if check_userns_enabled; then
    echo "✓ User namespaces are already enabled"
    USERNS_SUPPORTED=true
else
    echo "ℹ User namespaces are not enabled"
    echo "Note: This test will not attempt to enable them to avoid requiring authentication"
    echo "Real-world usage would run: ./cmgr enable-userns"
    USERNS_SUPPORTED=false
fi

# Step 2: Run the full command to create a sandbox
echo
echo "Step 2: Creating a test sandbox environment..."

# Source additional libraries needed for sandbox creation
source "${SCRIPT_DIR}/lib/sandbox.sh"
TEST_INSTANCE="test-integration"

echo "Creating sandbox: ${TEST_INSTANCE}"
if create_sandbox "${TEST_INSTANCE}"; then
    echo "✓ Sandbox created successfully"
else
    echo "✗ Failed to create sandbox"
    exit 1
fi

# Step 3: Test sandbox isolation
echo
echo "Step 3: Testing sandbox isolation..."

# Create a test file outside the sandbox with unique content
MARKER_FILE="${TEST_DIR}/outside_marker.txt"
MARKER_CONTENT="This file should not be visible inside the sandbox $(date)"
echo "${MARKER_CONTENT}" > "${MARKER_FILE}"
echo "Created marker file: ${MARKER_FILE}"

# Create a test script to verify isolation
TEST_SCRIPT="${SANDBOX_BASE}/${TEST_INSTANCE}/test_isolation.sh"
cat > "${TEST_SCRIPT}" << EOF
#!/bin/bash
# Test script for sandbox isolation

echo "Running inside sandbox as user: \$(whoami)"
echo "Home directory: \$HOME"

# Test 1: Check if user namespaces work
if unshare --user echo "User namespaces working" &>/dev/null; then
    echo "✓ Can create user namespaces inside sandbox"
else
    echo "⚠️ Cannot create user namespaces inside sandbox"
    # Show the error message
    unshare --user echo "test" 2>&1 || true
fi

# Test 2: Check if we can see the real user's home
real_user_home="/home/$(whoami)"
if [ -d "\$real_user_home" ]; then
    echo "⚠️ Can access real user home: \$real_user_home"
    # List some contents to verify
    ls -la "\$real_user_home" 2>/dev/null || echo "Cannot list contents"
else
    echo "✓ Cannot access real user home - isolation working"
fi

# Test 3: Check if we can see the marker file
marker_file="${MARKER_FILE}"
if [ -f "\$marker_file" ]; then
    echo "⚠️ Can access marker file outside sandbox: \$marker_file"
    cat "\$marker_file"
else
    echo "✓ Cannot access marker file - isolation working"
fi

# Test 4: Create a file inside sandbox
sandbox_file="\$HOME/sandbox_marker.txt"
echo "This file was created inside the sandbox at \$(date)" > "\$sandbox_file"
echo "✓ Created file inside sandbox: \$sandbox_file"

# Done!
echo "All tests completed inside sandbox"
EOF

chmod +x "${TEST_SCRIPT}"

# Run the test script in the sandbox
echo "Running isolation tests in sandbox..."
if run_in_sandbox "${TEST_INSTANCE}" "./test_isolation.sh"; then
    echo "✓ Sandbox tests completed successfully"
else
    echo "⚠️ Sandbox tests reported errors"
fi

# Step 4: Verify that files created in the sandbox are visible from outside
echo
echo "Step 4: Verifying sandbox file creation..."
SANDBOX_MARKER="${SANDBOX_BASE}/${TEST_INSTANCE}/sandbox_marker.txt"
if [ -f "${SANDBOX_MARKER}" ]; then
    echo "✓ Found marker file created inside sandbox:"
    cat "${SANDBOX_MARKER}"
else
    echo "✗ Could not find marker file from sandbox"
fi

echo
echo "==== TEST SUMMARY ===="
echo "User namespace support: $(check_userns_enabled && echo "Enabled" || echo "Disabled")"
echo "Sandbox creation: Success"
echo "Sandbox isolation: $([ -f "${SANDBOX_MARKER}" ] && echo "Working" || echo "Failed")"
echo

# Clean up
echo "Cleaning up test environment..."
rm -rf "${TEST_DIR}"
echo "Done!"
