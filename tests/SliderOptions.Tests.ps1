$repoRoot = Split-Path -Parent $PSScriptRoot
$enginePath = Join-Path $repoRoot "src\Core\Engine\Engine.psm1"
$null = Import-Module (Join-Path $repoRoot "src\Core\Settings.psm1") -Force -Global -ErrorAction Stop

function Get-QOTTestToggleActionState {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [bool]$Default = $false
    )

    $cmd = Get-Command Get-QOToggleActionState -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) {
        $null = Import-Module (Join-Path $repoRoot "src\Core\Settings.psm1") -Force -Global -ErrorAction Stop
        $cmd = Get-Command Get-QOToggleActionState -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $cmd) {
        throw "Get-QOToggleActionState is unavailable in the current test session."
    }

    return [bool](& $cmd -ActionId $ActionId -Default $Default)
}

function Invoke-QOTTestUiPump {
    param([int]$Milliseconds = 100)

    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds($Milliseconds)
    $timer.Add_Tick({
        param($sender, $args)
        $sender.Stop()
        $frame.Continue = $false
    })
    $timer.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Find-QOTTestVisualElement {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string]$Name
    )

    $queue = New-Object 'System.Collections.Generic.Queue[System.Object]'
    $visited = New-Object 'System.Collections.Generic.HashSet[int]'
    $queue.Enqueue($Root) | Out-Null

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (-not $current) { continue }

        $objectId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($current)
        if (-not $visited.Add($objectId)) { continue }

        if ($current -is [System.Windows.FrameworkElement] -and $current.Name -eq $Name) {
            return $current
        }

        try {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($current)) {
                if ($child) { $queue.Enqueue($child) | Out-Null }
            }
        } catch { }

        if ($current -is [System.Windows.DependencyObject]) {
            $count = 0
            try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($current) } catch { $count = 0 }
            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($current, $i)
                    if ($child) { $queue.Enqueue($child) | Out-Null }
                } catch { }
            }
        }
    }

    return $null
}

function Invoke-QOTTestSliderClick {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.CheckBox]$Control
    )

    $args = [System.Windows.Input.MouseButtonEventArgs]::new(
        [System.Windows.Input.Mouse]::PrimaryDevice,
        [Environment]::TickCount,
        [System.Windows.Input.MouseButton]::Left
    )
    $args.RoutedEvent = [System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent
    $args.Source = $Control
    $Control.RaiseEvent($args)
}

function Assert-QOTTestSectionSelectors {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)]$Tabs,
        [Parameter(Mandatory)]$Failures
    )

    $instantActions = @{
        CbDisableStartRecommended = "Invoke-QTweakStartMenuRecommendations"
        CbDisableSuggestedApps = "Invoke-QTweakSuggestedApps"
        CbDisableTipsStart = "Invoke-QTweakTipsInStart"
        CbDisableBingSearch = "Invoke-QTweakBingSearch"
        CbClassicMoreOptions = "Invoke-QTweakClassicContextMenu"
        CbDisableWidgets = "Invoke-QTweakWidgets"
        CbDisableTaskbarNews = "Invoke-QTweakNewsAndInterests"
        CbDisableMeetNow = "Invoke-QTweakMeetNow"
        CbDisableAdvertisingId = "Invoke-QTweakAdvertisingId"
        CbLimitFeedbackPrompts = "Invoke-QTweakFeedbackHub"
        CbDisableOnlineTips = "Invoke-QTweakOnlineTips"
        CbDisableLockScreenTips = "Invoke-QTweakDisableLockScreenTips"
        CbDisableSettingsSuggestedContent = "Invoke-QTweakDisableSettingsSuggestedContent"
        CbDisableTransparencyEffects = "Invoke-QTweakDisableTransparencyEffects"
        CbDisableStartupDelay = "Invoke-QTweakDisableStartupDelay"
        CbDisableGameDVR = "Invoke-QTweakDisableGameDVR"
        CbDisableWindowsConsumerFeatures = "Invoke-QTweakDisableWindowsConsumerFeatures"
        CbDisableWindowsRecall = "Invoke-QTweakDisableWindowsRecall"
        CbAdvAdobeNetworkBlock = "Invoke-QAdvancedAdobeNetworkBlock"
        CbAdvBlockRazerInstalls = "Invoke-QAdvancedBlockRazerInstalls"
        CbAdvBraveDebloat = "Invoke-QAdvancedBraveDebloat"
        CbAdvEdgeDebloat = "Invoke-QAdvancedEdgeDebloat"
        CbAdvDisableEdge = "Invoke-QAdvancedDisableEdge"
        CbAdvEdgeUninstallable = "Invoke-QAdvancedEdgeUninstallable"
        CbAdvDisableBackgroundApps = "Invoke-QAdvancedDisableBackgroundApps"
        CbAdvDisableFullscreenOptimizations = "Invoke-QAdvancedDisableFullscreenOptimizations"
        CbAdvDisableNotificationTray = "Invoke-QAdvancedDisableNotificationTray"
        CbAdvDisplayPerformance = "Invoke-QAdvancedDisplayPerformance"
        CbAdvDisableTelemetryScheduledTasks = "Invoke-QDisableTelemetryScheduledTasks"
        CbAdvDisableIPv6 = "Invoke-QAdvancedDisableIPv6"
        CbAdvDisableTeredo = "Invoke-QAdvancedDisableTeredo"
        CbAdvDisableCopilot = "Invoke-QAdvancedDisableCopilot"
        CbAdvDisableStorageSense = "Invoke-QAdvancedDisableStorageSense"
    }

    $oneShotActions = @{
        CbCleanTempFiles = "Invoke-QCleanTemp"
        CbEmptyRecycleBin = "Invoke-QCleanRecycleBin"
        CbCleanDoCache = "Invoke-QCleanDOCache"
        CbCleanWuCache = "Invoke-QCleanWindowsUpdateCache"
        CbCleanThumbCache = "Invoke-QCleanThumbnailCache"
        CbCleanPrefetchFiles = "Invoke-QCleanPrefetchFiles"
        CbRefreshIconCache = "Invoke-QRefreshWindowsIconCache"
        CbCleanErrorLogs = "Invoke-QCleanErrorLogs"
        CbCleanSetupLeftovers = "Invoke-QCleanSetupLeftovers"
        CbClearStoreCache = "Invoke-QCleanStoreCache"
        CbClearEventLogs = "Invoke-QClearWindowsEventLogs"
        CbClearTeamsCache = "Invoke-QCleanTeamsCache"
        CbEdgeLightCleanup = "Invoke-QCleanEdgeCache"
        CbChromeLightCleanup = "Invoke-QCleanChromeCache"
        CbCleanDirectXShaderCache = "Invoke-QCleanDirectXShaderCache"
        CbCleanWERQueue = "Invoke-QCleanWERQueue"
        CbClearClipboardHistory = "Invoke-QCleanClipboardHistory"
        CbCleanExplorerRecentItems = "Invoke-QCleanExplorerRecentItems"
        CbCleanWindowsSearchHistory = "Invoke-QCleanWindowsSearchHistory"
        CbAdvCleanComponentStore = "Invoke-QCleanComponentStore"
        CbAdvScanUnusedDeviceDrivers = "Invoke-QScanUnusedDeviceDrivers"
        CbAdvDeepCacheCleanup = "Invoke-QAdvancedDeepCache"
        CbAdvAggressiveComponentStoreCleanup = "Invoke-QAggressiveComponentStoreCleanup"
        CbAdvNetworkReset = "Invoke-QNetworkReset"
        CbAdvFlushDnsCache = "Invoke-QFlushDnsCache"
        CbAdvResetWinsock = "Invoke-QResetWinsock"
        CbAdvResetWindowsFirewall = "Invoke-QResetWindowsFirewall"
        CbAdvRestartWindowsExplorer = "Invoke-QRestartWindowsExplorer"
        CbAdvRebuildWindowsSearchIndex = "Invoke-QRebuildWindowsSearchIndex"
        CbAdvRunSfcRepair = "Invoke-QRunSfcSystemFileRepair"
        CbAdvRunDismHealthRepair = "Invoke-QRunDismHealthRepair"
    }

    $sectionGroups = @(
        @{ Tab = "TabCleaning"; Header = "CbSectionStorageCleanup"; Children = @("CbCleanTempFiles", "CbEmptyRecycleBin", "CbCleanDoCache", "CbCleanWuCache", "CbCleanThumbCache", "CbCleanPrefetchFiles", "CbRefreshIconCache") },
        @{ Tab = "TabCleaning"; Header = "CbSectionWindowsHousekeeping"; Children = @("CbCleanErrorLogs", "CbCleanSetupLeftovers", "CbClearStoreCache", "CbClearEventLogs", "CbClearTeamsCache") },
        @{ Tab = "TabCleaning"; Header = "CbSectionBrowserCleanup"; Children = @("CbEdgeLightCleanup", "CbChromeLightCleanup", "CbCleanDirectXShaderCache", "CbCleanWERQueue", "CbClearClipboardHistory", "CbCleanExplorerRecentItems", "CbCleanWindowsSearchHistory") },
        @{ Tab = "TabCleaning"; Header = "CbSectionStartMenuRecommendations"; Children = @("CbDisableStartRecommended", "CbDisableSuggestedApps", "CbDisableTipsStart", "CbDisableBingSearch", "CbClassicMoreOptions") },
        @{ Tab = "TabCleaning"; Header = "CbSectionTaskbarWidgets"; Children = @("CbDisableWidgets", "CbDisableTaskbarNews", "CbDisableMeetNow") },
        @{ Tab = "TabCleaning"; Header = "CbSectionPrivacyTelemetry"; Children = @("CbDisableAdvertisingId", "CbLimitFeedbackPrompts", "CbDisableOnlineTips", "CbDisableLockScreenTips", "CbDisableSettingsSuggestedContent", "CbDisableTransparencyEffects", "CbDisableStartupDelay") },
        @{ Tab = "TabCleaning"; Header = "CbSectionPerformanceTweaks"; Children = @("CbDisableGameDVR", "CbDisableWindowsConsumerFeatures", "CbDisableWindowsRecall") },
        @{ Tab = "TabAdvanced"; Header = "CbAdvSectionAppBrowserControls"; Children = @("CbAdvAdobeNetworkBlock", "CbAdvBlockRazerInstalls", "CbAdvBraveDebloat", "CbAdvEdgeDebloat", "CbAdvDisableEdge", "CbAdvEdgeUninstallable") },
        @{ Tab = "TabAdvanced"; Header = "CbAdvSectionSystemBehavior"; Children = @("CbAdvDisableBackgroundApps", "CbAdvDisableFullscreenOptimizations", "CbAdvDisableNotificationTray", "CbAdvDisplayPerformance") },
        @{ Tab = "TabAdvanced"; Header = "CbAdvSectionAdvancedCleaning"; Children = @("CbAdvRemoveOldProfiles", "CbAdvCleanComponentStore", "CbAdvDisableTelemetryScheduledTasks", "CbAdvScanUnusedDeviceDrivers", "CbAdvAggressiveRestoreCleanup", "CbAdvDeepCacheCleanup", "CbAdvAggressiveComponentStoreCleanup") },
        @{ Tab = "TabAdvanced"; Header = "CbAdvSectionConnectivityControls"; Children = @("CbAdvDisableIPv6", "CbAdvDisableTeredo", "CbAdvDisableCopilot", "CbAdvDisableStorageSense") },
        @{ Tab = "TabAdvanced"; Header = "CbAdvSectionNetworkServiceTuning"; Children = @("CbAdvNetworkReset", "CbAdvRepairNetworkAdapter", "CbAdvServiceTuning", "CbAdvFlushDnsCache", "CbAdvResetWinsock", "CbAdvResetWindowsFirewall") },
        @{ Tab = "TabAdvanced"; Header = "CbAdvSectionRepairRecovery"; Children = @("CbAdvRestartWindowsExplorer", "CbAdvRebuildWindowsSearchIndex", "CbAdvRunSfcRepair", "CbAdvRunDismHealthRepair") }
    )

    $env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS = "0"
    $env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS = ""

    foreach ($group in $sectionGroups) {
        $tab = $Window.FindName([string]$group.Tab)
        if ($tab) {
            $Tabs.SelectedItem = $tab
            $Window.UpdateLayout()
            Invoke-QOTTestUiPump -Milliseconds 50
        }

        $header = $Window.FindName([string]$group.Header)
        if (-not ($header -is [System.Windows.Controls.CheckBox])) {
            $Failures.Add(("{0}: section header CheckBox not found." -f $group.Header)) | Out-Null
            continue
        }

        $children = @(
            foreach ($childName in @($group.Children)) {
                $child = $Window.FindName([string]$childName)
                if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsEnabled -ne $false) {
                    $child
                }
            }
        )

        if ($children.Count -eq 0) {
            $Failures.Add(("{0}: no enabled child checkboxes found." -f $group.Header)) | Out-Null
            continue
        }

        $header.IsChecked = $false
        $Window.UpdateLayout()
        Invoke-QOTTestUiPump -Milliseconds 150

        if ([string]$group.Header -eq "CbSectionStartMenuRecommendations") {
            $env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS = "0"
        }

        $oneShotCountBefore = 0
        try {
            $existingOneShots = @([string]$env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $oneShotCountBefore = $existingOneShots.Count
        } catch { $oneShotCountBefore = 0 }

        $header.IsChecked = $true
        $Window.UpdateLayout()
        Invoke-QOTTestUiPump -Milliseconds 50

        $unchecked = @($children | Where-Object { $_.IsChecked -ne $true })
        if ($unchecked.Count -gt 0) {
            $Failures.Add(("{0}: did not check child options: {1}" -f $group.Header, (($unchecked | ForEach-Object Name) -join ", "))) | Out-Null
            continue
        }

        foreach ($child in $children) {
            if (-not $instantActions.ContainsKey([string]$child.Name)) { continue }
            $actionState = Get-QOTTestToggleActionState -ActionId ([string]$instantActions[[string]$child.Name]) -Default $false
            if ($actionState -ne $true) {
                $Failures.Add(("{0}: checking the section did not apply slider action {1}." -f $group.Header, $child.Name)) | Out-Null
            }
        }

        $recordedOneShots = @()
        try {
            $recordedOneShots = @([string]$env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        } catch { $recordedOneShots = @() }

        foreach ($child in $children) {
            if (-not $oneShotActions.ContainsKey([string]$child.Name)) { continue }
            $expectedActionId = [string]$oneShotActions[[string]$child.Name]
            if ($recordedOneShots -notcontains $expectedActionId) {
                $Failures.Add(("{0}: checking the section did not run one-shot action {1}." -f $group.Header, $child.Name)) | Out-Null
            }
        }

        if ([string]$group.Header -eq "CbSectionStartMenuRecommendations") {
            Invoke-QOTTestUiPump -Milliseconds 150
            $restartCount = 0
            try { $restartCount = [int]$env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS } catch { $restartCount = 0 }
            if ($restartCount -ne 1) {
                $Failures.Add(("{0}: expected one deferred Explorer restart after checking the section, got {1}." -f $group.Header, $restartCount)) | Out-Null
            }
        }

        $children[0].IsChecked = $false
        $Window.UpdateLayout()
        Invoke-QOTTestUiPump -Milliseconds 50

        if ($children.Count -gt 1 -and $header.IsChecked -ne $null) {
            $Failures.Add(("{0}: header did not enter mixed state after a child was unchecked." -f $group.Header)) | Out-Null
        }

        $children[0].IsChecked = $true
        $Window.UpdateLayout()
        Invoke-QOTTestUiPump -Milliseconds 50

        $oneShotCountBeforeUncheck = 0
        try {
            $recordedBeforeUncheck = @([string]$env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $oneShotCountBeforeUncheck = $recordedBeforeUncheck.Count
        } catch { $oneShotCountBeforeUncheck = 0 }

        $header.IsChecked = $false
        $Window.UpdateLayout()
        Invoke-QOTTestUiPump -Milliseconds 50

        $checked = @($children | Where-Object { $_.IsChecked -eq $true })
        if ($checked.Count -gt 0) {
            $Failures.Add(("{0}: did not clear child options: {1}" -f $group.Header, (($checked | ForEach-Object Name) -join ", "))) | Out-Null
        }

        foreach ($child in $children) {
            if (-not $instantActions.ContainsKey([string]$child.Name)) { continue }
            $actionState = Get-QOTTestToggleActionState -ActionId ([string]$instantActions[[string]$child.Name]) -Default $true
            if ($actionState -ne $false) {
                $Failures.Add(("{0}: unchecking the section did not restore slider action {1}." -f $group.Header, $child.Name)) | Out-Null
            }
        }

        $oneShotCountAfterUncheck = 0
        try {
            $recordedAfterUncheck = @([string]$env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $oneShotCountAfterUncheck = $recordedAfterUncheck.Count
        } catch { $oneShotCountAfterUncheck = 0 }

        if ($oneShotCountAfterUncheck -ne $oneShotCountBeforeUncheck) {
            $Failures.Add(("{0}: unchecking the section should not rerun one-shot actions." -f $group.Header)) | Out-Null
        }

        if ([string]$group.Header -eq "CbSectionStartMenuRecommendations") {
            Invoke-QOTTestUiPump -Milliseconds 150
            $restartCount = 0
            try { $restartCount = [int]$env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS } catch { $restartCount = 0 }
            if ($restartCount -ne 2) {
                $Failures.Add(("{0}: expected one deferred Explorer restart after unchecking the section, got total {1}." -f $group.Header, $restartCount)) | Out-Null
            }
        }
    }
}

Describe "Slider option wiring" {
    It "loads and toggles every slider-style option without throwing" {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop

        $oldToggleTestMode = $env:QOT_UI_TOGGLE_TEST_MODE
        $oldExplorerRestartCount = $env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS
        $oldOneShotActions = $env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS
        $oldSettingsPath = $env:QOT_SETTINGS_PATH
        $testSettingsPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-slider-settings-" + [guid]::NewGuid().ToString("N") + ".json")
        $env:QOT_UI_TOGGLE_TEST_MODE = "1"
        $env:QOT_SETTINGS_PATH = $testSettingsPath

        $window = $null
        try {
            Import-Module $enginePath -Force -ErrorAction Stop | Out-Null
            $window = Start-QOTMain -RootPath $repoRoot -WarmupOnly -PassThru
            if (-not $window) { throw "Start-QOTMain did not return a window." }

            $window.Left = 100
            $window.Top = 100
            $window.Show()
            $window.Activate() | Out-Null
            $window.UpdateLayout()
            Invoke-QOTTestUiPump -Milliseconds 250

            $tabs = $window.FindName("MainTabControl")
            if (-not $tabs) { throw "MainTabControl was not found." }

            $sliderOptions = @(
                @{ Name = "CbDisableStartRecommended"; Tag = "Invoke-QTweakStartMenuRecommendations"; Tab = "TabCleaning" },
                @{ Name = "CbDisableSuggestedApps"; Tag = "Invoke-QTweakSuggestedApps"; Tab = "TabCleaning" },
                @{ Name = "CbDisableTipsStart"; Tag = "Invoke-QTweakTipsInStart"; Tab = "TabCleaning" },
                @{ Name = "CbDisableBingSearch"; Tag = "Invoke-QTweakBingSearch"; Tab = "TabCleaning" },
                @{ Name = "CbClassicMoreOptions"; Tag = "Invoke-QTweakClassicContextMenu"; Tab = "TabCleaning" },
                @{ Name = "CbDisableWidgets"; Tag = "Invoke-QTweakWidgets"; Tab = "TabCleaning" },
                @{ Name = "CbDisableTaskbarNews"; Tag = "Invoke-QTweakNewsAndInterests"; Tab = "TabCleaning" },
                @{ Name = "CbDisableMeetNow"; Tag = "Invoke-QTweakMeetNow"; Tab = "TabCleaning" },
                @{ Name = "CbDisableAdvertisingId"; Tag = "Invoke-QTweakAdvertisingId"; Tab = "TabCleaning" },
                @{ Name = "CbLimitFeedbackPrompts"; Tag = "Invoke-QTweakFeedbackHub"; Tab = "TabCleaning" },
                @{ Name = "CbDisableOnlineTips"; Tag = "Invoke-QTweakOnlineTips"; Tab = "TabCleaning" },
                @{ Name = "CbDisableLockScreenTips"; Tag = "Invoke-QTweakDisableLockScreenTips"; Tab = "TabCleaning" },
                @{ Name = "CbDisableSettingsSuggestedContent"; Tag = "Invoke-QTweakDisableSettingsSuggestedContent"; Tab = "TabCleaning" },
                @{ Name = "CbDisableTransparencyEffects"; Tag = "Invoke-QTweakDisableTransparencyEffects"; Tab = "TabCleaning" },
                @{ Name = "CbDisableStartupDelay"; Tag = "Invoke-QTweakDisableStartupDelay"; Tab = "TabCleaning" },
                @{ Name = "CbDisableGameDVR"; Tag = "Invoke-QTweakDisableGameDVR"; Tab = "TabCleaning" },
                @{ Name = "CbDisableWindowsConsumerFeatures"; Tag = "Invoke-QTweakDisableWindowsConsumerFeatures"; Tab = "TabCleaning" },
                @{ Name = "CbDisableWindowsRecall"; Tag = "Invoke-QTweakDisableWindowsRecall"; Tab = "TabCleaning" },
                @{ Name = "CbAdvAdobeNetworkBlock"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvBlockRazerInstalls"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvBraveDebloat"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvEdgeDebloat"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisableEdge"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvEdgeUninstallable"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisableBackgroundApps"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisableFullscreenOptimizations"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisplayPerformance"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisableTelemetryScheduledTasks"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisableIPv6"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisableTeredo"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisableCopilot"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisableStorageSense"; Tab = "TabAdvanced" },
                @{ Name = "CbAdvDisableNotificationTray"; Tab = "TabAdvanced" }
            )

            $failures = New-Object System.Collections.Generic.List[string]

            foreach ($option in $sliderOptions) {
                $tab = $window.FindName([string]$option.Tab)
                if ($tab) {
                    $tabs.SelectedItem = $tab
                    $window.UpdateLayout()
                    Invoke-QOTTestUiPump -Milliseconds 50
                }

                $control = $window.FindName([string]$option.Name)
                if (-not ($control -is [System.Windows.Controls.CheckBox])) {
                    $failures.Add(("{0}: CheckBox not found." -f $option.Name)) | Out-Null
                    continue
                }

                if ($option.ContainsKey("Tag") -and ([string]$control.Tag -ne [string]$option.Tag)) {
                    $failures.Add(("{0}: expected Tag '{1}', got '{2}'." -f $option.Name, $option.Tag, [string]$control.Tag)) | Out-Null
                    continue
                }

                try { $control.BringIntoView() } catch { }
                $window.UpdateLayout()
                Invoke-QOTTestUiPump -Milliseconds 50

                $switchHost = Find-QOTTestVisualElement -Root $control -Name "ToggleSwitchHost"
                if (-not $switchHost) {
                    $failures.Add(("{0}: toggle switch visual was not generated." -f $option.Name)) | Out-Null
                    continue
                }

                if (-not $control.IsEnabled) {
                    $failures.Add(("{0}: control is disabled." -f $option.Name)) | Out-Null
                    continue
                }

                $before = [bool]$control.IsChecked
                try {
                    Invoke-QOTTestSliderClick -Control $control
                    $window.UpdateLayout()
                    Invoke-QOTTestUiPump -Milliseconds 50
                }
                catch {
                    $failures.Add(("{0}: click raised an error: {1}" -f $option.Name, $_.Exception.Message)) | Out-Null
                    continue
                }

                $after = [bool]$control.IsChecked
                if ($after -eq $before) {
                    $failures.Add(("{0}: click did not change IsChecked." -f $option.Name)) | Out-Null
                    continue
                }

                if (-not $control.IsEnabled) {
                    $failures.Add(("{0}: control stayed disabled after test-mode click." -f $option.Name)) | Out-Null
                    continue
                }

                Invoke-QOTTestSliderClick -Control $control
                $window.UpdateLayout()
                Invoke-QOTTestUiPump -Milliseconds 50

                if ([bool]$control.IsChecked -ne $before) {
                    $failures.Add(("{0}: second click did not restore the original state." -f $option.Name)) | Out-Null
                }
            }

            Assert-QOTTestSectionSelectors -Window $window -Tabs $tabs -Failures $failures

            if ($failures.Count -gt 0) {
                throw ("Slider option failures:`r`n" + ($failures -join "`r`n"))
            }
        }
        finally {
            if ($window) {
                try { $window.Close() } catch { }
            }
            $env:QOT_UI_TOGGLE_TEST_MODE = $oldToggleTestMode
            if ($null -eq $oldExplorerRestartCount) {
                try { Remove-Item Env:\QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS -ErrorAction SilentlyContinue } catch { }
            }
            else {
                $env:QOT_UI_TOGGLE_TEST_EXPLORER_RESTARTS = $oldExplorerRestartCount
            }
            if ($null -eq $oldOneShotActions) {
                try { Remove-Item Env:\QOT_UI_TEST_SECTION_ONESHOT_ACTIONS -ErrorAction SilentlyContinue } catch { }
            }
            else {
                $env:QOT_UI_TEST_SECTION_ONESHOT_ACTIONS = $oldOneShotActions
            }
            if ($null -eq $oldSettingsPath) {
                try { Remove-Item Env:\QOT_SETTINGS_PATH -ErrorAction SilentlyContinue } catch { }
            }
            else {
                $env:QOT_SETTINGS_PATH = $oldSettingsPath
            }
            if (Test-Path -LiteralPath $testSettingsPath) {
                try { Remove-Item -LiteralPath $testSettingsPath -Force -ErrorAction SilentlyContinue } catch { }
            }
        }
    }

}
