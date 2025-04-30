# Claude Desktop Manager Tests

This directory contains test scripts for verifying the functionality of Claude Desktop Manager.

## Test Scripts

### User Namespace Tests

- `test_userns.sh`: Tests the user namespace detection, enablement, and sandbox isolation features
- `integration_test.sh`: Full integration test of sandbox creation and isolation with user namespace support

## Running Tests

Run the tests with:

```bash
# Run the user namespace test
./tests/test_userns.sh

# Run the integration test
./tests/integration_test.sh
```

The user namespace test includes an interactive prompt to enable user namespaces if they are not already enabled. This requires authentication via pkexec, sudo, or doas.

The integration test assumes user namespaces are already enabled and will not attempt to enable them during the test run.

## Test Coverage

These tests verify:

1. User namespace detection and enablement
2. Sandbox creation with proper isolation
3. File system isolation between host and sandbox
4. Proper handling of user namespace errors
5. Dynamic user detection without hardcoded usernames

## Test Environment Variables

The integration test uses a separate test environment to avoid affecting your real Claude Desktop Manager configuration:

- `CMGR_HOME`: Set to a test directory
- `SANDBOX_BASE`: Set to a test sandbox directory

Both test directories are automatically cleaned up after tests complete.
