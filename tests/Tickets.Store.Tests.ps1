# Exercise stale editors and stores with two independent snapshots of real ticket data.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('QOTStore-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixture)
$failures = [Collections.Generic.List[string]]::new()
function Check([string]$Name,[scriptblock]$Test) {
    try { & $Test; Write-Host "PASS $Name" }
    catch { $failures.Add("$Name - $($_.Exception.Message)"); Write-Host "FAIL $Name - $($_.Exception.Message)" }
}
function Assert([bool]$Value,[string]$Problem) { if (!$Value) { throw $Problem } }
$originalData = $env:ProgramData
$originalLocal = $env:LOCALAPPDATA
$env:ProgramData = $fixture
$env:LOCALAPPDATA = $fixture
try {
    $module = Import-Module (Join-Path $repo 'src/Core/Tickets.psm1') -PassThru -DisableNameChecking
    & $module {
        param($dir)
        $script:TicketStorePath = Join-Path $dir 'Tickets.json'
        $script:TicketBackupPath = Join-Path $dir 'backups'
        function script:Write-QOTicketsCoreLog {}
    } $fixture
    Check 'customer replies preserve the exact mailbox and exclude the receiving support mailbox' {
        $customer = "O'Brien+case@example.invalid"
        $desk = 'support@example.invalid'
        $manual = New-QOTicket -Title 'Manual' -EmailTo $customer -SourceMailbox $desk
        $incoming = [pscustomobject]@{ Source='Outlook'; SourceMailbox=$desk; SenderEmail=$customer; EmailTo=$desk }
        $outgoing = [pscustomobject]@{ Source='Outlook'; SourceMailbox=$desk; SenderEmail=$desk; EmailTo=$customer }
        $legacy = [pscustomobject]@{ Source='Email'; EmailFrom="Technician Known <$customer>"; EmailTo=$desk }
        foreach ($ticket in @($manual,$incoming,$outgoing,$legacy)) {
            $address = & $module { param($row) Get-QOTicketPrimaryEmailAddress -Ticket $row } $ticket
            Assert ($address -ceq $customer) "Customer mailbox changed to '$address'"
        }
        foreach ($invalid in 'broken word customer@example.invalid', 'one@example.invalid;two@example.invalid', 'one@example.invalid,two@example.invalid') {
            $manual.EmailTo = $invalid
            $address = & $module { param($row) Get-QOTicketPrimaryEmailAddress -Ticket $row } $manual
            Assert (!$address) 'Malformed address was shortened to a different mailbox'
        }
        $incoming.SenderEmail = $desk
        Assert (!(& $module { param($row) Get-QOTicketPrimaryEmailAddress -Ticket $row } $incoming)) 'Reply would be sent to the support mailbox'
    }
    Check 'dispatch uses the current ticket address and never recovers a cleared address from the editor' {
        $customer = "O'Brien+case@example.invalid"
        $old = Add-QOTicket (New-QOTicket -Title 'Dispatch' -SenderEmail $customer -SourceMailbox 'desk@example.invalid')
        $send = {
            param($row)
            function Import-QOTOutlookIntegrationModule { $true }
            function Send-QOTicketOutlookEmail { param($To,$FromMailbox,$Subject,$Body,$TicketId) [pscustomobject]@{Success=$true;To=$To} }
            function Send-QOTicketOutlookReply { throw 'Unexpected Outlook reply transport' }
            Send-QOTicketReply -Ticket $row -Subject 'Test' -Body 'Fixture' -TransportOnly
        }
        $sent = & $module $send $old
        Assert ($sent.Success -and $sent.To -ceq $customer) 'Mail transport received a different customer'
        $current = Get-QOTickets -Quiet
        $row = $current.Tickets | Where-Object Id -eq $old.Id
        $row.SenderEmail = ''
        $row.EmailFrom = ''
        Save-QOTickets $current -Quiet
        $blocked = & $module $send $old
        Assert (!$blocked.Success) 'Dispatch rebuilt a removed recipient from an old editor'
    }
    Check 'recording delivered mail preserves a contact correction and the actual sent address' {
        $old = Add-QOTicket (New-QOTicket -Title 'Receipt' -EmailTo 'original@example.invalid' -AssignedTo Pat -SourceMailbox 'desk@example.invalid')
        $fresh = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $old.Id
        $fresh.EmailTo = 'current@example.invalid'
        $null = Update-QOTicket $fresh
        $sent = Complete-QOTTicketReplySend -Ticket $old -Subject Receipt -Body Sent -SendResult ([pscustomobject]@{Success=$true})
        $saved = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $old.Id
        Assert ($sent.Persisted -and $saved.EmailTo -eq 'current@example.invalid' -and $saved.Replies[0].To -eq 'original@example.invalid') 'The receipt showed a customer other than the one contacted'
    }
    Check 'legacy aliases and quoted mailbox whitespace survive a store round trip' {
        $quoted = '"client   ticket"@example.invalid'
        $ticket = Add-QOTicket (New-QOTicket -Title 'Quoted address' -EmailTo $quoted)
        $legacy = New-QOTicket -Title 'Legacy address'
        $legacy | Add-Member -NotePropertyName From -NotePropertyValue "Client <O'Brien@example.invalid>"
        $null = Add-QOTicket $legacy
        $rows = (Get-QOTickets -Quiet).Tickets
        Assert ((Get-QOTicketPrimaryEmailAddress ($rows | Where-Object Id -eq $ticket.Id)) -ceq $quoted) 'Whitespace changed the quoted mailbox'
        Assert ((Get-QOTicketPrimaryEmailAddress ($rows | Where-Object Id -eq $legacy.Id)) -ceq "O'Brien@example.invalid") 'Migration changed the legacy mailbox'
    }
    Check 'missing Outlook originals fall back to the verified customer and report the delivery error' {
        $desk = 'support@example.invalid'
        $customer = "O'Brien@example.invalid"
        $ticket = New-QOTicket -Source Outlook -Title 'Inbound' -EmailTo $desk -SourceMailbox $desk -SenderEmail $customer
        $ticket | Add-Member -NotePropertyName SourceMessageId -NotePropertyValue 'missing-item'
        $ticket = Add-QOTicket $ticket
        $result = & $module {
            param($row,$customer)
            function Import-QOTOutlookIntegrationModule { $true }
            function Send-QOTicketOutlookReply {
                param($Ticket,$Subject,$Body,$FromMailbox,$TicketId,$ExpectedRecipient)
                if ($ExpectedRecipient -cne $customer) { throw 'Incorrect threaded recipient' }
                [pscustomobject]@{Success=$false;Note='Original email not found in Outlook'}
            }
            function Send-QOTicketOutlookEmail {
                param($To,$Subject,$Body,$FromMailbox,$TicketId)
                if ($To -cne $customer) { throw 'Incorrect fallback recipient' }
                [pscustomobject]@{Success=$false;Note='Cannot resolve configured account'}
            }
            Send-QOTicketReply -Ticket $row -Subject Fixture -Body Fixture -TransportOnly
        } $ticket $customer
        Assert (!$result.Success -and $result.Note -eq 'Cannot resolve configured account') 'The fallback delivery error was hidden'
    }
    Check 'enqueue and retry preserve the reviewed destination and retain failed drafts' {
        $old = Add-QOTicket (New-QOTicket -Title 'Edited draft route' -EmailTo 'first@example.invalid')
        $null = Add-QOTTicketPendingReply -TicketId $old.Id -DraftId 'failed' -Subject Retry -Body 'Original'
        $null = Set-QOTTicketPendingReplyState -TicketId $old.Id -DraftId failed -SendState Failed -FailureNote 'Offline'
        $beforeContactEdit = Get-QOTickets -Quiet
        $expectedRoute = Get-QOTTicketPendingReplyMetadataFromTicket $old
        $current = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $old.Id
        $current.EmailTo = 'second@example.invalid'
        $null = Update-QOTicket $current
        $blocked = $false
        try { Save-QOTickets -Database $beforeContactEdit -Quiet -RouteTicketId $old.Id -ExpectedRoute $expectedRoute } catch { $blocked=$true }
        Assert $blocked 'Commit accepted a stale destination after an independent update'
        $blocked = $false
        try { $null = Add-QOTTicketPendingReply -TicketId $old.Id -DraftId 'another' -Subject Draft -Body Private -Ticket $old } catch { $blocked=$true }
        Assert ($blocked -and !(Get-QOTTicketPendingReply -TicketId $old.Id -DraftId another)) 'Enqueue silently redirected the reviewed draft'
        $retry = {
            param($id)
            function Initialize-QOTicketsReplyQueueService { [pscustomobject]@{WorkerRunning=$false;WorkerStarted=$false;ActiveCount=1} }
            Retry-QOTTicketPendingReply -TicketId $id -DraftId failed
        }
        $blocked = $false
        try { $null = & $module $retry $old.Id } catch { $blocked=$true }
        $failed = Get-QOTTicketPendingReply -TicketId $old.Id -DraftId failed
        Assert ($blocked -and $failed.SendState -eq 'Failed' -and $failed.Body -eq 'Original') 'Retry redirected or removed the failed draft'
        $current.EmailTo = 'first@example.invalid'
        $null = Update-QOTicket $current
        $replacement = & $module $retry $old.Id
        Assert ($replacement.DraftId -ne 'failed' -and $replacement.To -eq $current.EmailTo -and !(Get-QOTTicketPendingReply -TicketId $old.Id -DraftId failed)) 'Retry failed to replace the original draft'
    }
    Check 'cancelling cannot erase a receipt written after the queue was displayed' {
        $ticket = Add-QOTicket (New-QOTicket -Title 'Cancel during delivery' -EmailTo 'client@example.invalid')
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -DraftId 'raced' -Subject Race -Body Fixture
        $cancel = & $module {
            param($id)
            $lookup = Get-Command Get-QOTTicketPendingReply
            function Get-QOTTicketPendingReply($TicketId,$DraftId) {
                $old = & $lookup -TicketId $TicketId -DraftId $DraftId
                $null = Set-QOTTicketPendingReplyState $TicketId $DraftId Sent -DeliveryReceipt ([pscustomobject]@{Success=$true;SentEntryId='accepted'})
                return $old
            }
            Cancel-QOTTicketPendingReply $id raced
        } $ticket.Id
        $row = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id
        Assert (!$cancel.Cancelled -and $row.PendingReplies[0].DeliveryReceipt.SentEntryId -eq 'accepted') 'Cancellation discarded a confirmed submission'
    }
    Check 'a worker cannot dispatch superseded draft text' {
        $ticket = Add-QOTicket (New-QOTicket -Title 'Edited before claim' -EmailTo 'client@example.invalid')
        $picked = Add-QOTTicketPendingReply -TicketId $ticket.Id -DraftId edited -Subject 'First' -Body 'Obsolete body'
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -DraftId edited -Subject 'Final' -Body 'Corrected body'
        $claimed = Set-QOTTicketPendingReplyState $ticket.Id edited Sending
        $result = & $module {
            param($row,$picked)
            function Import-QOTOutlookIntegrationModule { $true }
            function Send-QOTicketOutlookEmail { [pscustomobject]@{Success=$true} }
            Send-QOTicketReply -Ticket $row -Subject $picked.Subject -Body $picked.Body -PendingReplyDraftId edited -TransportOnly
        } $ticket $picked
        Assert ($claimed.Body -eq 'Corrected body' -and !$result.Success -and $result.Note -like '*content*') 'Transport accepted obsolete draft text'
    }
    Check 'an outbound receipt does not invalidate other fresh-mail replies on the same ticket' {
        $ticket = Add-QOTicket (New-QOTicket -Title 'Two outbound replies' -EmailTo 'client@example.invalid')
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -DraftId first -Subject First -Body First
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -DraftId second -Subject Second -Body Second
        $null = Set-QOTTicketPendingReplyState $ticket.Id first Sending
        $receipt = [pscustomobject]@{Success=$true; ConversationId='first-outbound-conversation'}
        $null = Set-QOTTicketPendingReplyState $ticket.Id first Sent -DeliveryReceipt $receipt
        $recorded = Complete-QOTTicketReplySend $ticket First First $receipt -PendingReplyDraftId first
        $null = Set-QOTTicketPendingReplyState $ticket.Id second Sending
        $result = & $module {
            param($row)
            function Import-QOTOutlookIntegrationModule { $true }
            function Send-QOTicketOutlookEmail { param($To); [pscustomobject]@{Success=$true;To=$To} }
            function Send-QOTicketOutlookReply { throw 'The second message must still be a fresh outbound email' }
            Send-QOTicketReply -Ticket $row -Subject Second -Body Second -PendingReplyDraftId second -TransportOnly
        } $ticket
        Assert ($recorded.Persisted -and $result.Success -and $result.To -eq 'client@example.invalid') 'Recording the first reply blocked the second queued email'
    }
    Check 'an unrecognized saved delivery state requires review before sending' {
        $ticket = Add-QOTicket (New-QOTicket -Title 'Legacy mail state' -EmailTo 'client@example.invalid')
        $null = Add-QOTTicketPendingReply -TicketId $ticket.Id -DraftId legacy -Subject Legacy -Body Fixture
        $db = Get-QOTickets -Quiet
        ($db.Tickets | Where-Object Id -eq $ticket.Id).PendingReplies[0].SendState = 'UnknownState'
        Save-QOTickets $db -Quiet
        $entry = Get-QOTTicketPendingReply $ticket.Id legacy
        Assert ($entry.SendState -eq 'Failed') 'An unknown state was selected for automatic delivery'
        $null = & $module { Repair-QOTPendingReplyQueueState -Quiet }
        $entry = Get-QOTTicketPendingReply $ticket.Id legacy
        Assert ($entry.SendState -eq 'Failed' -and $entry.FailureNote -like '*review*') 'Unrecognized delivery state lacks an actionable explanation'
    }
    Check 'a launched queue worker is pinned to the requested ticket store' {
        $observed = & $module {
            $capture = @{}
            function Get-QOTPendingReplyQueueSnapshot { [pscustomobject]@{ActiveCount=1} }
            function Test-QOTicketsReplyQueueWorkerRunning { $false }
            function Test-QOTProcessElevated { $false }
            function Start-Process($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,[switch]$PassThru) {
                $capture.Arguments = $ArgumentList
                [pscustomobject]@{Id=123}
            }
            $null = Start-QOTicketsReplyQueueWorker
            $capture.Arguments
        }
        $expected = & $module { Convert-QOTReplyQueueProcessArgumentString @('-StorePath',(Get-QOTicketsStorePath)) }
        Assert ($observed.Contains($expected)) 'The queue worker launch omitted the original store'
    }
    Check 'older queued entries keep the same distinct IDs through read, claim and reload' {
        $path = Join-Path $fixture 'Tickets.json'
        $body = [pscustomobject]@{Subject='Legacy';Body='Identical';To='legacy@example.invalid';SendState='Queued'}
        $known = [pscustomobject]@{ReplyId='legacy-reply-id';Subject='Known';Body='Known';To='legacy@example.invalid';SendState='Queued'}
        $row = [pscustomobject]@{Id='old-queue';Title='Old queue';PendingReplies=@($body,$body,$known)}
        [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject @($row) -Depth 10))
        $first = @(Get-QOTicketPendingReplies -TicketId $row.Id)
        $next = Get-QOTNextPendingReply
        $claimed = Set-QOTTicketPendingReplyState $next.TicketId $next.DraftId Sending
        $second = @(Get-QOTicketPendingReplies -TicketId $row.Id)
        Assert ($claimed -and $first[2].DraftId -eq 'legacy-reply-id' -and (@($second.DraftId | Select-Object -Unique).Count -eq 3) -and (($first.DraftId -join ',') -ceq ($second.DraftId -join ','))) 'Repeated reads changed the ID and the worker could not claim the legacy entry'
    }
    Check 'legacy text deletion flags keep active tickets visible' {
        $legacy = @(
            @{Id='text-false'; Title='Visible'; IsDeleted='False'}
            @{Id='text-zero'; Title='Also visible'; IsDeleted='0'}
            @{Id='text-true'; Title='Trashed'; IsDeleted='TRUE'}
            @{Id='folder'; Title='Older trash'; Folder='Deleted'}
        )
        [IO.File]::WriteAllText((Join-Path $fixture 'Tickets.json'), (ConvertTo-Json -InputObject $legacy))
        $active = @(Get-QOTicketsByBucket Open)
        $trash = @(Get-QOTicketsByBucket Deleted)
        Assert ($active.Count -eq 2 -and $active.Id -contains 'text-false' -and $active.Id -contains 'text-zero') 'Legacy false deletion flags hid active tickets'
        Assert ($trash.Count -eq 2 -and $trash.Id -contains 'text-true' -and $trash.Id -contains 'folder') 'Legacy trash status was lost'
    }
    Check 'two notes with equal text and dates retain their individual IDs' {
        $ticket = New-QOTicket -Title 'Notes'
        $ticket.Notes = @('note-a','note-b' | ForEach-Object {
            [pscustomobject]@{NoteId=$_; Body='Called'; CreatedAt='2026-02-01 10:00:00'; Author='Tech'}
        })
        $null = Add-QOTicket $ticket
        $notes = ((Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id).Notes
        Assert ($notes.Count -eq 2) 'A distinct note disappeared'
        $null = Remove-QOTicketNote -Id $ticket.Id -NoteId 'note-a'
        $notes = ((Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id).Notes
        Assert ($notes.Count -eq 1 -and $notes[0].NoteId -eq 'note-b') 'Removing one note removed its neighbour'
    }
    Check 'adding the same ticket ID twice leaves exactly one stored ticket' {
        $ticket = Add-QOTicket (New-QOTicket -Title 'Retry')
        try { $null = Add-QOTicket $ticket } catch { }
        Assert (@((Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id).Count -eq 1) 'Duplicate ID persisted'
    }
    Check 'an editor holding an old row preserves subsequent notes and trash state' {
        $new = Add-QOTicket (New-QOTicket -Title 'Edited')
        $old = Get-QOTicketsByFolder Active | Where-Object Id -eq $new.Id
        $null = Add-QOTicketNote -Id $new.Id -Note 'Call customer' -NoteId 'contact'
        Remove-QOTicket -Id $new.Id
        $old.AssignedTo = 'Pat'
        Assert (Update-QOTicket $old) 'Assignment did not save'
        $saved = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $new.Id
        Assert ($saved.AssignedTo -eq 'Pat' -and $saved.IsDeleted -and $saved.Notes.NoteId -contains 'contact') 'Editor overwrote the later note or restored a deleted ticket'
        Set-QOTicketsAssignedTo -Id $new.Id -AssignedTo 'Lee'
        $old.Priority = 'High'
        Assert (Update-QOTicket $old) 'A second edit from the same window did not save'
        $saved = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $new.Id
        Assert ($saved.AssignedTo -eq 'Lee' -and $saved.Priority -eq 'High') 'A second edit resubmitted the old assignment'
    }
    Check 'note additions and removals from two open snapshots merge by note ID' {
        $ticket = Add-QOTicket (New-QOTicket -Title 'Notes in two editors')
        $null = Add-QOTicketNote -Id $ticket.Id -Note 'Old' -NoteId 'old'
        $beforeRemoval = Get-QOTickets -Quiet
        $row = $beforeRemoval.Tickets | Where-Object Id -eq $ticket.Id
        $row.Notes += [pscustomobject]@{NoteId='second'; Body='Check router'; CreatedAt='2026-02-01 10:00:00'}
        $null = Remove-QOTicketNote -Id $ticket.Id -NoteId 'old'
        $null = Add-QOTicketNote -Id $ticket.Id -Note 'Call supplier' -NoteId 'first'
        Save-QOTickets $beforeRemoval -Quiet
        $saved = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $ticket.Id
        Assert ($saved.Notes.Count -eq 2 -and $saved.Notes.NoteId -contains 'first' -and $saved.Notes.NoteId -contains 'second') 'Note additions conflicted or a removed note returned'
    }
    Check 'a stale database save preserves a field written by another PowerShell process' {
        $new = Add-QOTicket (New-QOTicket -Title 'Parallel edit')
        $second = Get-QOTickets -Quiet
        $b = $second.Tickets | Where-Object Id -eq $new.Id
        $b.Priority = 'High'
        $worker = Join-Path $fixture 'set-status.ps1'
        @'
param($ModulePath,$Fixture,$TicketId)
$ErrorActionPreference = 'Stop'
$env:ProgramData = $Fixture
$env:LOCALAPPDATA = $Fixture
$module = Import-Module $ModulePath -PassThru -DisableNameChecking
& $module {
    param($dir)
    $script:TicketStorePath = Join-Path $dir 'Tickets.json'
    $script:TicketBackupPath = Join-Path $dir 'backups'
    function script:Write-QOTicketsCoreLog {}
} $Fixture
Set-QOTicketsStatus -Id $TicketId -Status Pending
'@ | Set-Content -LiteralPath $worker
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker $module.Path $fixture $new.Id
        Assert ($LASTEXITCODE -eq 0) 'Second process failed to update its field'
        Save-QOTickets $second -Quiet
        $saved = (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $new.Id
        Assert ($saved.Status -eq 'Pending' -and $saved.Priority -eq 'High') 'A successful save lost another user''s change'
    }
    Check 'conflicting edits report a conflict and preserve the committed value' {
        $new = Add-QOTicket (New-QOTicket -Title 'Same field')
        $first = Get-QOTickets -Quiet
        $second = Get-QOTickets -Quiet
        ($first.Tickets | Where-Object Id -eq $new.Id).AssignedTo = 'Pat'
        ($second.Tickets | Where-Object Id -eq $new.Id).AssignedTo = 'Lee'
        Save-QOTickets $first -Quiet
        $rejected = $false
        try { Save-QOTickets $second -Quiet } catch { $rejected = $true }
        Assert ($rejected -and ((Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $new.Id).AssignedTo -eq 'Pat') 'A competing assignment was silently overwritten'
    }
    Check 'old snapshots cannot resurrect a removed ticket' {
        $new = Add-QOTicket (New-QOTicket -Title 'Removed from store')
        $old = Get-QOTickets -Quiet
        $fresh = Get-QOTickets -Quiet
        $fresh.Tickets = @($fresh.Tickets | Where-Object Id -ne $new.Id)
        Save-QOTickets $fresh -Quiet
        Save-QOTickets $old -Quiet
        Assert ($old.Tickets.Id -notcontains $new.Id) 'Stale save brought back a removed ticket'
    }
    Check 'switching storage refuses old grid rows and database snapshots' {
        $ticket = Add-QOTicket (New-QOTicket -Title 'Store selection')
        $row = Get-QOTicketsByBucket Open | Where-Object Id -eq $ticket.Id
        $db = Get-QOTickets -Quiet
        $src = Join-Path $fixture 'Tickets.json'
        $other = Join-Path $fixture 'Other.json'
        [IO.File]::Copy($src, $other)
        & $module { param($path) $script:TicketStorePath = $path } $other
        $row.Status = 'Closed'
        $stoppedRow = $false
        $stoppedDb = $false
        try { $null = Update-QOTicket $row } catch { $stoppedRow = $true }
        try { Save-QOTickets $db -Quiet } catch { $stoppedDb = $true }
        Assert ($stoppedRow -and $stoppedDb -and [IO.File]::ReadAllText($src) -ceq [IO.File]::ReadAllText($other)) 'Stale editor changed the selected store'
    }
} finally {
    $env:LOCALAPPDATA = $originalLocal
    $env:ProgramData = $originalData
    $path = (Resolve-Path -LiteralPath $fixture).Path
    if ((Split-Path -Parent $path) -eq [IO.Path]::GetTempPath().TrimEnd('\') -and (Split-Path -Leaf $path) -match '^QOTStore-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}
if ($failures.Count) { throw ($failures -join [Environment]::NewLine) }
