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
$script:QOT_AppsActionsRunspace = $null
$script:QOT_AppsActionsPowerShell = $null
$script:QOT_AppsActionsAsyncResult = $null
$script:QOT_AppsActionsTimer = $null
# Shared cancellation state. The worker runspace receives a reference to this
# synchronized hashtable and checks .CancelRequested between operations. The UI
# side can flip CancelRequested via Request-QOTAppsActionsCancel and the
# polling timer will tear the runspace down on the next tick.
$script:QOT_AppsActionsCancelState = $null

function Request-QOTAppsActionsCancel {
    <#
    .SYNOPSIS
    Requests cancellation of any in-progress app install/uninstall batch.
    .DESCRIPTION
    Sets the shared cancel flag. The polling timer (and the worker between
    operations) will see the flag and tear down the runspace cleanly. Safe
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

    if ($cmd -match "(?i)msiexec") {
        $cmd = $cmd -replace "(?i)\\s/I\\b", " /X"
        if ($cmd -notmatch "(?i)\\s/(qn|quiet)\\b") {
            $cmd = "$cmd /qn /norestart"
        }
    }

    return $cmd
}

function ConvertTo-QOTCommandParts {
    <#
    .SYNOPSIS
    Parses a registry UninstallString (or any Windows command line) into a
    validated [exe path] + [args array] pair.
    .DESCRIPTION
    Returns $null if the command line is empty, malformed, or the executable
    does not exist on disk. Used to convert the raw UninstallString registry
    value into something safe to pass to Start-Process without going through
    cmd.exe /c interpolation.

    Handles:
      - Quoted exe paths:    "C:\Program Files\App\uninst.exe" /S
      - Unquoted exe paths:  C:\Tools\unins.exe /quiet
      - Paths with spaces (greedy match for longest existing prefix)
      - Environment variable expansion: %ProgramFiles%, %SystemRoot% etc
      - Executable-on-PATH lookup via Get-Command (msiexec, etc)
    .OUTPUTS
    [pscustomobject] @{ ExePath = <full path>; Arguments = <string[]> }
    or $null if the command could not be safely resolved.
    #>
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
        # Unquoted. Greedy match: longest whitespace-prefixed substring that
        # actually resolves as a file on disk. Handles unquoted paths-with-spaces.
        $tokens = $cmd -split '\s+'
        for ($i = $tokens.Count; $i -ge 1; $i--) {
            $candidate = ($tokens[0..($i - 1)] -join ' ')
            $hit = $null
            if (Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction SilentlyContinue) {
                $hit = $candidate
            }
            elseif (Test-Path -LiteralPath ($candidate + '.exe') -PathType Leaf -ErrorAction SilentlyContinue) {
                $hit = $candidate + '.exe'
            }
            if ($hit) {
                $exePath = $hit
                if ($i -lt $tokens.Count) {
                    $argString = ($tokens[$i..($tokens.Count - 1)] -join ' ')
                }
                break
            }
        }

        if (-not $exePath) {
            # No prefix resolved as a file. Take the first token and try PATH lookup
            # later. msiexec, regsvr32 etc end up here.
            $exePath = $tokens[0]
            if ($tokens.Count -gt 1) {
                $argString = ($tokens[1..($tokens.Count - 1)] -join ' ')
            }
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

    # Tokenise argString honouring quotes. Each match is either a "quoted string"
    # or a bare non-whitespace run.
    $argList = @()
    if (-not [string]::IsNullOrWhiteSpace($argString)) {
        $tokenRegex = [regex]'"([^"]*)"|(\S+)'
        foreach ($m in $tokenRegex.Matches($argString)) {
            if ($m.Groups[1].Success) {
                $argList += $m.Groups[1].Value
            }
            elseif ($m.Groups[2].Success) {
                $argList += $m.Groups[2].Value
            }
        }
    }

    return [pscustomobject]@{
        ExePath   = $exePath
        Arguments = $argList
    }
}

function Start-QOTProcessFromCommand {
    <#
    .SYNOPSIS
    Safely launches an uninstall command, splitting it into exe + args rather
    than passing the raw string to cmd.exe /c.
    .DESCRIPTION
    The previous implementation wrapped the entire registry UninstallString
    in quotes and handed it to cmd.exe /c, which is vulnerable to command
    injection if the registry value is malicious or malformed. This version
    parses the command into a validated executable path + argument array and
    uses Start-Process -ArgumentList, so each argument is a separate token
    rather than being interpolated into a shell string.
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$Wait
    )

    if ([string]::IsNullOrWhiteSpace($Command)) { return }

    $parts = ConvertTo-QOTCommandParts -Command $Command
    if (-not $parts) {
        try { Write-QLog ("Refusing to execute uninstall command - executable could not be resolved or does not exist on disk. Raw: {0}" -f $Command) "WARN" } catch { }
        return
    }

    if (-not (Test-Path -LiteralPath $parts.ExePath -PathType Leaf)) {
        try { Write-QLog ("Refusing to execute uninstall command - resolved path '{0}' does not exist." -f $parts.ExePath) "WARN" } catch { }
        return
    }

    try { Write-QLog ("Executing uninstall: '{0}' with {1} argument(s)" -f $parts.ExePath, $parts.Arguments.Count) "DEBUG" } catch { }

    $startArgs = @{
        FilePath    = $parts.ExePath
        WindowStyle = 'Hidden'
    }
    if ($parts.Arguments.Count -gt 0) { $startArgs.ArgumentList = $parts.Arguments }
    if ($Wait) { $startArgs.Wait = $true }

    Start-Process @startArgs
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
        try { Write-QLog "Apps actions already running. Ignoring duplicate Play request." "WARN" } catch { }
        return
    }

    Commit-QOTGridEdits -Grid $AppsGrid
    Commit-QOTGridEdits -Grid $InstallGrid

    $installedItems = @($AppsGrid.ItemsSource)
    $commonItems = @($InstallGrid.ItemsSource)

    $needsRefresh = ($installedItems.Count -eq 0)
    if (-not $needsRefresh -and $Global:QOT_InstalledAppsCacheTimestamp) {
        try {
            $cacheAge = (New-TimeSpan -Start $Global:QOT_InstalledAppsCacheTimestamp -End (Get-Date)).TotalMinutes
            if ($cacheAge -ge 30) { $needsRefresh = $true }
        } catch { }
    }

    if ($needsRefresh) {
        try { Write-QLog "Apps dataset empty/stale. Triggering refresh before Play actions." "INFO" } catch { }
        Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid -ForceScan
        if ($Global:QOT_InstalledAppsCache -and $Global:QOT_InstalledAppsCache.Count -gt 0) {
            $installedItems = @($Global:QOT_InstalledAppsCache)
        }
    }

    $selectedInstalled = @($installedItems | Where-Object { $_.IsSelected -eq $true })
    $selectedCommon = @($commonItems | Where-Object { $_.IsSelected -eq $true -and $_.IsInstallable -ne $false })

    try { Write-QLog ("Apps selections discovered for Play: {0}" -f ($selectedInstalled.Count + $selectedCommon.Count)) "INFO" } catch { }

    if ($selectedInstalled.Count -eq 0 -and $selectedCommon.Count -eq 0) {
        try { Write-QLog "Apps actions skipped. Nothing selected." "INFO" } catch { }
        return
    }

    $installedDataset = Get-QOTInstalledAppDataset -Apps $installedItems
    $installedNameSet = $installedDataset.AllNames
    $selectedInstalledNameSet = Get-QOTInstalledAppNameSet -Apps $selectedInstalled
    $selectedCommonNameSet = Get-QOTInstalledAppNameSet -Apps $selectedCommon

    $overlap = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $selectedInstalledNameSet) {
        if ($selectedCommonNameSet.Contains($name)) {
            [void]$overlap.Add($name)
        }
    }

    if ($overlap.Count -gt 0) {
        foreach ($name in $overlap) {
            try { Write-QLog ("App appears in both install and uninstall selections. Skipping '{0}'." -f $name) "WARN" } catch { }
        }
        $selectedInstalled = @($selectedInstalled | Where-Object { -not $overlap.Contains((Get-QOTNormalizedAppName -Name $_.Name)) })
        $selectedCommon = @($selectedCommon | Where-Object { -not $overlap.Contains((Get-QOTNormalizedAppName -Name $_.Name)) })
    }

    $installedTasks = New-Object System.Collections.Generic.List[object]
    foreach ($app in $selectedInstalled) {
        $name = [string]$app.Name
        $key = Get-QOTNormalizedAppName -Name $name
        if (-not $installedNameSet.Contains($key)) {
            try { Write-QLog ("Skipping uninstall for '{0}' because it no longer appears installed." -f $name) "WARN" } catch { }
            continue
        }
        $cmd = Get-QOTSilentUninstallCommand -App $app
        if ([string]::IsNullOrWhiteSpace($cmd)) {
            try { Write-QLog ("Completed task: Uninstall {0} (FAILED - no uninstall command is available)" -f $name) "ERROR" } catch { }
            continue
        }
        $installedTasks.Add([pscustomobject]@{ Name = $name; Command = $cmd }) | Out-Null
    }

    $commonTasks = New-Object System.Collections.Generic.List[object]
    foreach ($app in $selectedCommon) {
        $name = [string]$app.Name
        $alreadyInstalled = Test-QOTCommonAppInstalled -CommonApp $app -InstalledDataset $installedDataset
        if (-not $alreadyInstalled -and (Get-Command Test-QOTWingetAppInstalled -ErrorAction SilentlyContinue) -and -not [string]::IsNullOrWhiteSpace($app.WingetId)) {
            try { $alreadyInstalled = Test-QOTWingetAppInstalled -WingetId $app.WingetId } catch { $alreadyInstalled = $false }
        }

        if ($alreadyInstalled) {
            $app.Status = "Installed"
            $app.IsInstallable = $false
            $app.IsSelected = $false
            try { Write-QLog ("Skipped task: Install {0} (already installed)" -f $name) "INFO" } catch { }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($app.WingetId)) {
            $app.Status = "Failed"
            try { Write-QLog ("Completed task: Install {0} (FAILED - missing WingetId)" -f $name) "ERROR" } catch { }
            continue
        }

        $commonTasks.Add([pscustomobject]@{ Name = $name; WingetId = [string]$app.WingetId }) | Out-Null
    }

    if ($installedTasks.Count -eq 0 -and $commonTasks.Count -eq 0) {
        Update-QOTCommonAppsInstallStatus -InstalledApps $installedItems
        return
    }

    $selectedInstalledUi = @($selectedInstalled)
    $selectedCommonUi = @($selectedCommon)
    $dispatcher = $AppsGrid.Dispatcher

    if ($script:QOT_AppsActionsTimer) {
        try { $script:QOT_AppsActionsTimer.Stop() } catch { }
        $script:QOT_AppsActionsTimer = $null
    }
    if ($script:QOT_AppsActionsPowerShell) {
        try { $script:QOT_AppsActionsPowerShell.Dispose() } catch { }
        $script:QOT_AppsActionsPowerShell = $null
    }
    if ($script:QOT_AppsActionsRunspace) {
        try { $script:QOT_AppsActionsRunspace.Dispose() } catch { }
        $script:QOT_AppsActionsRunspace = $null
    }
    $script:QOT_AppsActionsAsyncResult = $null

    # Helper function to safely dispose all runspace resources
    function Invoke-QOTCleanupAppsActions {
        param([string]$Reason = "Unknown")
        try {
            if ($script:QOT_AppsActionsPowerShell) {
                try { $script:QOT_AppsActionsPowerShell.Stop() } catch { }
                try { $script:QOT_AppsActionsPowerShell.Dispose() } catch { }
                $script:QOT_AppsActionsPowerShell = $null
            }
        } catch { }

        try {
            if ($script:QOT_AppsActionsRunspace) {
                try { $script:QOT_AppsActionsRunspace.Dispose() } catch { }
                $script:QOT_AppsActionsRunspace = $null
            }
        } catch { }

        try {
            if ($script:QOT_AppsActionsTimer) {
                try { $script:QOT_AppsActionsTimer.Stop() } catch { }
                try { $script:QOT_AppsActionsTimer.Dispose() } catch { }
                $script:QOT_AppsActionsTimer = $null
            }
        } catch { }

        try {
            if ($script:QOT_AppsActionsTimeoutWatchdog) {
                try { $script:QOT_AppsActionsTimeoutWatchdog.Stop() } catch { }
                try { $script:QOT_AppsActionsTimeoutWatchdog.Dispose() } catch { }
                $script:QOT_AppsActionsTimeoutWatchdog = $null
            }
        } catch { }

        $script:QOT_AppsActionsAsyncResult = $null
        $script:QOT_AppsActionsInProgress = $false
        $script:QOT_AppsActionsStartTime = $null
        $script:QOT_AppsActionsCancelState = $null

        try { Write-QLog ("Apps background cleanup completed. Reason: {0}" -f $Reason) "DEBUG" } catch { }
    }

    # Initialize timeout tracking
    $script:QOT_AppsActionsStartTime = Get-Date
    $maxTimeoutSeconds = 600  # 10 minutes max operation time

    # Synchronized cancel-state hashtable shared with the worker runspace. The
    # worker checks .CancelRequested between each install/uninstall iteration
    # and bails out early when set. The polling timer also watches this flag.
    $script:QOT_AppsActionsCancelState = [hashtable]::Synchronized(@{
        CancelRequested = $false
    })

    try {
        $script:QOT_AppsActionsRunspace = [runspacefactory]::CreateRunspace()
        $script:QOT_AppsActionsRunspace.Open()
        $script:QOT_AppsActionsPowerShell = [powershell]::Create()
        $script:QOT_AppsActionsPowerShell.Runspace = $script:QOT_AppsActionsRunspace

        $installModulePath = Join-Path $PSScriptRoot "InstallCommonApps.psm1"
        $null = $script:QOT_AppsActionsPowerShell.AddScript({
        param(
            [object[]]$InstalledTasks,
            [object[]]$CommonTasks,
            [string]$InstallModulePath,
            [hashtable]$CancelState
        )

        $ErrorActionPreference = "Stop"

        function Test-CancelRequested {
            if (-not $CancelState) { return $false }
            try { return [bool]$CancelState.CancelRequested } catch { return $false }
        }

        function Invoke-QOTWorkerCommand {
            param([string]$Command)

            $safeCommand = [string]$Command
            $safeCommand = $safeCommand.Trim()
            if ([string]::IsNullOrWhiteSpace($safeCommand)) {
                return [pscustomobject]@{ ExitCode = 1; StdOut = ""; StdErr = "Empty uninstall command" }
            }

            $filePath = $null
            $arguments = ""

            if ($safeCommand -match '^\s*"([^"]+)"\s*(.*)$') {
                $filePath = $matches[1]
                $arguments = $matches[2]
            }
            elseif ($safeCommand -match '^\s*([A-Za-z]:\\.*?\.exe)\s*(.*)$') {
                $filePath = $matches[1]
                $arguments = $matches[2]
            }
            elseif ($safeCommand -match '^\s*([^\s]+)\s*(.*)$') {
                $filePath = $matches[1]
                $arguments = $matches[2]
            }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.CreateNoWindow = $true
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true

            if (-not [string]::IsNullOrWhiteSpace($filePath)) {
                $psi.FileName = $filePath
                $psi.Arguments = $arguments
            }
            else {
                $wrappedCommand = "`"$safeCommand`""
                $psi.FileName = "cmd.exe"
                $psi.Arguments = "/d /s /c " + $wrappedCommand
            }

            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            [void]$proc.Start()
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()

            return [pscustomobject]@{ ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderr }
        }
        if (Test-Path -LiteralPath $InstallModulePath) {
            Import-Module -Name $InstallModulePath -Force -ErrorAction SilentlyContinue
        }

        $result = [pscustomobject]@{
            Uninstall = New-Object System.Collections.Generic.List[object]
            Install   = New-Object System.Collections.Generic.List[object]
            Cancelled = $false
        }

        foreach ($task in @($InstalledTasks)) {
            if (Test-CancelRequested) {
                $result.Cancelled = $true
                break
            }
            $name = [string]$task.Name
            $cmd  = [string]$task.Command
            try {
                $cmdResult = Invoke-QOTWorkerCommand -Command $cmd
                                $ok = ($cmdResult.ExitCode -in @(0, 3010, 1641))
                                $trimmedErr = [string]$cmdResult.StdErr
                $trimmedOut = [string]$cmdResult.StdOut
                if ($trimmedErr) { $trimmedErr = $trimmedErr.Trim() }
                if ($trimmedOut) { $trimmedOut = $trimmedOut.Trim() }
                $note = if ($ok) { "SUCCESS (ExitCode=$($cmdResult.ExitCode))" } else { "ExitCode=$($cmdResult.ExitCode) ERR=$trimmedErr OUT=$trimmedOut" }
                $result.Uninstall.Add([pscustomobject]@{ Name = $name; Success = $ok; Note = $note }) | Out-Null
            }
            catch {
                $result.Uninstall.Add([pscustomobject]@{ Name = $name; Success = $false; Note = $_.Exception.Message }) | Out-Null
            }
        }

        if (-not $result.Cancelled) {
            foreach ($task in @($CommonTasks)) {
                if (Test-CancelRequested) {
                    $result.Cancelled = $true
                    break
                }
                $name = [string]$task.Name
                $wingetId = [string]$task.WingetId
                try {
                    if (-not (Get-Command Install-QOTCommonApp -ErrorAction SilentlyContinue)) {
                        throw "Install-QOTCommonApp not found"
                    }
                    Install-QOTCommonApp -Name $name -WingetId $wingetId
                    $result.Install.Add([pscustomobject]@{ Name = $name; Success = $true; Note = "SUCCESS" }) | Out-Null
                }
                catch {
                    $result.Install.Add([pscustomobject]@{ Name = $name; Success = $false; Note = $_.Exception.Message }) | Out-Null
                }
            }
        }

        return $result
        }).AddArgument(@($installedTasks)).AddArgument(@($commonTasks)).AddArgument($installModulePath).AddArgument($script:QOT_AppsActionsCancelState)

        $script:QOT_AppsActionsInProgress = $true
        $script:QOT_AppsActionsAsyncResult = $script:QOT_AppsActionsPowerShell.BeginInvoke()

        # Main completion check timer
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(200)
        $timer.Add_Tick({
            if (-not $script:QOT_AppsActionsAsyncResult) {
                Invoke-QOTCleanupAppsActions -Reason "AsyncResult is null"
                return
            }

            # Cancellation check: if the UI requested cancel, stop the worker now
            # and tear everything down. We don't wait for the current operation to
            # finish - PowerShell.Stop() is best effort and the runspace dispose
            # below handles the rest.
            if (Test-QOTAppsActionsCancelRequested) {
                try { Write-QLog "Apps background actions cancellation observed by polling timer. Stopping worker." "INFO" } catch { }
                if ($script:QOT_AppsActionsPowerShell) {
                    try { $script:QOT_AppsActionsPowerShell.Stop() } catch { }
                }
                Invoke-QOTCleanupAppsActions -Reason "Cancellation requested"
                return
            }

            # Check for timeout first
            if ($script:QOT_AppsActionsStartTime) {
                $elapsed = ((Get-Date) - $script:QOT_AppsActionsStartTime).TotalSeconds
                if ($elapsed -gt $maxTimeoutSeconds) {
                    try { Write-QLog ("Apps background actions timeout after {0} seconds. Force stopping and cleaning up." -f [int]$elapsed) "WARN" } catch { }
                    Invoke-QOTCleanupAppsActions -Reason "Timeout exceeded ($elapsed seconds)"
                    return
                }
            }

            if (-not $script:QOT_AppsActionsAsyncResult.IsCompleted) {
                return
            }

            # Operation completed successfully, retrieve results and clean up
            $workerResult = $null
            $workerError = $null
            try {
                $workerResult = @($script:QOT_AppsActionsPowerShell.EndInvoke($script:QOT_AppsActionsAsyncResult))
                if ($workerResult.Count -gt 0) { $workerResult = $workerResult[-1] } else { $workerResult = $null }
            }
            catch {
                $workerError = $_.Exception
            }
            finally {
                Invoke-QOTCleanupAppsActions -Reason "Operation completed"
            }

        if ($workerError) {
            try { Write-QLog ("Apps background actions failed: {0}" -f $workerError.Message) "ERROR" } catch { }
            return
        }

        # If the worker observed cancellation between iterations, log it. We
        # still process any results it produced before the cancel, so partial
        # progress is reported to the user.
        if ($workerResult -and $workerResult.PSObject.Properties.Name -contains 'Cancelled' -and [bool]$workerResult.Cancelled) {
            try { Write-QLog "Apps background actions cancelled mid-batch. Processing partial results." "WARN" } catch { }
        }

        $didChange = $false

        foreach ($row in @($selectedInstalledUi)) {
            try { $row.IsSelected = $false } catch { }
        }
        foreach ($row in @($selectedCommonUi)) {
            try { $row.IsSelected = $false } catch { }
        }

        foreach ($entry in @($workerResult.Uninstall)) {
            if ($entry.Success) {
                $didChange = $true
                try { Write-QLog ("Completed task: Uninstall {0} (SUCCESS)" -f $entry.Name) "INFO" } catch { }
            } else {
                try { Write-QLog ("Completed task: Uninstall {0} (FAILED - {1})" -f $entry.Name, $entry.Note) "ERROR" } catch { }
            }
        }

        foreach ($entry in @($workerResult.Install)) {
            $target = @($selectedCommonUi | Where-Object { $_.Name -eq $entry.Name } | Select-Object -First 1)
            if ($entry.Success) {
                $didChange = $true
                if ($target.Count -gt 0) {
                    try { $target[0].Status = "Installed"; $target[0].IsInstallable = $false } catch { }
                }
                try { Write-QLog ("Completed task: Install {0} (SUCCESS)" -f $entry.Name) "INFO" } catch { }
            } else {
                if ($target.Count -gt 0) {
                    try { $target[0].Status = "Failed" } catch { }
                }
                try { Write-QLog ("Completed task: Install {0} (FAILED - {1})" -f $entry.Name, $entry.Note) "ERROR" } catch { }
            }
        }

        if ($didChange) {
            Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid -ForceScan
        }
        else {
            Update-QOTCommonAppsInstallStatus -InstalledApps @($AppsGrid.ItemsSource)
        }
    }.GetNewClosure())

        $script:QOT_AppsActionsTimer = $timer
        $script:QOT_AppsActionsTimer.Start()
        try { Write-QLog "Apps actions started in background (UI remains responsive)." "INFO" } catch { }
    }
    catch {
        try { Write-QLog ("Apps background actions failed to start: {0}" -f $_.Exception.Message) "ERROR" } catch { }
        Invoke-QOTCleanupAppsActions -Reason "Startup failed: $($_.Exception.Message)"
        throw
    }
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



