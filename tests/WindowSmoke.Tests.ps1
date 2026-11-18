# Run in Windows PowerShell. The child process owns its dispatcher and fixture files.
param([string]$FixturePath, [ValidateSet('EarlyClose','FreshAppEarlyClose','CloseThenCleanupError','TicketCommands','Normal')][string]$Scenario='Normal')
$ErrorActionPreference = 'Stop'
$parent = [IO.Path]::GetTempPath().TrimEnd('\')
if (!$FixturePath) {
    $scenarios = if ($PSBoundParameters.ContainsKey('Scenario')) { @($Scenario) } else { @('EarlyClose','FreshAppEarlyClose','CloseThenCleanupError','TicketCommands','Normal') }
    foreach ($testScenario in $scenarios) {
        $dir = Join-Path $parent ('Qot WindowTest-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $dir
        try {
            & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File $PSCommandPath -FixturePath $dir -Scenario $testScenario
            if ($LASTEXITCODE) { throw "Window smoke test exited with code $LASTEXITCODE" }
        } finally {
            $target = (Resolve-Path -LiteralPath $dir).Path
            if ((Split-Path $target -Parent) -eq $parent -and (Split-Path $target -Leaf) -match '^Qot WindowTest-[a-f0-9]{32}$') {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
        }
    }
    return
}
$fixture = (Resolve-Path -LiteralPath $FixturePath).Path
if ((Split-Path $fixture -Parent) -ne $parent -or (Split-Path $fixture -Leaf) -notmatch '^Qot WindowTest-[a-f0-9]{32}$' -or @(Get-ChildItem $fixture -Force).Count) {
    throw 'Expected an empty smoke test directory'
}
$repo = Split-Path $PSScriptRoot -Parent
$src = Join-Path $fixture 'src'
Copy-Item -LiteralPath (Join-Path $repo 'src') -Destination $src -Recurse
$env:ProgramData = $fixture
$env:TEMP = $fixture
$env:TMP = $fixture
$env:QOT_SMOKE_DIR = $fixture
$env:QOT_SETTINGS_PATH = Join-Path $fixture 'settings.json'

# Route toolkit data paths to the fixture, including modules that query .NET special folders.
foreach ($file in Get-ChildItem $src -Recurse -File | Where-Object Extension -in '.ps1','.psm1') {
    $original = [IO.File]::ReadAllText($file.FullName)
    $content = $original -replace '(?i)\[Environment\]::GetFolderPath\(\[Environment\+SpecialFolder\]::(?:LocalApplicationData|CommonApplicationData|ApplicationData|DesktopDirectory|CommonDesktopDirectory|MyDocuments|UserProfile)\)', '$env:QOT_SMOKE_DIR'
    $content = $content -replace '(?i)\$env:(?:LOCALAPPDATA|APPDATA|USERPROFILE)\b', '$env:QOT_SMOKE_DIR'
    if ($content -cne $original) { [IO.File]::WriteAllText($file.FullName, $content, [Text.UTF8Encoding]::new($true)) }
}
# Capture the OS drag loop and external editor at the fixture boundary. The WPF
# routed callbacks and task window lifecycle still run normally.
Add-Type 'public static class QotTestDrag { public static object Payload; public static void DoDragDrop(object source, object data, object effect) { Payload = data; } }'
$uiPath = Join-Path $src 'UI/MainWindow.UI.psm1'
$text = [IO.File]::ReadAllText($uiPath)
$text = $text.Replace('[System.Windows.DragDrop]::DoDragDrop(', '[QotTestDrag]::DoDragDrop(')
$text = $text.Replace('$window.Title = "Task Results"', '$window.ShowInTaskbar = $false; $window.ShowActivated = $false; $window.Opacity = 0; $window.Title = "Task Results"')
$text = $text.Replace('Start-Process -FilePath "notepad.exe"', 'Open-TestLogEditor -FilePath "notepad.exe"')
# Quarantine the real startup handoff to a virtual screen outside the desktop.
$text = $text.Replace('[System.Windows.SystemParameters]::VirtualScreenLeft', '(-32000)').Replace('[System.Windows.SystemParameters]::VirtualScreenTop', '(-32000)')
$text = $text.Replace('[System.Windows.WindowStartupLocation]::CenterScreen', '[System.Windows.WindowStartupLocation]::Manual')
$text = $text.Replace('$Window.ShowInTaskbar = $true', '$Window.ShowInTaskbar = $false').Replace('$window.ShowInTaskbar = $true', '$window.ShowInTaskbar = $false')
$viewPath = Join-Path $src 'UI/MainWindow.xaml'
$viewText = [IO.File]::ReadAllText($viewPath).Replace('WindowStartupLocation="CenterScreen"', 'WindowStartupLocation="Manual" Left="-32000" Top="-32000" ShowActivated="False" ShowInTaskbar="False"')
[IO.File]::WriteAllText($viewPath, $viewText)
[IO.File]::WriteAllText($uiPath, $text, [Text.UTF8Encoding]::new($true))
function global:Open-TestLogEditor($FilePath, $ArgumentList) { $global:QotTestEditorArguments = $ArgumentList }
function Add-TestOverrides([string]$RelativePath, [string[]]$Functions) {
    $path = Join-Path $src $RelativePath
    $text = [IO.File]::ReadAllText($path)
    $offset = $text.LastIndexOf('Export-ModuleMember')
    if ($offset -lt 0) { throw "Cannot place test overrides for $RelativePath" }
    $text = $text.Insert($offset, (($Functions -join [Environment]::NewLine) + [Environment]::NewLine))
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($true))
}
Add-TestOverrides 'Tickets/Tickets.UI.psm1' @(
    'function Start-QOTicketsAutoSyncWorker {}', 'function Invoke-QOTicketsEmailSyncAndRefresh {}',
    'function Start-TicketsEmailSyncAsync { throw "Unexpected sync launch" }',
    'function Start-QOTLimitedScheduledProcess { throw "Unexpected scheduler launch" }',
    'function Start-Process { throw "External process blocked in test" }'
)
Add-TestOverrides 'Core/Tickets.psm1' @(
    'function Initialize-QOTicketsReplyQueueService {}', 'function Start-Process { throw "External process blocked in test" }'
)
Add-TestOverrides 'Apps/InstallCommonApps.psm1' @(
    'function Get-QOTWingetInstalledIdSet { return ,([Collections.Generic.HashSet[string]]::new()) }'
)
Get-ChildItem (Join-Path $src 'Tickets') -File -Filter '*Runner.ps1' | ForEach-Object {
    Set-Content -LiteralPath $_.FullName 'throw "External integration blocked in smoke fixture"'
}
Set-Content (Join-Path $src 'Tickets/Tickets.Email.Outlook.psm1') 'function Sync-QOTicketsFromOutlook {}'
Set-Content (Join-Path $src 'Apps/InstalledApps.psm1') @(
    'function Get-QOTInstalledApps { [pscustomobject]@{Name="Scan fixture"; Source="Win32"} }'
    'function Get-QOTInstalledAppsCached { param([switch]$ForceRefresh) Get-QOTInstalledApps }'
)
Get-ChildItem (Join-Path $src 'Scripts') -Recurse -File -Filter '*.ps1' | ForEach-Object {
    Set-Content -LiteralPath $_.FullName 'param($Window); throw "Unexpected non-fixture action"'
}

function Assert([bool]$Condition, [string]$Description) {
    if (!$Condition) { throw $Description }
    Write-Host "PASS $Description"
}
function Wait-For([scriptblock]$Ready) {
    $frame = [Windows.Threading.DispatcherFrame]::new()
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(100)
    $limit = [datetime]::UtcNow.AddSeconds(30)
    $timer.Add_Tick({ if ((& $Ready) -or [datetime]::UtcNow -gt $limit) { $frame.Continue = $false } }.GetNewClosure())
    $timer.Start()
    try { [Windows.Threading.Dispatcher]::PushFrame($frame) } finally { $timer.Stop() }
}
function Test-StartupHandoff {
    param([switch]$CloseAtFirstRender)
    # The splash closes only after the fully opaque main window has painted.
    $splash = [Windows.Markup.XamlReader]::Parse('<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Left="-32000" Top="-32000" Width="30" Height="30" ShowActivated="False" ShowInTaskbar="False"/>')
    $handoff = @{ Rendered = $false; ClosedAfterRender = $false; FirstOpacity = -1; MatchedBackground = $false; ClosedDuringFade = $false }
    $rendered = [System.EventHandler]{
        param($main,$eventArgs)
        if ($handoff.Rendered) { return }
        $handoff.FirstOpacity = $main.Opacity
        $handoff.Rendered = $true
        $source = [Windows.PresentationSource]::FromVisual($main)
        $handoff.MatchedBackground = $source.CompositionTarget.BackgroundColor -eq $main.Background.Color
        if ($CloseAtFirstRender) {
            $handoff.ClosedDuringFade = $splash.IsVisible
            Request-QOTMainWindowClose -Window $main
        }
    }.GetNewClosure()
    $loaded = [Windows.RoutedEventHandler]{
        param($sender,$e)
        if ($sender -is [Windows.Window] -and $sender.Title -eq 'Quinn Optimiser Toolkit') {
            $sender.Add_ContentRendered($rendered)
        }
    }.GetNewClosure()
    [Windows.EventManager]::RegisterClassHandler([Windows.Window], [Windows.FrameworkElement]::LoadedEvent, $loaded)
    $splash.Add_Closed({ $handoff.ClosedAfterRender = $handoff.Rendered }.GetNewClosure())
    $splash.Show()
    $timeout = [datetime]::UtcNow.AddSeconds(45)
    $finish = [Windows.Threading.DispatcherTimer]::new()
    $finish.Interval = [timespan]::FromMilliseconds(100)
    $finish.Add_Tick({
        $main = [Windows.Application]::Current.MainWindow
        if (($handoff.Rendered -and !$splash.IsVisible) -or [datetime]::UtcNow -ge $timeout) {
            $finish.Stop()
            Request-QOTMainWindowClose -Window $main
        }
    }.GetNewClosure())
    $finish.Start()
    try { Start-QOTMainWindow -SplashWindow $splash } finally { $finish.Stop() }
    Assert ($handoff.ClosedAfterRender -and $handoff.FirstOpacity -eq 1) "The first main window frame is opaque and appears before the splash closes (opacity=$($handoff.FirstOpacity), closed after render=$($handoff.ClosedAfterRender))"
    if ($CloseAtFirstRender) {
        Assert ($handoff.ClosedDuringFade -and !$splash.IsVisible) 'Closing the main window during handoff also closes the startup widget'
    }
    Assert $handoff.MatchedBackground 'Native painting surface starts with the main window background colour'
}
Import-Module (Join-Path $src 'UI/MainWindow.UI.psm1') -DisableNameChecking
if ($Scenario -eq 'CloseThenCleanupError') {
    # Keep the actual modal window and close button; inject a failure in the
    # engine after the window loop exits. A retry leaves a marker in the fixture.
    Add-TestOverrides 'Core/Engine/Engine.psm1' @(@'
function Start-QOTMain {
    param($RootPath,$SplashWindow)
    $ui = Join-Path $RootPath 'src/UI/MainWindow.UI.psm1'
    $global:QotSmokeLaunchModule = Import-Module $ui -Force -PassThru
    Start-QOTMainWindow -SplashWindow $SplashWindow
    Set-Content $ui 'function Start-QOTMainWindow { Set-Content (Join-Path $env:QOT_SMOKE_DIR retry.txt) retry }'
    throw 'Simulated cleanup failure after main window close'
}
'@)
    Add-Type -AssemblyName PresentationFramework
    $closeTimer = [Windows.Threading.DispatcherTimer]::new()
    $closeTimer.Interval = [timespan]::FromMilliseconds(100)
    $closeTimer.Add_Tick({
        $main = [Windows.Application]::Current.MainWindow
        if ($main -and $main.IsVisible -and $main.IsLoaded) {
            $closeTimer.Stop()
            $button = $main.FindName('BtnWindowClose')
            $click = [Windows.Controls.Primitives.ButtonBase]::ClickEvent
            $cancel = [ComponentModel.CancelEventHandler]{ param($sender,$e) $e.Cancel = $true }
            $main.Add_Closing($cancel)
            try { $button.RaiseEvent([Windows.RoutedEventArgs]::new($click)) }
            finally { $main.Remove_Closing($cancel) }
            if ($main.IsVisible -and ![Windows.Application]::Current.Properties['QOT.MainWindowClosed']) {
                Set-Content (Join-Path $fixture 'opened.txt') $main.Title
            }
            # Exercise the startup close guard even when building the fixture
            # took more than five seconds on this machine.
            & $global:QotSmokeLaunchModule {
                $script:MainWindowStartupCloseGuard.Restart()
                $script:MainWindowUnexpectedCloseBlocked = $false
            }
            $button.RaiseEvent([Windows.RoutedEventArgs]::new($click))
            if ($main.IsVisible) {
                Set-Content (Join-Path $fixture 'blocked.txt') blocked
                [Windows.Application]::Current.Shutdown()
            }
        }
    })
    # If a broken button leaves the modal loop running, end the fixture and
    # report the failed close instead of waiting for user input.
    $watchdog = [Windows.Threading.DispatcherTimer]::new()
    $watchdog.Interval = [timespan]::FromSeconds(45)
    $watchdog.Add_Tick({
        $watchdog.Stop()
        Set-Content (Join-Path $fixture 'timeout.txt') timeout
        [Windows.Application]::Current.Shutdown()
    })
    $log = Join-Path $fixture 'intro.log'
    $cleanupError = $null
    $closeTimer.Start()
    $watchdog.Start()
    try { & (Join-Path $src 'Intro/Intro.ps1') -SkipSplash -Quiet -LogPath $log }
    catch { $cleanupError = $_ }
    finally { $watchdog.Stop(); $closeTimer.Stop() }
    Assert (!(Test-Path (Join-Path $fixture 'timeout.txt'))) 'The title-bar close completed before the fixture deadline'
    Assert (!(Test-Path (Join-Path $fixture 'blocked.txt'))) 'An explicit title-bar close works during the five-second startup guard'
    Assert ((Get-Content (Join-Path $fixture 'opened.txt')) -eq 'Quinn Optimiser Toolkit') 'A cancelled title-bar close keeps the main window open and its close marker clear'
    Assert ($cleanupError.Exception.Message -eq 'Simulated cleanup failure after main window close') 'Propagated the original cleanup error to the caller'
    $logText = Get-Content -Raw $log
    Assert ($logText -match '\[SHUTDOWN\].*Simulated cleanup failure after main window close' -and $logText -notmatch 'FATAL ERROR') 'Logged the cleanup error without reporting a startup failure'
    Assert (!(Test-Path (Join-Path $fixture 'retry.txt'))) 'A cleanup exception after close cannot start another main window'
    return
}
if ($Scenario -eq 'TicketCommands') {
    & (Join-Path $PSScriptRoot 'TicketCommands.ps1') -FixtureSource $src
    return
}
if ($Scenario -ne 'Normal') {
    Add-Type -AssemblyName PresentationFramework
    if ($Scenario -eq 'EarlyClose') { $null = [Windows.Application]::new() }
    Test-StartupHandoff -CloseAtFirstRender
    return
}
$window = @(Start-QOTMainWindow -WarmupOnly -PassThru) | Where-Object { $_ -is [Windows.Window] } | Select-Object -Last 1
Assert ($window -and !$window.IsVisible) 'Full main window builds hidden'
$tabs = $window.FindName('MainTabControl')
foreach ($pair in @('BtnNavApps:TabApps','BtnNavAdvanced:TabAdvanced','BtnNavTickets:TabTickets','BtnHelp:TabHelp','BtnSettings:TabSettings','BtnNavCleaning:TabCleaning')) {
    $button, $expected = $pair.Split(':')
    $window.FindName($button).RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    Assert ($tabs.SelectedItem.Name -eq $expected) "$button opens $expected"
}
Assert ($window.FindName('HelpHost').Content.FindName('HelpSections').Items.Count -gt 0) 'Help sections populated'
Assert ($null -ne $window.FindName('SettingsHost').Content.FindName('CbShowAppsTab')) 'Settings view populated'
Assert (& (Get-Module MainWindow.UI) { $script:TicketsUIInitialised }) 'Tickets UI initialised with isolated storage and mail'
$ticketUi = Get-Module Tickets.UI
$window.Width = 1000
$window.Height = 650
$window.Left = $window.Top = -32000
$window.ShowActivated = $window.ShowInTaskbar = $false
$window.Show()
$window.UpdateLayout()
$window.FindName('BtnNavTickets').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
function Test-RailButtonTargets([string[]]$Names) {
    $window.UpdateLayout()
    foreach ($name in $Names) {
        $button = $window.FindName($name)
        $center = [Windows.Point]::new($button.ActualWidth / 2, $button.ActualHeight / 2)
        $hit = $window.InputHitTest($button.TranslatePoint($center, $window))
        if (!$hit -or ($button -ne $hit -and !$button.IsAncestorOf($hit))) { return $false }
    }
    return $true
}
$navButtons = @('BtnNavCleaning','BtnNavApps','BtnNavAdvanced','BtnNavTickets','CbQuickSafeCleanup','BtnPlay','BtnLogs','BtnHelp','BtnSettings')
$ticketButtons = @('BtnRailTicketBack','BtnRailTicketNew','BtnRailTicketDelete','BtnRailTicketFilter')
$submenu = $window.FindName('TicketsRailSubmenu')
Assert ($submenu.IsVisible -and (Test-RailButtonTargets ($navButtons + $ticketButtons))) 'Expanded ticket sidebar keeps all navigation and ticket buttons reachable'
$window.FindName('BtnNavTickets').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
Assert (!$submenu.IsVisible -and (Test-RailButtonTargets $navButtons)) 'Collapsed ticket sidebar keeps all navigation buttons reachable'
$window.FindName('BtnNavTickets').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
$ticketGrid = $window.FindName('TicketsGrid')
$assigned = New-QOTicket -Title 'Fixture printer' -AssignedTo 'Pat'
$unassigned = New-QOTicket -Title 'Fixture laptop' -AssignedTo 'Unassigned'
$null = Add-QOTicket -Ticket $assigned
$null = Add-QOTicket -Ticket $unassigned
& $ticketUi { param($grid) $null = Invoke-QOTicketsGridRefresh -Grid $grid -GetTicketsCmd (Get-Command Get-QOTickets) } $ticketGrid
$filterMenu = $window.FindName('BtnTicketsFilterMenu').ContextMenu
$filterMenu.Opacity = 0
$window.FindName('BtnRailTicketFilter').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
$assigneeMenu = $filterMenu.Items | Where-Object Header -eq 'Assigned to'
$pat = $assigneeMenu.Items | Where-Object Tag -eq 'Assignee:Pat'
Assert ($null -ne $pat) 'Sidebar filter lists assignees found on tickets'
$pat.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
$filterMenu.IsOpen = $false
Assert ($ticketGrid.Items.Count -eq 1 -and $ticketGrid.Items[0].Id -eq $assigned.Id -and $pat.IsChecked) 'Clicking an assignee filters the queue and keeps its checkmark'
Assert ((Get-QOTicketListViewSettings).AssigneeFilter -eq 'Pat' -and $window.FindName('BtnRailTicketFilter').ToolTip -match 'Pat') 'Sidebar filter tooltip and saved settings match the visible queue'
$window.FindName('BtnNavCleaning').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
Assert (!$submenu.IsVisible) 'Switching away from Tickets closes its actions'
$window.Hide()
Assert ($window.FindName('InstallGrid').Items.Count -eq 32) 'Apps catalogue populated'
Wait-For { $window.FindName('AppsGrid').Items.Count -gt 0 }
Assert ($window.FindName('AppsGrid').Items[0].Name -eq 'Scan fixture') 'Apps scanner populated the grid'

$ui = Get-Module MainWindow.UI
Show-QOTTaskResultsWindow
$first = & $ui { $script:QOT_TaskResultsWindow }
$buttons = $first.Content.Children[-1].Children
$localLogs = Join-Path $fixture 'StudioVoly/QuinnToolkit/Logs'
$null = New-Item -Path $localLogs -ItemType Directory -Force
$log = Join-Path $localLogs 'QuinnOptimiserToolkit.log'
Set-Content $log 'test'
$buttons[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
$logQuoted = [string]$global:QotTestEditorArguments -eq ('"{0}"' -f $log)
$buttons[1].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
$closed = !$first.IsVisible -and (& $ui { $null -eq $script:QOT_TaskResultsWindow -and $null -eq $script:QOT_TaskResultsGrid })
if ($first.IsVisible) { $first.Close() }
Show-QOTTaskResultsWindow
$second = & $ui { $script:QOT_TaskResultsWindow }
$reopened = $second.IsVisible -and ![object]::ReferenceEquals($first, $second)
$second.Close()

# Invoke the actual registered drag handlers with deterministic pointer coordinates.
function Get-PointerHandler($Control, $Event) {
    $property = [Windows.UIElement].GetProperty('EventHandlersStore', [Reflection.BindingFlags]'Instance,NonPublic')
    $store = $property.GetValue($Control, $null)
    return ($store.GetRoutedEventHandlers($Event)[0].Handler.Target.Constants | Where-Object { $_ -is [scriptblock] } | Select-Object -First 1)
}
$rail = $window.FindName('RailIconHost')
$from = $rail.Children[0]
$onto = $rail.Children[2]
$down = Get-PointerHandler $from ([Windows.UIElement]::PreviewMouseLeftButtonDownEvent)
$move = Get-PointerHandler $from ([Windows.UIElement]::PreviewMouseMoveEvent)
$drop = Get-PointerHandler $onto ([Windows.UIElement]::DropEvent)
$pointer = [pscustomobject]@{ Point=[Windows.Point]::new(0, 0); LeftButton='Pressed'; Handled=$false; Data=$null }
$pointer | Add-Member ScriptMethod GetPosition { param($ignored) $this.Point }
& $down $from $pointer
$pointer.Point = [Windows.Point]::new(0, 1)
& $move $from $pointer
Assert ($null -eq [QotTestDrag]::Payload) 'Small pointer movements leave the rail order unchanged'
$pointer.Point = [Windows.Point]::new(0, 100)
& $move $from $pointer
$pointer.Data = [QotTestDrag]::Payload
if ($null -ne $pointer.Data) {
    $pointer.Point = [Windows.Point]::new(0, 0)
    & $drop $onto $pointer
}
$order = @($rail.Children | ForEach-Object Tag)
$sourceIndex = [array]::IndexOf($order,$from.Tag)
$dragged = $pointer.Data -and $sourceIndex -eq 1 -and $order[2] -eq $onto.Tag
Assert ($closed -and $reopened) 'Task Results closes, releases controls and reopens'
Assert $logQuoted 'Open Full Log passes the complete quoted path'
Assert ([bool]$dragged) 'Sidebar drag moves the selected button to the drop position'
$savedOrder = (Get-Content $env:QOT_SETTINGS_PATH -Raw | ConvertFrom-Json).UiState.RailIconOrder
Assert (($savedOrder -join ',') -eq ($order -join ',')) 'Sidebar saves the new order in fixture settings'

# All nine Quick clean definitions and the Play selection point to this harmless file.
$quickIds = @(
    'Invoke-QCleanTemp','Invoke-QCleanThumbnailCache','Invoke-QCleanDirectXShaderCache',
    'Invoke-QCleanWERQueue','Invoke-QCleanExplorerRecentItems','Invoke-QCleanWindowsSearchHistory',
    'Invoke-QCleanEdgeCache','Invoke-QCleanChromeCache','Invoke-QCleanTeamsCache'
)
Clear-QOTActionGroups
Clear-QOTActionDefinitions
$fake = Join-Path $fixture 'Noop.ps1'
Set-Content $fake 'param($Window); Add-Content -LiteralPath (Join-Path $env:QOT_SMOKE_DIR "calls.txt") "fixture"; [pscustomobject]@{Status="Success";Reason=""}'
foreach ($id in @('Smoke.Noop') + $quickIds) {
    Register-QOTActionDefinition -ActionId $id -Label $id -ScriptPath $fake
    if ((Get-QOTActionDefinition -ActionId $id).ScriptPath -ne $fake) { throw 'Unexpected action script in test catalogue' }
}
Register-QOTActionGroup -Name 'Smoke' -GetItems { param($window); [pscustomobject]@{ActionId='Smoke.Noop'; IsSelected=$true} }
$play = $window.FindName('BtnPlay')
$quick = $window.FindName('CbQuickSafeCleanup')
$calls = Join-Path $fixture 'calls.txt'
foreach ($count in @(1,2,11)) {
    if ($count -eq 11) { $quick.IsChecked = $true } else {
        $play.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    }
    Wait-For { (Test-Path $calls) -and @(Get-Content $calls).Count -ge $count -and $play.IsEnabled -and $quick.IsEnabled }
    $actual = if (Test-Path $calls) { @(Get-Content $calls).Count } else { 0 }
    Assert ($actual -eq $count -and $play.IsEnabled -and $quick.IsEnabled -and !$quick.IsChecked) "Play and Quick clean available after $count fixture calls"
}

Test-StartupHandoff
