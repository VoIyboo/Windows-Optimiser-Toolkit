# Exercise the WPF timers with the shipped worker and a disposable mail transport.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$repo = Split-Path $PSScriptRoot -Parent
$tempRoot = [IO.Path]::GetTempPath().TrimEnd('\')
$dir = Join-Path $tempRoot ('QotSync-' + [guid]::NewGuid().ToString('N'))
$old = @{}
foreach ($name in 'TEMP','ProgramData','QOT_SYNC_TEST_RESULT') { $old[$name] = [Environment]::GetEnvironmentVariable($name) }

function Assert([bool]$Condition,[string]$Message) {
    if (!$Condition) { throw $Message }
    Write-Host "PASS $Message"
}
function Wait-For([scriptblock]$Ready,[string]$Description) {
    $deadline = [datetime]::UtcNow.AddSeconds(5)
    do {
        [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
        if (& $Ready) { return }
        Start-Sleep -Milliseconds 20
    } while ([datetime]::UtcNow -lt $deadline)
    Get-Content (Join-Path $dir 'QuinnOptimiserToolkit\Logs\TicketsUI.log') -Tail 15 | Write-Host
    throw "Timed out waiting for $Description. Header: '$($status.Text)'. Visible rows: $($grid.Items.Count)"
}
try {
    $tickets = Join-Path $dir 'src\Tickets'
    $core = Join-Path $dir 'src\Core'
    $null = New-Item -Type Directory -Path $tickets,$core
    $env:TEMP = $dir
    $env:ProgramData = $dir
    Copy-Item -LiteralPath "$repo\src\Tickets\Tickets.UI.psm1","$repo\src\Tickets\Tickets.Email.SyncRunner.ps1" -Destination $tickets
    Set-Content -LiteralPath "$core\QOTImportHelper.ps1" -Value 'function Import-QOTOptionalModule { }'
    Set-Content -LiteralPath "$core\Tickets.psm1" -Value @'
function Get-QOTicketsStorePath { Join-Path $PSScriptRoot 'inbox.json' }
function Get-QOTickets {
    $path = Get-QOTicketsStorePath
    if (Test-Path -LiteralPath $path) { return [IO.File]::ReadAllText($path) | ConvertFrom-Json }
    [pscustomobject]@{Tickets=@()}
}
function Get-QOTMonitoredMailboxAddresses { 'fixture@example.invalid' }
function Sync-QOTicketsFromEmail {
    param($MaxPerMailbox,[switch]$AllowStartOutlook)
    if ($env:QOT_SYNC_TEST_RESULT -eq 'wait') { Start-Sleep -Seconds 20 }
    if ($env:QOT_SYNC_TEST_RESULT -eq 'fail') { throw 'fixture inbox unavailable' }
    $rows = @()
    if ($env:QOT_SYNC_TEST_RESULT -eq 'partial') {
        $rows = @([pscustomobject]@{Id='partial'; Title='Imported before interruption'; Status='Open'; EmailEntryId='partial'})
        @{Tickets=$rows} | ConvertTo-Json | Set-Content -LiteralPath (Get-QOTicketsStorePath)
        return [pscustomobject]@{Success=$false; Added=1; Updated=0; AddedTickets=$rows; Note='Interrupted read'}
    }
    if ($env:QOT_SYNC_TEST_RESULT -eq 'rows') {
        $rows = @([pscustomobject]@{Id='row1'; Title='Fixture message'; Status='Open'; EmailEntryId='entry1'})
        @{Tickets=$rows} | ConvertTo-Json | Set-Content -LiteralPath (Get-QOTicketsStorePath)
    }
    if ($env:QOT_SYNC_TEST_RESULT -eq 'mixed') {
        $prior = (Get-QOTickets).Tickets[0]
        $prior.Title = 'Updated original'
        $rows = @([pscustomobject]@{Id='row2'; Title='Second message'; Status='Open'; EmailEntryId='entry2'})
        @{Tickets=@($prior)+$rows} | ConvertTo-Json | Set-Content -LiteralPath (Get-QOTicketsStorePath)
        return [pscustomobject]@{Success=$true; Added=1; Updated=1; AddedTickets=$rows; Note='fixture'}
    }
    [pscustomobject]@{Success=$true; Added=$rows.Count; Updated=0; AddedTickets=$rows; Note='fixture'}
}
'@
    $ui = Import-Module "$tickets\Tickets.UI.psm1" -PassThru -Force -DisableNameChecking
    & $ui {
        function script:Test-QOTProcessElevated { $false }
        function script:Get-Process($Name) { if ($Name -eq 'OUTLOOK') { [pscustomobject]@{SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId} } }
    }
    $grid = [Windows.Controls.DataGrid]::new()
    $grid.CanUserAddRows = $false
    $status = [Windows.Controls.TextBlock]::new()
    $argsForSync = @{Grid=$grid; StatusText=$status; SyncCmd=(Get-Command Sync-QOTicketsFromEmail); GetTicketsCmd=(Get-Command Get-QOTickets)}
    $ready = { & $ui { !$script:TicketsEmailSyncInProgress } }
    $env:QOT_SYNC_TEST_RESULT = 'rows'
    & $ui { param($options); Register-QOTicketsSyncStatusClick @options } $argsForSync
    function Click-Header {
        $click = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left)
        $click.RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent
        $status.RaiseEvent($click)
    }
    Click-Header
    Click-Header
    Wait-For $ready 'a completed child process to clear the running state'
    Wait-For { $grid.Items.Count -eq 1 -and $status.Text -like 'Last successful email sync:*' } 'new mail to reach the grid and status'
    Assert ($grid.Items[0].Id -eq 'row1') 'A completed mail sync displays the new ticket'
    Assert ((& $ui { $script:TicketsSyncActiveRunId -eq 0 -and !$script:TicketsSyncCompletionTimer -and !$script:TicketsIncrementalMergeTimer })) 'Completion releases the sync and merge timers'
    Assert ((& $ui { $script:TicketsSyncRunCounter }) -eq 1) 'Header clicks start one worker and ignore repeated clicks while it is running'

    $env:QOT_SYNC_TEST_RESULT = 'fail'
    Invoke-QOTicketsEmailSyncAndRefresh @argsForSync -Force
    Wait-For $ready 'a failed sync to release its worker'
    Assert ((& $ui { $script:TicketsSyncFailureCount -eq 1 -and $script:TicketsSyncLastFailureNote -like '*fixture inbox unavailable*' })) 'An unavailable inbox schedules a retry'

    $env:QOT_SYNC_TEST_RESULT = 'wait'
    Invoke-QOTicketsEmailSyncAndRefresh @argsForSync -Force
    & $ui { $script:TicketsSyncActiveTimeoutSeconds = 0 }
    Wait-For $ready 'a timed-out sync to release its worker'
    Assert ((& $ui { $script:TicketsSyncLastFailureNote -like '*timed out*' })) 'A timeout leaves the header ready for another request'

    $env:QOT_SYNC_TEST_RESULT = 'empty'
    & $ui { param($options); Start-QOTicketsAutoSyncWorker @options; $script:TicketsSyncNextAttemptUtc = [datetime]::UtcNow.AddSeconds(-1) } $argsForSync
    Wait-For { (& $ui { $script:TicketsSyncRunCounter -eq 4 -and !$script:TicketsEmailSyncInProgress }) } 'the scheduled retry to complete'
    Assert ((& $ui { $script:TicketsSyncFailureCount -eq 0 -and $script:TicketsSyncNextAttemptUtc -gt [datetime]::UtcNow.AddMinutes(4) })) 'Automatic recovery returns to the five-minute polling interval'
    $env:QOT_SYNC_TEST_RESULT = 'mixed'
    Click-Header
    Wait-For $ready 'a sync containing new mail and a changed ticket'
    Assert ($grid.Items.Count -eq 2 -and ($grid.Items | Where-Object Id -eq 'row1').Title -eq 'Updated original') 'One sync displays both updated and newly imported tickets'

    $path = Join-Path $dir 'store.json'
    $events = [Collections.Generic.List[string]]::new()
    $getPath = { $path }.GetNewClosure()
    $refresh = { param($Grid,$GetTicketsCmd,$View); $events.Add([IO.File]::ReadAllText($path)) }.GetNewClosure()
    & $ui {
        param($g,$get,$refresh)
        Start-QOTicketsStoreAutoRefresh -Grid $g -GetTicketsCmd (Get-Command Get-QOTickets) -GetStorePathCmd $get -RefreshCmd $refresh
        $script:TicketsFileRefreshTimer.Interval = [timespan]::FromMilliseconds(40)
    } $grid $getPath $refresh
    [IO.File]::WriteAllText($path,'created')
    Wait-For { $events.Contains('created') } 'the first external save to refresh the grid'
    [IO.File]::WriteAllText($path,'restored')
    [IO.File]::SetLastWriteTimeUtc($path,[datetime]::UtcNow.AddDays(-1))
    Wait-For { $events.Contains('restored') } 'a restored copy with an older timestamp to refresh the grid'
    Assert ($events.Count -eq 2) 'Store polling refreshes once for each changed file'

    $env:QOT_SYNC_TEST_RESULT = 'wait'
    Click-Header
    & $ui {
        # Simulate a missed completion timer and a past watchdog deadline.
        $script:TicketsSyncCompletionTimer.Stop()
        $script:TicketsSyncLastStartUtc = [datetime]::UtcNow.AddMinutes(-5)
    }
    Wait-For $ready 'the watchdog to release a stale child worker'
    Assert ((& $ui { $script:TicketsSyncFailureCount -eq 1 })) 'The watchdog recovers a stalled process even if the completion timer stopped'

    Click-Header
    & $ui { Close-QOTicketsUI }
    Click-Header
    Assert ((& $ui { !$script:TicketsEmailSyncInProgress -and !$script:TicketsSyncProcess -and !$script:TicketsSyncActiveRunId -and $script:TicketsSyncRunCounter -eq 7 })) 'Closing Tickets releases its active worker and disconnects the manual sync click'
    $env:QOT_SYNC_TEST_RESULT = 'empty'
    & $ui { param($options); Register-QOTicketsSyncStatusClick @options } $argsForSync
    Click-Header
    Wait-For $ready 'the reopened header to sync'
    Assert ((& $ui { $script:TicketsSyncRunCounter -eq 8 -and $script:TicketsSyncFailureCount -eq 0 })) 'Reopening Tickets accepts a new manual sync'
    $env:QOT_SYNC_TEST_RESULT = 'partial'
    Click-Header
    Wait-For $ready 'a partially imported mailbox to schedule a retry'
    Assert ($grid.Items.Count -eq 1 -and $grid.Items[0].Id -eq 'partial' -and $status.Text -like '*retry*') 'Fetched tickets appear while the interrupted mailbox waits to retry'
} finally {
    if ($ui) { & $ui { Close-QOTicketsUI } }
    foreach ($name in $old.Keys) { [Environment]::SetEnvironmentVariable($name,$old[$name]) }
    if ([IO.Directory]::Exists($dir)) {
        $target = (Resolve-Path -LiteralPath $dir).Path
        if ((Split-Path $target -Parent) -eq $tempRoot -and (Split-Path $target -Leaf) -match '^QotSync-[0-9a-f]{32}$') {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
}
