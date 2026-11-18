# Exercise delivery decisions with Outlook-shaped objects. No COM session or mailbox is opened.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$module = Import-Module (Join-Path $repo 'src/Tickets/Tickets.Email.Outlook.psm1') -Force -PassThru -DisableNameChecking

function Assert([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
    Write-Host "PASS $Message"
}
function New-Collection([object[]]$Items) {
    $collection = [pscustomobject]@{ Count = $Items.Count; Values = $Items }
    $collection | Add-Member ScriptMethod Item { param($index) $this.Values[$index - 1] }
    $collection | Add-Member ScriptMethod ResolveAll { $true }
    return $collection
}
function New-Account([string]$Address, [string]$Inbox) {
    $store = [pscustomobject]@{ DisplayName = $Address; Inbox = $Inbox }
    $store | Add-Member ScriptMethod GetDefaultFolder { param($kind) if ($kind -eq 6) { $this.Inbox } }
    return [pscustomobject]@{ SmtpAddress = $Address; DisplayName = $Address; DeliveryStore = $store }
}
$address = "o'brien@example.invalid"
$recipient = [pscustomobject]@{ Address = $address }
$mail = [pscustomobject]@{ To = ''; Subject = ''; Body = ''; BodyFormat = 1; SendUsingAccount = $null; SentOnBehalfOfName = ''; Recipients = (New-Collection @($recipient)); Sent = 0 }
$mail | Add-Member ScriptMethod Send { $this.Sent++ }
$source = [pscustomobject]@{ Draft = $mail }
$source | Add-Member ScriptMethod Reply { $this.Draft }
$first = New-Account 'support@first.invalid' 'first inbox'
$second = New-Account 'support@second.invalid' 'second inbox'
$mapi = [pscustomobject]@{ Accounts = (New-Collection @($first,$second)); Stores = (New-Collection @($first.DeliveryStore,$second.DeliveryStore)); Source = $source }
$mapi | Add-Member ScriptMethod CreateRecipient { throw 'Shared access unavailable' }
$mapi | Add-Member ScriptMethod GetDefaultFolder { 'first inbox' }
$mapi | Add-Member ScriptMethod GetItemFromID { $this.Source }
$app = [pscustomobject]@{ Draft = $mail }
$app | Add-Member ScriptMethod CreateItem { $this.Draft }
& $module {
    param($MapiFixture,$AppFixture)
    $script:MapiFixture = $MapiFixture
    $script:AppFixture = $AppFixture
    function script:Initialize-QOTicketsCoreApi { }
    function script:Get-QOTOutlookNamespace { $script:MapiFixture }
    function script:Get-QOTOutlookApplication { $script:AppFixture }
    function script:Get-QOTEffectiveMonitoredMailboxAddresses { @() }
    function script:Get-QOTConfiguredMailboxAddresses { @() }
    function script:Write-QOTOutlookSyncLog { }
} $mapi $app

$stored = [pscustomobject]@{ Id='stored'; Source='Outlook'; SourceMessageId='entry'; EmailBody='original body'; UpdatedAt='2026-09-21 09:00:00' }
$incoming = [pscustomobject]@{ SourceMessageId='entry'; SenderEmail='customer@example.invalid'; UpdatedAt='2026-08-20 10:00:00'; EmailBody='original body' }
$changed = & $module { param($row,$mail) Update-QOTExistingTicketFromMailItem $row $mail } $stored $incoming
$unchanged = & $module { param($row,$mail) Update-QOTExistingTicketFromMailItem $row $mail } $stored $incoming
Assert ($changed -and !$unchanged -and $stored.SenderEmail -eq $incoming.SenderEmail -and $stored.UpdatedAt -eq '2026-09-21 09:00:00') 'A sender-only update schedules a save once and keeps newer local edits dated correctly'

$normalized = & $module { param($value) Normalize-QOTEmailAddress $value } $address
Assert ($normalized -ceq $address) 'Mailbox lookup preserves apostrophes in the complete address'
$result = Send-QOTicketOutlookEmail -To "Customer <$address>" -Subject 'Fixture' -Body 'Fixture'
Assert ($result.Success -and $mail.Sent -eq 1 -and $mail.To -ceq $address) 'New mail uses the single complete customer address'
$result = Send-QOTicketOutlookEmail -To "$address; extra@example.invalid" -Subject 'Fixture' -Body 'Fixture'
Assert (!$result.Success -and $mail.Sent -eq 1) 'Multiple destinations are rejected before sending'
$recipient.Address = 'other@example.invalid'
$result = Send-QOTicketOutlookEmail -To $address -Subject 'Fixture' -Body 'Fixture'
Assert (!$result.Success -and $mail.Sent -eq 1) 'An Outlook contact resolved to another mailbox cannot receive the ticket'
$ticket = [pscustomobject]@{ SourceMessageId = 'source'; SourceMailbox = $second.SmtpAddress }
$send = @{ Ticket = $ticket; ExpectedRecipient = $address; Subject = 'Fixture'; Body = 'Fixture' }
$result = Send-QOTicketOutlookReply @send
Assert (!$result.Success -and $mail.Sent -eq 1) 'A threaded reply with a different Reply-To is held'
$recipient.Address = $address
$mail.Recipients = New-Collection @($recipient,$recipient)
$result = Send-QOTicketOutlookReply @send
Assert (!$result.Success -and $mail.Sent -eq 1) 'A threaded reply with an additional resolved recipient is held'
$exchangeUser = [pscustomobject]@{ PrimarySmtpAddress = $address }
$entry = [pscustomobject]@{ Address = '/o=fixture/ou=address'; User = $exchangeUser }
$entry | Add-Member ScriptMethod GetExchangeUser { $this.User }
$mail.Recipients = New-Collection @([pscustomobject]@{ Address = $entry.Address; AddressEntry = $entry })
$result = Send-QOTicketOutlookReply @send
Assert ($result.Success -and $mail.Sent -eq 2 -and $mail.SendUsingAccount -eq $second) 'A single verified Exchange recipient receives the reply through the requested account'
$mail | Add-Member ScriptMethod Send -Force { $this.Sent++; throw 'Value does not fall within the expected range' }
$result = Send-QOTicketOutlookReply @send
Assert (!$result.Success -and $result.SubmissionUnconfirmed -and $mail.Sent -eq 3 -and $result.Note -like '*Sent Items*') 'A reply submission exception leaves the draft for review after exactly one Outlook handoff'
$mail | Add-Member ScriptMethod Send -Force { $this.Sent++; throw 'Server busy' }
$result = Send-QOTicketOutlookEmail -To $address -Subject 'Fixture' -Body 'Fixture'
Assert (!$result.Success -and $result.SubmissionUnconfirmed -and $mail.Sent -eq 4 -and $result.Note -like '*Outbox*') 'New mail with an unconfirmed handoff requires review even when Outlook reports busy'
$source | Add-Member NoteProperty Attempts 0
$source | Add-Member ScriptMethod Reply -Force {
    $this.Attempts++
    if ($this.Attempts -eq 1) { throw 'Value does not fall within the expected range' }
    $this.Draft
}
$mail | Add-Member ScriptMethod Send -Force { $this.Sent++ }
$result = Send-QOTicketOutlookReply @send
Assert ($result.Success -and $source.Attempts -eq 2 -and $mail.Sent -eq 5 -and $result.Note -eq 'Submitted to Outlook.') 'A composition error can rebuild the draft before one successful submission'
$inbox = & $module { param($map,$target) Get-QOTMailboxInboxFolder $map $target } $mapi $second.SmtpAddress
Assert ($inbox -eq 'second inbox') 'Secondary mailbox fallback opens its delivery store'
$first.DisplayName = $second.SmtpAddress
$account = & $module { param($map,$target) Get-QOTOutlookAccountForMailbox $map $target } $mapi $second.SmtpAddress
Assert ($account -eq $second) 'A misleading account display name cannot override its SMTP address'
$mapi.Accounts = New-Collection @()
$inbox = & $module { param($map,$target) Get-QOTMailboxInboxFolder $map $target } $mapi $second.SmtpAddress
Assert ($inbox -eq 'second inbox') 'Store-only fallback uses the exact address and the localized default Inbox'
$failed = $false
try { $null = & $module { param($map) Get-QOTMailboxInboxFolder $map 'support@unknown.invalid' } $mapi } catch { $failed = $true }
Assert $failed 'A similar mailbox name cannot substitute for a missing Inbox'

$oldMail = [pscustomobject]@{ ReceivedTime = (Get-Date).AddDays(-10); MessageClass = 'IPM.Note'; EntryID = 'old' }
$newMail = [pscustomobject]@{ ReceivedTime = Get-Date; MessageClass = 'IPM.Note'; EntryID = 'recent' }
$accessor = [pscustomobject]@{}
$accessor | Add-Member ScriptMethod GetProperty { param($property) if ($property -like '*/0x1035001F') { return '<FiXtUrE@example.invalid>' }; throw 'Missing property' }
$newMail | Add-Member NoteProperty PropertyAccessor $accessor
$items = New-Collection @($newMail,$oldMail)
$items | Add-Member NoteProperty FailAt 2
$items | Add-Member ScriptMethod Item -Force { param($n) if ($this.FailAt -eq $n) { throw 'Disconnected Inbox' }; $this.Values[$n - 1] }
$items | Add-Member NoteProperty CanSort $true
$items | Add-Member ScriptMethod Sort { if (!$this.CanSort) { throw 'Sort unavailable' } }
& $module {
    param($items)
    $script:Items = $items
    $script:ScanState = @{ Watermark = 0; SuccessTime = 0; Saved = @() }
    function script:Get-QOTickets { [pscustomobject]@{ Tickets = @() } }
    function script:Get-QOTicketsStorePath { 'fixture.json' }
    function script:Save-QOTickets($Database) { $script:ScanState.Saved = @($Database.Tickets) }
    function script:Get-QOTMonitoredMailboxAddresses { 'fixture@example.invalid' }
    function script:Get-QOTEffectiveMonitoredMailboxAddresses { 'fixture@example.invalid' }
    function script:Get-QOTMailboxInboxFolder($MAPI,$MailboxAddress) {
        $script:ScanState.LastMailbox = $MailboxAddress
        [pscustomobject]@{ Items = $script:Items }
    }
    function script:Get-QOTEmailSyncScope { [pscustomobject]@{ LastSyncUtc=[datetime]::UtcNow.AddDays(-2); MonitoredAddresses=@('fixture@example.invalid') } }
    function script:Get-QOTEffectiveEmailCutoffUtc { [datetime]::UtcNow.AddDays(-1) }
    function script:Set-QOEmailSyncCheckpoint($Revision,$CompletedUtc,$WatermarkUtc) {
        if ($WatermarkUtc) { $script:ScanState.Watermark++ }
        $script:ScanState.SuccessTime++
        return $true
    }
    function script:Convert-QOTMailItemToTicket($MailboxAddress,$MailItem) { [pscustomobject]@{ Id = $MailItem.EntryID } }
    function script:Get-QOTTicketIdentityKeys($Ticket) { $Ticket.Id }
} $items
$scan = Sync-QOTicketsFromOutlook
$state = & $module { $script:ScanState }
Assert (!$scan.Success -and !$scan.WatermarkAdvanced -and $state.Watermark -eq 0 -and $state.SuccessTime -eq 0 -and $state.Saved[0].Id -eq 'recent') 'A partial Inbox read saves fetched tickets and holds both sync timestamps for retry'
$items.FailAt = 0
$items.CanSort = $false
$items.Values = @($oldMail,$newMail)
$scan = Sync-QOTicketsFromOutlook
Assert ($scan.Success -and $scan.Added -eq 1 -and $state.Saved[0].Id -eq 'recent' -and $state.Watermark -eq 1) 'An unsorted Inbox still imports newer messages after an old message'
$found = & $module { param($map) Find-QOTOutlookMessageByInternetId $map 'fixture@example.invalid' -MailboxAddress 'second@example.invalid' } $mapi
Assert ($found -eq $newMail -and $state.LastMailbox -eq 'second@example.invalid') 'Reply lookup uses the original mailbox and the same normalized Internet Message-ID as import'

$newMail | Add-Member NoteProperty Categories 'Customer'
$newMail | Add-Member NoteProperty UnRead $true
$newMail | Add-Member NoteProperty Saves 0
$newMail | Add-Member ScriptMethod Save { $this.Saves++ }
& $module { function script:Save-QOTickets { throw 'Fixture store is full' } }
$failed = $false
try { $null = Sync-QOTicketsFromOutlook -MarkAsRead } catch { $failed = $_.Exception.Message -match 'Fixture store is full' }
Assert ($failed -and $newMail.UnRead -and $newMail.Categories -eq 'Customer' -and $newMail.Saves -eq 0) 'A failed ticket save leaves the Outlook message unread and its categories intact'
& $module { function script:Save-QOTickets($Database) { $script:ScanState.Saved = @($Database.Tickets) } }
$null = Sync-QOTicketsFromOutlook -MarkAsRead
Assert (!$newMail.UnRead -and $newMail.Categories -match 'QOT Imported' -and $newMail.Saves -eq 1) 'A successful ticket save applies the Outlook category and read flag'
