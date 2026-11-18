# Run in a fresh Windows PowerShell process. All state and the mail transport are disposable.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('QOT ticket tests ' + [guid]::NewGuid().ToString('N'))
$repo = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()
function Check([string]$Name, [scriptblock]$Test) {
    try { & $Test; Write-Host "PASS $Name" }
    catch { $failures.Add("$Name - $($_.Exception.Message)"); Write-Host "FAIL $Name - $($_.Exception.Message)" }
}
function Assert([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }

$originalEnvironment = @{}
foreach ($name in 'ProgramData','LOCALAPPDATA','QOT_SETTINGS_PATH','QOT_TEST_MAIL') {
    $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $env:ProgramData = Join-Path $root 'logs'
    $env:LOCALAPPDATA = Join-Path $root 'appdata'
    $env:QOT_SETTINGS_PATH = Join-Path $root 'settings.json'
    $env:QOT_TEST_MAIL = Join-Path $root 'simulated-mail.txt'
    $core = Join-Path $root 'src\Core'
    $tickets = Join-Path $root 'src\Tickets'
    $null = New-Item -Type Directory -Path $tickets,$core,(Join-Path $core 'Logging') -Force
    foreach ($file in 'Tickets.psm1','Settings.psm1','QOTImportHelper.ps1','TicketEmailAddress.ps1','Logging\Logging.psm1') {
        Copy-Item -LiteralPath (Join-Path $repo "src\Core\$file") -Destination (Join-Path $core $file)
    }
    Copy-Item -Path (Join-Path $repo 'src\Tickets\*.ps1') -Destination $tickets
    Copy-Item -LiteralPath (Join-Path $repo 'src\Tickets\Tickets.UI.psm1') -Destination $tickets
    # Redirect the shared settings module's known-folder cache, including in child processes.
    Add-Content -LiteralPath (Join-Path $core 'Settings.psm1') -Value '$script:QOAppDataRoot = $env:LOCALAPPDATA'
    $corePath = Join-Path $core 'Tickets.psm1'
    @'
$script:realUpdateTicket = ${function:Update-QOTicket}
function Update-QOTicket {
    param($Ticket)
    if (Test-Path ($env:QOT_TEST_MAIL + ".fail-history")) { throw "Simulated history write failure." }
    & $script:realUpdateTicket -Ticket $Ticket
}
'@ | Add-Content -LiteralPath $corePath
    @'
function Sync-QOTicketsFromOutlook { throw "No live mailbox is available in this test." }
function Send-QOTicketOutlookReply { throw "Unexpected reply transport." }
function Send-QOTicketOutlookEmail {
    param($To,$Subject,$Body,$FromMailbox,$TicketId)
    if ($Subject -eq 'Unconfirmed Outlook submission') {
        Add-Content -LiteralPath ($env:QOT_TEST_MAIL + '.unconfirmed') -Value $To
        return [pscustomobject]@{ Success=$false; SubmissionUnconfirmed=$true; Note='Outlook busy during submission. Check Outbox and Sent Items before resending.' }
    }
    Add-Content -LiteralPath $env:QOT_TEST_MAIL -Value $To
    return [pscustomobject]@{ Success = $true; Note = "Simulated send"; SentEntryId = "fixture-message" }
}
'@ | Set-Content -LiteralPath (Join-Path $tickets 'Tickets.Email.Outlook.psm1') -Encoding UTF8
    $toolkit = Import-Module (Join-Path $core 'Tickets.psm1') -PassThru -Force -DisableNameChecking
    $store = Join-Path $root 'live\Tickets.json'
    $backup = Join-Path $root 'configured backups'
    $null = Set-QOTicketStorageSettings -StorePath $store -BackupPath $backup
    $paths = Reset-QOTicketStorageCache

    Check 'ticket initialisation preserves settings during a read sharing violation' {
        $original = [IO.File]::ReadAllText($env:QOT_SETTINGS_PATH)
        $held = [IO.File]::Open($env:QOT_SETTINGS_PATH, 'Open', 'ReadWrite', [IO.FileShare]::Delete)
        $failed = $false
        try { try { $null = Reset-QOTicketStorageCache } catch { $failed = $true } }
        finally { $held.Dispose() }
        $current = [IO.File]::ReadAllText($env:QOT_SETTINGS_PATH)
        if ($current -cne $original) { [IO.File]::WriteAllText($env:QOT_SETTINGS_PATH, $original) }
        $null = Reset-QOTicketStorageCache
        Assert ($failed -and $current -ceq $original) 'A failed settings read selected or persisted a replacement store'
    }
    Check 'configured backup folder' {
        Assert ($paths.BackupPath -eq $backup) "Expected configured folder, got $($paths.BackupPath)"
    }
    $ticket = Add-QOTicket -Ticket (New-QOTicket -Title 'Printer' -SenderEmail 'customer@example.invalid' -SourceMailbox 'help@example.invalid')
    Check 'ticket updates, notes, filtering, delete and restore' {
        Set-QOTicketsStatus -Id $ticket.Id -Status Pending
        Set-QOTicketsPriority -Id $ticket.Id -Priority High
        Set-QOTicketsAssignedTo -Id $ticket.Id -AssignedTo Pat
        $null = Add-QOTicketNote -Id $ticket.Id -Note 'Checked cable' -NoteId 'note1'
        $pending = @(Get-QOTicketsFiltered -Status Pending)
        Assert ($pending.Count -eq 1 -and $pending[0].AssignedTo -eq 'Pat' -and $pending[0].Priority -eq 'High') 'Updated ticket missing from filter'
        Assert (@($pending[0].Notes).Count -eq 1) 'Missing note'
        $null = Remove-QOTicketNote -Id $ticket.Id -NoteId 'note1'
        Remove-QOTicket -Id $ticket.Id
        Assert (@(Get-QOTicketsByBucket -Bucket Deleted).Count -eq 1) 'Soft delete failed'
        Restore-QOTickets -Id $ticket.Id
        Assert (@(Get-QOTicketsByFolder -Folder Active).Count -eq 1) 'Restore failed'
        Assert ((Get-QOTicketAnalyticsSnapshot).PendingTickets -eq 1) 'Incorrect pending count'
        $csv = Join-Path $root 'export.csv'
        $null = Export-QOTicketsToExcelSpreadsheet -Path $csv
        Assert ((Import-Csv -LiteralPath $csv).Id -eq $ticket.Id) 'Ticket export failed'
    }
    Check 'background note worker saves, replays and deletes the same note' {
        $payload = Join-Path $root 'note-payload.json'
        $resultPath = Join-Path $root 'note-result.json'
        $noteText = 'Printer location ' + [char]0x03b2
        $noteJson = @{ TicketId = $ticket.Id; NoteId = 'background-note'; Author = 'Pat'; Note = $noteText } | ConvertTo-Json
        [IO.File]::WriteAllText($payload, $noteJson, [Text.UTF8Encoding]::new($false))
        $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $runner = Join-Path $tickets 'Tickets.BackgroundActionRunner.ps1'
        foreach ($operation in 'save-note','save-note','delete-note') {
            $null = & $engine -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -ToolkitRoot $root -Action $operation -PayloadPath $payload -ResultPath $resultPath
            Assert ($LASTEXITCODE -eq 0) "The $operation worker failed"
            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            Assert ($result.Success -and $result.Action -eq $operation -and $result.TicketId -eq $ticket.Id) "Unexpected $operation result"
            $stored = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id
            $notes = @($stored.Notes | Where-Object NoteId -eq 'background-note')
            if ($operation -eq 'save-note') {
                Assert ($notes.Count -eq 1 -and $notes[0].Body -ceq $noteText) 'Saving or replaying the note changed the content or count'
            } else {
                Assert ($notes.Count -eq 0) 'Deleted background note remained in the ticket'
            }
        }
    }
    Check 'workers hold queued actions when settings switch to a copy of the ticket store' {
        $secondStore = Join-Path $root 'other-team.json'
        Copy-Item -LiteralPath $store -Destination $secondStore
        $payload = Join-Path $root 'switch-payload.json'
        $resultPath = Join-Path $root 'switch-result.json'
        $replyPayload = New-QOTTicketReplyWorkerPayload -Ticket $ticket -Subject 'Original team' -Body 'Private reply'
        try {
            $null = Set-QOTicketStorageSettings -StorePath $secondStore -BackupPath $backup
            $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $noteJson = @{StorePath=$store; TicketId=$ticket.Id; NoteId='other-team-note'; Note='Original team only'} | ConvertTo-Json
            [IO.File]::WriteAllText($payload, $noteJson)
            $null = & $engine -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $tickets 'Tickets.BackgroundActionRunner.ps1') -ToolkitRoot $root -Action save-note -PayloadPath $payload -ResultPath $resultPath
            $noteResult = [IO.File]::ReadAllText($resultPath) | ConvertFrom-Json
            [IO.File]::WriteAllText($payload, ($replyPayload | ConvertTo-Json))
            $null = & $engine -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $tickets 'Tickets.Email.ReplyRunner.ps1') -ToolkitRoot $root -PayloadPath $payload -ResultPath $resultPath -TransportOnly
            $mailResult = [IO.File]::ReadAllText($resultPath) | ConvertFrom-Json
            $null = & $engine -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $tickets 'Tickets.Email.ReplyQueueRunner.ps1') -ToolkitRoot $root -StorePath $store
            Assert ($LASTEXITCODE -eq 1) 'The queue worker accepted a different store at startup'
            $copy = [IO.File]::ReadAllText($secondStore) | ConvertFrom-Json
            Assert (!$noteResult.Success -and $noteResult.Note -match 'store' -and !($copy.Tickets.Notes.NoteId -contains 'other-team-note')) 'A private note reached a different store'
            Assert ($replyPayload.StorePath -eq $store -and !$mailResult.Success -and $mailResult.Note -match 'store' -and !(Test-Path $env:QOT_TEST_MAIL)) 'The transport followed the changed store'
        } finally {
            $null = Set-QOTicketStorageSettings -StorePath $store -BackupPath $backup
            $null = Reset-QOTicketStorageCache
            if (Test-Path $env:QOT_TEST_MAIL) { Remove-Item -LiteralPath $env:QOT_TEST_MAIL }
        }
    }
    Check 'email import deduplicates and retains full Unicode body' {
        $message = [pscustomobject]@{ Subject='New request'; MessageId='message1'; Body=('sample '+[char]0x03b2)*300; From='client@example.invalid' }
        $first = Add-QOTicketFromEmail -Email $message
        $again = Add-QOTicketFromEmail -Email $message
        Assert ($first.Id -eq $again.Id) 'Duplicate import'
        Assert ([IO.File]::ReadAllText($again.EmailBodyPath) -ceq $message.Body) 'Lost imported body'
    }
    Check 'background queue rejects a customer change after the user submits a reply' {
        $composed = Add-QOTicket (New-QOTicket -Title 'Route handoff' -EmailTo 'first@example.invalid' -SourceMailbox 'help@example.invalid')
        $route = Get-QOTTicketPendingReplyMetadataFromTicket $composed
        Assert ($route.To -eq 'first@example.invalid') 'The compose snapshot missed the original recipient'
        $current = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $composed.Id
        $current.EmailTo = 'other@example.invalid'
        $null = Update-QOTicket -Ticket $current
        $payload = Join-Path $root 'queue-payload.json'
        $resultPath = Join-Path $root 'queue-result.json'
        $json = @{ TicketId=$composed.Id; Subject='Original customer'; Body='Private reply'; DraftId='route-test'; ExpectedRoute=$route } | ConvertTo-Json
        [IO.File]::WriteAllText($payload, $json)
        $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $null = & $engine -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $tickets 'Tickets.BackgroundActionRunner.ps1') -ToolkitRoot $root -Action queue-reply -PayloadPath $payload -ResultPath $resultPath
        $result = [IO.File]::ReadAllText($resultPath) | ConvertFrom-Json
        Assert (!$result.Success -and $result.Note -match 'changed|match|conflict') 'The worker accepted a different customer or failed for the wrong reason'
        Assert ($null -eq (Get-QOTTicketPendingReply -TicketId $composed.Id -DraftId 'route-test')) 'The mismatched reply entered the queue'
    }
    Check 'background reply sends exactly once through a clean install' {
        $entry = Add-QOTTicketPendingReply -TicketId $ticket.Id -Subject 'Re: Printer' -Body 'Try again' -DraftId 'draft1'
        Assert ($entry.DraftId -eq 'draft1') 'Queue entry missing'
        $runner = Join-Path $tickets 'Tickets.Email.ReplyQueueRunner.ps1'
        $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        & $engine -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $runner -ToolkitRoot $root -MaxFailureRetries 1
        Assert ($LASTEXITCODE -eq 0) "Queue runner exited $LASTEXITCODE"
        $delivered = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id
        Assert (@($delivered.PendingReplies).Count -eq 0) 'Reply remained queued'
        Assert (@($delivered.Replies).Count -eq 1 -and $delivered.Replies[0].SentEntryId -eq 'fixture-message') 'Sent reply missing or duplicated'
        Assert (@(Get-Content -LiteralPath $env:QOT_TEST_MAIL).Count -eq 1) 'Simulated transport count incorrect'
    }
    Check 'interrupted send requires review before another delivery attempt' {
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -Subject 'Interrupted' -Body 'Check first' -DraftId 'interrupted'
        $null = Set-QOTTicketPendingReplyState -TicketId $ticket.Id -DraftId interrupted -SendState Sending
        $next = Get-QOTNextPendingReply -StaleSendingSeconds 0
        Assert ($null -eq $next) 'An interrupted send was selected again for delivery'
        $saved = Get-QOTTicketPendingReply -TicketId $ticket.Id -DraftId interrupted
        Assert ($saved.SendState -eq 'Failed') 'Uncertain reply was not retained for review'
        $cancel = Cancel-QOTTicketPendingReply -TicketId $ticket.Id -DraftId interrupted
        Assert $cancel.Cancelled 'Could not dismiss the interrupted send'
    }
    Check 'confirmed delivery can repair history after a write failure without a resend' {
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -Subject 'Receipt' -Body 'Delivered' -DraftId 'receipt'
        $failureFile = $env:QOT_TEST_MAIL + '.fail-history'
        [IO.File]::WriteAllText($failureFile, 'fail history completion')
        $runner = Join-Path $tickets 'Tickets.Email.ReplyQueueRunner.ps1'
        & powershell -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $runner -ToolkitRoot $root -MaxFailureRetries 1
        Assert ($LASTEXITCODE -eq 0) 'Queued send failed'
        $pending = ((Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id).PendingReplies
        Assert ($pending[0].SendState -eq 'Sent' -and $pending[0].DeliveryReceipt.SentEntryId -eq 'fixture-message') 'Confirmed delivery receipt missing'
        $repeat = Add-QOTTicketPendingReply -TicketId $ticket.Id -DraftId receipt -Subject 'Receipt' -Body 'Delivered'
        Assert ($repeat.SendState -eq 'Sent') 'Duplicate enqueue reset a delivered draft'
        Assert (-not (Cancel-QOTTicketPendingReply -TicketId $ticket.Id -DraftId receipt).Cancelled) 'Cancellation erased a receipt'
        [IO.File]::Delete($failureFile)
        $null = Initialize-QOTicketsReplyQueueService -Reason 'test-startup'
        $null = Initialize-QOTicketsReplyQueueService -Reason 'test-startup'
        $updated = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id
        $history = @($updated.Replies | Where-Object ReplyId -eq 'receipt')
        Assert (@($updated.PendingReplies).Count -eq 0 -and $history.Count -eq 1 -and $history[0].SentEntryId -eq 'fixture-message') 'Sent reply history was not repaired'
        Assert (@(Get-Content -LiteralPath $env:QOT_TEST_MAIL).Count -eq 2) 'Delivery repeated during repair'
    }
    Check 'recipient changes hold the queued reply for review' {
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -Subject 'Routing' -Body 'Customer information' -DraftId routing
        $changed = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id
        $changed.SenderEmail = 'another@example.invalid'
        $null = Update-QOTicket -Ticket $changed
        $runner = Join-Path $tickets 'Tickets.Email.ReplyQueueRunner.ps1'
        & powershell -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $runner -ToolkitRoot $root -MaxFailureRetries 1
        Assert ((Get-QOTTicketPendingReply -TicketId $ticket.Id -DraftId routing).SendState -eq 'Failed') 'Modified target was used'
        Assert (@(Get-Content -LiteralPath $env:QOT_TEST_MAIL).Count -eq 2) 'Sent to a changed recipient'
        $null = Cancel-QOTTicketPendingReply -TicketId $ticket.Id -DraftId routing
    }
    Check 'an unconfirmed Outlook submission is held for review across worker restarts' {
        $address = 'uncertain@example.invalid'
        $unsure = Add-QOTicket (New-QOTicket -Title 'Delivery acknowledgement' -EmailTo $address)
        $null = Add-QOTTicketPendingReply -TicketId $unsure.Id -DraftId unsure -Subject 'Unconfirmed Outlook submission' -Body 'Fixture only'
        $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $worker = Join-Path $tickets 'Tickets.Email.ReplyQueueRunner.ps1'
        foreach ($run in 1,2) {
            & $engine -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $worker -ToolkitRoot $root -MaxFailureRetries 2
            Assert ($LASTEXITCODE -eq 0) "Queue worker run $run failed"
            $held = Get-QOTTicketPendingReply -TicketId $unsure.Id -DraftId unsure
            Assert ($held.SendState -eq 'Failed' -and !$held.NextAttemptAt -and $held.RetryCount -eq 1) 'An uncertain submission remained eligible for automatic retry'
            Assert ($held.FailureNote -match 'Check Outbox and Sent Items before resending') 'The operator did not receive the manual review instruction'
            $submissions = @(Get-Content -LiteralPath ($env:QOT_TEST_MAIL + '.unconfirmed'))
            Assert ($submissions.Count -eq 1 -and $submissions[0] -ceq $address) 'The worker submitted the message more than once or to the wrong mailbox'
        }
    }
    Check 'unconfigured automatic sync stays idle and manual sync remains available' {
        Add-Type -AssemblyName PresentationFramework
        $ui = Import-Module (Join-Path $tickets 'Tickets.UI.psm1') -Force -PassThru -DisableNameChecking
        & $ui {
            function Test-QOTProcessElevated { return $false }
            function Start-Process { throw 'Stopped at the test process boundary.' }
            $grid = New-Object System.Windows.Controls.DataGrid
            $arguments = @{Grid=$grid; GetTicketsCmd=(Get-Command Get-QOTickets); SyncCmd=(Get-Command Sync-QOTicketsFromEmail)}
            Invoke-QOTicketsEmailSyncAndRefresh @arguments
            Assert ($script:TicketsSyncRunCounter -eq 0) 'Automatic sync attempted an Outlook worker without a mailbox'
            $null = Invoke-QOTicketsManualSyncRequest @arguments
            Assert ($script:TicketsSyncRunCounter -eq 1) 'Manual sync request never reached worker launch'
        }
    }
    Check 'configured background sync waits for classic Outlook in the current session' {
        $ui = Import-Module (Join-Path $tickets 'Tickets.UI.psm1') -Force -PassThru -DisableNameChecking
        & $ui {
            function Get-QOTMonitoredMailboxAddresses { 'support@example.invalid' }
            function Get-Process { param($Name); if ($Name -eq 'OUTLOOK') { $outlookInstances } }
            function Test-QOTProcessElevated { return $elevated }
            function Start-QOTLimitedScheduledProcess { throw 'Stopped at the test scheduler boundary.' }
            function Start-Process { throw 'Stopped at the test process boundary.' }
            $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
            $grid = [System.Windows.Controls.DataGrid]::new()
            $status = [System.Windows.Controls.TextBlock]::new()
            $arguments = @{Grid=$grid; StatusText=$status; GetTicketsCmd=(Get-Command Get-QOTickets); SyncCmd=(Get-Command Sync-QOTicketsFromEmail)}
            $elevated = $false
            $outlookInstances = @()
            Invoke-QOTicketsEmailSyncAndRefresh @arguments
            Assert ($script:TicketsSyncRunCounter -eq 0) 'A sync worker started while Outlook was closed'
            $outlookInstances = @([pscustomobject]@{SessionId=$session + 1})
            Invoke-QOTicketsEmailSyncAndRefresh @arguments
            Assert ($script:TicketsSyncRunCounter -eq 0) 'Outlook in a different session triggered a worker'
            $outlookInstances = @([pscustomobject]@{SessionId=$session})
            $elevated = $true
            Invoke-QOTicketsEmailSyncAndRefresh @arguments
            Assert ($script:TicketsSyncRunCounter -eq 0 -and $script:TicketsLastSyncStatusMessage -match 'normally') 'Elevated unattended sync launched a worker or missed the explanation'
            $elevated = $false
            Invoke-QOTicketsEmailSyncAndRefresh @arguments
            Assert ($script:TicketsSyncRunCounter -eq 1) 'Automatic sync did not resume when Outlook opened'
            $elevated = $true
            Invoke-QOTicketsEmailSyncAndRefresh @arguments -Force
            Assert ($script:TicketsSyncRunCounter -eq 2) 'An explicit sync was blocked when running as administrator'
        }
    }
    Check 'elevated ticket sync schedules the worker directly with the current limited user' {
        $scheduler = New-Object -ComObject Schedule.Service
        $scheduler.Connect()
        $definition = $scheduler.NewTask(0)
        $service = [pscustomobject]@{Definition=$definition}
        $service | Add-Member ScriptMethod Connect {}
        $service | Add-Member ScriptMethod NewTask {param($flags) $this.Definition}
        $service | Add-Member ScriptMethod GetFolder {param($folder) $this}
        $service | Add-Member ScriptMethod RegisterTaskDefinition {param($name,$definition,$flags,$user,$password,$logon,$acl) $this}
        $service | Add-Member ScriptMethod Run {param($arguments)}
        & (Get-Module Tickets.UI) {
            param($fakeService,$fixtureDir)
            function New-Object { param($ComObject); if ($ComObject -eq 'Schedule.Service') { $fakeService } }
            $exe = Join-Path $PSHOME 'powershell.exe'
            $argsText = '-NoProfile -File "C:\fixture with spaces\sync.ps1"'
            $result = Start-QOTLimitedScheduledProcess -FilePath $exe -ArgumentString $argsText -WorkingDirectory $fixtureDir -TaskNamePrefix QOTSync
            try {
                $task = $fakeService.Definition
                $action = $task.Actions.Item(1)
                Assert ($task.Actions.Count -eq 1 -and $action.Path -eq $exe) 'Ticket sync starts an intermediate console'
                Assert ($action.Arguments -ceq $argsText -and $action.WorkingDirectory -eq $fixtureDir) 'Worker arguments or working directory changed'
                Assert ($task.Principal.LogonType -eq 3 -and $task.Principal.RunLevel -eq 0 -and $task.Principal.UserId -eq [Security.Principal.WindowsIdentity]::GetCurrent().Name) 'Worker must use the current interactive user at limited privileges'
                Assert ($task.Triggers.Count -eq 1 -and -not $task.Triggers.Item(1).Enabled -and $task.Triggers.Item(1).EndBoundary -and $task.Settings.DeleteExpiredTaskAfter) 'On-demand registration needs expiry without a second launch'
            } finally {
                if ($result.CommandPath) { Remove-Item -LiteralPath $result.CommandPath -Force }
            }
        } $service $root
    }
    Check 'ticket details preserve Unicode sender names from body files' {
        $senderName = 'Ren' + [char]0x00e9
        $bodyPath = Join-Path $root 'sender.txt'
        [IO.File]::WriteAllText($bodyPath, "From: $senderName <o'brien@example.invalid>")
        $details = & (Get-Module Tickets.UI) { param($path) Get-QOTicketSenderFallbackInfo -Ticket ([pscustomobject]@{EmailBodyPath=$path}) } $bodyPath
        Assert ($details.SenderName -ceq $senderName) "Wrong sender name: $($details.SenderName)"
        Assert ($details.SenderEmail -ceq "o'brien@example.invalid") "Wrong sender address: $($details.SenderEmail)"
    }
    Check 'closing delegate releases the module watcher and stops the sync timer' {
        $close = & (Get-Module Tickets.UI) {
            $script:TicketsFileWatcher = [IO.FileSystemWatcher]::new($env:LOCALAPPDATA)
            $script:TicketsSyncTimer = [Windows.Threading.DispatcherTimer]::new()
            $script:TicketsSyncTimer.Start()
            [ComponentModel.CancelEventHandler]${function:Close-QOTicketsUI}
        }
        $close.Invoke($null, [ComponentModel.CancelEventArgs]::new())
        $clean = & (Get-Module Tickets.UI) { $null -eq $script:TicketsFileWatcher -and -not $script:TicketsSyncTimer.IsEnabled }
        Assert $clean 'Ticket resources remained active after closing'
    }
    Check 'Outlook sync keeps different customers and conversations separate' {
        $path = Join-Path $tickets 'Fixture.Outlook.psm1'
        Copy-Item -LiteralPath (Join-Path $repo 'src\Tickets\Tickets.Email.Outlook.psm1') -Destination $path
        $outlook = Import-Module $path -Force -PassThru -DisableNameChecking
        & $outlook {
            function script:Get-QOTOutlookNamespace { param([switch]$AllowStartOutlook) return 'Fake MAPI' }
            function script:Get-QOTEffectiveMonitoredMailboxAddresses { param([switch]$AllowStartOutlook,[switch]$PersistWhenSingle) 'support@example.invalid' }
            $script:mailItems = [pscustomobject]@{ Messages = @(foreach ($messageId in 'alice','bob','alice-followup') {
                $name = $messageId.Split('-')[0]
                $item = [pscustomobject]@{
                    EntryID=$messageId; ConversationID=$name; Subject='Password reset'; ReceivedTime=(Get-Date)
                    SenderName=$name; SenderEmailAddress="$name@example.invalid"; Body="Request from $messageId"
                    MessageClass='IPM.Note'; Categories=''; Importance=1; Parent=[pscustomobject]@{StoreID='fixture'}
                }
                $item | Add-Member -MemberType ScriptMethod -Name Save -Value {}
                $item
            }) }
            $script:mailItems | Add-Member -MemberType ScriptMethod -Name Item -Value {param($n) $this.Messages[$n-1]}
            $script:mailItems | Add-Member -MemberType ScriptProperty -Name Count -Value { $this.Messages.Length }
            $script:mailItems | Add-Member -MemberType ScriptMethod -Name Sort -Value { param($field,$descending) }
            function script:Get-QOTMailboxInboxFolder {param($MAPI,$MailboxAddress) [pscustomobject]@{Items=$script:mailItems}}
            $first = Sync-QOTicketsFromOutlook
            Assert ($first.Added -eq 2) "Distinct messages became $($first.Added) new tickets"
            $second = Sync-QOTicketsFromOutlook
            Assert ($second.Added -eq 0) 'Repeat sync duplicated a message'
        }
    }
    Check 'a lost Outlook session produces a retryable send result without opening or minimizing Outlook' {
        $path = Join-Path $tickets 'Disconnected.Outlook.psm1'
        # The fixture must never attach to an Outlook instance on the test machine.
        $source = [IO.File]::ReadAllText((Join-Path $repo 'src\Tickets\Tickets.Email.Outlook.psm1'))
        $source = $source.Replace('[System.Runtime.InteropServices.Marshal]::GetActiveObject("Outlook.Application")', '$null')
        [IO.File]::WriteAllText($path, $source)
        $outlook = Import-Module $path -PassThru -DisableNameChecking
        & $outlook {
            function Initialize-QOTicketsCoreApi {}
            function Get-QOTOutlookNamespace { [pscustomobject]@{Application=$null} }
            $script:activations = 0
            function New-Object { param($ComObject); if ($ComObject -eq 'Outlook.Application') { $script:activations++; return [pscustomobject]@{} } }
            $result = Send-QOTicketOutlookEmail -To 'test@example.invalid' -Subject 'Fixture' -Body 'Fixture' -FromMailbox 'mail@example.invalid'
            Assert ($script:activations -eq 0) 'Sending attempted to open or minimize an Outlook window after disconnect'
            Assert (-not $result.Success -and $result.Note -match 'Classic Outlook is not open') 'The queue needs a retryable connection failure'
        }
    }
    Check 'ticket details never substitute or append another customer with the same subject' {
        $alice = [pscustomobject]@{ Id='ui-alice'; Subject='Same subject'; EmailBody='Alice body'; EmailConversationId='a'; CreatedAt='2025-01-02 12:00:00' }
        $bob = [pscustomobject]@{ Id='ui-bob'; Subject='Same subject'; EmailBody='Bob-only body'; EmailConversationId='b'; EmailFrom='bob@example.invalid'; CreatedAt='2025-01-02 12:00:00' }
        $null = Add-QOTicket -Ticket $bob
        $resolved = Resolve-QOTTicketDetailsSourceTicket -Ticket $alice
        Assert ($resolved.Id -eq $alice.Id) 'Selected ticket was replaced by an unrelated record'
        $details = Get-QOTicketDetailsBodyText -Ticket $alice -PreferCurrentTicket
        Assert ($details -notmatch 'Bob-only body') 'Timeline included another conversation'
        $keys = & (Get-Module Tickets.UI) {param($a,$b) Get-QOTicketDedupKey -Ticket $a; Get-QOTicketDedupKey -Ticket $b} $alice $bob
        Assert ($keys[0] -ne $keys[1]) 'The grid collapsed different tickets with the same subject'
    }
    Check 'recover an existing legacy backup past a newer damaged backup' {
        $oldBackupDir = Join-Path (Split-Path -Parent $store) 'Tickets.backup.json'
        $null = New-Item -Type Directory -Path $oldBackupDir,$backup -Force
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -Subject 'Once' -Body 'Possibly delivered' -DraftId restored
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -Subject 'In flight' -Body 'Possibly delivered too' -DraftId sending
        $null = Set-QOTTicketPendingReplyState -TicketId $ticket.Id -DraftId sending -SendState Sending
        Copy-Item -LiteralPath $store -Destination (Join-Path $oldBackupDir 'Tickets.json.bak_valid')
        $invalid = Join-Path $backup 'Tickets.json.bak_invalid'
        [IO.File]::WriteAllText($invalid, '{broken')
        [IO.File]::SetLastWriteTimeUtc($invalid, [datetime]::UtcNow.AddMinutes(1))
        [IO.File]::WriteAllText($store, '{broken live store')
        $result = Get-QOTickets -Quiet
        Assert ($result.Tickets.Id -contains $ticket.Id) 'Recovery missed the valid backup'
        $restored = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id
        Assert (@($restored.PendingReplies | Where-Object SendState -eq Failed).Count -eq 2) 'Restored drafts were eligible for automatic delivery'
        $runner = Join-Path $tickets 'Tickets.Email.ReplyQueueRunner.ps1'
        & powershell -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $runner -ToolkitRoot $root -MaxFailureRetries 1
        Assert (@(Get-Content -LiteralPath $env:QOT_TEST_MAIL).Count -eq 2) 'Restored drafts were sent'
    }
    Check 'unrecoverable store is preserved on read and stale save' {
        $badStore = Join-Path $root 'damaged\Tickets.json'
        $null = Set-QOTicketStorageSettings -StorePath $badStore -BackupPath (Join-Path $root 'empty backups')
        $null = Reset-QOTicketStorageCache
        $stale = Get-QOTickets -Quiet
        $badContent = '{incomplete database'
        [IO.File]::WriteAllText($badStore, $badContent)
        $failed = $false
        try { $null = Get-QOTickets -Quiet } catch { $failed = $true }
        Assert ($failed -and [IO.File]::ReadAllText($badStore) -ceq $badContent) 'Read reset the damaged store'
        $failed = $false
        try { Save-QOTickets -Database $stale -Quiet } catch { $failed = $true }
        Assert ($failed -and [IO.File]::ReadAllText($badStore) -ceq $badContent) 'Stale save replaced the damaged store'
    }
    Check 'large legacy store reads preserve queued mail and full ticket history' {
        $largeStore = Join-Path $root 'legacy\Tickets.json'
        $null = Set-QOTicketStorageSettings -StorePath $largeStore -BackupPath (Join-Path $root 'large backups')
        $null = Reset-QOTicketStorageCache
        $long = ('legacy text ' + [char]0x03b2 + '"') * 2500
        $legacy = New-QOTicket -Title 'Archived request'
        $legacy.Replies = @([pscustomobject]@{ReplyId='sent'; Body=$long})
        $legacy.PendingReplies = @([pscustomobject]@{DraftId='waiting'; Subject='Follow up'; Body=$long; SendState='Queued'})
        $writer = [IO.StreamWriter]::new($largeStore)
        try {
            $writer.WriteLine((ConvertTo-Json -InputObject @($legacy) -Depth 8))
            $padding = ' ' * 8192
            for ($i = 0; $i -lt 6400; $i++) { $writer.WriteLine($padding) }
        } finally { $writer.Dispose() }
        $original = (Get-FileHash -LiteralPath $largeStore).Hash
        $db = Get-QOTickets -Quiet
        Assert ($db.Tickets[0].PendingReplies[0].Body -ceq $long) 'Loading truncated a queued message'
        Assert ((Get-FileHash -LiteralPath $largeStore).Hash -eq $original) 'Reading rewrote the live legacy store'
        Save-QOTickets -Database $db -Quiet
        $stored = (Get-QOTickets -Quiet).Tickets[0]
        Assert ([IO.File]::ReadAllText($stored.Replies[0].BodyPath) -ceq $long) 'History lost text during body offload'
        Assert ($stored.PendingReplies[0].Body -ceq $long) 'Saving truncated a queued message'
    }
} finally {
    foreach ($name in $originalEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
    }
    $path = [IO.Path]::GetFullPath($root)
    if ([IO.Path]::GetDirectoryName($path) -eq [IO.Path]::GetTempPath().TrimEnd('\') -and
        [IO.Path]::GetFileName($path) -match '^QOT ticket tests [0-9a-f]{32}$') {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}
if ($failures.Count) { throw ($failures -join [Environment]::NewLine) }
