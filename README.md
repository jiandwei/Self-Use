# Self-Use

Personal Scoop bucket.

## WindInput updates

Scoop checks for running application processes **before** calling manifest uninstall hooks. Because WindInput runs as the `wind_input` background service, a normal `scoop update windinput` while it is active is blocked by design. This is not fixable by adding a `pre_uninstall` action to the manifest.

Use the repository helper from PowerShell (adapt the bucket directory if you cloned it under a different name):

```powershell
& "$env:USERPROFILE\scoop\buckets\Self-Use\bin\update-windinput.ps1"
```

The helper runs WindInput's official portable launcher with `-stop`, waits until the Scoop-managed processes exit, then runs `scoop update windinput`. The manifest's `post_install` starts the new version. If the update command fails, the helper attempts to start the existing installation again.

For a one-off manual update:

```powershell
& "$env:USERPROFILE\scoop\apps\windinput\current\wind_portable.exe" -stop
scoop update windinput
```

Do not enable Scoop's global `ignore_running_processes` setting to fix this: it bypasses protection for all applications.
