#!/bin/bash
# Direct sandbox isolation test

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SANDBOX_BASE="$HOME/sandboxes"
TEST_NAME="direct-test"
SANDBOX_HOME="$SANDBOX_BASE/$TEST_NAME"

# Create a test file in the real home
echo "TOP SECRET TEST DATA" > ~/.test-secret

# Source the sandbox functions
source "$SCRIPT_DIR/lib/sandbox.sh"

# Create test sandbox
echo "===== Creating test sandbox ====="
if [ -d "$SANDBOX_HOME" ]; then
  rm -rf "$SANDBOX_HOME"
fi
create_sandbox "$TEST_NAME"

# Create a direct bubblewrap command to test isolation
REAL_USER="${SUDO_USER:-$(whoami)}"
SANDBOX_USERNAME="claude"
SANDBOX_USER_HOME="/home/${SANDBOX_USERNAME}"

echo "===== Testing direct sandbox command ====="
echo "Real user: $REAL_USER"

# Use direct bubblewrap command for testing
bwrap \
  --proc /proc \
  --tmpfs /tmp \
  --bind "$SANDBOX_HOME" "$SANDBOX_USER_HOME" \
  --ro-bind /usr /usr \
  --ro-bind /bin /bin \
  --ro-bind /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /etc /etc \
  --tmpfs "$HOME" \
  --tmpfs "/home/$REAL_USER" \
  --setenv HOME "$SANDBOX_USER_HOME" \
  --setenv USER "$SANDBOX_USERNAME" \
  --setenv PATH "$SANDBOX_USER_HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" \
  --dev-bind /dev /dev \
  bash -c "
    echo 'INSIDE DIRECT SANDBOX'
    echo 'Current user: \$(whoami)'
    echo 'Home directory: \$HOME'
    
    echo '===== Sandbox Path Structure ====='
    ls -la /
    ls -la /home
    
    echo '===== Testing Real Home Access ====='
    echo 'Trying to access real user home:'
    ls -la /home/$REAL_USER 2>&1 || echo 'Access denied (GOOD)'
    
    echo 'Trying to access real home secret file:'
    cat /home/$REAL_USER/.test-secret 2>&1 || echo 'Access denied (GOOD)'
    
    echo '===== Writing Test Files ====='
    # Create a file in sandbox home
    mkdir -p \$HOME/.config/Claude
    echo 'SANDBOX TEST DATA' > \$HOME/.config/Claude/sandbox-test-config.json
    echo 'Created file in sandbox: \$HOME/.config/Claude/sandbox-test-config.json'
    cat \$HOME/.config/Claude/sandbox-test-config.json
    
    # Try to create a file in real user home
    echo 'Attempting to write to real user home:'
    mkdir -p /home/$REAL_USER/.config/Claude 2>&1 || echo 'Access denied (GOOD)'
    echo 'ISOLATION FAILURE' > /home/$REAL_USER/.config/Claude/test-isolation-fail.json 2>&1 || echo 'Access denied (GOOD)'
  "

# Verify that files were created in the right places
echo "===== Verifying File Locations ====="
echo "Sandbox config file:"
if [ -f "$SANDBOX_HOME/.config/Claude/sandbox-test-config.json" ]; then
  echo "Found in sandbox (GOOD)"
  cat "$SANDBOX_HOME/.config/Claude/sandbox-test-config.json"
else
  echo "Not found in sandbox (BAD)"
fi

echo "Real home test file:"
if [ -f "$HOME/.config/Claude/test-isolation-fail.json" ]; then
  echo "Found in real home (BAD - isolation failure)"
  cat "$HOME/.config/Claude/test-isolation-fail.json"
else
  echo "Not found in real home (GOOD)"
fi

# Clean up
echo "===== Cleanup ====="
rm -f ~/.test-secret
rm -rf "$SANDBOX_HOME"
echo "Test completed"