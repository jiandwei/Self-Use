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


## sing-box scheduled startup (PowerShell manager)

The Scoop manifest exposes `sing-box-manage` through the normal Scoop shims directory on PATH. The management script resides in `<scoop-root>\persist\sing-box\sing-box.ps1`. On upgrade, an earlier manager is backed up before being replaced with version 2 of the task manager.

Put the configuration in `<scoop-root>\persist\sing-box\config\config.json`. Start an **elevated PowerShell** session after installing or updating and use:

```powershell
sing-box-manage install
sing-box-manage start
sing-box-manage status
sing-box-manage restart
sing-box-manage stop
sing-box-manage uninstall
```

`install` validates the configuration with `sing-box check` and registers a Windows Scheduled Task named `sing-box` at startup. The task runs `sing-box.exe` from Scoop's `current` path **as SYSTEM**, with highest privileges, no execution time limit, and restart-on-failure at one-minute intervals (up to 999 attempts). Running `install` again refreshes the task's executable/config paths after an upgrade. Run `start` to launch it immediately; the task also starts at the next system boot. `status` shows task state and last result.

The task runs the executable directly rather than executing a writable management script as SYSTEM. Stop the task before `scoop update sing-box` and run `sing-box-manage install` again afterward to revalidate the configuration. This does not use WinSW, remove any old WinSW service, or automatically install a task as part of Scoop installation. `uninstall` removes only the scheduled task; it does not remove Scoop's sing-box installation. Do not keep an old WinSW service running at the same time.
