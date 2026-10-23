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

Scoop exposes `sing-box-manage` on PATH using its shim directory. The manager script is at `<scoop-root>\persist\sing-box\sing-box.ps1`.

Installing or updating sing-box automatically attempts to register (or refresh) a Windows Scheduled Task named `sing-box`. Windows requests administrator authorization (UAC) if required. Cancelling UAC or encountering registration errors prints a warning without failing the Scoop installation. You can retry later in an elevated PowerShell session using `sing-box-manage install`.

Configuration is expected at `<scoop-root>\persist\sing-box\config\config.json`. If the file exists during installation, it is checked using the newly installed sing-box executable before task registration. A missing config produces a warning, and the task is registered but cannot run successfully until valid configuration is added; run `sing-box-manage install` after creating the config to validate it. The manager script is persisted, and the prior version is backed up before an upgrade replaces it. After updating sing-box, the version 4 manager replaces the old version 3 script while retaining a timestamped backup.

To manage the task, use a normal PowerShell session. `status` does not require elevation. The `install`, `uninstall`, `start`, `stop`, and `restart` commands automatically request administrator approval through Windows UAC when necessary:

```powershell
sing-box-manage status
sing-box-manage start
sing-box-manage stop
sing-box-manage restart
sing-box-manage install
sing-box-manage uninstall
```

If UAC is cancelled, the management command fails with an explanatory error; it never bypasses Windows authorization. If the elevated action fails, the original command reports its nonzero exit code. To apply the updated manager on an existing installation, run `scoop update sing-box` (or `scoop update sing-box -f` when the installed version is already current).

The task runs the Scoop `current` version of `sing-box.exe` **as SYSTEM**, at system startup, with highest privileges and a one-minute restart interval after failure (up to 999 retries). `install` refreshes the existing task instead of creating duplicates. The installation hook registers the task, but does not start it immediately; run `sing-box-manage start` or reboot. The task action executes `sing-box.exe` directly, not a writable PowerShell script as SYSTEM.

**Updates:** stop sing-box before `scoop update sing-box`; the installation hook will attempt to update the scheduled task automatically. If authorization is declined, it can be registered manually afterward. This does not use WinSW or automatically remove a pre-existing WinSW service. Keep any legacy service stopped to avoid running two copies.
