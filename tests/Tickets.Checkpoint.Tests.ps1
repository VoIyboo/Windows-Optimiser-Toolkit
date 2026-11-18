# Real settings and importer with disposable, in-memory Inboxes.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$previousSettings = $env:QOT_SETTINGS_PATH
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('qot-checkpoint-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$env:QOT_SETTINGS_PATH = Join-Path $fixture 'settings.json'
function Assert($condition,$message) { if (!$condition) { throw $message }; Write-Host "PASS $message" }
try {
    $module = Import-Module (Join-Path $repo 'src/Tickets/Tickets.Email.Outlook.psm1') -Force -DisableNameChecking -PassThru
    $today = (Get-Date).Date
    $firstStore = Join-Path $fixture 'original.json'
    $nextStore = Join-Path $fixture 'new.json'
    $null = Set-QOTicketStorageSettings -StorePath $firstStore
    $null = Set-QOMonitoredMailboxAddresses @('first@example.invalid')
    $null = Set-QOEmailSyncStartDatePinned $today.AddDays(-7)
    & $module {
        $script:Rows = @()
        $script:Ages = @{ 'first@example.invalid' = -2; 'new@example.invalid' = -4; 'third@example.invalid' = -5 }
        $script:ChangeWhileScanning = $false
        function script:Initialize-QOTicketsCoreApi { }
        function script:Write-QOTOutlookSyncLog { }
        function script:Get-QOTOutlookNamespace { 'fake' }
        function script:Get-QOTMonitoredMailboxAddresses { Get-QOMonitoredMailboxAddresses }
        function script:Get-QOTickets { [pscustomobject]@{Tickets=$script:Rows} }
        function script:Get-QOTicketsStorePath { (Get-QOTicketStorageSettings).StorePath }
        function script:Save-QOTickets($Database) { $script:Rows = @($Database.Tickets) }
        function script:Get-QOTTicketIdentityKeys($Ticket) { $Ticket.Id }
        function script:Convert-QOTMailItemToTicket($MailboxAddress,$MailItem) { [pscustomobject]@{Id=$MailItem.EntryID} }
        function script:Get-QOTMailboxInboxFolder($MAPI,$MailboxAddress) {
            if ($script:ChangeWhileScanning) {
                $script:ChangeWhileScanning = $false
                $null = Set-QOMonitoredMailboxAddresses @('first@example.invalid','new@example.invalid','third@example.invalid')
            }
            $mail = [pscustomobject]@{
                EntryID=$MailboxAddress; ReceivedTime=(Get-Date).Date.AddDays($script:Ages[$MailboxAddress]).AddHours(1)
                MessageClass='IPM.Note'; Categories=''; UnRead=$true
            }
            $items = [pscustomobject]@{Count=1; Mail=$mail}
            $items | Add-Member ScriptMethod Item {param($index) $this.Mail}
            $items | Add-Member ScriptMethod Sort { }
            [pscustomobject]@{Items=$items}
        }
    }
    $first = Sync-QOTicketsFromOutlook -ProcessedCategory ''
    Assert ($first.Success -and $first.Added -eq 1 -and $first.WatermarkAdvanced) 'Initial import advances the original mailbox checkpoint'
    $null = Set-QOMonitoredMailboxAddresses @('new@example.invalid','first@example.invalid')
    $newScan = Sync-QOTicketsFromOutlook -ProcessedCategory ''
    Assert ($newScan.Added -eq 1 -and $newScan.AddedTickets[0].Id -eq 'new@example.invalid') 'Adding a mailbox imports its messages back to the pinned day'
    $progress = (Get-QOSettings).Tickets.EmailIntegration.LastSyncUtc
    $null = Set-QOMonitoredMailboxAddresses @('FIRST@example.invalid','new@example.invalid')
    $null = Set-QOEmailSyncStartDatePinned $today.AddDays(-7)
    Assert ((Get-QOSettings).Tickets.EmailIntegration.LastSyncUtc -eq $progress) 'Equivalent mailbox and date settings retain incremental progress'
    & $module { $script:Ages['first@example.invalid'] = -11; $script:Rows = @($script:Rows | Where-Object Id -ne 'first@example.invalid') }
    $null = Set-QOEmailSyncStartDatePinned $today.AddDays(-14)
    $backfill = Sync-QOTicketsFromOutlook -ProcessedCategory ''
    Assert ($backfill.Added -eq 1 -and $backfill.AddedTickets[0].Id -eq 'FIRST@example.invalid') 'Moving the start date earlier backfills the older Inbox period'
    & $module { $script:ChangeWhileScanning = $true }
    $outdated = Sync-QOTicketsFromOutlook -ProcessedCategory ''
    $current = (Get-QOSettings).Tickets.EmailIntegration
    Assert (!$outdated.WatermarkAdvanced -and !$current.LastSyncUtc -and !$current.LastSuccessfulSyncUtc) 'An in-flight scan cannot advance timestamps after its monitored mailboxes change'
    $retry = Sync-QOTicketsFromOutlook -ProcessedCategory ''
    Assert ($retry.Success -and $retry.Added -eq 1 -and $retry.AddedTickets[0].Id -eq 'third@example.invalid') 'The next pass imports the newly configured Inbox history'
    $settings = Get-QOSettings
    $revision = [string]$settings.Tickets.EmailIntegration.SyncRevision
    $time = [datetime]::UtcNow.AddMinutes(-30)
    $null = Set-QOEmailSyncCheckpoint -Revision $revision -CompletedUtc $time -WatermarkUtc $time
    $unchanged = (Get-QOSettings).Tickets.EmailIntegration
    Assert ($settings.Tickets.EmailIntegration.LastSyncUtc -eq $unchanged.LastSyncUtc -and $settings.Tickets.EmailIntegration.LastSuccessfulSyncUtc -eq $unchanged.LastSuccessfulSyncUtc) 'A slower import cannot move the same checkpoint backwards'
    $null = Set-QOMonitoredMailboxAddresses -Addresses @('auto@example.invalid') -IfUnconfigured
    Assert (@(Get-QOMonitoredMailboxAddresses).Count -eq 3) 'Late automatic mailbox discovery preserves the explicit monitored list'
    $legacy = [IO.File]::ReadAllText($env:QOT_SETTINGS_PATH) | ConvertFrom-Json
    $legacy.Tickets.EmailIntegration.LastSyncUtc = 'invalid timestamp'
    $legacy.Tickets.EmailIntegration.EmailSyncStartDatePinned = 'invalid date'
    [IO.File]::WriteAllText($env:QOT_SETTINGS_PATH, ($legacy | ConvertTo-Json -Depth 20))
    $null = Set-QOEmailSyncStartDatePinned $today.AddDays(-14)
    Assert ((Sync-QOTicketsFromOutlook -ProcessedCategory '').WatermarkAdvanced) 'An invalid legacy checkpoint can be repinned and synced'
    $oldScope = (Get-QOSettings).Tickets.EmailIntegration
    $null = Set-QOTicketStorageSettings -StorePath $firstStore -BackupPath (Join-Path $fixture 'other-backups')
    Assert ((Get-QOSettings).Tickets.EmailIntegration.LastSyncUtc -eq $oldScope.LastSyncUtc) 'Changing only the backup folder retains import history'
    $null = Set-QOTicketStorageSettings -StorePath $nextStore
    & $module { $script:Rows = @() }
    $reset = (Get-QOSettings).Tickets.EmailIntegration
    Assert (!$reset.LastSyncUtc -and !$reset.LastSuccessfulSyncUtc -and $reset.SyncRevision -ne $oldScope.SyncRevision) 'Switching the ticket database starts a new import checkpoint'
    $stale = Set-QOEmailSyncCheckpoint -Revision ([string]$reset.SyncRevision) -CompletedUtc ([datetime]::UtcNow) -WatermarkUtc ([datetime]::UtcNow) -StorePath $firstStore
    Assert (!$stale -and !(Get-QOSettings).Tickets.EmailIntegration.LastSyncUtc) 'A worker with a cached old ticket path cannot checkpoint another database'
    $reloaded = Sync-QOTicketsFromOutlook -ProcessedCategory ''
    Assert ($reloaded.Success -and $reloaded.Added -eq 3) 'A newly selected empty database imports historical tickets from all monitored mailboxes'
} finally {
    $env:QOT_SETTINGS_PATH = $previousSettings
    $resolved = (Resolve-Path -LiteralPath $fixture).Path
    if ([IO.Path]::GetDirectoryName($resolved) -eq [IO.Path]::GetTempPath().TrimEnd('\') -and [IO.Path]::GetFileName($resolved) -match '^qot-checkpoint-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
