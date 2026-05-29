# src\TweaksAndCleaning\TweaksAndCleaning.UI.psm1
# UI wiring for the Tweaks & Cleaning tab

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\Core\Config\Config.psm1"   -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Settings.psm1" -Global -Force -ErrorAction Stop

# ActionRegistry is optional but its import failure shouldn't be silent.
. (Join-Path $PSScriptRoot "..\..\Core\QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Actions\ActionRegistry.psm1") -ImporterContext 'TweaksAndCleaning.UI' -Global

Import-Module "$PSScriptRoot\Cleaning.psm1"                          -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\TweaksAndPrivacy\TweaksAndPrivacy.psm1" -Force -ErrorAction Stop

$script:QOTSelectAllTabActionsHandler = $null
$script:QOTSelectAllTabActionsLoadedHandler = $null
$script:QOTTweaksInstantToggleRefreshHandler = $null
$script:QOTTweaksSectionSelectorSyncInProgress = $false
$script:QOTTweaksSectionSelectorHandlers = @{}
$script:QOTTweaksSectionChildHandlers = @{}
$script:QOTTweaksSectionLastBulkActions = @{}
$script:QOTTweaksInstantToggleState = [pscustomobject]@{
    Handlers = @{}
    Metadata = @{}
    RestoreInProgress = $false
    Busy = @{}
    Operations = @{}
    ActiveExplorerRestartBatchId = 0
    NextExplorerRestartBatchId = 0
    ExplorerRestartBatches = @{}
    DeferredExplorerRestartPending = $false
    DeferredExplorerRestartTimer = $null
}
$script:QOTTweaksInstantToggleMouseHandler = $null

function Resolve-QOTTweaksToggleStateCommand {
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

function Test-QOTCheckboxIsBulkSelectable {
    param(
        [AllowNull()]$CheckBox
    )

    if (-not ($CheckBox -is [System.Windows.Controls.CheckBox])) {
        return $false
    }

    $tagValue = ""
    try { $tagValue = ([string]($CheckBox.Tag + "")).Trim() } catch { $tagValue = "" }

    switch ($tagValue) {
        "SectionSelector" { return $false }
        "Invoke-QTweakStartMenuRecommendations" { return $false }
        "Invoke-QTweakSuggestedApps" { return $false }
        "Invoke-QTweakTipsInStart" { return $false }
        "Invoke-QTweakBingSearch" { return $false }
        "Invoke-QTweakClassicContextMenu" { return $false }
        "Invoke-QTweakWidgets" { return $false }
        "Invoke-QTweakNewsAndInterests" { return $false }
        "Invoke-QTweakMeetNow" { return $false }
        "Invoke-QTweakAdvertisingId" { return $false }
        "Invoke-QTweakFeedbackHub" { return $false }
        "Invoke-QTweakOnlineTips" { return $false }
        "Invoke-QTweakDisableLockScreenTips" { return $false }
        "Invoke-QTweakDisableSettingsSuggestedContent" { return $false }
        "Invoke-QTweakDisableTransparencyEffects" { return $false }
        "Invoke-QTweakDisableStartupDelay" { return $false }
        "Invoke-QTweakDisableGameDVR" { return $false }
        "Invoke-QTweakDisableWindowsConsumerFeatures" { return $false }
        "Invoke-QTweakDisableWindowsRecall" { return $false }
        default { return $true }
    }
}

function Get-QOTNamedElement {
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $Root -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    try {
        if ($Root -is [System.Windows.FrameworkElement]) {
            $direct = $Root.FindName($Name)
            if ($direct) {
                return $direct
            }
        }

        $visited = New-Object 'System.Collections.Generic.HashSet[int]'
        $q = New-Object 'System.Collections.Generic.Queue[System.Object]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()
            if (-not $cur) { continue }

            $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
            if (-not $visited.Add($objId)) { continue }
            if ($cur -is [System.Windows.FrameworkElement]) {
                if ($cur.Name -eq $Name) {
                    return $cur
                }

                try {
                    $scoped = $cur.FindName($Name)
                    if ($scoped) {
                        return $scoped
                    }
                }
                catch { }
            }
            elseif ($cur -is [System.Windows.FrameworkContentElement]) {
                if ($cur.Name -eq $Name) {
                    return $cur
                }
            }

            try {
                foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                    if ($child) { $q.Enqueue($child) | Out-Null }
                }
            }
            catch { }

            if ($cur -is [System.Windows.DependencyObject]) {
                $count = 0
                try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }
                for ($i = 0; $i -lt $count; $i++) {
                    try {
                        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                        if ($child) { $q.Enqueue($child) | Out-Null }
                    }
                    catch { }
                }
            }
        }
    }
    catch { }

    return $null
}

function Get-QOTNamedElementsMap {
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    $lookup = @{}
    if (-not $Root -or -not $Names -or $Names.Count -eq 0) {
        return $lookup
    }

    $remaining = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($name in $Names) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $remaining.Add($name) | Out-Null
        }
    }

    if ($remaining.Count -eq 0) { return $lookup }

    try {
        if ($Root -is [System.Windows.FrameworkElement]) {
            foreach ($name in @($remaining)) {
                try {
                    $direct = $Root.FindName($name)
                    if ($direct) {
                        $lookup[$name] = $direct
                        $remaining.Remove($name) | Out-Null
                    }
                }
                catch { }
            }
        }

        if ($remaining.Count -eq 0) { return $lookup }

        $visited = New-Object 'System.Collections.Generic.HashSet[int]'
        $q = New-Object 'System.Collections.Generic.Queue[System.Object]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0 -and $remaining.Count -gt 0) {
            $cur = $q.Dequeue()
            if (-not $cur) { continue }

            $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
            if (-not $visited.Add($objId)) { continue }

            if ($cur -is [System.Windows.FrameworkElement]) {
                if (-not [string]::IsNullOrWhiteSpace($cur.Name) -and $remaining.Contains($cur.Name)) {
                    $lookup[$cur.Name] = $cur
                    $remaining.Remove($cur.Name) | Out-Null
                }

                foreach ($name in @($remaining)) {
                    try {
                        $scoped = $cur.FindName($name)
                        if ($scoped) {
                            $lookup[$name] = $scoped
                            $remaining.Remove($name) | Out-Null
                        }
                    }
                    catch { }
                }
            }
            elseif ($cur -is [System.Windows.FrameworkContentElement]) {
                if (-not [string]::IsNullOrWhiteSpace($cur.Name) -and $remaining.Contains($cur.Name)) {
                    $lookup[$cur.Name] = $cur
                    $remaining.Remove($cur.Name) | Out-Null
                }
            }

            try {
                foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                    if ($child) { $q.Enqueue($child) | Out-Null }
                }
            }
            catch { }

            if ($cur -is [System.Windows.DependencyObject]) {
                $count = 0
                try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }
                for ($i = 0; $i -lt $count; $i++) {
                    try {
                        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                        if ($child) { $q.Enqueue($child) | Out-Null }
                    }
                    catch { }
                }
            }
        }
    }
    catch { }

    return $lookup
}

function Set-QOTCheckboxStateInScope {
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)]
        [bool]$IsChecked
    )

    if (-not $Root) {
        return 0
    }

    $updated = 0

    $previousRestoreFlag = [bool]$script:QOTTweaksInstantToggleState.RestoreInProgress
    $script:QOTTweaksInstantToggleState.RestoreInProgress = $true

    try {
        $visited = New-Object 'System.Collections.Generic.HashSet[int]'
        $q = New-Object 'System.Collections.Generic.Queue[System.Object]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()
            if (-not $cur) { continue }

            $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
            if (-not $visited.Add($objId)) { continue }

            if (($cur -is [System.Windows.Controls.CheckBox]) -and (Test-QOTCheckboxIsBulkSelectable -CheckBox $cur)) {
                $cur.IsChecked = $IsChecked
                $updated++
            }

            try {
                foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                    if ($child) { $q.Enqueue($child) | Out-Null }
                }
            }
            catch { }

            if ($cur -is [System.Windows.DependencyObject]) {
                $count = 0
                try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }
                for ($i = 0; $i -lt $count; $i++) {
                    try {
                        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                        if ($child) { $q.Enqueue($child) | Out-Null }
                    }
                    catch { }
                }
            }
        }
    }
    catch { }
    finally {
        $script:QOTTweaksInstantToggleState.RestoreInProgress = $previousRestoreFlag
    }

    return $updated
}

function Get-QOTCheckboxSummaryInScope {
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root
    )

    if (-not $Root) {
        return [pscustomobject]@{
            Total = 0
            Checked = 0
            AllChecked = $false
        }
    }

    $total = 0
    $checked = 0

    try {
        $visited = New-Object 'System.Collections.Generic.HashSet[int]'
        $q = New-Object 'System.Collections.Generic.Queue[System.Object]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()
            if (-not $cur) { continue }

            $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
            if (-not $visited.Add($objId)) { continue }

            if (($cur -is [System.Windows.Controls.CheckBox]) -and (Test-QOTCheckboxIsBulkSelectable -CheckBox $cur)) {
                $total++
                if ($cur.IsChecked -eq $true) {
                    $checked++
                }
            }

            try {
                foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                    if ($child) { $q.Enqueue($child) | Out-Null }
                }
            }
            catch { }

            if ($cur -is [System.Windows.DependencyObject]) {
                $count = 0
                try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }
                for ($i = 0; $i -lt $count; $i++) {
                    try {
                        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                        if ($child) { $q.Enqueue($child) | Out-Null }
                    }
                    catch { }
                }
            }
        }
    }
    catch { }

    return [pscustomobject]@{
        Total = $total
        Checked = $checked
        AllChecked = ($total -gt 0 -and $checked -eq $total)
    }
}

function Get-QOTTweaksInstantToggleCommandNames {
    param(
        [Parameter(Mandatory)][string]$ActionId
    )

    switch ($ActionId) {
        "Invoke-QTweakStartMenuRecommendations" { return @{ Apply = "Invoke-QTweakStartMenuRecommendations"; Undo = "Invoke-QTweakEnableStartMenuRecommendations" } }
        "Invoke-QTweakSuggestedApps" { return @{ Apply = "Invoke-QTweakSuggestedApps"; Undo = "Invoke-QTweakEnableSuggestedApps" } }
        "Invoke-QTweakTipsInStart" { return @{ Apply = "Invoke-QTweakTipsInStart"; Undo = "Invoke-QTweakEnableTipsInStart" } }
        "Invoke-QTweakBingSearch" { return @{ Apply = "Invoke-QTweakBingSearch"; Undo = "Invoke-QTweakEnableBingSearch" } }
        "Invoke-QTweakClassicContextMenu" { return @{ Apply = "Invoke-QTweakClassicContextMenu"; Undo = "Invoke-QTweakEnableModernContextMenu" } }
        "Invoke-QTweakWidgets" { return @{ Apply = "Invoke-QTweakWidgets"; Undo = "Invoke-QTweakEnableWidgets" } }
        "Invoke-QTweakNewsAndInterests" { return @{ Apply = "Invoke-QTweakNewsAndInterests"; Undo = "Invoke-QTweakEnableNewsAndInterests" } }
        "Invoke-QTweakMeetNow" { return @{ Apply = "Invoke-QTweakMeetNow"; Undo = "Invoke-QTweakEnableMeetNow" } }
        "Invoke-QTweakAdvertisingId" { return @{ Apply = "Invoke-QTweakAdvertisingId"; Undo = "Invoke-QTweakEnableAdvertisingId" } }
        "Invoke-QTweakFeedbackHub" { return @{ Apply = "Invoke-QTweakFeedbackHub"; Undo = "Invoke-QTweakEnableFeedbackHub" } }
        "Invoke-QTweakOnlineTips" { return @{ Apply = "Invoke-QTweakOnlineTips"; Undo = "Invoke-QTweakEnableOnlineTips" } }
        "Invoke-QTweakDisableLockScreenTips" { return @{ Apply = "Invoke-QTweakDisableLockScreenTips"; Undo = "Invoke-QTweakEnableLockScreenTips" } }
        "Invoke-QTweakDisableSettingsSuggestedContent" { return @{ Apply = "Invoke-QTweakDisableSettingsSuggestedContent"; Undo = "Invoke-QTweakEnableSettingsSuggestedContent" } }
        "Invoke-QTweakDisableTransparencyEffects" { return @{ Apply = "Invoke-QTweakDisableTransparencyEffects"; Undo = "Invoke-QTweakEnableTransparencyEffects" } }
        "Invoke-QTweakDisableStartupDelay" { return @{ Apply = "Invoke-QTweakDisableStartupDelay"; Undo = "Invoke-QTweakEnableStartupDelay" } }
        "Invoke-QTweakDisableGameDVR" { return @{ Apply = "Invoke-QTweakDisableGameDVR"; Undo = "Invoke-QTweakEnableGameDVR" } }
        "Invoke-QTweakDisableWindowsConsumerFeatures" { return @{ Apply = "Invoke-QTweakDisableWindowsConsumerFeatures"; Undo = "Invoke-QTweakEnableWindowsConsumerFeatures" } }
        "Invoke-QTweakDisableWindowsRecall" { return @{ Apply = "Invoke-QTweakDisableWindowsRecall"; Undo = "Invoke-QTweakEnableWindowsRecall" } }
        default { return $null }
    }
}

function Test-QOTTweakRequiresExplorerRestart {
    param(
        [Parameter(Mandatory)][string]$ActionId
    )

    switch ($ActionId) {
        "Invoke-QTweakStartMenuRecommendations" { return $true }
        "Invoke-QTweakSuggestedApps" { return $true }
        "Invoke-QTweakTipsInStart" { return $true }
        "Invoke-QTweakBingSearch" { return $true }
        "Invoke-QTweakClassicContextMenu" { return $true }
        "Invoke-QTweakWidgets" { return $true }
        "Invoke-QTweakNewsAndInterests" { return $true }
        "Invoke-QTweakMeetNow" { return $true }
        default { return $false }
    }
}

function Restart-QOTExplorerShell {
    if ([string]::Equals([string]$env:QOT_UI_TOGGLE_TEST_MODE, "1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $restartCount = 0
        try { $restartCount = [int]$env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS } catch { $restartCount = 0 }
        $env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS = [string]($restartCount + 1)
        try { Write-QLog "Tweaks: Explorer restart skipped in UI toggle test mode." "DEBUG" } catch { }
        return $true
    }

    $explorerPath = Join-Path $env:WINDIR "explorer.exe"
    $explorerStopped = $false

    try {
        $explorerProcesses = @(Get-Process -Name "explorer" -ErrorAction SilentlyContinue)
        if ($explorerProcesses.Count -gt 0) {
            foreach ($process in $explorerProcesses) {
                try { Stop-Process -Id $process.Id -Force -ErrorAction Stop } catch { }
            }
            $explorerStopped = $true
            Start-Sleep -Milliseconds 700
        }

        $autoRestarted = $false
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 250
            $running = @(Get-Process -Name "explorer" -ErrorAction SilentlyContinue)
            if ($running.Count -gt 0) {
                $autoRestarted = $true
                break
            }
        }

        if ($autoRestarted) {
            try { Write-QLog "Tweaks: Explorer auto-restarted by Windows to apply shell changes." "INFO" } catch { }
            return $true
        }

        Start-Process -FilePath $explorerPath -WorkingDirectory $env:WINDIR -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 1200
        try {
            $shellApp = New-Object -ComObject Shell.Application
            foreach ($window in @($shellApp.Windows())) {
                if (-not $window) { continue }
                try {
                    $fullName = ""
                    try { $fullName = [System.IO.Path]::GetFileName([string]$window.FullName) } catch { $fullName = "" }
                    if ($fullName -ieq "explorer.exe") {
                        $window.Quit()
                    }
                }
                catch { }
            }
        }
        catch { }
        try { Write-QLog "Tweaks: Explorer manually restarted to apply shell changes." "INFO" } catch { }
        return $true
    }
    catch {
        try { Write-QLog ("Tweaks: failed to restart Explorer: {0}" -f $_.Exception.Message) "WARN" } catch { }
        if ($explorerStopped) {
            try { Start-Process -FilePath $explorerPath -WorkingDirectory $env:WINDIR -ErrorAction SilentlyContinue | Out-Null } catch { }
        }
        return $false
    }
}

function Start-QOTTweaksExplorerRestartBatch {
    $state = $script:QOTTweaksInstantToggleState

    $nextId = 0
    try { $nextId = [int]$state.NextExplorerRestartBatchId } catch { $nextId = 0 }
    $nextId++

    $state.NextExplorerRestartBatchId = $nextId
    $state.ActiveExplorerRestartBatchId = $nextId
    $state.ExplorerRestartBatches[$nextId] = [pscustomobject]@{
        Active = $true
        Running = 0
        PendingRestart = $false
        Actions = New-Object 'System.Collections.Generic.List[string]'
    }

    return $nextId
}

function Request-QOTTweaksDeferredExplorerRestart {
    param(
        [AllowNull()][string]$Reason
    )

    $state = $script:QOTTweaksInstantToggleState
    $state.DeferredExplorerRestartPending = $true

    $existingTimer = $null
    try { $existingTimer = $state.DeferredExplorerRestartTimer } catch { $existingTimer = $null }
    if ($existingTimer) { return }

    if ([string]::Equals([string]$env:QOT_UI_TOGGLE_TEST_MODE, "1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $restartCount = 0
        try { $restartCount = [int]$env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS } catch { $restartCount = 0 }
        $env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS = [string]($restartCount + 1)
        $state.DeferredExplorerRestartPending = $false

        try {
            $timer = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [TimeSpan]::FromMilliseconds(100)
            $handler = [System.EventHandler]{
                param($sender, $args)
                try { $sender.Stop() } catch { }
                try { $state.DeferredExplorerRestartTimer = $null } catch { }
            }.GetNewClosure()
            $timer.Add_Tick($handler)
            $state.DeferredExplorerRestartTimer = $timer
            $timer.Start()
        }
        catch {
            $state.DeferredExplorerRestartTimer = $null
        }
        return
    }

    try {
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(350)

        $handler = [System.EventHandler]{
            param($sender, $args)

            try { $sender.Stop() } catch { }
            try { $state.DeferredExplorerRestartTimer = $null } catch { }

            $shouldRestart = $false
            try { $shouldRestart = [bool]$state.DeferredExplorerRestartPending } catch { $shouldRestart = $false }
            $state.DeferredExplorerRestartPending = $false
            if (-not $shouldRestart) { return }

            try {
                if (-not [string]::IsNullOrWhiteSpace($Reason)) {
                    try { Write-QLog ("Tweaks: running deferred Explorer restart ({0})." -f $Reason) "DEBUG" } catch { }
                }
                Restart-QOTExplorerShell | Out-Null
            }
            catch {
                try { Write-QLog ("Tweaks: deferred Explorer restart failed: {0}" -f $_.Exception.Message) "WARN" } catch { }
            }
        }.GetNewClosure()

        $timer.Add_Tick($handler)
        $state.DeferredExplorerRestartTimer = $timer
        $timer.Start()
    }
    catch {
        $state.DeferredExplorerRestartPending = $false
        try { Restart-QOTExplorerShell | Out-Null } catch { }
    }
}

function Invoke-QOTTweaksExplorerRestartBatchIfReady {
    param(
        [Parameter(Mandatory)][int]$BatchId
    )

    if ($BatchId -le 0) { return }

    $state = $script:QOTTweaksInstantToggleState
    $batch = $null
    try { $batch = $state.ExplorerRestartBatches[$BatchId] } catch { $batch = $null }
    if (-not $batch) { return }

    if ([bool]$batch.Active) { return }
    if ([int]$batch.Running -gt 0) { return }

    $shouldRestart = $false
    try { $shouldRestart = [bool]$batch.PendingRestart } catch { $shouldRestart = $false }

    try { $state.ExplorerRestartBatches.Remove($BatchId) | Out-Null } catch { }

    if (-not $shouldRestart) { return }

    $actionCount = 0
    try { $actionCount = [int]$batch.Actions.Count } catch { $actionCount = 0 }
    try { Write-QLog ("Tweaks: queued one Explorer restart after section batch {0} ({1} shell-affecting action(s))." -f $BatchId, $actionCount) "DEBUG" } catch { }
    Request-QOTTweaksDeferredExplorerRestart -Reason ("section batch {0}" -f $BatchId)
}

function Stop-QOTTweaksExplorerRestartBatch {
    param(
        [Parameter(Mandatory)][int]$BatchId
    )

    if ($BatchId -le 0) { return }

    $state = $script:QOTTweaksInstantToggleState
    $batch = $null
    try { $batch = $state.ExplorerRestartBatches[$BatchId] } catch { $batch = $null }
    if ($batch) {
        try { $batch.Active = $false } catch { }
    }

    try {
        if ([int]$state.ActiveExplorerRestartBatchId -eq $BatchId) {
            $state.ActiveExplorerRestartBatchId = 0
        }
    } catch { }

    Invoke-QOTTweaksExplorerRestartBatchIfReady -BatchId $BatchId
}

function Register-QOTTweaksExplorerRestartBatchOperation {
    $state = $script:QOTTweaksInstantToggleState

    $batchId = 0
    try { $batchId = [int]$state.ActiveExplorerRestartBatchId } catch { $batchId = 0 }
    if ($batchId -le 0) { return 0 }

    $batch = $null
    try { $batch = $state.ExplorerRestartBatches[$batchId] } catch { $batch = $null }
    if (-not $batch) { return 0 }

    try { $batch.Running = ([int]$batch.Running + 1) } catch { }
    return $batchId
}

function Set-QOTTweaksExplorerRestartBatchPending {
    param(
        [Parameter(Mandatory)][int]$BatchId,
        [Parameter(Mandatory)][string]$ActionId
    )

    if ($BatchId -le 0) { return $false }

    $state = $script:QOTTweaksInstantToggleState
    $batch = $null
    try { $batch = $state.ExplorerRestartBatches[$BatchId] } catch { $batch = $null }
    if (-not $batch) { return $false }

    try { $batch.PendingRestart = $true } catch { }
    try {
        if (-not [string]::IsNullOrWhiteSpace($ActionId)) {
            $batch.Actions.Add($ActionId) | Out-Null
        }
    } catch { }

    return $true
}

function Complete-QOTTweaksExplorerRestartBatchOperation {
    param(
        [Parameter(Mandatory)][int]$BatchId
    )

    if ($BatchId -le 0) { return }

    $state = $script:QOTTweaksInstantToggleState
    $batch = $null
    try { $batch = $state.ExplorerRestartBatches[$BatchId] } catch { $batch = $null }
    if (-not $batch) { return }

    try {
        $running = [int]$batch.Running
        if ($running -gt 0) {
            $batch.Running = ($running - 1)
        }
    } catch { }

    Invoke-QOTTweaksExplorerRestartBatchIfReady -BatchId $BatchId
}

function Invoke-QOTTweaksSectionOneShotAction {
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
        try { Write-QLog ("Tweaks section one-shot action skipped in test mode: {0}" -f $ActionId) "DEBUG" } catch { }
        return $true
    }

    $definition = $null
    try { $definition = Get-QOTActionDefinition -ActionId $ActionId } catch { $definition = $null }
    if (-not $definition) {
        try { Write-QLog ("Tweaks section one-shot action has no definition: {0}" -f $ActionId) "WARN" } catch { }
        return $false
    }

    $scriptPath = [string]$definition.ScriptPath
    if ([string]::IsNullOrWhiteSpace($scriptPath) -or -not (Test-Path -LiteralPath $scriptPath)) {
        try { Write-QLog ("Tweaks section one-shot action script missing for {0}: {1}" -f $ActionId, $scriptPath) "ERROR" } catch { }
        return $false
    }

    try {
        try { Write-QLog ("Tweaks section one-shot action starting: {0}" -f $ActionId) "INFO" } catch { }
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
            try { Write-QLog ("Tweaks section one-shot action failed: {0}. {1}" -f $ActionId, $message) "ERROR" } catch { }
            return $false
        }
        if ($status -eq "Skipped") {
            try { Write-QLog ("Tweaks section one-shot action skipped: {0}. {1}" -f $ActionId, $reason) "WARN" } catch { }
            return $true
        }

        try { Write-QLog ("Tweaks section one-shot action completed: {0}" -f $ActionId) "INFO" } catch { }
        return $true
    }
    catch {
        try { Write-QLog ("Tweaks section one-shot action errored: {0}. {1}" -f $ActionId, $_.Exception.Message) "ERROR" } catch { }
        return $false
    }
}

function Stop-QOTTweaksInstantToggleOperation {
    param(
        [Parameter(Mandatory)][string]$ControlName
    )

    $operation = $null
    try { $operation = $script:QOTTweaksInstantToggleState.Operations[$ControlName] } catch { $operation = $null }
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
    try { $script:QOTTweaksInstantToggleState.Operations.Remove($ControlName) | Out-Null } catch { }
}

function Invoke-QOTTweaksInstantToggle {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.CheckBox]$Sender
    )

    $state = $script:QOTTweaksInstantToggleState
    if ($state.RestoreInProgress) { return }

    $controlName = [string]$Sender.Name
    if ([string]::IsNullOrWhiteSpace($controlName)) { return }

    $metadata = $null
    try { $metadata = $state.Metadata[$controlName] } catch { $metadata = $null }
    if (-not $metadata) { return }

    $targetState = [bool]$Sender.IsChecked
    try { Write-QLog ("Tweaks invoke toggle handler: {0} target={1}" -f $controlName, $targetState) "DEBUG" } catch { }
    if ($state.Busy[$controlName]) { return }

    $commandName = if ($targetState) { [string]$metadata.Apply } else { [string]$metadata.Undo }
    if ([string]::IsNullOrWhiteSpace($commandName)) { return }

    $state.Busy[$controlName] = $true
    try {
        try { Write-QLog ("Tweaks starting instant toggle: {0} command={1}" -f $controlName, $commandName) "DEBUG" } catch { }
        Start-QOTTweaksInstantToggleAsync -Control $Sender -ActionId ([string]$metadata.ActionId) -CommandName $commandName -TargetState $targetState -SetToggleStateCmd $metadata.SetToggleStateCmd -GetLiveStateCmd $metadata.GetLiveStateCmd -RestartExplorer ([bool]$metadata.RestartExplorer)
    }
    catch {
        try { Write-QLog ("Tweaks instant toggle failed: {0}. {1}" -f $metadata.ActionId, $_.Exception.Message) "ERROR" } catch { }
        $previousRestoreFlag = [bool]$state.RestoreInProgress
        $state.RestoreInProgress = $true
        try { $Sender.IsChecked = (-not $targetState) } catch { }
        finally { $state.RestoreInProgress = $previousRestoreFlag }
        $Sender.IsEnabled = $true
        $state.Busy.Remove($controlName) | Out-Null
    }
}

function Start-QOTTweaksInstantToggleAsync {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.CheckBox]$Control,
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)][bool]$TargetState,
        [AllowNull()]$SetToggleStateCmd,
        [AllowNull()]$GetLiveStateCmd,
        [bool]$RestartExplorer = $false
    )

    $controlName = [string]$Control.Name
    $state = $script:QOTTweaksInstantToggleState
    if ([string]::IsNullOrWhiteSpace($controlName)) {
        throw "Toggle control name is required."
    }

    Stop-QOTTweaksInstantToggleOperation -ControlName $controlName

    $modulePath = Join-Path $PSScriptRoot "..\TweaksAndPrivacy\TweaksAndPrivacy.psm1"
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw ("Tweaks module not found: " + $modulePath)
    }

    $originalToolTip = $null
    try { $originalToolTip = $Control.ToolTip } catch { $originalToolTip = $null }
    $Control.IsEnabled = $false
    try { $Control.ToolTip = if ($TargetState) { "Applying..." } else { "Reverting..." } } catch { }

    $explorerRestartBatchId = 0

    if ([string]::Equals([string]$env:QOT_UI_TOGGLE_TEST_MODE, "1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $explorerRestartBatchId = Register-QOTTweaksExplorerRestartBatchOperation
        if ($SetToggleStateCmd) {
            try { & $SetToggleStateCmd -ActionId $ActionId -IsEnabled $TargetState | Out-Null } catch { }
        }
        if ($RestartExplorer) {
            if (-not (Set-QOTTweaksExplorerRestartBatchPending -BatchId $explorerRestartBatchId -ActionId $ActionId)) {
                Restart-QOTExplorerShell | Out-Null
            }
        }
        Complete-QOTTweaksExplorerRestartBatchOperation -BatchId $explorerRestartBatchId
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
            [string]$ModulePath,
            [string]$CommandName
        )

        $ErrorActionPreference = "Stop"
        Import-Module -Name $ModulePath -Force -ErrorAction Stop

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
    }).AddArgument($modulePath).AddArgument($CommandName)

    $asyncResult = $powerShell.BeginInvoke()
    $explorerRestartBatchId = Register-QOTTweaksExplorerRestartBatchOperation
    $completionTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $completionTimer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timeoutStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $stopToggleOperationFn = ${function:Stop-QOTTweaksInstantToggleOperation}
    $restartExplorerFn = ${function:Restart-QOTExplorerShell}
    $setExplorerRestartBatchPendingFn = ${function:Set-QOTTweaksExplorerRestartBatchPending}
    $completeExplorerRestartBatchOperationFn = ${function:Complete-QOTTweaksExplorerRestartBatchOperation}

    $state.Operations[$controlName] = @{
        Timer           = $completionTimer
        PowerShell      = $powerShell
        Runspace        = $runspace
        AsyncResult     = $asyncResult
        OriginalToolTip = $originalToolTip
        Stopwatch       = $timeoutStopwatch
        ExplorerRestartBatchId = $explorerRestartBatchId
    }

    $completionHandler = [System.EventHandler]{
        param($sender, $args)

        $operation = $null
        try { $operation = $state.Operations[$controlName] } catch { $operation = $null }
        if (-not $operation) {
            try { $completionTimer.Stop() } catch { }
            return
        }

        $operationExplorerRestartBatchId = 0
        try { $operationExplorerRestartBatchId = [int]$operation.ExplorerRestartBatchId } catch { $operationExplorerRestartBatchId = 0 }

        $async = $operation.AsyncResult
        if (-not $async) {
            try { $completionTimer.Stop() } catch { }
            & $stopToggleOperationFn -ControlName $controlName
            & $completeExplorerRestartBatchOperationFn -BatchId $operationExplorerRestartBatchId
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
            try { Write-QLog ("Tweaks instant toggle failed: {0}. {1}" -f $ActionId, $errorText) "ERROR" } catch { }
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
            if ($RestartExplorer) {
                if (-not (& $setExplorerRestartBatchPendingFn -BatchId $operationExplorerRestartBatchId -ActionId $ActionId)) {
                    try {
                        try { Write-QLog ("Tweaks: restarting Explorer for {0}" -f $ActionId) "DEBUG" } catch { }
                        & $restartExplorerFn | Out-Null
                    }
                    catch {
                        try { Write-QLog ("Tweaks: Explorer restart invocation failed for {0}: {1}" -f $ActionId, $_.Exception.Message) "WARN" } catch { }
                    }
                }
                else {
                    try { Write-QLog ("Tweaks: deferred Explorer restart for {0} until section batch completes." -f $ActionId) "DEBUG" } catch { }
                }
            }

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
                    try { Write-QLog ("Tweaks live-state refresh failed for {0}: {1}" -f $ActionId, $_.Exception.Message) "WARN" } catch { }
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
                Write-QLog ("Tweaks instant toggle {0}: {1}{2}" -f $logVerb, $ActionId, $logSuffix) "INFO"
            } catch { }
        }

        try { $Control.ToolTip = $originalToolTip } catch { }
        $Control.IsEnabled = $true
        try { $state.Busy.Remove($controlName) | Out-Null } catch { }
        & $completeExplorerRestartBatchOperationFn -BatchId $operationExplorerRestartBatchId
    }.GetNewClosure()

    $completionTimer.Add_Tick($completionHandler)
    $completionTimer.Start()
}

function Register-QOTTweaksInstantToggleHandlers {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][object[]]$Actions
    )

    $getToggleStateCmd = Resolve-QOTTweaksToggleStateCommand -Name "Get-QOToggleActionState"
    $setToggleStateCmd = Resolve-QOTTweaksToggleStateCommand -Name "Set-QOToggleActionState"
    $getLiveStateCmd = Get-Command Get-QOTTweaksLiveToggleState -ErrorAction SilentlyContinue | Select-Object -First 1
    $state = $script:QOTTweaksInstantToggleState
    if (-not $script:QOTTweaksInstantToggleMouseHandler) {
        $script:QOTTweaksInstantToggleMouseHandler = [System.Windows.Input.MouseButtonEventHandler]{
            param($sender, $args)
            try {
                if ($sender -is [System.Windows.Controls.CheckBox]) {
                    if (-not $sender.IsEnabled) { return }

                    $state = $script:QOTTweaksInstantToggleState
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
                    Invoke-QOTTweaksInstantToggle -Sender $sender
                }
            }
            catch {
                try { Write-QLog ("Tweaks mouse handler error: {0}" -f $_.Exception.ToString()) "ERROR" } catch { }
            }
        }
    }

    foreach ($action in @($Actions)) {
        if (-not $action) { continue }

        $commandNames = Get-QOTTweaksInstantToggleCommandNames -ActionId ([string]$action.ActionId)
        if (-not $commandNames) { continue }

        $control = Get-QOTNamedElement -Root $Window -Name ([string]$action.Name)
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
            RestartExplorer  = (Test-QOTTweakRequiresExplorerRestart -ActionId ([string]$action.ActionId))
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
                try { Write-QLog ("Tweaks live-state init failed for {0}: {1}" -f $action.ActionId, $_.Exception.Message) "WARN" } catch { }
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
            $control.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent, $script:QOTTweaksInstantToggleMouseHandler, $true)
        }
        catch {
            try { Write-QLog ("Tweaks mouse handler attach failed for {0}: {1}" -f $action.ActionId, $_.Exception.ToString()) "ERROR" } catch { }
        }

        $state.Handlers[[string]$action.Name] = @{
            MouseUp = $script:QOTTweaksInstantToggleMouseHandler
        }
    }
}

function Sync-QOTTweaksInstantToggleStates {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][object[]]$Actions
    )

    $getLiveStateCmd = Get-Command Get-QOTTweaksLiveToggleState -ErrorAction SilentlyContinue | Select-Object -First 1
    $setToggleStateCmd = Resolve-QOTTweaksToggleStateCommand -Name "Set-QOToggleActionState"
    if (-not $getLiveStateCmd) { return }

    $state = $script:QOTTweaksInstantToggleState
    foreach ($action in @($Actions)) {
        if (-not $action -or [string]::IsNullOrWhiteSpace([string]$action.Name)) { continue }
        if (-not (Get-QOTTweaksInstantToggleCommandNames -ActionId ([string]$action.ActionId))) { continue }

        $control = Get-QOTNamedElement -Root $Window -Name ([string]$action.Name)
        if (-not ($control -is [System.Windows.Controls.CheckBox])) { continue }

        $controlName = [string]$control.Name
        if ($state.Busy[$controlName]) { continue }

        $liveState = $null
        try { $liveState = & $getLiveStateCmd -ActionId ([string]$action.ActionId) } catch { $liveState = $null }
        if ($null -eq $liveState) { continue }

        $previousRestoreFlag = [bool]$state.RestoreInProgress
        $state.RestoreInProgress = $true
        try { $control.IsChecked = [bool]$liveState } catch { }
        finally { $state.RestoreInProgress = $previousRestoreFlag }

        if ($setToggleStateCmd) {
            try { & $setToggleStateCmd -ActionId ([string]$action.ActionId) -IsEnabled ([bool]$liveState) | Out-Null } catch { }
        }
    }
}

function Get-QOTTweaksSectionSelectionSummary {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [string[]]$OptionNames
    )

    $total = 0
    $checked = 0

    foreach ($name in @($OptionNames)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $control = Get-QOTNamedElement -Root $Window -Name $name
        if (-not ($control -is [System.Windows.Controls.CheckBox])) { continue }

        $isBusy = $false
        try { $isBusy = [bool]$script:QOTTweaksInstantToggleState.Busy[[string]$control.Name] } catch { $isBusy = $false }
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

function Set-QOTTweaksSectionOptionsState {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [string[]]$OptionNames,
        [Parameter(Mandatory)]
        [bool]$IsChecked,
        [hashtable]$ActionMap = @{}
    )

    $updated = 0
    $previousSync = [bool]$script:QOTTweaksSectionSelectorSyncInProgress
    $script:QOTTweaksSectionSelectorSyncInProgress = $true
    $explorerRestartBatchId = Start-QOTTweaksExplorerRestartBatch

    try {
        foreach ($name in @($OptionNames)) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $control = Get-QOTNamedElement -Root $Window -Name $name
            if (-not ($control -is [System.Windows.Controls.CheckBox])) { continue }
            if ($control.IsEnabled -eq $false) { continue }
            if ($control.IsChecked -eq $IsChecked) { continue }

            $control.IsChecked = $IsChecked

            $metadata = $null
            try { $metadata = $script:QOTTweaksInstantToggleState.Metadata[[string]$control.Name] } catch { $metadata = $null }
            if ($metadata) {
                Invoke-QOTTweaksInstantToggle -Sender $control
            }
            elseif ($IsChecked) {
                $actionId = $null
                try { $actionId = [string]$ActionMap[[string]$control.Name] } catch { $actionId = $null }
                if ([string]::IsNullOrWhiteSpace($actionId)) {
                    try { $actionId = [string]$control.Tag } catch { $actionId = $null }
                }
                if (-not [string]::IsNullOrWhiteSpace($actionId)) {
                    Invoke-QOTTweaksSectionOneShotAction -ActionId $actionId -Window $Window | Out-Null
                }
            }
            $updated++
        }
    }
    finally {
        Stop-QOTTweaksExplorerRestartBatch -BatchId $explorerRestartBatchId
        $script:QOTTweaksSectionSelectorSyncInProgress = $previousSync
    }

    return $updated
}

function Update-QOTTweaksSectionSelectorState {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [hashtable]$Section
    )

    $header = Get-QOTNamedElement -Root $Window -Name ([string]$Section.HeaderName)
    if (-not ($header -is [System.Windows.Controls.CheckBox])) { return }

    $summary = Get-QOTTweaksSectionSelectionSummary -Window $Window -OptionNames ([string[]]$Section.OptionNames)
    $targetState = $false
    if ($summary.Total -gt 0 -and $summary.Checked -gt 0 -and $summary.Checked -lt $summary.Total) {
        $targetState = $null
    }
    elseif ($summary.AllChecked) {
        $targetState = $true
    }

    $previousSync = [bool]$script:QOTTweaksSectionSelectorSyncInProgress
    $script:QOTTweaksSectionSelectorSyncInProgress = $true
    try {
        $header.IsThreeState = $false
        $header.IsEnabled = ($summary.Total -gt 0)
        $header.IsChecked = $targetState
    }
    finally {
        $script:QOTTweaksSectionSelectorSyncInProgress = $previousSync
    }
}

function Update-QOTTweaksSectionSelectorStates {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [hashtable[]]$Sections
    )

    foreach ($section in @($Sections)) {
        if (-not $section) { continue }
        Update-QOTTweaksSectionSelectorState -Window $Window -Section $section
    }
}

function Register-QOTTweaksSectionSelectors {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [hashtable[]]$Sections,
        [hashtable]$ActionMap = @{}
    )

    $sectionsSnapshot = @($Sections)
    $updateAllFn = ${function:Update-QOTTweaksSectionSelectorStates}
    $setSectionFn = ${function:Set-QOTTweaksSectionOptionsState}
    $actionMap = if ($ActionMap) { $ActionMap } else { @{} }

    foreach ($section in $sectionsSnapshot) {
        if (-not $section -or [string]::IsNullOrWhiteSpace([string]$section.HeaderName)) { continue }

        $headerName = [string]$section.HeaderName
        $header = Get-QOTNamedElement -Root $Window -Name $headerName
        if (-not ($header -is [System.Windows.Controls.CheckBox])) { continue }

        if ($script:QOTTweaksSectionSelectorHandlers.ContainsKey($headerName)) {
            $oldHandler = $script:QOTTweaksSectionSelectorHandlers[$headerName]
            try { $header.Remove_Checked($oldHandler) } catch { }
            try { $header.Remove_Unchecked($oldHandler) } catch { }
        }

        $sectionSnapshot = $section
        $handler = [System.Windows.RoutedEventHandler]{
            param($sender, $args)

            if ($script:QOTTweaksSectionSelectorSyncInProgress) { return }
            $targetState = ($sender -is [System.Windows.Controls.CheckBox] -and $sender.IsChecked -eq $true)

            $nowTicks = [Environment]::TickCount64
            if (-not ($script:QOTTweaksSectionLastBulkActions -is [hashtable])) {
                $script:QOTTweaksSectionLastBulkActions = @{}
            }
            $lastBulkAction = $null
            try { $lastBulkAction = $script:QOTTweaksSectionLastBulkActions[$headerName] } catch { $lastBulkAction = $null }
            if ($lastBulkAction) {
                $lastTargetState = $null
                $lastTicks = 0
                try { $lastTargetState = [bool]$lastBulkAction.TargetState } catch { $lastTargetState = $null }
                try { $lastTicks = [int64]$lastBulkAction.Ticks } catch { $lastTicks = 0 }
                if ($null -ne $lastTargetState -and $lastTargetState -eq $targetState -and ($nowTicks - $lastTicks) -lt 2000) {
                    try { Write-QLog ("Tweaks & Cleaning section {0} duplicate {1} event ignored." -f $sectionSnapshot.HeaderName, $targetState) "DEBUG" } catch { }
                    return
                }
            }
            $script:QOTTweaksSectionLastBulkActions[$headerName] = [pscustomobject]@{
                TargetState = $targetState
                Ticks = $nowTicks
            }

            $updated = & $setSectionFn -Window $Window -OptionNames ([string[]]$sectionSnapshot.OptionNames) -IsChecked $targetState -ActionMap $actionMap
            & $updateAllFn -Window $Window -Sections $sectionsSnapshot
            $actionLabel = if ($targetState) { "checked" } else { "unchecked" }
            try { Write-QLog ("Tweaks & Cleaning section {0} {1} {2} boxes." -f $sectionSnapshot.HeaderName, $actionLabel, $updated) "DEBUG" } catch { }
        }.GetNewClosure()

        $script:QOTTweaksSectionSelectorHandlers[$headerName] = $handler
        try { $header.Add_Checked($handler) } catch { }
        try { $header.Add_Unchecked($handler) } catch { }
    }

    foreach ($section in $sectionsSnapshot) {
        foreach ($name in @($section.OptionNames)) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $control = Get-QOTNamedElement -Root $Window -Name $name
            if (-not ($control -is [System.Windows.Controls.CheckBox])) { continue }

            if ($script:QOTTweaksSectionChildHandlers.ContainsKey($name)) {
                $oldChildHandler = $script:QOTTweaksSectionChildHandlers[$name]
                try { $control.Remove_Checked($oldChildHandler) } catch { }
                try { $control.Remove_Unchecked($oldChildHandler) } catch { }
            }

            $childHandler = [System.Windows.RoutedEventHandler]{
                param($sender, $args)
                if ($script:QOTTweaksSectionSelectorSyncInProgress) { return }
                & $updateAllFn -Window $Window -Sections $sectionsSnapshot
            }.GetNewClosure()

            $script:QOTTweaksSectionChildHandlers[$name] = $childHandler
            try { $control.Add_Checked($childHandler) } catch { }
            try { $control.Add_Unchecked($childHandler) } catch { }
        }
    }

    & $updateAllFn -Window $Window -Sections $sectionsSnapshot
}

function Initialize-QOTTweaksAndCleaningUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    try {
        $actions = @(
            @{ Name = "CbCleanTempFiles";       Label = "Deep clean temporary folders";                 ActionId = "Invoke-QCleanTemp" },
            @{ Name = "CbEmptyRecycleBin";      Label = "Empty Recycle Bin";                      ActionId = "Invoke-QCleanRecycleBin" },
            @{ Name = "CbCleanDoCache";         Label = "Clean Delivery Optimisation cache";      ActionId = "Invoke-QCleanDOCache" },
            @{ Name = "CbCleanWuCache";         Label = "Clear Windows Update cache";             ActionId = "Invoke-QCleanWindowsUpdateCache" },
            @{ Name = "CbCleanThumbCache";      Label = "Clean thumbnail cache";                  ActionId = "Invoke-QCleanThumbnailCache" },
            @{ Name = "CbCleanErrorLogs";       Label = "Clean old error logs and crash dumps";   ActionId = "Invoke-QCleanErrorLogs" },
            @{ Name = "CbCleanSetupLeftovers";  Label = "Remove safe setup / upgrade leftovers";  ActionId = "Invoke-QCleanSetupLeftovers" },
            @{ Name = "CbClearStoreCache";      Label = "Clear Microsoft Store cache";            ActionId = "Invoke-QCleanStoreCache" },
            @{ Name = "CbEdgeLightCleanup";     Label = "Light clean of Microsoft Edge cache";    ActionId = "Invoke-QCleanEdgeCache" },
            @{ Name = "CbChromeLightCleanup";   Label = "Light clean of Chrome / Chromium cache"; ActionId = "Invoke-QCleanChromeCache" },
            @{ Name = "CbCleanDirectXShaderCache"; Label = "Clear DirectX shader cache"; ActionId = "Invoke-QCleanDirectXShaderCache" },
            @{ Name = "CbCleanWERQueue"; Label = "Clear Windows Error Reporting queue"; ActionId = "Invoke-QCleanWERQueue" },
            @{ Name = "CbClearClipboardHistory"; Label = "Clear clipboard history"; ActionId = "Invoke-QCleanClipboardHistory" },
            @{ Name = "CbCleanExplorerRecentItems"; Label = "Clear Explorer Recent items and Jump Lists"; ActionId = "Invoke-QCleanExplorerRecentItems" },
            @{ Name = "CbCleanWindowsSearchHistory"; Label = "Clear Windows Search history"; ActionId = "Invoke-QCleanWindowsSearchHistory" },
            @{ Name = "CbCleanPrefetchFiles"; Label = "Clear Prefetch files"; ActionId = "Invoke-QCleanPrefetchFiles" },
            @{ Name = "CbRefreshIconCache"; Label = "Refresh Windows icon cache"; ActionId = "Invoke-QRefreshWindowsIconCache" },
            @{ Name = "CbClearEventLogs"; Label = "Clear Windows Event Logs"; ActionId = "Invoke-QClearWindowsEventLogs" },
            @{ Name = "CbClearTeamsCache"; Label = "Clear Microsoft Teams cache"; ActionId = "Invoke-QCleanTeamsCache" },
            @{ Name = "CbDisableStartRecommended"; Label = "Hide Start menu recommended items";   ActionId = "Invoke-QTweakStartMenuRecommendations" },
            @{ Name = "CbDisableSuggestedApps";    Label = "Turn off suggested apps and promotions"; ActionId = "Invoke-QTweakSuggestedApps" },
            @{ Name = "CbDisableTipsStart";        Label = "Disable tips and suggestions in Start"; ActionId = "Invoke-QTweakTipsInStart" },
            @{ Name = "CbDisableBingSearch";       Label = "Turn off Bing / web results in Start search"; ActionId = "Invoke-QTweakBingSearch" },
            @{ Name = "CbClassicMoreOptions";      Label = "Use classic 'More options' right-click menu"; ActionId = "Invoke-QTweakClassicContextMenu" },
            @{ Name = "CbDisableWidgets";          Label = "Turn off Widgets";                    ActionId = "Invoke-QTweakWidgets" },
            @{ Name = "CbDisableTaskbarNews";      Label = "Turn off News / taskbar content";      ActionId = "Invoke-QTweakNewsAndInterests" },
            @{ Name = "CbDisableMeetNow";          Label = "Hide legacy Meet Now button";          ActionId = "Invoke-QTweakMeetNow" },
            @{ Name = "CbDisableAdvertisingId";    Label = "Turn off advertising ID";              ActionId = "Invoke-QTweakAdvertisingId" },
            @{ Name = "CbLimitFeedbackPrompts";    Label = "Reduce feedback and survey prompts";   ActionId = "Invoke-QTweakFeedbackHub" },
            @{ Name = "CbDisableOnlineTips";       Label = "Disable online tips and suggestions";  ActionId = "Invoke-QTweakOnlineTips" },
            @{ Name = "CbDisableLockScreenTips"; Label = "Disable lock screen tips, suggestions, and spotlight extras"; ActionId = "Invoke-QTweakDisableLockScreenTips" },
            @{ Name = "CbDisableSettingsSuggestedContent"; Label = "Disable Suggested content in Settings"; ActionId = "Invoke-QTweakDisableSettingsSuggestedContent" },
            @{ Name = "CbDisableTransparencyEffects"; Label = "Turn off transparency effects"; ActionId = "Invoke-QTweakDisableTransparencyEffects" },
            @{ Name = "CbDisableStartupDelay"; Label = "Disable startup delay for startup apps"; ActionId = "Invoke-QTweakDisableStartupDelay" },
            @{ Name = "CbDisableGameDVR"; Label = "Disable Game DVR"; ActionId = "Invoke-QTweakDisableGameDVR" },
            @{ Name = "CbDisableWindowsConsumerFeatures"; Label = "Disable Windows consumer features"; ActionId = "Invoke-QTweakDisableWindowsConsumerFeatures" },
            @{ Name = "CbDisableWindowsRecall"; Label = "Disable Windows Recall"; ActionId = "Invoke-QTweakDisableWindowsRecall" }
        )
        
        $actionsSnapshot = $actions
        $sectionActionMap = @{}
        foreach ($action in @($actionsSnapshot)) {
            if (-not $action -or [string]::IsNullOrWhiteSpace([string]$action.Name)) { continue }
            $sectionActionMap[[string]$action.Name] = [string]$action.ActionId
        }
        $sectionSelectors = @(
            @{
                HeaderName = "CbSectionStorageCleanup"
                OptionNames = @("CbCleanTempFiles", "CbEmptyRecycleBin", "CbCleanDoCache", "CbCleanWuCache", "CbCleanThumbCache", "CbCleanPrefetchFiles", "CbRefreshIconCache")
            },
            @{
                HeaderName = "CbSectionWindowsHousekeeping"
                OptionNames = @("CbCleanErrorLogs", "CbCleanSetupLeftovers", "CbClearStoreCache", "CbClearEventLogs", "CbClearTeamsCache")
            },
            @{
                HeaderName = "CbSectionBrowserCleanup"
                OptionNames = @("CbEdgeLightCleanup", "CbChromeLightCleanup", "CbCleanDirectXShaderCache", "CbCleanWERQueue", "CbClearClipboardHistory", "CbCleanExplorerRecentItems", "CbCleanWindowsSearchHistory")
            },
            @{
                HeaderName = "CbSectionStartMenuRecommendations"
                OptionNames = @("CbDisableStartRecommended", "CbDisableSuggestedApps", "CbDisableTipsStart", "CbDisableBingSearch", "CbClassicMoreOptions")
            },
            @{
                HeaderName = "CbSectionTaskbarWidgets"
                OptionNames = @("CbDisableWidgets", "CbDisableTaskbarNews", "CbDisableMeetNow")
            },
            @{
                HeaderName = "CbSectionPrivacyTelemetry"
                OptionNames = @("CbDisableAdvertisingId", "CbLimitFeedbackPrompts", "CbDisableOnlineTips", "CbDisableLockScreenTips", "CbDisableSettingsSuggestedContent", "CbDisableTransparencyEffects", "CbDisableStartupDelay")
            },
            @{
                HeaderName = "CbSectionPerformanceTweaks"
                OptionNames = @("CbDisableGameDVR", "CbDisableWindowsConsumerFeatures", "CbDisableWindowsRecall")
            }
        )
        $actionGroupName = "Tweaks & Cleaning"

        try {

            $uiCheckboxes = @()
            $missingUICheckboxes = @()
            $mappedNames = @($actionsSnapshot | ForEach-Object { $_.Name })
            $namedElements = Get-QOTNamedElementsMap -Root $Window -Names $mappedNames
            foreach ($action in $actionsSnapshot) {
                $control = Get-QOTNamedElement -Root $Window -Name $action.Name
                $control = $namedElements[$action.Name]
                if ($control -and $control -is [System.Windows.Controls.CheckBox]) {
                    $uiCheckboxes += [pscustomobject]@{
                        Name = $control.Name
                        Label = [string]$control.Content
                    }
                }
                else {
                    $missingUICheckboxes += $action
                }
            }

            $actionByName = @{}
            $duplicateActionNames = @()
            foreach ($action in $actionsSnapshot) {
                if (-not [string]::IsNullOrWhiteSpace($action.Name)) {
                    if ($actionByName.ContainsKey($action.Name)) {
                        $duplicateActionNames += $action.Name
                    } else {
                        $actionByName[$action.Name] = $action
                    }
                }
            }

            $duplicateUICheckboxes = @($uiCheckboxes | Group-Object Name | Where-Object { $_.Count -gt 1 })
            $missingFromActionList = @($uiCheckboxes | Where-Object { -not $actionByName.ContainsKey($_.Name) })
            $missingDefinitions = @()
            foreach ($action in $actionsSnapshot) {
                $definition = Get-QOTActionDefinition -ActionId $action.ActionId
                if (-not $definition) {
                    $missingDefinitions += $action
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($definition.ScriptPath) -or -not (Test-Path -LiteralPath $definition.ScriptPath)) {
                    $missingDefinitions += $action
                }
            }

            try { Write-QLog ("Tweaks & Cleaning checkboxes discovered in UI: {0}" -f $uiCheckboxes.Count) "INFO" } catch { }
            if ($uiCheckboxes.Count -eq 0) {
                $criticalMessage = "Tweaks & Cleaning checkboxes discovered in UI: 0. Startup halted to prevent silent action mismatches."
                try { Write-QLog $criticalMessage "CRITICAL" } catch {
                    try { Write-QLog $criticalMessage "ERROR" } catch { }
                }
                throw $criticalMessage
            }

            foreach ($cb in $uiCheckboxes) {
                try { Write-QLog ("Tweaks & Cleaning checkbox: {0} | {1}" -f $cb.Name, $cb.Label) "DEBUG" } catch { }
            }

            try { Write-QLog ("Tweaks & Cleaning actions mapped in UI module: {0}" -f $actionsSnapshot.Count) "INFO" } catch { }
            try {
                $catalogState = Get-QOTActionCatalogState
                Write-QLog ("ActionCatalog instance: {0} hash={1} count={2} (right before Tweaks UI mapping check)" -f $catalogState.TypeName, $catalogState.HashCode, $catalogState.Count) "INFO"
            } catch { }
            try { Write-QLog ("Total registered action definitions: {0}" -f (Get-QOTActionDefinitionCount)) "INFO" } catch { }

            if ($missingFromActionList.Count -gt 0) {
                foreach ($missing in $missingFromActionList) {
                    try { Write-QLog ("Tweaks & Cleaning checkbox has no mapped action definition: {0} | {1}" -f $missing.Name, $missing.Label) "WARN" } catch { }
                }
            }

            if ($missingDefinitions.Count -gt 0) {
                foreach ($missingDef in $missingDefinitions) {
                    try { Write-QLog ("Tweaks & Cleaning mapped action has no registered definition or script: {0} -> {1}" -f $missingDef.Name, $missingDef.ActionId) "WARN" } catch { }
                }
            }
            if ($missingUICheckboxes.Count -gt 0) {
                foreach ($missingUI in $missingUICheckboxes) {
                    try { Write-QLog ("Tweaks & Cleaning mapped checkbox missing in XAML: {0} -> {1}" -f $missingUI.Name, $missingUI.ActionId) "WARN" } catch { }
                }
            }
            if ($duplicateActionNames.Count -gt 0) {
                foreach ($duplicateName in ($duplicateActionNames | Select-Object -Unique)) {
                    try { Write-QLog ("Tweaks & Cleaning duplicate action Name detected: {0}" -f $duplicateName) "WARN" } catch { }
                }
            }

            if ($duplicateUICheckboxes.Count -gt 0) {
                foreach ($duplicateGroup in $duplicateUICheckboxes) {
                    try { Write-QLog ("Tweaks & Cleaning duplicate UI checkbox Name detected: {0}" -f $duplicateGroup.Name) "WARN" } catch { }
                }
            }

            if ($missingFromActionList.Count -eq 0 -and $missingDefinitions.Count -eq 0 -and $missingUICheckboxes.Count -eq 0 -and $uiCheckboxes.Count -eq $actionsSnapshot.Count -and $duplicateActionNames.Count -eq 0 -and $duplicateUICheckboxes.Count -eq 0) {
                try { Write-QLog "Tweaks & Cleaning checkbox/action mapping validated: no visual-only checkboxes detected." "INFO" } catch { }
            }
            if ($missingFromActionList.Count -gt 0 -or $missingDefinitions.Count -gt 0 -or $missingUICheckboxes.Count -gt 0) {
                $criticalMessage = "Tweaks & Cleaning checkbox/action mapping mismatch detected. Startup halted to prevent incorrect execution wiring."
                try { Write-QLog $criticalMessage "CRITICAL" } catch {
                    try { Write-QLog $criticalMessage "ERROR" } catch { }
                }
                throw $criticalMessage
            }
        }
        catch {
            try { Write-QLog ("Failed to validate Tweaks & Cleaning checkbox mappings: {0}" -f $_.Exception.Message) "ERROR" } catch { }
            throw
        }
        
        Register-QOTActionGroup -Name $actionGroupName -GetItems ({
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
                        $control = $null
                        if ($window -is [System.Windows.FrameworkElement]) {
                            try { $control = $window.FindName($actionName) } catch { }
                        }
                        return ($control -is [System.Windows.Controls.CheckBox] -and $control.IsChecked -eq $true)
                    }).GetNewClosure()
                }
            }
            return $items
        }).GetNewClosure()

        Register-QOTTweaksInstantToggleHandlers -Window $Window -Actions $actionsSnapshot
        Sync-QOTTweaksInstantToggleStates -Window $Window -Actions $actionsSnapshot

        if ($script:QOTTweaksInstantToggleRefreshHandler) {
            try { $Window.Remove_Activated($script:QOTTweaksInstantToggleRefreshHandler) } catch { }
        }
        $refreshActions = @($actionsSnapshot)
        $syncFn = ${function:Sync-QOTTweaksInstantToggleStates}
        $script:QOTTweaksInstantToggleRefreshHandler = [System.EventHandler]{
            param($sender, $args)
            try {
                & $syncFn -Window $Window -Actions $refreshActions
            }
            catch {
                try { Write-QLog ("Tweaks live-state refresh error: {0}" -f $_.Exception.Message) "WARN" } catch { }
            }
        }.GetNewClosure()
        try { $Window.Add_Activated($script:QOTTweaksInstantToggleRefreshHandler) } catch { }

        $cbDisableWindowsRecall = Get-QOTNamedElement -Root $Window -Name "CbDisableWindowsRecall"
        if ($cbDisableWindowsRecall -is [System.Windows.Controls.CheckBox]) {
            $isRecallSupported = $false
            try {
                $cv = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
                $build = 0
                try { $build = [int]$cv.CurrentBuildNumber } catch { $build = 0 }
                $isRecallSupported = ($build -ge 26100)
            }
            catch {
                $isRecallSupported = $false
            }

            if (-not $isRecallSupported) {
                $cbDisableWindowsRecall.IsChecked = $false
                $cbDisableWindowsRecall.IsEnabled = $false
                $cbDisableWindowsRecall.ToolTip = "Safe: disables Recall screenshot tracking when supported (unsupported on this system)."
                try {
                    $setToggleStateCmd = Resolve-QOTTweaksToggleStateCommand -Name "Set-QOToggleActionState"
                    if ($setToggleStateCmd) {
                        & $setToggleStateCmd -ActionId "Invoke-QTweakDisableWindowsRecall" -IsEnabled $false | Out-Null
                    }
                }
                catch { }
            }
            else {
                $cbDisableWindowsRecall.IsEnabled = $true
            }
        }
        $txtSelectedCount = Get-QOTNamedElement -Root $Window -Name "TxtSelectedCount"
        if ($txtSelectedCount) {
            $getNamedElementForCountFn = ${function:Get-QOTNamedElement}
            $updateSelectedCount = {
                $selectedCount = 0
                foreach ($mapped in $actionsSnapshot) {
                    if (-not $mapped -or [string]::IsNullOrWhiteSpace([string]$mapped.Name)) { continue }
                    $cb = & $getNamedElementForCountFn -Root $Window -Name ([string]$mapped.Name)
                    if ($cb -is [System.Windows.Controls.CheckBox] -and $cb.IsChecked -eq $true) {
                        $selectedCount++
                    }
                }

                try {
                    if ($null -ne $txtSelectedCount.PSObject.Properties['Text']) {
                        $txtSelectedCount.Text = [string]$selectedCount
                    }
                }
                catch { }
            }.GetNewClosure()

            foreach ($mapped in $actionsSnapshot) {
                if (-not $mapped -or [string]::IsNullOrWhiteSpace([string]$mapped.Name)) { continue }
                $cb = Get-QOTNamedElement -Root $Window -Name ([string]$mapped.Name)
                if ($cb -is [System.Windows.Controls.CheckBox]) {
                    $cb.Add_Checked({ param($sender, $args) & $updateSelectedCount }.GetNewClosure())
                    $cb.Add_Unchecked({ param($sender, $args) & $updateSelectedCount }.GetNewClosure())
                }
            }

            & $updateSelectedCount
        }

        Register-QOTTweaksSectionSelectors -Window $Window -Sections $sectionSelectors -ActionMap $sectionActionMap

        $btnSelectAllTabActions = Get-QOTNamedElement -Root $Window -Name "BtnSelectAllTabActions"
        if ($btnSelectAllTabActions) {
            $selectAllIcon = Get-QOTNamedElement -Root $Window -Name "TxtSelectAllTabActionsIcon"
            $tabCleaning = Get-QOTNamedElement -Root $Window -Name "TabCleaning"
            $scopeRoot = $tabCleaning
            if ($tabCleaning -is [System.Windows.Controls.TabItem] -and $tabCleaning.Content -is [System.Windows.DependencyObject]) {
                $scopeRoot = [System.Windows.DependencyObject]$tabCleaning.Content
            }

            if ($script:QOTSelectAllTabActionsHandler) {
                try { $btnSelectAllTabActions.Remove_Click($script:QOTSelectAllTabActionsHandler) } catch { }
            }

            $setCheckboxStateInScopeFn = ${function:Set-QOTCheckboxStateInScope}
            $getCheckboxSummaryInScopeFn = ${function:Get-QOTCheckboxSummaryInScope}
            $updateSelectAllButtonUi = {
                param($summary)

                if (-not $btnSelectAllTabActions) { return }

                $allChecked = $false
                if ($summary -and $summary.PSObject.Properties['AllChecked']) {
                    $allChecked = [bool]$summary.AllChecked
                }

                if ($allChecked) {
                    $btnSelectAllTabActions.ToolTip = "Uncheck all boxes"
                    if ($selectAllIcon -is [System.Windows.Controls.TextBlock]) {
                        $selectAllIcon.Text = [string][char]0xE73D
                    }
                }
                else {
                    $btnSelectAllTabActions.ToolTip = "Check all boxes"
                    if ($selectAllIcon -is [System.Windows.Controls.TextBlock]) {
                        $selectAllIcon.Text = [string][char]0xE73A
                    }
                }
            }.GetNewClosure()

            $initialSummary = & $getCheckboxSummaryInScopeFn -Root $scopeRoot
            & $updateSelectAllButtonUi -summary $initialSummary

            $script:QOTSelectAllTabActionsHandler = [System.Windows.RoutedEventHandler]{
                param($sender, $args)

                if (-not $scopeRoot) { return }

                $summaryBefore = & $getCheckboxSummaryInScopeFn -Root $scopeRoot
                $targetCheckedState = -not [bool]$summaryBefore.AllChecked
                $updated = & $setCheckboxStateInScopeFn -Root $scopeRoot -IsChecked $targetCheckedState
                $summaryAfter = & $getCheckboxSummaryInScopeFn -Root $scopeRoot
                & $updateSelectAllButtonUi -summary $summaryAfter

                $actionLabel = if ($targetCheckedState) { "checked" } else { "unchecked" }
                try { Write-QLog ("Tweaks & Cleaning Select All {0} {1} boxes." -f $actionLabel, $updated) "DEBUG" } catch { }
            }.GetNewClosure()

            try { $btnSelectAllTabActions.Add_Click($script:QOTSelectAllTabActionsHandler) } catch { }
        }

        try { Write-QLog "Tweaks & Cleaning UI initialised (action registry)." "DEBUG" } catch { }
    }
    catch {
        try { Write-QLog ("Tweaks/Cleaning UI initialisation error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
        throw
    }
}

Export-ModuleMember -Function Initialize-QOTTweaksAndCleaningUI
