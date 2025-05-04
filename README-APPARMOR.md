# AppArmor and Claude Desktop Manager

This document explains how to resolve issues with AppArmor preventing Claude Desktop Manager's sandbox functionality from working correctly on Ubuntu 24.04 and other systems with AppArmor enabled.

## Problem Description

Claude Desktop Manager uses [`bubblewrap`](https://github.com/containers/bubblewrap) for creating isolated sandboxes, which requires unprivileged user namespaces. On Ubuntu 24.04 and other systems with AppArmor enabled, the default AppArmor policy restricts unprivileged users from creating user namespaces and performing network namespace operations, even when the kernel is configured to allow it.

Symptoms of these issues include:

- Error messages like `bwrap: setting up uid map: Permission denied`
- Error messages like `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`
- AppArmor denial messages in system logs: `apparmor="DENIED" operation="capable" profile="unprivileged_userns" pid=XXXX comm="bwrap" capability=8 capname="setpcap"`
- Inability to create or start Claude Desktop instances

## Prerequisites

Before applying the AppArmor fix, ensure your kernel is properly configured:

1. Check that unprivileged user namespaces are enabled:
   ```bash
   sysctl kernel.unprivileged_userns_clone
   ```
   The output should be `kernel.unprivileged_userns_clone = 1`

2. Verify that you have the necessary kernel boot parameters. Your `/proc/cmdline` should include:
   ```
   namespace.unpriv_enable=1 user_namespace.enable=1
   ```

If these settings are not correctly configured, the AppArmor fix alone won't resolve the issue.

## Solution Implementation

Claude Desktop Manager includes three scripts to handle AppArmor configuration:

1. **`scripts/apparmor/check-apparmor-status.sh`** - Diagnoses AppArmor and bubblewrap issues
2. **`scripts/apparmor/fix-apparmor.sh`** - Applies changes to allow bubblewrap to work
3. **`scripts/apparmor/revert-apparmor-changes.sh`** - Reverts changes and restores original configuration

### Diagnosing AppArmor and Bubblewrap Issues

To diagnose issues with AppArmor and bubblewrap, run the diagnostic script:

```bash
./scripts/apparmor/check-apparmor-status.sh
```

This script will:

1. Check your current system configuration related to AppArmor and user namespaces
2. Test bubblewrap functionality with and without network isolation
3. Look for AppArmor denial messages in system logs
4. Provide specific guidance based on detected issues

If the script detects that bubblewrap fails with full isolation but works with `--share-net`, this confirms that you're experiencing the network namespace permission issue, which is already addressed by Claude Desktop Manager's default configuration.

### Applying the Fix

Run the fix script with sudo:

```bash
sudo ./scripts/apparmor/fix-apparmor.sh
```

This script will:

1. Check your current system configuration
2. Create a backup of your existing AppArmor configuration
3. Create a local override for the unprivileged_userns AppArmor profile
4. Reload AppArmor to apply the changes
5. Verify that bubblewrap can now create user namespaces

After applying the fix, you should be able to create and run Claude Desktop instances.

### Reverting Changes

If you need to revert the changes, run:

```bash
sudo ./scripts/apparmor/revert-apparmor-changes.sh
```

This script will:

1. Remove the local override for unprivileged_userns
2. Restore the original configuration from backup, if available
3. Reload AppArmor to apply the original restrictions
4. Verify that the system has been restored to its original state

## How the Fix Works

The fix works through a combination of approaches:

1. **Network Namespace Sharing**: By default, Claude Desktop Manager now uses `--share-net` to skip network namespace isolation, avoiding the most common permission errors.

2. **AppArmor Override**: A local AppArmor policy override is created at `/etc/apparmor.d/local/unprivileged_userns` that allows the specific capabilities needed by bubblewrap:

```
# Allow specific capabilities needed by bubblewrap
allow capability setpcap,
allow capability setuid,
allow capability setgid,
allow capability sys_admin,
allow capability net_admin,

# Allow network operations
allow network netlink raw,

# Allow writing to uid_map and gid_map files
allow owner /proc/*/uid_map rw,
allow owner /proc/*/gid_map rw,
allow owner /proc/*/setgroups rw,
```

This approach:
- Modifies only the specific restrictions that are blocking bubblewrap
- Preserves most of AppArmor's security protections
- Can be easily reverted without affecting system stability
- Works without disabling AppArmor completely

## Alternative Solutions

If the provided scripts don't resolve the issue, you have these alternative options:

### Option 1: Put AppArmor in Complain Mode for User Namespaces

```bash
sudo ln -s /etc/apparmor.d/unprivileged_userns /etc/apparmor.d/force-complain/
sudo systemctl reload apparmor
```

### Option 2: Temporarily Disable AppArmor

```bash
sudo systemctl stop apparmor
sudo systemctl disable apparmor
```

Note: This is more aggressive and disables all AppArmor protection, which may reduce system security.

## Troubleshooting

### Script Reports Success But Bubblewrap Still Fails

1. **Reboot Your System**: Some kernel parameter changes require a reboot to take effect.

2. **Check AppArmor Status**:
   ```bash
   sudo aa-status
   ```

3. **Examine AppArmor Logs**:
   ```bash
   sudo journalctl -k | grep -i apparmor | grep -i denied
   ```

4. **Verify Kernel Parameters**:
   ```bash
   cat /proc/cmdline
   sysctl kernel.unprivileged_userns_clone
   ```

### Script Fails to Apply Changes

1. **Check AppArmor Version**:
   ```bash
   apparmor_parser --version
   ```

2. **Verify AppArmor Profile Location**:
   ```bash
   ls -la /etc/apparmor.d/unprivileged_userns
   ```

3. **Manually Create the Override**:
   ```bash
   sudo mkdir -p /etc/apparmor.d/local
   echo "allow capability setpcap," | sudo tee /etc/apparmor.d/local/unprivileged_userns
   sudo systemctl reload apparmor
   ```

## Security Considerations

The AppArmor modifications made by this script reduce some of the security restrictions originally put in place by Ubuntu. This is necessary for bubblewrap to function, but it's important to understand the implications:

1. The changes only affect the unprivileged_userns profile, which is specifically about restricting unprivileged user namespace creation.

2. Even with these changes, bubblewrap's sandboxing provides significant security benefits by isolating Claude Desktop instances.

3. The ability to create user namespaces is required by many modern containerization and sandboxing tools, and is considered safe on properly configured systems.

4. If you have specific security concerns, consider using the revert script when you're not actively using Claude Desktop Manager.

## Further Information

- [Ubuntu AppArmor Documentation](https://ubuntu.com/server/docs/security-apparmor)
- [Bubblewrap GitHub Repository](https://github.com/containers/bubblewrap)
- [User Namespaces in the Linux Kernel](https://www.kernel.org/doc/html/latest/admin-guide/namespaces/user.html)
