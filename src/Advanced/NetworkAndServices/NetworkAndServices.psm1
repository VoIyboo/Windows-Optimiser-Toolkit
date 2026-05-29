# NetworkAndServices.psm1
# Advanced network repair and service tuning.

. (Join-Path $PSScriptRoot "..\..\Core\QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Logging\Logging.psm1") -ImporterContext 'NetworkAndServices' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Helpers.psm1")         -ImporterContext 'NetworkAndServices' -Force

function Invoke-QFlushDnsCache {
    return Invoke-QOTRunNativeCommandTask -TaskName "Flush DNS cache" -FilePath "ipconfig.exe" -Arguments @("/flushdns")
}

function Invoke-QResetWinsock {
    return Invoke-QOTRunNativeCommandTask -TaskName "Reset Winsock" -FilePath "netsh.exe" -Arguments @("winsock", "reset") -RequiresAdmin
}

function Invoke-QResetWindowsFirewall {
    $taskName = "Reset Windows Firewall"

    if (-not (Test-QOTIsAdmin)) {
        return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Admin required"
    }

    $confirmed = $true
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        $choice = [System.Windows.MessageBox]::Show(
            "Reset Windows Firewall to defaults? Custom inbound/outbound rules may be removed.",
            "Confirm Firewall Reset",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($choice -ne [System.Windows.MessageBoxResult]::Yes) {
            $confirmed = $false
        }
    }
    catch {
    }

    if (-not $confirmed) {
        return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "User cancelled"
    }

    return Invoke-QOTRunNativeCommandTask -TaskName $taskName -FilePath "netsh.exe" -Arguments @("advfirewall", "reset") -RequiresAdmin
}

function Invoke-QRestartWindowsExplorer {
    $taskName = "Restart Windows Explorer"

    try {
        $explorerProcesses = @(Get-Process -Name "explorer" -ErrorAction SilentlyContinue)
        if ($explorerProcesses.Count -eq 0) {
            return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Explorer process not found"
        }

        foreach ($proc in $explorerProcesses) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { }
        }

        Start-Sleep -Milliseconds 700
        Start-Process -FilePath "explorer.exe" -ErrorAction SilentlyContinue | Out-Null
        return New-QOTTaskResult -Name $taskName -Status "Success"
    }
    catch {
        return New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Explorer restart failed" -Error $_.Exception.Message
    }
}

function Invoke-QRebuildWindowsSearchIndex {
    $taskName = "Rebuild Windows Search index"

    try {
        Start-Process -FilePath "control.exe" -ArgumentList "srchadmin.dll" -ErrorAction Stop | Out-Null
        return New-QOTTaskResult -Name $taskName -Status "Success" -Reason "Opened Indexing Options (Advanced > Rebuild)"
    }
    catch {
        return New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Unable to open Indexing Options" -Error $_.Exception.Message
    }
}

function Invoke-QRunSfcSystemFileRepair {
    return Invoke-QOTRunNativeCommandTask -TaskName "Run SFC system file repair" -FilePath "sfc.exe" -Arguments @("/scannow") -RequiresAdmin
}

function Invoke-QRunDismHealthRepair {
    return Invoke-QOTRunNativeCommandTask -TaskName "Run DISM health repair" -FilePath "dism.exe" -Arguments @(
        "/Online",
        "/Cleanup-Image",
        "/RestoreHealth"
    ) -RequiresAdmin
}

function Resolve-QOTNetshIpResetOutcome {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][int]$ExitCode,
        [string]$StdOut,
        [string]$StdErr
    )

    $restartRecommended = $false
    if (-not [string]::IsNullOrWhiteSpace($StdOut) -and $StdOut -match 'Restart the computer to complete this action\.') {
        $restartRecommended = $true
    }

    $accessDenied = $false
    if (-not [string]::IsNullOrWhiteSpace($StdOut) -and $StdOut -match 'Access is denied\.') {
        $accessDenied = $true
    }

    if ($ExitCode -eq 0) {
        if ($restartRecommended) {
            return New-QOTTaskResult -Name $TaskName -Status "Success" -Reason "Restart recommended"
        }

        return New-QOTTaskResult -Name $TaskName -Status "Success"
    }

    if ($ExitCode -eq 1 -and $restartRecommended -and $accessDenied -and [string]::IsNullOrWhiteSpace($StdErr)) {
        Write-QLog "Network: netsh int ip reset completed with protected entries; restart recommended."
        return New-QOTTaskResult -Name $TaskName -Status "Success" -Reason "Restart recommended (some protected entries were skipped)"
    }

    $detail = $StdErr
    if ([string]::IsNullOrWhiteSpace($detail)) {
        $detailLines = @($StdOut -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($detailLines.Count -gt 0) {
            $detail = $detailLines[-1]
        }
    }

    return New-QOTTaskResult -Name $TaskName -Status "Failed" -Reason ("Command exited with code {0}" -f $ExitCode) -Error $detail
}

function Invoke-QNetworkReset {
    $taskName = "Network reset"
    if (-not (Test-QOTIsAdmin)) {
        return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Admin required"
    }

    $command = Get-Command -Name "netsh.exe" -ErrorAction SilentlyContinue
    if (-not $command) {
        return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Command unavailable: netsh.exe"
    }

    try {
        Write-QLog ("Network: running {0} int ip reset" -f $command.Source)

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $command.Source
        $startInfo.Arguments = "int ip reset"
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($startInfo)
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        $exitCode = 0
        try { $exitCode = [int]$process.ExitCode } catch { $exitCode = 0 }

        if (-not [string]::IsNullOrWhiteSpace($stdOut)) {
            Write-QLog ("Network: netsh int ip reset stdout: {0}" -f (($stdOut -replace '\s+', ' ').Trim()))
        }
        if (-not [string]::IsNullOrWhiteSpace($stdErr)) {
            Write-QLog ("Network: netsh int ip reset stderr: {0}" -f (($stdErr -replace '\s+', ' ').Trim())) "WARN"
        }

        return Resolve-QOTNetshIpResetOutcome -TaskName $taskName -ExitCode $exitCode -StdOut $stdOut -StdErr $stdErr
    }
    catch {
        return New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Command failed" -Error $_.Exception.Message
    }
}

function Invoke-QRepairAdapter {
    Write-QLog "Advanced: repair network adapter remains conservative (report mode)."
    return New-QOTTaskResult -Name "Repair network adapter" -Status "Skipped" -Reason "Report mode only in this build"
}

function Invoke-QServiceTune {
    Write-QLog "Advanced: service tuning remains conservative (report mode)."
    return New-QOTTaskResult -Name "Service tuning" -Status "Skipped" -Reason "Report mode only in this build"
}

function Invoke-QOTNetworkAndServices {
    Write-QLog "Invoke-QOTNetworkAndServices called."

    Invoke-QNetworkReset | Out-Null
    Invoke-QRepairAdapter | Out-Null
    Invoke-QServiceTune | Out-Null

    Write-QLog "Invoke-QOTNetworkAndServices completed."
}

Export-ModuleMember -Function `
    Invoke-QNetworkReset, `
    Invoke-QRepairAdapter, `
    Invoke-QServiceTune, `
    Invoke-QFlushDnsCache, `
    Invoke-QResetWinsock, `
    Invoke-QResetWindowsFirewall, `
    Invoke-QRestartWindowsExplorer, `
    Invoke-QRebuildWindowsSearchIndex, `
    Invoke-QRunSfcSystemFileRepair, `
    Invoke-QRunDismHealthRepair, `
    Invoke-QOTNetworkAndServices
