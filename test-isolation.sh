#!/bin/bash
# Test script to verify sandbox isolation

# Set up variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SANDBOX_BASE="$HOME/sandboxes"
TEST_NAME="isolation-test"
SANDBOX_HOME="$SANDBOX_BASE/$TEST_NAME"

echo "Creating test file in real home directory"
echo "TOP SECRET DATA" > ~/.isolation-test-file

# Source the sandbox functions
source "$SCRIPT_DIR/lib/sandbox.sh"

# Create test sandbox
echo "=== Creating test sandbox ==="
if [ -d "$SANDBOX_HOME" ]; then
  rm -rf "$SANDBOX_HOME"
fi
create_sandbox "$TEST_NAME"

# Run a command in the sandbox to check isolation
echo "=== Testing sandbox isolation ==="
run_in_sandbox "$TEST_NAME" bash -c "
  echo 'Inside sandbox'
  echo 'User: \$(whoami)'
  echo 'Home: \$HOME'
  
  # Try to access the real user's home directory
  echo 'Trying to access real user home:'
  
  # Get the real username dynamically
  real_user=\"${SUDO_USER:-$(whoami)}\"
  echo \"Real user: \$real_user\"
  
  # Try to access the real user's home
  echo \"Attempting to access: /home/\$real_user\"
  ls -la /home/\$real_user 2>&1 || echo 'Access denied (GOOD)'
  
  # Try to access the isolation test file
  echo 'Trying to access test file in real home:'
  cat /home/\$real_user/.isolation-test-file 2>&1 || echo 'Access denied (GOOD)'
  
  # Check if we can see other directories
  echo 'Checking visibility of other system directories:'
  for dir in /home /etc /usr /var; do
    echo -n \"\$dir: \"
    ls -la \$dir &>/dev/null && echo 'Accessible' || echo 'Not accessible'
  done
  
  # Write to sandbox home
  echo 'SANDBOX DATA' > \$HOME/sandbox-test-file
  echo 'Created sandbox test file: \$HOME/sandbox-test-file'
  
  # Check actual paths inside sandbox
  echo 'Actual paths in sandbox:'
  pwd
  ls -la /
  ls -la /home
  
  # Try to create a file in the same location as in the host
  echo 'Testing same-path file creation:'
  mkdir -p ~/.config/Claude
  echo 'SANDBOX CONFIG' > ~/.config/Claude/test-config.json
  cat ~/.config/Claude/test-config.json
  
  exit 0
"

# Verify the file was created in the sandbox, not in the real home
echo "=== Verifying file locations ==="
echo "Sandbox config file:"
if [ -f "$SANDBOX_HOME/.config/Claude/test-config.json" ]; then
  echo "Found in sandbox (GOOD)"
  cat "$SANDBOX_HOME/.config/Claude/test-config.json"
else
  echo "Not found in sandbox (BAD)"
fi

echo "Real home config file:"
if [ -f "$HOME/.config/Claude/test-config.json" ]; then
  echo "Found in real home (BAD - isolation failure)"
  cat "$HOME/.config/Claude/test-config.json"
else
  echo "Not found in real home (GOOD)"
fi

# Clean up
echo "=== Cleanup ==="
rm ~/.isolation-test-file
rm -rf "$SANDBOX_HOME"
echo "Test completed"