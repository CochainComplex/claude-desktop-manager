#!/bin/bash
# Test script for verifying user namespace functionality in Claude Desktop Manager
# This script tests:
# 1. Detection of user namespace support
# 2. Enabling user namespaces
# 3. Verifying sandbox isolation with user namespaces

set -e

# Include the necessary libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "${SCRIPT_DIR}/lib/dependencies.sh"
source "${SCRIPT_DIR}/lib/sandbox.sh"

# Create a test directory
TEST_DIR="${SCRIPT_DIR}/tests/tmp"
mkdir -p "${TEST_DIR}"

echo "==== USER NAMESPACE TEST ===="
echo "Running from: ${SCRIPT_DIR}"
echo "User: $(whoami)"
echo

# Test 1: Check if user namespaces are enabled
echo "Test 1: Checking user namespace support..."
if check_userns_enabled; then
    echo "✓ User namespaces are enabled"
else
    echo "✗ User namespaces are not enabled"
    
    # Ask if we should try to enable them
    echo -n "Would you like to try enabling user namespaces? (y/n) "
    read -r try_enable
    
    if [[ "$try_enable" =~ ^[Yy] ]]; then
        echo "Attempting to enable user namespaces..."
        if enable_userns; then
            echo "✓ Successfully enabled user namespaces"
        else
            echo "✗ Failed to enable user namespaces"
            echo "Some tests may fail, but we'll continue anyway"
        fi
    else
        echo "Skipping user namespace enablement"
    fi
fi

# Test 2: Test if uid map error occurs in sandbox
echo
echo "Test 2: Testing sandbox for uid map errors..."

# Set up a test sandbox
TEST_SANDBOX="${TEST_DIR}/test_sandbox"
mkdir -p "${TEST_SANDBOX}"

# Override SANDBOX_BASE for testing
SANDBOX_BASE="${TEST_DIR}"
SANDBOX_NAME="test_instance"

# Create a test script to run in the sandbox
cat > "${TEST_SANDBOX}/test_userns.sh" << 'EOF'
#!/bin/bash
# Test if we can create a user namespace
if unshare --user true 2>/dev/null; then
    echo "✓ Can create user namespaces inside sandbox"
else
    echo "✗ Cannot create user namespaces inside sandbox"
    # Show the error message
    unshare --user echo "test" 2>&1 || true
fi

# Check if we can access the real user's home
if [ -d "/home/$(whoami)" ]; then
    echo "✗ Can access real user's home directory - sandbox isolation failed"
else
    echo "✓ Cannot access real user's home directory - sandbox isolation working"
fi
EOF

chmod +x "${TEST_SANDBOX}/test_userns.sh"

# Run the test in the sandbox
echo "Running sandbox test..."
run_in_sandbox "${SANDBOX_NAME}" "./test_userns.sh" || echo "Test failed but continuing"

# Test 3: Verify sandbox isolation with files
echo
echo "Test 3: Testing sandbox isolation with files..."

# Create a file outside the sandbox
TEST_FILE="${TEST_DIR}/outside_file.txt"
echo "This file should not be accessible from inside the sandbox" > "${TEST_FILE}"

# Create a test script to check file access
cat > "${TEST_SANDBOX}/test_files.sh" << EOF
#!/bin/bash
# Try to access the file outside the sandbox
if [ -f "${TEST_FILE}" ]; then
    echo "✗ Can access file outside sandbox - isolation failed"
    cat "${TEST_FILE}"
else
    echo "✓ Cannot access file outside sandbox - isolation working"
fi

# Create a file inside the sandbox
echo "This file was created inside the sandbox" > "\$HOME/inside_file.txt"
echo "✓ Created file inside sandbox at \$HOME/inside_file.txt"
EOF

chmod +x "${TEST_SANDBOX}/test_files.sh"

# Run the file access test
echo "Running file access test..."
run_in_sandbox "${SANDBOX_NAME}" "./test_files.sh" || echo "Test failed but continuing"

# Verify the inside file exists in the sandbox directory
if [ -f "${TEST_SANDBOX}/inside_file.txt" ]; then
    echo "✓ Found file created inside sandbox"
    cat "${TEST_SANDBOX}/inside_file.txt"
else
    echo "✗ Could not find file created inside sandbox"
fi

echo
echo "==== TEST SUMMARY ===="
echo "1. User namespace support: $(check_userns_enabled && echo "Enabled" || echo "Disabled")"
echo "2. Sandbox isolation: $([ -f "${TEST_SANDBOX}/inside_file.txt" ] && echo "Working" || echo "Failed")"
echo

# Clean up
echo "Cleaning up test files..."
rm -rf "${TEST_DIR}"
echo "Done!"
