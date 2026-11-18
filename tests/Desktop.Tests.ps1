# Run with Windows PowerShell -NoProfile -STA -File tests\Desktop.Tests.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tempRoot = [IO.Path]::GetTempPath()
$fixture = Join-Path $tempRoot ('QOT-desktop-test-' + [guid]::NewGuid())
$null = New-Item -Type Directory -Path $fixture
$previous = @{}
foreach ($key in 'QOT_SETTINGS_PATH','LOCALAPPDATA','ProgramData') {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key)
}
$env:LOCALAPPDATA = $env:ProgramData = $fixture
$env:QOT_SETTINGS_PATH = Join-Path $fixture 'settings.json'
$failures = @()
function Test-Case($name, [scriptblock]$body) {
    try { & $body; Write-Host "PASS $name" }
    catch { $script:failures += $name; Write-Host "FAIL $name - $($_.Exception.Message)" }
}
try {
    Add-Type -AssemblyName PresentationFramework
    Import-Module (Join-Path $root 'src\Core\Settings.psm1')
    Import-Module (Join-Path $root 'src\Core\Actions\ActionRegistry.psm1') -DisableNameChecking
    $ui = Import-Module (Join-Path $root 'src\UI\MainWindow.UI.psm1') -PassThru -DisableNameChecking
    Test-Case 'Removing the last monitored mailbox survives a settings reload' {
        $null = Set-QOMonitoredAddresses -Addresses @('tech@example.invalid')
        $null = Set-QOMonitoredAddresses -Addresses @()
        if (@(Get-QOMonitoredMailboxAddresses).Count) { throw 'Address still saved' }
    }
    Test-Case 'Partially populated legacy settings preserve custom values and gain defaults' {
        Set-Content -LiteralPath $env:QOT_SETTINGS_PATH -Value '{"PreferredStartTab":"Apps","Tickets":{"ListView":false},"ExtensionSetting":17}'
        $s = Get-QOSettings
        if ($s.ExtensionSetting -ne 17 -or $s.PreferredStartTab -ne 'Apps' -or $s.Tickets.ListView.SortMode -ne 'Priority') { throw 'Settings migration lost values' }
    }
    Test-Case 'A task batch runs every action in order and persists each result' {
        $statuses = 'Success','Skipped','Failed'
        $entries = @(foreach ($status in $statuses) {
            $path = Join-Path $fixture "$status.ps1"

            Set-Content -LiteralPath $path -Value ("param(" + '$Window' + ") [pscustomobject]@{Status='$status';Reason='fixture'}")
            Register-QOTActionDefinition -ActionId "Test.$status" -ScriptPath $path -Label $status | Out-Null
            [pscustomobject]@{ActionId="Test.$status"}
        })
        $window = New-Object Windows.Window
        $complete = @{ Called = $false }
        $callback = { $complete.Called = $true }.GetNewClosure()
        $null = & $ui { param($w,$e,$cb) Start-QOTSelectedTasksAsync -Window $w -SelectedEntries $e -OnCompleted $cb } $window $entries $callback
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while (!$complete.Called -and $clock.Elapsed.TotalSeconds -lt 8) {
            $frame = New-Object Windows.Threading.DispatcherFrame
            $null = $window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle, [action]{ $frame.Continue = $false })
            [Windows.Threading.Dispatcher]::PushFrame($frame)
            Start-Sleep -Milliseconds 20
        }
        $settings = Get-QOSettings
        $summary = $settings.UiState.LastTaskRunSummary
        if (!$complete.Called -or $summary.Worked -ne 1 -or $summary.Skipped -ne 1 -or $summary.Failed -ne 1) {
            $state = & $ui { $script:QOT_TaskRunnerState }
            throw "Callback=$($complete.Called), index=$($state.CurrentIndex), timer=$($state.PollTimer.IsEnabled), resultReady=$($state.WorkerAsyncResult.IsCompleted), summary=$($summary | ConvertTo-Json -Compress)"
        }
        if (($settings.UiState.LastTaskRunEntries.Task -join ',') -ne 'Failed,Skipped,Success') { throw 'Task history incomplete or out of order' }
        if (& $ui { $null -ne $script:QOT_TaskRunnerState }) { throw 'Worker state still marked active' }
    }
    Test-Case 'Play remains responsive after a deadline and waits for the running action before advancing' {
        $slow = Join-Path $fixture 'slow.ps1'
        $next = Join-Path $fixture 'next.ps1'
        Set-Content -LiteralPath $slow -Value @'
param($Window)
$path = Join-Path $PSScriptRoot 'sequence.txt'
[IO.File]::AppendAllText($path, "started`n")
[Threading.Thread]::Sleep(1800)
[IO.File]::AppendAllText($path, "finished`n")
'@
        Set-Content -LiteralPath $next -Value @'
param($Window)
[IO.File]::AppendAllText((Join-Path $PSScriptRoot 'sequence.txt'), "next`n")
'@
        Register-QOTActionDefinition -ActionId Test.Timeout -ScriptPath $slow -Label Slow | Out-Null
        Register-QOTActionDefinition -ActionId Test.Next -ScriptPath $next -Label Next | Out-Null
        $entries = @('Test.Timeout','Test.Next') | ForEach-Object { [pscustomobject]@{ActionId=$_} }
        $window = [Windows.Window]::new()
        $progress = @{ Completed=0; Responsive=$false }
        $timerCount = & $ui { $script:ActiveTimers.Count }
        $callback = { $progress.Completed++ }.GetNewClosure()
        $null = & $ui {
            param($window,$entries,$callback)
            Start-QOTSelectedTasksAsync -Window $window -SelectedEntries $entries -OnCompleted $callback
            $script:QOT_TaskRunnerState.TaskTimeoutSeconds = 1
        } $window $entries $callback
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $sequence = Join-Path $fixture 'sequence.txt'
        while (!$progress.Completed -and $clock.Elapsed.TotalSeconds -lt 8) {
            $frame = [Windows.Threading.DispatcherFrame]::new()
            $null = $window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle, [action]{ $frame.Continue = $false })
            [Windows.Threading.Dispatcher]::PushFrame($frame)
            if ($clock.ElapsedMilliseconds -ge 1300 -and (Test-Path $sequence) -and
                ([IO.File]::ReadAllText($sequence)).Trim() -eq 'started') { $progress.Responsive = $true }
            Start-Sleep -Milliseconds 20
        }
        if (!$progress.Responsive) { throw 'Dispatcher blocked during the overdue action' }
        if ($progress.Completed -ne 1 -or ((Get-Content $sequence) -join ',') -ne 'started,finished,next') { throw 'A task overlapped, stopped prematurely, or replayed' }
        $history = (Get-QOSettings).UiState.LastTaskRunSummary
        if ($history.Worked -ne 1 -or $history.Failed -ne 1) { throw 'Deadline and completion outcomes were not recorded separately' }
        if ((& $ui { $script:ActiveTimers.Count }) -ne $timerCount) { throw 'Completed Play timer still retained' }
    }
    Test-Case 'Sidebar drop moves the source and retains its neighbours' {
        $panel = New-Object Windows.Controls.StackPanel
        foreach ($key in 'BtnRailCleaning','BtnRailApps','BtnRailAdvanced') {
            $button = New-Object Windows.Controls.Button
            $button.Name = $key
            $null = $panel.Children.Add($button)
        }
        $order = & $ui { param($p) Get-QOTRailIconCurrentOrder -Host $p } $panel
        if (($order -join ',') -ne 'BtnRailCleaning,BtnRailApps,BtnRailAdvanced') { throw "Order: $order" }
        $moved = & $ui { param($p,$o) Apply-QOTRailIconOrder -Host $p -Order (Move-QOTRailIconOrder -Order $o -SourceName 'BtnRailAdvanced' -TargetName 'BtnRailApps' -Placement Before) } $panel $order
        if (($moved -join ',') -ne 'BtnRailCleaning,BtnRailAdvanced,BtnRailApps') { throw "Reordered: $moved" }
    }
} finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key]) }
    if ((Split-Path -Parent $fixture) -eq $tempRoot.TrimEnd('\') -and (Split-Path -Leaf $fixture) -like 'QOT-desktop-test-*') {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
if ($failures.Count) { throw "$($failures.Count) desktop regression(s) failed." }
