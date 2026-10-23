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


## sing-box on Windows: startup and persistent configuration

The Scoop manifest keeps the binary under <scoop-root>\apps\sing-box\current and stores configuration and runtime data in two persistent directories:

    <scoop-root>\persist\sing-box\config\config.json
    <scoop-root>\persist\sing-box\data\

The task launches sing-box with its built-in configuration and working-directory flags:

    sing-box -D "<scoop-root>\persist\sing-box\data" -C "<scoop-root>\persist\sing-box\config" run

The -C option reads the JSON configuration files in config by filename order (a single config.json works as before); -D keeps relative runtime files under data across Scoop upgrades. Do not keep extra .json backup files in the config directory: sing-box may load them too. Configuration is checked using the **same** -C / -D flags before registration.

### Installation and control

After installing or updating sing-box with Scoop, the manifest copies the readable manager source from scripts/sing-box-manage.ps1 in this bucket to persist/sing-box/sing-box.ps1. A changed existing manager is backed up before replacement; no longer is the entire PowerShell source embedded in the JSON manifest.

If the configuration directory contains at least one .json file, Scoop tries to **register or refresh** the \sing-box Windows Scheduled Task automatically, asking for Windows UAC consent where needed. If there is no config file, the task registration is skipped with a warning rather than installing a boot task that will immediately fail. Add config.json, then register manually with the command below. A cancelled UAC prompt will not abort the Scoop installation.

The manager is available via the Scoop PATH shim:

```powershell
sing-box-manage status
sing-box-manage check
sing-box-manage install
sing-box-manage start
sing-box-manage restart
sing-box-manage stop
sing-box-manage uninstall
```

The new check command validates all JSON config files without UAC. Mutating operations request UAC automatically; status only requests UAC when necessary to verify a task invisible to the standard user. Installation checks configuration and verifies that the task exists after registering. Task errors are returned to the calling console, rather than merely reporting that the elevated process exited.

The task starts **at system boot** as SYSTEM, using the Scoop current executable path, without WinSW. Task Scheduler retries a failing process at one-minute intervals (up to 999 attempts). Registration does not start the task immediately; use sing-box-manage start once, or reboot. Stop it before running scoop update sing-box -f; the installation hook will refresh the task after the update.

**Security:** A SYSTEM task executing a Scoop binary under a user-writable directory has a privilege-escalation risk. This setup retains the prior SYSTEM behavior for compatibility with privileged TUN configurations. Use this only on a trusted single-user installation; for multi-user systems, use an administrator-protected executable/configuration location or a lower-privilege task instead. Do not leave a separate WinSW service running.
