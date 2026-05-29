# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside MainWindow)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

# ------------------------------------------------------------
# Logger
# ------------------------------------------------------------
$script:QOLog = {
    param([string]$Message)
    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $path = Join-Path $logDir "SettingsUI.log"
        Add-Content -LiteralPath $path -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8
    } catch { }
}

function Write-QOSettingsUILog {
    param([string]$Message)
    & $script:QOLog $Message
}

function Resolve-QOSettingsInvokableCommand {
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

Write-QOSettingsUILog "=== Settings.UI.psm1 LOADED ==="
try { Write-QOSettingsUILog ("Settings path = " + (Get-QOSettingsPath)) } catch { }

# ------------------------------------------------------------
# One time WPF assembly load
# ------------------------------------------------------------
$script:QOSettings_AssembliesLoaded = $false
function Initialize-QOSettingsUIAssemblies {
    if ($script:QOSettings_AssembliesLoaded) { return }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $script:QOSettings_AssembliesLoaded = $true
    Write-QOSettingsUILog "WPF assemblies loaded once"
}

# ------------------------------------------------------------
# Visual tree helpers
# ------------------------------------------------------------
function Find-QOElementByNameAndType {
    param(
        [Parameter(Mandatory)] $Root,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [Type] $Type
    )

    function Walk {
        param($Parent)

        if ($null -eq $Parent) { return $null }

        try {
            if ($Parent -is $Type -and $Parent.Name -eq $Name) { return $Parent }
        } catch { }

        $count = 0
        try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent) }
        catch { return $null }

        for ($i = 0; $i -lt $count; $i++) {
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
            $found = Walk $child
            if ($found) { return $found }
        }

        return $null
    }

    return (Walk $Root)
}

function Get-QOControl {
    param(
        [Parameter(Mandatory)] $Root,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [Type] $Type
    )

    try {
        if ($Root -is [System.Windows.FrameworkElement]) {
            $c = $Root.FindName($Name)
            if ($c -and ($c -is $Type)) { return $c }
        }
    } catch { }

    return Find-QOElementByNameAndType -Root $Root -Name $Name -Type $Type
}

function Convert-SettingsWindowToHostableRoot {
    param([Parameter(Mandatory)][xml]$Doc)

    $win = $Doc.DocumentElement
    if (-not $win -or $win.LocalName -ne "Window") {
        throw "SettingsWindow.xaml root must be <Window>."
    }

    $ns   = $win.NamespaceURI
    $grid = $Doc.CreateElement("Grid", $ns)

    $removeAttrs = @(
        "Title","Height","Width","Topmost","WindowStartupLocation",
        "ResizeMode","SizeToContent","ShowInTaskbar","WindowStyle","AllowsTransparency"
    )

    foreach ($a in @($win.Attributes)) {
        if ($removeAttrs -contains $a.Name) { continue }
        $null = $grid.Attributes.Append($a.Clone())
    }

    foreach ($child in @($win.ChildNodes)) {
        if ($child.NodeType -ne "Element") { continue }

        if ($child.LocalName -eq "Window.Resources") {
            $newRes = $Doc.CreateElement("Grid.Resources", $ns)
            foreach ($rChild in @($child.ChildNodes)) {
                $null = $newRes.AppendChild($rChild.Clone())
            }
            $null = $grid.AppendChild($newRes)
        } else {
            $null = $grid.AppendChild($child.Clone())
        }
    }

    $null = $Doc.RemoveChild($win)
    $null = $Doc.AppendChild($grid)

    return $Doc
}

# ------------------------------------------------------------
# Stored handlers to avoid double wiring
# ------------------------------------------------------------
$script:QOSettings_AddHandler    = $null
$script:QOSettings_RemHandler    = $null
$script:QOSettings_CalHandler    = $null
$script:QOSettings_FollowHandler = $null
$script:QOSettings_TabVisibilityHandler = $null
$script:QOSettings_TabVisibilityCheckedHandler = $null
$script:QOSettings_TabVisibilityUncheckedHandler = $null
$script:QOSettings_TabVisibilityClickHandler = $null
$script:QOSettings_TabVisibilityApplying = $false
$script:QOSettings_BrowseTicketStoreHandler = $null
$script:QOSettings_BrowseTicketBackupHandler = $null
$script:QOSettings_TicketStorageTextChangedHandler = $null
$script:QOSettings_TicketStorageLostFocusHandler = $null
$script:QOSettings_TicketStorageAutoSaveTimer = $null
$script:QOSettings_TicketStorageAutoSaveTimerHandler = $null
$script:QOSettings_TicketStorageAutoSaveSuspend = $false
$script:QOSettings_TicketStorageLastSavedKey = ""
$script:QOSettings_TicketStorageSaveInProgress = $false
$script:QOSettings_InstallShortcutHandler = $null
$script:QOSettings_TicketRecordsRefreshHandler = $null
$script:QOSettings_TicketRecordsExportHandler = $null
$script:QOSettings_TicketRecordsRangeChangedHandler = $null
$script:QOSettings_MainWindow = $null
$script:QOSettings_MainTabs = $null

function Set-QOTMainTabsVisibility {
    param(
        [bool]$ShowCleaning,
        [bool]$ShowApps,
        [bool]$ShowAdvanced,
        [bool]$ShowTickets,
        [AllowNull()][System.Windows.Window]$MainWindow,
        [AllowNull()][System.Windows.Controls.TabControl]$MainTabs
    )

    try {
        $mainWindow = $MainWindow
        $tabs = $MainTabs

        if (-not $mainWindow -and $script:QOSettings_MainWindow) { $mainWindow = $script:QOSettings_MainWindow }
        if (-not $tabs -and $script:QOSettings_MainTabs) { $tabs = $script:QOSettings_MainTabs }

        if ($tabs -and -not $mainWindow) {
            try { $mainWindow = [System.Windows.Window]::GetWindow($tabs) } catch { $mainWindow = $null }
        }
        if ($mainWindow -and -not $tabs) {
            $tabs = Get-QOControl -Root $mainWindow -Name "MainTabControl" -Type ([System.Windows.Controls.TabControl])
        }

        $app = $null
        if (-not $tabs) {
            try { $app = [System.Windows.Application]::Current } catch { $app = $null }
            if ($app) {
                try { $mainWindow = $app.MainWindow } catch { $mainWindow = $null }
                if ($mainWindow) {
                    $tabs = Get-QOControl -Root $mainWindow -Name "MainTabControl" -Type ([System.Windows.Controls.TabControl])
                }
                if (-not $tabs) {
                    try {
                        foreach ($window in @($app.Windows)) {
                            if (-not $window) { continue }
                            $candidateTabs = Get-QOControl -Root $window -Name "MainTabControl" -Type ([System.Windows.Controls.TabControl])
                            if ($candidateTabs) {
                                $mainWindow = $window
                                $tabs = $candidateTabs
                                break
                            }
                        }
                    } catch { }
                }
            }
        }

        if (-not $tabs) {
            Write-QOSettingsUILog "Set-QOTMainTabsVisibility skipped: MainTabControl not found."
            return
        }
        if (-not $mainWindow) {
            try { $mainWindow = [System.Windows.Window]::GetWindow($tabs) } catch { $mainWindow = $null }
        }

        $script:QOSettings_MainWindow = $mainWindow
        $script:QOSettings_MainTabs = $tabs

        $findTabByName = {
            param([string]$Name)
            foreach ($item in @($tabs.Items)) {
                if (-not $item -or -not ($item -is [System.Windows.Controls.TabItem])) { continue }
                $itemName = ""
                try { $itemName = [string]$item.Name } catch { $itemName = "" }
                if ($itemName -eq $Name) { return $item }
            }
            return $null
        }.GetNewClosure()

        $applyVisibility = {
            $tabCleaning = & $findTabByName "TabCleaning"
            $tabApps = & $findTabByName "TabApps"
            $tabAdvanced = & $findTabByName "TabAdvanced"
            $tabTickets = & $findTabByName "TabTickets"

            if ($tabCleaning) { $tabCleaning.Visibility = if ($ShowCleaning) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed } }
            if ($tabApps) { $tabApps.Visibility = if ($ShowApps) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed } }
            if ($tabAdvanced) { $tabAdvanced.Visibility = if ($ShowAdvanced) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed } }
            if ($tabTickets) { $tabTickets.Visibility = if ($ShowTickets) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed } }

            $current = $tabs.SelectedItem
            if ($current -and $current -is [System.Windows.Controls.TabItem] -and $current.Visibility -eq [System.Windows.Visibility]::Visible) {
                try { $tabs.UpdateLayout() } catch { }
                return
            }

            foreach ($candidate in @($tabCleaning, $tabApps, $tabAdvanced, $tabTickets)) {
                if ($candidate -and $candidate.Visibility -eq [System.Windows.Visibility]::Visible) {
                    $tabs.SelectedItem = $candidate
                    break
                }
            }

            try { $tabs.UpdateLayout() } catch { }
        }.GetNewClosure()

        $dispatcher = $null
        try { $dispatcher = $tabs.Dispatcher } catch { $dispatcher = $null }
        if ($dispatcher -and -not $dispatcher.CheckAccess()) {
            $dispatcher.Invoke([action]$applyVisibility)
        } else {
            & $applyVisibility
        }
    } catch {
        Write-QOSettingsUILog ("Set-QOTMainTabsVisibility failed: " + $_.Exception.ToString())
    }
}

function New-QOTSettingsView {
    param(
        [AllowNull()][System.Windows.Window]$MainWindow,
        [AllowNull()][System.Windows.Controls.TabControl]$MainTabs
    )

    Initialize-QOSettingsUIAssemblies

    if ($MainWindow) { $script:QOSettings_MainWindow = $MainWindow }
    if ($MainTabs) {
        $script:QOSettings_MainTabs = $MainTabs
        if (-not $script:QOSettings_MainWindow) {
            try { $script:QOSettings_MainWindow = [System.Windows.Window]::GetWindow($MainTabs) } catch { }
        }
    } elseif ($script:QOSettings_MainWindow -and -not $script:QOSettings_MainTabs) {
        try {
            $script:QOSettings_MainTabs = Get-QOControl -Root $script:QOSettings_MainWindow -Name "MainTabControl" -Type ([System.Windows.Controls.TabControl])
        } catch { }
    }

    $setMonitoredCmd = Resolve-QOSettingsInvokableCommand -Name "Set-QOMonitoredAddresses" -LookupErrorAction Stop
    $getSettingsCmd  = Resolve-QOSettingsInvokableCommand -Name "Get-QOSettings" -LookupErrorAction Stop
    $getMonitoredCmd = Resolve-QOSettingsInvokableCommand -Name "Get-QOMonitoredMailboxAddresses" -LookupErrorAction Stop

    $getPinnedCmd   = Resolve-QOSettingsInvokableCommand -Name "Get-QOEmailSyncStartDatePinned" -LookupErrorAction Stop
    $setPinnedCmd   = Resolve-QOSettingsInvokableCommand -Name "Set-QOEmailSyncStartDatePinned" -LookupErrorAction Stop
    $clearPinnedCmd = Resolve-QOSettingsInvokableCommand -Name "Clear-QOEmailSyncStartDatePinned" -LookupErrorAction Stop
    $getTicketStorageCmd = Resolve-QOSettingsInvokableCommand -Name "Get-QOTicketStorageSettings" -LookupErrorAction Stop
    $setTicketStorageCmd = Resolve-QOSettingsInvokableCommand -Name "Set-QOTicketStorageSettings" -LookupErrorAction Stop
    $resetTicketStorageCacheCmd = Resolve-QOSettingsInvokableCommand -Name "Reset-QOTicketStorageCache" -LookupErrorAction SilentlyContinue
    $getTabVisibilityCmd = Resolve-QOSettingsInvokableCommand -Name "Get-QOTabVisibilitySettings" -LookupErrorAction Stop
    $setTabVisibilityCmd = Resolve-QOSettingsInvokableCommand -Name "Set-QOTabVisibilitySettings" -LookupErrorAction Stop
    $setMainTabsVisibilityCmd = Resolve-QOSettingsInvokableCommand -Name "Set-QOTMainTabsVisibility" -LookupErrorAction Stop
    $getTicketAnalyticsCmd = Resolve-QOSettingsInvokableCommand -Name "Get-QOTicketAnalyticsSnapshot" -LookupErrorAction SilentlyContinue
    $exportTicketsCmd = Resolve-QOSettingsInvokableCommand -Name "Export-QOTicketsToExcelSpreadsheet" -LookupErrorAction SilentlyContinue

    $xamlPath = Join-Path $PSScriptRoot "SettingsWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "SettingsWindow.xaml not found at $xamlPath"
    }

    Write-QOSettingsUILog "Loading SettingsWindow.xaml (hosted)"

    [xml]$doc = Get-Content -LiteralPath $xamlPath -Raw
    $doc = Convert-SettingsWindowToHostableRoot -Doc $doc

    $reader = New-Object System.Xml.XmlNodeReader ($doc)
    $root   = [System.Windows.Markup.XamlReader]::Load($reader)
    if (-not $root) { throw "Failed to load Settings view from SettingsWindow.xaml" }

    $themePath = Join-Path (Join-Path $PSScriptRoot "..\..\UI") "Themes\SharedTheme.xaml"
    if (Test-Path -LiteralPath $themePath) {
        [xml]$themeDoc = Get-Content -LiteralPath $themePath -Raw
        $themeReader = New-Object System.Xml.XmlNodeReader($themeDoc)
        $themeDictionary = [System.Windows.Markup.XamlReader]::Load($themeReader)
        if ($themeDictionary) {
            [void]$root.Resources.MergedDictionaries.Add($themeDictionary)
        }
    }

    # Required controls
    $txtEmail  = Get-QOControl -Root $root -Name "TxtEmail"       -Type ([System.Windows.Controls.TextBox])
    $btnAdd    = Get-QOControl -Root $root -Name "BtnAdd"         -Type ([System.Windows.Controls.Button])
    $btnRem    = Get-QOControl -Root $root -Name "BtnRemove"      -Type ([System.Windows.Controls.Button])
    $list      = Get-QOControl -Root $root -Name "LstEmails"      -Type ([System.Windows.Controls.ListBox])

    $cal       = Get-QOControl -Root $root -Name "CalEmailCutoff" -Type ([System.Windows.Controls.Calendar])
    $btnFollow = Get-QOControl -Root $root -Name "BtnFollowToday" -Type ([System.Windows.Controls.Button])
    $txtTicketStorePath = Get-QOControl -Root $root -Name "TxtTicketStorePath" -Type ([System.Windows.Controls.TextBox])
    $btnBrowseTicketStore = Get-QOControl -Root $root -Name "BtnBrowseTicketStore" -Type ([System.Windows.Controls.Button])
    $txtTicketBackupPath = Get-QOControl -Root $root -Name "TxtTicketBackupPath" -Type ([System.Windows.Controls.TextBox])
    $btnBrowseTicketBackup = Get-QOControl -Root $root -Name "BtnBrowseTicketBackup" -Type ([System.Windows.Controls.Button])
    $cbShowCleaningTab = Get-QOControl -Root $root -Name "CbShowCleaningTab" -Type ([System.Windows.Controls.CheckBox])
    $cbShowAppsTab = Get-QOControl -Root $root -Name "CbShowAppsTab" -Type ([System.Windows.Controls.CheckBox])
    $cbShowAdvancedTab = Get-QOControl -Root $root -Name "CbShowAdvancedTab" -Type ([System.Windows.Controls.CheckBox])
    $cbShowTicketsTab = Get-QOControl -Root $root -Name "CbShowTicketsTab" -Type ([System.Windows.Controls.CheckBox])
    $btnInstallDesktopShortcut = Get-QOControl -Root $root -Name "BtnInstallDesktopShortcut" -Type ([System.Windows.Controls.Button])
    $btnInstallDesktopShortcutImage = Get-QOControl -Root $root -Name "BtnInstallDesktopShortcutImage" -Type ([System.Windows.Controls.Image])
    $btnInstallDesktopShortcutIcon = Get-QOControl -Root $root -Name "BtnInstallDesktopShortcutIcon" -Type ([System.Windows.Controls.TextBlock])
    $lblDesktopShortcutStatus = Get-QOControl -Root $root -Name "LblDesktopShortcutStatus" -Type ([System.Windows.Controls.TextBlock])
    $cmbTicketRecordsRange = Get-QOControl -Root $root -Name "CmbTicketRecordsRange" -Type ([System.Windows.Controls.ComboBox])
    $btnTicketRecordsRefresh = Get-QOControl -Root $root -Name "BtnTicketRecordsRefresh" -Type ([System.Windows.Controls.Button])
    $btnExportTicketsExcel = Get-QOControl -Root $root -Name "BtnExportTicketsExcel" -Type ([System.Windows.Controls.Button])
    $txtTicketRecordsSummary = Get-QOControl -Root $root -Name "TxtTicketRecordsSummary" -Type ([System.Windows.Controls.TextBlock])
    $txtTicketRecordsOpenWaiting = Get-QOControl -Root $root -Name "TxtTicketRecordsOpenWaiting" -Type ([System.Windows.Controls.TextBlock])
    $txtTicketRecordsFirstReply = Get-QOControl -Root $root -Name "TxtTicketRecordsFirstReply" -Type ([System.Windows.Controls.TextBlock])
    $txtTicketRecordsLastUpdated = Get-QOControl -Root $root -Name "TxtTicketRecordsLastUpdated" -Type ([System.Windows.Controls.TextBlock])
    $panelTicketRecordsBars = Get-QOControl -Root $root -Name "PanelTicketRecordsBars" -Type ([System.Windows.Controls.StackPanel])

    $hint      = Get-QOControl -Root $root -Name "LblHint"        -Type ([System.Windows.Controls.TextBlock])

    if (-not $txtEmail)  { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)    { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)    { throw "BtnRemove not found (Button)" }
    if (-not $list)      { throw "LstEmails not found (ListBox)" }
    if (-not $cal)       { throw "CalEmailCutoff not found (Calendar)" }
    if (-not $btnFollow) { throw "BtnFollowToday not found (Button)" }
    if (-not $txtTicketStorePath) { throw "TxtTicketStorePath not found (TextBox)" }
    if (-not $btnBrowseTicketStore) { throw "BtnBrowseTicketStore not found (Button)" }
    if (-not $txtTicketBackupPath) { throw "TxtTicketBackupPath not found (TextBox)" }
    if (-not $btnBrowseTicketBackup) { throw "BtnBrowseTicketBackup not found (Button)" }
    if (-not $cbShowCleaningTab) { throw "CbShowCleaningTab not found (CheckBox)" }
    if (-not $cbShowAppsTab) { throw "CbShowAppsTab not found (CheckBox)" }
    if (-not $cbShowAdvancedTab) { throw "CbShowAdvancedTab not found (CheckBox)" }
    if (-not $cbShowTicketsTab) { throw "CbShowTicketsTab not found (CheckBox)" }
    if (-not $btnInstallDesktopShortcut) { throw "BtnInstallDesktopShortcut not found (Button)" }
    if (-not $btnInstallDesktopShortcutImage) { throw "BtnInstallDesktopShortcutImage not found (Image)" }
    if (-not $btnInstallDesktopShortcutIcon) { throw "BtnInstallDesktopShortcutIcon not found (TextBlock)" }
    if (-not $lblDesktopShortcutStatus) { throw "LblDesktopShortcutStatus not found (TextBlock)" }
    if (-not $cmbTicketRecordsRange) { throw "CmbTicketRecordsRange not found (ComboBox)" }
    if (-not $btnTicketRecordsRefresh) { throw "BtnTicketRecordsRefresh not found (Button)" }
    if (-not $btnExportTicketsExcel) { throw "BtnExportTicketsExcel not found (Button)" }
    if (-not $txtTicketRecordsSummary) { throw "TxtTicketRecordsSummary not found (TextBlock)" }
    if (-not $txtTicketRecordsOpenWaiting) { throw "TxtTicketRecordsOpenWaiting not found (TextBlock)" }
    if (-not $txtTicketRecordsFirstReply) { throw "TxtTicketRecordsFirstReply not found (TextBlock)" }
    if (-not $txtTicketRecordsLastUpdated) { throw "TxtTicketRecordsLastUpdated not found (TextBlock)" }
    if (-not $panelTicketRecordsBars) { throw "PanelTicketRecordsBars not found (StackPanel)" }

    # Bind mailbox list
    $addresses = New-Object "System.Collections.ObjectModel.ObservableCollection[string]"
    foreach ($e in @(& $getMonitoredCmd)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }
    $list.ItemsSource = $addresses
    Write-QOSettingsUILog ("Bound mailbox list. Count=" + $addresses.Count)

    # Initialise calendar state
    try {
        $pinned = & $getPinnedCmd
        if ($pinned) {
            $cal.SelectedDate = $pinned.Date
            $cal.DisplayDate  = $pinned.Date
            if ($hint) { $hint.Text = "Start date pinned to " + $pinned.ToString("dd/MM/yyyy") }
        } else {
            $cal.SelectedDate = $null
            $cal.DisplayDate  = (Get-Date).Date
            if ($hint) { $hint.Text = "Start date follows today until you select a date." }
        }
    } catch {
        Write-QOSettingsUILog ("Init calendar failed: " + $_.Exception.ToString())
        if ($hint) { $hint.Text = "Calendar initialisation failed. Check logs." }
    }

    # Initialise ticket storage paths
    try {
        $storage = & $getTicketStorageCmd
        $script:QOSettings_TicketStorageAutoSaveSuspend = $true
        $txtTicketStorePath.Text = [string]$storage.StorePath
        $txtTicketBackupPath.Text = [string]$storage.BackupPath
        $script:QOSettings_TicketStorageLastSavedKey = ("{0}`n{1}" -f ([string]$txtTicketStorePath.Text).Trim(), ([string]$txtTicketBackupPath.Text).Trim())
    } catch {
        Write-QOSettingsUILog ("Init ticket storage paths failed: " + $_.Exception.ToString())
        $script:QOSettings_TicketStorageAutoSaveSuspend = $true
        $txtTicketStorePath.Text = ""
        $txtTicketBackupPath.Text = ""
        $script:QOSettings_TicketStorageLastSavedKey = ""
    } finally {
        $script:QOSettings_TicketStorageAutoSaveSuspend = $false
    }

    # Initialise tab visibility checkbox state
    try {
        $vis = & $getTabVisibilityCmd
        $cbShowCleaningTab.IsChecked = [bool]$vis.Cleaning
        $cbShowAppsTab.IsChecked = [bool]$vis.Apps
        $cbShowAdvancedTab.IsChecked = [bool]$vis.Advanced
        $cbShowTicketsTab.IsChecked = [bool]$vis.Tickets
    } catch {
        $cbShowCleaningTab.IsChecked = $true
        $cbShowAppsTab.IsChecked = $true
        $cbShowAdvancedTab.IsChecked = $true
        $cbShowTicketsTab.IsChecked = $true
    }

    try {
        if (-not $cmbTicketRecordsRange.SelectedItem -and $cmbTicketRecordsRange.Items.Count -gt 0) {
            $cmbTicketRecordsRange.SelectedIndex = 0
        }
    } catch { }

    # Remove old handlers safely (use remove_* accessors, NOT RemoveHandler)
    try {
        if ($script:QOSettings_AddHandler)    { $btnAdd.remove_Click($script:QOSettings_AddHandler) }
    } catch { }
    try {
        if ($script:QOSettings_RemHandler)    { $btnRem.remove_Click($script:QOSettings_RemHandler) }
    } catch { }
    try {
        if ($script:QOSettings_CalHandler)    { $cal.remove_SelectedDatesChanged($script:QOSettings_CalHandler) }
    } catch { }
    try {
        if ($script:QOSettings_FollowHandler) { $btnFollow.remove_Click($script:QOSettings_FollowHandler) }
    } catch { }
    try {
        if ($script:QOSettings_BrowseTicketStoreHandler) { $btnBrowseTicketStore.remove_Click($script:QOSettings_BrowseTicketStoreHandler) }
    } catch { }
    try {
        if ($script:QOSettings_BrowseTicketBackupHandler) { $btnBrowseTicketBackup.remove_Click($script:QOSettings_BrowseTicketBackupHandler) }
    } catch { }
    try {
        if ($script:QOSettings_TicketStorageTextChangedHandler) {
            $txtTicketStorePath.remove_TextChanged($script:QOSettings_TicketStorageTextChangedHandler)
            $txtTicketBackupPath.remove_TextChanged($script:QOSettings_TicketStorageTextChangedHandler)
        }
    } catch { }
    try {
        if ($script:QOSettings_TicketStorageLostFocusHandler) {
            $txtTicketStorePath.remove_LostFocus($script:QOSettings_TicketStorageLostFocusHandler)
            $txtTicketBackupPath.remove_LostFocus($script:QOSettings_TicketStorageLostFocusHandler)
        }
    } catch { }
    try {
        if ($script:QOSettings_TicketStorageAutoSaveTimer -and $script:QOSettings_TicketStorageAutoSaveTimerHandler) {
            $script:QOSettings_TicketStorageAutoSaveTimer.Stop()
            $script:QOSettings_TicketStorageAutoSaveTimer.remove_Tick($script:QOSettings_TicketStorageAutoSaveTimerHandler)
        }
    } catch { }
    try {
        if ($script:QOSettings_InstallShortcutHandler) { $btnInstallDesktopShortcut.remove_Click($script:QOSettings_InstallShortcutHandler) }
    } catch { }
    try {
        if ($script:QOSettings_TicketRecordsRefreshHandler) { $btnTicketRecordsRefresh.remove_Click($script:QOSettings_TicketRecordsRefreshHandler) }
    } catch { }
    try {
        if ($script:QOSettings_TicketRecordsExportHandler) { $btnExportTicketsExcel.remove_Click($script:QOSettings_TicketRecordsExportHandler) }
    } catch { }
    try {
        if ($script:QOSettings_TicketRecordsRangeChangedHandler) { $cmbTicketRecordsRange.remove_SelectionChanged($script:QOSettings_TicketRecordsRangeChangedHandler) }
    } catch { }
    try {
        if ($script:QOSettings_TabVisibilityCheckedHandler) {
            $cbShowCleaningTab.remove_Checked($script:QOSettings_TabVisibilityCheckedHandler)
            $cbShowAppsTab.remove_Checked($script:QOSettings_TabVisibilityCheckedHandler)
            $cbShowAdvancedTab.remove_Checked($script:QOSettings_TabVisibilityCheckedHandler)
            $cbShowTicketsTab.remove_Checked($script:QOSettings_TabVisibilityCheckedHandler)
        }
    } catch { }
    try {
        if ($script:QOSettings_TabVisibilityUncheckedHandler) {
            $cbShowCleaningTab.remove_Unchecked($script:QOSettings_TabVisibilityUncheckedHandler)
            $cbShowAppsTab.remove_Unchecked($script:QOSettings_TabVisibilityUncheckedHandler)
            $cbShowAdvancedTab.remove_Unchecked($script:QOSettings_TabVisibilityUncheckedHandler)
            $cbShowTicketsTab.remove_Unchecked($script:QOSettings_TabVisibilityUncheckedHandler)
        }
    } catch { }
    try {
        if ($script:QOSettings_TabVisibilityHandler) {
            $cbShowCleaningTab.remove_Click($script:QOSettings_TabVisibilityHandler)
            $cbShowAppsTab.remove_Click($script:QOSettings_TabVisibilityHandler)
            $cbShowAdvancedTab.remove_Click($script:QOSettings_TabVisibilityHandler)
            $cbShowTicketsTab.remove_Click($script:QOSettings_TabVisibilityHandler)
        }
    } catch { }
    try {
        if ($script:QOSettings_TabVisibilityClickHandler) {
            $cbShowCleaningTab.remove_Click($script:QOSettings_TabVisibilityClickHandler)
            $cbShowAppsTab.remove_Click($script:QOSettings_TabVisibilityClickHandler)
            $cbShowAdvancedTab.remove_Click($script:QOSettings_TabVisibilityClickHandler)
            $cbShowTicketsTab.remove_Click($script:QOSettings_TabVisibilityClickHandler)
        }
    } catch { }

    # Add mailbox
    $script:QOSettings_AddHandler = {
        try {
            $addr = ([string]$txtEmail.Text).Trim()
            Write-QOSettingsUILog ("Add clicked. Input='" + $addr + "'")

            if (-not $addr) {
                if ($hint) { $hint.Text = "Enter an email address." }
                return
            }

            $lower = $addr.ToLower()
            foreach ($x in $addresses) {
                if (([string]$x).Trim().ToLower() -eq $lower) {
                    $txtEmail.Text = ""
                    if ($hint) { $hint.Text = "Already exists." }
                    return
                }
            }

            $addresses.Add($addr)
            $txtEmail.Text = ""

            $saveList = @($addresses | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            $null = & $setMonitoredCmd -Addresses $saveList

            $after = & $getSettingsCmd
            $count = @($after.Tickets.EmailIntegration.MonitoredAddresses).Count
            Write-QOSettingsUILog ("Saved. Stored count=" + $count)

            if ($hint) { $hint.Text = "Added " + $addr }
        }
        catch {
            Write-QOSettingsUILog ("Add failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Add stack: " + $_.ScriptStackTrace)
            if ($hint) { $hint.Text = "Add failed. Check logs." }
        }
    }.GetNewClosure()

    # Remove mailbox
    $script:QOSettings_RemHandler = {
        try {
            $sel = $list.SelectedItem
            Write-QOSettingsUILog ("Remove clicked. Selected='" + ($sel + "") + "'")

            if (-not $sel) {
                if ($hint) { $hint.Text = "Select an address to remove." }
                return
            }

            [void]$addresses.Remove([string]$sel)

            $saveList = @($addresses | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            $null = & $setMonitoredCmd -Addresses $saveList

            $after = & $getSettingsCmd
            $count = @($after.Tickets.EmailIntegration.MonitoredAddresses).Count
            Write-QOSettingsUILog ("Removed. Stored count=" + $count)

            if ($hint) { $hint.Text = "Removed " + $sel }
        }
        catch {
            Write-QOSettingsUILog ("Remove failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Remove stack: " + $_.ScriptStackTrace)
            if ($hint) { $hint.Text = "Remove failed. Check logs." }
        }
    }.GetNewClosure()

    # Calendar selected date changed (use native add_SelectedDatesChanged)
    $script:QOSettings_CalHandler = [System.EventHandler[System.Windows.Controls.SelectionChangedEventArgs]]{
        param(
            [object]$sender,
            [System.Windows.Controls.SelectionChangedEventArgs]$e
        )

        try {
            # Ignore events with no added dates (helps reduce noise)
            if (-not $e -or -not $e.AddedItems -or $e.AddedItems.Count -lt 1) { return }

            $picked = $sender.SelectedDate
            if ($picked) {
                $null = & $setPinnedCmd -Date $picked
                if ($hint) { $hint.Text = "Start date pinned to " + $picked.ToString("dd/MM/yyyy") }
                Write-QOSettingsUILog ("Pinned date = " + $picked.ToString("yyyy-MM-dd"))
            }
        } catch {
            Write-QOSettingsUILog ("Calendar handler failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Date selection failed. Check logs." }
        }
    }.GetNewClosure()

    # Follow today button (clears pin)
    $script:QOSettings_FollowHandler = {
        try {
            $null = & $clearPinnedCmd
            $cal.SelectedDate = $null
            $cal.DisplayDate  = (Get-Date).Date
            if ($hint) { $hint.Text = "Start date follows today until you select a date." }
            Write-QOSettingsUILog "Cleared pinned date (follow today)"
        } catch {
            Write-QOSettingsUILog ("Follow today failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Follow today failed. Check logs." }
        }
    }.GetNewClosure()

    $script:QOSettings_BrowseTicketStoreHandler = {
        try {
            $dialog = New-Object Microsoft.Win32.SaveFileDialog
            $dialog.Title = "Select shared tickets file"
            $dialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
            $dialog.FileName = "Tickets.json"
            $dialog.OverwritePrompt = $false

            $seedPath = ([string]$txtTicketStorePath.Text).Trim()
            if ($seedPath) {
                try {
                    $seedDir = Split-Path -Parent $seedPath
                    if ($seedDir -and (Test-Path -LiteralPath $seedDir)) {
                        $dialog.InitialDirectory = $seedDir
                    }
                } catch { }
            }

            $picked = $dialog.ShowDialog()
            if ($picked) {
                $txtTicketStorePath.Text = [string]$dialog.FileName
                & $saveTicketStorageNow
            }
        } catch {
            Write-QOSettingsUILog ("Browse shared store failed: " + $_.Exception.ToString())
        }
    }.GetNewClosure()

    $script:QOSettings_BrowseTicketBackupHandler = {
        try {
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = "Select local ticket backup folder"
            $dialog.UseDescriptionForTitle = $true
            $dialog.ShowNewFolderButton = $true

            $seedPath = ([string]$txtTicketBackupPath.Text).Trim()
            if ($seedPath -and (Test-Path -LiteralPath $seedPath -PathType Container)) {
                $dialog.SelectedPath = $seedPath
            }

            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $txtTicketBackupPath.Text = [string]$dialog.SelectedPath
                & $saveTicketStorageNow
            }
        } catch {
            Write-QOSettingsUILog ("Browse backup path failed: " + $_.Exception.ToString())
        }
    }.GetNewClosure()

    $saveTicketStorageNow = {
        param([switch]$Silent)

        if ($script:QOSettings_TicketStorageAutoSaveSuspend) { return }
        if ($script:QOSettings_TicketStorageSaveInProgress) { return }

        $storePath = ([string]$txtTicketStorePath.Text).Trim()
        $backupPath = ([string]$txtTicketBackupPath.Text).Trim()
        $candidateKey = ("{0}`n{1}" -f $storePath, $backupPath)
        if ($candidateKey -eq $script:QOSettings_TicketStorageLastSavedKey) { return }

        try {
            $script:QOSettings_TicketStorageSaveInProgress = $true
            $savedStorage = & $setTicketStorageCmd -StorePath $storePath -BackupPath $backupPath

            if ($savedStorage) {
                $script:QOSettings_TicketStorageAutoSaveSuspend = $true
                $txtTicketStorePath.Text = [string]$savedStorage.StorePath
                $txtTicketBackupPath.Text = [string]$savedStorage.BackupPath
                $script:QOSettings_TicketStorageLastSavedKey = ("{0}`n{1}" -f ([string]$txtTicketStorePath.Text).Trim(), ([string]$txtTicketBackupPath.Text).Trim())
            } else {
                $script:QOSettings_TicketStorageLastSavedKey = $candidateKey
            }

            if ($resetTicketStorageCacheCmd) {
                try { $null = & $resetTicketStorageCacheCmd } catch { }
            }

            if ($hint -and (-not $Silent)) { $hint.Text = "Ticket storage paths auto-saved." }
            Write-QOSettingsUILog ("Ticket storage paths auto-saved. StorePath={0} BackupPath={1}" -f $txtTicketStorePath.Text, $txtTicketBackupPath.Text)
        } catch {
            Write-QOSettingsUILog ("Ticket storage auto-save failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Ticket storage save failed. Check logs." }
        } finally {
            $script:QOSettings_TicketStorageAutoSaveSuspend = $false
            $script:QOSettings_TicketStorageSaveInProgress = $false
        }
    }.GetNewClosure()

    $script:QOSettings_TicketStorageAutoSaveTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:QOSettings_TicketStorageAutoSaveTimer.Interval = [System.TimeSpan]::FromMilliseconds(500)
    $script:QOSettings_TicketStorageAutoSaveTimerHandler = [System.EventHandler]{
        param($sender, $eventArgs)
        try { $sender.Stop() } catch { }
        & $saveTicketStorageNow -Silent
    }.GetNewClosure()
    $script:QOSettings_TicketStorageAutoSaveTimer.add_Tick($script:QOSettings_TicketStorageAutoSaveTimerHandler)

    $script:QOSettings_TicketStorageTextChangedHandler = [System.Windows.Controls.TextChangedEventHandler]{
        param($sender, $eventArgs)
        if ($script:QOSettings_TicketStorageAutoSaveSuspend) { return }
        try {
            if ($script:QOSettings_TicketStorageAutoSaveTimer) {
                $script:QOSettings_TicketStorageAutoSaveTimer.Stop()
                $script:QOSettings_TicketStorageAutoSaveTimer.Start()
            }
        } catch { }
    }.GetNewClosure()

    $script:QOSettings_TicketStorageLostFocusHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $eventArgs)
        try {
            if ($script:QOSettings_TicketStorageAutoSaveTimer) { $script:QOSettings_TicketStorageAutoSaveTimer.Stop() }
        } catch { }
        & $saveTicketStorageNow
    }.GetNewClosure()

    $script:QOSettings_TabVisibilityHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            if ($script:QOSettings_TabVisibilityApplying) { return }
            $script:QOSettings_TabVisibilityApplying = $true

            $showCleaning = [bool]$cbShowCleaningTab.IsChecked
            $showApps = [bool]$cbShowAppsTab.IsChecked
            $showAdvanced = [bool]$cbShowAdvancedTab.IsChecked
            $showTickets = [bool]$cbShowTicketsTab.IsChecked

            if (-not ($showCleaning -or $showApps -or $showAdvanced -or $showTickets)) {
                $showTickets = $true
                $cbShowTicketsTab.IsChecked = $true
            }

            Write-QOSettingsUILog ("Tab visibility request: Cleaning={0} Apps={1} Advanced={2} Tickets={3}" -f $showCleaning, $showApps, $showAdvanced, $showTickets)

            $saved = & $setTabVisibilityCmd -Cleaning $showCleaning -Apps $showApps -Advanced $showAdvanced -Tickets $showTickets
            if ($saved) {
                $cbShowCleaningTab.IsChecked = [bool]$saved.Cleaning
                $cbShowAppsTab.IsChecked = [bool]$saved.Apps
                $cbShowAdvancedTab.IsChecked = [bool]$saved.Advanced
                $cbShowTicketsTab.IsChecked = [bool]$saved.Tickets
                & $setMainTabsVisibilityCmd -ShowCleaning ([bool]$saved.Cleaning) -ShowApps ([bool]$saved.Apps) -ShowAdvanced ([bool]$saved.Advanced) -ShowTickets ([bool]$saved.Tickets) -MainWindow $script:QOSettings_MainWindow -MainTabs $script:QOSettings_MainTabs
                Write-QOSettingsUILog ("Tab visibility applied from saved state: Cleaning={0} Apps={1} Advanced={2} Tickets={3}" -f ([bool]$saved.Cleaning), ([bool]$saved.Apps), ([bool]$saved.Advanced), ([bool]$saved.Tickets))
            } else {
                & $setMainTabsVisibilityCmd -ShowCleaning $showCleaning -ShowApps $showApps -ShowAdvanced $showAdvanced -ShowTickets $showTickets -MainWindow $script:QOSettings_MainWindow -MainTabs $script:QOSettings_MainTabs
                Write-QOSettingsUILog ("Tab visibility applied from requested state (save returned null).")
            }

            if ($hint) { $hint.Text = "Tab visibility updated." }
        }
        catch {
            Write-QOSettingsUILog ("Tab visibility save failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Tab visibility save failed. Check logs." }
        }
        finally {
            $script:QOSettings_TabVisibilityApplying = $false
        }
    }.GetNewClosure()

    $script:QOSettings_TabVisibilityCheckedHandler = $script:QOSettings_TabVisibilityHandler
    $script:QOSettings_TabVisibilityUncheckedHandler = $script:QOSettings_TabVisibilityHandler
    $script:QOSettings_TabVisibilityClickHandler = $script:QOSettings_TabVisibilityHandler

    $resolveTicketRecordRange = {
        $rangeValue = "All"
        try {
            $selected = $cmbTicketRecordsRange.SelectedItem
            if ($selected -is [System.Windows.Controls.ComboBoxItem]) {
                $tagValue = ([string]($selected.Tag + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($tagValue)) {
                    $rangeValue = $tagValue
                }
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$cmbTicketRecordsRange.Text)) {
                $textValue = ([string]$cmbTicketRecordsRange.Text).Trim().ToLowerInvariant()
                switch -Regex ($textValue) {
                    "year" { $rangeValue = "Year"; break }
                    "month" { $rangeValue = "Month"; break }
                    "week" { $rangeValue = "Week"; break }
                    "today|day" { $rangeValue = "Day"; break }
                    default { $rangeValue = "All" }
                }
            }
        } catch { $rangeValue = "All" }
        return $rangeValue
    }.GetNewClosure()

    $createTicketRecordBarRow = {
        param(
            [string]$Name,
            [int]$Count,
            [int]$MaxCount
        )

        $safeMax = if ($MaxCount -lt 1) { 1 } else { $MaxCount }
        $safeCount = if ($Count -lt 0) { 0 } else { $Count }

        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
        $rowBorder.Padding = New-Object System.Windows.Thickness(6, 4, 6, 4)
        $rowBorder.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#0B1220"))
        $rowBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#1F2A44"))
        $rowBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $rowBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)

        $rowGrid = New-Object System.Windows.Controls.Grid
        $colName = New-Object System.Windows.Controls.ColumnDefinition
        $colName.Width = [System.Windows.GridLength]::new(120)
        $colBar = New-Object System.Windows.Controls.ColumnDefinition
        $colBar.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $colCount = New-Object System.Windows.Controls.ColumnDefinition
        $colCount.Width = [System.Windows.GridLength]::new(42)
        $rowGrid.ColumnDefinitions.Add($colName)
        $rowGrid.ColumnDefinitions.Add($colBar)
        $rowGrid.ColumnDefinitions.Add($colCount)

        $txtName = New-Object System.Windows.Controls.TextBlock
        $txtName.Text = [string]$Name
        $txtName.Foreground = [System.Windows.Media.Brushes]::White
        $txtName.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $txtName.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        [System.Windows.Controls.Grid]::SetColumn($txtName, 0)

        $bar = New-Object System.Windows.Controls.ProgressBar
        $bar.Height = 12
        $bar.Minimum = 0
        $bar.Maximum = $safeMax
        $bar.Value = $safeCount
        $bar.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $bar.Margin = New-Object System.Windows.Thickness(8, 0, 8, 0)
        $bar.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#2563EB"))
        $bar.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#172033"))
        [System.Windows.Controls.Grid]::SetColumn($bar, 1)

        $txtCount = New-Object System.Windows.Controls.TextBlock
        $txtCount.Text = [string]$safeCount
        $txtCount.Foreground = [System.Windows.Media.Brushes]::White
        $txtCount.FontWeight = [System.Windows.FontWeights]::SemiBold
        $txtCount.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
        $txtCount.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($txtCount, 2)

        $null = $rowGrid.Children.Add($txtName)
        $null = $rowGrid.Children.Add($bar)
        $null = $rowGrid.Children.Add($txtCount)
        $rowBorder.Child = $rowGrid
        return $rowBorder
    }.GetNewClosure()

    $refreshTicketRecords = {
        param([switch]$Silent)

        try {
            $panelTicketRecordsBars.Children.Clear()
        } catch { }

        if (-not $getTicketAnalyticsCmd) {
            $txtTicketRecordsSummary.Text = "Ticket records unavailable."
            $txtTicketRecordsOpenWaiting.Text = "Open/waiting age: n/a"
            $txtTicketRecordsFirstReply.Text = "First reply: n/a"
            $txtTicketRecordsLastUpdated.Text = "Updated: command missing"
            if ($btnExportTicketsExcel) { $btnExportTicketsExcel.IsEnabled = $false }
            return
        }

        try {
            $rangeValue = & $resolveTicketRecordRange
            $snapshot = & $getTicketAnalyticsCmd -Range $rangeValue

            if (-not $snapshot) {
                throw "Snapshot returned null."
            }

            $total = [int]$snapshot.TotalTickets
            $openCount = [int]$snapshot.OpenTickets
            $pendingCount = [int]$snapshot.PendingTickets
            $closedCount = [int]$snapshot.ClosedTickets
            $avgOpenHours = [double]$snapshot.AverageOpenAgeHours
            $avgPendingHours = [double]$snapshot.AveragePendingAgeHours
            $avgFirstReplyMinutes = [double]$snapshot.AverageFirstReplyMinutes
            $firstReplySamples = [int]$snapshot.FirstReplySamples

            $txtTicketRecordsSummary.Text = ("Tickets: {0} | Open: {1} | Waiting: {2} | Closed: {3}" -f $total, $openCount, $pendingCount, $closedCount)
            $txtTicketRecordsOpenWaiting.Text = ("Avg open age: {0}h | Avg waiting age: {1}h" -f $avgOpenHours.ToString("0.##"), $avgPendingHours.ToString("0.##"))
            if ($firstReplySamples -gt 0) {
                $txtTicketRecordsFirstReply.Text = ("IT first reply: {0} mins ({1} tickets)" -f $avgFirstReplyMinutes.ToString("0.##"), $firstReplySamples)
            } else {
                $txtTicketRecordsFirstReply.Text = "IT first reply: n/a (no replied tickets in range)"
            }

            $userCounts = @($snapshot.UserCounts)
            if ($userCounts.Count -eq 0) {
                $emptyText = New-Object System.Windows.Controls.TextBlock
                $emptyText.Text = "No tickets in this range."
                $emptyText.Foreground = [System.Windows.Media.Brushes]::LightGray
                $emptyText.Margin = New-Object System.Windows.Thickness(4, 2, 4, 2)
                $null = $panelTicketRecordsBars.Children.Add($emptyText)
            } else {
                $maxCount = 1
                try {
                    $maxCount = [int](($userCounts | Measure-Object -Property Count -Maximum).Maximum)
                    if ($maxCount -lt 1) { $maxCount = 1 }
                } catch { $maxCount = 1 }

                foreach ($item in $userCounts) {
                    if ($null -eq $item) { continue }
                    $name = [string]($item.Name + "")
                    if ([string]::IsNullOrWhiteSpace($name)) { $name = "Unassigned" }
                    $count = 0
                    try { $count = [int]$item.Count } catch { $count = 0 }
                    $row = & $createTicketRecordBarRow -Name $name -Count $count -MaxCount $maxCount
                    if ($row) { $null = $panelTicketRecordsBars.Children.Add($row) }
                }
            }

            $generatedAt = [string]($snapshot.GeneratedAt + "")
            if ([string]::IsNullOrWhiteSpace($generatedAt)) {
                $generatedAt = (Get-Date).ToString("g")
            }
            $txtTicketRecordsLastUpdated.Text = ("Updated: {0} ({1})" -f $generatedAt, $rangeValue)

            if (-not $Silent) {
                if ($hint) { $hint.Text = "Ticket records refreshed." }
            }
        } catch {
            $txtTicketRecordsSummary.Text = "Ticket records failed to load."
            $txtTicketRecordsOpenWaiting.Text = "Open/waiting age: n/a"
            $txtTicketRecordsFirstReply.Text = "First reply: n/a"
            $txtTicketRecordsLastUpdated.Text = "Updated: failed"
            Write-QOSettingsUILog ("Ticket records refresh failed: " + $_.Exception.ToString())
            if (-not $Silent -and $hint) {
                $hint.Text = "Ticket records refresh failed. Check logs."
            }
        }
    }.GetNewClosure()

    $script:QOSettings_TicketRecordsRefreshHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        & $refreshTicketRecords
    }.GetNewClosure()

    $script:QOSettings_TicketRecordsRangeChangedHandler = [System.Windows.Controls.SelectionChangedEventHandler]{
        param($sender, $args)
        & $refreshTicketRecords -Silent
    }.GetNewClosure()

    $script:QOSettings_TicketRecordsExportHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            if (-not $exportTicketsCmd) {
                if ($hint) { $hint.Text = "Ticket export unavailable (command missing)." }
                return
            }

            $dialog = New-Object Microsoft.Win32.SaveFileDialog
            $dialog.Title = "Export tickets to Excel-ready CSV"
            $dialog.Filter = "Excel-ready CSV (*.csv)|*.csv|All files (*.*)|*.*"
            $dialog.FileName = ("QOT_Tickets_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmm"))
            $dialog.AddExtension = $true
            $dialog.DefaultExt = "csv"
            $picked = $dialog.ShowDialog()
            if (-not $picked) { return }

            $rangeValue = & $resolveTicketRecordRange
            $result = & $exportTicketsCmd -Path ([string]$dialog.FileName) -Range $rangeValue
            if ($result -and [bool]$result.Success) {
                $txtTicketRecordsLastUpdated.Text = ("Updated: export complete ({0} rows, {1})" -f ([int]$result.Count, $rangeValue))
                if ($hint) { $hint.Text = ("Tickets exported: {0}" -f [string]$result.Path) }
            } else {
                $note = ""
                try { $note = [string]$result.Note } catch { $note = "" }
                if ($hint) { $hint.Text = ("Ticket export failed. " + $note) }
            }
        } catch {
            Write-QOSettingsUILog ("Ticket export failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Ticket export failed. Check logs." }
        }
    }.GetNewClosure()

    $getDesktopShortcutPaths = {
        $paths = New-Object System.Collections.Generic.List[string]
        $desktopPaths = @()
        try { $desktopPaths += [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory) } catch { }
        try { $desktopPaths += [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDesktopDirectory) } catch { }

        $desktopPaths = $desktopPaths |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique

        foreach ($desktopPath in $desktopPaths) {
            foreach ($candidate in @("Quinn Optimiser Toolkit.lnk", "Quinn Optimiser Toolkit*.lnk", "Quinn Optimiser Toolkit*.url")) {
                try {
                    if ($candidate -like "*`**") {
                        $matches = Get-ChildItem -LiteralPath $desktopPath -Filter $candidate -File -ErrorAction SilentlyContinue
                        foreach ($match in $matches) {
                            if ($match -and -not [string]::IsNullOrWhiteSpace($match.FullName)) {
                                [void]$paths.Add([string]$match.FullName)
                            }
                        }
                    } else {
                        $candidatePath = Join-Path $desktopPath $candidate
                        if (Test-Path -LiteralPath $candidatePath) {
                            [void]$paths.Add([string]$candidatePath)
                        }
                    }
                } catch { }
            }
        }

        return ($paths | Select-Object -Unique)
    }.GetNewClosure()

    $refreshShellDesktop = {
        try {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class QOTShellRefresh {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@ -ErrorAction SilentlyContinue | Out-Null
            [QOTShellRefresh]::SHChangeNotify(0x8000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
        } catch {
            try {
                Start-Process -FilePath (Join-Path $env:WINDIR "System32\ie4uinit.exe") -ArgumentList "-show" -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
            } catch { }
        }
    }.GetNewClosure()

    $resolveDesktopShortcutImage = {
        param(
            [Parameter(Mandatory=$true)][bool]$Installed
        )

        $repoRootPath = $null
        try { $repoRootPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path } catch { $repoRootPath = $null }
        if (-not $repoRootPath) { return $null }

        $uiDir = Join-Path $repoRootPath "src\UI"
        if (-not (Test-Path -LiteralPath $uiDir)) { return $null }

        try {
            $allImages = Get-ChildItem -LiteralPath $uiDir -File -ErrorAction SilentlyContinue | Where-Object {
                $_.Extension -in @(".png", ".jpg", ".jpeg")
            }

            if ($Installed) {
                $match = $allImages |
                    Where-Object { $_.Name -match "(?i)uninstall" } |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1
                if ($match -and (Test-Path -LiteralPath $match.FullName)) {
                    return [string]$match.FullName
                }
            } else {
                $match = $allImages |
                    Where-Object { $_.Name -match "(?i)install" -and $_.Name -notmatch "(?i)uninstall" } |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1
                if ($match -and (Test-Path -LiteralPath $match.FullName)) {
                    return [string]$match.FullName
                }
            }
        } catch { }

        return $null
    }.GetNewClosure()

    $updateDesktopShortcutUiState = {
        $result = [pscustomobject]@{
            Installed = $false
            ShortcutPath = $null
            AllShortcutPaths = @()
        }
        try {
            $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
            if ([string]::IsNullOrWhiteSpace($desktopPath)) {
                throw "Unable to resolve desktop folder."
            }

            $result.ShortcutPath = Join-Path $desktopPath "Quinn Optimiser Toolkit.lnk"
            $result.AllShortcutPaths = @(& $getDesktopShortcutPaths)
            $result.Installed = (($result.AllShortcutPaths | Measure-Object).Count -gt 0)

            if ($btnInstallDesktopShortcut) {
                if ($result.Installed) {
                    $btnInstallDesktopShortcut.ToolTip = "Remove the Quinn Optimiser Toolkit desktop icon"
                } else {
                    $btnInstallDesktopShortcut.ToolTip = "Create or refresh the Quinn Optimiser Toolkit desktop icon"
                }
            }

            $stateImagePath = & $resolveDesktopShortcutImage -Installed ([bool]$result.Installed)
            $imageSet = $false
            if ($btnInstallDesktopShortcutImage) {
                if ($stateImagePath -and (Test-Path -LiteralPath $stateImagePath)) {
                    try {
                        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                        $bitmap.BeginInit()
                        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                        $bitmap.UriSource = New-Object System.Uri($stateImagePath, [System.UriKind]::Absolute)
                        $bitmap.EndInit()
                        $bitmap.Freeze()
                        $btnInstallDesktopShortcutImage.Source = $bitmap
                        $imageSet = $true
                    } catch {
                        $btnInstallDesktopShortcutImage.Source = $null
                    }
                } else {
                    $btnInstallDesktopShortcutImage.Source = $null
                }
            }

            if ($btnInstallDesktopShortcutIcon) {
                if ($imageSet) {
                    $btnInstallDesktopShortcutIcon.Visibility = [System.Windows.Visibility]::Collapsed
                } else {
                    $btnInstallDesktopShortcutIcon.Visibility = [System.Windows.Visibility]::Visible
                    if ($result.Installed) {
                        $btnInstallDesktopShortcutIcon.Text = [char]0xE898
                        $btnInstallDesktopShortcutIcon.Foreground = [System.Windows.Media.Brushes]::Salmon
                    } else {
                        $btnInstallDesktopShortcutIcon.Text = [char]0xE896
                        $btnInstallDesktopShortcutIcon.Foreground = [System.Windows.Media.Brushes]::DeepSkyBlue
                    }
                }
            }

            if ($lblDesktopShortcutStatus) {
                if ($result.Installed) {
                    $lblDesktopShortcutStatus.Text = ("Desktop icon installed ({0} shortcut{1})." -f (($result.AllShortcutPaths | Measure-Object).Count), ($(if ((($result.AllShortcutPaths | Measure-Object).Count) -eq 1) { "" } else { "s" })))
                } else {
                    $lblDesktopShortcutStatus.Text = "Desktop icon not installed yet."
                }
            }
        } catch {
            if ($lblDesktopShortcutStatus) {
                $lblDesktopShortcutStatus.Text = ("Desktop icon status unavailable: {0}" -f $_.Exception.Message)
            }
            Write-QOSettingsUILog ("Desktop icon state check failed: " + $_.Exception.ToString())
        }
        return $result
    }.GetNewClosure()

    $script:QOSettings_InstallShortcutHandler = {
        $shell = $null
        $shortcut = $null
        try {
            $state = & $updateDesktopShortcutUiState
            if (-not $state -or [string]::IsNullOrWhiteSpace([string]$state.ShortcutPath)) {
                throw "Unable to resolve desktop shortcut path."
            }

            if ([bool]$state.Installed) {
                $removedCount = 0
                foreach ($existingShortcut in @($state.AllShortcutPaths)) {
                    if ([string]::IsNullOrWhiteSpace([string]$existingShortcut)) { continue }
                    try {
                        Remove-Item -LiteralPath ([string]$existingShortcut) -Force -ErrorAction Stop
                        $removedCount++
                    } catch {
                        Write-QOSettingsUILog ("Desktop shortcut remove failed for '{0}': {1}" -f [string]$existingShortcut, $_.Exception.Message)
                    }
                }
                & $refreshShellDesktop | Out-Null
                & $updateDesktopShortcutUiState | Out-Null
                if ($hint) { $hint.Text = "Desktop icon removed." }
                Write-QOSettingsUILog ("Desktop shortcut uninstall requested. Removed={0}" -f $removedCount)
                return
            }

            $repoRootPath = $null
            try { $repoRootPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path } catch { $repoRootPath = $null }
            if (-not $repoRootPath) { throw "Unable to resolve repository root path." }

            $introScriptPath = $null
            try { $introScriptPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..\Intro\Intro.ps1")).Path } catch { $introScriptPath = $null }
            if (-not $introScriptPath) { throw "Intro launcher script not found." }

            $powerShellPath = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
            if (-not (Test-Path -LiteralPath $powerShellPath)) { throw "Windows PowerShell executable not found." }
            $wscriptPath = Join-Path $env:WINDIR "System32\wscript.exe"
            if (-not (Test-Path -LiteralPath $wscriptPath)) { throw "Windows Script Host executable not found." }

            $iconPath = Join-Path $repoRootPath "src\UI\QOT.ico"
            $launcherScriptPath = Join-Path $repoRootPath "src\Intro\LaunchQuinnHidden.vbs"
            $launcherContent = @"
Option Explicit
Dim shell, cmd
Set shell = CreateObject("WScript.Shell")
cmd = Chr(34) & "$($powerShellPath.Replace('"','""'))" & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -STA -File " & Chr(34) & "$($introScriptPath.Replace('"','""'))" & Chr(34)
shell.Run cmd, 0, False
"@
            Set-Content -LiteralPath $launcherScriptPath -Value $launcherContent -Encoding ASCII -Force

            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut([string]$state.ShortcutPath)
            $shortcut.TargetPath = $wscriptPath
            $shortcut.Arguments = "`"$launcherScriptPath`""
            $shortcut.WorkingDirectory = $repoRootPath
            $shortcut.Description = "Launch Quinn Optimiser Toolkit"
            if (Test-Path -LiteralPath $iconPath) {
                $shortcut.IconLocation = "$iconPath,0"
            } else {
                $shortcut.IconLocation = "$powerShellPath,0"
            }
            $shortcut.Save()
            if ($shortcut) { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
            if ($shell) { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }

            & $refreshShellDesktop | Out-Null
            & $updateDesktopShortcutUiState | Out-Null
            if ($hint) { $hint.Text = "Desktop shortcut installed." }
            Write-QOSettingsUILog ("Desktop shortcut installed: {0}" -f $state.ShortcutPath)
        } catch {
            try { if ($shortcut) { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) } } catch { }
            try { if ($shell) { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) } } catch { }
            if ($lblDesktopShortcutStatus) {
                $lblDesktopShortcutStatus.Text = ("Shortcut install failed: {0}" -f $_.Exception.Message)
            }
            if ($hint) { $hint.Text = "Desktop shortcut install failed. Check logs." }
            Write-QOSettingsUILog ("Desktop shortcut install failed: " + $_.Exception.ToString())
        }
    }.GetNewClosure()

    # Wire handlers (NO AddHandler)
    $btnAdd.add_Click($script:QOSettings_AddHandler)
    $btnRem.add_Click($script:QOSettings_RemHandler)
    $cal.add_SelectedDatesChanged($script:QOSettings_CalHandler)
    $btnFollow.add_Click($script:QOSettings_FollowHandler)
    $btnBrowseTicketStore.add_Click($script:QOSettings_BrowseTicketStoreHandler)
    $btnBrowseTicketBackup.add_Click($script:QOSettings_BrowseTicketBackupHandler)
    $txtTicketStorePath.add_TextChanged($script:QOSettings_TicketStorageTextChangedHandler)
    $txtTicketBackupPath.add_TextChanged($script:QOSettings_TicketStorageTextChangedHandler)
    $txtTicketStorePath.add_LostFocus($script:QOSettings_TicketStorageLostFocusHandler)
    $txtTicketBackupPath.add_LostFocus($script:QOSettings_TicketStorageLostFocusHandler)
    $btnInstallDesktopShortcut.add_Click($script:QOSettings_InstallShortcutHandler)
    $btnTicketRecordsRefresh.add_Click($script:QOSettings_TicketRecordsRefreshHandler)
    $btnExportTicketsExcel.add_Click($script:QOSettings_TicketRecordsExportHandler)
    $cmbTicketRecordsRange.add_SelectionChanged($script:QOSettings_TicketRecordsRangeChangedHandler)
    $cbShowCleaningTab.add_Checked($script:QOSettings_TabVisibilityCheckedHandler)
    $cbShowAppsTab.add_Checked($script:QOSettings_TabVisibilityCheckedHandler)
    $cbShowAdvancedTab.add_Checked($script:QOSettings_TabVisibilityCheckedHandler)
    $cbShowTicketsTab.add_Checked($script:QOSettings_TabVisibilityCheckedHandler)
    $cbShowCleaningTab.add_Unchecked($script:QOSettings_TabVisibilityUncheckedHandler)
    $cbShowAppsTab.add_Unchecked($script:QOSettings_TabVisibilityUncheckedHandler)
    $cbShowAdvancedTab.add_Unchecked($script:QOSettings_TabVisibilityUncheckedHandler)
    $cbShowTicketsTab.add_Unchecked($script:QOSettings_TabVisibilityUncheckedHandler)
    $cbShowCleaningTab.add_Click($script:QOSettings_TabVisibilityClickHandler)
    $cbShowAppsTab.add_Click($script:QOSettings_TabVisibilityClickHandler)
    $cbShowAdvancedTab.add_Click($script:QOSettings_TabVisibilityClickHandler)
    $cbShowTicketsTab.add_Click($script:QOSettings_TabVisibilityClickHandler)

    # Apply visibility immediately when opening Settings in case config changed outside this session.
    & $setMainTabsVisibilityCmd -ShowCleaning ([bool]$cbShowCleaningTab.IsChecked) -ShowApps ([bool]$cbShowAppsTab.IsChecked) -ShowAdvanced ([bool]$cbShowAdvancedTab.IsChecked) -ShowTickets ([bool]$cbShowTicketsTab.IsChecked) -MainWindow $script:QOSettings_MainWindow -MainTabs $script:QOSettings_MainTabs
    & $updateDesktopShortcutUiState | Out-Null
    & $refreshTicketRecords -Silent

    Write-QOSettingsUILog "Wired handlers using add_* accessors (no AddHandler)"

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView, Write-QOSettingsUILog
