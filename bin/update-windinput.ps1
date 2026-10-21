# Update WindInput without globally disabling Scoop's running-process safety check.
# Usage: & "$env:USERPROFILE\scoop\buckets\Self-Use\bin\update-windinput.ps1"
$ErrorActionPreference = 'Stop'
$scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
$appRoot = Join-Path $scoopRoot 'apps\windinput'
$launcher = Join-Path $appRoot 'current\wind_portable.exe'
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "WindInput portable launcher not found: $launcher"
}
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    throw 'Scoop is not available in PATH.'
}

# -stop unregisters TSF and stops the service; do not force-kill arbitrary processes.
Write-Host 'Stopping WindInput before Scoop update...'
$stop = Start-Process -FilePath $launcher -ArgumentList '-stop' -WorkingDirectory (Split-Path $launcher) -Wait -PassThru
if ($stop.ExitCode -ne 0) {
    throw "WindInput stop failed with exit code $($stop.ExitCode); update cancelled."
}

# Scoop checks executable paths, not only process names. Ensure it has exited.
$deadline = (Get-Date).AddSeconds(15)
do {
    $running = @(Get-Process -Name 'wind_input', 'wind_portable' -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($appRoot + '\', [StringComparison]::OrdinalIgnoreCase) }
        catch { $false }
    })
    if (-not $running.Count) { break }
    Start-Sleep -Milliseconds 250
} while ((Get-Date) -lt $deadline)
if ($running.Count) {
    throw 'WindInput is still running from the Scoop app directory. Close it and retry; update cancelled.'
}

try {
    & scoop update windinput
    if ($LASTEXITCODE -ne 0) { throw "scoop update windinput failed with exit code $LASTEXITCODE" }
} catch {
    # The old version may still be installed. Restore input service if possible.
    if (Test-Path -LiteralPath $launcher) {
        Write-Warning 'Update did not finish. Attempting to restart the existing WindInput.'
        & $launcher -start
    }
    throw
}
# The manifest's post_install starts and registers the newly installed version.
