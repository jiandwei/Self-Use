# Self-Use sing-box task manager v6
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('install', 'uninstall', 'start', 'stop', 'restart', 'status', 'check')]
    [string]$Action = 'status',
    [string]$ValidationExe = ''
)

$ErrorActionPreference = 'Stop'
$TaskName = 'sing-box'
$TaskPath = '\'
$PersistDir = $PSScriptRoot
$ScoopRoot = Split-Path (Split-Path $PersistDir -Parent) -Parent
$ExePath = Join-Path $ScoopRoot 'apps\sing-box\current\sing-box.exe'
$ConfigDir = Join-Path $PersistDir 'config'
$DataDir = Join-Path $PersistDir 'data'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedManagementAction {
    $escapedScript = $PSCommandPath.Replace("'", "''")
    $escapedValidationExe = $ValidationExe.Replace("'", "''")
    $logDir = Join-Path $PersistDir 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $outputFile = Join-Path $logDir ('manage-' + [guid]::NewGuid().ToString('N') + '.log')
    $escapedOutput = $outputFile.Replace("'", "''")
    # Capture all streams in the elevated process; keep output and exit status visible.
    $command = "try { & '$escapedScript' -Action '$Action' -ValidationExe '$escapedValidationExe' *>&1 | Out-File -LiteralPath '$escapedOutput' -Encoding UTF8; exit 0 } catch { (`$_ | Out-String) | Out-File -LiteralPath '$escapedOutput' -Encoding UTF8 -Append; exit 1 }"
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $powershell = Join-Path $PSHOME 'powershell.exe'
    if (!(Test-Path -LiteralPath $powershell -PathType Leaf)) {
        $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    }
    Write-Host "Requesting administrator approval for sing-box '$Action'..."
    try {
        $process = Start-Process -FilePath $powershell -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) -PassThru -Wait -ErrorAction Stop
        if (Test-Path -LiteralPath $outputFile) {
            Get-Content -LiteralPath $outputFile -Encoding UTF8 | ForEach-Object { Write-Host $_ }
        } else {
            Write-Warning 'Elevated process returned no diagnostic output.'
        }
        if ($process.ExitCode -ne 0) {
            throw "Elevated sing-box '$Action' failed (exit code $($process.ExitCode))."
        }
    } catch {
        throw "Administrator operation '$Action' failed or was cancelled: $($_.Exception.Message)"
    } finally {
        Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
    }
}

if ($Action -notin @('status', 'check') -and !(Test-Administrator)) {
    Invoke-ElevatedManagementAction
    return
}

function Get-SingBoxTask {
    # Non-admin users might not see tasks registered with the SYSTEM account.
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
        if ($task) { return $task }
    } catch {
        if (!(Test-Administrator)) {
            throw "Task '$TaskName' is not visible in this session; administrator verification is required."
        }
        $tasks = @(Get-ScheduledTask -TaskPath $TaskPath -ErrorAction Stop)
        return ($tasks | Where-Object { $_.TaskName -eq $TaskName } | Select-Object -First 1)
    }
    if (!(Test-Administrator)) {
        throw "Task '$TaskName' is not visible in this session; administrator verification is required."
    }
    return $null
}

function Assert-ConfigFiles {
    if (!(Test-Path -LiteralPath $ConfigDir -PathType Container)) {
        throw "Missing sing-box config directory: $ConfigDir"
    }
    if (!(Get-ChildItem -LiteralPath $ConfigDir -File -Filter '*.json' | Select-Object -First 1)) {
        throw "No .json configuration files in $ConfigDir. Create config.json before registering startup."
    }
    if (!(Test-Path -LiteralPath $DataDir -PathType Container)) {
        New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    }
}

function Assert-TaskInstalled {
    if (!(Get-SingBoxTask)) {
        throw "Task '$TaskName' is not installed. Run 'sing-box-manage install' first."
    }
}

function Wait-UntilStopped {
    for ($i = 0; $i -lt 50; $i++) {
        if ((Get-SingBoxTask).State -ne 'Running') { return }
        Start-Sleep -Milliseconds 200
    }
    throw "Timed out waiting for task '$TaskName' to stop."
}

switch ($Action) {
    'check' {
        Assert-ConfigFiles
        if (!(Test-Path -LiteralPath $ExePath -PathType Leaf)) { throw "sing-box executable not found: $ExePath" }
        & $ExePath -D $DataDir -C $ConfigDir check
        if ($LASTEXITCODE -ne 0) { throw "Config check failed (exit code $LASTEXITCODE)." }
        Write-Host "Config is valid: $ConfigDir"
    }
    'install' {
        Assert-ConfigFiles
        $checkExe = $ExePath
        if ($ValidationExe) { $checkExe = $ValidationExe }
        if (!(Test-Path -LiteralPath $checkExe -PathType Leaf)) { throw "sing-box executable not found: $checkExe" }
        Write-Host "Validating sing-box configuration files in $ConfigDir..."
        & $checkExe -D $DataDir -C $ConfigDir check
        if ($LASTEXITCODE -ne 0) { throw "Config check failed (exit code $LASTEXITCODE)." }

        # Keep the task action on the stable Scoop current binary, not on the manager script.
        $taskAction = New-ScheduledTaskAction -Execute $ExePath -Argument ('-D "{0}" -C "{1}" run' -f $DataDir, $ConfigDir) -WorkingDirectory $DataDir
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description 'Start sing-box as SYSTEM at boot; retry on failure.' -Force | Out-Null
        $registeredTask = Get-SingBoxTask
        if (!$registeredTask) { throw "Task '$TaskName' could not be found after registration." }
        Write-Host "Verified scheduled task '$TaskName' ($($registeredTask.State))."
        Write-Host "Installed startup task '$TaskName'. Run 'sing-box-manage start' to start now."
    }
    'uninstall' {
        $task = Get-SingBoxTask
        if (!$task) {
            Write-Host "Task '$TaskName' is not installed."
        } else {
            if ($task.State -eq 'Running') {
                Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
                Wait-UntilStopped
            }
            Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
            Write-Host "Removed startup task '$TaskName'."
        }
    }
    'start' {
        Assert-TaskInstalled
        Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
        Write-Host 'sing-box start requested.'
    }
    'stop' {
        Assert-TaskInstalled
        Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
        Wait-UntilStopped
        Write-Host 'sing-box stopped.'
    }
    'restart' {
        Assert-TaskInstalled
        if ((Get-SingBoxTask).State -eq 'Running') {
            Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
            Wait-UntilStopped
        }
        Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
        Write-Host 'sing-box restart requested.'
    }
    'status' {
        try {
            $task = Get-SingBoxTask
            if ($task) {
                $info = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
            }
        } catch {
            if (!(Test-Administrator)) {
                Write-Host 'Unable to query task details without administrator rights; checking with UAC...'
                Invoke-ElevatedManagementAction
                return
            }
            throw
        }
        if (!$task) {
            Write-Host "Task '$TaskName' is not installed (verified as administrator)."
        } else {
            $task | Select-Object TaskName, State
            $info | Select-Object LastRunTime, LastTaskResult, NextRunTime
        }
    }
}
