# src\Advanced\AdvancedTweaks\AdvancedTweaks.UI.psm1
# UI wiring for the Advanced tab

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\AdvancedTweaks.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\AdvancedCleaning\AdvancedCleaning.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\NetworkAndServices\NetworkAndServices.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Settings.psm1" -Global -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Actions\ActionRegistry.psm1" -Global -ErrorAction SilentlyContinue

$script:QOTAdvancedSelectAllHandler = $null
$script:QOTAdvancedSelectAllLoadedHandler = $null
$script:QOTAdvancedSectionSelectorSyncInProgress = $false
$script:QOTAdvancedSectionSelectorHandlers = @{}
$script:QOTAdvancedSectionChildHandlers = @{}
$script:QOTAdvancedSectionLastBulkActions = @{}
$script:QOTAdvancedInstantToggleState = [pscustomobject]@{
    Handlers = @{}
    Metadata = @{}
    RestoreInProgress = $false
    Busy = @{}
    Operations = @{}
}
$script:QOTAdvancedInstantToggleMouseHandler = $null

function Resolve-QOTAdvancedToggleStateCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][System.Management.Automation.ActionPreference]$LookupErrorAction = [System.Management.Automation.ActionPreference]::SilentlyContinue
    )

    $resolved = $null
    try {
        $resolved = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    catch {
        $resolved = $null
    }

    if (-not $resolved) {
        $settingsModulePath = Join-Path $PSScriptRoot "..\..\Core\Settings.psm1"
        try {
            Import-Module $settingsModulePath -Global -Force -ErrorAction Stop
        }
        catch {
            if ($LookupErrorAction -eq [System.Management.Automation.ActionPreference]::Stop) { throw }
            return $null
        }

        try {
            $resolved = Get-Command -Name $Name -ErrorAction $LookupErrorAction | Select-Object -First 1
        }
        catch {
            if ($LookupErrorAction -eq [System.Management.Automation.ActionPreference]::Stop) { throw }
            return $null
        }
    }

    return $resolved
}

function Test-QOTAdvancedActionIsBulkSelectable {
    param(
        [AllowNull()][string]$ActionId
    )

    $actionIdValue = ([string]($ActionId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($actionIdValue)) { return $false }
    return (-not [bool](Get-QOTAdvancedInstantToggleCommandNames -ActionId $actionIdValue))
}

function Get-QOTAdvancedSelectionSummary {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [object[]]$Actions
    )

    $total = 0
    $checked = 0

    foreach ($action in $Actions) {
        if (-not $action -or -not $action.Name) { continue }
        if (-not (Test-QOTAdvancedActionIsBulkSelectable -ActionId ([string]$action.ActionId))) { continue }

        $control = $Window.FindName([string]$action.Name)
        if ($control -is [System.Windows.Controls.CheckBox]) {
            $total++
            if ($control.IsChecked -eq $true) {
                $checked++
            }
        }
    }

    return [pscustomobject]@{
        Total = $total
        Checked = $checked
        AllChecked = ($total -gt 0 -and $checked -eq $total)
    }
}

function Set-QOTAdvancedSelectionState {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [object[]]$Actions,
        [Parameter(Mandatory)]
        [bool]$IsChecked
    )

    $updated = 0

    $previousRestoreFlag = [bool]$script:QOTAdvancedInstantToggleState.RestoreInProgress
    $script:QOTAdvancedInstantToggleState.RestoreInProgress = $true

    try {
        foreach ($action in $Actions) {
            if (-not $action -or -not $action.Name) { continue }
            if (-not (Test-QOTAdvancedActionIsBulkSelectable -ActionId ([string]$action.ActionId))) { continue }

            $control = $Window.FindName([string]$action.Name)
            if ($control -is [System.Windows.Controls.CheckBox]) {
                $control.IsChecked = $IsChecked
                $updated++
            }
        }
    }
    finally {
        $script:QOTAdvancedInstantToggleState.RestoreInProgress = $previousRestoreFlag
    }

    return $updated
}

function Update-QOTAdvancedSelectAllButtonUi {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$Button,
        [Parameter(Mandatory = $false)]
        $Icon,
        [Parameter(Mandatory)]
        [bool]$AllChecked
    )

    if ($AllChecked) {
        $Button.ToolTip = "Uncheck all boxes"
        if ($Icon -is [System.Windows.Controls.TextBlock]) {
            $Icon.Text = [string][char]0xE73D
        }
    }
    else {
        $Button.ToolTip = "Check all boxes"
        if ($Icon -is [System.Windows.Controls.TextBlock]) {
            $Icon.Text = [string][char]0xE73A
        }
    }
}

function Register-QOTAdvancedSelectAllButton {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [object[]]$Actions
    )

    $button = $Window.FindName("BtnSelectAllAdvancedActions")
    if (-not ($button -is [System.Windows.Controls.Button])) {
        return $false
    }

    $icon = $Window.FindName("TxtSelectAllAdvancedActionsIcon")

    if ($script:QOTAdvancedSelectAllHandler) {
        try { $button.Remove_Click($script:QOTAdvancedSelectAllHandler) } catch { }
    }

    $actionsSnapshot = @($Actions)
    $getSummaryFn = ${function:Get-QOTAdvancedSelectionSummary}
    $setStateFn = ${function:Set-QOTAdvancedSelectionState}
    $updateUiFn = ${function:Update-QOTAdvancedSelectAllButtonUi}

    $script:QOTAdvancedSelectAllHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)

        $summaryBefore = & $getSummaryFn -Window $Window -Actions $actionsSnapshot
        $targetCheckedState = -not [bool]$summaryBefore.AllChecked

        $updated = & $setStateFn -Window $Window -Actions $actionsSnapshot -IsChecked $targetCheckedState
        $summaryAfter = & $getSummaryFn -Window $Window -Actions $actionsSnapshot
        & $updateUiFn -Button $button -Icon $icon -AllChecked $summaryAfter.AllChecked

        $actionLabel = if ($targetCheckedState) { "checked" } else { "unchecked" }
        try { Write-QLog ("Advanced Select All {0} {1} boxes." -f $actionLabel, $updated) "DEBUG" } catch { }
    }.GetNewClosure()

    try {
        $button.Add_Click($script:QOTAdvancedSelectAllHandler)
    }
    catch {
        return $false
    }

    $initialSummary = & $getSummaryFn -Window $Window -Actions $actionsSnapshot
    & $updateUiFn -Button $button -Icon $icon -AllChecked $initialSummary.AllChecked

    return $true
}

function Get-QOTAdvancedInstantToggleCommandNames {
    param(
        [Parameter(Mandatory)][string]$ActionId
    )

    switch ($ActionId) {
        "Invoke-QAdvancedAdobeNetworkBlock" { return @{ Apply = "Invoke-QAdvancedAdobeNetworkBlock"; Undo = "Invoke-QAdvancedRestoreAdobeNetworkBlock" } }
        "Invoke-QAdvancedBlockRazerInstalls" { return @{ Apply = "Invoke-QAdvancedBlockRazerInstalls"; Undo = "Invoke-QAdvancedAllowRazerInstalls" } }
        "Invoke-QAdvancedBraveDebloat" { return @{ Apply = "Invoke-QAdvancedBraveDebloat"; Undo = "Invoke-QAdvancedRestoreBraveDebloat" } }
        "Invoke-QAdvancedEdgeDebloat" { return @{ Apply = "Invoke-QAdvancedEdgeDebloat"; Undo = "Invoke-QAdvancedRestoreEdgeDebloat" } }
        "Invoke-QAdvancedDisableEdge" { return @{ Apply = "Invoke-QAdvancedDisableEdge"; Undo = "Invoke-QAdvancedEnableEdge" } }
        "Invoke-QAdvancedEdgeUninstallable" { return @{ Apply = "Invoke-QAdvancedEdgeUninstallable"; Undo = "Invoke-QAdvancedRestoreEdgeUninstallable" } }
        "Invoke-QAdvancedDisableBackgroundApps" { return @{ Apply = "Invoke-QAdvancedDisableBackgroundApps"; Undo = "Invoke-QAdvancedEnableBackgroundApps" } }
        "Invoke-QAdvancedDisableFullscreenOptimizations" { return @{ Apply = "Invoke-QAdvancedDisableFullscreenOptimizations"; Undo = "Invoke-QAdvancedEnableFullscreenOptimizations" } }
        "Invoke-QDisableTelemetryScheduledTasks" { return @{ Apply = "Invoke-QDisableTelemetryScheduledTasks"; Undo = "Invoke-QEnableTelemetryScheduledTasks" } }
        "Invoke-QAdvancedDisableIPv6" { return @{ Apply = "Invoke-QAdvancedDisableIPv6"; Undo = "Invoke-QAdvancedEnableIPv6" } }
        "Invoke-QAdvancedDisableTeredo" { return @{ Apply = "Invoke-QAdvancedDisableTeredo"; Undo = "Invoke-QAdvancedEnableTeredo" } }
        "Invoke-QAdvancedDisableCopilot" { return @{ Apply = "Invoke-QAdvancedDisableCopilot"; Undo = "Invoke-QAdvancedEnableCopilot" } }
        "Invoke-QAdvancedDisableStorageSense" { return @{ Apply = "Invoke-QAdvancedDisableStorageSense"; Undo = "Invoke-QAdvancedEnableStorageSense" } }
        "Invoke-QAdvancedDisableNotificationTray" { return @{ Apply = "Invoke-QAdvancedDisableNotificationTray"; Undo = "Invoke-QAdvancedEnableNotificationTray" } }
        "Invoke-QAdvancedDisplayPerformance" { return @{ Apply = "Invoke-QAdvancedDisplayPerformance"; Undo = "Invoke-QAdvancedRestoreDisplayPerformance" } }
        default { return $null }
    }
}

function Stop-QOTAdvancedInstantToggleOperation {
    param(
        [Parameter(Mandatory)][string]$ControlName
    )

    $operation = $null
    try { $operation = $script:QOTAdvancedInstantToggleState.Operations[$ControlName] } catch { $operation = $null }
    if (-not $operation) { return }

    try {
        if ($operation.Timer) {
            try { $operation.Timer.Stop() } catch { }
        }
    } catch { }
    try {
        if ($operation.PowerShell) {
            try { $operation.PowerShell.Dispose() } catch { }
        }
    } catch { }
    try {
        if ($operation.Runspace) {
            try { $operation.Runspace.Dispose() } catch { }
        }
    } catch { }
    try { $script:QOTAdvancedInstantToggleState.Operations.Remove($ControlName) | Out-Null } catch { }
}

function Invoke-QOTAdvancedInstantToggle {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.CheckBox]$Sender
    )

    $state = $script:QOTAdvancedInstantToggleState
    if ($state.RestoreInProgress) { return }

    $controlName = [string]$Sender.Name
    if ([string]::IsNullOrWhiteSpace($controlName)) { return }

    $metadata = $null
    try { $metadata = $state.Metadata[$controlName] } catch { $metadata = $null }
    if (-not $metadata) { return }

    $targetState = [bool]$Sender.IsChecked
    try { Write-QLog ("Advanced invoke toggle handler: {0} target={1}" -f $controlName, $targetState) "DEBUG" } catch { }
    if ($state.Busy[$controlName]) { return }

    $commandName = if ($targetState) { [string]$metadata.Apply } else { [string]$metadata.Undo }
    if ([string]::IsNullOrWhiteSpace($commandName)) { return }

    $state.Busy[$controlName] = $true
    try {
        try { Write-QLog ("Advanced starting instant toggle: {0} command={1}" -f $controlName, $commandName) "DEBUG" } catch { }
        Start-QOTAdvancedInstantToggleAsync -Control $Sender -ActionId ([string]$metadata.ActionId) -CommandName $commandName -TargetState $targetState -SetToggleStateCmd $metadata.SetToggleStateCmd -GetLiveStateCmd $metadata.GetLiveStateCmd
    }
    catch {
        try { Write-QLog ("Advanced instant toggle failed: {0}. {1}" -f $metadata.ActionId, $_.Exception.Message) "ERROR" } catch { }
        $previousRestoreFlag = [bool]$state.RestoreInProgress
        $state.RestoreInProgress = $true
        try { $Sender.IsChecked = (-not $targetState) } catch { }
        finally { $state.RestoreInProgress = $previousRestoreFlag }
        $Sender.IsEnabled = $true
        $state.Busy.Remove($controlName) | Out-Null
    }
}

function Start-QOTAdvancedInstantToggleAsync {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.CheckBox]$Control,
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)][bool]$TargetState,
        [AllowNull()]$SetToggleStateCmd,
        [AllowNull()]$GetLiveStateCmd
    )

    $controlName = [string]$Control.Name
    $state = $script:QOTAdvancedInstantToggleState
    if ([string]::IsNullOrWhiteSpace($controlName)) {
        throw "Toggle control name is required."
    }

    Stop-QOTAdvancedInstantToggleOperation -ControlName $controlName

    $advancedTweaksModule = Join-Path $PSScriptRoot "AdvancedTweaks.psm1"
    $advancedCleaningModule = Join-Path $PSScriptRoot "..\AdvancedCleaning\AdvancedCleaning.psm1"
    $networkModule = Join-Path $PSScriptRoot "..\NetworkAndServices\NetworkAndServices.psm1"

    foreach ($modulePath in @($advancedTweaksModule, $advancedCleaningModule, $networkModule)) {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            throw ("Advanced toggle module not found: " + $modulePath)
        }
    }

    $originalToolTip = $null
    try { $originalToolTip = $Control.ToolTip } catch { $originalToolTip = $null }
    $Control.IsEnabled = $false
    try { $Control.ToolTip = if ($TargetState) { "Applying..." } else { "Reverting..." } } catch { }

    if ([string]::Equals([string]$env:QOT_UI_TOGGLE_TEST_MODE, "1", [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($SetToggleStateCmd) {
            try { & $SetToggleStateCmd -ActionId $ActionId -IsEnabled $TargetState | Out-Null } catch { }
        }
        try { $Control.ToolTip = $originalToolTip } catch { }
        $Control.IsEnabled = $true
        try { $state.Busy.Remove($controlName) | Out-Null } catch { }
        return
    }

    $runspace = [runspacefactory]::CreateRunspace()
    try { $runspace.ApartmentState = [System.Threading.ApartmentState]::STA } catch { }
    try { $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread } catch { }
    $runspace.Open()

    $powerShell = [powershell]::Create()
    $powerShell.Runspace = $runspace
    $null = $powerShell.AddScript({
        param(
            [string[]]$ModulePaths,
            [string]$CommandName
        )

        $ErrorActionPreference = "Stop"
        foreach ($modulePath in @($ModulePaths)) {
            if (-not [string]::IsNullOrWhiteSpace($modulePath)) {
                Import-Module -Name $modulePath -Force -ErrorAction Stop
            }
        }

        $invokeCmd = Get-Command -Name $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $invokeCmd) {
            throw ("Toggle command unavailable: " + $CommandName)
        }

        $result = & $invokeCmd
        if (-not $result) {
            $result = [pscustomobject]@{
                Status = "Skipped"
                Reason = "No result returned."
                Error  = ""
            }
        }

        $status = ""
        $reason = ""
        $errorText = ""
        try { if ($result.PSObject.Properties.Name -contains "Status") { $status = [string]$result.Status } } catch { $status = "" }
        try { if ($result.PSObject.Properties.Name -contains "Reason") { $reason = [string]($result.Reason + "") } } catch { $reason = "" }
        try { if ($result.PSObject.Properties.Name -contains "Error") { $errorText = [string]($result.Error + "") } } catch { $errorText = "" }

        [pscustomobject]@{
            Status = $status
            Reason = $reason
            Error  = $errorText
        }
    }).AddArgument(@($advancedTweaksModule, $advancedCleaningModule, $networkModule)).AddArgument($CommandName)

    $asyncResult = $powerShell.BeginInvoke()
    $completionTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $completionTimer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timeoutStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $stopToggleOperationFn = ${function:Stop-QOTAdvancedInstantToggleOperation}

    $state.Operations[$controlName] = @{
        Timer           = $completionTimer
        PowerShell      = $powerShell
        Runspace        = $runspace
        AsyncResult     = $asyncResult
        OriginalToolTip = $originalToolTip
        Stopwatch       = $timeoutStopwatch
    }

    $completionHandler = [System.EventHandler]{
        param($sender, $args)

        $operation = $null
        try { $operation = $state.Operations[$controlName] } catch { $operation = $null }
        if (-not $operation) {
            try { $completionTimer.Stop() } catch { }
            return
        }

        $async = $operation.AsyncResult
        if (-not $async) {
            try { $completionTimer.Stop() } catch { }
            & $stopToggleOperationFn -ControlName $controlName
            return
        }

        $isCompleted = $false
        try { $isCompleted = [bool]$async.IsCompleted } catch { $isCompleted = $true }
        $hasTimedOut = $false
        try {
            if ($operation.Stopwatch) {
                $hasTimedOut = ($operation.Stopwatch.ElapsedMilliseconds -ge 10000)
            }
        } catch { $hasTimedOut = $false }

        if (-not $isCompleted -and -not $hasTimedOut) { return }

        $result = $null
        $completionError = $null
        if ($hasTimedOut -and -not $isCompleted) {
            $completionError = [System.TimeoutException]::new("The toggle operation did not finish in time.")
        }
        else {
            try {
                $output = @($operation.PowerShell.EndInvoke($async))
                if ($output.Count -gt 0) {
                    $result = $output[-1]
                }
            }
            catch {
                $completionError = $_.Exception
            }
        }

        try { $completionTimer.Stop() } catch { }
        & $stopToggleOperationFn -ControlName $controlName

        $status = ""
        $reason = ""
        $errorText = ""
        $failed = $false

        if ($completionError) {
            $failed = $true
            $errorText = [string]$completionError.Message
        }
        else {
            try { if ($result -and $result.PSObject.Properties.Name -contains "Status") { $status = [string]$result.Status } } catch { $status = "" }
            try { if ($result -and $result.PSObject.Properties.Name -contains "Reason") { $reason = [string]($result.Reason + "") } } catch { $reason = "" }
            try { if ($result -and $result.PSObject.Properties.Name -contains "Error") { $errorText = [string]($result.Error + "") } } catch { $errorText = "" }

            if ($status -eq "Failed") {
                $failed = $true
                if ([string]::IsNullOrWhiteSpace($errorText)) { $errorText = $reason }
            }
            elseif ($status -eq "Skipped" -and $reason -match '(?i)admin required|requires admin') {
                $failed = $true
                $errorText = $reason
            }
        }

        if ($failed) {
            try { Write-QLog ("Advanced instant toggle failed: {0}. {1}" -f $ActionId, $errorText) "ERROR" } catch { }
            $previousRestoreFlag = [bool]$state.RestoreInProgress
            $state.RestoreInProgress = $true
            try { $Control.IsChecked = (-not $TargetState) } catch { }
            finally { $state.RestoreInProgress = $previousRestoreFlag }

            if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                try {
                    [System.Windows.MessageBox]::Show(
                        $errorText,
                        "Toggle failed",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    ) | Out-Null
                } catch { }
            }
        }
        else {
            $resolvedState = $TargetState
            $liveStateAvailable = $false
            if ($GetLiveStateCmd) {
                try {
                    $liveState = & $GetLiveStateCmd -ActionId $ActionId
                    if ($null -ne $liveState) {
                        $resolvedState = [bool]$liveState
                        $liveStateAvailable = $true
                    }
                }
                catch {
                    try { Write-QLog ("Advanced live-state refresh failed for {0}: {1}" -f $ActionId, $_.Exception.Message) "WARN" } catch { }
                }
            }

            $previousRestoreFlag = [bool]$state.RestoreInProgress
            $state.RestoreInProgress = $true
            try { $Control.IsChecked = $resolvedState } catch { }
            finally { $state.RestoreInProgress = $previousRestoreFlag }

            if ($SetToggleStateCmd) {
                try { & $SetToggleStateCmd -ActionId $ActionId -IsEnabled $resolvedState | Out-Null } catch { }
            }
            try {
                $logVerb = if ($resolvedState) { "applied" } else { "reverted" }
                $logSuffix = if ($liveStateAvailable) { " (live state confirmed)" } else { "" }
                Write-QLog ("Advanced instant toggle {0}: {1}{2}" -f $logVerb, $ActionId, $logSuffix) "INFO"
            } catch { }
        }

        try { $Control.ToolTip = $originalToolTip } catch { }
        $Control.IsEnabled = $true
        try { $state.Busy.Remove($controlName) | Out-Null } catch { }
    }.GetNewClosure()

    $completionTimer.Add_Tick($completionHandler)
    $completionTimer.Start()
}

function Register-QOTAdvancedInstantToggleHandlers {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][object[]]$Actions
    )

    $getToggleStateCmd = Resolve-QOTAdvancedToggleStateCommand -Name "Get-QOToggleActionState"
    $setToggleStateCmd = Resolve-QOTAdvancedToggleStateCommand -Name "Set-QOToggleActionState"
    $getLiveStateCmd = Get-Command Get-QOTAdvancedLiveToggleState -ErrorAction SilentlyContinue | Select-Object -First 1
    $state = $script:QOTAdvancedInstantToggleState
    if (-not $script:QOTAdvancedInstantToggleMouseHandler) {
        $script:QOTAdvancedInstantToggleMouseHandler = [System.Windows.Input.MouseButtonEventHandler]{
            param($sender, $args)
            try {
                if ($sender -is [System.Windows.Controls.CheckBox]) {
                    if (-not $sender.IsEnabled) { return }

                    $state = $script:QOTAdvancedInstantToggleState
                    $controlName = [string]$sender.Name
                    if ($state.Busy[$controlName]) {
                        try { $args.Handled = $true } catch { }
                        return
                    }

                    $previousRestoreFlag = [bool]$state.RestoreInProgress
                    $state.RestoreInProgress = $true
                    try {
                        $sender.IsChecked = (-not [bool]$sender.IsChecked)
                    }
                    finally {
                        $state.RestoreInProgress = $previousRestoreFlag
                    }

                    try { $sender.Focus() | Out-Null } catch { }
                    try { $args.Handled = $true } catch { }
                    try { $sender.UpdateLayout() } catch { }
                    try { $sender.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) | Out-Null } catch { }
                    Invoke-QOTAdvancedInstantToggle -Sender $sender
                }
            }
            catch {
                try { Write-QLog ("Advanced mouse handler error: {0}" -f $_.Exception.ToString()) "ERROR" } catch { }
            }
        }
    }

    foreach ($action in @($Actions)) {
        if (-not $action) { continue }

        $commandNames = Get-QOTAdvancedInstantToggleCommandNames -ActionId ([string]$action.ActionId)
        if (-not $commandNames) { continue }

        $control = $Window.FindName([string]$action.Name)
        if (-not ($control -is [System.Windows.Controls.CheckBox])) { continue }

        $existingHandlers = $state.Handlers[[string]$action.Name]
        if ($existingHandlers) {
            try { $control.RemoveHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent, $existingHandlers.MouseUp) } catch { }
        }

        $state.Metadata[[string]$action.Name] = @{
            ActionId         = [string]$action.ActionId
            Apply            = [string]$commandNames.Apply
            Undo             = [string]$commandNames.Undo
            SetToggleStateCmd = $setToggleStateCmd
            GetLiveStateCmd  = $getLiveStateCmd
        }

        $resolvedState = $null
        if ($getLiveStateCmd) {
            try {
                $liveState = & $getLiveStateCmd -ActionId ([string]$action.ActionId)
                if ($null -ne $liveState) {
                    $resolvedState = [bool]$liveState
                }
            }
            catch {
                try { Write-QLog ("Advanced live-state init failed for {0}: {1}" -f $action.ActionId, $_.Exception.Message) "WARN" } catch { }
            }
        }
        if ($null -eq $resolvedState -and $getToggleStateCmd) {
            try { $resolvedState = [bool](& $getToggleStateCmd -ActionId ([string]$action.ActionId) -Default $false) } catch { $resolvedState = $false }
        }

        if ($null -ne $resolvedState) {
            $previousRestoreFlag = [bool]$state.RestoreInProgress
            $state.RestoreInProgress = $true
            try {
                if ($control.IsEnabled -ne $false) {
                    $control.IsChecked = [bool]$resolvedState
                }
                elseif ($resolvedState -and $setToggleStateCmd) {
                    & $setToggleStateCmd -ActionId ([string]$action.ActionId) -IsEnabled $false | Out-Null
                }
            }
            finally {
                $state.RestoreInProgress = $previousRestoreFlag
            }

            if ($setToggleStateCmd) {
                try { & $setToggleStateCmd -ActionId ([string]$action.ActionId) -IsEnabled ([bool]$resolvedState) | Out-Null } catch { }
            }
        }

        try {
            $control.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent, $script:QOTAdvancedInstantToggleMouseHandler, $true)
        }
        catch {
            try { Write-QLog ("Advanced mouse handler attach failed for {0}: {1}" -f $action.ActionId, $_.Exception.ToString()) "ERROR" } catch { }
        }

        $state.Handlers[[string]$action.Name] = @{
            MouseUp = $script:QOTAdvancedInstantToggleMouseHandler
        }
    }
}

function Invoke-QOTAdvancedSectionOneShotAction {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [AllowNull()]$Window
    )

    if ([string]::IsNullOrWhiteSpace($ActionId)) { return $false }

    if ([string]::Equals([string]$env:QOT_UI_TOGGLE_TEST_MODE, "1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $current = [string]$env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS
        if ([string]::IsNullOrWhiteSpace($current)) {
            $env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS = $ActionId
        }
        else {
            $env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS = ($current + ";" + $ActionId)
        }
        try { Write-QLog ("Advanced section one-shot action skipped in test mode: {0}" -f $ActionId) "DEBUG" } catch { }
        return $true
    }

    $definition = $null
    try { $definition = Get-QOTActionDefinition -ActionId $ActionId } catch { $definition = $null }
    if (-not $definition) {
        try { Write-QLog ("Advanced section one-shot action has no definition: {0}" -f $ActionId) "WARN" } catch { }
        return $false
    }

    $scriptPath = [string]$definition.ScriptPath
    if ([string]::IsNullOrWhiteSpace($scriptPath) -or -not (Test-Path -LiteralPath $scriptPath)) {
        try { Write-QLog ("Advanced section one-shot action script missing for {0}: {1}" -f $ActionId, $scriptPath) "ERROR" } catch { }
        return $false
    }

    try {
        try { Write-QLog ("Advanced section one-shot action starting: {0}" -f $ActionId) "INFO" } catch { }
        $result = & $scriptPath -Window $Window

        $status = ""
        $reason = ""
        $errorText = ""
        foreach ($entry in @($result)) {
            if (-not $entry) { continue }
            if ($entry.PSObject.Properties.Name -contains "Status") {
                $status = [string]$entry.Status
                if ($entry.PSObject.Properties.Name -contains "Reason") { $reason = [string]$entry.Reason }
                if ($entry.PSObject.Properties.Name -contains "Error") { $errorText = [string]$entry.Error }
                break
            }
        }

        if ($status -eq "Failed") {
            $message = if (-not [string]::IsNullOrWhiteSpace($errorText)) { $errorText } else { $reason }
            try { Write-QLog ("Advanced section one-shot action failed: {0}. {1}" -f $ActionId, $message) "ERROR" } catch { }
            return $false
        }
        if ($status -eq "Skipped") {
            try { Write-QLog ("Advanced section one-shot action skipped: {0}. {1}" -f $ActionId, $reason) "WARN" } catch { }
            return $true
        }

        try { Write-QLog ("Advanced section one-shot action completed: {0}" -f $ActionId) "INFO" } catch { }
        return $true
    }
    catch {
        try { Write-QLog ("Advanced section one-shot action errored: {0}. {1}" -f $ActionId, $_.Exception.Message) "ERROR" } catch { }
        return $false
    }
}

function Get-QOTAdvancedSectionSelectionSummary {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string[]]$OptionNames
    )

    $total = 0
    $checked = 0

    foreach ($name in @($OptionNames)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $control = $Window.FindName($name)
        if (-not ($control -is [System.Windows.Controls.CheckBox])) { continue }

        $isBusy = $false
        try { $isBusy = [bool]$script:QOTAdvancedInstantToggleState.Busy[[string]$control.Name] } catch { $isBusy = $false }
        if ($control.IsEnabled -eq $false -and -not $isBusy) { continue }

        $total++
        if ($control.IsChecked -eq $true) {
            $checked++
        }
    }

    return [pscustomobject]@{
        Total      = $total
        Checked    = $checked
        AllChecked = ($total -gt 0 -and $checked -eq $total)
        AnyChecked = ($checked -gt 0)
    }
}

function Set-QOTAdvancedSectionOptionsState {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string[]]$OptionNames,
        [Parameter(Mandatory)][bool]$IsChecked,
        [hashtable]$ActionMap = @{}
    )

    $updated = 0
    $previousSync = [bool]$script:QOTAdvancedSectionSelectorSyncInProgress
    $script:QOTAdvancedSectionSelectorSyncInProgress = $true

    try {
        foreach ($name in @($OptionNames)) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $control = $Window.FindName($name)
            if (-not ($control -is [System.Windows.Controls.CheckBox])) { continue }
            if ($control.IsEnabled -eq $false) { continue }
            if ($control.IsChecked -eq $IsChecked) { continue }

            $control.IsChecked = $IsChecked

            $metadata = $null
            try { $metadata = $script:QOTAdvancedInstantToggleState.Metadata[[string]$control.Name] } catch { $metadata = $null }
            if ($metadata) {
                Invoke-QOTAdvancedInstantToggle -Sender $control
            }
            elseif ($IsChecked) {
                $actionId = $null
                try { $actionId = [string]$ActionMap[[string]$control.Name] } catch { $actionId = $null }
                if (-not [string]::IsNullOrWhiteSpace($actionId)) {
                    Invoke-QOTAdvancedSectionOneShotAction -ActionId $actionId -Window $Window | Out-Null
                }
            }
            $updated++
        }
    }
    finally {
        $script:QOTAdvancedSectionSelectorSyncInProgress = $previousSync
    }

    return $updated
}

function Update-QOTAdvancedSectionSelectorState {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][hashtable]$Section
    )

    $header = $Window.FindName([string]$Section.HeaderName)
    if (-not ($header -is [System.Windows.Controls.CheckBox])) { return }

    $summary = Get-QOTAdvancedSectionSelectionSummary -Window $Window -OptionNames ([string[]]$Section.OptionNames)
    $targetState = $false
    if ($summary.Total -gt 0 -and $summary.Checked -gt 0 -and $summary.Checked -lt $summary.Total) {
        $targetState = $null
    }
    elseif ($summary.AllChecked) {
        $targetState = $true
    }

    $previousSync = [bool]$script:QOTAdvancedSectionSelectorSyncInProgress
    $script:QOTAdvancedSectionSelectorSyncInProgress = $true
    try {
        $header.IsThreeState = $false
        $header.IsEnabled = ($summary.Total -gt 0)
        $header.IsChecked = $targetState
    }
    finally {
        $script:QOTAdvancedSectionSelectorSyncInProgress = $previousSync
    }
}

function Update-QOTAdvancedSectionSelectorStates {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][hashtable[]]$Sections
    )

    foreach ($section in @($Sections)) {
        if (-not $section) { continue }
        Update-QOTAdvancedSectionSelectorState -Window $Window -Section $section
    }
}

function Register-QOTAdvancedSectionSelectors {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][hashtable[]]$Sections,
        [hashtable]$ActionMap = @{}
    )

    $sectionsSnapshot = @($Sections)
    $updateAllFn = ${function:Update-QOTAdvancedSectionSelectorStates}
    $setSectionFn = ${function:Set-QOTAdvancedSectionOptionsState}
    $actionMap = if ($ActionMap) { $ActionMap } else { @{} }

    foreach ($section in $sectionsSnapshot) {
        if (-not $section -or [string]::IsNullOrWhiteSpace([string]$section.HeaderName)) { continue }

        $headerName = [string]$section.HeaderName
        $header = $Window.FindName($headerName)
        if (-not ($header -is [System.Windows.Controls.CheckBox])) { continue }

        if ($script:QOTAdvancedSectionSelectorHandlers.ContainsKey($headerName)) {
            $oldHandler = $script:QOTAdvancedSectionSelectorHandlers[$headerName]
            try { $header.Remove_Checked($oldHandler) } catch { }
            try { $header.Remove_Unchecked($oldHandler) } catch { }
        }

        $sectionSnapshot = $section
        $handler = [System.Windows.RoutedEventHandler]{
            param($sender, $args)

            if ($script:QOTAdvancedSectionSelectorSyncInProgress) { return }
            $targetState = ($sender -is [System.Windows.Controls.CheckBox] -and $sender.IsChecked -eq $true)

            $nowTicks = [Environment]::TickCount64
            if (-not ($script:QOTAdvancedSectionLastBulkActions -is [hashtable])) {
                $script:QOTAdvancedSectionLastBulkActions = @{}
            }
            $lastBulkAction = $null
            try { $lastBulkAction = $script:QOTAdvancedSectionLastBulkActions[$headerName] } catch { $lastBulkAction = $null }
            if ($lastBulkAction) {
                $lastTargetState = $null
                $lastTicks = 0
                try { $lastTargetState = [bool]$lastBulkAction.TargetState } catch { $lastTargetState = $null }
                try { $lastTicks = [int64]$lastBulkAction.Ticks } catch { $lastTicks = 0 }
                if ($null -ne $lastTargetState -and $lastTargetState -eq $targetState -and ($nowTicks - $lastTicks) -lt 2000) {
                    try { Write-QLog ("Advanced section {0} duplicate {1} event ignored." -f $sectionSnapshot.HeaderName, $targetState) "DEBUG" } catch { }
                    return
                }
            }
            $script:QOTAdvancedSectionLastBulkActions[$headerName] = [pscustomobject]@{
                TargetState = $targetState
                Ticks = $nowTicks
            }

            $updated = & $setSectionFn -Window $Window -OptionNames ([string[]]$sectionSnapshot.OptionNames) -IsChecked $targetState -ActionMap $actionMap
            & $updateAllFn -Window $Window -Sections $sectionsSnapshot
            $actionLabel = if ($targetState) { "checked" } else { "unchecked" }
            try { Write-QLog ("Advanced section {0} {1} {2} boxes." -f $sectionSnapshot.HeaderName, $actionLabel, $updated) "DEBUG" } catch { }
        }.GetNewClosure()

        $script:QOTAdvancedSectionSelectorHandlers[$headerName] = $handler
        try { $header.Add_Checked($handler) } catch { }
        try { $header.Add_Unchecked($handler) } catch { }
    }

    foreach ($section in $sectionsSnapshot) {
        foreach ($name in @($section.OptionNames)) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $control = $Window.FindName($name)
            if (-not ($control -is [System.Windows.Controls.CheckBox])) { continue }

            if ($script:QOTAdvancedSectionChildHandlers.ContainsKey($name)) {
                $oldChildHandler = $script:QOTAdvancedSectionChildHandlers[$name]
                try { $control.Remove_Checked($oldChildHandler) } catch { }
                try { $control.Remove_Unchecked($oldChildHandler) } catch { }
            }

            $childHandler = [System.Windows.RoutedEventHandler]{
                param($sender, $args)
                if ($script:QOTAdvancedSectionSelectorSyncInProgress) { return }
                & $updateAllFn -Window $Window -Sections $sectionsSnapshot
            }.GetNewClosure()

            $script:QOTAdvancedSectionChildHandlers[$name] = $childHandler
            try { $control.Add_Checked($childHandler) } catch { }
            try { $control.Add_Unchecked($childHandler) } catch { }
        }
    }

    & $updateAllFn -Window $Window -Sections $sectionsSnapshot
}

function Initialize-QOTAdvancedTweaksUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )
    try {
        $actions = @(
            @{ Name = "CbAdvAdobeNetworkBlock"; Label = "Adobe network block"; ActionId = "Invoke-QAdvancedAdobeNetworkBlock" },
            @{ Name = "CbAdvBlockRazerInstalls"; Label = "Block Razer software installs"; ActionId = "Invoke-QAdvancedBlockRazerInstalls" },
            @{ Name = "CbAdvBraveDebloat"; Label = "Brave debloat"; ActionId = "Invoke-QAdvancedBraveDebloat" },
            @{ Name = "CbAdvEdgeDebloat"; Label = "Edge debloat"; ActionId = "Invoke-QAdvancedEdgeDebloat" },
            @{ Name = "CbAdvDisableEdge"; Label = "Disable Edge"; ActionId = "Invoke-QAdvancedDisableEdge" },
            @{ Name = "CbAdvEdgeUninstallable"; Label = "Make Edge uninstallable via Settings"; ActionId = "Invoke-QAdvancedEdgeUninstallable" },
            @{ Name = "CbAdvDisableBackgroundApps"; Label = "Disable background apps"; ActionId = "Invoke-QAdvancedDisableBackgroundApps" },
            @{ Name = "CbAdvDisableFullscreenOptimizations"; Label = "Disable fullscreen optimizations"; ActionId = "Invoke-QAdvancedDisableFullscreenOptimizations" },
            @{ Name = "CbAdvDisableIPv6"; Label = "Disable IPv6"; ActionId = "Invoke-QAdvancedDisableIPv6" },
            @{ Name = "CbAdvDisableTeredo"; Label = "Disable Teredo"; ActionId = "Invoke-QAdvancedDisableTeredo" },
            @{ Name = "CbAdvDisableCopilot"; Label = "Disable Microsoft Copilot"; ActionId = "Invoke-QAdvancedDisableCopilot" },
            @{ Name = "CbAdvDisableStorageSense"; Label = "Disable Storage Sense"; ActionId = "Invoke-QAdvancedDisableStorageSense" },
            @{ Name = "CbAdvDisableNotificationTray"; Label = "Disable notification tray/calendar"; ActionId = "Invoke-QAdvancedDisableNotificationTray" },
            @{ Name = "CbAdvDisplayPerformance"; Label = "Set display for performance"; ActionId = "Invoke-QAdvancedDisplayPerformance" },
            @{ Name = "CbAdvRemoveOldProfiles"; Label = "Remove old profiles"; ActionId = "Invoke-QRemoveOldProfiles"; Available = $false; DisabledToolTip = "Temporarily unavailable in this build while the backend implementation is completed." },
            @{ Name = "CbAdvAggressiveRestoreCleanup"; Label = "Aggressive restore/log cleanup"; ActionId = "Invoke-QAggressiveRestoreCleanup"; Available = $false; DisabledToolTip = "Temporarily unavailable in this build while the backend implementation is completed." },
            @{ Name = "CbAdvDeepCacheCleanup"; Label = "Deep cache/component store cleanup"; ActionId = "Invoke-QAdvancedDeepCache" },
            @{ Name = "CbAdvCleanComponentStore"; Label = "Clean Windows Component Store"; ActionId = "Invoke-QCleanComponentStore" },
            @{ Name = "CbAdvAggressiveComponentStoreCleanup"; Label = "Aggressive component store cleanup"; ActionId = "Invoke-QAggressiveComponentStoreCleanup" },
            @{ Name = "CbAdvScanUnusedDeviceDrivers"; Label = "Scan unused device drivers (report only)"; ActionId = "Invoke-QScanUnusedDeviceDrivers" },
            @{ Name = "CbAdvDisableTelemetryScheduledTasks"; Label = "Disable telemetry scheduled tasks"; ActionId = "Invoke-QDisableTelemetryScheduledTasks" },
            @{ Name = "CbAdvNetworkReset"; Label = "Network reset"; ActionId = "Invoke-QNetworkReset" },
            @{ Name = "CbAdvRepairNetworkAdapter"; Label = "Repair network adapter"; ActionId = "Invoke-QRepairAdapter"; Available = $false; DisabledToolTip = "Temporarily unavailable in this build while the backend implementation is completed." },
            @{ Name = "CbAdvServiceTuning"; Label = "Service tuning"; ActionId = "Invoke-QServiceTune"; Available = $false; DisabledToolTip = "Temporarily unavailable in this build while the backend implementation is completed." },
            @{ Name = "CbAdvFlushDnsCache"; Label = "Flush DNS cache"; ActionId = "Invoke-QFlushDnsCache" },
            @{ Name = "CbAdvResetWinsock"; Label = "Reset Winsock"; ActionId = "Invoke-QResetWinsock" },
            @{ Name = "CbAdvResetWindowsFirewall"; Label = "Reset Windows Firewall"; ActionId = "Invoke-QResetWindowsFirewall" },
            @{ Name = "CbAdvRestartWindowsExplorer"; Label = "Restart Windows Explorer"; ActionId = "Invoke-QRestartWindowsExplorer" },
            @{ Name = "CbAdvRebuildWindowsSearchIndex"; Label = "Rebuild Windows Search index"; ActionId = "Invoke-QRebuildWindowsSearchIndex" },
            @{ Name = "CbAdvRunSfcRepair"; Label = "Run SFC system file repair"; ActionId = "Invoke-QRunSfcSystemFileRepair" },
            @{ Name = "CbAdvRunDismHealthRepair"; Label = "Run DISM health repair"; ActionId = "Invoke-QRunDismHealthRepair" }
        )

        foreach ($action in @($actions)) {
            if (-not $action -or -not $action.Name) { continue }
            $control = $Window.FindName([string]$action.Name)
            if (-not ($control -is [System.Windows.Controls.CheckBox])) { continue }

            try { $control.Content = [string]$action.Label } catch { }

            $isAvailable = $true
            try {
                if ($action.PSObject.Properties.Name -contains "Available") {
                    $isAvailable = [bool]$action.Available
                }
            } catch { $isAvailable = $true }

            if (-not $isAvailable) {
                try { $control.IsChecked = $false } catch { }
                try { $control.IsEnabled = $false } catch { }
                try {
                    if ($action.PSObject.Properties.Name -contains "DisabledToolTip") {
                        $control.ToolTip = [string]$action.DisabledToolTip
                    }
                } catch { }
            }
        }

        $actionsSnapshot = @(
            $actions |
                Where-Object {
                    $isAvailable = $true
                    try {
                        if ($_.PSObject.Properties.Name -contains "Available") {
                            $isAvailable = [bool]$_.Available
                        }
                    } catch { $isAvailable = $true }
                    $isAvailable
                }
        )
        $sectionActionMap = @{}
        foreach ($action in @($actionsSnapshot)) {
            if (-not $action -or [string]::IsNullOrWhiteSpace([string]$action.Name)) { continue }
            $sectionActionMap[[string]$action.Name] = [string]$action.ActionId
        }
        $sectionSelectors = @(
            @{
                HeaderName = "CbAdvSectionAppBrowserControls"
                OptionNames = @("CbAdvAdobeNetworkBlock", "CbAdvBlockRazerInstalls", "CbAdvBraveDebloat", "CbAdvEdgeDebloat", "CbAdvDisableEdge", "CbAdvEdgeUninstallable")
            },
            @{
                HeaderName = "CbAdvSectionSystemBehavior"
                OptionNames = @("CbAdvDisableBackgroundApps", "CbAdvDisableFullscreenOptimizations", "CbAdvDisableNotificationTray", "CbAdvDisplayPerformance")
            },
            @{
                HeaderName = "CbAdvSectionAdvancedCleaning"
                OptionNames = @("CbAdvRemoveOldProfiles", "CbAdvCleanComponentStore", "CbAdvDisableTelemetryScheduledTasks", "CbAdvScanUnusedDeviceDrivers", "CbAdvAggressiveRestoreCleanup", "CbAdvDeepCacheCleanup", "CbAdvAggressiveComponentStoreCleanup")
            },
            @{
                HeaderName = "CbAdvSectionConnectivityControls"
                OptionNames = @("CbAdvDisableIPv6", "CbAdvDisableTeredo", "CbAdvDisableCopilot", "CbAdvDisableStorageSense")
            },
            @{
                HeaderName = "CbAdvSectionNetworkServiceTuning"
                OptionNames = @("CbAdvNetworkReset", "CbAdvRepairNetworkAdapter", "CbAdvServiceTuning", "CbAdvFlushDnsCache", "CbAdvResetWinsock", "CbAdvResetWindowsFirewall")
            },
            @{
                HeaderName = "CbAdvSectionRepairRecovery"
                OptionNames = @("CbAdvRestartWindowsExplorer", "CbAdvRebuildWindowsSearchIndex", "CbAdvRunSfcRepair", "CbAdvRunDismHealthRepair")
            }
        )

        Register-QOTAdvancedInstantToggleHandlers -Window $Window -Actions $actionsSnapshot
        Register-QOTAdvancedSectionSelectors -Window $Window -Sections $sectionSelectors -ActionMap $sectionActionMap

        Register-QOTActionGroup -Name "Advanced" -GetItems ({
            param($Window)

            $items = @()
            foreach ($action in $actionsSnapshot) {
                $actionName = $action.Name
                $actionLabel = $action.Label
                $actionId = $action.ActionId

                $items += [pscustomobject]@{
                    ActionId = $actionId
                    Label = $actionLabel
                    IsSelected = ({
                        param($window)
                        $control = $window.FindName($actionName)
                        $control -and $control.IsChecked -eq $true
                    }).GetNewClosure()
                }
            }
            return $items
        }).GetNewClosure()

        try { Write-QLog "Advanced UI initialised (action registry)." "DEBUG" } catch { }
    }
    catch {
        try { Write-QLog ("Advanced UI initialisation error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

Export-ModuleMember -Function Initialize-QOTAdvancedTweaksUI

