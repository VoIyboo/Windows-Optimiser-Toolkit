# src\Apps\Apps.Actions.psm1
# Backend action handlers for Apps tab selections

$ErrorActionPreference = "Stop"

# Dot-source the import diagnostics helper so optional imports below get
# logged on failure instead of silently swallowed.
. (Join-Path $PSScriptRoot "..\Core\QOTImportHelper.ps1")

$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\Core\Logging\Logging.psm1") -ImporterContext 'Apps.Actions' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "Apps.Helpers.psm1")            -ImporterContext 'Apps.Actions' -Force -Critical
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "InstallCommonApps.psm1")       -ImporterContext 'Apps.Actions' -Force -Critical

$script:QOT_AppsActionsInProgress = $false
# Cancellation takes effect between packages, after the current installer exits.
$script:QOT_AppsActionsCancelState = $null

function Request-QOTAppsActionsCancel {
    <#
    .SYNOPSIS
    Requests cancellation of any in-progress app install/uninstall batch.
    .DESCRIPTION
    Sets the shared cancel flag. The worker stops before the next package. Safe
    to call when nothing is running - in that case it's a no-op.
    Returns $true if a running operation was asked to cancel, $false if
    there was nothing to cancel.
    #>
    if (-not $script:QOT_AppsActionsInProgress) {
        return $false
    }
    if ($script:QOT_AppsActionsCancelState) {
        try { $script:QOT_AppsActionsCancelState.CancelRequested = $true } catch { }
        try { Write-QLog "Apps actions: cancellation requested by user." "INFO" } catch { }
        return $true
    }
    return $false
}

function Test-QOTAppsActionsCancelRequested {
    <#
    .SYNOPSIS
    Returns $true if a cancel has been requested for the current batch.
    #>
    if (-not $script:QOT_AppsActionsCancelState) { return $false }
    try { return [bool]$script:QOT_AppsActionsCancelState.CancelRequested } catch { return $false }
}

function Get-QOTSilentUninstallCommand {
    param(
        [Parameter(Mandatory)][object]$App
    )

    $cmd = $App.UninstallString
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }

    # Match the executable itself, including an optional quoted full path.
    if ($cmd -match '^\s*(?:"(?:[^"]*\\)?msiexec(?:\.exe)?"|(?:[^\s"]*\\)?msiexec(?:\.exe)?)(?=\s|$)') {
        $cmd = $cmd -replace '(?i)(\s)/I(?=[{\s]|$)', '$1/X'
        if ($cmd -notmatch '(?i)\s/(?:q[nbrf]?[!+\-]?|quiet|passive)(?=\s|$)') { $cmd += ' /qn' }
        if ($cmd -notmatch '(?i)\s/(?:norestart|forcerestart|promptrestart)(?=\s|$)') { $cmd += ' /norestart' }
    }

    return $cmd
}

function ConvertTo-QOTCommandParts {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
    $cmd = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }

    $exePath = ""
    $argString = ""

    if ($cmd.StartsWith('"')) {
        # Quoted exe path - take everything between the opening and matching close quote.
        $closeIdx = $cmd.IndexOf('"', 1)
        if ($closeIdx -le 1) { return $null }  # malformed - no closing quote
        $exePath = $cmd.Substring(1, $closeIdx - 1)
        if ($cmd.Length -gt ($closeIdx + 1)) {
            $argString = $cmd.Substring($closeIdx + 1).Trim()
        }
    }
    else {
        # Resolve an unquoted path with spaces while leaving its argument text intact.
        $match = [regex]::Match($cmd, '^(.+?\.exe)(?=\s|$)\s*(.*)$', 'IgnoreCase')
        if ($match.Success -and (Test-Path -LiteralPath $match.Groups[1].Value -PathType Leaf)) {
            $exePath = $match.Groups[1].Value
            $argString = $match.Groups[2].Value
        }
        else {
            $parts = $cmd -split '\s+', 2
            $exePath = $parts[0]
            if ($parts.Count -gt 1) { $argString = $parts[1] }
        }
    }

    # If the exe still isn't a direct file on disk, try resolving via PATH.
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf -ErrorAction SilentlyContinue)) {
        $resolved = Get-Command -Name $exePath -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved -and $resolved.Path) { $exePath = $resolved.Path }
    }

    # Final validation: must be a real file before we ever execute it.
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf -ErrorAction SilentlyContinue)) {
        return $null
    }

    return [pscustomobject]@{ ExePath = $exePath; Arguments = $argString }
}

function Start-QOTProcessFromCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$Wait
    )

    $parts = ConvertTo-QOTCommandParts -Command $Command
    if (-not $parts) { throw "Uninstall executable could not be resolved." }

    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $parts.ExePath
    $info.Arguments = $parts.Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true

    $process = [Diagnostics.Process]::Start($info)
    try {
        if ($Wait) {
            if (-not $process.WaitForExit(600000)) { throw "Uninstaller still running after 10 minutes. Check its status before retrying." }
            if ($process.ExitCode -notin @(0, 1641, 3010)) {
                throw "Uninstaller returned exit code $($process.ExitCode)."
            }
        }
    }
    finally { $process.Dispose() }
}

function Invoke-QOTInstallCommonAppItem {
    param(
        [Parameter(Mandatory)][object]$App
    )

    if (-not $App) { return }

    if (-not (Get-Command Install-QOTCommonApp -ErrorAction SilentlyContinue)) {
        throw "Install-QOTCommonApp not found. Check Apps\\InstallCommonApps.psm1 is imported."
    }

    if ([string]::IsNullOrWhiteSpace($App.WingetId)) {
        return
    }

    Install-QOTCommonApp -Name $App.Name -WingetId $App.WingetId
    $App.IsSelected = $false
}

function Invoke-QOTUninstallAppItem {
    param(
        [Parameter(Mandatory)][object]$App
    )

    if (-not $App) { return }

    $name = $App.Name
    $cmd  = Get-QOTSilentUninstallCommand -App $App

    if ([string]::IsNullOrWhiteSpace($cmd)) {
        try { Write-QLog ("Skipping uninstall for '{0}' because UninstallString is empty." -f $name) "WARN" } catch { }
        return
    }

    try {
        try { Write-QLog ("Uninstalling: {0}" -f $name) "DEBUG" } catch { }
        Start-QOTProcessFromCommand -Command $cmd -Wait
        $App.IsSelected = $false
    }
    catch {
        try { Write-QLog ("Failed uninstall '{0}': {1}" -f $name, $_.Exception.Message) "ERROR" } catch { }
    }
}

function Invoke-QOTRunSelectedAppsActions {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$InstallGrid
    )

    if ($script:QOT_AppsActionsInProgress) {
        return [pscustomobject]@{ Status = 'Skipped'; Reason = 'Another applications batch is running.' }
    }

    Commit-QOTGridEdits -Grid $AppsGrid
    Commit-QOTGridEdits -Grid $InstallGrid
    $installedItems = @($AppsGrid.ItemsSource)
    $installed = @($installedItems | Where-Object IsSelected -eq $true)
    $common = @($InstallGrid.ItemsSource | Where-Object { $_.IsSelected -and $_.IsInstallable -ne $false })
    $commonNames = Get-QOTInstalledAppNameSet -Apps $common
    $installedNames = Get-QOTInstalledAppNameSet -Apps $installed
    $dataset = Get-QOTInstalledAppDataset -Apps $installedItems

    $tasks = [Collections.Generic.List[object]]::new()
    foreach ($app in $installed) {
        if ($commonNames.Contains((Get-QOTNormalizedAppName $app.Name))) { continue }
        $tasks.Add([pscustomobject]@{ Kind='Uninstall'; Row=$app; Command=(Get-QOTSilentUninstallCommand $app) })
    }
    foreach ($app in $common) {
        if ($installedNames.Contains((Get-QOTNormalizedAppName $app.Name))) { continue }
        if (Test-QOTCommonAppInstalled $app $dataset) {
            $app.Status = 'Installed'
            if ($app.PSObject.Properties['StatusText']) { $app.StatusText = 'Status: Installed' }
            $app.IsInstallable = $false
            $app.IsSelected = $false
            continue
        }
        $tasks.Add([pscustomobject]@{ Kind='Install'; Row=$app; Command=[string]$app.WingetId })
    }
    if (-not $tasks.Count) {
        $InstallGrid.Items.Refresh()
        return [pscustomobject]@{ Status='Skipped'; Reason='No applicable selections. Check for duplicate install and uninstall selections.' }
    }

    # Only the UI thread accesses grid rows. The worker receives plain task descriptions.
    $requests = foreach ($task in $tasks) {
        [pscustomobject]@{ Kind=$task.Kind; Name=$task.Row.Name; Command=$task.Command }
    }
    $script:QOT_AppsActionsInProgress = $true
    $script:QOT_AppsActionsCancelState = [hashtable]::Synchronized(@{ CancelRequested = $false })
    $worker = [powershell]::Create()
    $timer = [Windows.Threading.DispatcherTimer]::new()
    try {
        $null = $worker.AddScript({
            param($AppsModule, $InstallModule, [object[]]$Requests, $CancelState)
            $ErrorActionPreference = 'Stop'
            Import-Module $AppsModule -DisableNameChecking
            Import-Module $InstallModule -DisableNameChecking
            $uninstallResults = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
            foreach ($request in $Requests) {
                if ($CancelState.CancelRequested) { break }
                if ($request.Kind -eq 'Uninstall' -and $uninstallResults.ContainsKey([string]$request.Command)) {
                    $uninstallResults[[string]$request.Command]
                    continue
                }
                $status = 'Success'
                $reason = ''
                try {
                    if ($request.Kind -eq 'Uninstall') {
                        Start-QOTProcessFromCommand -Command $request.Command -Wait
                    }
                    elseif (Test-QOTWingetAppInstalled -WingetId $request.Command) {
                        $status = 'Skipped'
                        $reason = 'Already installed'
                    }
                    else {
                        Install-QOTCommonApp -Name $request.Name -WingetId $request.Command
                    }
                } catch {
                    $status = 'Failed'
                    $reason = $_.Exception.Message
                }
                $outcome = [pscustomobject]@{ Status=$status; Reason=$reason }
                if ($request.Kind -eq 'Uninstall') { $uninstallResults[[string]$request.Command] = $outcome }
                $outcome
            }
        }).AddArgument($PSCommandPath).AddArgument((Join-Path $PSScriptRoot 'InstallCommonApps.psm1')).AddArgument(@($requests)).AddArgument($script:QOT_AppsActionsCancelState)
        $pending = $worker.BeginInvoke()
        # Pump WPF events until this action has an outcome for the main Play queue.
        $frame = [Windows.Threading.DispatcherFrame]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $timer.Add_Tick({ if ($pending.IsCompleted) { $frame.Continue = $false } }.GetNewClosure())
        $timer.Start()
        [Windows.Threading.Dispatcher]::PushFrame($frame)
        $results = @($worker.EndInvoke($pending))
        $cancelled = $script:QOT_AppsActionsCancelState.CancelRequested
    }
    finally {
        $timer.Stop()
        $worker.Dispose()
        $script:QOT_AppsActionsInProgress = $false
        $script:QOT_AppsActionsCancelState = $null
    }

    $errors = [Collections.Generic.List[string]]::new()
    $didChange = $false
    for ($i = 0; $i -lt $results.Count; $i++) {
        $result = $results[$i]
        $task = $tasks[$i]
        $row = $task.Row
        if ($result.Status -eq 'Failed') {
            $errors.Add(("{0} {1}: {2}" -f $task.Kind, $row.Name, $result.Reason))
        } else {
            $row.IsSelected = $false
            if ($result.Status -eq 'Success') { $didChange = $true }
        }
        if ($task.Kind -eq 'Install') {
            $row.Status = if ($result.Status -eq 'Failed') { 'Failed' } else { 'Installed' }
            $row.IsInstallable = $result.Status -eq 'Failed'
            if ($row.PSObject.Properties['StatusText']) { $row.StatusText = "Status: $($row.Status)" }
        }
        $level = if ($result.Status -eq 'Failed') { 'ERROR' } else { 'INFO' }
        try { Write-QLog ("{0} {1}: {2} {3}" -f $task.Kind, $row.Name, $result.Status, $result.Reason) $level } catch { }
    }
    $InstallGrid.Items.Refresh()
    $AppsGrid.Items.Refresh()
    if ($didChange) { Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid -ForceScan }
    if ($errors.Count) { return [pscustomobject]@{ Status='Failed'; Reason=($errors -join '; ') } }
    if ($cancelled) { return [pscustomobject]@{ Status='Skipped'; Reason='Cancelled between packages.' } }
    if (-not $didChange) { return [pscustomobject]@{ Status='Skipped'; Reason='Packages already installed.' } }
    return [pscustomobject]@{ Status='Success'; Reason='' }
}

function Invoke-QOTInstallSelectedCommonApps {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid
    )

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true -and -not [string]::IsNullOrWhiteSpace($_.WingetId) -and $_.IsInstallable -ne $false })

    if ($selected.Count -eq 0) {
        try { Write-QLog "Install skipped. No common apps selected." "DEBUG" } catch { }
        return
    }

    foreach ($app in $selected) {
        try {
            if (-not (Get-Command Install-QOTCommonApp -ErrorAction SilentlyContinue)) {
                throw "Install-QOTCommonApp not found. Check Apps\InstallCommonApps.psm1 is imported."
            }

            Install-QOTCommonApp -Name $app.Name -WingetId $app.WingetId
            $app.IsSelected = $false
        }
        catch {
            try { Write-QLog ("Install failed for '{0}': {1}" -f $app.Name, $_.Exception.Message) "ERROR" } catch { }
        }
    }
}

function Invoke-QOTUninstallSelectedApps {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [switch]$Rescan
    )

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true })
    $didUninstall = $false

    if ($selected.Count -eq 0) {
        try { Write-QLog "Uninstall skipped. No installed apps selected." "DEBUG" } catch { }
        return
    }

    foreach ($app in $selected) {
        $name = $app.Name
        $cmd  = Get-QOTSilentUninstallCommand -App $app

        if ([string]::IsNullOrWhiteSpace($cmd)) {
            try { Write-QLog ("Skipping uninstall for '{0}' because UninstallString is empty." -f $name) "WARN" } catch { }
            continue
        }

        try {
            try { Write-QLog ("Uninstalling: {0}" -f $name) "DEBUG" } catch { }
            Start-QOTProcessFromCommand -Command $cmd -Wait
            $didUninstall = $true
            $app.IsSelected = $false
        }
        catch {
            try { Write-QLog ("Failed uninstall '{0}': {1}" -f $name, $_.Exception.Message) "ERROR" } catch { }
        }
    }

    if ($Rescan -and $didUninstall) {
        Start-QOTInstalledAppsScanAsync -AppsGrid $Grid -ForceScan
    }
}

Export-ModuleMember -Function Get-QOTSilentUninstallCommand, Start-QOTProcessFromCommand, Invoke-QOTInstallCommonAppItem, Invoke-QOTUninstallAppItem, Invoke-QOTRunSelectedAppsActions, Invoke-QOTInstallSelectedCommonApps, Invoke-QOTUninstallSelectedApps, Request-QOTAppsActionsCancel, Test-QOTAppsActionsCancelRequested



