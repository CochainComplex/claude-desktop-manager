# Bubblewrap Sandboxing on Ubuntu 24.04

This document explains how to resolve issues with Claude Desktop Manager's sandbox functionality on Ubuntu 24.04.

## Root Cause: AppArmor User Namespace Restrictions

Ubuntu 24.04 introduces a new security feature that restricts unprivileged user namespaces through AppArmor. This is controlled by the kernel parameter:

```
kernel.apparmor_restrict_unprivileged_userns = 1
```

When this parameter is enabled (which is the default), applications need explicit AppArmor profiles with the `userns` rule to create user namespaces. Since bubblewrap (`bwrap`) is used by Claude Desktop Manager for sandboxing, this restriction prevents the application from working correctly.

### Symptoms of the Issue

If you encounter these errors, you're likely hitting the AppArmor restriction:

- Error messages like `bwrap: setting up uid map: Permission denied`
- Error messages like `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`
- AppArmor denial messages in system logs: `apparmor="DENIED" operation="capable" profile="unprivileged_userns" pid=XXXX comm="bwrap" capability=8 capname="setpcap"`
- Inability to create or start Claude Desktop instances

## Prerequisites

Before applying the fix, ensure your kernel is properly configured:

1. Check that unprivileged user namespaces are enabled:
   ```bash
   sysctl kernel.unprivileged_userns_clone
   ```
   This should return `kernel.unprivileged_userns_clone = 1`

2. Check the AppArmor restriction status (Ubuntu 24.04 only):
   ```bash
   sysctl kernel.apparmor_restrict_unprivileged_userns
   ```
   If this returns `kernel.apparmor_restrict_unprivileged_userns = 1`, the restriction is active.

## Simple Solution

The most straightforward solution is to disable the AppArmor restriction on unprivileged user namespaces:

```bash
# Create a persistent configuration file
echo "kernel.apparmor_restrict_unprivileged_userns = 0" | sudo tee /etc/sysctl.d/60-cmgr-apparmor-namespace.conf

# Apply the setting immediately
sudo sysctl -p /etc/sysctl.d/60-cmgr-apparmor-namespace.conf
```

This change allows bubblewrap to create user namespaces without requiring a specific AppArmor profile.

## Automated Scripts

Claude Desktop Manager includes three utilities to manage this issue:

1. **`scripts/apparmor/check-apparmor-status.sh`** - Diagnoses the root cause of sandboxing issues
2. **`scripts/apparmor/fix-apparmor.sh`** - Applies the necessary system changes
3. **`scripts/apparmor/revert-apparmor-changes.sh`** - Reverts changes and restores original configuration

### Diagnosing the Issue

Run the diagnostic script to identify the problem:

```bash
./scripts/apparmor/check-apparmor-status.sh
```

This script will:
- Check your Ubuntu version and identify if you're on 24.04
- Check if the AppArmor user namespace restriction is enabled
- Test bubblewrap functionality with the settings used by Claude Desktop Manager
- Look for AppArmor denial messages in system logs
- Provide a clear diagnosis with recommended next steps

### Applying the Fix

Run the fix script with sudo:

```bash
sudo ./scripts/apparmor/fix-apparmor.sh
```

This script:
1. Creates a backup of your current system settings
2. Disables the AppArmor restriction on unprivileged user namespaces
3. Ensures unprivileged user namespaces are enabled
4. Verifies that bubblewrap works correctly after changes

### Reverting Changes

If you need to restore your system to its original state:

```bash
sudo ./scripts/apparmor/revert-apparmor-changes.sh
```

This script:
1. Removes the configuration file that disables AppArmor restrictions
2. Re-enables the default AppArmor restrictions
3. Restores any changed kernel parameters from backup
4. Verifies the system has been restored to its original state

## How the Fix Works

Our solution takes a simple, targeted approach to address the root cause:

1. **Disable AppArmor User Namespace Restrictions**: We create a persistent configuration file at `/etc/sysctl.d/60-cmgr-apparmor-namespace.conf` that contains:

```
kernel.apparmor_restrict_unprivileged_userns = 0
```

This change allows bubblewrap to create user namespaces without requiring specific AppArmor profiles. It's the most direct solution to the root cause.

2. **Enable Unprivileged User Namespaces**: We ensure the kernel allows unprivileged user namespaces by setting:

```
kernel.unprivileged_userns_clone = 1
```

3. **Backup Original Settings**: Before making any changes, we create a backup of all relevant system settings to enable easy restoration if needed.

This approach:
- Targets the specific root cause without complexity
- Makes minimal system changes needed for functionality
- Creates no unnecessary configuration files
- Can be easily reverted to restore original security settings
- Doesn't modify or disable AppArmor itself

## Alternative Solutions

If the primary solution doesn't resolve the issue, here are some alternatives:

### Option 1: Manual Run-time Change (Temporary)

You can temporarily disable the restriction until the next reboot:

```bash
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

This change will be lost after rebooting.

### Option 2: Create a bubblewrap AppArmor Profile

Create a dedicated AppArmor profile for bubblewrap:

```bash
sudo tee /etc/apparmor.d/bwrap << EOF
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  # Site-specific additions and overrides
  include if exists <local/bwrap>
}
EOF

sudo systemctl reload apparmor
```

### Option 3: Wait for Official Fix

Ubuntu developers are working on providing AppArmor profiles for applications that legitimately need user namespaces. You can:

1. Keep your system updated with:
   ```bash
   sudo apt update && sudo apt upgrade
   ```

2. Check for updates to the AppArmor package that might include fixes for bubblewrap.

### Option 4: Temporarily Disable AppArmor (Not Recommended)

Only as a last resort:

```bash
sudo systemctl stop apparmor
sudo systemctl disable apparmor
```

Note: This disables all AppArmor protection, which significantly reduces system security and is not recommended.

## Troubleshooting

### Verifying the Issue

1. **Check Ubuntu Version**:
   ```bash
   lsb_release -rs
   ```
   This issue specifically affects Ubuntu 24.04.

2. **Verify AppArmor Restrictions**:
   ```bash
   sysctl kernel.apparmor_restrict_unprivileged_userns
   ```
   A value of `1` confirms the restriction is enabled.

3. **Check AppArmor Denials**:
   ```bash
   sudo journalctl -k | grep -i apparmor | grep -i denied | grep -i bwrap
   ```
   Look for denial messages related to bubblewrap.

4. **Test bubblewrap Command**:
   ```bash
   bwrap --share-net --unshare-user --bind / / echo "test"
   ```
   If this fails, it confirms the issue.

### Fix Applied But Still Not Working

1. **Verify the Fix is Applied**:
   ```bash
   sysctl kernel.apparmor_restrict_unprivileged_userns
   ```
   Should show `0` if the fix is working.

2. **Reboot the System**:
   ```bash
   sudo reboot
   ```
   Some changes require a system restart to fully take effect.

3. **Check for Conflicting Settings**:
   ```bash
   grep -r "apparmor_restrict_unprivileged" /etc/sysctl.d/
   ```
   Look for multiple configuration files that might conflict.

4. **Try Manual Temporary Fix**:
   ```bash
   sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
   sudo sysctl -w kernel.unprivileged_userns_clone=1
   ```
   Test if bubblewrap works immediately after applying these settings.

### System Updates

The issue with bubblewrap on Ubuntu 24.04 is known, and Ubuntu developers may release official fixes in updates. Keep your system updated:

```bash
sudo apt update && sudo apt upgrade
```

This may eventually install an official AppArmor profile for bubblewrap that addresses the issue without disabling security features.

## Security Considerations

The fix disables an Ubuntu 24.04 security feature to allow bubblewrap to work. This has some security implications:

1. **Limited Security Impact**: The change only affects the AppArmor restriction on unprivileged user namespaces and doesn't disable AppArmor itself.

2. **Controlled Risk**: User namespaces have been available in most Linux distributions for years without this specific restriction, including earlier Ubuntu versions.

3. **Sandboxing Benefits**: Even with this change, Claude Desktop Manager's use of bubblewrap still provides valuable isolation between instances.

4. **Temporary Option**: If you have high security requirements, you can use our revert script when not actively using Claude Desktop Manager.

5. **Future Improvements**: Ubuntu developers are working to provide proper AppArmor profiles for applications that need user namespaces, which will eventually provide a better solution.

## Additional Resources

- [Ubuntu Blog: Restricted Unprivileged User Namespaces](https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces)
- [Ubuntu AppArmor Documentation](https://ubuntu.com/server/docs/security-apparmor)
- [Bubblewrap GitHub Repository](https://github.com/containers/bubblewrap)
- [User Namespaces in the Linux Kernel](https://www.kernel.org/doc/html/latest/admin-guide/namespaces/user.html)
