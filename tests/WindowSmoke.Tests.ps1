# Run in Windows PowerShell. The child process owns its dispatcher and fixture files.
param([string]$FixturePath)
$ErrorActionPreference = 'Stop'
$parent = [IO.Path]::GetTempPath().TrimEnd('\')
if (!$FixturePath) {
    $dir = Join-Path $parent ('Qot WindowTest-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $dir
    try {
        & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File $PSCommandPath -FixturePath $dir
        if ($LASTEXITCODE) { throw "Window smoke test exited with code $LASTEXITCODE" }
    } finally {
        $target = (Resolve-Path -LiteralPath $dir).Path
        if ((Split-Path $target -Parent) -eq $parent -and (Split-Path $target -Leaf) -match '^Qot WindowTest-[a-f0-9]{32}$') {
            Remove-Item -LiteralPath $target -Recurse -Force
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
Import-Module (Join-Path $src 'UI/MainWindow.UI.psm1') -DisableNameChecking
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
