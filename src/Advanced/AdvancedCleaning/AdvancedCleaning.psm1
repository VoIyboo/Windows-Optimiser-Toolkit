# AdvancedCleaning.psm1
# Higher-risk cleanup and maintenance operations.

. (Join-Path $PSScriptRoot "..\..\Core\QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Config\Config.psm1")   -ImporterContext 'AdvancedCleaning' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Logging\Logging.psm1") -ImporterContext 'AdvancedCleaning' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Helpers.psm1")         -ImporterContext 'AdvancedCleaning' -Force

function Invoke-QRemoveOldProfiles {
    [CmdletBinding()]
    param()

    Write-QLog "Advanced: Remove old user profiles is in report-only mode."
    return New-QOTTaskResult -Name "Remove unused user profiles" -Status "Skipped" -Reason "Report mode only in this build"
}

function Invoke-QAggressiveRestoreCleanup {
    [CmdletBinding()]
    param()

    Write-QLog "Advanced: Aggressive restore/log cleanup remains safety-gated in this build."
    return New-QOTTaskResult -Name "Aggressive restore/log cleanup" -Status "Skipped" -Reason "Not implemented in this build"
}

function Invoke-QCleanComponentStore {
    return Invoke-QOTRunNativeCommandTask -TaskName "Clean Windows Component Store" -FilePath "dism.exe" -Arguments @(
        "/Online",
        "/Cleanup-Image",
        "/StartComponentCleanup",
        "/NoRestart"
    ) -RequiresAdmin
}

function Invoke-QAggressiveComponentStoreCleanup {
    return Invoke-QOTRunNativeCommandTask -TaskName "Aggressive component store cleanup" -FilePath "dism.exe" -Arguments @(
        "/Online",
        "/Cleanup-Image",
        "/StartComponentCleanup",
        "/ResetBase",
        "/NoRestart"
    ) -RequiresAdmin
}

function Invoke-QAdvancedDeepCache {
    # Keep legacy action id working; map to high-risk DISM reset-base cleanup.
    return Invoke-QAggressiveComponentStoreCleanup
}

function Invoke-QScanUnusedDeviceDrivers {
    $taskName = "Scan unused device drivers (report only)"

    $pnputil = Get-Command -Name "pnputil.exe" -ErrorAction SilentlyContinue
    if (-not $pnputil) {
        return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "pnputil unavailable"
    }

    try {
        $output = @(& $pnputil.Source /enum-drivers 2>&1)
        $drivers = @($output | Where-Object { $_ -match '^\s*Published Name\s*:\s*oem\d+\.inf\s*$' })
        $count = $drivers.Count

        Write-QLog ("Advanced: driver scan complete (report mode). Enumerated packages: {0}" -f $count)
        return New-QOTTaskResult -Name $taskName -Status "Success" -Reason ("Scan/report mode only. Enumerated driver packages: {0}" -f $count)
    }
    catch {
        return New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Driver scan failed" -Error $_.Exception.Message
    }
}

function Invoke-QDisableTelemetryScheduledTasks {
    $taskName = "Disable telemetry scheduled tasks"

    if (-not (Test-QOTIsAdmin)) {
        return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Admin required"
    }

    $tasks = @(
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "Microsoft Compatibility Appraiser" },
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "ProgramDataUpdater" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "Consolidator" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "UsbCeip" },
        @{ Path = "\Microsoft\Windows\DiskDiagnostic\"; Name = "Microsoft-Windows-DiskDiagnosticDataCollector" }
    )

    $disabled = 0
    $skipped = 0
    $failed = 0

    foreach ($task in $tasks) {
        try {
            $scheduledTask = Get-ScheduledTask -TaskPath ([string]$task.Path) -TaskName ([string]$task.Name) -ErrorAction SilentlyContinue
            if (-not $scheduledTask) {
                $skipped++
                continue
            }

            if ([string]$scheduledTask.State -eq "Disabled") {
                $skipped++
                continue
            }

            Disable-ScheduledTask -TaskPath ([string]$task.Path) -TaskName ([string]$task.Name) -ErrorAction Stop | Out-Null
            $disabled++
        }
        catch {
            $failed++
        }
    }

    if ($failed -gt 0 -and $disabled -eq 0) {
        return New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Task disable operations failed"
    }

    if ($disabled -gt 0) {
        return New-QOTTaskResult -Name $taskName -Status "Success" -Reason ("Disabled {0} task(s); skipped {1}." -f $disabled, $skipped)
    }

    return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "No matching telemetry tasks found"
}

function Invoke-QEnableTelemetryScheduledTasks {
    $taskName = "Enable telemetry scheduled tasks"

    if (-not (Test-QOTIsAdmin)) {
        return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Admin required"
    }

    $tasks = @(
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "Microsoft Compatibility Appraiser" },
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "ProgramDataUpdater" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "Consolidator" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "UsbCeip" },
        @{ Path = "\Microsoft\Windows\DiskDiagnostic\"; Name = "Microsoft-Windows-DiskDiagnosticDataCollector" }
    )

    $enabled = 0
    $skipped = 0
    $failed = 0

    foreach ($task in $tasks) {
        try {
            $scheduledTask = Get-ScheduledTask -TaskPath ([string]$task.Path) -TaskName ([string]$task.Name) -ErrorAction SilentlyContinue
            if (-not $scheduledTask) {
                $skipped++
                continue
            }

            if ([string]$scheduledTask.State -ne "Disabled") {
                $skipped++
                continue
            }

            Enable-ScheduledTask -TaskPath ([string]$task.Path) -TaskName ([string]$task.Name) -ErrorAction Stop | Out-Null
            $enabled++
        }
        catch {
            $failed++
        }
    }

    if ($failed -gt 0 -and $enabled -eq 0) {
        return New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Task enable operations failed"
    }

    if ($enabled -gt 0) {
        return New-QOTTaskResult -Name $taskName -Status "Success" -Reason ("Enabled {0} task(s); skipped {1}." -f $enabled, $skipped)
    }

    return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "No matching telemetry tasks found"
}

Export-ModuleMember -Function `
    Invoke-QRemoveOldProfiles, `
    Invoke-QAggressiveRestoreCleanup, `
    Invoke-QAdvancedDeepCache, `
    Invoke-QCleanComponentStore, `
    Invoke-QAggressiveComponentStoreCleanup, `
    Invoke-QScanUnusedDeviceDrivers, `
    Invoke-QDisableTelemetryScheduledTasks, `
    Invoke-QEnableTelemetryScheduledTasks
