# src\UI\MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# One time init for Tickets UI
$script:TicketsUIInitialised = $false
$script:AppsUIInitialised = $false
$script:MainWindow = $null
$script:SummaryTextBlock = $null
$script:SummaryTimer = $null
$script:PlayButtonTimer = $null
$script:IsPlayRunning = $false
$script:GlobalExceptionHandlersRegistered = $false
$script:DispatcherUnhandledExceptionHandler = $null
$script:AppDomainUnhandledExceptionHandler = $null
$script:TaskUnobservedExceptionHandler = $null
$script:MainTabSelectionMemoryHandler = $null
$script:QOT_TaskRunnerState = $null
$script:QOTTaskbarIdentityApplied = $false
$script:QOT_LogsButton = $null
$script:QOT_LogsButtonHandler = $null
$script:QOT_QuickSafeCleanupHandler = $null
$script:QOT_QuickSafeCleanupResetInProgress = $false
$script:QOT_RailNavigationSelectionHandler = $null
$script:QOT_RailDragSource = $null
$script:QOT_RailDragStartPoint = $null
$script:QOT_RailIsDragging = $false
$script:QOT_TaskResultsWindow = $null
$script:QOT_TaskResultsSummaryText = $null
$script:QOT_TaskResultsGrid = $null
$script:QOT_TaskResultsPlaceholderEntries = $null
$script:QOT_TaskRunEntries = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$script:QOT_TaskRunSummary = [ordered]@{
    SelectedCount = 0
    Worked = 0
    Skipped = 0
    Failed = 0
    LastRunAt = $null
}

# Centralized timer registry. Every DispatcherTimer created in this module should
# be added here via Register-QOTMainWindowTimer so it can be cleanly stopped and
# disposed on window close / module reload. Prevents ghost timers from firing
# against a disposed window and accumulating CPU+memory cost over time.
# Uses ArrayList (not List[DispatcherTimer]) so the script does not fail to load
# before PresentationFramework / WindowsBase have been registered in this session.
$script:ActiveTimers = New-Object System.Collections.ArrayList

function Register-QOTMainWindowTimer {
    <#
    .SYNOPSIS
    Tracks a DispatcherTimer in the central registry so Stop-AllTimers can
    later stop and dispose it.
    .DESCRIPTION
    Pass any newly-created DispatcherTimer through this helper before Start().
    The function does not Start the timer for you - callers retain control of
    interval, tick handlers, and lifetime.
    .EXAMPLE
    $t = [System.Windows.Threading.DispatcherTimer]::new()
    $t.Interval = [TimeSpan]::FromSeconds(5)
    $t.Add_Tick({ ... })
    Register-QOTMainWindowTimer -Timer $t
    $t.Start()
    #>
    param(
        [Parameter(Mandatory)]$Timer
    )

    if (-not $Timer) { return }
    if (-not $script:ActiveTimers) {
        $script:ActiveTimers = New-Object System.Collections.ArrayList
    }
    if (-not $script:ActiveTimers.Contains($Timer)) {
        $null = $script:ActiveTimers.Add($Timer)
    }
}

function Stop-AllTimers {
    <#
    .SYNOPSIS
    Stops every DispatcherTimer in the central registry, then clears the list.
    .DESCRIPTION
    Call on window close and before any module reload. Each Stop() is wrapped
    in try/catch so one bad timer cannot block the rest from being stopped.
    Timers do not implement IDisposable, so we only Stop() them - clearing the
    registry releases the last script-level reference and lets GC collect them.
    #>
    if (-not $script:ActiveTimers -or $script:ActiveTimers.Count -eq 0) { return }

    $stopped = 0
    foreach ($timer in @($script:ActiveTimers)) {
        if (-not $timer) { continue }
        try {
            if ($timer.IsEnabled) { $timer.Stop() }
            $stopped++
        }
        catch {
            # Timer may already be stopped or disposed; ignore and continue.
        }
    }
    try { $script:ActiveTimers.Clear() } catch { }
    try { Write-QOTStartupTrace ("MainWindow: Stop-AllTimers stopped {0} timer(s)." -f $stopped) } catch { }
}

function Resolve-QOTInvokableCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][System.Management.Automation.ActionPreference]$LookupErrorAction = [System.Management.Automation.ActionPreference]::Stop
    )

    $resolved = $null
    try {
        $resolved = @(Get-Command -Name $Name -ErrorAction $LookupErrorAction | Select-Object -First 1)
    } catch {
        if ($LookupErrorAction -eq [System.Management.Automation.ActionPreference]::Stop) { throw }
        return $null
    }

    if ($resolved -is [System.Array]) {
        if ($resolved.Count -gt 0) { return $resolved[0] }
        return $null
    }

    return $resolved
}

function Get-QOTPersistableTabName {
    param([AllowNull()]$Tab)

    if (-not $Tab) { return $null }
    $name = ""
    try { $name = [string]$Tab.Name } catch { $name = "" }
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }

    $persistable = @("TabCleaning", "TabApps", "TabAdvanced", "TabTickets")
    if ($persistable -contains $name) { return $name }
    return $null
}

function Convert-QOTLegacyStartTabToName {
    param([AllowNull()][string]$LegacyTab)

    switch (([string]($LegacyTab + "")).Trim()) {
        "Cleaning" { return "TabCleaning" }
        "Apps"     { return "TabApps" }
        "Advanced" { return "TabAdvanced" }
        "Tickets"  { return "TabTickets" }
        default    { return $null }
    }
}

function Convert-QOTTabNameToLegacyStartTab {
    param([AllowNull()][string]$TabName)

    switch (([string]($TabName + "")).Trim()) {
        "TabCleaning" { return "Cleaning" }
        "TabApps"     { return "Apps" }
        "TabAdvanced" { return "Advanced" }
        "TabTickets"  { return "Tickets" }
        default       { return "Cleaning" }
    }
}

function Save-QOTSelectedTabMemory {
    param([AllowNull()]$Tabs)

    if (-not $Tabs) { return }
    if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) { return }
    if (-not (Get-Command Save-QOSettings -ErrorAction SilentlyContinue)) { return }

    $selectedTabName = Get-QOTPersistableTabName -Tab $Tabs.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selectedTabName)) { return }

    try {
        $settings = Get-QOSettings
        if (-not $settings) { return }

        if ($settings.PSObject.Properties.Name -notcontains "UiState") {
            $settings | Add-Member -NotePropertyName UiState -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if ($settings.UiState.PSObject.Properties.Name -notcontains "LastSelectedTab") {
            $settings.UiState | Add-Member -NotePropertyName LastSelectedTab -NotePropertyValue $selectedTabName -Force
        } else {
            $settings.UiState.LastSelectedTab = $selectedTabName
        }

        $legacyStartTab = Convert-QOTTabNameToLegacyStartTab -TabName $selectedTabName
        if ($settings.PSObject.Properties.Name -notcontains "PreferredStartTab") {
            $settings | Add-Member -NotePropertyName PreferredStartTab -NotePropertyValue $legacyStartTab -Force
        } else {
            $settings.PreferredStartTab = $legacyStartTab
        }

        Save-QOSettings -Settings $settings
    } catch { }
}

function Restore-QOTSelectedTabMemory {
    param([AllowNull()]$Tabs)

    if (-not $Tabs) { return }
    if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) { return }

    $targetName = $null
    try {
        $settings = Get-QOSettings
        if (-not $settings) { return }

        if ($settings.PSObject.Properties.Name -contains "UiState" -and $settings.UiState) {
            if ($settings.UiState.PSObject.Properties.Name -contains "LastSelectedTab") {
                $candidate = ([string]$settings.UiState.LastSelectedTab).Trim()
                if ($candidate) {
                    $targetName = $candidate
                }
            }
        }

        if (-not $targetName -and $settings.PSObject.Properties.Name -contains "PreferredStartTab") {
            $targetName = Convert-QOTLegacyStartTabToName -LegacyTab ([string]$settings.PreferredStartTab)
        }
    } catch { return }

    if (-not $targetName) { return }

    try {
        foreach ($item in @($Tabs.Items)) {
            if (-not $item) { continue }
            $name = ""
            try { $name = [string]$item.Name } catch { $name = "" }
            if ($name -ne $targetName) { continue }
            if ($item.Visibility -ne [System.Windows.Visibility]::Visible) { break }
            $Tabs.SelectedItem = $item
            break
        }
    } catch { }
}

function Get-QOTDefaultRailIconOrder {
    return @(
        "BtnNavCleaning",
        "BtnNavApps",
        "BtnNavAdvanced",
        "BtnNavTickets",
        "CbQuickSafeCleanup",
        "BtnPlay",
        "BtnLogs",
        "BtnHelp",
        "BtnSettings"
    )
}

function Save-QOTRailIconOrder {
    param([string[]]$Order)

    if (-not $Order -or $Order.Count -eq 0) { return }
    if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) { return }
    if (-not (Get-Command Save-QOSettings -ErrorAction SilentlyContinue)) { return }

    try {
        $settings = Get-QOSettings
        if (-not $settings) { return }

        if ($settings.PSObject.Properties.Name -notcontains "UiState") {
            $settings | Add-Member -NotePropertyName UiState -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if ($settings.UiState.PSObject.Properties.Name -notcontains "RailIconOrder") {
            $settings.UiState | Add-Member -NotePropertyName RailIconOrder -NotePropertyValue @($Order) -Force
        }
        else {
            $settings.UiState.RailIconOrder = @($Order)
        }

        Save-QOSettings -Settings $settings
    }
    catch { }
}

function Get-QOTSavedRailIconOrder {
    if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) {
        return @(Get-QOTDefaultRailIconOrder)
    }

    $defaultOrder = @(Get-QOTDefaultRailIconOrder)
    try {
        $settings = Get-QOSettings
        if (-not $settings) { return $defaultOrder }
        if ($settings.PSObject.Properties.Name -notcontains "UiState" -or -not $settings.UiState) { return $defaultOrder }
        if ($settings.UiState.PSObject.Properties.Name -notcontains "RailIconOrder") { return $defaultOrder }

        $saved = @($settings.UiState.RailIconOrder | ForEach-Object { ([string]($_ + "")).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($saved.Count -eq 0) { return $defaultOrder }

        $validNames = @{}
        foreach ($name in $defaultOrder) { $validNames[$name] = $true }

        $normalized = New-Object System.Collections.Generic.List[string]
        foreach ($name in $saved) {
            if ($validNames.ContainsKey($name) -and -not $normalized.Contains($name)) {
                $normalized.Add($name) | Out-Null
            }
        }
        foreach ($name in $defaultOrder) {
            if (-not $normalized.Contains($name)) {
                $normalized.Add($name) | Out-Null
            }
        }

        return @($normalized)
    }
    catch {
        return $defaultOrder
    }
}

function Get-QOTRailIconCurrentOrder {
    param([AllowNull()]$Host)

    if (-not $Host) { return @() }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($child in @($Host.Children)) {
        if (-not $child) { continue }
        $name = Get-QOTRailHostChildKey -Child $child
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $result.Add($name) | Out-Null
    }
    return @($result)
}

function Apply-QOTRailIconOrder {
    param(
        [AllowNull()]$Host,
        [string[]]$Order
    )

    if (-not $Host) { return @() }

    $childrenByName = @{}
    foreach ($child in @($Host.Children)) {
        if (-not $child) { continue }
        $name = Get-QOTRailHostChildKey -Child $child
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $childrenByName[$name] = $child
    }

    $targetOrder = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($Order)) {
        if ($childrenByName.ContainsKey($name) -and -not $targetOrder.Contains($name)) {
            $targetOrder.Add($name) | Out-Null
        }
    }
    foreach ($name in @(Get-QOTDefaultRailIconOrder)) {
        if ($childrenByName.ContainsKey($name) -and -not $targetOrder.Contains($name)) {
            $targetOrder.Add($name) | Out-Null
        }
    }

    $newChildren = @()
    foreach ($name in $targetOrder) {
        if ($childrenByName.ContainsKey($name)) {
            $newChildren += $childrenByName[$name]
        }
    }

    try {
        $Host.Children.Clear()
        foreach ($child in $newChildren) {
            [void]$Host.Children.Add($child)
        }
    }
    catch { }

    return @($targetOrder)
}

function Get-QOTRailHostChildKey {
    param([AllowNull()]$Child)

    if (-not $Child) { return "" }

    $tagValue = $null
    try { $tagValue = $Child.Tag } catch { $tagValue = $null }
    if ($tagValue -is [string] -and -not [string]::IsNullOrWhiteSpace($tagValue)) {
        return ([string]$tagValue).Trim()
    }

    $name = ""
    try { $name = [string]$Child.Name } catch { $name = "" }
    return $name
}

function Move-QOTRailIconOrder {
    param(
        [string[]]$Order,
        [Parameter(Mandatory)][string]$SourceName,
        [string]$TargetName,
        [ValidateSet("Before","After","End")][string]$Placement = "Before"
    )

    $normalizedOrder = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($Order)) {
        $normalizedName = ([string]($name + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($normalizedName)) { continue }
        if (-not $normalizedOrder.Contains($normalizedName)) {
            $normalizedOrder.Add($normalizedName) | Out-Null
        }
    }

    if ($normalizedOrder.Count -eq 0) { return @() }
    if ([string]::IsNullOrWhiteSpace($SourceName) -or -not $normalizedOrder.Contains($SourceName)) {
        return @($normalizedOrder)
    }

    [void]$normalizedOrder.Remove($SourceName)

    if (
        $Placement -eq "End" -or
        [string]::IsNullOrWhiteSpace($TargetName) -or
        -not $normalizedOrder.Contains($TargetName)
    ) {
        $normalizedOrder.Add($SourceName) | Out-Null
        return @($normalizedOrder)
    }

    $targetIndex = $normalizedOrder.IndexOf($TargetName)
    if ($targetIndex -lt 0) {
        $normalizedOrder.Add($SourceName) | Out-Null
        return @($normalizedOrder)
    }

    if ($Placement -eq "After") {
        $targetIndex += 1
    }
    if ($targetIndex -gt $normalizedOrder.Count) {
        $targetIndex = $normalizedOrder.Count
    }

    $normalizedOrder.Insert($targetIndex, $SourceName)
    return @($normalizedOrder)
}

function Resolve-QOTRailIconHostChild {
    param(
        [AllowNull()]$Host,
        [AllowNull()]$Element
    )

    if (-not $Host -or -not $Element) { return $null }

    $current = $Element
    while ($current) {
        try {
            if ($current -is [System.Windows.FrameworkElement]) {
                $currentName = Get-QOTRailHostChildKey -Child $current
                if (-not [string]::IsNullOrWhiteSpace($currentName)) {
                    $parent = $null
                    try { $parent = [System.Windows.LogicalTreeHelper]::GetParent($current) } catch { $parent = $null }
                    if ($parent -eq $Host) {
                        return $current
                    }
                }
            }
        } catch { }

        $parentNode = $null
        try {
            if ($current -is [System.Windows.Media.Visual] -or $current -is [System.Windows.Media.Media3D.Visual3D]) {
                $parentNode = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
            }
        } catch { $parentNode = $null }
        if (-not $parentNode) {
            try { $parentNode = [System.Windows.LogicalTreeHelper]::GetParent($current) } catch { $parentNode = $null }
        }
        $current = $parentNode
    }

    return $null
}

function Update-QOTRailIconHostLayout {
    param([AllowNull()]$Host)

    if (-not $Host) { return }

    try { $Host.InvalidateMeasure() } catch { }
    try { $Host.InvalidateArrange() } catch { }
    try { $Host.UpdateLayout() } catch { }

    $parent = $null
    try { $parent = [System.Windows.LogicalTreeHelper]::GetParent($Host) } catch { $parent = $null }
    if (-not $parent) {
        try { $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($Host) } catch { $parent = $null }
    }

    try { if ($parent) { $parent.InvalidateMeasure() } } catch { }
    try { if ($parent) { $parent.InvalidateArrange() } } catch { }
    try { if ($parent) { $parent.UpdateLayout() } } catch { }
}

function Get-QOTRailDragTargetAtPoint {
    param(
        [AllowNull()]$Host,
        [Parameter(Mandatory)][string]$SourceName,
        [Parameter(Mandatory)][System.Windows.Point]$Point
    )

    if (-not $Host) { return $null }

    $entries = @()
    $sourceTop = $null
    $sourceBottom = $null

    foreach ($child in @($Host.Children)) {
        if (-not ($child -is [System.Windows.FrameworkElement])) { continue }
        $name = Get-QOTRailHostChildKey -Child $child
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $origin = $null
        try { $origin = $child.TranslatePoint((New-Object System.Windows.Point(0, 0)), $Host) } catch { $origin = $null }
        if (-not $origin) { continue }

        $height = 0.0
        try { $height = [double]$child.ActualHeight } catch { $height = 0.0 }
        if ($height -le 0) { continue }

        $top = [double]$origin.Y
        $bottom = $top + $height
        $mid = $top + ($height / 2.0)

        if ($name -eq $SourceName) {
            $sourceTop = $top
            $sourceBottom = $bottom
            continue
        }

        $entries += [pscustomobject]@{
            Name = $name
            Top = $top
            Mid = $mid
            Bottom = $bottom
        }
    }

    if ($null -ne $sourceTop -and $null -ne $sourceBottom) {
        if ($Point.Y -ge $sourceTop -and $Point.Y -le $sourceBottom) {
            return $null
        }
    }

    foreach ($entry in $entries) {
        if ($Point.Y -lt $entry.Mid) {
            return [pscustomobject]@{
                TargetName = [string]$entry.Name
                Placement = "Before"
            }
        }
    }

    if ($entries.Count -gt 0) {
        return [pscustomobject]@{
            TargetName = [string]$entries[-1].Name
            Placement = "After"
        }
    }

    return $null
}

function Invoke-QOTRailIconMoveOnHost {
    param(
        [AllowNull()]$Host,
        [Parameter(Mandatory)][string]$SourceName,
        [Parameter(Mandatory)][ValidateSet("Top","Up","Down","Bottom")][string]$Direction
    )

    if (-not $Host) { return @() }

    $currentOrder = @(Get-QOTRailIconCurrentOrder -Host $Host)
    if ($currentOrder.Count -eq 0 -or -not ($currentOrder -contains $SourceName)) {
        return @($currentOrder)
    }

    $currentIndex = [array]::IndexOf($currentOrder, $SourceName)
    if ($currentIndex -lt 0) { return @($currentOrder) }

    $desiredOrder = @($currentOrder)
    switch ($Direction) {
        "Top" {
            if ($currentIndex -le 0) { return @($currentOrder) }
            $targetName = [string]$desiredOrder[0]
            $desiredOrder = @(Move-QOTRailIconOrder -Order $desiredOrder -SourceName $SourceName -TargetName $targetName -Placement "Before")
        }
        "Up" {
            if ($currentIndex -le 0) { return @($currentOrder) }
            $targetName = [string]$desiredOrder[$currentIndex - 1]
            $desiredOrder = @(Move-QOTRailIconOrder -Order $desiredOrder -SourceName $SourceName -TargetName $targetName -Placement "Before")
        }
        "Down" {
            if ($currentIndex -ge ($desiredOrder.Count - 1)) { return @($currentOrder) }
            $targetName = [string]$desiredOrder[$currentIndex + 1]
            $desiredOrder = @(Move-QOTRailIconOrder -Order $desiredOrder -SourceName $SourceName -TargetName $targetName -Placement "After")
        }
        "Bottom" {
            if ($currentIndex -ge ($desiredOrder.Count - 1)) { return @($currentOrder) }
            $desiredOrder = @(Move-QOTRailIconOrder -Order $desiredOrder -SourceName $SourceName -Placement "End")
        }
    }

    $appliedOrder = @(Apply-QOTRailIconOrder -Host $Host -Order $desiredOrder)
    Save-QOTRailIconOrder -Order $appliedOrder
    Update-QOTRailIconHostLayout -Host $Host
    return @($appliedOrder)
}

function Find-QOTTabByName {
    param(
        [AllowNull()]$Tabs,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Tabs) { return $null }
    foreach ($item in @($Tabs.Items)) {
        if (-not $item -or -not ($item -is [System.Windows.Controls.TabItem])) { continue }
        $itemName = ""
        try { $itemName = [string]$item.Name } catch { $itemName = "" }
        if ($itemName -eq $Name) { return $item }
    }
    return $null
}

function Set-QOTRailButtonActiveState {
    param(
        [AllowNull()]$Button,
        [bool]$IsActive
    )

    if (-not $Button) { return }
    try {
        $Button.Tag = $(if ($IsActive) { "Active" } else { "Inactive" })
    } catch { }
}

function Sync-QOTRailNavigationState {
    param(
        [AllowNull()]$Tabs,
        [hashtable]$ButtonsByTabName,
        [AllowNull()]$HelpButton,
        [AllowNull()]$SettingsButton,
        [AllowNull()]$HelpTab,
        [AllowNull()]$SettingsTab
    )

    if (-not $Tabs) { return }

    $selectedTab = $null
    try { $selectedTab = $Tabs.SelectedItem } catch { $selectedTab = $null }

    foreach ($entry in $ButtonsByTabName.GetEnumerator()) {
        $tab = Find-QOTTabByName -Tabs $Tabs -Name ([string]$entry.Key)
        $button = $entry.Value
        if (-not $button) { continue }

        $isVisible = $false
        if ($tab) {
            try { $isVisible = ($tab.Visibility -eq [System.Windows.Visibility]::Visible) } catch { $isVisible = $false }
        }

        try {
            $button.Visibility = $(if ($isVisible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed })
        } catch { }

        Set-QOTRailButtonActiveState -Button $button -IsActive ($isVisible -and $selectedTab -eq $tab)
    }

    Set-QOTRailButtonActiveState -Button $HelpButton -IsActive ($selectedTab -eq $HelpTab)
    Set-QOTRailButtonActiveState -Button $SettingsButton -IsActive ($selectedTab -eq $SettingsTab)
}

function Register-QOTRailIconReordering {
    param([AllowNull()]$Host)

    if (-not ($Host -is [System.Windows.Controls.Panel])) { return }

    $dragDataFormat = "QuinnOptimiserToolkit.RailIcon"
    $getRailIconCurrentOrderCmd = ${function:Get-QOTRailIconCurrentOrder}
    $moveRailIconOrderCmd = ${function:Move-QOTRailIconOrder}
    $applyRailIconOrderCmd = ${function:Apply-QOTRailIconOrder}
    $resolveRailIconHostChildCmd = ${function:Resolve-QOTRailIconHostChild}
    $getRailDragTargetAtPointCmd = ${function:Get-QOTRailDragTargetAtPoint}
    $updateRailIconHostLayoutCmd = ${function:Update-QOTRailIconHostLayout}
    $saveRailIconOrderCmd = ${function:Save-QOTRailIconOrder}
    $getRailHostChildKeyCmd = ${function:Get-QOTRailHostChildKey}

    $clearDragState = {
        try {
            if ($script:QOT_RailDragSource -is [System.Windows.FrameworkElement]) {
                try { $script:QOT_RailDragSource.Opacity = 1.0 } catch { }
                try { $script:QOT_RailDragSource.RenderTransform = $null } catch { }
                try { [System.Windows.Controls.Panel]::SetZIndex($script:QOT_RailDragSource, 0) } catch { }
                try { $script:QOT_RailDragSource.ReleaseMouseCapture() } catch { }
            }
        } catch { }
        $script:QOT_RailDragSource = $null
        $script:QOT_RailDragStartPoint = $null
        $script:QOT_RailIsDragging = $false
    }.GetNewClosure()

    $applyDragReorder = {
        param(
            [Parameter(Mandatory)][string]$SourceName,
            [Parameter(Mandatory)][string]$TargetName,
            [Parameter(Mandatory)][ValidateSet("Before","After")][string]$Placement
        )

        $currentOrder = @()
        if ($getRailIconCurrentOrderCmd) {
            $currentOrder = @(& $getRailIconCurrentOrderCmd -Host $Host)
        }
        if ($currentOrder.Count -eq 0 -or -not ($currentOrder -contains $SourceName) -or -not ($currentOrder -contains $TargetName)) {
            return $false
        }

        $finalOrder = @()
        if ($moveRailIconOrderCmd) {
            $finalOrder = @(& $moveRailIconOrderCmd -Order $currentOrder -SourceName $SourceName -TargetName $TargetName -Placement $Placement)
        }
        if (($finalOrder -join ",") -eq ($currentOrder -join ",")) { return $false }

        $appliedOrder = @()
        if ($applyRailIconOrderCmd) {
            $appliedOrder = @(& $applyRailIconOrderCmd -Host $Host -Order $finalOrder)
        }
        if ($saveRailIconOrderCmd) {
            try { & $saveRailIconOrderCmd -Order $appliedOrder } catch { }
        }
        if ($updateRailIconHostLayoutCmd) {
            try { & $updateRailIconHostLayoutCmd -Host $Host } catch { }
        }
        return $true
    }.GetNewClosure()

    try { $Host.AllowDrop = $true } catch { }

    foreach ($child in @($Host.Children)) {
        if (-not ($child -is [System.Windows.FrameworkElement])) { continue }

        $sourceChild = $child
        $actionControl = $child
        if ($child -is [System.Windows.Controls.Border] -and $child.Child -is [System.Windows.FrameworkElement]) {
            $actionControl = $child.Child
        }
        $dragSurfaces = @($sourceChild)
        if ($actionControl -and $actionControl -ne $sourceChild) {
            $dragSurfaces += $actionControl
        }

        try { $child.AllowDrop = $true } catch { }
        try { $child.Cursor = [System.Windows.Input.Cursors]::Hand } catch { }
        try { if ($actionControl) { $actionControl.Cursor = [System.Windows.Input.Cursors]::Hand } } catch { }

        foreach ($dragSurface in @($dragSurfaces)) {
            if (-not ($dragSurface -is [System.Windows.FrameworkElement])) { continue }

            $dragSurface.Add_PreviewMouseLeftButtonDown({
                param($sender, $args)
                & $clearDragState
                $script:QOT_RailDragSource = $sourceChild
                try { $script:QOT_RailDragStartPoint = $args.GetPosition($Host) } catch { $script:QOT_RailDragStartPoint = $null }
                $script:QOT_RailIsDragging = $false
            }.GetNewClosure())

            $dragSurface.Add_PreviewMouseMove({
                param($sender, $args)
                if ($args.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
                if ($script:QOT_RailDragSource -ne $sourceChild) { return }

                $sourceName = ""
                if ($getRailHostChildKeyCmd) {
                    try { $sourceName = [string](& $getRailHostChildKeyCmd -Child $sourceChild) } catch { $sourceName = "" }
                }
                if ([string]::IsNullOrWhiteSpace($sourceName) -or -not $script:QOT_RailDragStartPoint) { return }

                $currentPoint = $null
                try { $currentPoint = $args.GetPosition($Host) } catch { $currentPoint = $null }
                if (-not $currentPoint) { return }

                $deltaX = [math]::Abs($currentPoint.X - $script:QOT_RailDragStartPoint.X)
                $deltaY = [math]::Abs($currentPoint.Y - $script:QOT_RailDragStartPoint.Y)
                if ($deltaX -lt [SystemParameters]::MinimumHorizontalDragDistance -and $deltaY -lt [SystemParameters]::MinimumVerticalDragDistance) {
                    return
                }

                $script:QOT_RailIsDragging = $true
                try { $sourceChild.Opacity = 0.55 } catch { }
                try { [System.Windows.Controls.Panel]::SetZIndex($sourceChild, 20) } catch { }

                $dragData = [System.Windows.DataObject]::new()
                try { $dragData.SetData($dragDataFormat, $sourceName) } catch { }

                try {
                    try { $args.Handled = $true } catch { }
                    $null = [System.Windows.DragDrop]::DoDragDrop(
                        $sourceChild,
                        $dragData,
                        [System.Windows.DragDropEffects]::Move
                    )
                }
                finally {
                    & $clearDragState
                }
            }.GetNewClosure())

            $dragSurface.Add_PreviewMouseLeftButtonUp({
                param($sender, $args)
                if ($script:QOT_RailDragSource -eq $sourceChild -and $script:QOT_RailIsDragging) {
                    try { $args.Handled = $true } catch { }
                }
                if ($script:QOT_RailDragSource -eq $sourceChild) {
                    & $clearDragState
                }
            }.GetNewClosure())
        }

        $child.Add_DragOver({
            param($sender, $args)
            $sourceName = ""
            try {
                if ($args.Data.GetDataPresent($dragDataFormat)) {
                    $sourceName = [string]$args.Data.GetData($dragDataFormat)
                }
            } catch { $sourceName = "" }

            $targetName = ""
            if ($getRailHostChildKeyCmd) {
                try { $targetName = [string](& $getRailHostChildKeyCmd -Child $sourceChild) } catch { $targetName = "" }
            }

            try {
                $args.Effects = $(if ((-not [string]::IsNullOrWhiteSpace($sourceName)) -and $sourceName -ne $targetName) { [System.Windows.DragDropEffects]::Move } else { [System.Windows.DragDropEffects]::None })
            } catch { }
            try { $args.Handled = $true } catch { }
        }.GetNewClosure())

        $child.Add_Drop({
            param($sender, $args)
            $sourceName = ""
            try {
                if ($args.Data.GetDataPresent($dragDataFormat)) {
                    $sourceName = [string]$args.Data.GetData($dragDataFormat)
                }
            } catch { $sourceName = "" }

            $targetName = ""
            if ($getRailHostChildKeyCmd) {
                try { $targetName = [string](& $getRailHostChildKeyCmd -Child $sourceChild) } catch { $targetName = "" }
            }

            if (-not [string]::IsNullOrWhiteSpace($sourceName) -and -not [string]::IsNullOrWhiteSpace($targetName) -and $sourceName -ne $targetName) {
                $dropPoint = $null
                try { $dropPoint = $args.GetPosition($sourceChild) } catch { $dropPoint = $null }
                $placement = "Before"
                if ($dropPoint) {
                    $targetHeight = 0.0
                    try { $targetHeight = [double]$sourceChild.ActualHeight } catch { $targetHeight = 0.0 }
                    if ($targetHeight -gt 0 -and $dropPoint.Y -ge ($targetHeight / 2.0)) {
                        $placement = "After"
                    }
                }
                $null = & $applyDragReorder -SourceName $sourceName -TargetName $targetName -Placement $placement
            }

            & $clearDragState
            try { $args.Handled = $true } catch { }
        }.GetNewClosure())
    }

    $Host.Add_DragOver({
        param($sender, $args)
        $sourceName = ""
        try {
            if ($args.Data.GetDataPresent($dragDataFormat)) {
                $sourceName = [string]$args.Data.GetData($dragDataFormat)
            }
        } catch { $sourceName = "" }

        try {
            $args.Effects = $(if (-not [string]::IsNullOrWhiteSpace($sourceName)) { [System.Windows.DragDropEffects]::Move } else { [System.Windows.DragDropEffects]::None })
        } catch { }
        try { $args.Handled = $true } catch { }
    }.GetNewClosure())

    $Host.Add_Drop({
        param($sender, $args)
        $sourceName = ""
        try {
            if ($args.Data.GetDataPresent($dragDataFormat)) {
                $sourceName = [string]$args.Data.GetData($dragDataFormat)
            }
        } catch { $sourceName = "" }

        if (-not [string]::IsNullOrWhiteSpace($sourceName)) {
            $currentOrder = @()
            if ($getRailIconCurrentOrderCmd) {
                $currentOrder = @(& $getRailIconCurrentOrderCmd -Host $Host)
            }
            if ($currentOrder.Count -gt 0 -and $currentOrder[-1] -ne $sourceName) {
                $finalOrder = @()
                if ($moveRailIconOrderCmd) {
                    $finalOrder = @(& $moveRailIconOrderCmd -Order $currentOrder -SourceName $sourceName -Placement "End")
                }
                if ($applyRailIconOrderCmd) {
                    $appliedOrder = @(& $applyRailIconOrderCmd -Host $Host -Order $finalOrder)
                    try { & $saveRailIconOrderCmd -Order $appliedOrder } catch { }
                    try { & $updateRailIconHostLayoutCmd -Host $Host } catch { }
                }
            }
        }

        & $clearDragState
        try { $args.Handled = $true } catch { }
    }.GetNewClosure())
}

function Set-QOTTicketsRailSubmenuState {
    param(
        [AllowNull()]$Submenu,
        [AllowNull()]$TicketsButton,
        [AllowNull()]$Container,
        [bool]$IsOpen
    )

    if (-not $Submenu) { return }

    if (-not $IsOpen) {
        try { $Submenu.Visibility = [System.Windows.Visibility]::Collapsed } catch { }
        return
    }

    try {
        if ($TicketsButton -and $Container) {
            $origin = $TicketsButton.TranslatePoint((New-Object System.Windows.Point(0, 0)), $Container)
            $top = [Math]::Round($origin.Y + $TicketsButton.ActualHeight + 4)
            $Submenu.Margin = New-Object System.Windows.Thickness(0, $top, 0, 0)
        }
    } catch { }

    try { $Submenu.Visibility = [System.Windows.Visibility]::Visible } catch { }
}

function Set-QOTProcessTaskbarIdentity {
    param(
        [Parameter(Mandatory = $false)]
        [string]$AppUserModelId = ""
    )

    if ([string]::IsNullOrWhiteSpace($AppUserModelId)) {
        $AppUserModelId = [Environment]::GetEnvironmentVariable("QOT_APP_USER_MODEL_ID", "Process")
    }
    if ([string]::IsNullOrWhiteSpace($AppUserModelId)) {
        $AppUserModelId = "StudioVoly.QuinnOptimiserToolkit"
    }

    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class QOTShellAppIdMain {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
}
"@ -ErrorAction SilentlyContinue | Out-Null

        [void][QOTShellAppIdMain]::SetCurrentProcessExplicitAppUserModelID($AppUserModelId)
        Write-QOTStartupTrace ("Applied process AppUserModelID: {0}" -f $AppUserModelId) "INFO"
    }
    catch {
        Write-QOTStartupTrace ("Failed setting process AppUserModelID: {0}" -f $_.Exception.Message) "WARN"
    }
}

function Set-QOTWindowIconFromFile {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    try {
        $iconPath = Join-Path $PSScriptRoot "QOT.ico"
        if (-not (Test-Path -LiteralPath $iconPath)) {
            Write-QOTStartupTrace ("MainWindow icon file not found: {0}" -f $iconPath) "WARN"
            return
        }

        $iconUri = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
        $iconFrame = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconUri)
        if ($iconFrame) {
            $Window.Icon = $iconFrame
            Write-QOTStartupTrace ("MainWindow icon applied from: {0}" -f $iconPath) "INFO"
        }
    }
    catch {
        Write-QOTStartupTrace ("Failed applying MainWindow icon: {0}" -f $_.Exception.Message) "WARN"
    }

    try {
        $headerLogoPath = Join-Path $PSScriptRoot "QOT-header-icon.png"
        if (-not (Test-Path -LiteralPath $headerLogoPath)) {
            Write-QOTStartupTrace ("Header logo file not found: {0}" -f $headerLogoPath) "WARN"
            return
        }

        $headerLogo = $Window.FindName("WindowTitleIcon")
        if (-not ($headerLogo -is [System.Windows.Controls.Image])) {
            Write-QOTStartupTrace "Header logo control was not found." "WARN"
            return
        }

        $logoUri = [System.Uri]::new($headerLogoPath, [System.UriKind]::Absolute)
        $logoBitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
        $logoBitmap.BeginInit()
        $logoBitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $logoBitmap.UriSource = $logoUri
        $logoBitmap.EndInit()
        $logoBitmap.Freeze()

        $headerLogo.Source = $logoBitmap
        Write-QOTStartupTrace ("Header logo applied from: {0}" -f $headerLogoPath) "INFO"
    }
    catch {
        Write-QOTStartupTrace ("Failed applying header logo: {0}" -f $_.Exception.Message) "WARN"
    }
}

function Initialize-QOTTaskbarIdentity {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    if (-not $Window) { return }

    try {
        Set-QOTProcessTaskbarIdentity
        Set-QOTWindowIconFromFile -Window $Window
        $script:QOTTaskbarIdentityApplied = $true
    }
    catch {
        Write-QOTStartupTrace ("Initialize taskbar identity failed: {0}" -f $_.Exception.Message) "WARN"
    }
}

function Apply-QOTMainTabVisibilityFromSettings {
    param([AllowNull()]$Tabs)

    if (-not $Tabs) { return }
    if (-not (Get-Command Get-QOTabVisibilitySettings -ErrorAction SilentlyContinue)) { return }

    $showCleaning = $true
    $showApps = $true
    $showAdvanced = $true
    $showTickets = $true

    try {
        $tabVisibility = Get-QOTabVisibilitySettings
        if ($tabVisibility) {
            $showCleaning = [bool]$tabVisibility.Cleaning
            $showApps = [bool]$tabVisibility.Apps
            $showAdvanced = [bool]$tabVisibility.Advanced
            $showTickets = [bool]$tabVisibility.Tickets
        }
    } catch { }

    if (-not ($showCleaning -or $showApps -or $showAdvanced -or $showTickets)) {
        $showTickets = $true
    }

    $desiredVisibilityByName = @{
        TabCleaning = $showCleaning
        TabApps     = $showApps
        TabAdvanced = $showAdvanced
        TabTickets  = $showTickets
    }

    $firstVisibleTab = $null
    foreach ($tabName in @("TabCleaning", "TabApps", "TabAdvanced", "TabTickets")) {
        if (-not $desiredVisibilityByName.ContainsKey($tabName)) { continue }
        $tab = Find-QOTTabByName -Tabs $Tabs -Name $tabName
        if (-not $tab) { continue }

        if ([bool]$desiredVisibilityByName[$tabName]) {
            $tab.Visibility = [System.Windows.Visibility]::Visible
            if (-not $firstVisibleTab) { $firstVisibleTab = $tab }
        }
        else {
            $tab.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }

    if (-not $firstVisibleTab) {
        $ticketsTab = Find-QOTTabByName -Tabs $Tabs -Name "TabTickets"
        if ($ticketsTab) {
            $ticketsTab.Visibility = [System.Windows.Visibility]::Visible
            $firstVisibleTab = $ticketsTab
            try {
                if (Get-Command Set-QOTabVisibilitySettings -ErrorAction SilentlyContinue) {
                    Set-QOTabVisibilitySettings -Cleaning $showCleaning -Apps $showApps -Advanced $showAdvanced -Tickets $true | Out-Null
                }
            } catch { }
        }
    }

    $selectedTab = $null
    try { $selectedTab = $Tabs.SelectedItem } catch { $selectedTab = $null }
    if ($selectedTab -and $selectedTab -is [System.Windows.Controls.TabItem]) {
        if ($selectedTab.Visibility -eq [System.Windows.Visibility]::Visible) { return }
    }

    if ($firstVisibleTab) {
        try { $Tabs.SelectedItem = $firstVisibleTab } catch { }
    }
}

function Write-QOTStartupTrace {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )

    $line = "[STARTUP] $Message"

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $line $Level
            return
        }
    } catch { }

    try {
        $fallbackDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"
        New-Item -ItemType Directory -Path $fallbackDir -Force -ErrorAction Stop | Out-Null
        $fallbackPath = Join-Path $fallbackDir "MainWindow.Startup.log"
        Add-Content -LiteralPath $fallbackPath -Value ("[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $line) -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Write-QOTRuntimeLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $Message $Level
            return
        }
    } catch { }

    try {
        $fallbackDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"
        New-Item -ItemType Directory -Path $fallbackDir -Force -ErrorAction Stop | Out-Null
        $fallbackPath = Join-Path $fallbackDir "MainWindow.Runtime.log"
        Add-Content -LiteralPath $fallbackPath -Value ("[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message) -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Write-QOTRuntimeLogSafe {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )

    try {
        $runtimeLogger = @(Get-Command Write-QOTRuntimeLog -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($runtimeLogger -is [System.Array]) {
            $runtimeLogger = if ($runtimeLogger.Count -gt 0) { $runtimeLogger[0] } else { $null }
        }
        if ($runtimeLogger) {
            & $runtimeLogger -Message $Message -Level $Level
            return
        }
    } catch { }

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $Message $Level
            return
        }
    } catch { }

    try {
        $fallbackDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"
        New-Item -ItemType Directory -Path $fallbackDir -Force -ErrorAction Stop | Out-Null
        $fallbackPath = Join-Path $fallbackDir "MainWindow.Runtime.log"
        Add-Content -LiteralPath $fallbackPath -Value ("[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message) -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Get-QOTGlobalTaskTimeoutSeconds {
    $defaultSeconds = 1800
    $resolvedSeconds = $defaultSeconds
    $rawValue = $null

    try {
        if (Get-Command Get-QOSettings -ErrorAction SilentlyContinue) {
            $settings = Get-QOSettings
            if ($settings -and ($settings.PSObject.Properties.Name -contains "TaskTimeoutSeconds")) {
                $rawValue = $settings.TaskTimeoutSeconds
            }
        }
    } catch { }

    if ($null -eq $rawValue) {
        try {
            $envValue = [string]$env:QOT_TASK_TIMEOUT_SECONDS
            if (-not [string]::IsNullOrWhiteSpace($envValue)) {
                $rawValue = $envValue
            }
        } catch { }
    }

    try {
        if ($null -ne $rawValue) {
            $candidate = [int]$rawValue
            if ($candidate -gt 0) {
                $resolvedSeconds = $candidate
            }
        }
    } catch { }

    if ($resolvedSeconds -lt 300) { $resolvedSeconds = 300 }
    if ($resolvedSeconds -gt 43200) { $resolvedSeconds = 43200 }
    return [int]$resolvedSeconds
}

function Invoke-QOTCallbackSafely {
    param(
        [AllowNull()]$Callback,
        [object[]]$ArgumentList = @()
    )

    $target = $Callback
    if ($target -is [System.Array]) {
        $target = @($target | Where-Object {
            $_ -is [scriptblock] -or $_ -is [System.Management.Automation.CommandInfo] -or $_ -is [string]
        } | Select-Object -First 1)
        if ($target -is [System.Array]) {
            $target = if ($target.Count -gt 0) { $target[0] } else { $null }
        }
    }

    if ($target -is [System.Management.Automation.CommandInfo]) {
        return & $target @ArgumentList
    }
    if ($target -is [scriptblock]) {
        return & $target @ArgumentList
    }
    if ($target -is [string] -and -not [string]::IsNullOrWhiteSpace($target)) {
        $resolved = @(Get-Command -Name $target -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($resolved -is [System.Array]) {
            $resolved = if ($resolved.Count -gt 0) { $resolved[0] } else { $null }
        }
        if ($resolved) {
            return & $resolved @ArgumentList
        }
    }

    throw "Callback is not invokable."
}

try {
    Set-Item -Path Function:\global\Write-QOTRuntimeLog -Value ${function:Write-QOTRuntimeLog} -Force -ErrorAction SilentlyContinue
} catch { }
try {
    Set-Item -Path Function:\global\Write-QOTRuntimeLogSafe -Value ${function:Write-QOTRuntimeLogSafe} -Force -ErrorAction SilentlyContinue
} catch { }
try {
    Set-Item -Path Function:\global\Write-QOTStartupTrace -Value ${function:Write-QOTStartupTrace} -Force -ErrorAction SilentlyContinue
} catch { }
try {
    Set-Item -Path Function:\global\Resolve-QOTInvokableCommand -Value ${function:Resolve-QOTInvokableCommand} -Force -ErrorAction SilentlyContinue
} catch { }

function Convert-QOTTaskStatusToFriendlyLabel {
    param([AllowNull()][string]$Status)

    switch (([string]($Status + "")).Trim().ToUpperInvariant()) {
        "SUCCESS" { return "Worked" }
        "SKIPPED" { return "Skipped" }
        default   { return "Failed" }
    }
}

function New-QOTBrushFromHex {
    param(
        [Parameter(Mandatory)][string]$Hex,
        [AllowNull()]$Fallback = $null
    )

    try {
        return [System.Windows.Media.Brush]([System.Windows.Media.BrushConverter]::new().ConvertFromString($Hex))
    }
    catch {
        if ($Fallback -is [System.Windows.Media.Brush]) {
            return $Fallback
        }
        if ($null -ne $Fallback) {
            try {
                return [System.Windows.Media.Brush]([System.Windows.Media.BrushConverter]::new().ConvertFrom($Fallback))
            } catch { }
        }
        return $Fallback
    }
}

function Update-QOTTaskLogsButtonState {
    $btn = $script:QOT_LogsButton
    if (-not $btn) { return }

    $worked = 0
    $skipped = 0
    $failed = 0
    $selectedCount = 0
    $lastRunAt = $null

    try { $worked = [int]$script:QOT_TaskRunSummary.Worked } catch { $worked = 0 }
    try { $skipped = [int]$script:QOT_TaskRunSummary.Skipped } catch { $skipped = 0 }
    try { $failed = [int]$script:QOT_TaskRunSummary.Failed } catch { $failed = 0 }
    try { $selectedCount = [int]$script:QOT_TaskRunSummary.SelectedCount } catch { $selectedCount = 0 }
    try { $lastRunAt = $script:QOT_TaskRunSummary.LastRunAt } catch { $lastRunAt = $null }

    $tooltip = "Task results: no runs yet."
    if ($lastRunAt) {
        $tooltip = ("Last run ({0}): Worked {1}, Skipped {2}, Failed {3} of {4} task(s)." -f ([datetime]$lastRunAt).ToString("g"), $worked, $skipped, $failed, $selectedCount)
    }
    $btn.ToolTip = $tooltip
    try { $btn.IsEnabled = $true } catch { }
    try { $btn.IsHitTestVisible = $true } catch { }

    $defaultBrush = New-QOTBrushFromHex -Hex "#9CA3AF" -Fallback $btn.Foreground
    $goodBrush = New-QOTBrushFromHex -Hex "#34D399" -Fallback $defaultBrush
    $warnBrush = New-QOTBrushFromHex -Hex "#F59E0B" -Fallback $defaultBrush
    $badBrush = New-QOTBrushFromHex -Hex "#F87171" -Fallback $defaultBrush

    if ($failed -gt 0) {
        $btn.Foreground = $badBrush
    }
    elseif ($skipped -gt 0) {
        $btn.Foreground = $warnBrush
    }
    elseif ($worked -gt 0) {
        $btn.Foreground = $goodBrush
    }
    else {
        $btn.Foreground = $defaultBrush
    }
}

function Update-QOTTaskResultsWindowLiveState {
    $window = $script:QOT_TaskResultsWindow
    if (-not $window) { return }

    $updateUi = {
        $summaryText = $script:QOT_TaskResultsSummaryText
        if ($summaryText) {
            $worked = 0; $skipped = 0; $failed = 0; $selected = 0; $lastRunAt = $null
            try { $worked = [int]$script:QOT_TaskRunSummary.Worked } catch { }
            try { $skipped = [int]$script:QOT_TaskRunSummary.Skipped } catch { }
            try { $failed = [int]$script:QOT_TaskRunSummary.Failed } catch { }
            try { $selected = [int]$script:QOT_TaskRunSummary.SelectedCount } catch { }
            try { $lastRunAt = $script:QOT_TaskRunSummary.LastRunAt } catch { }

            if ($lastRunAt) {
                $summaryText.Text = ("Last run {0} | Worked: {1} | Skipped: {2} | Failed: {3} | Total selected: {4}" -f ([datetime]$lastRunAt).ToString("g"), $worked, $skipped, $failed, $selected)
            } else {
                $summaryText.Text = "No task run recorded yet. Select actions and press Play."
            }
        }

        $grid = $script:QOT_TaskResultsGrid
        if ($grid) {
            if ($script:QOT_TaskRunEntries -and $script:QOT_TaskRunEntries.Count -gt 0) {
                if ($grid.ItemsSource -ne $script:QOT_TaskRunEntries) {
                    $grid.ItemsSource = $script:QOT_TaskRunEntries
                }
            } else {
                if (-not $script:QOT_TaskResultsPlaceholderEntries) {
                    $script:QOT_TaskResultsPlaceholderEntries = New-Object System.Collections.ObjectModel.ObservableCollection[object]
                    $script:QOT_TaskResultsPlaceholderEntries.Add([pscustomobject]@{
                        Time   = "-"
                        Task   = "No tasks have been run yet"
                        Result = "-"
                        Detail = "Run selected actions with Play to see easy-to-read results here."
                    }) | Out-Null
                }
                if ($grid.ItemsSource -ne $script:QOT_TaskResultsPlaceholderEntries) {
                    $grid.ItemsSource = $script:QOT_TaskResultsPlaceholderEntries
                }
            }
            try { $grid.Items.Refresh() } catch { }
        }
    }.GetNewClosure()

    try {
        if ($window.Dispatcher -and (-not $window.Dispatcher.CheckAccess())) {
            $window.Dispatcher.Invoke([action]{ & $updateUi }) | Out-Null
        } else {
            & $updateUi
        }
    } catch { }
}

function Save-QOTTaskRunState {
    try {
        if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) { return }
        if (-not (Get-Command Save-QOSettings -ErrorAction SilentlyContinue)) { return }

        $settings = Get-QOSettings
        if (-not $settings) { return }

        if ($settings.PSObject.Properties.Name -notcontains "UiState") {
            $settings | Add-Member -NotePropertyName UiState -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        $lastRunAtValue = $null
        try { $lastRunAtValue = $script:QOT_TaskRunSummary.LastRunAt } catch { $lastRunAtValue = $null }
        $lastRunAtStamp = $null
        if ($lastRunAtValue) {
            try { $lastRunAtStamp = ([datetime]$lastRunAtValue).ToString("o") } catch { $lastRunAtStamp = [string]$lastRunAtValue }
        }

        $summary = [pscustomobject]@{
            SelectedCount = [int]($script:QOT_TaskRunSummary.SelectedCount)
            Worked        = [int]($script:QOT_TaskRunSummary.Worked)
            Skipped       = [int]($script:QOT_TaskRunSummary.Skipped)
            Failed        = [int]($script:QOT_TaskRunSummary.Failed)
            LastRunAt     = $lastRunAtStamp
        }

        $entriesToPersist = @()
        if ($script:QOT_TaskRunEntries) {
            foreach ($entry in @($script:QOT_TaskRunEntries | Select-Object -First 200)) {
                if (-not $entry) { continue }
                $entriesToPersist += [pscustomobject]@{
                    Time   = [string]$entry.Time
                    Task   = [string]$entry.Task
                    Result = [string]$entry.Result
                    Detail = [string]$entry.Detail
                }
            }
        }

        if ($settings.UiState.PSObject.Properties.Name -notcontains "LastTaskRunSummary") {
            $settings.UiState | Add-Member -NotePropertyName LastTaskRunSummary -NotePropertyValue $summary -Force
        } else {
            $settings.UiState.LastTaskRunSummary = $summary
        }

        if ($settings.UiState.PSObject.Properties.Name -notcontains "LastTaskRunEntries") {
            $settings.UiState | Add-Member -NotePropertyName LastTaskRunEntries -NotePropertyValue @($entriesToPersist) -Force
        } else {
            $settings.UiState.LastTaskRunEntries = @($entriesToPersist)
        }

        Save-QOSettings -Settings $settings
    } catch { }
}

function Restore-QOTTaskRunState {
    try {
        if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) { return }
        $settings = Get-QOSettings
        if (-not $settings) { return }
        if ($settings.PSObject.Properties.Name -notcontains "UiState") { return }

        $savedSummary = $null
        $savedEntries = @()
        try {
            if ($settings.UiState.PSObject.Properties.Name -contains "LastTaskRunSummary") {
                $savedSummary = $settings.UiState.LastTaskRunSummary
            }
        } catch { $savedSummary = $null }
        try {
            if ($settings.UiState.PSObject.Properties.Name -contains "LastTaskRunEntries") {
                $savedEntries = @($settings.UiState.LastTaskRunEntries)
            }
        } catch { $savedEntries = @() }

        if (-not $script:QOT_TaskRunEntries) {
            $script:QOT_TaskRunEntries = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        } else {
            try { $script:QOT_TaskRunEntries.Clear() } catch { }
        }

        foreach ($saved in $savedEntries) {
            if (-not $saved) { continue }
            try {
                $script:QOT_TaskRunEntries.Add([pscustomobject]@{
                    Time   = [string]$saved.Time
                    Task   = [string]$saved.Task
                    Result = [string]$saved.Result
                    Detail = [string]$saved.Detail
                }) | Out-Null
            } catch { }
        }

        $selectedCount = 0
        $worked = 0
        $skipped = 0
        $failed = 0
        $lastRunAt = $null
        try { if ($savedSummary -and $savedSummary.PSObject.Properties.Name -contains "SelectedCount") { $selectedCount = [int]$savedSummary.SelectedCount } } catch { }
        try { if ($savedSummary -and $savedSummary.PSObject.Properties.Name -contains "Worked") { $worked = [int]$savedSummary.Worked } } catch { }
        try { if ($savedSummary -and $savedSummary.PSObject.Properties.Name -contains "Skipped") { $skipped = [int]$savedSummary.Skipped } } catch { }
        try { if ($savedSummary -and $savedSummary.PSObject.Properties.Name -contains "Failed") { $failed = [int]$savedSummary.Failed } } catch { }
        try {
            if ($savedSummary -and $savedSummary.PSObject.Properties.Name -contains "LastRunAt") {
                $stamp = [string]$savedSummary.LastRunAt
                if (-not [string]::IsNullOrWhiteSpace($stamp)) {
                    $lastRunAt = [datetime]$stamp
                }
            }
        } catch { $lastRunAt = $null }

        $script:QOT_TaskRunSummary = [ordered]@{
            SelectedCount = $selectedCount
            Worked        = $worked
            Skipped       = $skipped
            Failed        = $failed
            LastRunAt     = $lastRunAt
        }
    } catch { }

    Update-QOTTaskLogsButtonState
    Update-QOTTaskResultsWindowLiveState
}

function Reset-QOTTaskRunLog {
    param([int]$SelectedCount = 0)

    if (-not $script:QOT_TaskRunEntries) {
        $script:QOT_TaskRunEntries = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    } else {
        try { $script:QOT_TaskRunEntries.Clear() } catch { }
    }

    $script:QOT_TaskRunSummary = [ordered]@{
        SelectedCount = [int]$SelectedCount
        Worked = 0
        Skipped = 0
        Failed = 0
        LastRunAt = $null
    }

    Update-QOTTaskLogsButtonState
    Update-QOTTaskResultsWindowLiveState
}

function Add-QOTTaskRunLogEntry {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$Status,
        [AllowNull()][string]$Reason
    )

    if (-not $script:QOT_TaskRunEntries) {
        $script:QOT_TaskRunEntries = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    }

    $friendly = Convert-QOTTaskStatusToFriendlyLabel -Status $Status
    $detail = ""
    if ($friendly -eq "Worked") {
        $detail = "Completed successfully."
    }
    elseif ([string]::IsNullOrWhiteSpace([string]$Reason)) {
        $detail = if ($friendly -eq "Skipped") { "Skipped." } else { "Task failed." }
    }
    else {
        $detail = [string]$Reason
    }

    $entry = [pscustomobject]@{
        Time   = (Get-Date).ToString("g")
        Task   = [string]$TaskName
        Result = $friendly
        Detail = $detail
    }

    try { $script:QOT_TaskRunEntries.Insert(0, $entry) } catch { $script:QOT_TaskRunEntries.Add($entry) | Out-Null }
    Update-QOTTaskResultsWindowLiveState
}

function Complete-QOTTaskRunLog {
    param(
        [int]$SelectedCount,
        [int]$Worked,
        [int]$Skipped,
        [int]$Failed
    )

    $script:QOT_TaskRunSummary = [ordered]@{
        SelectedCount = [int]$SelectedCount
        Worked = [int]$Worked
        Skipped = [int]$Skipped
        Failed = [int]$Failed
        LastRunAt = (Get-Date)
    }

    Save-QOTTaskRunState
    Update-QOTTaskLogsButtonState
    Update-QOTTaskResultsWindowLiveState
}

function Show-QOTTaskResultsWindow {
    param([AllowNull()][System.Windows.Window]$Owner)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null

    try {
        if ($script:QOT_TaskResultsWindow) {
            $existingWindow = $script:QOT_TaskResultsWindow
            $isUsable = $true
            try { $null = $existingWindow.Title } catch { $isUsable = $false }

            if ($isUsable) {
                try {
                    if ($existingWindow.WindowState -eq [System.Windows.WindowState]::Minimized) {
                        $existingWindow.WindowState = [System.Windows.WindowState]::Normal
                    }
                } catch { }
                try {
                    if (-not $existingWindow.IsVisible) {
                        $existingWindow.Show()
                    }
                } catch { }
                # Don't activate - let user continue working
                # try { $existingWindow.Activate() | Out-Null } catch { }
                try {
                    $existingWindow.Topmost = $true
                    $existingWindow.Topmost = $false
                } catch { }
                try {
                    if ($existingWindow.IsVisible) {
                        Update-QOTTaskResultsWindowLiveState
                        return
                    }
                } catch { }
                Update-QOTTaskResultsWindowLiveState
            }
            else {
                $script:QOT_TaskResultsWindow = $null
                $script:QOT_TaskResultsSummaryText = $null
                $script:QOT_TaskResultsGrid = $null
            }
        }
    } catch { }

    $window = New-Object System.Windows.Window
    $window.Title = "Task Results"
    $window.Width = 820
    $window.Height = 520
    $window.MinWidth = 680
    $window.MinHeight = 420
    $window.Background = New-QOTBrushFromHex -Hex "#0F172A" -Fallback [System.Windows.Media.Brushes]::Black
    $window.Foreground = New-QOTBrushFromHex -Hex "#E5E7EB" -Fallback [System.Windows.Media.Brushes]::White
    $window.WindowStartupLocation = if ($Owner) { [System.Windows.WindowStartupLocation]::CenterOwner } else { [System.Windows.WindowStartupLocation]::CenterScreen }
    if ($Owner) {
        try { $window.Owner = $Owner } catch { }
    }

    $root = New-Object System.Windows.Controls.Grid
    $root.Margin = "14"
    $rowSummary = New-Object System.Windows.Controls.RowDefinition
    $rowSummary.Height = [System.Windows.GridLength]::Auto
    $rowGrid = New-Object System.Windows.Controls.RowDefinition
    $rowGrid.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $rowActions = New-Object System.Windows.Controls.RowDefinition
    $rowActions.Height = [System.Windows.GridLength]::Auto
    $root.RowDefinitions.Add($rowSummary)
    $root.RowDefinitions.Add($rowGrid)
    $root.RowDefinitions.Add($rowActions)

    $summaryBorder = New-Object System.Windows.Controls.Border
    $summaryBorder.Background = New-QOTBrushFromHex -Hex "#0B1220" -Fallback [System.Windows.Media.Brushes]::Transparent
    $summaryBorder.BorderBrush = New-QOTBrushFromHex -Hex "#1D4ED8" -Fallback [System.Windows.Media.Brushes]::Gray
    $summaryBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $summaryBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $summaryBorder.Padding = New-Object System.Windows.Thickness(12, 10, 12, 10)
    $summaryBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    [System.Windows.Controls.Grid]::SetRow($summaryBorder, 0)

    $summaryText = New-Object System.Windows.Controls.TextBlock
    $summaryText.FontSize = 14
    $summaryText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $summaryText.TextWrapping = [System.Windows.TextWrapping]::Wrap

    $worked = 0; $skipped = 0; $failed = 0; $selected = 0; $lastRunAt = $null
    try { $worked = [int]$script:QOT_TaskRunSummary.Worked } catch { }
    try { $skipped = [int]$script:QOT_TaskRunSummary.Skipped } catch { }
    try { $failed = [int]$script:QOT_TaskRunSummary.Failed } catch { }
    try { $selected = [int]$script:QOT_TaskRunSummary.SelectedCount } catch { }
    try { $lastRunAt = $script:QOT_TaskRunSummary.LastRunAt } catch { }

    if ($lastRunAt) {
        $summaryText.Text = ("Last run {0} | Worked: {1} | Skipped: {2} | Failed: {3} | Total selected: {4}" -f ([datetime]$lastRunAt).ToString("g"), $worked, $skipped, $failed, $selected)
    }
    else {
        $summaryText.Text = "No task run recorded yet. Select actions and press Play."
    }
    $summaryBorder.Child = $summaryText
    $script:QOT_TaskResultsSummaryText = $summaryText
    $root.Children.Add($summaryBorder) | Out-Null

    $grid = New-Object System.Windows.Controls.DataGrid
    $grid.AutoGenerateColumns = $false
    $grid.IsReadOnly = $true
    $grid.CanUserAddRows = $false
    $grid.CanUserDeleteRows = $false
    $grid.SelectionMode = [System.Windows.Controls.DataGridSelectionMode]::Single
    $grid.HeadersVisibility = [System.Windows.Controls.DataGridHeadersVisibility]::Column
    $grid.BorderBrush = New-QOTBrushFromHex -Hex "#1E3A8A" -Fallback [System.Windows.Media.Brushes]::Gray
    $grid.BorderThickness = New-Object System.Windows.Thickness(1)
    $grid.RowBackground = New-QOTBrushFromHex -Hex "#0B1220" -Fallback [System.Windows.Media.Brushes]::Transparent
    $grid.AlternatingRowBackground = New-QOTBrushFromHex -Hex "#111827" -Fallback [System.Windows.Media.Brushes]::Transparent
    $grid.Foreground = New-QOTBrushFromHex -Hex "#E5E7EB" -Fallback [System.Windows.Media.Brushes]::White
    $grid.Background = New-QOTBrushFromHex -Hex "#020617" -Fallback [System.Windows.Media.Brushes]::Black
    [System.Windows.Controls.Grid]::SetRow($grid, 1)

    $colTime = New-Object System.Windows.Controls.DataGridTextColumn
    $colTime.Header = "Time"
    $colTime.Binding = New-Object System.Windows.Data.Binding("Time")
    $colTime.Width = 145
    $grid.Columns.Add($colTime) | Out-Null

    $colTask = New-Object System.Windows.Controls.DataGridTextColumn
    $colTask.Header = "Task"
    $colTask.Binding = New-Object System.Windows.Data.Binding("Task")
    $colTask.Width = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
    $grid.Columns.Add($colTask) | Out-Null

    $colResult = New-Object System.Windows.Controls.DataGridTextColumn
    $colResult.Header = "Result"
    $colResult.Binding = New-Object System.Windows.Data.Binding("Result")
    $colResult.Width = 120
    $grid.Columns.Add($colResult) | Out-Null

    $colDetail = New-Object System.Windows.Controls.DataGridTextColumn
    $colDetail.Header = "Details"
    $colDetail.Binding = New-Object System.Windows.Data.Binding("Detail")
    $colDetail.Width = New-Object System.Windows.Controls.DataGridLength(1.5, [System.Windows.Controls.DataGridLengthUnitType]::Star)
    $grid.Columns.Add($colDetail) | Out-Null

    if ($script:QOT_TaskRunEntries -and $script:QOT_TaskRunEntries.Count -gt 0) {
        $grid.ItemsSource = $script:QOT_TaskRunEntries
    }
    else {
        if (-not $script:QOT_TaskResultsPlaceholderEntries) {
            $script:QOT_TaskResultsPlaceholderEntries = New-Object System.Collections.ObjectModel.ObservableCollection[object]
            $script:QOT_TaskResultsPlaceholderEntries.Add([pscustomobject]@{
                Time = "-"
                Task = "No tasks have been run yet"
                Result = "-"
                Detail = "Run selected actions with Play to see easy-to-read results here."
            }) | Out-Null
        }
        $grid.ItemsSource = $script:QOT_TaskResultsPlaceholderEntries
    }

    $script:QOT_TaskResultsGrid = $grid
    $root.Children.Add($grid) | Out-Null

    $actions = New-Object System.Windows.Controls.StackPanel
    $actions.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $actions.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $actions.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
    [System.Windows.Controls.Grid]::SetRow($actions, 2)

    $btnOpenFile = New-Object System.Windows.Controls.Button
    $btnOpenFile.Content = "Open Full Log File"
    $btnOpenFile.MinWidth = 130
    $btnOpenFile.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $btnOpenFile.Add_Click({
        try {
            $candidatePaths = @(
                (Join-Path (Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs") "QuinnOptimiserToolkit.log"),
                (Join-Path (Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs") "QuinnOptimiserToolkit.log")
            )
            $logPath = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $logPath) {
                [System.Windows.MessageBox]::Show("Log file was not found yet.", "Task Results", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
                return
            }
            Start-Process -FilePath "notepad.exe" -ArgumentList @($logPath) | Out-Null
        } catch { }
    })
    $actions.Children.Add($btnOpenFile) | Out-Null

    $btnClose = New-Object System.Windows.Controls.Button
    $btnClose.Content = "Close"
    $btnClose.MinWidth = 90
    $btnClose.Add_Click({ param($sender,$args) try { $window.Close() } catch { } })
    $actions.Children.Add($btnClose) | Out-Null

    $root.Children.Add($actions) | Out-Null
    $window.Content = $root
    $script:QOT_TaskResultsWindow = $window
    try {
        $window.Add_Closed({
            try { $script:QOT_TaskResultsWindow = $null } catch { }
            try { $script:QOT_TaskResultsSummaryText = $null } catch { }
            try { $script:QOT_TaskResultsGrid = $null } catch { }
        }.GetNewClosure())
    } catch { }

    Update-QOTTaskResultsWindowLiveState
    $window.Show()
    # Don't activate - let user continue working
    # $window.Activate() | Out-Null
}

function Get-QOTExceptionReport {
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $depth = 0
    $current = $Exception

    while ($current) {
        $parts.Add(("Exception[{0}] Type: {1}" -f $depth, $current.GetType().FullName))
        $parts.Add(("Exception[{0}] Message: {1}" -f $depth, $current.Message))
        if (-not [string]::IsNullOrWhiteSpace($current.StackTrace)) {
            $parts.Add(("Exception[{0}] StackTrace:`n{1}" -f $depth, $current.StackTrace))
        }

        $current = $current.InnerException
        $depth++
    }

    return ($parts -join [Environment]::NewLine)
}

function Import-QOTSharedThemeDictionary {
    param(
        [Parameter(Mandatory)]$Root,
        [Parameter(Mandatory)][string]$DictionaryPath
    )

    if (-not $Root) { return }
    if (-not (Test-Path -LiteralPath $DictionaryPath)) {
        throw "Shared theme dictionary not found at $DictionaryPath"
    }

    $resources = $Root.Resources
    if (-not $resources) {
        $resources = New-Object System.Windows.ResourceDictionary
        $Root.Resources = $resources
    }

    foreach ($existing in @($resources.MergedDictionaries)) {
        try {
            if ($existing.Contains("QOTVerticalScrollBarTemplate")) {
                return
            }
        } catch { }
    }

    [xml]$dictionaryDoc = Get-Content -LiteralPath $DictionaryPath -Raw
    $dictionaryReader = New-Object System.Xml.XmlNodeReader($dictionaryDoc)
    $dictionary = [System.Windows.Markup.XamlReader]::Load($dictionaryReader)
    if ($dictionary) {
        [void]$resources.MergedDictionaries.Add($dictionary)
    }
}

function Get-QOTPrimaryLogPath {
    $candidatePaths = @(
        (Join-Path (Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs") "QuinnOptimiserToolkit.log"),
        (Join-Path (Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs") "QuinnOptimiserToolkit.log")
    )

    foreach ($candidatePath in @($candidatePaths)) {
        try {
            if (Test-Path -LiteralPath $candidatePath) { return $candidatePath }
        } catch { }
    }

    return $candidatePaths[0]
}

function Show-QOTTicketsStartupFailurePanel {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string]$Message
    )

    try {
        $panel = $Window.FindName("TicketsStartupErrorPanel")
        $text = $Window.FindName("TicketsStartupErrorText")
        $grid = $Window.FindName("TicketsGrid")
        $detailsPanel = $Window.FindName("TicketDetailsPanel")

        if ($panel) {
            $panel.Visibility = [System.Windows.Visibility]::Visible
        }
        if ($text) {
            $text.Text = $Message
        }
        if ($grid) {
            $grid.Visibility = [System.Windows.Visibility]::Collapsed
        }
        if ($detailsPanel) {
            $detailsPanel.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
    catch {
        Write-QOTStartupTrace ("Tickets startup failure panel could not be shown: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Invoke-QOTStartupStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [int]$WarnThresholdMs = 200
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-QOTStartupTrace "$Name start"
    try {
        & $Action
    }
    catch {
        $sw.Stop()
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("{0} failed ({1} ms)`n{2}" -f $Name, [math]::Round($sw.Elapsed.TotalMilliseconds), $errorDetail) 'ERROR'
        throw
    }
    $sw.Stop()

    $durationMs = [math]::Round($sw.Elapsed.TotalMilliseconds)
    $level = if ($durationMs -ge $WarnThresholdMs) { 'WARN' } else { 'INFO' }
    Write-QOTStartupTrace ("{0} end ({1} ms)" -f $Name, $durationMs) $level
}

function Import-QOTModuleIfNeeded {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Global,
        [switch]$Optional
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        if ($Optional) { return }
        throw "Module path not found: $resolvedPath"
    }

    $alreadyLoaded = Get-Module | Where-Object { $_.Path -and ([System.IO.Path]::GetFullPath($_.Path) -eq $resolvedPath) }
    if ($alreadyLoaded) {
        Write-QOTStartupTrace ("Module already loaded: {0}" -f (Split-Path -Leaf $resolvedPath)) 'DEBUG'
        return
    }

    if ($Global) {
        Import-Module $resolvedPath -Global -ErrorAction Stop
    } else {
        Import-Module $resolvedPath -ErrorAction Stop
    }
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $identity) { return $false }

        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-QOTDriveSummary {
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    if (-not $drives) { return "n/a" }

    $segments = foreach ($drive in $drives) {
        if (-not $drive.Size -or $drive.Size -eq 0) { continue }
        $totalGB = [math]::Round($drive.Size / 1GB, 1)
        $freeGB = [math]::Round($drive.FreeSpace / 1GB, 1)
        $freePct = [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 0)
        "{0}: {1}/{2} GB free ({3}% free)" -f $drive.DeviceID, $freeGB, $totalGB, $freePct
    }

    if (-not $segments) { return "n/a" }
    return ($segments -join ", ")
}

function Get-QOTCpuSummary {
    $cpus = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue
    if (-not $cpus) { return "n/a" }
    $avg = ($cpus | Measure-Object -Property LoadPercentage -Average).Average
    if ($null -eq $avg) { return "n/a" }
    return ("{0}%" -f [math]::Round($avg, 0))
}

function Get-QOTRamSummary {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os -or -not $os.TotalVisibleMemorySize) { return "n/a" }
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $freePct = if ($totalGB -gt 0) { [math]::Round(($freeGB / $totalGB) * 100, 0) } else { 0 }
    return ("{0}/{1} GB free ({2}% free)" -f $freeGB, $totalGB, $freePct)
}

function Get-QOTNetworkSummary {
    $adapters = Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue
    if (-not $adapters) { return "n/a" }
    $bytesPerSec = ($adapters | Measure-Object -Property BytesTotalPersec -Sum).Sum
    if ($null -eq $bytesPerSec) { return "n/a" }
    $mbps = [math]::Round(($bytesPerSec * 8) / 1MB, 1)
    return ("{0} Mbps" -f $mbps)
}

function Get-QOTGpuSummary {
    $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name -Unique
    if (-not $gpus) { return $null }
    return ($gpus -join ", ")
}

function Get-QOTSystemSummaryText {
    $parts = New-Object System.Collections.Generic.List[string]

    $parts.Add(("Drives: {0}" -f (Get-QOTDriveSummary)))
    $parts.Add(("CPU: {0}" -f (Get-QOTCpuSummary)))
    $parts.Add(("RAM: {0}" -f (Get-QOTRamSummary)))
    $parts.Add(("Network: {0}" -f (Get-QOTNetworkSummary)))

    $gpuSummary = Get-QOTGpuSummary
    if (-not [string]::IsNullOrWhiteSpace($gpuSummary)) {
        $parts.Add(("GPU: {0}" -f $gpuSummary))
    }

    return ($parts -join " | ")
}

function Set-QOTSummary {
    param(
        [string]$Text
    )

    if (-not $script:SummaryTextBlock) { return }
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $script:SummaryTextBlock.Text = $Text
}

function Set-QOTPlayProgress {
    param(
        [System.Windows.Shapes.Path]$ProgressPath,
        [System.Windows.Media.RectangleGeometry]$ProgressClip,
        [double]$Percent
    )

    if (-not $ProgressPath -or -not $ProgressClip) { return }
    $safePercent = [math]::Max(0, [math]::Min(100, $Percent))

    $width = 34.0
    $height = 34.0
    try { if ([double]$ProgressPath.ActualWidth -gt 0) { $width = [double]$ProgressPath.ActualWidth } } catch { }
    try { if ([double]$ProgressPath.ActualHeight -gt 0) { $height = [double]$ProgressPath.ActualHeight } } catch { }
    try {
        if ($width -le 0 -and [double]$ProgressClip.Rect.Width -gt 0) {
            $width = [double]$ProgressClip.Rect.Width
        }
    } catch { }
    try {
        if ($height -le 0 -and [double]$ProgressClip.Rect.Height -gt 0) {
            $height = [double]$ProgressClip.Rect.Height
        }
    } catch { }
    if ($width -le 0) { $width = 34.0 }
    if ($height -le 0) { $height = 34.0 }

    $filledWidth = ($width * $safePercent / 100.0)
    $ProgressClip.Rect = New-Object System.Windows.Rect(0, 0, $filledWidth, $height)
}

function Set-QOTUIEnabledState {
    param(
        [AllowNull()]
        $Control,
        [Parameter(Mandatory)][bool]$IsEnabled
    )

    if (-not $Control) { return $false }

    $hasIsEnabled = $null -ne $Control.PSObject.Properties['IsEnabled']
    if (-not $hasIsEnabled) {
        try { Write-QLog ("Skipping IsEnabled set; control type does not expose IsEnabled: {0}" -f $Control.GetType().FullName) "WARN" } catch { }
        return $false
    }

    $Control.IsEnabled = $IsEnabled
    return $true
}

function Set-QOTHitTestVisibility {
    param(
        [AllowNull()]
        $Control,
        [Parameter(Mandatory)][bool]$IsHitTestVisible
    )

    if (-not $Control) { return $false }

    $hasIsHitTestVisible = $null -ne $Control.PSObject.Properties['IsHitTestVisible']
    if (-not $hasIsHitTestVisible) {
        try { Write-QLog ("Skipping IsHitTestVisible set; control type does not expose IsHitTestVisible: {0}" -f $Control.GetType().FullName) "WARN" } catch { }
        return $false
    }

    $Control.IsHitTestVisible = $IsHitTestVisible
    return $true
}

function Invoke-QOTPlayCompletionSound {
    try {
        [console]::Beep(880, 120)
        [console]::Beep(1245, 140)
    }
    catch {
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
    }
}

function Resolve-QOTControlSet {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string[]]$Names
    )

    $resolved = @{}
    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($name in $Names) {
        $control = Find-QOTControlByNameDeep -Root $Root -Name $name
        if ($control) {
            $resolved[$name] = $control
        }
        else {
            $missing.Add($name) | Out-Null
        }
    }

    return [pscustomobject]@{
        Resolved = $resolved
        Missing  = @($missing)
    }
}

function Resolve-QOTControlSetFallback {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string[]]$Names
    )

    $resolved = @{}
    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($name in $Names) {
        $control = Find-QOTControlByNameDeep -Root $Root -Name $name
        if ($control) {
            $resolved[$name] = $control
        }
        else {
            $missing.Add($name) | Out-Null
        }
    }

    return [pscustomobject]@{
        Resolved = $resolved
        Missing  = @($missing)
    }
}

function Invoke-QOTControlResolution {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string[]]$Names
    )

    if (-not $Root) {
        throw "Invoke-QOTControlResolution requires a non-null root."
    }

    if ($script:MainWindow -and ([object]::ReferenceEquals($Root, $script:MainWindow) -eq $false)) {
        Write-QOTStartupTrace "Control resolution root does not match script:MainWindow; forcing resolver root to script:MainWindow" 'WARN'
        $Root = $script:MainWindow
    }

    try {
        return Resolve-QOTControlSet -Root $Root -Names $Names
    }
    catch {
        $errorText = "Resolve-QOTControlSet failed; falling back to legacy control resolution. Error: $($_.Exception.Message)"
        Write-QOTStartupTrace $errorText 'ERROR'
        try { Write-QLog $errorText 'ERROR' } catch { }
    }

    return Resolve-QOTControlSetFallback -Root $Root -Names $Names
}

function Set-QOTTextValue {
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)][string]$Name,
        [string]$Value
    )

    if (-not $Window -or [string]::IsNullOrWhiteSpace($Name)) { return }

    $control = Find-QOTControlByNameDeep -Root $Window -Name $Name
    if (-not $control) { return }

    try {
        if ($null -ne $control.PSObject.Properties['Text']) {
            $control.Text = [string]$Value
        }
    }
    catch { }
}

function ConvertTo-QOTFriendlySize {
    param([double]$Bytes)

    if ($Bytes -lt 1KB) { return ("{0:N0} B" -f [math]::Max(0, $Bytes)) }
    if ($Bytes -lt 1MB) { return ("{0:N1} KB" -f ($Bytes / 1KB)) }
    if ($Bytes -lt 1GB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    return ("{0:N2} GB" -f ($Bytes / 1GB))
}

function Get-QOTFolderSizeBytesSafe {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return [int64]0 }
    $pathExists = $false
    try { $pathExists = Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue } catch { $pathExists = $false }
    if (-not $pathExists) { return [int64]0 }

    $total = [int64]0
    try {
        $files = Get-ChildItem -LiteralPath $Path -File -Force -Recurse -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            try { $total += [int64]$file.Length } catch { }
        }
    }
    catch { }

    return $total
}

function Get-QOTUptimeSummary {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if (-not $os -or -not $os.LastBootUpTime) { return "n/a" }

        $lastBoot = [System.Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)
        $uptime = (Get-Date) - $lastBoot
        return ("{0}d {1}h {2}m" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes)
    }
    catch {
        return "n/a"
    }
}

function Get-QOTMaintenanceSnapshot {
    param([int]$SelectedCount = 0)

    $systemDrive = if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) { "C:" } else { $env:SystemDrive }

    $diskFreeBytes = [int64]0
    try {
        $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $systemDrive) -ErrorAction SilentlyContinue
        if ($drive) { $diskFreeBytes = [int64]$drive.FreeSpace }
    }
    catch { }

    $tempEstimateBytes = [int64]0
    $tempCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($env:TEMP, "$env:SystemRoot\Temp")) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $tempCandidates.Add($candidate) | Out-Null
        }
    }

    $usersRoot = Join-Path $systemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot) {
        try {
            foreach ($userDir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue)) {
                if (-not $userDir) { continue }
                $tempCandidates.Add((Join-Path $userDir.FullName 'AppData\Local\Temp')) | Out-Null
            }
        }
        catch { }
    }

    foreach ($tempPath in @($tempCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        $tempEstimateBytes += Get-QOTFolderSizeBytesSafe -Path $tempPath
    }

    $windowsUpdateCacheBytes = Get-QOTFolderSizeBytesSafe -Path "$env:SystemRoot\SoftwareDistribution\Download"

    $ramUsage = 'n/a'
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os -and $os.TotalVisibleMemorySize -gt 0) {
            $totalBytes = [int64]$os.TotalVisibleMemorySize * 1KB
            $freeBytes = [int64]$os.FreePhysicalMemory * 1KB
            $usedBytes = [int64][math]::Max(0, $totalBytes - $freeBytes)
            $ramUsage = ("{0} used of {1}" -f (ConvertTo-QOTFriendlySize -Bytes $usedBytes), (ConvertTo-QOTFriendlySize -Bytes $totalBytes))
        }
    }
    catch { }

    return [pscustomobject]@{
        DiskFreeBytes = $diskFreeBytes
        TempEstimateBytes = $tempEstimateBytes
        WindowsUpdateCacheBytes = $windowsUpdateCacheBytes
        RamUsage = $ramUsage
        Uptime = (Get-QOTUptimeSummary)
        SelectedCount = $SelectedCount
    }
}

function Update-QOTMaintenanceSummaryPanel {
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)]$Before,
        [AllowNull()]$After,
        [int]$Completed = 0,
        [int]$Skipped = 0,
        [int]$Failed = 0,
        [string]$LastRunTime = $null
    )

    if (-not $Window -or -not $Before) { return }

    Set-QOTTextValue -Window $Window -Name 'TxtBeforeDiskFree' -Value (ConvertTo-QOTFriendlySize -Bytes $Before.DiskFreeBytes)
    Set-QOTTextValue -Window $Window -Name 'TxtBeforeTempSize' -Value (ConvertTo-QOTFriendlySize -Bytes $Before.TempEstimateBytes)
    Set-QOTTextValue -Window $Window -Name 'TxtBeforeWindowsUpdateCacheSize' -Value (ConvertTo-QOTFriendlySize -Bytes $Before.WindowsUpdateCacheBytes)
    Set-QOTTextValue -Window $Window -Name 'TxtBeforeRamUsage' -Value ([string]$Before.RamUsage)
    Set-QOTTextValue -Window $Window -Name 'TxtBeforeUptime' -Value ([string]$Before.Uptime)
    Set-QOTTextValue -Window $Window -Name 'TxtSelectedCount' -Value ([string]$Before.SelectedCount)

    if ($After) {
        $recoveredBytes = [int64][math]::Max(0, ([int64]$After.DiskFreeBytes - [int64]$Before.DiskFreeBytes))
        Set-QOTTextValue -Window $Window -Name 'TxtAfterRecoveredSpace' -Value (ConvertTo-QOTFriendlySize -Bytes $recoveredBytes)
    }

    Set-QOTTextValue -Window $Window -Name 'TxtAfterActionsCompleted' -Value ([string]$Completed)
    Set-QOTTextValue -Window $Window -Name 'TxtAfterActionsSkipped' -Value ([string]$Skipped)
    Set-QOTTextValue -Window $Window -Name 'TxtAfterActionsFailed' -Value ([string]$Failed)
    Set-QOTTextValue -Window $Window -Name 'TxtRunSummary' -Value ("{0} / {1}" -f $Skipped, $Failed)

    if ([string]::IsNullOrWhiteSpace($LastRunTime)) {
        Set-QOTTextValue -Window $Window -Name 'TxtLastRunTime' -Value 'Never'
    }
    else {
        Set-QOTTextValue -Window $Window -Name 'TxtLastRunTime' -Value $LastRunTime
    }
}

function Run-QOTSelectedTasks {
    param(
        $Window,
        [System.Windows.Shapes.Path]$ProgressPath,
        [System.Windows.Media.RectangleGeometry]$ProgressClip,
        [object[]]$SelectedEntries
    )

    $activeWindow = $Window
    if (-not $activeWindow) {
        $activeWindow = $script:MainWindow
    }
    if (-not $activeWindow) {
        throw 'Main window is not initialised. Cannot run selected tasks.'
    }

    if (-not (Get-Command Get-QOTSelectedActionsInExecutionOrder -ErrorAction SilentlyContinue)) {
        throw 'Get-QOTSelectedActionsInExecutionOrder is unavailable. Action registry did not load correctly.'
    }
    if (-not (Get-Command Get-QOTActionDefinition -ErrorAction SilentlyContinue)) {
        throw 'Get-QOTActionDefinition is unavailable. Action registry did not load correctly.'
    }

    $selectedEntries = @()
    if ($PSBoundParameters.ContainsKey('SelectedEntries') -and $null -ne $SelectedEntries) {
        $selectedEntries = @($SelectedEntries)
    }
    else {
        try {
            $selectedEntries = @(Get-QOTSelectedActionsInExecutionOrder -Window $activeWindow)
        }
        catch {
            throw "Failed to enumerate selected actions: $($_.Exception.Message)"
        }
    }

    $beforeSnapshot = Get-QOTMaintenanceSnapshot -SelectedCount $selectedEntries.Count
    Update-QOTMaintenanceSummaryPanel -Window $activeWindow -Before $beforeSnapshot -After $null -Completed 0 -Skipped 0 -Failed 0 -LastRunTime 'Never'
    Reset-QOTTaskRunLog -SelectedCount $selectedEntries.Count

    if ($selectedEntries.Count -eq 0) {
        Write-QOTRuntimeLogSafe 'No tasks selected.' 'INFO'
        Write-QOTRuntimeLogSafe 'No more tasks to do.' 'INFO'
        Complete-QOTTaskRunLog -SelectedCount 0 -Worked 0 -Skipped 0 -Failed 0
        return
    }

    $successCount = 0
    $skippedCount = 0
    $failedCount = 0
    $taskTimeoutSeconds = Get-QOTGlobalTaskTimeoutSeconds
    $setPlayProgressSafe = {
        param(
            [System.Windows.Shapes.Path]$Path,
            [System.Windows.Media.RectangleGeometry]$Clip,
            [double]$Percent
        )

        try {
            Set-QOTPlayProgress -ProgressPath $Path -ProgressClip $Clip -Percent $Percent
            return
        } catch { }

        try {
            if (-not $Path -or -not $Clip) { return }
            $safePercent = [math]::Max(0, [math]::Min(100, $Percent))
            $width = 34.0
            $height = 34.0
            try { if ([double]$Path.ActualWidth -gt 0) { $width = [double]$Path.ActualWidth } } catch { }
            try { if ([double]$Path.ActualHeight -gt 0) { $height = [double]$Path.ActualHeight } } catch { }
            if ($width -le 0) { $width = 34.0 }
            if ($height -le 0) { $height = 34.0 }
            $filledWidth = ($width * $safePercent / 100.0)
            $Clip.Rect = New-Object System.Windows.Rect(0, 0, $filledWidth, $height)
        } catch { }
    }.GetNewClosure()

    $invokeTaskWithUiPump = {
        param(
            [Parameter(Mandatory)][string]$ScriptPath,
            [int]$TimeoutSeconds = 1800
        )

        $rs = [runspacefactory]::CreateRunspace()
        try { $rs.ApartmentState = [System.Threading.ApartmentState]::STA } catch { }
        try { $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread } catch { }
        $rs.Open()

        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $null = $ps.AddScript({
            param([string]$InnerScriptPath)
            $ErrorActionPreference = "Stop"
            & $InnerScriptPath -Window $null
        }).AddArgument($ScriptPath)

        $async = $null
        try {
            $async = $ps.BeginInvoke()
            $startedAt = Get-Date

            while ($true) {
                if ($async.IsCompleted) { break }

                # Keep the WPF message pump active while worker task runs.
                $frame = New-Object System.Windows.Threading.DispatcherFrame
                $yieldTimer = [System.Windows.Threading.DispatcherTimer]::new()
                $yieldTimer.Interval = [TimeSpan]::FromMilliseconds(50)
                $yieldTimer.Add_Tick({
                    param($sender, $args)
                    try { $sender.Stop() } catch { }
                    try { $frame.Continue = $false } catch { }
                }.GetNewClosure())
                try { Register-QOTMainWindowTimer -Timer $yieldTimer } catch { }
                try { $yieldTimer.Start() } catch { }
                [System.Windows.Threading.Dispatcher]::PushFrame($frame)

                if (((Get-Date) - $startedAt).TotalSeconds -ge $TimeoutSeconds) {
                    try { $ps.Stop() } catch { }
                    throw ("Timed out after {0} seconds" -f [int]$TimeoutSeconds)
                }
            }

            return @($ps.EndInvoke($async))
        }
        finally {
            try { $ps.Dispose() } catch { }
            try { $rs.Dispose() } catch { }
        }
    }.GetNewClosure()

    for ($i = 0; $i -lt $selectedEntries.Count; $i++) {
        $selection = $selectedEntries[$i]
        $actionId = [string]$selection.ActionId
        if ([string]::IsNullOrWhiteSpace($actionId)) {
            $failedCount++
            continue
        }

        $definition = Get-QOTActionDefinition -ActionId $actionId
        if (-not $definition) {
            Write-QOTRuntimeLogSafe ("Action definition missing: {0}" -f $actionId) 'ERROR'
            $failedCount++
            continue
        }

        $taskName = if (-not [string]::IsNullOrWhiteSpace([string]$definition.Label)) { [string]$definition.Label } else { $actionId }
        $scriptPath = [string]$definition.ScriptPath

        Write-QOTRuntimeLogSafe ("Now doing task: {0}" -f $taskName) 'INFO'

        $taskStatus = 'FAILED'
        $taskReason = $null

        try {
            if ([string]::IsNullOrWhiteSpace($scriptPath)) {
                throw "No script path found for action '$actionId'."
            }
            if (-not (Test-Path -LiteralPath $scriptPath)) {
                throw "Script path does not exist: $scriptPath"
            }

            if ($actionId -eq 'Apps.RunSelected') {
                $result = & {
                    $ErrorActionPreference = 'Stop'
                    & $scriptPath -Window $activeWindow
                }
            }
            else {
                $result = & $invokeTaskWithUiPump -ScriptPath $scriptPath -TimeoutSeconds $taskTimeoutSeconds
            }

            $resultStatus = $null
            $resultReason = $null
            $resultError = $null

            if ($null -ne $result) {
                foreach ($entry in @($result)) {
                    if ($null -eq $entry) { continue }
                    if ($entry.PSObject.Properties.Name -contains 'Status') {
                        $resultStatus = [string]$entry.Status
                        if ($entry.PSObject.Properties.Name -contains 'Reason') { $resultReason = [string]$entry.Reason }
                        if ($entry.PSObject.Properties.Name -contains 'Error') { $resultError = [string]$entry.Error }
                        break
                    }
                }
            }

            if ($resultStatus) {
                switch ($resultStatus.ToLowerInvariant()) {
                    'success' { $taskStatus = 'SUCCESS' }
                    'skipped' { $taskStatus = 'SKIPPED'; $taskReason = $resultReason }
                    'failed'  { $taskStatus = 'FAILED'; $taskReason = $resultReason }
                    default {
                        $taskStatus = 'FAILED'
                        $taskReason = "Unknown task result status: $resultStatus"
                    }
                }
                if (-not $taskReason -and $resultError) {
                    $taskReason = $resultError
                }
            }
            else {
                $taskStatus = 'SUCCESS'
            }
        }
        catch {
            $taskStatus = 'FAILED'
            $taskReason = $_.Exception.Message
            Write-QOTRuntimeLogSafe ("Task failed: {0} | {1}" -f $taskName, $taskReason) 'ERROR'
        }
        finally {
            switch ($taskStatus) {
                'SUCCESS' { $successCount++ }
                'SKIPPED' { $skippedCount++ }
                default { $failedCount++ }
            }

            if ($taskStatus -eq 'SUCCESS') {
                Write-QOTRuntimeLogSafe ("Completed task: {0} (SUCCESS)" -f $taskName) 'INFO'
            }
            elseif ($taskStatus -eq 'SKIPPED') {
                Write-QOTRuntimeLogSafe ("Skipped task: {0}" -f $taskName) 'WARN'
            }
            else {
                if ([string]::IsNullOrWhiteSpace($taskReason)) { $taskReason = 'Unknown error' }
                Write-QOTRuntimeLogSafe ("Completed task: {0} (FAILED - {1})" -f $taskName, $taskReason) 'ERROR'
            }
            Add-QOTTaskRunLogEntry -TaskName $taskName -Status $taskStatus -Reason $taskReason

            if ($ProgressPath -and $ProgressClip) {
                $pct = [math]::Round((($i + 1) / [double]$selectedEntries.Count) * 100, 0)
                & $setPlayProgressSafe -Path $ProgressPath -Clip $ProgressClip -Percent $pct
            }
        }
    }

    $afterSnapshot = Get-QOTMaintenanceSnapshot -SelectedCount $selectedEntries.Count
    Update-QOTMaintenanceSummaryPanel -Window $activeWindow -Before $beforeSnapshot -After $afterSnapshot -Completed $successCount -Skipped $skippedCount -Failed $failedCount -LastRunTime ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    Complete-QOTTaskRunLog -SelectedCount $selectedEntries.Count -Worked $successCount -Skipped $skippedCount -Failed $failedCount

    Write-QOTRuntimeLogSafe ("Summary: Success={0} Skipped={1} Failed={2}" -f $successCount, $skippedCount, $failedCount) 'INFO'
    Write-QOTRuntimeLogSafe 'No more tasks to do.' 'INFO'
}

function New-QOTMaintenanceSnapshotPlaceholder {
    param([int]$SelectedCount = 0)

    return [pscustomobject]@{
        DiskFreeBytes           = [int64]0
        TempEstimateBytes       = [int64]0
        WindowsUpdateCacheBytes = [int64]0
        RamUsage                = 'n/a'
        Uptime                  = 'n/a'
        SelectedCount           = [int]$SelectedCount
    }
}

function Resolve-QOTTaskExecutionOutcome {
    param(
        [AllowNull()]$Result,
        [AllowNull()][System.Exception]$Error
    )

    $taskStatus = 'FAILED'
    $taskReason = $null

    if ($Error) {
        $taskReason = [string]$Error.Message
        return [pscustomobject]@{
            Status = $taskStatus
            Reason = $taskReason
        }
    }

    $resultStatus = $null
    $resultReason = $null
    $resultError = $null

    if ($null -ne $Result) {
        foreach ($entry in @($Result)) {
            if ($null -eq $entry) { continue }
            if ($entry.PSObject.Properties.Name -contains 'Status') {
                $resultStatus = [string]$entry.Status
                if ($entry.PSObject.Properties.Name -contains 'Reason') { $resultReason = [string]$entry.Reason }
                if ($entry.PSObject.Properties.Name -contains 'Error') { $resultError = [string]$entry.Error }
                break
            }
        }
    }

    if ($resultStatus) {
        switch ($resultStatus.ToLowerInvariant()) {
            'success' { $taskStatus = 'SUCCESS' }
            'skipped' { $taskStatus = 'SKIPPED'; $taskReason = $resultReason }
            'failed'  { $taskStatus = 'FAILED'; $taskReason = $resultReason }
            default {
                $taskStatus = 'FAILED'
                $taskReason = "Unknown task result status: $resultStatus"
            }
        }
        if (-not $taskReason -and $resultError) {
            $taskReason = $resultError
        }
    }
    else {
        $taskStatus = 'SUCCESS'
    }

    return [pscustomobject]@{
        Status = $taskStatus
        Reason = $taskReason
    }
}

function Start-QOTSelectedTasksAsync {
    param(
        $Window,
        [System.Windows.Shapes.Path]$ProgressPath,
        [System.Windows.Media.RectangleGeometry]$ProgressClip,
        [scriptblock]$OnCompleted,
        [object[]]$SelectedEntries
    )

    $activeWindow = $Window
    if (-not $activeWindow) { $activeWindow = $script:MainWindow }
    if (-not $activeWindow) {
        throw 'Main window is not initialised. Cannot run selected tasks.'
    }

    if (-not (Get-Command Get-QOTSelectedActionsInExecutionOrder -ErrorAction SilentlyContinue)) {
        throw 'Get-QOTSelectedActionsInExecutionOrder is unavailable. Action registry did not load correctly.'
    }
    if (-not (Get-Command Get-QOTActionDefinition -ErrorAction SilentlyContinue)) {
        throw 'Get-QOTActionDefinition is unavailable. Action registry did not load correctly.'
    }

    $selectedEntries = @()
    if ($PSBoundParameters.ContainsKey('SelectedEntries') -and $null -ne $SelectedEntries) {
        $selectedEntries = @($SelectedEntries)
    }
    else {
        try {
            $selectedEntries = @(Get-QOTSelectedActionsInExecutionOrder -Window $activeWindow)
        }
        catch {
            throw "Failed to enumerate selected actions: $($_.Exception.Message)"
        }
    }

    $invokeCallbackCmd = $null
    $resolveOutcomeCmd = $null
    $addTaskLogEntryCmd = $null
    $newSnapshotCmd = $null
    $updateSummaryCmd = $null
    $completeTaskLogCmd = $null
    $getActionDefinitionCmd = $null

    try { $invokeCallbackCmd = Resolve-QOTInvokableCommand -Name "Invoke-QOTCallbackSafely" -LookupErrorAction SilentlyContinue } catch { $invokeCallbackCmd = $null }
    try { $resolveOutcomeCmd = Resolve-QOTInvokableCommand -Name "Resolve-QOTTaskExecutionOutcome" -LookupErrorAction SilentlyContinue } catch { $resolveOutcomeCmd = $null }
    try { $addTaskLogEntryCmd = Resolve-QOTInvokableCommand -Name "Add-QOTTaskRunLogEntry" -LookupErrorAction SilentlyContinue } catch { $addTaskLogEntryCmd = $null }
    try { $newSnapshotCmd = Resolve-QOTInvokableCommand -Name "New-QOTMaintenanceSnapshotPlaceholder" -LookupErrorAction SilentlyContinue } catch { $newSnapshotCmd = $null }
    try { $updateSummaryCmd = Resolve-QOTInvokableCommand -Name "Update-QOTMaintenanceSummaryPanel" -LookupErrorAction SilentlyContinue } catch { $updateSummaryCmd = $null }
    try { $completeTaskLogCmd = Resolve-QOTInvokableCommand -Name "Complete-QOTTaskRunLog" -LookupErrorAction SilentlyContinue } catch { $completeTaskLogCmd = $null }
    try { $getActionDefinitionCmd = Resolve-QOTInvokableCommand -Name "Get-QOTActionDefinition" -LookupErrorAction SilentlyContinue } catch { $getActionDefinitionCmd = $null }

    if (-not $invokeCallbackCmd) { try { $invokeCallbackCmd = ${function:Invoke-QOTCallbackSafely} } catch { } }
    if (-not $resolveOutcomeCmd) { try { $resolveOutcomeCmd = ${function:Resolve-QOTTaskExecutionOutcome} } catch { } }
    if (-not $addTaskLogEntryCmd) { try { $addTaskLogEntryCmd = ${function:Add-QOTTaskRunLogEntry} } catch { } }
    if (-not $newSnapshotCmd) { try { $newSnapshotCmd = ${function:New-QOTMaintenanceSnapshotPlaceholder} } catch { } }
    if (-not $updateSummaryCmd) { try { $updateSummaryCmd = ${function:Update-QOTMaintenanceSummaryPanel} } catch { } }
    if (-not $completeTaskLogCmd) { try { $completeTaskLogCmd = ${function:Complete-QOTTaskRunLog} } catch { } }

    if (-not $invokeCallbackCmd) {
        $invokeCallbackCmd = {
            param(
                [AllowNull()]$Callback,
                [object[]]$ArgumentList = @()
            )

            if ($Callback -is [System.Management.Automation.CommandInfo]) {
                return & $Callback @ArgumentList
            }
            if ($Callback -is [scriptblock]) {
                return & $Callback @ArgumentList
            }
            if ($Callback -and $Callback -is [string]) {
                $resolved = @(Get-Command -Name $Callback -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($resolved -is [System.Array]) {
                    $resolved = if ($resolved.Count -gt 0) { $resolved[0] } else { $null }
                }
                if ($resolved) {
                    return & $resolved @ArgumentList
                }
            }
            throw "Callback is not invokable."
        }.GetNewClosure()
    }

    $writeQLogCmd = $null
    try {
        $writeQLogCmd = @(Get-Command Write-QLog -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($writeQLogCmd -is [System.Array]) {
            $writeQLogCmd = if ($writeQLogCmd.Count -gt 0) { $writeQLogCmd[0] } else { $null }
        }
    } catch { $writeQLogCmd = $null }

    $writeRuntimeSafe = {
        param(
            [Parameter(Mandatory)][string]$Message,
            [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
        )

        try {
            if ($writeQLogCmd) {
                & $writeQLogCmd $Message $Level
                return
            }
        } catch { }

        try {
            $fallbackDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"
            New-Item -ItemType Directory -Path $fallbackDir -Force -ErrorAction Stop | Out-Null
            $fallbackPath = Join-Path $fallbackDir "MainWindow.Runtime.log"
            Add-Content -LiteralPath $fallbackPath -Value ("[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message) -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }.GetNewClosure()

    try {
        $invokeType = if ($null -eq $invokeCallbackCmd) { "<null>" } else { $invokeCallbackCmd.GetType().FullName }
        $resolveType = if ($null -eq $resolveOutcomeCmd) { "<null>" } else { $resolveOutcomeCmd.GetType().FullName }
        & $writeRuntimeSafe ("Async helper bindings: invoke={0}; resolve={1}" -f $invokeType, $resolveType) 'DEBUG'
    } catch { }

    $beforeSnapshot = if ($null -ne $newSnapshotCmd) {
        & $newSnapshotCmd -SelectedCount $selectedEntries.Count
    } else {
        New-QOTMaintenanceSnapshotPlaceholder -SelectedCount $selectedEntries.Count
    }
    try {
        if ($null -ne $updateSummaryCmd) {
            & $updateSummaryCmd -Window $activeWindow -Before $beforeSnapshot -After $null -Completed 0 -Skipped 0 -Failed 0 -LastRunTime 'Never'
        } else {
            Update-QOTMaintenanceSummaryPanel -Window $activeWindow -Before $beforeSnapshot -After $null -Completed 0 -Skipped 0 -Failed 0 -LastRunTime 'Never'
        }
    } catch { }
    Reset-QOTTaskRunLog -SelectedCount $selectedEntries.Count
    $taskTimeoutSeconds = Get-QOTGlobalTaskTimeoutSeconds

    $state = [ordered]@{
        Window          = $activeWindow
        ProgressPath    = $ProgressPath
        ProgressClip    = $ProgressClip
        SelectedEntries = @($selectedEntries)
        RunStartedAt    = (Get-Date)
        BeforeSnapshot  = $beforeSnapshot
        SuccessCount    = 0
        SkippedCount    = 0
        FailedCount     = 0
        CurrentIndex    = 0
        CurrentActionId = ""
        CurrentTaskName = ""
        CurrentTaskStartedAt = $null
        TaskTimeoutSeconds = $taskTimeoutSeconds
        WorkerRunspace  = $null
        WorkerPowerShell = $null
        WorkerAsyncResult = $null
        PollTimer       = $null
        PollTickHandler = $null
        OnCompleted     = $OnCompleted
    }
    $setPlayProgressSafe = {
        param(
            [System.Windows.Shapes.Path]$Path,
            [System.Windows.Media.RectangleGeometry]$Clip,
            [double]$Percent
        )

        try {
            Set-QOTPlayProgress -ProgressPath $Path -ProgressClip $Clip -Percent $Percent
            return
        } catch { }

        try {
            if (-not $Path -or -not $Clip) { return }
            $safePercent = [math]::Max(0, [math]::Min(100, $Percent))
            $width = 34.0
            $height = 34.0
            try { if ([double]$Path.ActualWidth -gt 0) { $width = [double]$Path.ActualWidth } } catch { }
            try { if ([double]$Path.ActualHeight -gt 0) { $height = [double]$Path.ActualHeight } } catch { }
            if ($width -le 0) { $width = 34.0 }
            if ($height -le 0) { $height = 34.0 }
            $filledWidth = ($width * $safePercent / 100.0)
            $Clip.Rect = New-Object System.Windows.Rect(0, 0, $filledWidth, $height)
        } catch { }
    }.GetNewClosure()

    $script:QOT_TaskRunnerState = $state

    $disposeWorkerInvocation = {
        if ($state.WorkerPowerShell) {
            try { $state.WorkerPowerShell.Dispose() } catch { }
            $state.WorkerPowerShell = $null
        }
        $state.WorkerAsyncResult = $null
    }.GetNewClosure()

    $disposeWorkerRunspace = {
        if ($state.WorkerRunspace) {
            try { $state.WorkerRunspace.Dispose() } catch { }
            $state.WorkerRunspace = $null
        }
    }.GetNewClosure()

    $disposeWorker = {
        & $disposeWorkerInvocation
        & $disposeWorkerRunspace
    }.GetNewClosure()

    $ensureWorkerRunspace = {
        if ($state.WorkerRunspace) { return $true }
        try {
            $rs = [runspacefactory]::CreateRunspace()
            try { $rs.ApartmentState = [System.Threading.ApartmentState]::STA } catch { }
            try { $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread } catch { }
            $rs.Open()
            $state.WorkerRunspace = $rs
            return $true
        } catch {
            try { & $writeRuntimeSafe ("Worker runspace creation failed: {0}" -f $_.Exception.Message) 'ERROR' } catch { }
            try { & $disposeWorkerRunspace } catch { }
            return $false
        }
    }.GetNewClosure()

    $updateProgress = {
        if (-not $state.ProgressPath -or -not $state.ProgressClip) { return }
        $total = [int]@($state.SelectedEntries).Count
        if ($total -le 0) {
            & $setPlayProgressSafe -Path $state.ProgressPath -Clip $state.ProgressClip -Percent 0
            return
        }
        $pct = [math]::Round((([double]$state.CurrentIndex) / [double]$total) * 100, 0)
        & $setPlayProgressSafe -Path $state.ProgressPath -Clip $state.ProgressClip -Percent $pct
    }.GetNewClosure()

    $applyOutcome = {
        param($Outcome)

        $status = "FAILED"
        $reason = $null
        try { if ($Outcome -and $Outcome.PSObject.Properties.Name -contains 'Status') { $status = [string]$Outcome.Status } } catch { $status = "FAILED" }
        try { if ($Outcome -and $Outcome.PSObject.Properties.Name -contains 'Reason') { $reason = [string]$Outcome.Reason } } catch { $reason = $null }

        switch ($status) {
            'SUCCESS' { $state.SuccessCount++ }
            'SKIPPED' { $state.SkippedCount++ }
            default { $state.FailedCount++ }
        }

        if ($status -eq 'SUCCESS') {
            & $writeRuntimeSafe ("Completed task: {0} (SUCCESS)" -f $state.CurrentTaskName) 'INFO'
        }
        elseif ($status -eq 'SKIPPED') {
            & $writeRuntimeSafe ("Skipped task: {0}" -f $state.CurrentTaskName) 'WARN'
        }
        else {
            if ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'Unknown error' }
            & $writeRuntimeSafe ("Completed task: {0} (FAILED - {1})" -f $state.CurrentTaskName, $reason) 'ERROR'
        }

        if ($null -ne $addTaskLogEntryCmd) {
            & $addTaskLogEntryCmd -TaskName $state.CurrentTaskName -Status $status -Reason $reason
        } else {
            Add-QOTTaskRunLogEntry -TaskName $state.CurrentTaskName -Status $status -Reason $reason
        }
    }.GetNewClosure()

    $completeRun = {
        try {
            $afterSnapshot = if ($null -ne $newSnapshotCmd) {
                & $newSnapshotCmd -SelectedCount @($state.SelectedEntries).Count
            } else {
                New-QOTMaintenanceSnapshotPlaceholder -SelectedCount @($state.SelectedEntries).Count
            }

            if ($null -ne $updateSummaryCmd) {
                & $updateSummaryCmd `
                    -Window $state.Window `
                    -Before $state.BeforeSnapshot `
                    -After $afterSnapshot `
                    -Completed $state.SuccessCount `
                    -Skipped $state.SkippedCount `
                    -Failed $state.FailedCount `
                    -LastRunTime ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
            } else {
                Update-QOTMaintenanceSummaryPanel `
                    -Window $state.Window `
                    -Before $state.BeforeSnapshot `
                    -After $afterSnapshot `
                    -Completed $state.SuccessCount `
                    -Skipped $state.SkippedCount `
                    -Failed $state.FailedCount `
                    -LastRunTime ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
            }
        } catch { }

        & $writeRuntimeSafe ("Summary: Success={0} Skipped={1} Failed={2}" -f $state.SuccessCount, $state.SkippedCount, $state.FailedCount) 'INFO'
        & $writeRuntimeSafe 'No more tasks to do.' 'INFO'

        if ($null -ne $completeTaskLogCmd) {
            & $completeTaskLogCmd -SelectedCount @($state.SelectedEntries).Count -Worked $state.SuccessCount -Skipped $state.SkippedCount -Failed $state.FailedCount
        } else {
            Complete-QOTTaskRunLog -SelectedCount @($state.SelectedEntries).Count -Worked $state.SuccessCount -Skipped $state.SkippedCount -Failed $state.FailedCount
        }

        if ($state.PollTimer) {
            try { $state.PollTimer.Stop() } catch { }
        }
        & $disposeWorker
        $script:QOT_TaskRunnerState = $null

        try {
            if ($state.OnCompleted) {
                if ($null -ne $invokeCallbackCmd) {
                    & $invokeCallbackCmd -Callback $state.OnCompleted
                } else {
                    & $state.OnCompleted
                }
            }
        } catch {
            try {
                & $writeRuntimeSafe ("Async completion callback failed: {0}" -f $_.Exception.Message) 'ERROR'
            } catch { }
        }
    }.GetNewClosure()

    $startNext = $null
    $startNext = {
        while ($true) {
            $total = [int]@($state.SelectedEntries).Count
            if ($state.CurrentIndex -ge $total) {
                & $completeRun
                return
            }

            $selection = $state.SelectedEntries[$state.CurrentIndex]
            $actionId = ""
            try { $actionId = [string]$selection.ActionId } catch { $actionId = "" }
            if ([string]::IsNullOrWhiteSpace($actionId)) {
                $state.CurrentActionId = "<missing>"
                $state.CurrentTaskName = "Unknown task"
                & $applyOutcome @([pscustomobject]@{ Status = "FAILED"; Reason = "Missing action id" })
                $state.CurrentIndex++
                & $updateProgress
                continue
            }

            $definition = if ($null -ne $getActionDefinitionCmd) { & $getActionDefinitionCmd -ActionId $actionId } else { Get-QOTActionDefinition -ActionId $actionId }
            if (-not $definition) {
                $state.CurrentActionId = $actionId
                $state.CurrentTaskName = $actionId
                & $applyOutcome @([pscustomobject]@{ Status = "FAILED"; Reason = "Action definition missing: $actionId" })
                $state.CurrentIndex++
                & $updateProgress
                continue
            }

            $taskName = if (-not [string]::IsNullOrWhiteSpace([string]$definition.Label)) { [string]$definition.Label } else { $actionId }
            $scriptPath = [string]$definition.ScriptPath
            $state.CurrentActionId = $actionId
            $state.CurrentTaskName = $taskName
            $state.CurrentTaskStartedAt = Get-Date

            & $writeRuntimeSafe ("Now doing task: {0}" -f $taskName) 'INFO'

            if ([string]::IsNullOrWhiteSpace($scriptPath) -or (-not (Test-Path -LiteralPath $scriptPath))) {
                $reason = if ([string]::IsNullOrWhiteSpace($scriptPath)) { "No script path found for action '$actionId'." } else { "Script path does not exist: $scriptPath" }
                & $applyOutcome @([pscustomobject]@{ Status = "FAILED"; Reason = $reason })
                $state.CurrentIndex++
                & $updateProgress
                continue
            }

            # Apps action already runs its own background worker and needs live UI controls.
            if ($actionId -eq 'Apps.RunSelected') {
                $appsResult = $null
                $appsError = $null
                try {
                    $appsResult = & {
                        $ErrorActionPreference = 'Stop'
                        & $scriptPath -Window $state.Window
                    }
                }
                catch {
                    $appsError = $_.Exception
                }

                $appsOutcome = if ($null -ne $resolveOutcomeCmd) { & $resolveOutcomeCmd -Result $appsResult -Error $appsError } else { Resolve-QOTTaskExecutionOutcome -Result $appsResult -Error $appsError }
                & $applyOutcome @($appsOutcome)
                $state.CurrentIndex++
                & $updateProgress
                continue
            }

            if (-not (& $ensureWorkerRunspace)) {
                & $applyOutcome @([pscustomobject]@{ Status = "FAILED"; Reason = "Worker runspace could not be initialised." })
                $state.CurrentIndex++
                & $updateProgress
                continue
            }

            $ps = [powershell]::Create()
            $ps.Runspace = $state.WorkerRunspace
            $null = $ps.AddScript({
                param([string]$ScriptPath)
                $ErrorActionPreference = 'Stop'
                & $ScriptPath -Window $null
            }).AddArgument($scriptPath)

            $state.WorkerPowerShell = $ps
            $state.WorkerAsyncResult = $ps.BeginInvoke()
            if (-not $state.PollTimer) {
                $state.PollTimer = [System.Windows.Threading.DispatcherTimer]::new()
                $state.PollTimer.Interval = [TimeSpan]::FromMilliseconds(150)
                $state.PollTickHandler = {
                    if ($null -eq $state.WorkerAsyncResult) { return }
                    if ($state.CurrentTaskStartedAt) {
                        try {
                            $elapsedSeconds = ((Get-Date) - ([datetime]$state.CurrentTaskStartedAt)).TotalSeconds
                            if ($elapsedSeconds -ge [double]$state.TaskTimeoutSeconds) {
                                try { $state.PollTimer.Stop() } catch { }
                                try { & $disposeWorker } catch { }
                                $timeoutReason = ("Timed out after {0} seconds" -f [int]$state.TaskTimeoutSeconds)
                                try { & $writeRuntimeSafe ("Task timed out: {0} ({1})" -f $state.CurrentTaskName, $timeoutReason) 'ERROR' } catch { }
                                try { & $applyOutcome @([pscustomobject]@{ Status = "FAILED"; Reason = $timeoutReason }) } catch { }
                                try { $state.CurrentIndex++ } catch { }
                                try { & $updateProgress } catch { }
                                try { & $startNext } catch { try { & $completeRun } catch { } }
                                return
                            }
                        } catch { }
                    }
                    if (-not $state.WorkerAsyncResult.IsCompleted) { return }

                    try { $state.PollTimer.Stop() } catch { }

                    $workerResult = $null
                    $workerError = $null
                    try {
                        $output = @($state.WorkerPowerShell.EndInvoke($state.WorkerAsyncResult))
                        if ($output.Count -gt 0) {
                            $workerResult = $output
                        }
                    }
                    catch {
                        $workerError = $_.Exception
                    }
                    finally {
                        try { & $disposeWorkerInvocation } catch { }
                        $state.CurrentTaskStartedAt = $null
                    }

                    try {
                        $outcome = if ($null -ne $resolveOutcomeCmd) { & $resolveOutcomeCmd -Result $workerResult -Error $workerError } else { Resolve-QOTTaskExecutionOutcome -Result $workerResult -Error $workerError }
                        & $applyOutcome @($outcome)
                    }
                    catch {
                        try {
                            & $writeRuntimeSafe ("Async task runner callback failed for task '{0}': {1}" -f $state.CurrentTaskName, $_.Exception.Message) 'ERROR'
                        } catch { }
                        try { $state.FailedCount++ } catch { }
                        try {
                            if ($null -ne $addTaskLogEntryCmd) {
                                & $addTaskLogEntryCmd -TaskName $state.CurrentTaskName -Status 'FAILED' -Reason $_.Exception.Message
                            } else {
                                Add-QOTTaskRunLogEntry -TaskName $state.CurrentTaskName -Status 'FAILED' -Reason $_.Exception.Message
                            }
                        } catch { }
                    }

                    try { $state.CurrentIndex++ } catch { }
                    try { & $updateProgress } catch { }
                    try { & $startNext } catch { try { & $completeRun } catch { } }
                }.GetNewClosure()
                $state.PollTimer.Add_Tick($state.PollTickHandler)
                try { Register-QOTMainWindowTimer -Timer $state.PollTimer } catch { }
            }

            try { $state.PollTimer.Start() } catch { }
            return
        }
    }.GetNewClosure()

    & $updateProgress
    if (@($state.SelectedEntries).Count -eq 0) {
        & $writeRuntimeSafe 'No tasks selected.' 'INFO'
        & $writeRuntimeSafe 'No more tasks to do.' 'INFO'
        & $completeRun
        return $true
    }

    & $startNext
    return $true
}

function Find-QOTControlByNameDeep {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Root -or [string]::IsNullOrWhiteSpace($Name)) { return $null }

    try {
        if ($Root -is [System.Windows.FrameworkElement]) {
            $direct = $Root.FindName($Name)
            if ($direct) { return $direct }
        }
    } catch { }

    $visited = New-Object 'System.Collections.Generic.HashSet[int]'
    $q = New-Object 'System.Collections.Generic.Queue[System.Object]'
    $q.Enqueue($Root) | Out-Null

    while ($q.Count -gt 0) {
        $cur = $q.Dequeue()
        if (-not $cur) { continue }

        $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
        if (-not $visited.Add($objId)) { continue }

        if ($cur -is [System.Windows.FrameworkElement]) {
            if ($cur.Name -eq $Name) { return $cur }
            try {
                $withinScope = $cur.FindName($Name)
                if ($withinScope) { return $withinScope }
            } catch { }
        } elseif ($cur -is [System.Windows.FrameworkContentElement]) {
            if ($cur.Name -eq $Name) { return $cur }
        }

        try {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                if ($child) { $q.Enqueue($child) | Out-Null }
            }
        } catch { }

        if ($cur -is [System.Windows.DependencyObject]) {
            try {
                $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur)
                for ($i = 0; $i -lt $count; $i++) {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                }
            } catch { }
        }
    }

    return $null
}

function Show-QOTStartupErrorBanner {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string]$Message
    )

    $banner = Find-QOTControlByNameDeep -Root $Window -Name "ExecutionMessage"
    if (-not $banner) {
        Write-QOTStartupTrace ("Startup error banner control not found. Message: {0}" -f $Message) 'ERROR'
        return
    }

    $banner.Text = $Message
    $banner.Visibility = [System.Windows.Visibility]::Visible
}

function Add-QOTStartupIssue {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Issues,
        [Parameter(Mandatory)][string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $Issues.Add($Message) | Out-Null
}

function Open-QOTHiddenTab {
    param(
        [Parameter(Mandatory)]$Tabs,
        [Parameter(Mandatory)]$Tab
    )

    if (-not $Tabs -or -not $Tab) { return }

    $Tabs.SelectedItem = $Tab
}

function Get-QOTNamedElementsMap {
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root
    )

    $map = @{}

    try {
        # Track visited objects by identity hash so a tree containing a cycle
        # (or a node that legitimately appears in both visual and logical
        # parents) cannot cause an infinite BFS. Without this guard, a
        # pathological tree would loop until the dispatcher killed it.
        $visited = New-Object 'System.Collections.Generic.HashSet[int]'
        $maxVisited = 10000  # Hard ceiling - real trees are far smaller
        $q = New-Object 'System.Collections.Generic.Queue[System.Windows.DependencyObject]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            if ($visited.Count -ge $maxVisited) {
                try { Write-QOTStartupTrace ("Named element map walk aborted - visited {0} nodes (limit {1}). Possible visual tree cycle." -f $visited.Count, $maxVisited) 'WARN' } catch { }
                break
            }

            $cur = $q.Dequeue()
            if (-not $cur) { continue }

            $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
            if (-not $visited.Add($objId)) { continue }

            if ($cur -is [System.Windows.FrameworkElement]) {
                $n = $cur.Name
                if (-not [string]::IsNullOrWhiteSpace($n)) {
                    if (-not $map.ContainsKey($n)) {
                        $map[$n] = $cur.GetType().FullName
                    }
                }
            }

            $count = 0
            try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }

            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                } catch { }
            }
        }
    } catch { }

    return $map
}

function Get-QOTNamedElementsSnapshot {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [int]$MaxCount = 30
    )

    $result = New-Object System.Collections.ArrayList
    $seenNames = New-Object 'System.Collections.Generic.HashSet[string]'
    $visited = New-Object 'System.Collections.Generic.HashSet[int]'
    $queue = New-Object 'System.Collections.Generic.Queue[System.Object]'
    $queue.Enqueue($Root) | Out-Null

    while ($queue.Count -gt 0 -and $result.Count -lt $MaxCount) {
        $cur = $queue.Dequeue()
        if (-not $cur) { continue }

        $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
        if (-not $visited.Add($objId)) { continue }

        if ($cur -is [System.Windows.FrameworkElement] -or $cur -is [System.Windows.FrameworkContentElement]) {
            $name = $cur.Name
            if (-not [string]::IsNullOrWhiteSpace($name) -and $seenNames.Add($name)) {
                [void]$result.Add([pscustomobject]@{ Name = $name; Type = $cur.GetType().FullName })
            }
        }

        if ($cur -is [System.Windows.DependencyObject]) {
            try {
                foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                    if ($child) { $queue.Enqueue($child) | Out-Null }
                }
            }
            catch {
                Write-QOTStartupTrace ("Named elements snapshot logical-tree walk skipped for {0}: {1}" -f $cur.GetType().FullName, $_.Exception.Message) 'DEBUG'
            }
        }

        if ($cur -is [System.Windows.DependencyObject]) {
            try {
                $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur)
                for ($i = 0; $i -lt $count; $i++) {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $queue.Enqueue($child) | Out-Null }
                }
            } catch { }
        }
    }

    return @($result)
}

$script:MainWindowAllowClose = $false
$script:MainWindowCloseReason = $null
$script:MainWindowNativeHook = $null
$script:MainWindowStartupCloseGuard = [System.Diagnostics.Stopwatch]::StartNew()
$script:MainWindowUnexpectedCloseBlocked = $false

function Request-QOTMainWindowClose {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [string]$Reason = "InternalRequest"
    )

    $script:MainWindowAllowClose = $true
    $script:MainWindowCloseReason = $Reason
    $Window.Close()
}

function Sync-QOTWindowChromeButtons {
    param(
        [AllowNull()][System.Windows.Window]$Window,
        [AllowNull()]$MaximizeButton,
        [AllowNull()]$MaximizeGlyph
    )

    if (-not $Window) { return }

    $isMaximized = $false
    try { $isMaximized = ($Window.WindowState -eq [System.Windows.WindowState]::Maximized) } catch { $isMaximized = $false }

    if ($MaximizeGlyph) {
        try { $MaximizeGlyph.Text = $(if ($isMaximized) { [string][char]0xE923 } else { [string][char]0xE922 }) } catch { }
    }

    if ($MaximizeButton) {
        try { $MaximizeButton.ToolTip = $(if ($isMaximized) { "Restore" } else { "Maximise" }) } catch { }
    }
}

function Write-QOTWindowVisibilityDiagnostics {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [string]$Prefix = "MainWindow"
    )

    $diagnostic = "{0} visibility: IsVisible={1}; Visibility={2}; WindowState={3}; Left={4}; Top={5}; Width={6}; Height={7}; Opacity={8}; ShowInTaskbar={9}" -f `
        $Prefix, $Window.IsVisible, $Window.Visibility, $Window.WindowState, $Window.Left, $Window.Top, $Window.Width, $Window.Height, $Window.Opacity, $Window.ShowInTaskbar
    Write-QOTStartupTrace $diagnostic

    $app = [System.Windows.Application]::Current
    if ($app) {
        $currentMainWindowType = if ($app.MainWindow) { $app.MainWindow.GetType().FullName } else { '<null>' }
        Write-QOTStartupTrace ("Application.Current.MainWindow currently: {0}" -f $currentMainWindowType)
    } else {
        Write-QOTStartupTrace "Application.Current is null while logging visibility diagnostics" 'WARN'
    }
}

function Ensure-QOTWpfApplication {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [switch]$PreserveExplicitShutdown
    )

    $existing = [System.Windows.Application]::Current
    if ($existing) {
        $isBootstrapApplication = (-not $existing.MainWindow) -and ($existing.Windows.Count -eq 0)
        Write-QOTStartupTrace ("Using existing WPF Application instance: {0}" -f $existing.GetType().FullName)
        if ((-not $PreserveExplicitShutdown) -and ($existing.ShutdownMode -ne [System.Windows.ShutdownMode]::OnMainWindowClose)) {
            $existing.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
            Write-QOTStartupTrace ("Application.Current.ShutdownMode forced to: {0}" -f $existing.ShutdownMode) 'WARN'
        }
        if (-not $existing.MainWindow -or -not [object]::ReferenceEquals($existing.MainWindow, $Window)) {
            $existing.MainWindow = $Window
            Write-QOTStartupTrace ("Application.Current.MainWindow assigned to: {0}" -f $Window.GetType().FullName)
        }

        return [pscustomobject]@{
            Application = $existing
            CreatedHere = $false
            BootstrapOnly = $isBootstrapApplication
        }
    }

    $created = [System.Windows.Application]::new()
    $created.ShutdownMode = if ($PreserveExplicitShutdown) {
        [System.Windows.ShutdownMode]::OnExplicitShutdown
    } else {
        [System.Windows.ShutdownMode]::OnMainWindowClose
    }
    $created.MainWindow = $Window
    Write-QOTStartupTrace ("Created new WPF Application instance: {0}" -f $created.GetType().FullName)
    Write-QOTStartupTrace ("Application.Current.MainWindow assigned to: {0}" -f $Window.GetType().FullName)

    return [pscustomobject]@{
        Application = $created
        CreatedHere = $true
        BootstrapOnly = $false
    }
}

function Register-QOTGlobalExceptionGuards {
    param(
        [Parameter(Mandatory)][System.Windows.Application]$Application
    )

    if ($script:GlobalExceptionHandlersRegistered) {
        return
    }

    $script:DispatcherUnhandledExceptionHandler = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler]{
        param($sender, $eventArgs)

        try {
            $exceptionText = if ($eventArgs.Exception) {
                Get-QOTExceptionReport -Exception $eventArgs.Exception
            }
            else {
                "DispatcherUnhandledException fired without an Exception payload."
            }

            Write-QOTStartupTrace ("Unhandled dispatcher exception intercepted; keeping MainWindow alive.`n{0}" -f $exceptionText) 'ERROR'
            try { Write-QLog ("Unhandled dispatcher exception intercepted; keeping MainWindow alive.`n{0}" -f $exceptionText) 'ERROR' } catch { }

            $eventArgs.Handled = $true
        }
        catch {
            try { $eventArgs.Handled = $true } catch { }
        }
    }
    $Application.add_DispatcherUnhandledException($script:DispatcherUnhandledExceptionHandler)

    $script:AppDomainUnhandledExceptionHandler = [System.UnhandledExceptionEventHandler]{
        param($sender, $eventArgs)

        try {
            $exceptionObject = $eventArgs.ExceptionObject
            $exceptionText = if ($exceptionObject -is [System.Exception]) {
                Get-QOTExceptionReport -Exception $exceptionObject
            }
            elseif ($exceptionObject) {
                $exceptionObject.ToString()
            }
            else {
                "<null exception object>"
            }

            Write-QOTStartupTrace ("AppDomain unhandled exception observed (IsTerminating={0}).`n{1}" -f $eventArgs.IsTerminating, $exceptionText) 'ERROR'
            try { Write-QLog ("AppDomain unhandled exception observed (IsTerminating={0}).`n{1}" -f $eventArgs.IsTerminating, $exceptionText) 'ERROR' } catch { }
        }
        catch {
        }
    }
    [System.AppDomain]::CurrentDomain.add_UnhandledException($script:AppDomainUnhandledExceptionHandler)

    $script:TaskUnobservedExceptionHandler = [System.EventHandler[System.Threading.Tasks.UnobservedTaskExceptionEventArgs]]{
        param($sender, $eventArgs)

        try {
            $exceptionText = if ($eventArgs.Exception) {
                Get-QOTExceptionReport -Exception $eventArgs.Exception
            }
            else {
                "TaskScheduler.UnobservedTaskException fired without Exception payload."
            }

            Write-QOTStartupTrace ("Unobserved task exception intercepted and marked observed.`n{0}" -f $exceptionText) 'ERROR'
            try { Write-QLog ("Unobserved task exception intercepted and marked observed.`n{0}" -f $exceptionText) 'ERROR' } catch { }
            $eventArgs.SetObserved()
        }
        catch {
        }
    }
    [System.Threading.Tasks.TaskScheduler]::add_UnobservedTaskException($script:TaskUnobservedExceptionHandler)

    $script:GlobalExceptionHandlersRegistered = $true
    Write-QOTStartupTrace "Registered global WPF/CLR exception guards for MainWindow stability"
}

function Set-QOTWindowSafetyDefaults {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $Window.WindowState = [System.Windows.WindowState]::Normal
    $Window.Visibility = [System.Windows.Visibility]::Visible
    $Window.ShowInTaskbar = $true
    $Window.Opacity = 1

    $virtualLeft = [System.Windows.SystemParameters]::VirtualScreenLeft
    $virtualTop = [System.Windows.SystemParameters]::VirtualScreenTop
    $virtualWidth = [System.Windows.SystemParameters]::VirtualScreenWidth
    $virtualHeight = [System.Windows.SystemParameters]::VirtualScreenHeight

    $hasInvalidLeft = [double]::IsNaN($Window.Left) -or [double]::IsInfinity($Window.Left)
    $hasInvalidTop = [double]::IsNaN($Window.Top) -or [double]::IsInfinity($Window.Top)
    $hasOffscreenLeft = ($Window.Left -lt $virtualLeft) -or ($Window.Left -gt ($virtualLeft + $virtualWidth))
    $hasOffscreenTop = ($Window.Top -lt $virtualTop) -or ($Window.Top -gt ($virtualTop + $virtualHeight))

    if ($hasInvalidLeft -or $hasInvalidTop -or $hasOffscreenLeft -or $hasOffscreenTop) {
        $width = if ($Window.Width -gt 0) { $Window.Width } else { 1200 }
        $height = if ($Window.Height -gt 0) { $Window.Height } else { 800 }
        $Window.Left = $virtualLeft + (($virtualWidth - $width) / 2)
        $Window.Top = $virtualTop + (($virtualHeight - $height) / 2)
    }
}

function Invoke-QOTSplashFadeOut {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$SplashWindow,

        [int]$DurationMs = 350,
        [switch]$Wait
    )

    $startupTraceSafe = {
        param(
            [string]$Message,
            [string]$Level = "INFO"
        )

        try {
            Write-QOTStartupTrace $Message $Level
            return
        } catch { }

        try { Write-QLog ("[STARTUP] {0}" -f $Message) $Level } catch { }
    }.GetNewClosure()

    try {
        if (-not $SplashWindow.Dispatcher.CheckAccess()) {
            $SplashWindow.Dispatcher.Invoke([action]{
                Invoke-QOTSplashFadeOut -SplashWindow $SplashWindow -DurationMs $DurationMs -Wait:$Wait
            }.GetNewClosure())
            return
        }

        & $startupTraceSafe ("Fading out splash window over {0} ms" -f $DurationMs)

        $fadeCompleted = $false
        $waitFrame = $null
        $waitTimer = $null

        $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
        $animation.From = if ($SplashWindow.Opacity -gt 0) { [double]$SplashWindow.Opacity } else { 1.0 }
        $animation.To = 0.0
        $animation.Duration = [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds([Math]::Max(50, $DurationMs)))
        $animation.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop

        $animation.Add_Completed({
            try {
                $SplashWindow.Opacity = 0
                $SplashWindow.Close()
                & $startupTraceSafe "Splash window fade-out completed and window closed"
            }
            catch {
                & $startupTraceSafe ("Splash close after fade failed: {0}" -f $_.Exception.Message) 'WARN'
            }
            finally {
                $fadeCompleted = $true
                if ($waitFrame) {
                    try { $waitFrame.Continue = $false } catch { }
                }
                if ($waitTimer) {
                    try { $waitTimer.Stop() } catch { }
                }
            }
        }.GetNewClosure())

        $SplashWindow.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animation)

        if ($Wait) {
            $waitFrame = New-Object System.Windows.Threading.DispatcherFrame
            $waitTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $waitTimer.Interval = [System.TimeSpan]::FromMilliseconds([Math]::Max(500, ($DurationMs + 1000)))
            $waitTimer.Add_Tick({
                param($sender, $args)
                try { $sender.Stop() } catch { }
                if (-not $fadeCompleted) {
                    & $startupTraceSafe "Splash fade wait timed out; forcing close." 'WARN'
                    try {
                        $SplashWindow.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
                    } catch { }
                    try { $SplashWindow.Opacity = 0 } catch { }
                    try { $SplashWindow.Close() } catch { }
                    $fadeCompleted = $true
                }
                try { $waitFrame.Continue = $false } catch { }
            }.GetNewClosure())
            try { Register-QOTMainWindowTimer -Timer $waitTimer } catch { }
            $waitTimer.Start()
            [System.Windows.Threading.Dispatcher]::PushFrame($waitFrame)
        }
    }
    catch {
        & $startupTraceSafe ("Splash fade-out failed, closing immediately: {0}" -f $_.Exception.Message) 'WARN'
        try { $SplashWindow.Close() } catch { }
    }
}

function Invoke-QOTMainWindowFadeIn {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [int]$DurationMs = 260,
        [double]$StartOpacity = 0.0
    )

    try {
        if (-not $Window.Dispatcher.CheckAccess()) {
            $Window.Dispatcher.Invoke([action]{
                Invoke-QOTMainWindowFadeIn -Window $Window -DurationMs $DurationMs -StartOpacity $StartOpacity
            }.GetNewClosure())
            return
        }

        $safeStart = [Math]::Max(0.0, [Math]::Min(1.0, [double]$StartOpacity))
        $Window.Opacity = $safeStart

        $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
        $animation.From = $safeStart
        $animation.To = 1.0
        $animation.Duration = [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds([Math]::Max(80, $DurationMs)))
        $animation.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $animation.Add_Completed({
            try {
                $Window.Opacity = 1.0
            } catch { }
        })
        $Window.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animation)
    }
    catch {
        try { $Window.Opacity = 1.0 } catch { }
    }
}

function Start-QOTMainWindow {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $SplashWindow,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Issues = @(),

        [switch]$WarmupOnly,
        [switch]$PassThru
    )

    $basePath = Join-Path $PSScriptRoot ".."
    $startupIssues = New-Object 'System.Collections.Generic.List[string]'
    foreach ($issue in @($Issues)) {
        if ([string]::IsNullOrWhiteSpace($issue)) { continue }
        $startupIssues.Add($issue) | Out-Null
    }
    if (-not $script:MainWindowStartupCloseGuard) {
        $script:MainWindowStartupCloseGuard = [System.Diagnostics.Stopwatch]::StartNew()
    }
    else {
        $script:MainWindowStartupCloseGuard.Restart()
    }
    $script:MainWindowUnexpectedCloseBlocked = $false
    # ------------------------------------------------------------
    # Core modules
    # ------------------------------------------------------------
    Invoke-QOTStartupStep "Core module imports" {
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Config\Config.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Logging\Logging.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Settings.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Tickets.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Actions\ActionRegistry.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Actions\ActionsCatalog.psm1") -Optional
    }

    # ------------------------------------------------------------
    # Apps modules (data + engine)
    # ------------------------------------------------------------
    $appsModuleImports = @(
        @{ Name = "Apps\InstalledApps.psm1"; Path = (Join-Path $basePath "Apps\InstalledApps.psm1") },
        @{ Name = "Apps\InstallCommonApps.psm1"; Path = (Join-Path $basePath "Apps\InstallCommonApps.psm1") }
    )

    foreach ($moduleSpec in $appsModuleImports) {
        try {
            Invoke-QOTStartupStep ("Import {0}" -f $moduleSpec.Name) {
                Import-QOTModuleIfNeeded -Path $moduleSpec.Path
            }
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace (("Failed to import {0}; continuing startup.`n{1}" -f $moduleSpec.Name, $errorDetail)) 'ERROR'
            try { Write-QLog (("Failed to import {0}; continuing startup.`n{1}" -f $moduleSpec.Name, $errorDetail)) "ERROR" } catch { }
            Add-QOTStartupIssue -Issues $startupIssues -Message ("Module failed to load: {0}" -f $moduleSpec.Name)
        }
    }

    # ------------------------------------------------------------
    # UI modules (import if not already loaded)
    # ------------------------------------------------------------
    $uiModuleImports = @(
        @{ Name = "Tickets\Tickets.UI.psm1"; Path = (Join-Path $basePath "Tickets\Tickets.UI.psm1"); Global = $true },
        @{ Name = "UI\HelpWindow.UI.psm1"; Path = (Join-Path $basePath "UI\HelpWindow.UI.psm1") },
        @{ Name = "Core\Settings\Settings.UI.psm1"; Path = (Join-Path $basePath "Core\Settings\Settings.UI.psm1") },
        @{ Name = "Apps\Apps.UI.psm1"; Path = (Join-Path $basePath "Apps\Apps.UI.psm1") },
        @{ Name = "TweaksAndCleaning\CleaningAndMain\TweaksAndCleaning.UI.psm1"; Path = (Join-Path $basePath "TweaksAndCleaning\CleaningAndMain\TweaksAndCleaning.UI.psm1") },
        @{ Name = "Advanced\AdvancedTweaks\AdvancedTweaks.UI.psm1"; Path = (Join-Path $basePath "Advanced\AdvancedTweaks\AdvancedTweaks.UI.psm1") }
    )

    foreach ($moduleSpec in $uiModuleImports) {
        try {
            Invoke-QOTStartupStep ("Import {0}" -f $moduleSpec.Name) {
                if ($moduleSpec.Global) {
                    Import-QOTModuleIfNeeded -Path $moduleSpec.Path -Global
                }
                else {
                    Import-QOTModuleIfNeeded -Path $moduleSpec.Path
                }
            }
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace (("Failed to import {0}; continuing startup.`n{1}" -f $moduleSpec.Name, $errorDetail)) 'ERROR'
            try { Write-QLog (("Failed to import {0}; continuing startup.`n{1}" -f $moduleSpec.Name, $errorDetail)) "ERROR" } catch { }
            Add-QOTStartupIssue -Issues $startupIssues -Message ("Module failed to load: {0}" -f $moduleSpec.Name)
        }
    }

    if (-not (Get-Command Write-QOTicketsUILog -ErrorAction SilentlyContinue)) {
        function global:Write-QOTicketsUILog {
            param(
                [Parameter(Mandatory = $true)][string]$Message,
                [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
            )

            try {
                if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                    Write-QLog $Message $Level
                    return
                }
            } catch { }

                        try { Write-QOTRuntimeLogSafe ("[Tickets.UI] " + $Level + ": " + $Message) $Level } catch { }
        }
    }

    # ------------------------------------------------------------
    # Load MainWindow XAML
    # ------------------------------------------------------------
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # Ensure there is a WPF Application before showing the splash window.
    # Keeping startup in explicit shutdown mode prevents the process from
    # tearing down when the intro splash closes while the main window is
    # still transitioning to visible.
    $startupAppCreatedHere = $false
    $startupApp = [System.Windows.Application]::Current
    if (-not $startupApp) {
        $startupApp = [System.Windows.Application]::new()
        $startupAppCreatedHere = $true
        Write-QOTStartupTrace "Created WPF Application instance during intro bootstrap."
    }
    if ($startupApp.ShutdownMode -ne [System.Windows.ShutdownMode]::OnExplicitShutdown) {
        $startupApp.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
        Write-QOTStartupTrace ("Intro set Application.ShutdownMode to {0}." -f $startupApp.ShutdownMode)
    }

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "MainWindow.xaml not found at $xamlPath"
    }
    Write-QOTStartupTrace "START MainWindow build begin"
    try { Write-QLog ("Loading XAML from: {0}" -f $xamlPath) "DEBUG" } catch { }

    try {
        $xaml   = Get-Content -LiteralPath $xamlPath -Raw
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
        Import-QOTSharedThemeDictionary -Root $window -DictionaryPath (Join-Path $PSScriptRoot "Themes\SharedTheme.xaml")
        Write-QOTStartupTrace "Loaded XAML OK"
        Write-QOTStartupTrace "XAML load OK"
        Write-QOTStartupTrace "InitializeComponent OK"
    }
    catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("MainWindow XAML load failed from {0}`n{1}" -f $xamlPath, $errorDetail) 'ERROR'
        try { Write-QLog ("MainWindow XAML load failed from {0}`n{1}" -f $xamlPath, $errorDetail) "ERROR" } catch { }
        throw
    }

    if (-not $window) {
        throw "Failed to load MainWindow from XAML"
    }

    Initialize-QOTTaskbarIdentity -Window $window
    try {
        $window.Add_SourceInitialized({
            try {
                Initialize-QOTTaskbarIdentity -Window $window
            } catch { }
        }.GetNewClosure())
    } catch { }

    Write-QOTStartupTrace ("MainWindow XAML path: {0}" -f ([System.IO.Path]::GetFullPath($xamlPath)))
    Write-QOTStartupTrace ("MainWindow root type: {0}" -f $window.GetType().FullName)
    try {
        $namedSnapshot = Get-QOTNamedElementsSnapshot -Root $window -MaxCount 30
        if ($namedSnapshot.Count -gt 0) {
            Write-QOTStartupTrace ("First {0} named elements: {1}" -f $namedSnapshot.Count, (($namedSnapshot | ForEach-Object { "{0}<{1}>" -f $_.Name, $_.Type }) -join ', '))
        }
        else {
            Write-QOTStartupTrace "First named elements: none discovered" 'WARN'
        }
    } catch {
        Write-QOTStartupTrace ("Failed to enumerate named elements snapshot: {0}" -f $_.Exception.Message) 'WARN'
    }

    $script:MainWindow = $window
    $applicationState = Ensure-QOTWpfApplication -Window $window -PreserveExplicitShutdown:$WarmupOnly
    $app = $applicationState.Application
    
    # Intro typically creates a bootstrap Application + shows the splash before
    # MainWindow startup begins. In that state, ShowDialog() can return
    # immediately in some hosts, leaving no visible main UI.
    #
    # When the only existing WPF window is the splash, treat this process as a
    # bootstrap launch and prefer app.Run(mainWindow) for a stable primary loop.
    $splashOnlyWindowBootstrap = $false
    if ($SplashWindow -and $app) {
        try {
            $currentWindows = @($app.Windows)
            if ($currentWindows.Count -eq 1 -and [object]::ReferenceEquals($currentWindows[0], $SplashWindow)) {
                $splashOnlyWindowBootstrap = $true
                Write-QOTStartupTrace "Detected splash-only bootstrap state; forcing app.Run(mainWindow) path."
            }
        }
        catch {
            Write-QOTStartupTrace ("Failed to inspect current WPF window set before launch: {0}" -f $_.Exception.Message) 'WARN'
        }
    }

    $appCreatedHere = [bool]($applicationState.CreatedHere -or $startupAppCreatedHere -or $applicationState.BootstrapOnly -or $splashOnlyWindowBootstrap)
    Register-QOTGlobalExceptionGuards -Application $app

    if (-not [System.Windows.Application]::Current) {
        Write-QOTStartupTrace "Application.Current is unexpectedly null after Ensure-QOTWpfApplication" 'ERROR'
        throw "WPF Application instance was not available after initialisation."
    }
    $script:SummaryTextBlock = Find-QOTControlByNameDeep -Root $script:MainWindow -Name "SummaryText"

    $window.Add_Loaded({
        Write-QOTStartupTrace "MainWindow.Loaded fired"
    })
    $window.Add_ContentRendered({
        Write-QOTStartupTrace "MainWindow ContentRendered event fired"
    })

    if (Get-Command Clear-QOTActionGroups -ErrorAction SilentlyContinue) {
        Clear-QOTActionGroups
    }
    if (Get-Command Clear-QOTActionDefinitions -ErrorAction SilentlyContinue) {
        Clear-QOTActionDefinitions
    }

    $requiredControls = @(
        "MainTabControl","BtnPlay","AppsGrid","InstallGrid",
        "TicketsGrid","BtnNewTicket","BtnDeleteTicket",
        "SettingsHost","HelpHost","TabTickets"
    )
    $controlResolution = Invoke-QOTControlResolution -Root $script:MainWindow -Names $requiredControls
    $resolvedControls = $controlResolution.Resolved
    $missingControls = @($controlResolution.Missing)

    try {
        foreach ($controlName in $requiredControls) {
            if ($resolvedControls.ContainsKey($controlName)) {
                $controlType = $resolvedControls[$controlName].GetType().FullName
                Write-QOTStartupTrace ("Control resolved from MainWindow instance: {0} ({1})" -f $controlName, $controlType) 'DEBUG'
            }
            else {
                Write-QOTStartupTrace ("Control unresolved from MainWindow instance: {0}" -f $controlName) 'WARN'
            }
        }
    } catch { }

    if ($missingControls.Count -eq 0) {
        Write-QOTStartupTrace ("UI controls resolved: OK ({0}/{1})" -f $resolvedControls.Count, $requiredControls.Count)
    } else {
        Write-QOTStartupTrace ("UI controls resolution FAILED ({0}/{1}). Missing: {2}" -f $resolvedControls.Count, $requiredControls.Count, ($missingControls -join ', ')) 'WARN'
    }

    $criticalRequiredControls = @("BtnPlay", "MainTabControl")
    $criticalMissing = @($criticalRequiredControls | Where-Object { -not $resolvedControls.ContainsKey($_) })
    $hasCriticalResolutionFailure = ($criticalMissing.Count -gt 0)
    if ($hasCriticalResolutionFailure) {
        $fatalMessage = "Critical UI controls missing: {0}. Modules (Apps/Tickets/Tweaks) will not be wired." -f ($criticalMissing -join ', ')
        Write-QOTStartupTrace $fatalMessage 'ERROR'
        try { Write-QLog $fatalMessage 'ERROR' } catch { }
        Show-QOTStartupErrorBanner -Window $window -Message $fatalMessage
    }

    $extraControlResolution = Invoke-QOTControlResolution -Root $script:MainWindow -Names @("TabApps","TabCleaning","TabAdvanced","BtnPlayProgressPath","BtnPlayProgressClip","ExecutionMessage","BtnLogs","BtnSettings","BtnHelp","TabHelp","TabSettings","CbQuickSafeCleanup","BtnNavCleaning","BtnNavApps","BtnNavAdvanced","BtnNavTickets","RailIconHost","RailShellGrid","TicketsRailSubmenu","BtnRailTicketBack","BtnRailTicketNew","BtnRailTicketDelete","BtnRailTicketFilter","BtnToggleTicketDetails","BtnNewTicket","BtnDeleteTicket","BtnTicketsFilterMenu","CustomTitleBarHost","WindowDragSurface","HeaderContentDragSurface","BtnWindowMinimize","BtnWindowMaximize","BtnWindowMaximizeGlyph","BtnWindowClose","WindowTitleIcon")
    foreach ($kv in $extraControlResolution.Resolved.GetEnumerator()) {
        if (-not $resolvedControls.ContainsKey($kv.Key)) {
            $resolvedControls[$kv.Key] = $kv.Value
        }
    }

    $tabs         = $resolvedControls["MainTabControl"]
    $tabCleaning  = $resolvedControls["TabCleaning"]
    $tabApps      = $resolvedControls["TabApps"]
    $tabAdvanced  = $resolvedControls["TabAdvanced"]
    $tabTickets   = $resolvedControls["TabTickets"]
    $tabHelp      = $resolvedControls["TabHelp"]
    $tabSettings  = $resolvedControls["TabSettings"]
    $btnNavByTab  = [ordered]@{
        TabCleaning = $resolvedControls["BtnNavCleaning"]
        TabApps     = $resolvedControls["BtnNavApps"]
        TabAdvanced = $resolvedControls["BtnNavAdvanced"]
        TabTickets  = $resolvedControls["BtnNavTickets"]
    }
    $btnHelpNav = $resolvedControls["BtnHelp"]
    $btnSettingsNav = $resolvedControls["BtnSettings"]
    $railIconHost = $resolvedControls["RailIconHost"]
    $railShellGrid = $resolvedControls["RailShellGrid"]
    $ticketsRailSubmenu = $resolvedControls["TicketsRailSubmenu"]
    $btnRailTicketBack = $resolvedControls["BtnRailTicketBack"]
    $btnRailTicketNew = $resolvedControls["BtnRailTicketNew"]
    $btnRailTicketDelete = $resolvedControls["BtnRailTicketDelete"]
    $btnRailTicketFilter = $resolvedControls["BtnRailTicketFilter"]
    $btnTicketBack = $resolvedControls["BtnToggleTicketDetails"]
    $btnTicketNew = $resolvedControls["BtnNewTicket"]
    $btnTicketDelete = $resolvedControls["BtnDeleteTicket"]
    $btnTicketFilter = $resolvedControls["BtnTicketsFilterMenu"]
    $customTitleBarHost = $resolvedControls["CustomTitleBarHost"]
    $windowDragSurface = $resolvedControls["WindowDragSurface"]
    $headerContentDragSurface = $resolvedControls["HeaderContentDragSurface"]
    $btnWindowMinimize = $resolvedControls["BtnWindowMinimize"]
    $btnWindowMaximize = $resolvedControls["BtnWindowMaximize"]
    $btnWindowMaximizeGlyph = $resolvedControls["BtnWindowMaximizeGlyph"]
    $btnWindowClose = $resolvedControls["BtnWindowClose"]
    $findTabByNameCmd = ${function:Find-QOTTabByName}
    $syncRailNavigationStateCmd = ${function:Sync-QOTRailNavigationState}
    $setTicketsRailSubmenuStateCmd = ${function:Set-QOTTicketsRailSubmenuState}

    $syncRailNavigationSafe = {
        try {
            & $syncRailNavigationStateCmd -Tabs $tabs -ButtonsByTabName $btnNavByTab -HelpButton $btnHelpNav -SettingsButton $btnSettingsNav -HelpTab $tabHelp -SettingsTab $tabSettings
        } catch { }
        try {
            $selectedTabName = ""
            try { if ($tabs.SelectedItem) { $selectedTabName = [string]$tabs.SelectedItem.Name } } catch { $selectedTabName = "" }
            if ($selectedTabName -ne "TabTickets") {
                & $setTicketsRailSubmenuStateCmd -Submenu $ticketsRailSubmenu -TicketsButton $btnNavByTab["TabTickets"] -Container $railShellGrid -IsOpen $false
            }
        } catch { }
    }.GetNewClosure()

    $syncWindowChromeButtonsSafe = {
        try {
            Sync-QOTWindowChromeButtons -Window $window -MaximizeButton $btnWindowMaximize -MaximizeGlyph $btnWindowMaximizeGlyph
        } catch { }
    }.GetNewClosure()

    $toggleWindowStateSafe = {
        try {
            if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) {
                $window.WindowState = [System.Windows.WindowState]::Normal
            }
            else {
                $window.WindowState = [System.Windows.WindowState]::Maximized
            }
        } catch { }
        & $syncWindowChromeButtonsSafe
    }.GetNewClosure()

    $isWindowChromeButtonSource = {
        param([AllowNull()]$Element)

        $current = $Element
        while ($current) {
            try {
                if ($current -is [System.Windows.Controls.Button]) {
                    $currentName = ""
                    try { $currentName = [string]$current.Name } catch { $currentName = "" }
                    if ($currentName -in @("BtnWindowMinimize","BtnWindowMaximize","BtnWindowClose")) {
                        return $true
                    }
                }
            } catch { }

            $parentNode = $null
            try {
                if ($current -is [System.Windows.Media.Visual] -or $current -is [System.Windows.Media.Media3D.Visual3D]) {
                    $parentNode = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
                }
            } catch { $parentNode = $null }
            if (-not $parentNode) {
                try { $parentNode = [System.Windows.LogicalTreeHelper]::GetParent($current) } catch { $parentNode = $null }
            }
            $current = $parentNode
        }

        return $false
    }.GetNewClosure()

    if ($btnWindowMinimize) {
        $btnWindowMinimize.Add_Click({
            try { $window.WindowState = [System.Windows.WindowState]::Minimized } catch { }
        }.GetNewClosure())
    }

    if ($btnWindowMaximize) {
        $btnWindowMaximize.Add_Click({
            & $toggleWindowStateSafe
        }.GetNewClosure())
    }

    if ($btnWindowClose) {
        $btnWindowClose.Add_Click({
            try {
                $script:MainWindowAllowClose = $true
                $script:MainWindowCloseReason = "CustomTitleBarCloseButton"
                $window.Close()
            } catch { }
        }.GetNewClosure())
    }

    foreach ($dragSurface in @($windowDragSurface, $headerContentDragSurface)) {
        if (-not $dragSurface) { continue }
        $dragSurface.Add_PreviewMouseLeftButtonDown({
            param($sender, $args)
            if (& $isWindowChromeButtonSource -Element $args.OriginalSource) { return }

            if ($args.ClickCount -ge 2) {
                & $toggleWindowStateSafe
                try { $args.Handled = $true } catch { }
                return
            }

            try {
                $window.DragMove()
                $args.Handled = $true
            } catch { }
        }.GetNewClosure())
    }

    $window.Add_StateChanged({
        & $syncWindowChromeButtonsSafe
    }.GetNewClosure())
    & $syncWindowChromeButtonsSafe

    if ($tabs) {
        Apply-QOTMainTabVisibilityFromSettings -Tabs $tabs
        Restore-QOTSelectedTabMemory -Tabs $tabs

        if ($railIconHost) {
            try {
                $savedRailOrder = @(Get-QOTSavedRailIconOrder)
                $appliedRailOrder = Apply-QOTRailIconOrder -Host $railIconHost -Order $savedRailOrder
                Register-QOTRailIconReordering -Host $railIconHost
                Save-QOTRailIconOrder -Order $appliedRailOrder
            } catch { }
        }

        try {
            if ($script:MainTabSelectionMemoryHandler) {
                $tabs.RemoveHandler([System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent, $script:MainTabSelectionMemoryHandler)
            }
        } catch { }

        $script:MainTabSelectionMemoryHandler = [System.Windows.Controls.SelectionChangedEventHandler]{
            param($sender, $eventArgs)
            try { Save-QOTSelectedTabMemory -Tabs $tabs } catch { }
            & $syncRailNavigationSafe
        }.GetNewClosure()

        try {
            $tabs.AddHandler([System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent, $script:MainTabSelectionMemoryHandler)
        } catch { }

        foreach ($entry in $btnNavByTab.GetEnumerator()) {
            $button = $entry.Value
            if (-not $button) { continue }

            $targetTabName = [string]$entry.Key
            $button.Add_Click({
                $targetTab = $null
                if ($findTabByNameCmd) {
                    $targetTab = & $findTabByNameCmd -Tabs $tabs -Name $targetTabName
                }
                if (-not $targetTab) { return }
                try {
                    if ($targetTab.Visibility -eq [System.Windows.Visibility]::Visible) {
                        $shouldOpenTicketsSubmenu = $false
                        if ($targetTabName -eq "TabTickets") {
                            $isAlreadySelected = ($tabs.SelectedItem -eq $targetTab)
                            $submenuOpen = $false
                            try { $submenuOpen = ($ticketsRailSubmenu.Visibility -eq [System.Windows.Visibility]::Visible) } catch { $submenuOpen = $false }
                            $shouldOpenTicketsSubmenu = (-not $isAlreadySelected) -or (-not $submenuOpen)
                        }
                        $tabs.SelectedItem = $targetTab
                        if ($targetTabName -eq "TabTickets") {
                            & $setTicketsRailSubmenuStateCmd -Submenu $ticketsRailSubmenu -TicketsButton $btnNavByTab["TabTickets"] -Container $railShellGrid -IsOpen $shouldOpenTicketsSubmenu
                        }
                        else {
                            & $setTicketsRailSubmenuStateCmd -Submenu $ticketsRailSubmenu -TicketsButton $btnNavByTab["TabTickets"] -Container $railShellGrid -IsOpen $false
                        }
                    }
                } catch { }
                & $syncRailNavigationSafe
            }.GetNewClosure())
        }

        $keepTicketsRailSubmenuOpenSafe = {
            try {
                $selectedTabName = ""
                try { if ($tabs.SelectedItem) { $selectedTabName = [string]$tabs.SelectedItem.Name } } catch { $selectedTabName = "" }
                $shouldStayOpen = ($selectedTabName -eq "TabTickets")
                & $setTicketsRailSubmenuStateCmd -Submenu $ticketsRailSubmenu -TicketsButton $btnNavByTab["TabTickets"] -Container $railShellGrid -IsOpen $shouldStayOpen
            } catch { }
        }.GetNewClosure()

        if ($btnRailTicketBack -and $btnTicketBack) {
            $btnRailTicketBack.Add_Click({
                try {
                    if ((-not $WarmupOnly) -and $btnTicketBack.IsEnabled) {
                        $btnTicketBack.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    }
                } catch { }
                & $keepTicketsRailSubmenuOpenSafe
            }.GetNewClosure())
        }

        if ($btnRailTicketNew -and $btnTicketNew) {
            $btnRailTicketNew.Add_Click({
                try {
                    if ((-not $WarmupOnly) -and $btnTicketNew.IsEnabled) {
                        $btnTicketNew.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    }
                } catch { }
                & $keepTicketsRailSubmenuOpenSafe
            }.GetNewClosure())
        }

        if ($btnRailTicketDelete -and $btnTicketDelete) {
            $btnRailTicketDelete.Add_Click({
                try {
                    if ((-not $WarmupOnly) -and $btnTicketDelete.IsEnabled) {
                        $btnTicketDelete.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    }
                } catch { }
                & $keepTicketsRailSubmenuOpenSafe
            }.GetNewClosure())
        }

        if ($btnRailTicketFilter -and $btnTicketFilter) {
            $btnRailTicketFilter.Add_Click({
                try {
                    if ($btnTicketFilter.IsEnabled) {
                        $btnTicketFilter.Tag = $btnRailTicketFilter
                        $btnTicketFilter.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    }
                } catch { }
                & $keepTicketsRailSubmenuOpenSafe
            }.GetNewClosure())
        }

        & $syncRailNavigationSafe
    }

    if (-not $WarmupOnly -and $appCreatedHere -and (-not $SplashWindow)) {
        try {
            Write-QOTStartupTrace "Early MainWindow reveal before feature module wiring"
            Set-QOTWindowSafetyDefaults -Window $window
            if (-not $window.IsVisible -or $window.Visibility -ne [System.Windows.Visibility]::Visible) {
                $window.Show()
                # Don't activate - let user continue working
                # $window.Activate() | Out-Null
                Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow early-show"
            }
        }
        catch {
            Write-QOTStartupTrace ("Early MainWindow reveal failed: {0}" -f $_.Exception.Message) 'WARN'
        }
    }

    # ------------------------------------------------------------
    # Initialise Apps UI
    # ------------------------------------------------------------
    if (-not $hasCriticalResolutionFailure) {
        try {
            if (-not (Get-Command Initialize-QOTAppsUI -ErrorAction SilentlyContinue)) {
                throw "Initialize-QOTAppsUI not found. Apps\Apps.UI.psm1 did not load or export correctly."
            }

            Invoke-QOTStartupStep "Initialise Apps UI" { $script:AppsUIInitialised = [bool](Initialize-QOTAppsUI -Window $window) }
            Write-QOTStartupTrace "Initialise Apps UI OK"
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace ("Apps UI failed to load; continuing startup.`n{0}" -f $errorDetail) 'ERROR'
            try { Write-QLog ("Apps UI failed to load; continuing startup.`n{0}" -f $errorDetail) "ERROR" } catch { }
        }

    # ------------------------------------------------------------
    # Initialise Tickets UI
    # ------------------------------------------------------------
        try {
        if (-not (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue)) {
            throw "Initialize-QOTicketsUI not found. Tickets\Tickets.UI.psm1 did not load or export correctly."
        }
        if (-not (Get-Command Invoke-QOTicketsFilterSafely -ErrorAction SilentlyContinue)) {
            throw "Invoke-QOTicketsFilterSafely not found after Tickets UI module import."
        }
        Invoke-QOTStartupStep "Initialise Tickets UI" { $script:TicketsUIInitialised = [bool](Initialize-QOTicketsUI -Window $window) }
        if (Get-Command Initialize-QOTicketsReplyQueueService -ErrorAction SilentlyContinue) {
            Invoke-QOTStartupStep "Rehydrate reply queue" { Initialize-QOTicketsReplyQueueService -Reason "app-startup" | Out-Null }
        }
        }
        catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("Tickets UI failed to load; continuing startup with Tickets disabled.`n{0}" -f $errorDetail) 'ERROR'
        try { Write-QLog ("Tickets UI failed to load; continuing startup with Tickets disabled.`n{0}" -f $errorDetail) "ERROR" } catch { }
        try {
            $logPath = Get-QOTPrimaryLogPath
            $ticketFailureMessage = "Tickets failed to initialise.`r`n`r`n{0}`r`n`r`nLog: {1}" -f $_.Exception.Message, $logPath
            Show-QOTTicketsStartupFailurePanel -Window $window -Message $ticketFailureMessage
        } catch { }
        Add-QOTStartupIssue -Issues $startupIssues -Message "Tickets tools failed to load."
        }

    # ------------------------------------------------------------
    # Initialise Tweaks & Cleaning UI
    # ------------------------------------------------------------
        try {
            if (-not (Get-Command Initialize-QOTActionCatalog -ErrorAction SilentlyContinue)) {
                throw "Initialize-QOTActionCatalog not found. Core\\Actions\\ActionsCatalog.psm1 did not load or export correctly."
            }

            Invoke-QOTStartupStep "Initialise action catalog" { Initialize-QOTActionCatalog }

            Invoke-QOTStartupStep "Validate action catalog initialisation" {
                $actionDefinitionCount = Get-QOTActionDefinitionCount
                if ($actionDefinitionCount -le 0) {
                    throw "Action catalog initialised with zero definitions. Tweaks UI initialisation blocked."
                }
                try {
                    $catalogState = Get-QOTActionCatalogState
                    Write-QLog ("ActionCatalog instance: {0} hash={1} count={2} (after action catalog init before Tweaks UI)" -f $catalogState.TypeName, $catalogState.HashCode, $catalogState.Count) "INFO"
                } catch { }
            }
            
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace ("Action catalog failed to initialise; continuing startup with Tweaks disabled.`n{0}" -f $errorDetail) 'ERROR'
            try { Write-QLog ("Action catalog failed to initialise; continuing startup with Tweaks disabled.`n{0}" -f $errorDetail) "ERROR" } catch { }
            Add-QOTStartupIssue -Issues $startupIssues -Message "Tweaks catalog failed to initialise."
        }

    # ------------------------------------------------------------
    # Initialise Advanced Tweaks UI
    # ------------------------------------------------------------
        try {
            if (-not (Get-Command Initialize-QOTTweaksAndCleaningUI -ErrorAction SilentlyContinue)) {
                throw "Initialize-QOTTweaksAndCleaningUI not found. TweaksAndCleaning.UI.psm1 did not load or export correctly."
            }

            Invoke-QOTStartupStep "Initialise Tweaks UI" { Initialize-QOTTweaksAndCleaningUI -Window $window }
            Write-QOTStartupTrace "Initialise Tweaks UI OK"
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace ("Tweaks/Cleaning UI failed to load; continuing startup with Tweaks disabled.`n{0}" -f $errorDetail) 'ERROR'
            try { Write-QLog ("Tweaks/Cleaning UI failed to load; continuing startup with Tweaks disabled.`n{0}" -f $errorDetail) "ERROR" } catch { }
            Add-QOTStartupIssue -Issues $startupIssues -Message "Tweaks & Cleaning tools failed to load."
        }

    # ------------------------------------------------------------
    # Register action catalog (central ActionId mappings)
    # ------------------------------------------------------------
        try {
            if (-not (Get-Command Initialize-QOTAdvancedTweaksUI -ErrorAction SilentlyContinue)) {
                throw "Initialize-QOTAdvancedTweaksUI not found. AdvancedTweaks.UI.psm1 did not load or export correctly."
            }

            Invoke-QOTStartupStep "Initialise Advanced UI" { Initialize-QOTAdvancedTweaksUI -Window $window }
            Write-QOTStartupTrace "Initialise Advanced UI OK"
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace ("Advanced UI failed to load; continuing startup.`n{0}" -f $errorDetail) 'ERROR'
            try { Write-QLog ("Advanced UI failed to load; continuing startup.`n{0}" -f $errorDetail) "ERROR" } catch { }
        }



    # ------------------------------------------------------------
   # Wire Play button (global action registry)
    # ------------------------------------------------------------
        $btnPlay = $resolvedControls["BtnPlay"]
        $btnLogs = $resolvedControls["BtnLogs"]
        $quickSafeCleanup = $resolvedControls["CbQuickSafeCleanup"]
        $playProgressPath = $resolvedControls["BtnPlayProgressPath"]
        $playProgressClip = $resolvedControls["BtnPlayProgressClip"]
        $executionMessage = $resolvedControls["ExecutionMessage"]
        $runtimeLoggerCmd = Resolve-QOTInvokableCommand -Name "Write-QOTRuntimeLogSafe" -LookupErrorAction SilentlyContinue
        $showTaskResultsCmd = Resolve-QOTInvokableCommand -Name "Show-QOTTaskResultsWindow" -LookupErrorAction SilentlyContinue
    $runtimeLoggerSafe = {
            param(
                [Parameter(Mandatory)][string]$Message,
                [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
            )

            try {
                if ($runtimeLoggerCmd) {
                    if ($runtimeLoggerCmd -is [System.Management.Automation.CommandInfo]) {
                        & $runtimeLoggerCmd -Message $Message -Level $Level
                    } elseif ($runtimeLoggerCmd -is [scriptblock]) {
                        & $runtimeLoggerCmd -Message $Message -Level $Level
                    } else {
                        $resolved = Resolve-QOTInvokableCommand -Name ([string]$runtimeLoggerCmd) -LookupErrorAction SilentlyContinue
                        if ($resolved) {
                            & $resolved -Message $Message -Level $Level
                        } else {
                            throw "Runtime logger command is unavailable."
                        }
                    }
                    return
                }
            } catch { }

            try {
                if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                    Write-QLog $Message $Level
                    return
                }
            } catch { }

            try {
                $fallbackDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"
                New-Item -ItemType Directory -Path $fallbackDir -Force -ErrorAction Stop | Out-Null
                $fallbackPath = Join-Path $fallbackDir "MainWindow.Runtime.log"
                Add-Content -LiteralPath $fallbackPath -Value ("[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message) -Encoding UTF8 -ErrorAction Stop
            } catch { }
        }.GetNewClosure()

    try { Restore-QOTTaskRunState } catch { }

    if ($btnPlay) {
        $setPlayProgressCmd = Resolve-QOTInvokableCommand -Name "Set-QOTPlayProgress" -LookupErrorAction SilentlyContinue
        $setUiEnabledCmd = Resolve-QOTInvokableCommand -Name "Set-QOTUIEnabledState" -LookupErrorAction Stop
        $setHitTestVisibilityCmd = Resolve-QOTInvokableCommand -Name "Set-QOTHitTestVisibility" -LookupErrorAction Stop
        $getSelectedActionsCmd = Resolve-QOTInvokableCommand -Name "Get-QOTSelectedActionsInExecutionOrder" -LookupErrorAction SilentlyContinue
        $testAnyActionsSelectedCmd = Resolve-QOTInvokableCommand -Name "Test-QOTAnyActionsSelected" -LookupErrorAction SilentlyContinue
        $startSelectedTasksAsyncCmd = Resolve-QOTInvokableCommand -Name "Start-QOTSelectedTasksAsync" -LookupErrorAction SilentlyContinue
        $runSelectedTasksCmd = Resolve-QOTInvokableCommand -Name "Run-QOTSelectedTasks" -LookupErrorAction Stop
        $playCompletionSoundCmd = Resolve-QOTInvokableCommand -Name "Invoke-QOTPlayCompletionSound" -LookupErrorAction Stop
        $setPlayProgressSafe = {
            param([double]$Percent)

            try {
                if ($setPlayProgressCmd) {
                    & $setPlayProgressCmd -ProgressPath $playProgressPath -ProgressClip $playProgressClip -Percent $Percent
                    return
                }
            } catch { }

            try {
                if (-not $playProgressPath -or -not $playProgressClip) { return }
                $safePercent = [math]::Max(0, [math]::Min(100, $Percent))
                $width = 34.0
                $height = 34.0
                try { if ([double]$playProgressPath.ActualWidth -gt 0) { $width = [double]$playProgressPath.ActualWidth } } catch { }
                try { if ([double]$playProgressPath.ActualHeight -gt 0) { $height = [double]$playProgressPath.ActualHeight } } catch { }
                if ($width -le 0) { $width = 34.0 }
                if ($height -le 0) { $height = 34.0 }
                $filledWidth = ($width * $safePercent / 100.0)
                $playProgressClip.Rect = New-Object System.Windows.Rect(0, 0, $filledWidth, $height)
            } catch { }
        }.GetNewClosure()

        $null = & $setUiEnabledCmd -Control $btnPlay -IsEnabled $true
        $null = & $setHitTestVisibilityCmd -Control $btnPlay -IsHitTestVisible $true
        & $setPlayProgressSafe 0

        $playClickHandler = [System.Windows.RoutedEventHandler]{
            param($sender, $args)

            & $runtimeLoggerSafe "User clicked Play button" "INFO"
            $playRunCompleted = $false
            $completePlayRun = {
                param([bool]$PlaySound = $true)
                if ($playRunCompleted) { return }
                $playRunCompleted = $true

                if ($script:PlayButtonTimer) {
                    try { $script:PlayButtonTimer.Stop() } catch { }
                    $script:PlayButtonTimer = $null
                }
                & $setPlayProgressSafe 0
                $script:IsPlayRunning = $false
                $null = & $setUiEnabledCmd -Control $btnPlay -IsEnabled $true
                $null = & $setHitTestVisibilityCmd -Control $btnPlay -IsHitTestVisible $true
                if ($PlaySound) {
                    try { & $playCompletionSoundCmd } catch { }
                }
            }.GetNewClosure()

            try {
                if ($script:IsPlayRunning) {
                    & $runtimeLoggerSafe "Play click ignored because tasks are already running." "DEBUG"
                    return
                }

                $activeWindow = $script:MainWindow
                if (-not $activeWindow) {
                    $activeWindow = [System.Windows.Window]::GetWindow($sender)
                }
                if (-not $activeWindow) {
                    throw "Main window reference is not available for Play button execution."
                }

                $selectedCount = $null
                try {
                    if ($getSelectedActionsCmd) {
                        $selectedCount = @(& $getSelectedActionsCmd -Window $activeWindow).Count
                    }
                    elseif ($testAnyActionsSelectedCmd) {
                        $selectedCount = if ([bool](& $testAnyActionsSelectedCmd -Window $activeWindow)) { 1 } else { 0 }
                    }
                }
                catch {
                    $selectedCount = $null
                    & $runtimeLoggerSafe ("Failed to inspect selected actions before Play: {0}" -f $_.Exception.Message) "WARN"
                }

                if ($null -ne $selectedCount -and [int]$selectedCount -le 0) {
                    if ($executionMessage) {
                        $executionMessage.Text = "Select at least one option before pressing Play."
                        $executionMessage.Visibility = [System.Windows.Visibility]::Visible
                    }
                    & $runtimeLoggerSafe "Play click ignored because no actions are selected." "INFO"
                    $script:IsPlayRunning = $false
                    $null = & $setUiEnabledCmd -Control $btnPlay -IsEnabled $true
                    $null = & $setHitTestVisibilityCmd -Control $btnPlay -IsHitTestVisible $true
                    & $setPlayProgressSafe 0
                    return
                }

                if ($executionMessage) {
                    $executionMessage.Visibility = [System.Windows.Visibility]::Collapsed
                    $executionMessage.Text = ""
                }

                $script:IsPlayRunning = $true
                & $setPlayProgressSafe 0

                $null = & $setUiEnabledCmd -Control $btnPlay -IsEnabled $false
                $null = & $setHitTestVisibilityCmd -Control $btnPlay -IsHitTestVisible $false

                $asyncStarted = $false
                if ($startSelectedTasksAsyncCmd) {
                    try {
                        $onCompleted = {
                            try { & $completePlayRun $true } catch { }
                        }.GetNewClosure()
                        $asyncStarted = [bool](& $startSelectedTasksAsyncCmd -Window $activeWindow -ProgressPath $playProgressPath -ProgressClip $playProgressClip -OnCompleted $onCompleted)
                        if ($asyncStarted) {
                            if ($script:PlayButtonTimer) {
                                try { $script:PlayButtonTimer.Stop() } catch { }
                                $script:PlayButtonTimer = $null
                            }

                            $watchdog = [System.Windows.Threading.DispatcherTimer]::new()
                            $watchdog.Interval = [TimeSpan]::FromMilliseconds(350)
                            $watchdog.Add_Tick({
                                if (-not $script:IsPlayRunning) {
                                    try { $watchdog.Stop() } catch { }
                                    $script:PlayButtonTimer = $null
                                    return
                                }

                                if ($script:QOT_TaskRunnerState) {
                                    return
                                }

                                $isDisabled = $false
                                try { $isDisabled = -not [bool]$btnPlay.IsEnabled } catch { $isDisabled = $false }
                                if (-not $isDisabled) {
                                    try { $watchdog.Stop() } catch { }
                                    $script:PlayButtonTimer = $null
                                    return
                                }

                                & $runtimeLoggerSafe "Play button watchdog restoring UI after async runner completed without a clean callback." "WARN"
                                try { $watchdog.Stop() } catch { }
                                $script:PlayButtonTimer = $null
                                try { & $completePlayRun $false } catch { }
                            }.GetNewClosure())

                            $script:PlayButtonTimer = $watchdog
                            try { Register-QOTMainWindowTimer -Timer $script:PlayButtonTimer } catch { }
                            try { $script:PlayButtonTimer.Start() } catch { }
                        }
                    } catch {
                        $asyncStarted = $false
                        & $runtimeLoggerSafe ("Async runner start failed; falling back to sync runner. {0}" -f $_.Exception.Message) "WARN"
                    }
                }

                if (-not $asyncStarted) {
                    & $runSelectedTasksCmd -Window $activeWindow -ProgressPath $playProgressPath -ProgressClip $playProgressClip
                    & $completePlayRun $true
                }
            }
            catch {
                & $runtimeLoggerSafe ("Play button handler failed: {0}" -f $_.Exception.Message) "ERROR"
                & $completePlayRun $false
            }
        }.GetNewClosure()

        $btnPlay.Add_Click($playClickHandler)

        if ($quickSafeCleanup -is [System.Windows.Controls.CheckBox]) {
            $quickSafeActionIds = @(
                "Invoke-QCleanTemp",
                "Invoke-QCleanThumbnailCache",
                "Invoke-QCleanDirectXShaderCache",
                "Invoke-QCleanWERQueue",
                "Invoke-QCleanExplorerRecentItems",
                "Invoke-QCleanWindowsSearchHistory",
                "Invoke-QCleanEdgeCache",
                "Invoke-QCleanChromeCache",
                "Invoke-QCleanTeamsCache"
            )

            try {
                if ($script:QOT_QuickSafeCleanupHandler) {
                    $quickSafeCleanup.Remove_Checked($script:QOT_QuickSafeCleanupHandler)
                }
            } catch { }

            $quickSafeCleanupHandler = [System.Windows.RoutedEventHandler]{
                param($sender, $args)

                if ($script:QOT_QuickSafeCleanupResetInProgress) { return }
                if (-not ($sender -is [System.Windows.Controls.CheckBox]) -or $sender.IsChecked -ne $true) { return }

                & $runtimeLoggerSafe "User clicked Quick clean." "INFO"

                $quickRunCompleted = $false
                $completeQuickRun = {
                    param([bool]$PlaySound = $true)
                    if ($quickRunCompleted) { return }
                    $quickRunCompleted = $true

                    & $setPlayProgressSafe 0
                    $script:IsPlayRunning = $false
                    $null = & $setUiEnabledCmd -Control $btnPlay -IsEnabled $true
                    $null = & $setHitTestVisibilityCmd -Control $btnPlay -IsHitTestVisible $true
                    try { $quickSafeCleanup.IsEnabled = $true } catch { }

                    $script:QOT_QuickSafeCleanupResetInProgress = $true
                    try { $quickSafeCleanup.IsChecked = $false } catch { }
                    finally { $script:QOT_QuickSafeCleanupResetInProgress = $false }

                    if ($PlaySound) {
                        try { & $playCompletionSoundCmd } catch { }
                    }
                }.GetNewClosure()

                try {
                    if ($script:IsPlayRunning) {
                        & $runtimeLoggerSafe "Quick clean ignored because tasks are already running." "DEBUG"
                        $script:QOT_QuickSafeCleanupResetInProgress = $true
                        try { $quickSafeCleanup.IsChecked = $false } catch { }
                        finally { $script:QOT_QuickSafeCleanupResetInProgress = $false }
                        return
                    }

                    $activeWindow = $script:MainWindow
                    if (-not $activeWindow) {
                        $activeWindow = [System.Windows.Window]::GetWindow($sender)
                    }
                    if (-not $activeWindow) {
                        throw "Main window reference is not available for Quick clean execution."
                    }

                    $quickEntries = @(
                        foreach ($actionId in $quickSafeActionIds) {
                            [pscustomobject]@{
                                Group    = "Quick Safe Cleanup"
                                ActionId = [string]$actionId
                                Item     = [pscustomobject]@{
                                    ActionId = [string]$actionId
                                    Label    = [string]$actionId
                                }
                            }
                        }
                    )

                    if ($executionMessage) {
                        $executionMessage.Visibility = [System.Windows.Visibility]::Collapsed
                        $executionMessage.Text = ""
                    }

                    $script:IsPlayRunning = $true
                    & $setPlayProgressSafe 0
                    $null = & $setUiEnabledCmd -Control $btnPlay -IsEnabled $false
                    $null = & $setHitTestVisibilityCmd -Control $btnPlay -IsHitTestVisible $false
                    try { $quickSafeCleanup.IsEnabled = $false } catch { }

                    $asyncStarted = $false
                    if ($startSelectedTasksAsyncCmd) {
                        try {
                            $onCompleted = {
                                try { & $completeQuickRun $true } catch { }
                            }.GetNewClosure()
                            $asyncStarted = [bool](& $startSelectedTasksAsyncCmd -Window $activeWindow -ProgressPath $playProgressPath -ProgressClip $playProgressClip -OnCompleted $onCompleted -SelectedEntries $quickEntries)
                        }
                        catch {
                            $asyncStarted = $false
                            & $runtimeLoggerSafe ("Quick clean async start failed; falling back to sync runner. {0}" -f $_.Exception.Message) "WARN"
                        }
                    }

                    if (-not $asyncStarted) {
                        & $runSelectedTasksCmd -Window $activeWindow -ProgressPath $playProgressPath -ProgressClip $playProgressClip -SelectedEntries $quickEntries
                        & $completeQuickRun $true
                    }
                }
                catch {
                    & $runtimeLoggerSafe ("Quick clean handler failed: {0}" -f $_.Exception.Message) "ERROR"
                    & $completeQuickRun $false
                }
            }.GetNewClosure()

            $script:QOT_QuickSafeCleanupHandler = $quickSafeCleanupHandler
            try { $quickSafeCleanup.Add_Checked($quickSafeCleanupHandler) } catch { }
        }
    }

    if ($btnLogs) {
        $script:QOT_LogsButton = $btnLogs
        Update-QOTTaskLogsButtonState

        try {
            if ($script:QOT_LogsButtonHandler) {
                $btnLogs.Remove_Click($script:QOT_LogsButtonHandler)
            }
        } catch { }

        $script:QOT_LogsButtonHandler = [System.Windows.RoutedEventHandler]{
            param($sender, $args)
            try {
                & $runtimeLoggerSafe "Logs button clicked." "INFO"
                $owner = $script:MainWindow
                if (-not $owner) {
                    try { $owner = [System.Windows.Window]::GetWindow($sender) } catch { $owner = $null }
                }
                $openLogsView = {
                    param([AllowNull()][System.Windows.Window]$OwnerWindow)

                    $effectiveShowCmd = $showTaskResultsCmd
                    if (-not $effectiveShowCmd) {
                        try { $effectiveShowCmd = Resolve-QOTInvokableCommand -Name "Show-QOTTaskResultsWindow" -LookupErrorAction SilentlyContinue } catch { $effectiveShowCmd = $null }
                    }
                    if ($effectiveShowCmd) {
                        & $effectiveShowCmd -Owner $OwnerWindow
                        return
                    }

                    throw "Task results view command is unavailable."
                }.GetNewClosure()

                if ($owner -and $owner.Dispatcher -and (-not $owner.Dispatcher.CheckAccess())) {
                    $owner.Dispatcher.Invoke([action]{ & $openLogsView -OwnerWindow $owner }) | Out-Null
                }
                else {
                    & $openLogsView -OwnerWindow $owner
                }
            } catch {
                & $runtimeLoggerSafe ("Logs window failed to open: {0}" -f $_.Exception.Message) "ERROR"
                try {
                    $worked = 0; $skipped = 0; $failed = 0
                    try { $worked = [int]$script:QOT_TaskRunSummary.Worked } catch { }
                    try { $skipped = [int]$script:QOT_TaskRunSummary.Skipped } catch { }
                    try { $failed = [int]$script:QOT_TaskRunSummary.Failed } catch { }
                    [System.Windows.MessageBox]::Show(
                        ("Task results summary`n`nWorked: {0}`nSkipped: {1}`nFailed: {2}" -f $worked, $skipped, $failed),
                        "Task Results",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    ) | Out-Null
                } catch { }
            }
        }.GetNewClosure()

        $btnLogs.Add_Click($script:QOT_LogsButtonHandler)
    }


    # ------------------------------------------------------------
    # Initialise Settings UI (hosted in SettingsHost)
    # ------------------------------------------------------------
        $resolveHostFromHiddenTab = {
            param(
                [Parameter(Mandatory)][string]$HostName,
                [Parameter(Mandatory)][string]$TabName
            )

            $host = $null
            if ($resolvedControls.ContainsKey($HostName)) {
                $host = $resolvedControls[$HostName]
            }
            if (-not $host) {
                $host = Find-QOTControlByNameDeep -Root $window -Name $HostName
            }
            if ($host) {
                $resolvedControls[$HostName] = $host
                return $host
            }

            if (-not $tabs) { return $null }
            if (-not $resolvedControls.ContainsKey($TabName)) { return $null }

            $targetTab = $resolvedControls[$TabName]
            if (-not $targetTab) { return $null }

            $previousTab = $tabs.SelectedItem
            $previousVisibility = $targetTab.Visibility

            try {
                if ($targetTab.Visibility -ne [System.Windows.Visibility]::Visible) {
                    $targetTab.Visibility = [System.Windows.Visibility]::Visible
                }
                $tabs.SelectedItem = $targetTab
                $window.UpdateLayout()

                $host = Find-QOTControlByNameDeep -Root $window -Name $HostName
                if (-not $host -and $targetTab -is [System.Windows.FrameworkElement]) {
                    try { $host = $targetTab.FindName($HostName) } catch { }
                }
            }
            catch {
                Write-QOTStartupTrace ("Deferred host resolution failed for {0}: {1}" -f $HostName, $_.Exception.Message) 'WARN'
            }
            finally {
                try {
                    if ($previousTab) { $tabs.SelectedItem = $previousTab }
                    if ($previousVisibility -ne [System.Windows.Visibility]::Visible) { $targetTab.Visibility = $previousVisibility }
                    $window.UpdateLayout()
                } catch { }
            }

            if ($host) {
                $resolvedControls[$HostName] = $host
            }

            return $host
        }.GetNewClosure()

        $settingsHost = & $resolveHostFromHiddenTab "SettingsHost" "TabSettings"
        if (-not $settingsHost) {
            Write-QOTStartupTrace "SettingsHost not found. Settings tab content will be unavailable." 'WARN'
            Add-QOTStartupIssue -Issues $startupIssues -Message "Settings view host is missing."
        }
        
    if ($settingsHost) {
    try {
        $cmd = Resolve-QOTInvokableCommand -Name "New-QOTSettingsView" -LookupErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "New-QOTSettingsView not found. Check Core\Settings\Settings.UI.psm1 exports it."
        }

        $settingsView = Invoke-QOTStartupStep "Build settings view" { New-QOTSettingsView -MainWindow $window -MainTabs $tabs }
        if ($settingsView -is [System.Array]) {
            $settingsView = $settingsView | Where-Object { $_ -is [System.Windows.DependencyObject] } | Select-Object -Last 1
        }
        if (-not ($settingsView -is [System.Windows.DependencyObject])) { throw "Settings view returned null" }

        $settingsHost.Content = $settingsView
    }
    catch {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "Settings failed to load.`r`n$($_.Exception.Message)"
        $tb.Foreground = [System.Windows.Media.Brushes]::White
        $tb.Margin = "10"
        $settingsHost.Content = $tb
        Add-QOTStartupIssue -Issues $startupIssues -Message "Settings view failed to load."
    }
    }
    # ------------------------------------------------------------
    # Initialise Help UI (hosted in HelpHost)
    # ------------------------------------------------------------
        $helpHost = & $resolveHostFromHiddenTab "HelpHost" "TabHelp"
        if (-not $helpHost) {
            Write-QOTStartupTrace "HelpHost not found. Help tab content will be unavailable." 'WARN'
            Add-QOTStartupIssue -Issues $startupIssues -Message "Help view host is missing."
        }
        
    if ($helpHost) {
    try {
        $cmd = Resolve-QOTInvokableCommand -Name "New-QOTHelpView" -LookupErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "New-QOTHelpView not found. Check UI\HelpWindow.UI.psm1 exports it."
        }

        $helpView = Invoke-QOTStartupStep "Build help view" { New-QOTHelpView }
        if ($helpView -is [System.Array]) {
            $helpView = $helpView | Where-Object { $_ -is [System.Windows.DependencyObject] } | Select-Object -Last 1
        }
        if (-not ($helpView -is [System.Windows.DependencyObject])) { throw "Help view returned null" }

        $helpHost.Content = $helpView
    }
    catch {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "Help failed to load.`r`n$($_.Exception.Message)"
        $tb.Foreground = [System.Windows.Media.Brushes]::White
        $tb.Margin = "10"
        $helpHost.Content = $tb
        Add-QOTStartupIssue -Issues $startupIssues -Message "Help view failed to load."
    }
    }

    if ($startupIssues.Count -gt 0) {
        $summary = "Some features failed to load: " + (($startupIssues | Select-Object -Unique) -join " ")
        Show-QOTStartupErrorBanner -Window $window -Message $summary
    }

    # ------------------------------------------------------------
    # Gear icon switches to Settings tab (tab is hidden)
    # ------------------------------------------------------------
        $btnSettings = $btnSettingsNav
        $btnHelp     = $btnHelpNav
        
        if ($btnSettings -and $tabs -and $tabSettings) {
            $btnSettings.Add_Click({
                Open-QOTHiddenTab -Tabs $tabs -Tab $tabSettings
                & $syncRailNavigationSafe
            })
        }

        if ($btnHelp -and $tabs -and $tabHelp) {
            $btnHelp.Add_Click({
                Open-QOTHiddenTab -Tabs $tabs -Tab $tabHelp
                & $syncRailNavigationSafe
            })
        }
    }
    else {
        Write-QOTStartupTrace "Critical UI controls are missing; feature module wiring skipped." 'WARN'
    }
    
    # ------------------------------------------------------------
    # System summary refresh
    # ------------------------------------------------------------
    if ($script:SummaryTextBlock) {
        Invoke-QOTStartupStep "Initial system summary" { Set-QOTSummary -Text (Get-QOTSystemSummaryText) }

        try {
            $selectedCountAtStartup = 0
            if (Get-Command Get-QOTSelectedActionsInExecutionOrder -ErrorAction SilentlyContinue) {
                $selectedCountAtStartup = @((Get-QOTSelectedActionsInExecutionOrder -Window $window)).Count
            }
            $startupSnapshot = Get-QOTMaintenanceSnapshot -SelectedCount $selectedCountAtStartup
            Update-QOTMaintenanceSummaryPanel -Window $window -Before $startupSnapshot -After $null -Completed 0 -Skipped 0 -Failed 0 -LastRunTime 'Never'
        }
        catch {
            Write-QOTStartupTrace ("Failed to initialise maintenance summary panel: {0}" -f $_.Exception.Message) 'WARN'
        }

        $script:SummaryTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:SummaryTimer.Interval = [TimeSpan]::FromSeconds(5)
        $script:SummaryTimer.Add_Tick({
            Set-QOTSummary -Text (Get-QOTSystemSummaryText)
        })
        Register-QOTMainWindowTimer -Timer $script:SummaryTimer
        $script:SummaryTimer.Start()
    }

    # ------------------------------------------------------------
    # Close splash + show main window
    # ------------------------------------------------------------
    if ($WarmupOnly) {
        if ($PassThru) { return $window }
        return
    }
    try {
        $shouldFadeInMainWindow = [bool]$SplashWindow
        if ($shouldFadeInMainWindow) {
            try { $window.Opacity = 0.0 } catch { }
        }

        Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow pre-show"
        
        if ($appCreatedHere) {
            if ($shouldFadeInMainWindow) {
                Write-QOTStartupTrace "Deferring MainWindow.Show() until splash fade-out completes"
                Set-QOTWindowSafetyDefaults -Window $window
                try { $window.Opacity = 0.0 } catch { }
            }
            else {
                Write-QOTStartupTrace "Calling MainWindow.Show()"
                $window.Show()
                # Don't activate - let user continue working
                # $window.Activate() | Out-Null
                Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow post-show"
                Set-QOTWindowSafetyDefaults -Window $window
                if (-not $window.IsVisible -or $window.Visibility -ne [System.Windows.Visibility]::Visible) {
                    Write-QOTStartupTrace "MainWindow not visible after Show; re-showing with safety defaults" 'WARN'
                    $window.Show()
                    # Don't activate - let user continue working
                    # $window.Activate() | Out-Null
                    Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow post-safety-show"
                }
            }
        }
        else {
            Write-QOTStartupTrace "Skipping pre-show because existing WPF application path uses MainWindow.ShowDialog()"
            # Keep the window hidden for ShowDialog(); only apply safe geometry/state.
            $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
            $window.WindowState = [System.Windows.WindowState]::Normal
            $window.ShowInTaskbar = $true
            $virtualLeft = [System.Windows.SystemParameters]::VirtualScreenLeft
            $virtualTop = [System.Windows.SystemParameters]::VirtualScreenTop
            $virtualWidth = [System.Windows.SystemParameters]::VirtualScreenWidth
            $virtualHeight = [System.Windows.SystemParameters]::VirtualScreenHeight
            $hasInvalidLeft = [double]::IsNaN($window.Left) -or [double]::IsInfinity($window.Left)
            $hasInvalidTop = [double]::IsNaN($window.Top) -or [double]::IsInfinity($window.Top)
            $hasOffscreenLeft = ($window.Left -lt $virtualLeft) -or ($window.Left -gt ($virtualLeft + $virtualWidth))
            $hasOffscreenTop = ($window.Top -lt $virtualTop) -or ($window.Top -gt ($virtualTop + $virtualHeight))
            if ($hasInvalidLeft -or $hasInvalidTop -or $hasOffscreenLeft -or $hasOffscreenTop) {
                $width = if ($window.Width -gt 0) { $window.Width } else { 1200 }
                $height = if ($window.Height -gt 0) { $window.Height } else { 800 }
                $window.Left = $virtualLeft + (($virtualWidth - $width) / 2)
                $window.Top = $virtualTop + (($virtualHeight - $height) / 2)
            }
            try { $window.Visibility = [System.Windows.Visibility]::Hidden } catch { }
            if ($shouldFadeInMainWindow) {
                try { $window.Opacity = 0.0 } catch { }
            }
            Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow pre-dialog"
        }
        if (-not $app) {
            throw "WPF Application instance is null before Run()."
        }
        if (-not $window) {
            throw "MainWindow instance is null before Run()."
        }

        $currentApartmentState = [System.Threading.Thread]::CurrentThread.GetApartmentState()
        Write-QOTStartupTrace ("CurrentThread.ApartmentState before Run: {0}" -f $currentApartmentState)

        $app.MainWindow = $window
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
        Write-QOTStartupTrace ("Application ShutdownMode set to: {0}" -f $app.ShutdownMode)

        $window.Add_Loaded({ Write-QOTStartupTrace "MainWindow lifecycle event fired: Loaded" })
        $window.Add_SourceInitialized({
            try {
                $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
                $source = [System.Windows.Interop.HwndSource]::FromHwnd($helper.Handle)
                if ($source -and -not $script:MainWindowNativeHook) {
                    $script:MainWindowNativeHook = [System.Windows.Interop.HwndSourceHook]{
                        param($hwnd, $msg, $wParam, $lParam, [ref]$handled)

                        $WM_SYSCOMMAND = 0x0112
                        $SC_CLOSE = 0xF060
                        if ($msg -eq $WM_SYSCOMMAND) {
                            $cmd = ([int64]$wParam) -band 0xFFF0
                            if ($cmd -eq $SC_CLOSE) {
                                $script:MainWindowAllowClose = $true
                                $script:MainWindowCloseReason = "SystemCommandClose"
                                Write-QOTStartupTrace "MainWindow close intent detected via WM_SYSCOMMAND/SC_CLOSE"
                            }
                        }
                        return [IntPtr]::Zero
                    }
                    $source.AddHook($script:MainWindowNativeHook)
                    Write-QOTStartupTrace "MainWindow native close hook attached"
                }
            }
            catch {
                Write-QOTStartupTrace ("Failed to attach main window native close hook: {0}" -f $_.Exception.Message) 'WARN'
            }
        })
        $window.Add_ContentRendered({
            Write-QOTStartupTrace "MainWindow lifecycle event fired: ContentRendered"
            if ($shouldFadeInMainWindow) {
                try {
                    $startOpacity = 0.0
                    try { $startOpacity = [double]$window.Opacity } catch { $startOpacity = 0.0 }
                    Invoke-QOTMainWindowFadeIn -Window $window -DurationMs 260 -StartOpacity $startOpacity
                    Write-QOTStartupTrace "MainWindow fade-in started after splash."
                }
                catch {
                    Write-QOTStartupTrace ("MainWindow fade-in failed: {0}" -f $_.Exception.Message) 'WARN'
                    try { $window.Opacity = 1.0 } catch { }
                }
                finally {
                    $shouldFadeInMainWindow = $false
                }
            }
        })
        $window.Add_Closing({
            param($sender, $eventArgs)
            $closeReason = if ($script:MainWindowCloseReason) { $script:MainWindowCloseReason } else { "User/System close request" }
            Write-QOTStartupTrace ("MainWindow lifecycle event fired: Closing (Cancel={0}; Reason={1}; AllowClose={2})" -f $eventArgs.Cancel, $closeReason, $script:MainWindowAllowClose)
                $closeGuardWindowMs = 5000
                $elapsedMs = if ($script:MainWindowStartupCloseGuard) { [math]::Round($script:MainWindowStartupCloseGuard.Elapsed.TotalMilliseconds) } else { -1 }
                $isExplicitCloseIntent = [bool]$script:MainWindowAllowClose

                if ((-not $isExplicitCloseIntent) -and (-not $script:MainWindowUnexpectedCloseBlocked) -and $elapsedMs -ge 0 -and $elapsedMs -lt $closeGuardWindowMs) {
                    $eventArgs.Cancel = $true
                    $script:MainWindowUnexpectedCloseBlocked = $true
                    Write-QOTStartupTrace ("Blocked unexpected early MainWindow close request at {0} ms after startup; keeping UI alive." -f $elapsedMs) 'WARN'
                    try {
                        $sender.Dispatcher.BeginInvoke([action]{
                            try {
                                $sender.Show()
                                # Don't activate - let user continue working
                                # $sender.Activate() | Out-Null
                            }
                            catch {
                            }
                        }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
                    }
                    catch {
                    }
                    return
                }

            if (-not $script:MainWindowAllowClose) {
                Write-QOTStartupTrace "MainWindow close request arrived without explicit close intent marker; allowing close as safety fallback" 'WARN'
            }

            $script:MainWindowAllowClose = $false
            $script:MainWindowCloseReason = $null
        })
        $window.Add_Closed({
            Write-QOTStartupTrace "MainWindow lifecycle event fired: Closed"
            $script:MainWindowAllowClose = $false
            $script:MainWindowCloseReason = $null
            $script:MainWindowNativeHook = $null
            $script:MainWindowUnexpectedCloseBlocked = $false

            # Stop every DispatcherTimer tracked in the central registry. This catches
            # any ghost timers we might have missed naming explicitly, and is safe to
            # call multiple times (Stop-AllTimers ignores already-stopped timers).
            try { Stop-AllTimers } catch { Write-QOTStartupTrace ("MainWindow: Stop-AllTimers on close failed: {0}" -f $_.Exception.Message) 'WARN' }

            # Belt-and-braces: clear the named script-level references too so the
            # rest of the cleanup logic below knows the timers have been stopped.
            if ($script:PlayButtonTimer) {
                try { $script:PlayButtonTimer.Stop() } catch { }
                $script:PlayButtonTimer = $null
            }
            if ($script:SummaryTimer) {
                try { $script:SummaryTimer.Stop() } catch { }
                $script:SummaryTimer = $null
            }

            $script:IsPlayRunning = $false
            $script:MainWindow = $null
            $script:SummaryTextBlock = $null
            $script:QOT_LogsButton = $null
            $script:QOT_LogsButtonHandler = $null
            if ($script:QOT_TaskResultsWindow) {
                try { $script:QOT_TaskResultsWindow.Close() } catch { }
                $script:QOT_TaskResultsWindow = $null
            }
            if ($script:MainWindowStartupCloseGuard) {
                try { $script:MainWindowStartupCloseGuard.Stop() } catch { }
            }
            try {
                $appCurrent = [System.Windows.Application]::Current
                if ($appCurrent -and $appCurrent.MainWindow -and [object]::ReferenceEquals($appCurrent.MainWindow, $sender)) {
                    $appCurrent.MainWindow = $null
                }
            }
            catch {
            }
        })

        if ($appCreatedHere -and -not $shouldFadeInMainWindow) {
            Write-QOTStartupTrace "Forcing MainWindow.Show() immediately before Run"
            $window.Show()
            # Don't activate - let user continue working
            # $window.Activate() | Out-Null
            Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow pre-run forced-show"
        }
        elseif ($appCreatedHere -and $shouldFadeInMainWindow) {
            Write-QOTStartupTrace "Skipping pre-run forced-show; waiting for splash fade-out first"
        }

        if ($SplashWindow) {
            try {
                Write-QOTStartupTrace "Starting splash fade-out before main window reveal"
                Invoke-QOTSplashFadeOut -SplashWindow $SplashWindow -DurationMs 350 -Wait
            }
            catch {
                Write-QOTStartupTrace ("Failed to fade splash window cleanly: {0}" -f $_.Exception.Message) 'WARN'
                try { $SplashWindow.Close() } catch { }
            }
        }

        if ($appCreatedHere -and $shouldFadeInMainWindow) {
            Write-QOTStartupTrace "Showing MainWindow after splash fade-out"
            $window.Show()
            # Don't activate - let user continue working
            # $window.Activate() | Out-Null
            Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow post-splash-show"
            try {
                Invoke-QOTMainWindowFadeIn -Window $window -DurationMs 260 -StartOpacity 0.0
                Write-QOTStartupTrace "MainWindow fade-in started."
            } catch {
                Write-QOTStartupTrace ("MainWindow fade-in start failed: {0}" -f $_.Exception.Message) 'WARN'
                try { $window.Opacity = 1.0 } catch { }
            }
            $shouldFadeInMainWindow = $false
        }

        if ($appCreatedHere) {
            Write-QOTStartupTrace "Entering app.Run(mainWindow)"
            try {
                $app.Run($window) | Out-Null
                Write-QOTStartupTrace "app.Run(mainWindow) exited normally"
            }
            catch {
                $runExceptionText = if ($_.Exception) { $_.Exception.ToString() } else { $_.ToString() }
                Write-QOTStartupTrace ("app.Run(mainWindow) threw an exception.`n{0}" -f $runExceptionText) 'ERROR'
                try { Write-QLog ("app.Run(mainWindow) threw an exception.`n{0}" -f $runExceptionText) "ERROR" } catch { }
                throw
            }
        }
        else {
            Write-QOTStartupTrace "Using existing WPF application run loop; attempting MainWindow.ShowDialog()"
            try {
                if ($window.IsVisible -or $window.Visibility -ne [System.Windows.Visibility]::Hidden) {
                    try { $window.Hide() } catch { $window.Visibility = [System.Windows.Visibility]::Hidden }
                }
            } catch { }

            $showDialogCompleted = $false
            $showDialogStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $window.ShowDialog() | Out-Null
                $showDialogCompleted = $true
                Write-QOTStartupTrace "MainWindow.ShowDialog() exited normally"
            }
            catch {
                $dialogExceptionText = if ($_.Exception) { $_.Exception.ToString() } else { $_.ToString() }
                Write-QOTStartupTrace ("MainWindow.ShowDialog() threw an exception.`n{0}" -f $dialogExceptionText) 'ERROR'
                try { Write-QLog ("MainWindow.ShowDialog() threw an exception.`n{0}" -f $dialogExceptionText) "ERROR" } catch { }
                throw
            }
 finally {
                $showDialogStopwatch.Stop()
            }

            # Some hosts create a bootstrap WPF app where ShowDialog can return
            # almost immediately without a visible window. Recover by forcing a
            # modeless show and waiting on a local dispatcher frame.
            if ($showDialogCompleted -and (-not $window.IsVisible) -and $showDialogStopwatch.ElapsedMilliseconds -lt 1500) {
                Write-QOTStartupTrace ("MainWindow.ShowDialog() returned in {0} ms with IsVisible={1}; forcing modeless fallback show." -f [math]::Round($showDialogStopwatch.Elapsed.TotalMilliseconds), $window.IsVisible) 'WARN'
                try {
                    $window.Show()
                    $window.Activate() | Out-Null
                    Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow modeless fallback"

                    $dispatcherFrame = [System.Windows.Threading.DispatcherFrame]::new($true)
                    $closedHandler = [System.EventHandler]{
                        param($sender, $eventArgs)
                        $dispatcherFrame.Continue = $false
                    }
                    $window.add_Closed($closedHandler)
                    try {
                        [System.Windows.Threading.Dispatcher]::PushFrame($dispatcherFrame)
                    }
                    finally {
                        $window.remove_Closed($closedHandler)
                    }
                }
                catch {
                    $fallbackError = if ($_.Exception) { $_.Exception.ToString() } else { $_.ToString() }
                    Write-QOTStartupTrace ("MainWindow modeless fallback failed.`n{0}" -f $fallbackError) 'ERROR'
                    try { Write-QLog ("MainWindow modeless fallback failed.`n{0}" -f $fallbackError) "ERROR" } catch { }
                    throw
                }
            }
        }
    }
    
    catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("MainWindow show failed.`n{0}" -f $errorDetail) 'ERROR'
        try { Write-QLog ("MainWindow show failed.`n{0}" -f $errorDetail) "ERROR" } catch { }
        throw
    }

    if ($PassThru) { return $window }
}

$globalPublishFunctions = @(
    'Write-QOTRuntimeLog',
    'Write-QOTRuntimeLogSafe',
    'Write-QOTStartupTrace',
    'Resolve-QOTInvokableCommand',
    'Invoke-QOTCallbackSafely'
)

foreach ($fnName in $globalPublishFunctions) {
    try {
        $fn = @(Get-Command -Name $fnName -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($fn -is [System.Array]) {
            $fn = if ($fn.Count -gt 0) { $fn[0] } else { $null }
        }
        if ($fn -and $fn.ScriptBlock) {
            Set-Item -Path ("Function:\global\{0}" -f $fnName) -Value $fn.ScriptBlock -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

Export-ModuleMember -Function Start-QOTMainWindow, Set-QOTSummary, Resolve-QOTControlSet, Resolve-QOTInvokableCommand, Request-QOTMainWindowClose, Write-QOTRuntimeLog, Write-QOTRuntimeLogSafe, Write-QOTStartupTrace, Reset-QOTTaskRunLog, Add-QOTTaskRunLogEntry, Complete-QOTTaskRunLog, Show-QOTTaskResultsWindow, Update-QOTTaskLogsButtonState

