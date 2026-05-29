# src\Core\Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System (NO UI CODE)

$ErrorActionPreference = "Stop"

# Import Settings (required - hard fail if missing)
Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Global -Force -ErrorAction Stop

# Import logging (optional, but log failures rather than silently swallow them)
. (Join-Path $PSScriptRoot "QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "Logging\Logging.psm1") -ImporterContext 'Core.Tickets' -Force

# Import Outlook ticket sync (optional)
try {
    $outlookMod = Join-Path $PSScriptRoot "..\Tickets\Tickets.Email.Outlook.psm1"
    if (Test-Path -LiteralPath $outlookMod) {
        Import-Module $outlookMod -Global -ErrorAction Stop
    }
} catch {
    # Outlook integration is optional
}

function Import-QOTOutlookIntegrationModule {
    $syncCmd = Get-Command Sync-QOTicketsFromOutlook -ErrorAction SilentlyContinue
    $replyCmd = Get-Command Send-QOTicketOutlookReply -ErrorAction SilentlyContinue
    if ($syncCmd -and $replyCmd) { return $true }

    $outlookMod = Join-Path $PSScriptRoot "..\Tickets\Tickets.Email.Outlook.psm1"
    if (-not (Test-Path -LiteralPath $outlookMod)) {
        return $false
    }

    try {
        Import-Module $outlookMod -Global -ErrorAction Stop
    }
    catch {
        Write-QOTicketsCoreLog ("Tickets: Outlook integration module import failed. " + $_.Exception.Message) "WARN"
    }

    $syncCmd = Get-Command Sync-QOTicketsFromOutlook -ErrorAction SilentlyContinue
    $replyCmd = Get-Command Send-QOTicketOutlookReply -ErrorAction SilentlyContinue
    return [bool]($syncCmd -and $replyCmd)
}


# =====================================================================
# Script state
# =====================================================================
$script:TicketStorePath  = $null
$script:TicketBackupPath = $null
$script:TicketStoreLockTimeoutSeconds = 5
$script:TicketBackupMinIntervalSeconds = 90
$script:TicketLastBackupUtc = [datetime]::MinValue
$script:TicketStoreCompactionThresholdBytes = 50MB
$script:TicketLargeInlineBodyLineThresholdChars = 12000
$script:TicketCompactedBodyFileMaxChars = 12000
$script:ValidTicketStatuses = @(
    "New",
    "In Progress",
    "Pending",
    "Closed"
    
)
$script:ValidTicketPriorities = @(
    "Low",
    "Medium",
    "High",
    "Critical"
)

function Write-QOTicketsCoreLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Level = "INFO"
    )
    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $Message $Level
        }
    } catch { }
}

# =====================================================================
# Helpers
# =====================================================================
function Ensure-QOSettingProperty {
    param(
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$DefaultValue
    )

    if (-not $Settings) { throw "Settings object is null." }

    if ($Settings.PSObject.Properties.Name -notcontains $Name) {
        $Settings | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue -Force
    }

    return $Settings
}

function Resolve-QOTicketsSettingsCommand {
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $cmd = $null
    try {
        $cmd = @(Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($cmd -is [System.Array]) {
            if ($cmd.Count -gt 0) { $cmd = $cmd[0] } else { $cmd = $null }
        }
    } catch { $cmd = $null }

    if (-not $cmd) {
        $settingsModulePath = Join-Path $PSScriptRoot "Settings.psm1"
        if (Test-Path -LiteralPath $settingsModulePath) {
            try {
                Import-Module $settingsModulePath -Global -Force -ErrorAction Stop
            } catch {
                Write-QOTicketsCoreLog ("Tickets: Settings module import retry failed while resolving {0}. {1}" -f $Name, $_.Exception.Message) "WARN"
            }
        }

        try {
            $cmd = @(Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($cmd -is [System.Array]) {
                if ($cmd.Count -gt 0) { $cmd = $cmd[0] } else { $cmd = $null }
            }
        } catch { $cmd = $null }
    }

    return $cmd
}

function Get-QOTicketsCoreAppDataRoot {
    $getAppDataCmd = Resolve-QOTicketsSettingsCommand -Name "Get-QOAppDataRoot"
    if ($getAppDataCmd) {
        try {
            $value = [string](& $getAppDataCmd)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        } catch { }
    }

    $candidates = @(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),
        $env:LOCALAPPDATA,
        $env:APPDATA,
        $env:USERPROFILE
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    if ($candidates.Count -gt 0) {
        return [string]$candidates[0]
    }

    return [System.IO.Path]::GetTempPath()
}

function Get-QOTicketsSettingsObject {
    $getSettingsCmd = Resolve-QOTicketsSettingsCommand -Name "Get-QOSettings"
    if ($getSettingsCmd) {
        try {
            $settings = & $getSettingsCmd
            if ($settings) { return $settings }
        } catch {
            Write-QOTicketsCoreLog ("Tickets: Get-QOSettings failed, using fallback defaults. " + $_.Exception.Message) "WARN"
        }
    }

    $newDefaultsCmd = Resolve-QOTicketsSettingsCommand -Name "New-QODefaultSettings"
    if ($newDefaultsCmd) {
        try {
            $settings = & $newDefaultsCmd -NoSave
            if ($settings) { return $settings }
        } catch { }
    }

    return [pscustomobject]@{
        TicketStorePath       = ""
        LocalTicketBackupPath = ""
        TicketsColumnLayout   = @()
    }
}

function Save-QOTicketsSettingsObject {
    param(
        [Parameter(Mandatory)]$Settings
    )

    $saveSettingsCmd = Resolve-QOTicketsSettingsCommand -Name "Save-QOSettings"
    if (-not $saveSettingsCmd) {
        Write-QOTicketsCoreLog "Tickets: Save-QOSettings unavailable; skipping settings persistence for this run." "WARN"
        return $false
    }

    try {
        $null = & $saveSettingsCmd -Settings $Settings
        return $true
    } catch {
        Write-QOTicketsCoreLog ("Tickets: Save-QOSettings failed. " + $_.Exception.Message) "WARN"
        return $false
    }
}

function New-QODefaultTicketDatabase {
    [pscustomobject]@{
        SchemaVersion = 1
        Tickets       = @()
    }
}

function New-QODefaultTicketsFile {
    param([Parameter(Mandatory)][string]$Path)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        "[]" | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

function Get-QOLatestTicketBackupPath {
    param(
        [Parameter(Mandatory)][string]$TicketPath,
        [AllowNull()][string]$BackupDirectory
    )

    $candidates = @()
    $ticketName = Split-Path -Leaf $TicketPath
    $backupPattern = "{0}.bak_*" -f $ticketName

    if (-not [string]::IsNullOrWhiteSpace($BackupDirectory)) {
        try {
            if (Test-Path -LiteralPath $BackupDirectory) {
                $candidates += Get-ChildItem -LiteralPath $BackupDirectory -Filter $backupPattern -File -ErrorAction SilentlyContinue
            }
        } catch { }
    }

    $ticketDir = Split-Path -Parent $TicketPath
    if (-not [string]::IsNullOrWhiteSpace($ticketDir)) {
        try {
            if (Test-Path -LiteralPath $ticketDir) {
                $candidates += Get-ChildItem -LiteralPath $ticketDir -Filter $backupPattern -File -ErrorAction SilentlyContinue
            }
        } catch { }
    }

    if (-not $candidates -or $candidates.Count -eq 0) {
        return $null
    }

    $latest = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        return [string]$latest.FullName
    }

    return $null
}

function Normalize-QOTicketDatabase {
    param([Parameter(Mandatory)]$Database)

    if ($null -eq $Database) {
        $Database = New-QODefaultTicketDatabase
    }

    if (($null -ne $Database) -and (-not ($Database.PSObject.Properties.Name -contains "Tickets"))) {
        $ticketList = @()
        if ($Database -is [System.Array]) {
            $ticketList = @($Database)
        } elseif ($Database -is [System.Collections.IEnumerable] -and -not ($Database -is [string])) {
            $ticketList = @($Database)
        } else {
            $ticketList = @($Database)
        }

        $Database = [pscustomobject]@{
            SchemaVersion = 1
            Tickets       = $ticketList
        }
    }

    if (-not ($Database.PSObject.Properties.Name -contains "Tickets")) {
        $Database | Add-Member -NotePropertyName Tickets -NotePropertyValue @() -Force
    }

    if ($null -eq $Database.Tickets) { $Database.Tickets = @() }
    $Database.Tickets = @($Database.Tickets)
    foreach ($ticket in $Database.Tickets) {
        if ($null -eq $ticket) { continue }

        $nowStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

        if (-not ($ticket.PSObject.Properties.Name -contains "DeletedAt")) {
            $ticket | Add-Member -NotePropertyName DeletedAt -NotePropertyValue $null -Force
        }

        $isDeleted = $false
        if ($ticket.PSObject.Properties.Name -contains "IsDeleted") {
            try { $isDeleted = [bool]$ticket.IsDeleted } catch { $isDeleted = $false }
        } else {
            $isDeleted = ([bool]$ticket.DeletedAt -or ($ticket.PSObject.Properties.Name -contains "Folder" -and $ticket.Folder -eq "Deleted"))
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "Folder")) {
            $folderValue = if ($isDeleted) { "Deleted" } else { "Active" }
            $ticket | Add-Member -NotePropertyName Folder -NotePropertyValue $folderValue -Force
                }

        if ($isDeleted -and $ticket.Folder -ne "Deleted") {
            $ticket.Folder = "Deleted"
        } elseif (-not $isDeleted -and $ticket.Folder -eq "Deleted") {
            $ticket.Folder = "Active"
        }

        if ($isDeleted -and (-not $ticket.DeletedAt)) {
            $ticket.DeletedAt = $nowStamp
        } elseif (-not $isDeleted -and $ticket.DeletedAt) {
            $ticket.DeletedAt = $null
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "IsDeleted")) {
            $ticket | Add-Member -NotePropertyName IsDeleted -NotePropertyValue $isDeleted -Force
        } else {
            $ticket.IsDeleted = $isDeleted
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "Status")) {
            $ticket | Add-Member -NotePropertyName Status -NotePropertyValue "New" -Force
        }

        if ([string]::IsNullOrWhiteSpace([string]$ticket.Status)) {
            $ticket.Status = "New"
        }

        if ($ticket.Status -eq "Open") {
            $ticket.Status = "In Progress"
        }

        if ($ticket.Status -eq "Waiting on User") {
            $ticket.Status = "Pending"
        }

        if ($ticket.Status -eq "No Longer Required") {
            $ticket.Status = "Closed"
        }

        if ($ticket.Status -eq "Completed") {
            $ticket.Status = "Closed"
        }

        if ($script:ValidTicketStatuses -notcontains $ticket.Status) {
            $ticket.Status = "New"
        }
        
        if (-not ($ticket.PSObject.Properties.Name -contains "Title")) {
            $fallbackTitle = ""
            try {
                if (($ticket.PSObject.Properties.Name -contains "TicketName") -and -not [string]::IsNullOrWhiteSpace([string]$ticket.TicketName)) {
                    $fallbackTitle = [string]$ticket.TicketName
                } elseif ($ticket.PSObject.Properties.Name -contains "Subject") {
                    $fallbackTitle = [string]$ticket.Subject
                }
            } catch { $fallbackTitle = "" }
            $ticket | Add-Member -NotePropertyName Title -NotePropertyValue $fallbackTitle -Force
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "TicketName")) {
            $fallbackTicketName = ""
            try {
                if ($ticket.PSObject.Properties.Name -contains "Title") {
                    $fallbackTicketName = [string]$ticket.Title
                } elseif ($ticket.PSObject.Properties.Name -contains "Subject") {
                    $fallbackTicketName = [string]$ticket.Subject
                }
            } catch { $fallbackTicketName = "" }
            $ticket | Add-Member -NotePropertyName TicketName -NotePropertyValue $fallbackTicketName -Force
        }

        if ([string]::IsNullOrWhiteSpace([string]$ticket.TicketName)) {
            $ticket.TicketName = $ticket.Title
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "Subject")) {
            $ticket | Add-Member -NotePropertyName Subject -NotePropertyValue $ticket.Title -Force
        }

        # Keep key text fields bounded so malformed/encoded email subjects cannot bloat the store.
        try {
            $normalizedTitle = Normalize-QOTicketTextField -Value ([string]$ticket.Title) -MaxLength 220
            if ([string]::IsNullOrWhiteSpace($normalizedTitle)) { $normalizedTitle = "(No subject)" }
            $ticket.Title = $normalizedTitle
        } catch { }
        try {
            $normalizedTicketName = Normalize-QOTicketTextField -Value ([string]$ticket.TicketName) -MaxLength 220
            if ([string]::IsNullOrWhiteSpace($normalizedTicketName)) { $normalizedTicketName = [string]$ticket.Title }
            $ticket.TicketName = $normalizedTicketName
        } catch { }
        try {
            $normalizedSubject = Normalize-QOTicketTextField -Value ([string]$ticket.Subject) -MaxLength 320
            if ([string]::IsNullOrWhiteSpace($normalizedSubject)) { $normalizedSubject = [string]$ticket.Title }
            $ticket.Subject = $normalizedSubject
        } catch { }

        if (-not ($ticket.PSObject.Properties.Name -contains "Priority")) {
            $ticket | Add-Member -NotePropertyName Priority -NotePropertyValue "Medium" -Force
        }
        $prioritySubject = ""
        try {
            if ($ticket.PSObject.Properties.Name -contains "Subject") {
                $prioritySubject = [string]$ticket.Subject
            } elseif ($ticket.PSObject.Properties.Name -contains "Title") {
                $prioritySubject = [string]$ticket.Title
            }
        } catch { }
        $ticket.Priority = Normalize-QOTicketPriority -Priority ([string]$ticket.Priority) -Subject $prioritySubject -Status ([string]$ticket.Status)

        if (-not ($ticket.PSObject.Properties.Name -contains "AssignedTo")) {
            $ticket | Add-Member -NotePropertyName AssignedTo -NotePropertyValue "Unassigned" -Force
        }
        $ticket.AssignedTo = Normalize-QOTicketAssignee -AssignedTo ([string]$ticket.AssignedTo)

        if (-not ($ticket.PSObject.Properties.Name -contains "CreatedAt")) {
            if ($ticket.PSObject.Properties.Name -contains "Created") {
                $ticket | Add-Member -NotePropertyName CreatedAt -NotePropertyValue $ticket.Created -Force
            } else {
                $ticket | Add-Member -NotePropertyName CreatedAt -NotePropertyValue (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Force
            }
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "UpdatedAt")) {
            $ticket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue $ticket.CreatedAt -Force
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "EmailFrom")) {
            $ticket | Add-Member -NotePropertyName EmailFrom -NotePropertyValue "" -Force
        }
        try {
            $ticket.EmailFrom = Normalize-QOTicketTextField -Value ([string]$ticket.EmailFrom) -MaxLength 320
        } catch { }

        if (-not ($ticket.PSObject.Properties.Name -contains "EmailTo")) {
            $ticket | Add-Member -NotePropertyName EmailTo -NotePropertyValue "" -Force
        }
        try {
            $ticket.EmailTo = Normalize-QOTicketTextField -Value ([string]$ticket.EmailTo) -MaxLength 320
        } catch { }

        if (-not ($ticket.PSObject.Properties.Name -contains "SourceMailbox")) {
            $ticket | Add-Member -NotePropertyName SourceMailbox -NotePropertyValue "" -Force
        }
        try {
            $ticket.SourceMailbox = Normalize-QOTicketTextField -Value ([string]$ticket.SourceMailbox) -MaxLength 320
        } catch { }

        if (-not ($ticket.PSObject.Properties.Name -contains "SenderName")) {
            $ticket | Add-Member -NotePropertyName SenderName -NotePropertyValue "" -Force
        }
        try {
            $ticket.SenderName = Normalize-QOTicketTextField -Value ([string]$ticket.SenderName) -MaxLength 240
        } catch { }

        if (-not ($ticket.PSObject.Properties.Name -contains "SenderEmail")) {
            $ticket | Add-Member -NotePropertyName SenderEmail -NotePropertyValue "" -Force
        }
        try {
            $ticket.SenderEmail = Normalize-QOTicketTextField -Value ([string]$ticket.SenderEmail) -MaxLength 320
        } catch { }

        try {
            if ([string]::IsNullOrWhiteSpace([string]$ticket.SenderEmail)) {
                foreach ($emailProp in @("From", "CustomerEmail", "ContactEmail", "RequesterEmail", "RequestEmail", "EmailAddress")) {
                    if (-not ($ticket.PSObject.Properties.Name -contains $emailProp)) { continue }
                    $emailCandidate = [string]($ticket.$emailProp + "")
                    if ([string]::IsNullOrWhiteSpace($emailCandidate)) { continue }
                    $emailMatch = [regex]::Match($emailCandidate, '(?i)([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})')
                    if ($emailMatch.Success) {
                        $ticket.SenderEmail = Normalize-QOTicketTextField -Value ([string]$emailMatch.Groups[1].Value) -MaxLength 320
                        break
                    }
                }
            }
        } catch { }
        try {
            if ([string]::IsNullOrWhiteSpace([string]$ticket.SenderName) -and -not [string]::IsNullOrWhiteSpace([string]$ticket.EmailFrom)) {
                $fromMatch = [regex]::Match([string]$ticket.EmailFrom, '^\s*"?([^"<]+?)"?\s*<\s*[^>]+\s*>\s*$')
                if ($fromMatch.Success) {
                    $ticket.SenderName = Normalize-QOTicketTextField -Value ([string]$fromMatch.Groups[1].Value) -MaxLength 240
                }
            }
        } catch { }
        try {
            if ([string]::IsNullOrWhiteSpace([string]$ticket.EmailFrom)) {
                if ((-not [string]::IsNullOrWhiteSpace([string]$ticket.SenderName)) -and (-not [string]::IsNullOrWhiteSpace([string]$ticket.SenderEmail))) {
                    $ticket.EmailFrom = Normalize-QOTicketTextField -Value ("{0} <{1}>" -f [string]$ticket.SenderName, [string]$ticket.SenderEmail) -MaxLength 320
                } elseif (-not [string]::IsNullOrWhiteSpace([string]$ticket.SenderEmail)) {
                    $ticket.EmailFrom = Normalize-QOTicketTextField -Value ([string]$ticket.SenderEmail) -MaxLength 320
                }
            }
        } catch { }

        if (-not ($ticket.PSObject.Properties.Name -contains "EmailBodyPath")) {
            $ticket | Add-Member -NotePropertyName EmailBodyPath -NotePropertyValue "" -Force
        }
        if (-not ($ticket.PSObject.Properties.Name -contains "EmailBodyPreview")) {
            $ticket | Add-Member -NotePropertyName EmailBodyPreview -NotePropertyValue "" -Force
        }
        try {
            if ([string]::IsNullOrWhiteSpace([string]$ticket.EmailBodyPath)) {
                foreach ($legacyPathProp in @("BodyPath", "HtmlBodyPath", "TextBodyPath", "PreviewPath")) {
                    if (-not ($ticket.PSObject.Properties.Name -contains $legacyPathProp)) { continue }
                    $legacyPathValue = ([string]($ticket.$legacyPathProp + "")).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($legacyPathValue)) {
                        $ticket.EmailBodyPath = $legacyPathValue
                        break
                    }
                }
            }
        } catch { }
        try {
            if ([string]::IsNullOrWhiteSpace([string]$ticket.EmailBodyPreview)) {
                foreach ($legacyPreviewProp in @("BodyPreview", "Preview", "Body", "EmailBody", "TextBody", "HtmlBody")) {
                    if (-not ($ticket.PSObject.Properties.Name -contains $legacyPreviewProp)) { continue }
                    $legacyPreviewValue = [string]($ticket.$legacyPreviewProp + "")
                    if ([string]::IsNullOrWhiteSpace($legacyPreviewValue)) { continue }
                    $ticket.EmailBodyPreview = Get-QOTicketBodyPreview -Body $legacyPreviewValue -MaxChars 600
                    if (-not [string]::IsNullOrWhiteSpace([string]$ticket.EmailBodyPreview)) { break }
                }
            }
        } catch { }

        if ($ticket.PSObject.Properties.Name -contains "EmailBodyPreview") {
            try { $ticket.EmailBodyPreview = Get-QOTicketBodyPreview -Body ([string]$ticket.EmailBodyPreview) -MaxChars 600 } catch { }
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "Replies")) {
            $ticket | Add-Member -NotePropertyName Replies -NotePropertyValue @() -Force
        }
        if ($null -eq $ticket.Replies) {
            $ticket.Replies = @()
        } else {
            $ticket.Replies = @($ticket.Replies)
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "IncomingMessages")) {
            $ticket | Add-Member -NotePropertyName IncomingMessages -NotePropertyValue @() -Force
        }
        if ($null -eq $ticket.IncomingMessages) {
            $ticket.IncomingMessages = @()
        } else {
            $ticket.IncomingMessages = @($ticket.IncomingMessages)
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "Notes")) {
            $ticket | Add-Member -NotePropertyName Notes -NotePropertyValue @() -Force
        }
        if ($null -eq $ticket.Notes) {
            $ticket.Notes = @()
        } else {
            $ticket.Notes = @($ticket.Notes)
        }

        if (-not ($ticket.PSObject.Properties.Name -contains "PendingReplies")) {
            $ticket | Add-Member -NotePropertyName PendingReplies -NotePropertyValue @() -Force
        }
        if ($null -eq $ticket.PendingReplies) {
            $ticket.PendingReplies = @()
        } else {
            $ticket.PendingReplies = @($ticket.PendingReplies)
        }

        foreach ($collectionName in @("Messages", "History", "Conversation", "SentReplies", "InternalNotes", "SystemEvents", "Events", "Timeline", "Activity", "AuditTrail")) {
            if (-not ($ticket.PSObject.Properties.Name -contains $collectionName)) {
                $ticket | Add-Member -NotePropertyName $collectionName -NotePropertyValue @() -Force
            }
            try {
                if ($null -eq $ticket.$collectionName) {
                    $ticket.$collectionName = @()
                } else {
                    $ticket.$collectionName = @($ticket.$collectionName)
                }
            } catch {
                try { $ticket | Add-Member -NotePropertyName $collectionName -NotePropertyValue @() -Force } catch { }
            }
        }

        try {
            $normalizedReplies = @(Merge-QOTTicketActivityEntries -PrimaryEntries @($ticket.Replies) -SecondaryEntries @($ticket.SentReplies))
            foreach ($replyEntry in @($normalizedReplies)) {
                if (-not $replyEntry) { continue }
                try {
                    if (-not ($replyEntry.PSObject.Properties.Name -contains "Type") -or [string]::IsNullOrWhiteSpace([string]$replyEntry.Type)) {
                        $replyEntry | Add-Member -NotePropertyName Type -NotePropertyValue "TechnicianReply" -Force
                    }
                } catch { }
                try {
                    if (-not ($replyEntry.PSObject.Properties.Name -contains "EntryType") -or [string]::IsNullOrWhiteSpace([string]$replyEntry.EntryType)) {
                        $replyEntry | Add-Member -NotePropertyName EntryType -NotePropertyValue "TechnicianReply" -Force
                    }
                } catch { }
            }
            $ticket.Replies = @($normalizedReplies)
            $ticket.SentReplies = @()
        } catch { }

        try {
            $normalizedNotes = @(Merge-QOTTicketActivityEntries -PrimaryEntries @($ticket.Notes) -SecondaryEntries @($ticket.InternalNotes))
            foreach ($noteEntry in @($normalizedNotes)) {
                if (-not $noteEntry) { continue }
                try {
                    $existingNoteId = ""
                    foreach ($noteIdProp in @("NoteId", "ClientNoteId", "Id")) {
                        if ([string]::IsNullOrWhiteSpace($existingNoteId) -and $noteEntry.PSObject.Properties.Name -contains $noteIdProp) {
                            $existingNoteId = ([string]($noteEntry.$noteIdProp + "")).Trim()
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($existingNoteId)) {
                        $fingerprintValue = [string](Get-QOTTicketActivityEntryFingerprint -Entry $noteEntry)
                        if ([string]::IsNullOrWhiteSpace($fingerprintValue)) { $fingerprintValue = [string]($noteEntry | ConvertTo-Json -Depth 8 -Compress) }
                        $sha = [System.Security.Cryptography.SHA256]::Create()
                        try {
                            $bytes = [System.Text.Encoding]::UTF8.GetBytes($fingerprintValue)
                            $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
                            if ($hash.Length -gt 24) { $hash = $hash.Substring(0, 24) }
                            $noteEntry | Add-Member -NotePropertyName NoteId -NotePropertyValue ("legacy-" + $hash) -Force
                        } finally {
                            try { $sha.Dispose() } catch { }
                        }
                    }
                } catch { }
                try {
                    if (-not ($noteEntry.PSObject.Properties.Name -contains "Type") -or [string]::IsNullOrWhiteSpace([string]$noteEntry.Type)) {
                        $noteEntry | Add-Member -NotePropertyName Type -NotePropertyValue "InternalNote" -Force
                    }
                } catch { }
                try {
                    if (-not ($noteEntry.PSObject.Properties.Name -contains "EntryType") -or [string]::IsNullOrWhiteSpace([string]$noteEntry.EntryType)) {
                        $noteEntry | Add-Member -NotePropertyName EntryType -NotePropertyValue "InternalNote" -Force
                    }
                } catch { }
            }
            $ticket.Notes = @($normalizedNotes)
            $ticket.InternalNotes = @()
        } catch { }

        foreach ($pendingReply in @($ticket.PendingReplies)) {
            if (-not $pendingReply) { continue }

            $draftId = ""
            try { if ($pendingReply.PSObject.Properties.Name -contains "DraftId") { $draftId = ([string]($pendingReply.DraftId + "")).Trim() } } catch { $draftId = "" }
            if ([string]::IsNullOrWhiteSpace($draftId)) {
                try { $draftId = [guid]::NewGuid().ToString("N") } catch { $draftId = ([string](Get-Date -Format "yyyyMMddHHmmssfff")) }
                try { $pendingReply | Add-Member -NotePropertyName DraftId -NotePropertyValue $draftId -Force } catch { }
            }
            try {
                if (-not ($pendingReply.PSObject.Properties.Name -contains "ReplyId") -or [string]::IsNullOrWhiteSpace([string]$pendingReply.ReplyId)) {
                    $pendingReply | Add-Member -NotePropertyName ReplyId -NotePropertyValue $draftId -Force
                }
            } catch { }
            try {
                $pendingState = "Queued"
                if ($pendingReply.PSObject.Properties.Name -contains "SendState") {
                    $pendingState = Normalize-QOTTicketPendingReplyState -SendState ([string]$pendingReply.SendState)
                }
                $pendingReply.SendState = $pendingState
            } catch { }
            try {
                if (-not ($pendingReply.PSObject.Properties.Name -contains "FailureNote")) {
                    $pendingReply | Add-Member -NotePropertyName FailureNote -NotePropertyValue "" -Force
                } else {
                    $pendingReply.FailureNote = ([string]($pendingReply.FailureNote + "")).Trim()
                }
            } catch { }
            try {
                $lastErrorValue = ""
                if ($pendingReply.PSObject.Properties.Name -contains "LastError") {
                    $lastErrorValue = ([string]($pendingReply.LastError + "")).Trim()
                }
                if ([string]::IsNullOrWhiteSpace($lastErrorValue)) {
                    $lastErrorValue = [string]($pendingReply.FailureNote + "")
                }
                $pendingReply | Add-Member -NotePropertyName LastError -NotePropertyValue $lastErrorValue -Force
            } catch { }
            try {
                if (-not ($pendingReply.PSObject.Properties.Name -contains "SentAt")) {
                    $pendingReply | Add-Member -NotePropertyName SentAt -NotePropertyValue "" -Force
                } elseif ([string]::IsNullOrWhiteSpace([string]$pendingReply.SentAt) -and [string]::Equals([string]$pendingReply.SendState, "Sent", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $fallbackSentAt = ""
                    foreach ($dateProp in @("LastAttemptAt", "CreatedAt")) {
                        try {
                            if ($pendingReply.PSObject.Properties.Name -contains $dateProp) {
                                $fallbackSentAt = ([string]($pendingReply.$dateProp + "")).Trim()
                                if (-not [string]::IsNullOrWhiteSpace($fallbackSentAt)) { break }
                            }
                        } catch { }
                    }
                    $pendingReply.SentAt = $fallbackSentAt
                }
            } catch { }
        }
    }

    return $Database
}

function Get-QOTTicketActivityEntryFingerprint {
    param(
        [AllowNull()]$Entry
    )

    if ($null -eq $Entry) { return "" }
    if ($Entry -is [string]) { return ("string|" + ([string]$Entry).Trim().ToLowerInvariant()) }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($propertyName in @("ReplyId", "DraftId", "Type", "EntryType", "Kind", "Subject", "Title", "Body", "Text", "Message", "Content", "Preview", "CreatedAt", "SentAt", "ReceivedAt", "UpdatedAt", "Author", "CreatedBy", "User", "Technician", "To", "FailureNote")) {
        try {
            if ($Entry.PSObject.Properties.Name -contains $propertyName) {
                $value = ([string]($Entry.$propertyName + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $parts.Add(($propertyName.ToLowerInvariant() + "=" + $value.ToLowerInvariant())) | Out-Null
                }
            }
        } catch { }
    }

    if ($parts.Count -eq 0) {
        try {
            return ("json|" + (($Entry | ConvertTo-Json -Depth 6 -Compress) + ""))
        } catch {
            return ("type|" + [string]$Entry.GetType().FullName)
        }
    }

    return ($parts -join "|")
}

function Merge-QOTTicketActivityEntries {
    param(
        [AllowNull()][object[]]$PrimaryEntries,
        [AllowNull()][object[]]$SecondaryEntries
    )

    $results = New-Object System.Collections.Generic.List[object]
    $seenFingerprints = New-Object System.Collections.Generic.HashSet[string]

    foreach ($entry in @($PrimaryEntries) + @($SecondaryEntries)) {
        if ($null -eq $entry) { continue }
        $fingerprint = ""
        try { $fingerprint = [string](Get-QOTTicketActivityEntryFingerprint -Entry $entry) } catch { $fingerprint = "" }
        if (-not [string]::IsNullOrWhiteSpace($fingerprint)) {
            if (-not $seenFingerprints.Add($fingerprint)) { continue }
        }
        $results.Add($entry) | Out-Null
    }

    try { return @($results.ToArray()) } catch { return @() }
}

function Normalize-QOTicketTextField {
    param(
        [AllowNull()][string]$Value,
        [int]$MaxLength = 240
    )

    $text = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    if ($MaxLength -lt 32) { $MaxLength = 32 }

    # Collapse excessive whitespace/newlines in heading-style fields.
    $text = ($text -replace '\s+', ' ').Trim()
    if ($text.Length -gt $MaxLength) {
        $text = $text.Substring(0, $MaxLength).Trim()
    }
    return $text
}

function Normalize-QOTicketPriority {
    param(
        [AllowNull()][string]$Priority,
        [AllowNull()][string]$Subject,
        [AllowNull()][string]$Status
    )

    $priorityValue = ([string]($Priority + "")).Trim().ToLowerInvariant()
    switch ($priorityValue) {
        "low"      { return "Low" }
        "medium"   { return "Medium" }
        "med"      { return "Medium" }
        "normal"   { return "Medium" }
        "high"     { return "High" }
        "urgent"   { return "High" }
        "critical" { return "Critical" }
        "sev1"     { return "Critical" }
        "sev2"     { return "High" }
        "sev3"     { return "Medium" }
        "sev4"     { return "Low" }
    }

    $subjectValue = ([string]($Subject + "")).Trim().ToLowerInvariant()
    if ($subjectValue) {
        if ($subjectValue -match '\b(critical|sev[\s\-]?1|p1|outage|system down|major incident)\b') { return "Critical" }
        if ($subjectValue -match '\b(high|urgent|asap|immediately|sev[\s\-]?2|p2)\b') { return "High" }
        if ($subjectValue -match '\b(low|minor|info|question|sev[\s\-]?4|p4)\b') { return "Low" }
    }

    $statusValue = ([string]($Status + "")).Trim().ToLowerInvariant()
    if ($statusValue -eq "closed") { return "Low" }

    return "Medium"
}

function Normalize-QOTicketAssignee {
    param(
        [AllowNull()][string]$AssignedTo
    )

    $assigneeValue = ([string]($AssignedTo + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($assigneeValue)) { return "Unassigned" }
    if ($assigneeValue -match '^(?i)(unassigned|none|n/?a|null)$') { return "Unassigned" }
    return $assigneeValue
}

function Get-QOTicketMergeTimestamp {
    param([AllowNull()]$Ticket)

    if ($null -eq $Ticket) { return [datetime]::MinValue }

    $rawValue = $null
    try {
        if ($Ticket.PSObject.Properties.Name -contains "UpdatedAt") {
            $rawValue = [string]$Ticket.UpdatedAt
        }
    } catch { }

    if ([string]::IsNullOrWhiteSpace([string]$rawValue)) {
        try {
            if ($Ticket.PSObject.Properties.Name -contains "CreatedAt") {
                $rawValue = [string]$Ticket.CreatedAt
            }
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace([string]$rawValue)) {
        return [datetime]::MinValue
    }

    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact(
            $rawValue,
            "yyyy-MM-dd HH:mm:ss",
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeLocal,
            [ref]$parsed
        )) {
        return $parsed
    }

    if ([datetime]::TryParse($rawValue, [ref]$parsed)) {
        return $parsed
    }

    return [datetime]::MinValue
}

function Get-QOTicketStoreMutexName {
    param([Parameter(Mandatory)][string]$StorePath)

    $normalizedPath = $StorePath
    try { $normalizedPath = [System.IO.Path]::GetFullPath([string]$StorePath) } catch { }
    $normalizedPath = ([string]$normalizedPath).Trim().ToLowerInvariant()

    $hashHex = ""
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedPath)
        $hashBytes = $sha1.ComputeHash($bytes)
        $hashHex = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
    } finally {
        if ($sha1) { $sha1.Dispose() }
    }

    return ("Local\QOTicketsStore_{0}" -f $hashHex)
}

function Get-QOTicketBodiesDirectory {
    Initialize-QOTicketStorage

    $ticketDir = Split-Path -Parent $script:TicketStorePath
    $bodiesDir = Join-Path $ticketDir "Bodies"
    if (-not (Test-Path -LiteralPath $bodiesDir)) {
        New-Item -ItemType Directory -Path $bodiesDir -Force | Out-Null
    }
    return $bodiesDir
}

function New-QOTicketBodyFilePath {
    param(
        [AllowNull()][string]$TicketId,
        [AllowNull()][string]$Suffix
    )

    $rawId = ([string]($TicketId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($rawId)) {
        $rawId = [guid]::NewGuid().ToString()
    }

    $safeId = ($rawId -replace '[^a-zA-Z0-9\-_]', '_')
    if ([string]::IsNullOrWhiteSpace($safeId)) {
        $safeId = [guid]::NewGuid().ToString("N")
    }

    $safeSuffix = ([string]($Suffix + "")).Trim()
    if (-not [string]::IsNullOrWhiteSpace($safeSuffix)) {
        $safeSuffix = ($safeSuffix -replace '[^a-zA-Z0-9\-_]', '_')
        if (-not [string]::IsNullOrWhiteSpace($safeSuffix)) {
            $safeId = ($safeId + "-" + $safeSuffix)
        }
    }

    return (Join-Path (Get-QOTicketBodiesDirectory) ($safeId + ".txt"))
}

function Resolve-QOTicketBodyFilePath {
    param(
        [AllowNull()][string]$Path
    )

    $pathValue = ([string]($Path + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($pathValue)) { return "" }

    try {
        if ([System.IO.Path]::IsPathRooted($pathValue)) {
            return $pathValue
        }
    } catch { }

    try {
        $storePath = [string]$script:TicketStorePath
        if (-not [string]::IsNullOrWhiteSpace($storePath)) {
            return (Join-Path (Split-Path -Parent $storePath) $pathValue)
        }
    } catch { }

    return $pathValue
}

function ConvertTo-QOTicketJsonStringLiteral {
    param(
        [AllowNull()][string]$Value
    )

    $text = [string]($Value + "")
    if ([string]::IsNullOrEmpty($text)) { return "" }

    $builder = New-Object System.Text.StringBuilder
    foreach ($ch in $text.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -eq 34) {
            [void]$builder.Append('\"')
        } elseif ($code -eq 92) {
            [void]$builder.Append('\\')
        } elseif ($code -eq 8) {
            [void]$builder.Append('\b')
        } elseif ($code -eq 9) {
            [void]$builder.Append('\t')
        } elseif ($code -eq 10) {
            [void]$builder.Append('\n')
        } elseif ($code -eq 12) {
            [void]$builder.Append('\f')
        } elseif ($code -eq 13) {
            [void]$builder.Append('\r')
        } elseif ($code -lt 32) {
            [void]$builder.Append(("\u{0:x4}" -f $code))
        } else {
            [void]$builder.Append($ch)
        }
    }

    return $builder.ToString()
}

function Get-QOTicketDecodedJsonStringPrefix {
    param(
        [Parameter(Mandatory)][string]$Line,
        [int]$MaxChars = 600
    )

    if ($MaxChars -lt 1) { $MaxChars = 1 }

    $colonIndex = $Line.IndexOf(":")
    if ($colonIndex -lt 0) {
        return [pscustomobject]@{ Text = ""; WasTruncated = $false }
    }

    $startQuote = $Line.IndexOf('"', $colonIndex + 1)
    if ($startQuote -lt 0) {
        return [pscustomobject]@{ Text = ""; WasTruncated = $false }
    }

    $builder = New-Object System.Text.StringBuilder
    $closed = $false
    $i = $startQuote + 1
    while ($i -lt $Line.Length -and $builder.Length -lt $MaxChars) {
        $ch = $Line[$i]
        $code = [int][char]$ch

        if ($code -eq 34) {
            $closed = $true
            break
        }

        if ($code -eq 92 -and ($i + 1) -lt $Line.Length) {
            $i++
            $esc = $Line[$i]
            $escCode = [int][char]$esc
            switch ($escCode) {
                34 { [void]$builder.Append('"') }
                92 { [void]$builder.Append('\') }
                47 { [void]$builder.Append('/') }
                98 { [void]$builder.Append([char]8) }
                102 { [void]$builder.Append([char]12) }
                110 { [void]$builder.Append("`n") }
                114 { [void]$builder.Append("`r") }
                116 { [void]$builder.Append("`t") }
                117 {
                    if (($i + 4) -lt $Line.Length) {
                        $hex = $Line.Substring($i + 1, 4)
                        try {
                            [void]$builder.Append([char]([Convert]::ToInt32($hex, 16)))
                            $i += 4
                        } catch {
                            [void]$builder.Append($esc)
                        }
                    } else {
                        [void]$builder.Append($esc)
                    }
                }
                default { [void]$builder.Append($esc) }
            }
        } else {
            [void]$builder.Append($ch)
        }

        $i++
    }

    $wasTruncated = (-not $closed)
    return [pscustomobject]@{
        Text         = $builder.ToString()
        WasTruncated = $wasTruncated
    }
}

function Compress-QOTicketStoreLargeBodyLines {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][string]$BackupDirectory,
        [int]$LineLengthThresholdChars = $script:TicketLargeInlineBodyLineThresholdChars,
        [int]$BodyFileMaxChars = $script:TicketCompactedBodyFileMaxChars,
        [switch]$Quiet
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if ($LineLengthThresholdChars -lt 1024) { $LineLengthThresholdChars = 1024 }
    if ($BodyFileMaxChars -lt 600) { $BodyFileMaxChars = 600 }

    $storeDir = Split-Path -Parent $Path
    $bodiesDir = Join-Path $storeDir "Bodies"
    $leaf = Split-Path -Leaf $Path
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $tempPath = Join-Path $storeDir ("{0}.compact.tmp.{1}.{2}" -f $leaf, $PID, ([guid]::NewGuid().ToString("N")))
    $backupRoot = ([string]($BackupDirectory + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = $storeDir }
    $backupPath = Join-Path $backupRoot ("{0}.compact-backup-{1}" -f $leaf, $timestamp)

    $reader = $null
    $writer = $null
    $changedCount = 0
    $lineNo = 0
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    try {
        if (-not (Test-Path -LiteralPath $bodiesDir)) {
            New-Item -ItemType Directory -Path $bodiesDir -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $backupRoot)) {
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        }

        $reader = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::UTF8, $true, 1048576)
        $writer = New-Object System.IO.StreamWriter($tempPath, $false, $utf8NoBom, 1048576)

        while (($line = $reader.ReadLine()) -ne $null) {
            $lineNo++
            $trimmed = $line.TrimStart()
            $isLargeInlineBody = (
                $line.Length -gt $LineLengthThresholdChars -and
                $trimmed.StartsWith('"Body"', [System.StringComparison]::Ordinal)
            )

            if (-not $isLargeInlineBody) {
                $writer.WriteLine($line)
                continue
            }

            $indentLength = $line.Length - $trimmed.Length
            $indent = ""
            if ($indentLength -gt 0) { $indent = $line.Substring(0, $indentLength) }
            $hadTrailingComma = $line.TrimEnd().EndsWith(",", [System.StringComparison]::Ordinal)
            $bodyPrefix = Get-QOTicketDecodedJsonStringPrefix -Line $line -MaxChars $BodyFileMaxChars
            $bodyText = [string]$bodyPrefix.Text
            if ($bodyPrefix.WasTruncated -or $line.Length -gt $BodyFileMaxChars) {
                $bodyText = $bodyText.TrimEnd() + "`r`n`r`n[Body compacted because it was too large for the ticket store. Full original JSON is preserved in backup: $backupPath]"
            }

            $bodyFileName = "legacy-body-line-{0}.txt" -f $lineNo
            $bodyPath = Join-Path $bodiesDir $bodyFileName
            [System.IO.File]::WriteAllText($bodyPath, $bodyText, $utf8NoBom)

            $previewText = Get-QOTicketBodyPreview -Body $bodyText -MaxChars 600
            $encodedBodyPath = ConvertTo-QOTicketJsonStringLiteral -Value $bodyPath
            $encodedPreview = ConvertTo-QOTicketJsonStringLiteral -Value $previewText
            $previewComma = if ($hadTrailingComma) { "," } else { "" }

            $writer.WriteLine($indent + '"Body":  "",')
            $writer.WriteLine($indent + ('"BodyPath":  "{0}",' -f $encodedBodyPath))
            $writer.WriteLine($indent + ('"BodyPreview":  "{0}"{1}' -f $encodedPreview, $previewComma))
            $changedCount++
        }
    }
    catch {
        Write-QOTicketsCoreLog ("Tickets: Large body compaction failed. Error: {0}" -f $_.Exception.Message) "WARN"
        return $false
    }
    finally {
        if ($reader) { try { $reader.Dispose() } catch { } }
        if ($writer) { try { $writer.Dispose() } catch { } }
    }

    if ($changedCount -le 0) {
        try { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue } catch { }
        return $false
    }

    try {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction Stop
        try {
            [System.IO.File]::Replace($tempPath, $Path, $null, $true)
        } catch {
            [System.IO.File]::Copy($tempPath, $Path, $true)
            [System.IO.File]::Delete($tempPath)
        }
        if (-not $Quiet) {
            Write-QOTicketsCoreLog ("Tickets: Compacted {0} oversized inline body entries. Backup={1}" -f $changedCount, $backupPath)
        }
        return $true
    }
    catch {
        Write-QOTicketsCoreLog ("Tickets: Failed to replace ticket store after compaction. Error: {0}" -f $_.Exception.Message) "ERROR"
        return $false
    }
    finally {
        try { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function Read-QOTicketStoreJsonText {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Get-QOTicketStableBodySuffix {
    param(
        [AllowNull()][string]$TicketId,
        [Parameter(Mandatory)][string]$Kind,
        [int]$Index,
        [AllowNull()]$Entry
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add([string]$TicketId) | Out-Null
    $parts.Add([string]$Kind) | Out-Null
    $parts.Add([string]$Index) | Out-Null

    foreach ($propName in @("SourceMessageId", "EmailMessageId", "SentEntryId", "ConversationId", "CreatedAt", "Subject")) {
        try {
            if ($Entry -and ($Entry.PSObject.Properties.Name -contains $propName)) {
                $value = ([string]($Entry.$propName + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $parts.Add($value) | Out-Null
                }
            }
        } catch { }
    }

    $key = ($parts -join "|")
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($key)
        $hashBytes = $sha1.ComputeHash($bytes)
        $hashHex = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
    } finally {
        if ($sha1) { $sha1.Dispose() }
    }

    return ("{0}-{1}" -f $Kind, $hashHex.Substring(0, 16))
}

function Optimize-QOTicketInlineTextBodyStorage {
    param(
        [AllowNull()]$Owner,
        [AllowNull()][string]$TicketId,
        [string]$BodyProperty = "Body",
        [string]$PathProperty = "BodyPath",
        [string]$PreviewProperty = "BodyPreview",
        [AllowNull()][string]$PathSuffix,
        [int]$InlineThresholdChars = 2048,
        [switch]$AlwaysOffload
    )

    if (-not $Owner) { return }
    if ($InlineThresholdChars -lt 256) { $InlineThresholdChars = 256 }

    $inlineBody = ""
    $bodyPath = ""
    $preview = ""
    try { if ($Owner.PSObject.Properties.Name -contains $BodyProperty) { $inlineBody = [string]($Owner.$BodyProperty + "") } } catch { $inlineBody = "" }
    try { if ($Owner.PSObject.Properties.Name -contains $PathProperty) { $bodyPath = ([string]($Owner.$PathProperty + "")).Trim() } } catch { $bodyPath = "" }
    try { if ($Owner.PSObject.Properties.Name -contains $PreviewProperty) { $preview = [string]($Owner.$PreviewProperty + "") } } catch { $preview = "" }

    if ([string]::IsNullOrWhiteSpace($inlineBody) -and [string]::IsNullOrWhiteSpace($bodyPath)) {
        return
    }

    $resolvedBodyPath = Resolve-QOTicketBodyFilePath -Path $bodyPath
    if (-not $AlwaysOffload -and
        [string]::IsNullOrWhiteSpace($resolvedBodyPath) -and
        -not [string]::IsNullOrWhiteSpace($inlineBody) -and
        $inlineBody.Length -le $InlineThresholdChars) {
        if ($Owner.PSObject.Properties.Name -contains $PreviewProperty) {
            try { $Owner.$PreviewProperty = Get-QOTicketBodyPreview -Body ([string]$Owner.$PreviewProperty) } catch { }
        }
        return
    }

    $savedToBodyFile = $false
    if (-not [string]::IsNullOrWhiteSpace($inlineBody)) {
        if ([string]::IsNullOrWhiteSpace($resolvedBodyPath)) {
            $resolvedBodyPath = New-QOTicketBodyFilePath -TicketId $TicketId -Suffix $PathSuffix
            $bodyPath = $resolvedBodyPath
        }

        $shouldWriteFile = $false
        if (-not (Test-Path -LiteralPath $resolvedBodyPath)) {
            $shouldWriteFile = $true
        } elseif ($AlwaysOffload -or $inlineBody.Length -gt $InlineThresholdChars) {
            $shouldWriteFile = $true
        }

        if ($shouldWriteFile) {
            try {
                $bodyDir = Split-Path -Parent $resolvedBodyPath
                if (-not (Test-Path -LiteralPath $bodyDir)) {
                    New-Item -ItemType Directory -Path $bodyDir -Force | Out-Null
                }
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllText($resolvedBodyPath, $inlineBody, $utf8NoBom)
                $savedToBodyFile = $true
            } catch {
                Write-QOTicketsCoreLog ("Tickets: Failed to persist body file for ticket {0}. {1}" -f [string]$TicketId, $_.Exception.Message) "WARN"
            }
        } else {
            $savedToBodyFile = $true
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($resolvedBodyPath) -and (Test-Path -LiteralPath $resolvedBodyPath)) {
        $savedToBodyFile = $true
    }

    if (-not $savedToBodyFile) { return }

    if ([string]::IsNullOrWhiteSpace($preview)) {
        $preview = Get-QOTicketBodyPreview -Body $inlineBody
    } else {
        $preview = Get-QOTicketBodyPreview -Body $preview
    }

    if ($Owner.PSObject.Properties.Name -contains $PathProperty) {
        try { $Owner.$PathProperty = $resolvedBodyPath } catch { }
    } else {
        try { $Owner | Add-Member -NotePropertyName $PathProperty -NotePropertyValue $resolvedBodyPath -Force } catch { }
    }

    if ($Owner.PSObject.Properties.Name -contains $PreviewProperty) {
        try { $Owner.$PreviewProperty = $preview } catch { }
    } else {
        try { $Owner | Add-Member -NotePropertyName $PreviewProperty -NotePropertyValue $preview -Force } catch { }
    }

    if ($Owner.PSObject.Properties.Name -contains $BodyProperty) {
        try { $Owner.$BodyProperty = "" } catch { }
    } else {
        try { $Owner | Add-Member -NotePropertyName $BodyProperty -NotePropertyValue "" -Force } catch { }
    }
}

function Get-QOTicketBodyPreview {
    param(
        [AllowNull()][string]$Body,
        [int]$MaxChars = 600
    )

    $text = [string]($Body + "")
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    if ($MaxChars -lt 100) { $MaxChars = 100 }
    if ($text.Length -le $MaxChars) { return $text }
    return ($text.Substring(0, $MaxChars) + "...")
}

function Optimize-QOTicketBodyStorage {
    param(
        [Parameter(Mandatory)]$Database
    )

    if (-not $Database -or -not ($Database.PSObject.Properties.Name -contains "Tickets")) {
        return
    }

    foreach ($ticket in @($Database.Tickets)) {
        if (-not $ticket) { continue }

        $ticketId = ""
        try {
            if ($ticket.PSObject.Properties.Name -contains "Id") {
                $ticketId = [string]$ticket.Id
            }
        } catch { $ticketId = "" }

        Optimize-QOTicketInlineTextBodyStorage -Owner $ticket -TicketId $ticketId -BodyProperty "EmailBody" -PathProperty "EmailBodyPath" -PreviewProperty "EmailBodyPreview" -AlwaysOffload

        $incomingIndex = 0
        try {
            if ($ticket.PSObject.Properties.Name -contains "IncomingMessages") {
                foreach ($incoming in @($ticket.IncomingMessages)) {
                    if ($null -eq $incoming) { continue }
                    $suffix = Get-QOTicketStableBodySuffix -TicketId $ticketId -Kind "incoming" -Index $incomingIndex -Entry $incoming
                    Optimize-QOTicketInlineTextBodyStorage -Owner $incoming -TicketId $ticketId -BodyProperty "Body" -PathProperty "BodyPath" -PreviewProperty "BodyPreview" -PathSuffix $suffix
                    $incomingIndex++
                }
            }
        } catch { }

        $replyIndex = 0
        try {
            if ($ticket.PSObject.Properties.Name -contains "Replies") {
                foreach ($reply in @($ticket.Replies)) {
                    if ($null -eq $reply) { continue }
                    $suffix = Get-QOTicketStableBodySuffix -TicketId $ticketId -Kind "reply" -Index $replyIndex -Entry $reply
                    Optimize-QOTicketInlineTextBodyStorage -Owner $reply -TicketId $ticketId -BodyProperty "Body" -PathProperty "BodyPath" -PreviewProperty "BodyPreview" -PathSuffix $suffix
                    $replyIndex++
                }
            }
        } catch { }

        $noteIndex = 0
        try {
            if ($ticket.PSObject.Properties.Name -contains "Notes") {
                foreach ($note in @($ticket.Notes)) {
                    if ($null -eq $note) { continue }
                    $suffix = Get-QOTicketStableBodySuffix -TicketId $ticketId -Kind "note" -Index $noteIndex -Entry $note
                    Optimize-QOTicketInlineTextBodyStorage -Owner $note -TicketId $ticketId -BodyProperty "Body" -PathProperty "BodyPath" -PreviewProperty "BodyPreview" -PathSuffix $suffix
                    $noteIndex++
                }
            }
        } catch { }
    }
}

function Merge-QOTicketDatabases {
    param(
        [Parameter(Mandatory)]$BaseDatabase,
        [Parameter(Mandatory)]$IncomingDatabase
    )

    $base = Normalize-QOTicketDatabase -Database $BaseDatabase
    $incoming = Normalize-QOTicketDatabase -Database $IncomingDatabase

    $map = @{}
    $order = New-Object 'System.Collections.Generic.List[string]'
    $orphans = New-Object 'System.Collections.ArrayList'

    foreach ($ticket in @($base.Tickets)) {
        if ($null -eq $ticket) { continue }
        $id = ([string]($ticket.Id + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($id)) {
            [void]$orphans.Add($ticket)
            continue
        }

        if (-not $map.ContainsKey($id)) {
            $order.Add($id) | Out-Null
        }
        $map[$id] = $ticket
    }

    foreach ($ticket in @($incoming.Tickets)) {
        if ($null -eq $ticket) { continue }
        $id = ([string]($ticket.Id + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($id)) {
            [void]$orphans.Add($ticket)
            continue
        }

        if (-not $map.ContainsKey($id)) {
            $map[$id] = $ticket
            $order.Add($id) | Out-Null
            continue
        }

        $existing = $map[$id]
        $existingStamp = Get-QOTicketMergeTimestamp -Ticket $existing
        $incomingStamp = Get-QOTicketMergeTimestamp -Ticket $ticket

        # Same timestamp resolves to incoming (latest in-memory edit intent).
        if ($incomingStamp -ge $existingStamp) {
            $map[$id] = $ticket
        }
    }

    $mergedTickets = @()
    foreach ($id in $order) {
        if ($map.ContainsKey($id)) {
            $mergedTickets += @($map[$id])
        }
    }

    if ($orphans.Count -gt 0) {
        $mergedTickets += @($orphans)
    }

    $baseVersion = 1
    $incomingVersion = 1
    try { $baseVersion = [int]$base.SchemaVersion } catch { $baseVersion = 1 }
    try { $incomingVersion = [int]$incoming.SchemaVersion } catch { $incomingVersion = 1 }
    $schemaVersion = [Math]::Max($baseVersion, $incomingVersion)

    return [pscustomobject]@{
        SchemaVersion = $schemaVersion
        Tickets       = @($mergedTickets)
    }
}

function Write-QOTicketsStoreFileAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$JsonContent
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $leaf = Split-Path -Leaf $Path
    $tempName = "{0}.tmp.{1}.{2}" -f $leaf, $PID, ([guid]::NewGuid().ToString("N"))
    $tempPath = Join-Path $dir $tempName

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, $JsonContent, $utf8NoBom)

        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tempPath, $Path, $null, $true)
            } catch {
                [System.IO.File]::Copy($tempPath, $Path, $true)
                [System.IO.File]::Delete($tempPath)
            }
        } else {
            [System.IO.File]::Move($tempPath, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}


function Test-QOIsBadTicketPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }

    $p = [string]$Path

    # Anything inside TEMP extraction paths is not stable
    if ($p -like "*\AppData\Local\Temp\QuinnOptimiserToolkit\*") { return $true }
    if ($p -like "*\Temp\QuinnOptimiserToolkit\*") { return $true }

    # If it's not a JSON file, treat as bad
    if ($p -notlike "*.json") { return $true }

    return $false
}

function Get-QOTicketsStorePath {
    Initialize-QOTicketStorage
    return $script:TicketStorePath
}

function Ensure-QOTicketsStoreDirectory {
    Initialize-QOTicketStorage
    $dir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Reset-QOTicketStorageCache {
    $script:TicketStorePath = $null
    $script:TicketBackupPath = $null
    Initialize-QOTicketStorage
    return [pscustomobject]@{
        StorePath  = [string]$script:TicketStorePath
        BackupPath = [string]$script:TicketBackupPath
    }
}

# =====================================================================
# Storage path resolution (uses Config module)
# =====================================================================
function Get-QOTicketStorePath {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:TicketStorePath)) {
        return [string]$script:TicketStorePath
    }

    # Try Config module first (preferred)
    $configCmd = Get-Command -Name "Get-QOTPath" -ErrorAction SilentlyContinue
    if ($configCmd) {
        try {
            $ticketsDir = & $configCmd -Name "tickets"
            if (-not [string]::IsNullOrWhiteSpace($ticketsDir)) {
                if (-not (Test-Path -LiteralPath $ticketsDir)) {
                    New-Item -ItemType Directory -Path $ticketsDir -Force | Out-Null
                }
                $script:TicketStorePath = Join-Path $ticketsDir "Tickets.json"
                return $script:TicketStorePath
            }
        } catch { }
    }

    # Fall back to Settings module
    $appDataCmd = Get-Command -Name "Get-QOAppDataRoot" -ErrorAction SilentlyContinue
    if ($appDataCmd) {
        try {
            $appDataRoot = & $appDataCmd
            if (-not [string]::IsNullOrWhiteSpace([string]$appDataRoot)) {
                $ticketsDir = Join-Path ([string]$appDataRoot) "QuinnOptimiserToolkit\Tickets"
                if (-not (Test-Path -LiteralPath $ticketsDir)) {
                    New-Item -ItemType Directory -Path $ticketsDir -Force | Out-Null
                }
                $script:TicketStorePath = Join-Path $ticketsDir "Tickets.json"
                return $script:TicketStorePath
            }
        } catch { }
    }

    # Last resort -- LocalAppData direct (never temp)
    $localAppData = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    }
    $ticketsDir = Join-Path $localAppData "QuinnOptimiserToolkit\Tickets"
    if (-not (Test-Path -LiteralPath $ticketsDir)) {
        New-Item -ItemType Directory -Path $ticketsDir -Force | Out-Null
    }
    $script:TicketStorePath = Join-Path $ticketsDir "Tickets.json"
    return $script:TicketStorePath
}

# =====================================================================
# Storage initialisation (with path migration)
# =====================================================================
function Initialize-QOTicketStorage {
    if ($script:TicketStorePath -and $script:TicketBackupPath) { return }

    $settings = Get-QOTicketsSettingsObject

    $settings = Ensure-QOSettingProperty $settings "TicketStorePath" ""
    $settings = Ensure-QOSettingProperty $settings "LocalTicketBackupPath" ""
    $settings = Ensure-QOSettingProperty $settings "TicketsColumnLayout" @()

    $appDataRoot = Get-QOTicketsCoreAppDataRoot
    $stableStorePath  = Join-Path $appDataRoot "StudioVoly\QuinnToolkit\Tickets\Tickets.json"
    $stableBackupPath = Join-Path $appDataRoot "StudioVoly\QuinnToolkit\Tickets\Backups"
    $legacyStorePaths = @(
        (Join-Path $appDataRoot "StudioVoly\QuinnToolkit\Tickets.json"),
        (Join-Path $appDataRoot "StudioVoly\QuinnToolkit\Tickets\TicketStore.json")
    )

    $currentPath = [string]$settings.TicketStorePath
    $needReset   = $false

    # Decide if current path is unsafe or unusable
    if (Test-QOIsBadTicketPath -Path $currentPath) {
        $needReset = $true
    }

    # Attempt migration if we are changing paths AND old file exists somewhere
    if ($needReset) {
        # If old path exists and stable doesn't, copy it across
        try {
            if (-not [string]::IsNullOrWhiteSpace($currentPath)) {
                if (Test-Path -LiteralPath $currentPath) {
                    $stableDir = Split-Path -Parent $stableStorePath
                    if (-not (Test-Path -LiteralPath $stableDir)) {
                        New-Item -ItemType Directory -Path $stableDir -Force | Out-Null
                    }

                    if (-not (Test-Path -LiteralPath $stableStorePath)) {
                        Copy-Item -LiteralPath $currentPath -Destination $stableStorePath -Force
                        Write-QOTicketsCoreLog ("Tickets: Migrated legacy store from {0} to {1}" -f $currentPath, $stableStorePath)
                    }
                }
            }
        } catch { }
        
        if (-not (Test-Path -LiteralPath $stableStorePath)) {
            foreach ($legacyPath in $legacyStorePaths) {
                if ([string]::IsNullOrWhiteSpace($legacyPath)) { continue }
                if (Test-Path -LiteralPath $legacyPath) {
                    try {
                        $stableDir = Split-Path -Parent $stableStorePath
                        if (-not (Test-Path -LiteralPath $stableDir)) {
                            New-Item -ItemType Directory -Path $stableDir -Force | Out-Null
                        }
                        Copy-Item -LiteralPath $legacyPath -Destination $stableStorePath -Force
                        Write-QOTicketsCoreLog ("Tickets: Migrated legacy store from {0} to {1}" -f $legacyPath, $stableStorePath)
                        break
                    } catch { }
                }
            }
        }


        $settings.TicketStorePath = $stableStorePath
    }

    # Backup path should always be stable
    if ([string]::IsNullOrWhiteSpace([string]$settings.LocalTicketBackupPath) -or
        ([string]$settings.LocalTicketBackupPath -like "*\AppData\Local\Temp\QuinnOptimiserToolkit\*")) {
        $settings.LocalTicketBackupPath = $stableBackupPath
    }

    $null = Save-QOTicketsSettingsObject -Settings $settings

    $script:TicketStorePath  = [string]$settings.TicketStorePath
    $script:TicketBackupPath = Join-Path (Split-Path $script:TicketStorePath -Parent) "Tickets.backup.json"

    # Ensure directories exist
    New-Item -ItemType Directory -Path (Split-Path -Parent $script:TicketStorePath) -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null

    # Ensure the tickets file exists
    New-QODefaultTicketsFile -Path $script:TicketStorePath
}

# =====================================================================
# Database IO
# =====================================================================
function Get-QOTickets {
    param(
        [switch]$Quiet
    )

    $loadStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $saveStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $Quiet) { Write-QOTicketsCoreLog "Tickets: Resolve ticket store path" }
        Initialize-QOTicketStorage
        if (-not $Quiet) { Write-QOTicketsCoreLog ("Tickets: Store path resolved. StorePath={0}" -f $script:TicketStorePath) }
        if (-not $Quiet) { Write-QOTicketsCoreLog "Tickets: Read JSON file" }
        if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
            if (-not $Quiet) { Write-QOTicketsCoreLog ("Tickets: Store file missing. Creating new store at {0}." -f $script:TicketStorePath) }
            New-QODefaultTicketsFile -Path $script:TicketStorePath
        }
        try {
            $storeInfo = Get-Item -LiteralPath $script:TicketStorePath -ErrorAction Stop
            $compactThreshold = [int64]$script:TicketStoreCompactionThresholdBytes
            if ($compactThreshold -lt 1MB) { $compactThreshold = 50MB }
            if ($storeInfo.Length -gt $compactThreshold) {
                if (-not $Quiet) { Write-QOTicketsCoreLog ("Tickets: Store is large ({0:n1} MB). Checking for oversized inline bodies." -f ($storeInfo.Length / 1MB)) }
                $null = Compress-QOTicketStoreLargeBodyLines -Path $script:TicketStorePath -BackupDirectory $script:TicketBackupPath -Quiet:$Quiet
            }
        } catch {
            Write-QOTicketsCoreLog ("Tickets: Store compaction pre-check failed. {0}" -f $_.Exception.Message) "WARN"
        }
        $currentWriteUtc = [datetime]::MinValue
        try { $currentWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($script:TicketStorePath) } catch { $currentWriteUtc = [datetime]::MinValue }
        $rawJson = Read-QOTicketStoreJsonText -Path $script:TicketStorePath
        if ([string]::IsNullOrWhiteSpace($rawJson)) {
            if (-not $Quiet) { Write-QOTicketsCoreLog "Tickets: JSON file empty. Treating as empty array." }
            $rawJson = "[]"
        }
        if (-not $Quiet) { Write-QOTicketsCoreLog "Tickets: Parse JSON" }
        $db = $rawJson | ConvertFrom-Json -ErrorAction Stop
        if (-not $db) {
            $db = New-QODefaultTicketDatabase
        }

        if (-not $Quiet) { Write-QOTicketsCoreLog "Tickets: Map to objects" }
        $db = Normalize-QOTicketDatabase -Database $db
        $stampTicks = 0L
        try { $stampTicks = [int64]$currentWriteUtc.Ticks } catch { $stampTicks = 0L }
        if ($db.PSObject.Properties.Name -contains "__StoreLastWriteUtcTicks") {
            try { $db.__StoreLastWriteUtcTicks = $stampTicks } catch { }
        } else {
            try { $db | Add-Member -NotePropertyName "__StoreLastWriteUtcTicks" -NotePropertyValue $stampTicks -Force } catch { }
        }
        $ticketCount = 0
        try { $ticketCount = @($db.Tickets).Count } catch { }
        try {
            $ticketsWithMainBody = 0
            $previewedTickets = 0
            foreach ($loadedTicket in @($db.Tickets)) {
                if (-not $loadedTicket) { continue }
                $bodyPath = ""
                $previewValue = ""
                try { if ($loadedTicket.PSObject.Properties.Name -contains "EmailBodyPath") { $bodyPath = ([string]($loadedTicket.EmailBodyPath + "")).Trim() } } catch { $bodyPath = "" }
                try { if ($loadedTicket.PSObject.Properties.Name -contains "EmailBodyPreview") { $previewValue = ([string]($loadedTicket.EmailBodyPreview + "")).Trim() } } catch { $previewValue = "" }
                if (-not [string]::IsNullOrWhiteSpace($bodyPath)) { $ticketsWithMainBody++ }
                if (-not [string]::IsNullOrWhiteSpace($previewValue)) { $previewedTickets++ }
            }
            if (-not $Quiet) {
                Write-QOTicketsCoreLog ("Tickets: Load body summary. TicketsWithBodyPath={0}; TicketsWithPreview={1}; TotalTickets={2}" -f `
                    $ticketsWithMainBody, `
                    $previewedTickets, `
                    $ticketCount)
            }
        } catch { }
        if (-not $Quiet) {
            Write-QOTicketsCoreLog ("Tickets: Load completed. Tickets={0}." -f $ticketCount)
            Write-QOTicketsCoreLog ("Tickets: Load duration {0} ms." -f [int]$loadStopwatch.Elapsed.TotalMilliseconds)
        }
        
        return $db
    }
    catch {
        $msg = $_.Exception.Message
        $stack = $_.Exception.StackTrace
        $inner = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { "" }

        Write-QOTicketsCoreLog ("Tickets: Load failed. Error: " + $msg) "ERROR"
        if ($inner) { Write-QOTicketsCoreLog ("Tickets: InnerException: " + $inner) "ERROR" }
        if ($stack) { Write-QOTicketsCoreLog ("Tickets: StackTrace: " + $stack) "ERROR" }
        $ticketPath = $script:TicketStorePath
        $errorToThrow = [System.Exception]::new(
            ("Tickets: Failed to load ticket store from {0}. Error: {1}" -f $ticketPath, $msg),
            $_.Exception
        )
        try {
            $backupPath = Get-QOLatestTicketBackupPath -TicketPath $ticketPath -BackupDirectory $script:TicketBackupPath
            if ($backupPath) {
                Copy-Item -LiteralPath $backupPath -Destination $ticketPath -Force -ErrorAction SilentlyContinue
                $db = Read-QOTicketStoreJsonText -Path $ticketPath | ConvertFrom-Json -ErrorAction Stop
                if ($db) {
                    $db = Normalize-QOTicketDatabase -Database $db
                    $ticketCount = 0
                    try { $ticketCount = @($db.Tickets).Count } catch { }
                    Write-QOTicketsCoreLog ("Tickets: Restored from backup {0}. Loaded {1} tickets." -f $backupPath, $ticketCount)
                    return $db
                }
            }
        } catch { }
        $isMemoryFailure = $false
        try {
            $errorText = ([string]$msg + " " + [string]$inner).ToLowerInvariant()
            if ($errorText -match 'outofmemory|insufficient memory') {
                $isMemoryFailure = $true
            }
        } catch { $isMemoryFailure = $false }

        if ($isMemoryFailure) {
            Write-QOTicketsCoreLog "Tickets: Skipping destructive reset because load failure appears to be memory-related." "WARN"
            throw $errorToThrow
        }

        try {
            if (-not [string]::IsNullOrWhiteSpace($ticketPath)) {
                if (Test-Path -LiteralPath $ticketPath) {
                    $backupName = "{0}.bak_{1}" -f $ticketPath, (Get-Date -Format "yyyyMMddHHmmss")
                    Copy-Item -LiteralPath $ticketPath -Destination $backupName -Force -ErrorAction SilentlyContinue
                }

                New-QODefaultTicketDatabase | ConvertTo-Json -Depth 8 |
                    Set-Content -LiteralPath $ticketPath -Encoding UTF8
            }
        } catch { }
        throw $errorToThrow
    }
    finally {
        try { if ($loadStopwatch) { $loadStopwatch.Stop() } } catch { }
    }
}

function Save-QOTickets {
    param(
        [Parameter(Mandatory)]$Database,
        [switch]$SkipBodyOptimization,
        [switch]$Quiet
    )

    Initialize-QOTicketStorage

    if (-not ($Database.PSObject.Properties.Name -contains "Tickets")) {
        $Database | Add-Member -NotePropertyName Tickets -NotePropertyValue @() -Force
    }

    $Database = Normalize-QOTicketDatabase -Database $Database

    $incomingStoreStampTicks = 0L
    try {
        if ($Database.PSObject.Properties.Name -contains "__StoreLastWriteUtcTicks") {
            $incomingStoreStampTicks = [int64]$Database.__StoreLastWriteUtcTicks
            try { $null = $Database.PSObject.Properties.Remove("__StoreLastWriteUtcTicks") } catch { }
        }
    } catch { $incomingStoreStampTicks = 0L }

    $mutexName = Get-QOTicketStoreMutexName -StorePath $script:TicketStorePath
    $mutex = $null
    $lockTaken = $false

    try {
        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
        $timeoutSeconds = 15
        try { $timeoutSeconds = [int]$script:TicketStoreLockTimeoutSeconds } catch { $timeoutSeconds = 15 }
        if ($timeoutSeconds -lt 2) { $timeoutSeconds = 2 }
        $timeout = [System.TimeSpan]::FromSeconds($timeoutSeconds)

        try {
            $lockTaken = $mutex.WaitOne($timeout)
        } catch [System.Threading.AbandonedMutexException] {
            $lockTaken = $true
            Write-QOTicketsCoreLog ("Tickets: Store lock was abandoned. Continuing write for {0}." -f $script:TicketStorePath) "WARN"
        }

        if (-not $lockTaken) {
            throw ("Timed out after {0}s waiting for shared ticket store lock ({1})." -f $timeoutSeconds, $script:TicketStorePath)
        }

        $currentWriteUtc = [datetime]::MinValue
        $currentWriteTicks = 0L
        if (Test-Path -LiteralPath $script:TicketStorePath) {
            try {
                $currentWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($script:TicketStorePath)
                $currentWriteTicks = [int64]$currentWriteUtc.Ticks
            } catch {
                $currentWriteUtc = [datetime]::MinValue
                $currentWriteTicks = 0L
            }
        }

        try {
            if (Test-Path -LiteralPath $script:TicketStorePath) {
                $nowUtc = (Get-Date).ToUniversalTime()
                $backupIntervalSeconds = 90
                try { $backupIntervalSeconds = [int]$script:TicketBackupMinIntervalSeconds } catch { $backupIntervalSeconds = 90 }
                if ($backupIntervalSeconds -lt 15) { $backupIntervalSeconds = 15 }
                $elapsedSeconds = 0.0
                try { $elapsedSeconds = ($nowUtc - $script:TicketLastBackupUtc).TotalSeconds } catch { $elapsedSeconds = 999999.0 }
                if ($elapsedSeconds -ge $backupIntervalSeconds) {
                    if (-not (Test-Path -LiteralPath $script:TicketBackupPath)) {
                        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
                    }
                    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
                    $ticketName = Split-Path -Leaf $script:TicketStorePath
                    $backupName = "{0}.bak_{1}" -f $ticketName, $timestamp
                    $backupPath = Join-Path $script:TicketBackupPath $backupName
                    Copy-Item -LiteralPath $script:TicketStorePath -Destination $backupPath -Force -ErrorAction SilentlyContinue
                    $script:TicketLastBackupUtc = $nowUtc
                }
            }
        } catch { }

        $useFastIncomingSave = $false
        if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
            $useFastIncomingSave = $true
        } elseif ($incomingStoreStampTicks -gt 0 -and $currentWriteTicks -gt 0 -and $incomingStoreStampTicks -eq $currentWriteTicks) {
            $useFastIncomingSave = $true
        }

        $merged = $null
        if ($useFastIncomingSave) {
            $merged = $Database
        } else {
            $latestOnDisk = New-QODefaultTicketDatabase
            if (Test-Path -LiteralPath $script:TicketStorePath) {
                try {
                    $rawJson = Read-QOTicketStoreJsonText -Path $script:TicketStorePath
                    if ([string]::IsNullOrWhiteSpace($rawJson)) { $rawJson = "[]" }
                    $latestOnDisk = $rawJson | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-QOTicketsCoreLog ("Tickets: Existing store read failed during save merge. Using default and continuing. Error: {0}" -f $_.Exception.Message) "WARN"
                    $latestOnDisk = New-QODefaultTicketDatabase
                }
            }
            $merged = Merge-QOTicketDatabases -BaseDatabase $latestOnDisk -IncomingDatabase $Database
        }
        if (-not $SkipBodyOptimization) {
            Optimize-QOTicketBodyStorage -Database $merged
        }
        try {
            $ticketsWithMainBody = 0
            $previewedTickets = 0
            foreach ($savedTicket in @($merged.Tickets)) {
                if (-not $savedTicket) { continue }
                $bodyPath = ""
                $previewValue = ""
                try { if ($savedTicket.PSObject.Properties.Name -contains "EmailBodyPath") { $bodyPath = ([string]($savedTicket.EmailBodyPath + "")).Trim() } } catch { $bodyPath = "" }
                try { if ($savedTicket.PSObject.Properties.Name -contains "EmailBodyPreview") { $previewValue = ([string]($savedTicket.EmailBodyPreview + "")).Trim() } } catch { $previewValue = "" }
                if (-not [string]::IsNullOrWhiteSpace($bodyPath)) { $ticketsWithMainBody++ }
                if (-not [string]::IsNullOrWhiteSpace($previewValue)) { $previewedTickets++ }
            }
            Write-QOTicketsCoreLog ("Tickets: Save body summary. TicketsWithBodyPath={0}; TicketsWithPreview={1}; TotalTickets={2}" -f `
                $ticketsWithMainBody, `
                $previewedTickets, `
                @($merged.Tickets).Count)
        } catch { }
        $json = $merged | ConvertTo-Json -Depth 25
        Write-QOTicketsStoreFileAtomic -Path $script:TicketStorePath -JsonContent $json

        $newWriteTicks = 0L
        try {
            $newWriteTicks = [int64]([System.IO.File]::GetLastWriteTimeUtc($script:TicketStorePath).Ticks)
        } catch { $newWriteTicks = 0L }

        try {
            $Database.Tickets = @($merged.Tickets)
            if ($Database.PSObject.Properties.Name -contains "SchemaVersion") {
                $Database.SchemaVersion = $merged.SchemaVersion
            } else {
                $Database | Add-Member -NotePropertyName SchemaVersion -NotePropertyValue $merged.SchemaVersion -Force
            }
            if ($Database.PSObject.Properties.Name -contains "__StoreLastWriteUtcTicks") {
                $Database.__StoreLastWriteUtcTicks = $newWriteTicks
            } else {
                $Database | Add-Member -NotePropertyName "__StoreLastWriteUtcTicks" -NotePropertyValue $newWriteTicks -Force
            }
        } catch { }

        $savedCount = 0
        try { $savedCount = @($merged.Tickets).Count } catch { }
        if (-not $Quiet) {
            Write-QOTicketsCoreLog ("Tickets: Saved {0} tickets to {1} (shared merge safe)." -f $savedCount, $script:TicketStorePath)
            Write-QOTicketsCoreLog ("Tickets: Save duration {0} ms." -f [int]$saveStopwatch.Elapsed.TotalMilliseconds)
        }
    }
    finally {
        try { if ($saveStopwatch) { $saveStopwatch.Stop() } } catch { }
        if ($lockTaken -and $mutex) {
            try { $mutex.ReleaseMutex() } catch { }
        }
        if ($mutex) {
            try { $mutex.Dispose() } catch { }
        }
    }
}

# =====================================================================
# CRUD
# =====================================================================
function New-QOTicket {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$TicketName,
        [string]$Subject,
        [string]$Priority = "Medium",
        [string]$AssignedTo = "Unassigned",
        [string]$Status = "New",
        [string]$InitialNote,
        [string]$EmailFrom = "",
        [string]$EmailTo = "",
        [string]$SenderName = "",
        [string]$SenderEmail = "",
        [string]$SourceMailbox = "",
        [string]$Source = "Manual"
    )
    $statusValue = if ([string]::IsNullOrWhiteSpace([string]$Status)) { "New" } else { [string]$Status }
    if ($statusValue -eq "Open") { $statusValue = "In Progress" }
    if ($script:ValidTicketStatuses -notcontains $statusValue) { $statusValue = "New" }

    $nameValue = if ([string]::IsNullOrWhiteSpace([string]$TicketName)) { $Title } else { $TicketName }
    $subjectValue = if ([string]::IsNullOrWhiteSpace([string]$Subject)) { $nameValue } else { $Subject }
    $emailFromValue = Normalize-QOTicketTextField -Value ([string]$EmailFrom) -MaxLength 320
    $emailToValue = Normalize-QOTicketTextField -Value ([string]$EmailTo) -MaxLength 320
    $senderNameValue = Normalize-QOTicketTextField -Value ([string]$SenderName) -MaxLength 240
    $senderEmailValue = Normalize-QOTicketTextField -Value ([string]$SenderEmail) -MaxLength 320
    $sourceMailboxValue = Normalize-QOTicketTextField -Value ([string]$SourceMailbox) -MaxLength 320
    $sourceValue = Normalize-QOTicketTextField -Value ([string]$Source) -MaxLength 80
    if ([string]::IsNullOrWhiteSpace($sourceValue)) { $sourceValue = "Manual" }

    $now = Get-Date
    $notes = @()
    if (-not [string]::IsNullOrWhiteSpace($InitialNote)) {
        $notes += [pscustomobject]@{
            Body      = $InitialNote
            CreatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
        }
    }


    [pscustomobject]@{
        Id         = [guid]::NewGuid().ToString()
        Title      = $nameValue
        TicketName = $nameValue
        Subject    = $subjectValue
        CreatedAt  = $now.ToString("yyyy-MM-dd HH:mm:ss")
        UpdatedAt  = $now.ToString("yyyy-MM-dd HH:mm:ss")
        Status     = $statusValue
        Priority   = (Normalize-QOTicketPriority -Priority $Priority -Subject $subjectValue -Status $statusValue)
        AssignedTo = (Normalize-QOTicketAssignee -AssignedTo $AssignedTo)
        Source     = $sourceValue
        Folder     = "Active"
        DeletedAt  = $null
        IsDeleted  = $false
        EmailFrom  = $emailFromValue
        EmailTo    = $emailToValue
        SenderName = $senderNameValue
        SenderEmail = $senderEmailValue
        SourceMailbox = $sourceMailboxValue
        Notes      = $notes
        Replies    = @()
        PendingReplies = @()
    }
}

function Add-QOTicket {
    param([Parameter(Mandatory)]$Ticket)

    $db = Get-QOTickets -Quiet
    try {
        if ($Ticket.PSObject.Properties.Name -notcontains "UpdatedAt") {
            $Ticket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Force
        }
        if ($Ticket.PSObject.Properties.Name -notcontains "Priority") {
            $Ticket | Add-Member -NotePropertyName Priority -NotePropertyValue "Medium" -Force
        }
        if ($Ticket.PSObject.Properties.Name -notcontains "AssignedTo") {
            $Ticket | Add-Member -NotePropertyName AssignedTo -NotePropertyValue "Unassigned" -Force
        }
        $prioritySubject = ""
        try {
            if ($Ticket.PSObject.Properties.Name -contains "Subject") {
                $prioritySubject = [string]$Ticket.Subject
            } elseif ($Ticket.PSObject.Properties.Name -contains "Title") {
                $prioritySubject = [string]$Ticket.Title
            }
        } catch { }
        $Ticket.Priority = Normalize-QOTicketPriority -Priority ([string]$Ticket.Priority) -Subject $prioritySubject -Status ([string]$Ticket.Status)
        $Ticket.AssignedTo = Normalize-QOTicketAssignee -AssignedTo ([string]$Ticket.AssignedTo)
    } catch { }
    $db.Tickets = @($db.Tickets) + @($Ticket)
    Save-QOTickets -Database $db -Quiet
    return $Ticket
}

function Update-QOTicket {
    param([Parameter(Mandatory)]$Ticket)

    $db = Get-QOTickets -Quiet

    $ticketId = $null
    try { $ticketId = [string]$Ticket.Id } catch { }
    if ([string]::IsNullOrWhiteSpace($ticketId)) {
        return $false
    }

    $updated = $false
    foreach ($existing in @($db.Tickets)) {
        if ($null -eq $existing) { continue }
        if ($existing.Id -ne $ticketId) { continue }

        $nowStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        try {
            if ($Ticket.PSObject.Properties.Name -contains "UpdatedAt") {
                $Ticket.UpdatedAt = $nowStamp
            } else {
                $Ticket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue $nowStamp -Force
            }
        } catch { }

        foreach ($prop in $Ticket.PSObject.Properties) {
            if ($prop.Name -eq "Id") { continue }
            if ($prop.Name -match 'Display$') { continue }
            $existing | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
        try {
            if ($existing.PSObject.Properties.Name -notcontains "AssignedTo") {
                $existing | Add-Member -NotePropertyName AssignedTo -NotePropertyValue "Unassigned" -Force
            }
            $existing.AssignedTo = Normalize-QOTicketAssignee -AssignedTo ([string]$existing.AssignedTo)
        } catch { }

        $updated = $true
        break
    }

    if ($updated) {
        Save-QOTickets -Database $db -Quiet
    }

    return $updated
}



function Remove-QOTicket {
    param([Parameter(Mandatory)][string[]]$Id)

    $db = Get-QOTickets -Quiet
    $ids = @($Id | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($ids.Count -eq 0) {
        return
    }

    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ($ids -contains $ticket.Id) {
            $ticket.Folder = "Deleted"
            $ticket.DeletedAt = $now
            $ticket.IsDeleted = $true
            $ticket.UpdatedAt = $now
        }
    }
    Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
}

function Restore-QOTickets {
    param([Parameter(Mandatory)][string[]]$Id)

    $db = Get-QOTickets -Quiet
    $ids = @($Id | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($ids.Count -eq 0) {
        return
    }

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ($ids -contains $ticket.Id) {
            $ticket.Folder = "Active"
            $ticket.DeletedAt = $null
            $ticket.IsDeleted = $false
            $ticket.UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
}

function Set-QOTicketsStatus {
    param(
        [Parameter(Mandatory)][string[]]$Id,
        [Parameter(Mandatory)][string]$Status
    )

    $statusValue = [string]$Status
    if ($statusValue -eq "Open") { $statusValue = "In Progress" }

    if ($script:ValidTicketStatuses -notcontains $statusValue) {
        throw "Invalid status '$Status'. Allowed: $($script:ValidTicketStatuses -join ', ')."
    }

    $db = Get-QOTickets -Quiet
    $ids = @($Id | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($ids.Count -eq 0) {
        return
    }

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ($ids -contains $ticket.Id) {
            $ticket.Status = $statusValue
            $ticket.UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
}

function Get-QOTicketStatuses {
    return @($script:ValidTicketStatuses)
}

function Set-QOTicketsPriority {
    param(
        [Parameter(Mandatory)][string[]]$Id,
        [Parameter(Mandatory)][string]$Priority
    )

    $priorityValue = Normalize-QOTicketPriority -Priority $Priority -Subject $null -Status $null
    if ($script:ValidTicketPriorities -notcontains $priorityValue) {
        throw "Invalid priority '$Priority'. Allowed: $($script:ValidTicketPriorities -join ', ')."
    }

    $db = Get-QOTickets -Quiet
    $ids = @($Id | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($ids.Count -eq 0) {
        return
    }

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ($ids -contains $ticket.Id) {
            $ticket.Priority = $priorityValue
            $ticket.UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
}

function Get-QOTicketPriorities {
    return @($script:ValidTicketPriorities)
}

function Set-QOTicketsAssignedTo {
    param(
        [Parameter(Mandatory)][string[]]$Id,
        [AllowNull()][string]$AssignedTo
    )

    $assignedToValue = Normalize-QOTicketAssignee -AssignedTo $AssignedTo

    $db = Get-QOTickets -Quiet
    $ids = @($Id | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($ids.Count -eq 0) {
        return
    }

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ($ids -contains $ticket.Id) {
            $ticket.AssignedTo = $assignedToValue
            $ticket.UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
}

function Add-QOTicketAssigneeCandidate {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]]$Values,
        [AllowNull()]$Value
    )

    $candidate = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) { return }

    $normalized = Normalize-QOTicketAssignee -AssignedTo $candidate
    if ([string]::IsNullOrWhiteSpace($normalized)) { return }
    if ($normalized -eq "Unassigned") { return }

    [void]$Values.Add($normalized)
}

function Get-QOTicketAssignees {
    $db = Get-QOTickets -Quiet
    $values = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }

        try {
            if ($ticket.PSObject.Properties.Name -contains "AssignedTo") {
                Add-QOTicketAssigneeCandidate -Values $values -Value $ticket.AssignedTo
            }
        } catch { }

        try {
            if ($ticket.PSObject.Properties.Name -contains "LastReadBy") {
                Add-QOTicketAssigneeCandidate -Values $values -Value $ticket.LastReadBy
            }
        } catch { }

        try {
            if ($ticket.PSObject.Properties.Name -contains "ReadBy") {
                $readByValue = $ticket.ReadBy
                if ($readByValue -is [System.Collections.IEnumerable] -and $readByValue -isnot [string]) {
                    foreach ($reader in @($readByValue)) {
                        Add-QOTicketAssigneeCandidate -Values $values -Value $reader
                    }
                } else {
                    Add-QOTicketAssigneeCandidate -Values $values -Value $readByValue
                }
            }
        } catch { }

        try {
            if ($ticket.PSObject.Properties.Name -contains "Notes") {
                foreach ($note in @($ticket.Notes)) {
                    if ($null -eq $note) { continue }
                    if ($note.PSObject.Properties.Name -contains "Author") {
                        Add-QOTicketAssigneeCandidate -Values $values -Value $note.Author
                    }
                }
            }
        } catch { }

        try {
            if ($ticket.PSObject.Properties.Name -contains "Replies") {
                foreach ($reply in @($ticket.Replies)) {
                    if ($null -eq $reply) { continue }
                    if ($reply.PSObject.Properties.Name -contains "Author") {
                        Add-QOTicketAssigneeCandidate -Values $values -Value $reply.Author
                    }
                }
            }
        } catch { }
    }

    $sorted = @($values | ForEach-Object { $_ } | Sort-Object)
    return @("Unassigned") + $sorted
}

function Convert-QOTicketDateValue {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return [datetime]::MinValue }
    if ($Value -is [datetime]) { return ([datetime]$Value) }

    $rawValue = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($rawValue)) { return [datetime]::MinValue }

    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact(
            $rawValue,
            "yyyy-MM-dd HH:mm:ss",
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeLocal,
            [ref]$parsed
        )) {
        return $parsed
    }

    if ([datetime]::TryParse($rawValue, [ref]$parsed)) {
        return $parsed
    }

    return [datetime]::MinValue
}

function Get-QOTicketCreatedDateTime {
    param([AllowNull()]$Ticket)

    if ($null -eq $Ticket) { return [datetime]::MinValue }

    foreach ($propName in @("CreatedAt", "Created", "EmailReceived")) {
        try {
            if ($Ticket.PSObject.Properties.Name -contains $propName) {
                $dt = Convert-QOTicketDateValue -Value $Ticket.$propName
                if ($dt -gt [datetime]::MinValue) { return $dt }
            }
        } catch { }
    }

    return [datetime]::MinValue
}

function Get-QOTicketUpdatedDateTime {
    param([AllowNull()]$Ticket)

    if ($null -eq $Ticket) { return [datetime]::MinValue }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "UpdatedAt") {
            return (Convert-QOTicketDateValue -Value $Ticket.UpdatedAt)
        }
    } catch { }
    return [datetime]::MinValue
}

function Get-QOTicketFirstReplyDateTime {
    param([AllowNull()]$Ticket)

    if ($null -eq $Ticket) { return [datetime]::MinValue }

    $firstReplyAt = [datetime]::MinValue
    foreach ($propName in @("FirstResponseAt", "FirstReplyAt")) {
        try {
            if ($Ticket.PSObject.Properties.Name -contains $propName) {
                $dt = Convert-QOTicketDateValue -Value $Ticket.$propName
                if ($dt -gt [datetime]::MinValue) {
                    $firstReplyAt = $dt
                    break
                }
            }
        } catch { }
    }

    $replies = @()
    try {
        if ($Ticket.PSObject.Properties.Name -contains "Replies") {
            $replies = @($Ticket.Replies)
        }
    } catch { $replies = @() }

    foreach ($reply in $replies) {
        if ($null -eq $reply) { continue }

        $replyDate = [datetime]::MinValue
        foreach ($propName in @("CreatedAt", "Date", "Timestamp")) {
            try {
                if ($reply.PSObject.Properties.Name -contains $propName) {
                    $replyDate = Convert-QOTicketDateValue -Value $reply.$propName
                    if ($replyDate -gt [datetime]::MinValue) { break }
                }
            } catch { }
        }

        if ($replyDate -le [datetime]::MinValue) { continue }
        if (($firstReplyAt -eq [datetime]::MinValue) -or ($replyDate -lt $firstReplyAt)) {
            $firstReplyAt = $replyDate
        }
    }

    return $firstReplyAt
}

function Test-QOTicketClosedStatus {
    param([AllowNull()][string]$Status)

    $statusValue = ([string]($Status + "")).Trim().ToLowerInvariant()
    return ($statusValue -eq "closed" -or $statusValue -eq "completed")
}

function Get-QOTicketAnalyticsPeriodStart {
    param(
        [ValidateSet("All", "Year", "Month", "Week", "Day")]
        [string]$Range = "All",
        [datetime]$Now = (Get-Date)
    )

    switch ($Range) {
        "Year"  { return [datetime]::new($Now.Year, 1, 1, 0, 0, 0) }
        "Month" { return [datetime]::new($Now.Year, $Now.Month, 1, 0, 0, 0) }
        "Week"  {
            # Monday-based week start for consistency.
            $deltaDays = ([int]$Now.DayOfWeek + 6) % 7
            return $Now.Date.AddDays(-$deltaDays)
        }
        "Day"   { return $Now.Date }
        default { return [datetime]::MinValue }
    }
}

function Get-QOTicketsByAnalyticsRange {
    param(
        [AllowNull()]$Tickets,
        [ValidateSet("All", "Year", "Month", "Week", "Day")]
        [string]$Range = "All",
        [datetime]$Now = (Get-Date),
        [switch]$IncludeDeleted
    )

    $periodStart = Get-QOTicketAnalyticsPeriodStart -Range $Range -Now $Now
    $items = @()

    foreach ($ticket in @($Tickets)) {
        if (-not $ticket) { continue }
        if (-not $IncludeDeleted -and [bool]$ticket.IsDeleted) { continue }

        if ($Range -ne "All") {
            $createdAt = Get-QOTicketCreatedDateTime -Ticket $ticket
            if ($createdAt -le [datetime]::MinValue) { continue }
            if ($createdAt -lt $periodStart) { continue }
        }

        $items += @($ticket)
    }

    return @($items)
}

function Get-QOTicketAnalyticsSnapshot {
    param(
        [ValidateSet("All", "Year", "Month", "Week", "Day")]
        [string]$Range = "All"
    )

    $now = Get-Date
    $periodStart = Get-QOTicketAnalyticsPeriodStart -Range $Range -Now $now

    $db = Get-QOTickets -Quiet
    $tickets = @(Get-QOTicketsByAnalyticsRange -Tickets $db.Tickets -Range $Range -Now $now)

    $totalCount = @($tickets).Count
    $closedTickets = @($tickets | Where-Object { Test-QOTicketClosedStatus -Status ([string]$_.Status) })
    $pendingTickets = @($tickets | Where-Object { ([string]($_.Status + "")).Trim().ToLowerInvariant() -eq "pending" })
    $openTickets = @(
        $tickets |
            Where-Object {
                $statusValue = ([string]($_.Status + "")).Trim().ToLowerInvariant()
                (-not (Test-QOTicketClosedStatus -Status $statusValue)) -and ($statusValue -ne "pending")
            }
    )

    $openAgeMinutes = @()
    foreach ($ticket in $openTickets) {
        $createdAt = Get-QOTicketCreatedDateTime -Ticket $ticket
        if ($createdAt -le [datetime]::MinValue) { continue }
        if ($createdAt -gt $now) { continue }
        $openAgeMinutes += @([double](($now - $createdAt).TotalMinutes))
    }

    $pendingAgeMinutes = @()
    foreach ($ticket in $pendingTickets) {
        $createdAt = Get-QOTicketCreatedDateTime -Ticket $ticket
        if ($createdAt -le [datetime]::MinValue) { continue }
        if ($createdAt -gt $now) { continue }
        $pendingAgeMinutes += @([double](($now - $createdAt).TotalMinutes))
    }

    $firstReplyMinutes = @()
    foreach ($ticket in $tickets) {
        $createdAt = Get-QOTicketCreatedDateTime -Ticket $ticket
        $firstReplyAt = Get-QOTicketFirstReplyDateTime -Ticket $ticket
        if ($createdAt -le [datetime]::MinValue) { continue }
        if ($firstReplyAt -le [datetime]::MinValue) { continue }
        if ($firstReplyAt -lt $createdAt) { continue }
        $firstReplyMinutes += @([double](($firstReplyAt - $createdAt).TotalMinutes))
    }

    $averageValue = {
        param([AllowNull()]$Values)
        $set = @($Values)
        if ($set.Count -eq 0) { return 0.0 }
        $avg = 0.0
        try { $avg = [double](($set | Measure-Object -Average).Average) } catch { $avg = 0.0 }
        return [double][math]::Round($avg, 1)
    }

    $assigneeCounts = @{}
    foreach ($ticket in $tickets) {
        $assignee = "Unassigned"
        try {
            if ($ticket.PSObject.Properties.Name -contains "AssignedTo") {
                $assignee = Normalize-QOTicketAssignee -AssignedTo ([string]$ticket.AssignedTo)
            } else {
                $assignee = "Unassigned"
            }
        } catch { $assignee = "Unassigned" }

        if ($assigneeCounts.ContainsKey($assignee)) {
            $assigneeCounts[$assignee] = [int]$assigneeCounts[$assignee] + 1
        } else {
            $assigneeCounts[$assignee] = 1
        }
    }

    $userCounts = @(
        $assigneeCounts.GetEnumerator() |
            Sort-Object @{ Expression = { [int]$_.Value }; Descending = $true }, @{ Expression = { [string]$_.Key }; Descending = $false } |
            ForEach-Object {
                [pscustomobject]@{
                    Name  = [string]$_.Key
                    Count = [int]$_.Value
                }
            }
    )

    return [pscustomobject]@{
        Range                     = [string]$Range
        GeneratedAt               = $now.ToString("yyyy-MM-dd HH:mm:ss")
        PeriodStart               = if ($periodStart -gt [datetime]::MinValue) { $periodStart.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        TotalTickets              = [int]$totalCount
        OpenTickets               = [int]@($openTickets).Count
        PendingTickets            = [int]@($pendingTickets).Count
        ClosedTickets             = [int]@($closedTickets).Count
        AverageOpenAgeHours       = [double][math]::Round((& $averageValue -Values $openAgeMinutes) / 60.0, 2)
        AveragePendingAgeHours    = [double][math]::Round((& $averageValue -Values $pendingAgeMinutes) / 60.0, 2)
        AverageFirstReplyMinutes  = [double](& $averageValue -Values $firstReplyMinutes)
        FirstReplySamples         = [int]@($firstReplyMinutes).Count
        UserCounts                = @($userCounts)
    }
}

function Export-QOTicketsToExcelSpreadsheet {
    param(
        [AllowNull()][string]$Path,
        [ValidateSet("All", "Year", "Month", "Week", "Day")]
        [string]$Range = "All",
        [switch]$IncludeDeleted
    )

    $targetPath = ([string]($Path + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        $documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        if ([string]::IsNullOrWhiteSpace($documentsPath)) {
            $documentsPath = Join-Path $env:USERPROFILE "Documents"
        }
        $targetPath = Join-Path $documentsPath ("QOT_Tickets_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    }

    $requestedExt = ([string]([System.IO.Path]::GetExtension($targetPath))).ToLowerInvariant()
    if ($requestedExt -ne ".csv") {
        $targetPath = [System.IO.Path]::ChangeExtension($targetPath, ".csv")
    }

    $targetDir = Split-Path -Parent $targetPath
    if (-not [string]::IsNullOrWhiteSpace($targetDir) -and (-not (Test-Path -LiteralPath $targetDir))) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $db = Get-QOTickets -Quiet
    $records = @()
    $now = Get-Date
    $tickets = @(Get-QOTicketsByAnalyticsRange -Tickets $db.Tickets -Range $Range -Now $now -IncludeDeleted:$IncludeDeleted)

    foreach ($ticket in @($tickets)) {
        if ($null -eq $ticket) { continue }

        $createdAt = Get-QOTicketCreatedDateTime -Ticket $ticket
        $updatedAt = Get-QOTicketUpdatedDateTime -Ticket $ticket
        $firstReplyAt = Get-QOTicketFirstReplyDateTime -Ticket $ticket
        $isClosed = Test-QOTicketClosedStatus -Status ([string]$ticket.Status)

        $openHours = ""
        if ($createdAt -gt [datetime]::MinValue) {
            if ($isClosed -and ($updatedAt -gt [datetime]::MinValue) -and ($updatedAt -ge $createdAt)) {
                $openHours = [math]::Round((($updatedAt - $createdAt).TotalHours), 2)
            } elseif (-not $isClosed) {
                $openHours = [math]::Round((($now - $createdAt).TotalHours), 2)
            }
        }

        $pendingHours = ""
        $statusValue = ([string]($ticket.Status + "")).Trim()
        if ($statusValue.ToLowerInvariant() -eq "pending" -and $createdAt -gt [datetime]::MinValue) {
            $pendingHours = [math]::Round((($now - $createdAt).TotalHours), 2)
        }

        $firstReplyMins = ""
        if ($createdAt -gt [datetime]::MinValue -and $firstReplyAt -gt [datetime]::MinValue -and $firstReplyAt -ge $createdAt) {
            $firstReplyMins = [math]::Round((($firstReplyAt - $createdAt).TotalMinutes), 1)
        }

        $replyCount = 0
        try { if ($ticket.PSObject.Properties.Name -contains "Replies") { $replyCount = @($ticket.Replies).Count } } catch { $replyCount = 0 }
        $noteCount = 0
        try { if ($ticket.PSObject.Properties.Name -contains "Notes") { $noteCount = @($ticket.Notes).Count } } catch { $noteCount = 0 }

        $records += [pscustomobject]@{
            Id                = [string]($ticket.Id + "")
            Subject           = [string]($ticket.Subject + "")
            Status            = $statusValue
            Priority          = [string]($ticket.Priority + "")
            AssignedTo        = Normalize-QOTicketAssignee -AssignedTo ([string]($ticket.AssignedTo + ""))
            Source            = [string]($ticket.Source + "")
            CreatedAt         = if ($createdAt -gt [datetime]::MinValue) { $createdAt.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
            UpdatedAt         = if ($updatedAt -gt [datetime]::MinValue) { $updatedAt.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
            IsClosed          = [bool]$isClosed
            IsDeleted         = [bool]$ticket.IsDeleted
            DeletedAt         = [string]($ticket.DeletedAt + "")
            OpenHours         = $openHours
            PendingHours      = $pendingHours
            FirstReplyMinutes = $firstReplyMins
            ReplyCount        = [int]$replyCount
            NoteCount         = [int]$noteCount
            EmailFrom         = [string]($ticket.EmailFrom + "")
            EmailTo           = [string]($ticket.EmailTo + "")
            Title             = [string]($ticket.Title + "")
            TicketName        = [string]($ticket.TicketName + "")
        }
    }

    $records | Export-Csv -LiteralPath $targetPath -NoTypeInformation -Encoding UTF8

    $note = "CSV exported for Excel."
    if ($requestedExt -ne ".csv" -and -not [string]::IsNullOrWhiteSpace($requestedExt)) {
        $note = ("Requested '{0}' but exported CSV for Excel compatibility." -f $requestedExt)
    }

    return [pscustomobject]@{
        Success        = $true
        Path           = $targetPath
        Count          = [int]@($records).Count
        Format         = "CSV"
        Range          = [string]$Range
        IncludeDeleted = [bool]$IncludeDeleted
        Note           = $note
    }
}

function Get-QOTicketsByBucket {
    param(
        [string]$Bucket = "All"
    )

    $bucketValue = if ([string]::IsNullOrWhiteSpace([string]$Bucket)) { "All" } else { ([string]$Bucket).Trim() }
    $allowedBuckets = @("Open", "Closed", "Deleted", "All")
    if ($allowedBuckets -notcontains $bucketValue) {
        Write-QOTicketsCoreLog ("Tickets: Invalid bucket '{0}' supplied. Falling back to All." -f $bucketValue) "WARN"
        $bucketValue = "All"
    }
    $db = Get-QOTickets -Quiet
    $items = @($db.Tickets)
    $totalCount = 0
    try { $totalCount = $items.Count } catch { }
    Write-QOTicketsCoreLog ("Tickets: Filtering bucket '{0}'. Total before filter={1}." -f $bucketValue, $totalCount)

    switch ($bucketValue) {
        "Open" {
            return @(
                $items | Where-Object {
                    $_ -and (-not [bool]$_.IsDeleted) -and ($_.Status -ne "Closed") -and ($_.Status -ne "Completed")
                }
            )
        }
        "Closed" {
            return @(
                $items | Where-Object {
                    $_ -and (-not [bool]$_.IsDeleted) -and (($_.Status -eq "Closed") -or ($_.Status -eq "Completed"))
                }
            )
        }
        "Deleted" {
            return @(
                $items | Where-Object {
                    $_ -and ([bool]$_.IsDeleted)
                }
            )
        }
        "All" {
            return @($items)
        }
    }
}


function Get-QOTicketsByFolder {
    param(
        [ValidateSet("Active", "Deleted")]
        [string]$Folder = "Active"
    )

    $db = Get-QOTickets -Quiet
    $totalCount = 0
    try { $totalCount = @($db.Tickets).Count } catch { }
    Write-QOTicketsCoreLog ("Tickets: Filtering folder '{0}'. Total before filter={1}." -f $Folder, $totalCount)
    $folderValue = if ([string]::IsNullOrWhiteSpace($Folder)) { "Active" } else { [string]$Folder }

    return @(
        $db.Tickets |
            Where-Object { $_ -and ($_.Folder -eq $folderValue) }
    )
}

function Get-QOTicketsFiltered {
    param(
        [string[]]$Status,
        [bool]$IncludeDeleted
    )

    $db = Get-QOTickets -Quiet
    
    $statuses = $null
    if ($null -ne $Status) {
        $statuses = @(
            $Status |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                ForEach-Object { [string]$_ }
        )
    } else {
        $statuses = @($script:ValidTicketStatuses)
    }
    if ($statuses.Count -eq 0) {
        $statuses = @($script:ValidTicketStatuses)
    }

    $includeDeleted = [bool]$IncludeDeleted

    $matchesAllStatuses = $false
    if ($statuses.Count -ge $script:ValidTicketStatuses.Count) {
        $matchCount = @(
            $script:ValidTicketStatuses |
                Where-Object { $statuses -contains $_ }
        ).Count
        $matchesAllStatuses = ($matchCount -eq $script:ValidTicketStatuses.Count)
    }

    $items = @(
        $db.Tickets |
            Where-Object { $_ }
    )

    if (-not $matchesAllStatuses) {
        $items = @(
            $items |
                Where-Object { $statuses -contains $_.Status }
        )
    }

    return @(
        $items |
            Where-Object { $includeDeleted -or (-not [bool]$_.IsDeleted) }
    )
}

# =====================================================================
# Settings bridge for monitored addresses
# =====================================================================
function Get-QOTMonitoredMailboxAddresses {
    # Prefer dedicated Settings function if available
    if (Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction SilentlyContinue) {
        $a = @(Get-QOMonitoredMailboxAddresses)
        return @(
            $a |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
        )
    }

    # Fallback (should not really happen now)
    $s = Get-QOTicketsSettingsObject
    if (-not $s) { return @() }

    try {
        $list = @($s.Tickets.EmailIntegration.MonitoredAddresses)
        return @(
            $list |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
        )
    } catch {
        return @()
    }
}

# =====================================================================
# Email ticket creation (PowerShell 5.1 safe)
# =====================================================================
function Add-QOTicketFromEmail {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Email
    )

    $subject  = ""
    $from     = ""
    $to       = ""
    $body     = ""
    $msgId    = ""
    $received = $null
    $priority = ""

    try {
        if ($Email.PSObject.Properties.Name -contains "Subject") {
            $subject = [string]$Email.Subject
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "From") {
            $from = [string]$Email.From
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "To") {
            $to = $Email.To
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "Body") {
            $body = [string]$Email.Body
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "Snippet") {
            if (-not $body) {
                $body = [string]$Email.Snippet
            }
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "MessageId") {
            $msgId = [string]$Email.MessageId
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "Received") {
            $received = $Email.Received
        }
    } catch { }
    try {
        if ($Email.PSObject.Properties.Name -contains "Priority") {
            $priority = [string]$Email.Priority
        }
    } catch { }
    try {
        if (-not $priority -and $Email.PSObject.Properties.Name -contains "Importance") {
            $importanceValue = ([string]$Email.Importance).Trim().ToLowerInvariant()
            if ($importanceValue -eq "high") {
                $priority = "High"
            } elseif ($importanceValue -eq "low") {
                $priority = "Low"
            }
        }
    } catch { }

    $subject = ($subject + "").Trim()
    $from    = ($from + "").Trim()
    $msgId   = ($msgId + "").Trim()

    if ($to -is [System.Array]) { $to = ($to -join "; ") }
    $to = ([string]($to + "")).Trim()

    if (-not $received) { $received = Get-Date }
    if ([string]::IsNullOrWhiteSpace($subject)) { $subject = "(No subject)" }
    if ([string]::IsNullOrWhiteSpace($from))    { $from = "Unknown sender" }

    $db = Get-QOTickets -Quiet

    # Dedup by MessageId
    if ($msgId) {
        foreach ($t in @($db.Tickets)) {
            try {
                if (($t.Source -eq "Email") -and ($t.EmailMessageId -eq $msgId)) {
                    return $t
                }
            } catch { }
        }
    }

    $ticket = [pscustomobject]@{
        Id             = ([guid]::NewGuid().ToString())
        Title          = $subject
        TicketName     = $subject
        Subject        = $subject
        Status         = "New"
        CreatedAt      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        UpdatedAt      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Priority       = (Normalize-QOTicketPriority -Priority $priority -Subject $subject -Status "New")
        AssignedTo     = "Unassigned"
        Source         = "Email"
        Folder         = "Active"
        DeletedAt      = $null
        IsDeleted      = $false
        EmailFrom      = $from
        EmailTo        = $to
        EmailReceived  = $received
        EmailMessageId = $msgId
        EmailBody      = $body
        Notes          = @()
        Replies        = @()
        PendingReplies = @()
    }

    $db.Tickets = @($db.Tickets) + @($ticket)
    Save-QOTickets -Database $db

    return $ticket
}

# =====================================================================
# Sync stub (so UI can call it without exploding)
# =====================================================================
function Sync-QOTicketsFromEmail {
    param(
        [int]$MaxPerMailbox = 250,
        [switch]$MarkAsRead,
        [switch]$AllowStartOutlook
    )

    try {
        if ($MaxPerMailbox -lt 1) { $MaxPerMailbox = 1 }
        if ($MaxPerMailbox -gt 500) { $MaxPerMailbox = 500 }
        $null = Import-QOTOutlookIntegrationModule
        if (-not (Get-Command Sync-QOTicketsFromOutlook -ErrorAction SilentlyContinue)) {
            return [pscustomobject]@{ Success = $false; Added = 0; Note = "Outlook sync function not loaded." }
        }

        $r = Sync-QOTicketsFromOutlook -MaxPerMailbox $MaxPerMailbox -MarkAsRead:$MarkAsRead -AllowStartOutlook:$AllowStartOutlook
        if (-not $r) { $r = [pscustomobject]@{ Success = $false; Added = 0; Note = "Outlook sync returned nothing." } }
        if ($r -and ($r.PSObject.Properties.Name -notcontains "Success")) {
            $derivedSuccess = $true
            try {
                $noteValue = ""
                if ($r.PSObject.Properties.Name -contains "Note") { $noteValue = [string]$r.Note }
                if ($noteValue -match '(?i)\b(failed|unavailable|not loaded|not found|required)\b') {
                    $derivedSuccess = $false
                }
            } catch { }
            try { $r | Add-Member -NotePropertyName Success -NotePropertyValue $derivedSuccess -Force } catch { }
        }

        return $r
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Added = 0
            Note  = ("Sync failed: " + $_.Exception.Message)
        }
    }
}

function Add-QOTicketNote {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Note,
        [string]$Author = "User",
        [AllowNull()][string]$NoteId
    )

    $idValue = ([string]$Id).Trim()
    $noteValue = ([string]$Note).Trim()
    $authorValue = ([string]$Author).Trim()
    $noteIdValue = ([string]($NoteId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($authorValue)) { $authorValue = "User" }
    if ([string]::IsNullOrWhiteSpace($noteIdValue)) { $noteIdValue = [guid]::NewGuid().ToString("N") }

    if ([string]::IsNullOrWhiteSpace($idValue)) {
        throw "Ticket id is required."
    }
    if ([string]::IsNullOrWhiteSpace($noteValue)) {
        throw "Note text is required."
    }

    $db = Get-QOTickets -Quiet
    $updatedTicket = $null
    $nowStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $storePathForLog = ""
    try { $storePathForLog = [string](Get-QOTicketsStorePath) } catch { $storePathForLog = "" }
    try { Write-QOTicketsCoreLog ("Tickets: Add internal note requested. TicketId='{0}' NoteId='{1}' StorePath='{2}'." -f $idValue, $noteIdValue, $storePathForLog) } catch { }

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ([string]$ticket.Id -ne $idValue) { continue }

        if (-not ($ticket.PSObject.Properties.Name -contains "Notes")) {
            $ticket | Add-Member -NotePropertyName Notes -NotePropertyValue @() -Force
        }

        $entry = [pscustomobject]@{
            NoteId    = $noteIdValue
            Body      = $noteValue
            CreatedAt = $nowStamp
            Author    = $authorValue
            Type      = "InternalNote"
            EntryType = "InternalNote"
        }

        $existingNotes = @()
        try { $existingNotes = @($ticket.Notes | Where-Object { $_ }) } catch { $existingNotes = @() }
        $alreadyExists = $false
        foreach ($existingNote in @($existingNotes)) {
            if (-not $existingNote) { continue }
            $existingNoteId = ""
            try { if ($existingNote.PSObject.Properties.Name -contains "NoteId") { $existingNoteId = ([string]($existingNote.NoteId + "")).Trim() } } catch { $existingNoteId = "" }
            if (-not [string]::IsNullOrWhiteSpace($existingNoteId) -and [string]::Equals($existingNoteId, $noteIdValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                $alreadyExists = $true
                break
            }
        }

        if (-not $alreadyExists) {
            $ticket.Notes = @($existingNotes) + @($entry)
        }
        try { Write-QOTicketsCoreLog ("Tickets: Internal note linked. TicketId='{0}' NoteId='{1}' Collection='Notes' NoteCount={2} DuplicateSuppressed={3}." -f $idValue, $noteIdValue, @($ticket.Notes).Count, $alreadyExists) } catch { }
        if ($ticket.PSObject.Properties.Name -contains "UpdatedAt") {
            $ticket.UpdatedAt = $nowStamp
        } else {
            $ticket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue $nowStamp -Force
        }
        $updatedTicket = $ticket
        break
    }

    if (-not $updatedTicket) {
        throw ("Ticket not found: " + $idValue)
    }

    Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
    try { Write-QOTicketsCoreLog ("Tickets: Internal note persisted. TicketId='{0}' NoteId='{1}' Collection='Notes' StorePath='{2}'." -f $idValue, $noteIdValue, $storePathForLog) } catch { }
    return $updatedTicket
}

function Remove-QOTicketNote {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][Alias("ClientNoteId")][string]$NoteId
    )

    $idValue = ([string]$Id).Trim()
    $noteIdValue = ([string]($NoteId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($idValue)) { throw "Ticket id is required." }
    if ([string]::IsNullOrWhiteSpace($noteIdValue)) { throw "Note id is required." }

    $db = Get-QOTickets -Quiet
    $updatedTicket = $null
    $removedCount = 0
    $nowStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $storePathForLog = ""
    try { $storePathForLog = [string](Get-QOTicketsStorePath) } catch { $storePathForLog = "" }
    try { Write-QOTicketsCoreLog ("Tickets: Delete internal note requested. TicketId='{0}' NoteId='{1}' StorePath='{2}'." -f $idValue, $noteIdValue, $storePathForLog) } catch { }

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ([string]$ticket.Id -ne $idValue) { continue }

        foreach ($collectionName in @("Notes", "InternalNotes")) {
            if (-not ($ticket.PSObject.Properties.Name -contains $collectionName)) { continue }

            $remainingNotes = @()
            foreach ($existingNote in @($ticket.$collectionName)) {
                if (-not $existingNote) { continue }
                $matchesNote = $false
                foreach ($noteIdProp in @("NoteId", "ClientNoteId", "Id")) {
                    $existingNoteId = ""
                    try {
                        if ($existingNote.PSObject.Properties.Name -contains $noteIdProp) {
                            $existingNoteId = ([string]($existingNote.$noteIdProp + "")).Trim()
                        }
                    } catch { $existingNoteId = "" }
                    if (-not [string]::IsNullOrWhiteSpace($existingNoteId) -and [string]::Equals($existingNoteId, $noteIdValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $matchesNote = $true
                        break
                    }
                }
                if ($matchesNote) {
                    $removedCount++
                    continue
                }
                $remainingNotes += $existingNote
            }

            try { $ticket.$collectionName = @($remainingNotes) } catch { }
        }

        if ($removedCount -gt 0) {
            if ($ticket.PSObject.Properties.Name -contains "UpdatedAt") {
                $ticket.UpdatedAt = $nowStamp
            } else {
                $ticket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue $nowStamp -Force
            }
        }
        $updatedTicket = $ticket
        break
    }

    if (-not $updatedTicket) {
        throw ("Ticket not found: " + $idValue)
    }

    if ($removedCount -gt 0) {
        Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
    }
    try { Write-QOTicketsCoreLog ("Tickets: Internal note delete persisted. TicketId='{0}' NoteId='{1}' Removed={2} StorePath='{3}'." -f $idValue, $noteIdValue, $removedCount, $storePathForLog) } catch { }

    return [pscustomobject]@{
        TicketId = $idValue
        NoteId   = $noteIdValue
        Removed  = ($removedCount -gt 0)
        Count    = $removedCount
        Ticket   = $updatedTicket
    }
}

function Rename-QOTicket {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    $db = Get-QOTickets
    $updated = $false
    $nowStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    foreach ($ticket in @($db.Tickets)) {
        if ($null -eq $ticket) { continue }
        if ($ticket.Id -ne $Id) { continue }

        $ticket.TicketName = $Name
        $ticket.Title = $Name
        $ticket.Subject = $Name
        $ticket.UpdatedAt = $nowStamp
        $updated = $true
        break
    }

    if ($updated) {
        Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
    }

    return $updated
}

function Test-QOTicketHasReplyReference {
    param(
        [AllowNull()]$Ticket
    )

    if (-not $Ticket) { return $false }

    try {
        if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") {
            if (-not [string]::IsNullOrWhiteSpace([string]$Ticket.SourceMessageId)) {
                return $true
            }
        }
    } catch { }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailMessageId") {
            if (-not [string]::IsNullOrWhiteSpace([string]$Ticket.EmailMessageId)) {
                return $true
            }
        }
    } catch { }

    return $false
}

function Normalize-QOTicketEmailAddress {
    param(
        [AllowNull()][string]$Value
    )

    $rawValue = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($rawValue)) { return "" }

    $match = [regex]::Match($rawValue, '(?i)([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})')
    if (-not $match.Success) { return "" }

    return ([string]$match.Groups[1].Value).Trim().ToLowerInvariant()
}

function Get-QOTicketPrimaryEmailAddress {
    param(
        [AllowNull()]$Ticket
    )

    if (-not $Ticket) { return "" }

    foreach ($propName in @("EmailTo", "SenderEmail", "ContactEmail", "EmailFrom")) {
        $rawValue = ""
        try {
            if ($Ticket.PSObject.Properties.Name -contains $propName) {
                $rawValue = ([string]($Ticket.$propName + "")).Trim()
            }
        } catch { $rawValue = "" }

        if ([string]::IsNullOrWhiteSpace($rawValue)) { continue }
        $match = [regex]::Match($rawValue, '(?i)([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})')
        if ($match.Success) {
            return ([string]$match.Groups[1].Value).Trim()
        }
    }

    return ""
}

function Test-QOTicketPrefersOutboundEmailSend {
    param(
        [AllowNull()]$Ticket
    )

    if (-not $Ticket) { return $false }
    if (-not (Test-QOTicketHasReplyReference -Ticket $Ticket)) { return $false }

    $mailboxAddress = Normalize-QOTicketEmailAddress -Value (Get-QOTicketPreferredSenderMailbox -Ticket $Ticket)
    if ([string]::IsNullOrWhiteSpace($mailboxAddress)) {
        try {
            if ($Ticket.PSObject.Properties.Name -contains "SourceMailbox") {
                $mailboxAddress = Normalize-QOTicketEmailAddress -Value ([string]$Ticket.SourceMailbox)
            }
        } catch { $mailboxAddress = "" }
    }
    if ([string]::IsNullOrWhiteSpace($mailboxAddress)) { return $false }

    $fromAddress = ""
    foreach ($propName in @("SenderEmail", "EmailFrom")) {
        try {
            if ([string]::IsNullOrWhiteSpace($fromAddress) -and $Ticket.PSObject.Properties.Name -contains $propName) {
                $fromAddress = Normalize-QOTicketEmailAddress -Value ([string]$Ticket.$propName)
            }
        } catch { }
    }

    $toAddress = ""
    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailTo") {
            $toAddress = Normalize-QOTicketEmailAddress -Value ([string]$Ticket.EmailTo)
        }
    } catch { $toAddress = "" }

    return (
        -not [string]::IsNullOrWhiteSpace($fromAddress) -and
        -not [string]::IsNullOrWhiteSpace($toAddress) -and
        $fromAddress -eq $mailboxAddress -and
        $toAddress -eq $mailboxAddress
    )
}

function Get-QOTicketPreferredSenderMailbox {
    param(
        [AllowNull()]$Ticket
    )

    $sourceMailbox = ""
    try {
        if ($Ticket -and ($Ticket.PSObject.Properties.Name -contains "SourceMailbox")) {
            $sourceMailbox = ([string]($Ticket.SourceMailbox + "")).Trim()
        }
    } catch { $sourceMailbox = "" }
    if (-not [string]::IsNullOrWhiteSpace($sourceMailbox)) {
        return $sourceMailbox
    }

    $configuredMailboxes = @(Get-QOTMonitoredMailboxAddresses)
    if ($configuredMailboxes.Count -eq 1) {
        return ([string]$configuredMailboxes[0]).Trim()
    }

    return ""
}

function Normalize-QOTTicketPendingReplyState {
    param([AllowNull()][string]$SendState)

    $stateValue = ([string]($SendState + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($stateValue)) { return "Queued" }

    switch ($stateValue.ToLowerInvariant()) {
        "pending" { return "Queued" }
        "queued"  { return "Queued" }
        "sending" { return "Sending" }
        "sent"    { return "Sent" }
        "failed"  { return "Failed" }
        default   { return "Queued" }
    }
}

function Get-QOTTicketPendingReplyTimestampUtc {
    param([AllowNull()]$Value)

    $rawValue = ""
    try { $rawValue = ([string]($Value + "")).Trim() } catch { $rawValue = "" }
    if ([string]::IsNullOrWhiteSpace($rawValue)) { return [datetime]::MinValue }

    $parsed = [datetime]::MinValue
    try {
        if ([datetime]::TryParse($rawValue, [ref]$parsed)) {
            if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) {
                $parsed = [datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Local)
            }
            return $parsed.ToUniversalTime()
        }
    } catch { }

    return [datetime]::MinValue
}

function Get-QOTTicketPendingReplyContentKey {
    param(
        [AllowNull()][string]$Subject,
        [AllowNull()][string]$Body,
        [AllowNull()][string]$To
    )

    $subjectValue = ([string]($Subject + "")).Trim().ToLowerInvariant()
    $toValue = ([string]($To + "")).Trim().ToLowerInvariant()
    $bodyValue = [string]($Body + "")
    $bodyValue = $bodyValue.Replace("`r`n", "`n").Replace("`r", "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($bodyValue)) { return "" }

    return ($toValue + "`n" + $subjectValue + "`n" + $bodyValue)
}

function Get-QOTTicketPendingReplyMetadataFromTicket {
    param(
        [AllowNull()]$Ticket
    )

    $result = [pscustomobject]@{
        To              = ""
        MessageId       = ""
        ConversationId  = ""
        SourceMessageId = ""
        SenderMailbox   = ""
    }

    if (-not $Ticket) { return $result }

    try {
        $toValue = ""
        try { $toValue = [string](Get-QOTicketPrimaryEmailAddress -Ticket $Ticket) } catch { $toValue = "" }
        if ([string]::IsNullOrWhiteSpace($toValue)) {
            foreach ($propName in @("CustomerEmail", "ContactEmail", "RequesterEmail", "RequestEmail", "EmailTo")) {
                try {
                    if ($Ticket.PSObject.Properties.Name -contains $propName) {
                        $candidate = ([string]($Ticket.$propName + "")).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                            $toValue = $candidate
                            break
                        }
                    }
                } catch { }
            }
        }
        $result.To = ([string]($toValue + "")).Trim()
    } catch { }

    foreach ($mapping in @(
            @{ Result = "MessageId"; Source = "EmailMessageId" },
            @{ Result = "ConversationId"; Source = "EmailConversationId" },
            @{ Result = "SourceMessageId"; Source = "SourceMessageId" }
        )) {
        try {
            $sourceName = [string]$mapping.Source
            if ($Ticket.PSObject.Properties.Name -contains $sourceName) {
                $value = ([string]($Ticket.$sourceName + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $result.$([string]$mapping.Result) = $value
                }
            }
        } catch { }
    }

    try {
        $senderMailbox = ""
        try { $senderMailbox = [string](Get-QOTicketPreferredSenderMailbox -Ticket $Ticket) } catch { $senderMailbox = "" }
        if ([string]::IsNullOrWhiteSpace($senderMailbox)) {
            try {
                if ($Ticket.PSObject.Properties.Name -contains "SourceMailbox") {
                    $senderMailbox = ([string]($Ticket.SourceMailbox + "")).Trim()
                }
            } catch { $senderMailbox = "" }
        }
        $result.SenderMailbox = ([string]($senderMailbox + "")).Trim()
    } catch { }

    return $result
}

function New-QOTTicketReplyWorkerPayload {
    param(
        [Parameter(Mandatory)]$Ticket,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [AllowNull()][string]$PendingReplyDraftId
    )

    $subjectValue = ([string]($Subject + "")).Trim()
    $bodyValue = [string]($Body + "")
    if ([string]::IsNullOrWhiteSpace($subjectValue)) { throw "Reply subject is required." }
    if ([string]::IsNullOrWhiteSpace($bodyValue.Trim())) { throw "Reply body is required." }

    $ticketId = ""
    $sourceMessageId = ""
    $sourceStoreId = ""
    $emailMessageId = ""
    try { if ($Ticket.PSObject.Properties.Name -contains "Id") { $ticketId = ([string]($Ticket.Id + "")).Trim() } } catch { $ticketId = "" }
    try { if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") { $sourceMessageId = ([string]($Ticket.SourceMessageId + "")).Trim() } } catch { $sourceMessageId = "" }
    try { if ($Ticket.PSObject.Properties.Name -contains "SourceStoreId") { $sourceStoreId = ([string]($Ticket.SourceStoreId + "")).Trim() } } catch { $sourceStoreId = "" }
    try { if ($Ticket.PSObject.Properties.Name -contains "EmailMessageId") { $emailMessageId = ([string]($Ticket.EmailMessageId + "")).Trim() } } catch { $emailMessageId = "" }

    return [pscustomobject]@{
        TicketId            = $ticketId
        PendingReplyDraftId = ([string]($PendingReplyDraftId + "")).Trim()
        Subject             = $subjectValue
        Body                = $bodyValue
        To                  = [string](Get-QOTicketPrimaryEmailAddress -Ticket $Ticket)
        SenderMailbox       = [string](Get-QOTicketPreferredSenderMailbox -Ticket $Ticket)
        SourceMessageId     = $sourceMessageId
        SourceStoreId       = $sourceStoreId
        EmailMessageId      = $emailMessageId
    }
}

function Get-QOTicketPendingReplies {
    param(
        [AllowNull()][string]$TicketId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $db = Get-QOTickets -Quiet
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($ticket in @($db.Tickets)) {
        if (-not $ticket) { continue }

        $currentTicketId = ""
        try { if ($ticket.PSObject.Properties.Name -contains "Id") { $currentTicketId = ([string]($ticket.Id + "")).Trim() } } catch { $currentTicketId = "" }
        if ([string]::IsNullOrWhiteSpace($currentTicketId)) { continue }
        if (-not [string]::IsNullOrWhiteSpace($resolvedTicketId) -and -not [string]::Equals($currentTicketId, $resolvedTicketId, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $pendingReplies = @()
        try {
            if ($ticket.PSObject.Properties.Name -contains "PendingReplies") {
                $pendingReplies = @($ticket.PendingReplies)
            }
        } catch { $pendingReplies = @() }

        foreach ($pending in $pendingReplies) {
            if (-not $pending) { continue }

            $draftId = ""
            $replyIdValue = ""
            $subjectValue = ""
            $bodyValue = ""
            $toValue = ""
            $messageIdValue = ""
            $conversationIdValue = ""
            $sourceMessageIdValue = ""
            $senderMailboxValue = ""
            $createdAtValue = ""
            $lastAttemptAtValue = ""
            $nextAttemptAtValue = ""
            $failureNoteValue = ""
            $lastErrorValue = ""
            $retryCountValue = 0
            $sendStateValue = "Queued"
            $sentAtValue = ""

            try { if ($pending.PSObject.Properties.Name -contains "DraftId") { $draftId = ([string]($pending.DraftId + "")).Trim() } } catch { $draftId = "" }
            try { if ($pending.PSObject.Properties.Name -contains "ReplyId") { $replyIdValue = ([string]($pending.ReplyId + "")).Trim() } } catch { $replyIdValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "Subject") { $subjectValue = ([string]($pending.Subject + "")).Trim() } } catch { $subjectValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "Body") { $bodyValue = [string]($pending.Body + "") } } catch { $bodyValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "To") { $toValue = ([string]($pending.To + "")).Trim() } } catch { $toValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "MessageId") { $messageIdValue = ([string]($pending.MessageId + "")).Trim() } } catch { $messageIdValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "ConversationId") { $conversationIdValue = ([string]($pending.ConversationId + "")).Trim() } } catch { $conversationIdValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "SourceMessageId") { $sourceMessageIdValue = ([string]($pending.SourceMessageId + "")).Trim() } } catch { $sourceMessageIdValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "SenderMailbox") { $senderMailboxValue = ([string]($pending.SenderMailbox + "")).Trim() } } catch { $senderMailboxValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "CreatedAt") { $createdAtValue = ([string]($pending.CreatedAt + "")).Trim() } } catch { $createdAtValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "LastAttemptAt") { $lastAttemptAtValue = ([string]($pending.LastAttemptAt + "")).Trim() } } catch { $lastAttemptAtValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "NextAttemptAt") { $nextAttemptAtValue = ([string]($pending.NextAttemptAt + "")).Trim() } } catch { $nextAttemptAtValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "FailureNote") { $failureNoteValue = ([string]($pending.FailureNote + "")).Trim() } } catch { $failureNoteValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "LastError") { $lastErrorValue = ([string]($pending.LastError + "")).Trim() } } catch { $lastErrorValue = "" }
            try { if ($pending.PSObject.Properties.Name -contains "RetryCount") { $retryCountValue = [int]$pending.RetryCount } } catch { $retryCountValue = 0 }
            try { if ($pending.PSObject.Properties.Name -contains "SendState") { $sendStateValue = Normalize-QOTTicketPendingReplyState -SendState ([string]$pending.SendState) } } catch { $sendStateValue = "Queued" }
            try { if ($pending.PSObject.Properties.Name -contains "SentAt") { $sentAtValue = ([string]($pending.SentAt + "")).Trim() } } catch { $sentAtValue = "" }

            if ([string]::IsNullOrWhiteSpace($draftId)) { $draftId = [guid]::NewGuid().ToString("N") }
            if ([string]::IsNullOrWhiteSpace($replyIdValue)) { $replyIdValue = $draftId }
            if ([string]::IsNullOrWhiteSpace($createdAtValue)) { $createdAtValue = (Get-Date).ToUniversalTime().ToString("o") }
            if ([string]::IsNullOrWhiteSpace($lastAttemptAtValue)) { $lastAttemptAtValue = $createdAtValue }
            if ([string]::IsNullOrWhiteSpace($lastErrorValue)) { $lastErrorValue = $failureNoteValue }

            $results.Add([pscustomobject]@{
                ReplyId        = $replyIdValue
                TicketId       = $currentTicketId
                DraftId        = $draftId
                Subject        = $subjectValue
                Body           = $bodyValue
                To             = $toValue
                MessageId      = $messageIdValue
                ConversationId = $conversationIdValue
                SourceMessageId = $sourceMessageIdValue
                SenderMailbox  = $senderMailboxValue
                CreatedAt      = $createdAtValue
                LastAttemptAt  = $lastAttemptAtValue
                NextAttemptAt  = $nextAttemptAtValue
                SendState      = $sendStateValue
                FailureNote    = $failureNoteValue
                LastError      = $lastErrorValue
                RetryCount     = $retryCountValue
                SentAt         = $sentAtValue
            }) | Out-Null
        }
    }

    try { return @($results.ToArray()) } catch { return @() }
}

function Add-QOTTicketPendingReply {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [AllowNull()][string]$DraftId,
        [AllowNull()][string]$SendState = "Queued",
        [AllowNull()]$Ticket
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $subjectValue = ([string]($Subject + "")).Trim()
    $bodyValue = [string]($Body + "")
    $draftKey = ([string]($DraftId + "")).Trim()
    $stateValue = Normalize-QOTTicketPendingReplyState -SendState $SendState
    $nowStamp = (Get-Date).ToUniversalTime().ToString("o")

    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) { throw "Ticket Id is required." }
    if ([string]::IsNullOrWhiteSpace($subjectValue)) { throw "Reply subject is required." }
    if ([string]::IsNullOrWhiteSpace($bodyValue.Trim())) { throw "Reply body is required." }
    if ([string]::IsNullOrWhiteSpace($draftKey)) { $draftKey = [guid]::NewGuid().ToString("N") }

    $db = Get-QOTickets -Quiet
    $updated = $false
    $savedEntry = $null
    $duplicateSuppressed = $false

    foreach ($ticket in @($db.Tickets)) {
        if (-not $ticket) { continue }

        $currentTicketId = ""
        try { if ($ticket.PSObject.Properties.Name -contains "Id") { $currentTicketId = ([string]($ticket.Id + "")).Trim() } } catch { $currentTicketId = "" }
        if (-not [string]::Equals($currentTicketId, $resolvedTicketId, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        if (-not ($ticket.PSObject.Properties.Name -contains "PendingReplies")) {
            $ticket | Add-Member -NotePropertyName PendingReplies -NotePropertyValue @() -Force
        }

        $pendingReplies = @()
        try { $pendingReplies = @($ticket.PendingReplies) } catch { $pendingReplies = @() }
        $metadataTicket = $Ticket
        if (-not $metadataTicket) { $metadataTicket = $ticket }
        $pendingMetadata = Get-QOTTicketPendingReplyMetadataFromTicket -Ticket $metadataTicket
        $contentKey = Get-QOTTicketPendingReplyContentKey -Subject $subjectValue -Body $bodyValue -To ([string]$pendingMetadata.To)

        $entryUpdated = $false
        foreach ($pending in $pendingReplies) {
            if (-not $pending) { continue }
            $pendingDraftId = ""
            try { if ($pending.PSObject.Properties.Name -contains "DraftId") { $pendingDraftId = ([string]($pending.DraftId + "")).Trim() } } catch { $pendingDraftId = "" }
            if (-not [string]::Equals($pendingDraftId, $draftKey, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

            try { $pending.ReplyId = $draftKey } catch { $pending | Add-Member -NotePropertyName ReplyId -NotePropertyValue $draftKey -Force }
            try { $pending.DraftId = $draftKey } catch { }
            try { $pending.Subject = $subjectValue } catch { }
            try { $pending.Body = $bodyValue } catch { }
            try { $pending.SendState = $stateValue } catch { }
            try { $pending.FailureNote = "" } catch { }
            try { $pending.LastError = "" } catch { $pending | Add-Member -NotePropertyName LastError -NotePropertyValue "" -Force }
            try {
                if (-not ($pending.PSObject.Properties.Name -contains "CreatedAt") -or [string]::IsNullOrWhiteSpace([string]$pending.CreatedAt)) {
                    $pending | Add-Member -NotePropertyName CreatedAt -NotePropertyValue $nowStamp -Force
                }
            } catch { }
            try { $pending.LastAttemptAt = $nowStamp } catch { $pending | Add-Member -NotePropertyName LastAttemptAt -NotePropertyValue $nowStamp -Force }
            try { $pending.NextAttemptAt = "" } catch { $pending | Add-Member -NotePropertyName NextAttemptAt -NotePropertyValue "" -Force }
            try { $pending.SentAt = "" } catch { $pending | Add-Member -NotePropertyName SentAt -NotePropertyValue "" -Force }
            try {
                if (-not ($pending.PSObject.Properties.Name -contains "RetryCount")) {
                    $pending | Add-Member -NotePropertyName RetryCount -NotePropertyValue 0 -Force
                }
            } catch { }
            foreach ($metadataProp in @("To", "MessageId", "ConversationId", "SourceMessageId", "SenderMailbox")) {
                $metadataValue = ""
                try { $metadataValue = ([string]($pendingMetadata.$metadataProp + "")).Trim() } catch { $metadataValue = "" }
                if ([string]::IsNullOrWhiteSpace($metadataValue)) { continue }
                try {
                    if ($pending.PSObject.Properties.Name -contains $metadataProp) {
                        if ([string]::IsNullOrWhiteSpace([string]$pending.$metadataProp)) {
                            $pending.$metadataProp = $metadataValue
                        }
                    } else {
                        $pending | Add-Member -NotePropertyName $metadataProp -NotePropertyValue $metadataValue -Force
                    }
                } catch { }
            }

            $savedEntry = [pscustomobject]@{
                ReplyId       = $draftKey
                TicketId      = $resolvedTicketId
                DraftId       = $draftKey
                Subject       = $subjectValue
                Body          = $bodyValue
                To            = [string]$pending.To
                MessageId     = [string]$pending.MessageId
                ConversationId = [string]$pending.ConversationId
                SourceMessageId = [string]$pending.SourceMessageId
                SenderMailbox = [string]$pending.SenderMailbox
                CreatedAt     = [string]$pending.CreatedAt
                LastAttemptAt = $nowStamp
                NextAttemptAt = ""
                SendState     = $stateValue
                FailureNote   = ""
                LastError     = ""
                RetryCount    = [int]$pending.RetryCount
                SentAt        = ""
                DuplicateSuppressed = $false
            }
            $entryUpdated = $true
            break
        }

        if (-not $entryUpdated -and -not [string]::IsNullOrWhiteSpace($contentKey)) {
            foreach ($pending in $pendingReplies) {
                if (-not $pending) { continue }
                $pendingStateValue = "Queued"
                try { if ($pending.PSObject.Properties.Name -contains "SendState") { $pendingStateValue = Normalize-QOTTicketPendingReplyState -SendState ([string]$pending.SendState) } } catch { $pendingStateValue = "Queued" }
                if ($pendingStateValue -notmatch '^(?i)(Queued|Sending)$') { continue }

                $pendingContentTo = ""
                try { if ($pending.PSObject.Properties.Name -contains "To") { $pendingContentTo = ([string]($pending.To + "")).Trim() } } catch { $pendingContentTo = "" }
                $pendingContentKey = Get-QOTTicketPendingReplyContentKey -Subject ([string]($pending.Subject + "")) -Body ([string]($pending.Body + "")) -To $pendingContentTo
                if ([string]::IsNullOrWhiteSpace($pendingContentKey)) { continue }
                if (-not [string]::Equals($pendingContentKey, $contentKey, [System.StringComparison]::Ordinal)) { continue }

                $duplicateDraftId = ""
                try { if ($pending.PSObject.Properties.Name -contains "DraftId") { $duplicateDraftId = ([string]($pending.DraftId + "")).Trim() } } catch { $duplicateDraftId = "" }
                if ([string]::IsNullOrWhiteSpace($duplicateDraftId)) { $duplicateDraftId = $draftKey }
                $duplicateReplyId = $duplicateDraftId
                try {
                    if ($pending.PSObject.Properties.Name -contains "ReplyId") {
                        $candidateReplyId = ([string]($pending.ReplyId + "")).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($candidateReplyId)) { $duplicateReplyId = $candidateReplyId }
                    }
                } catch { }

                $savedEntry = [pscustomobject]@{
                    ReplyId       = $duplicateReplyId
                    TicketId      = $resolvedTicketId
                    DraftId       = $duplicateDraftId
                    Subject       = [string]($pending.Subject + "")
                    Body          = [string]($pending.Body + "")
                    To            = [string]($(if ($pending.PSObject.Properties.Name -contains "To") { $pending.To } else { "" }) + "")
                    MessageId     = [string]($(if ($pending.PSObject.Properties.Name -contains "MessageId") { $pending.MessageId } else { "" }) + "")
                    ConversationId = [string]($(if ($pending.PSObject.Properties.Name -contains "ConversationId") { $pending.ConversationId } else { "" }) + "")
                    SourceMessageId = [string]($(if ($pending.PSObject.Properties.Name -contains "SourceMessageId") { $pending.SourceMessageId } else { "" }) + "")
                    SenderMailbox = [string]($(if ($pending.PSObject.Properties.Name -contains "SenderMailbox") { $pending.SenderMailbox } else { "" }) + "")
                    CreatedAt     = [string]($(if ($pending.PSObject.Properties.Name -contains "CreatedAt") { $pending.CreatedAt } else { $nowStamp }) + "")
                    LastAttemptAt = [string]($(if ($pending.PSObject.Properties.Name -contains "LastAttemptAt") { $pending.LastAttemptAt } else { $nowStamp }) + "")
                    NextAttemptAt = [string]($(if ($pending.PSObject.Properties.Name -contains "NextAttemptAt") { $pending.NextAttemptAt } else { "" }) + "")
                    SendState     = $pendingStateValue
                    FailureNote   = [string]($(if ($pending.PSObject.Properties.Name -contains "FailureNote") { $pending.FailureNote } else { "" }) + "")
                    LastError     = [string]($(if ($pending.PSObject.Properties.Name -contains "LastError") { $pending.LastError } elseif ($pending.PSObject.Properties.Name -contains "FailureNote") { $pending.FailureNote } else { "" }) + "")
                    RetryCount    = $(try { [int]$pending.RetryCount } catch { 0 })
                    SentAt        = [string]($(if ($pending.PSObject.Properties.Name -contains "SentAt") { $pending.SentAt } else { "" }) + "")
                    DuplicateSuppressed = $true
                }
                $duplicateSuppressed = $true
                break
            }
        }

        if ($duplicateSuppressed) {
            try {
                Write-QOTicketsCoreLog ("Tickets: Duplicate pending reply suppressed. TicketId='{0}' DraftId='{1}' ExistingDraftId='{2}'." -f $resolvedTicketId, $draftKey, [string]$savedEntry.DraftId)
            } catch { }
            return $savedEntry
        }

        if (-not $entryUpdated) {
            $savedEntry = [pscustomobject]@{
                ReplyId       = $draftKey
                TicketId      = $resolvedTicketId
                DraftId       = $draftKey
                Subject       = $subjectValue
                Body          = $bodyValue
                To            = [string]$pendingMetadata.To
                MessageId     = [string]$pendingMetadata.MessageId
                ConversationId = [string]$pendingMetadata.ConversationId
                SourceMessageId = [string]$pendingMetadata.SourceMessageId
                SenderMailbox = [string]$pendingMetadata.SenderMailbox
                CreatedAt     = $nowStamp
                LastAttemptAt = $nowStamp
                NextAttemptAt = ""
                SendState     = $stateValue
                FailureNote   = ""
                LastError     = ""
                RetryCount    = 0
                SentAt        = ""
                DuplicateSuppressed = $false
            }
            $pendingReplies = @($pendingReplies) + @([pscustomobject]@{
                ReplyId       = $savedEntry.ReplyId
                DraftId       = $savedEntry.DraftId
                Subject       = $savedEntry.Subject
                Body          = $savedEntry.Body
                To            = $savedEntry.To
                MessageId     = $savedEntry.MessageId
                ConversationId = $savedEntry.ConversationId
                SourceMessageId = $savedEntry.SourceMessageId
                SenderMailbox = $savedEntry.SenderMailbox
                CreatedAt     = $savedEntry.CreatedAt
                LastAttemptAt = $savedEntry.LastAttemptAt
                NextAttemptAt = $savedEntry.NextAttemptAt
                SendState     = $savedEntry.SendState
                FailureNote   = $savedEntry.FailureNote
                RetryCount    = $savedEntry.RetryCount
                LastError     = $savedEntry.LastError
                SentAt        = $savedEntry.SentAt
            })
            $ticket.PendingReplies = @($pendingReplies)
        } else {
            $ticket.PendingReplies = @($pendingReplies)
        }

        try {
            if ($ticket.PSObject.Properties.Name -contains "UpdatedAt") {
                $ticket.UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            } else {
                $ticket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Force
            }
        } catch { }

        $updated = $true
        break
    }

    if (-not $updated) { throw ("Ticket not found: " + $resolvedTicketId) }

    Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
    return $savedEntry
}

function Set-QOTTicketPendingReplyState {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId,
        [Parameter(Mandatory)][ValidateSet("Pending","Queued","Sending","Sent","Failed")][string]$SendState,
        [AllowNull()][string]$FailureNote,
        [int]$RetryCount = -1,
        [AllowNull()][string]$NextAttemptAt = "",
        [AllowNull()][string]$SentAt = ""
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $draftKey = ([string]($DraftId + "")).Trim()
    $stateValue = Normalize-QOTTicketPendingReplyState -SendState $SendState
    $failureNoteValue = ([string]($FailureNote + "")).Trim()
    $nowStamp = (Get-Date).ToUniversalTime().ToString("o")

    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) { return $null }
    if ([string]::IsNullOrWhiteSpace($draftKey)) { return $null }

    $db = Get-QOTickets -Quiet
    $savedEntry = $null

    foreach ($ticket in @($db.Tickets)) {
        if (-not $ticket) { continue }

        $currentTicketId = ""
        try { if ($ticket.PSObject.Properties.Name -contains "Id") { $currentTicketId = ([string]($ticket.Id + "")).Trim() } } catch { $currentTicketId = "" }
        if (-not [string]::Equals($currentTicketId, $resolvedTicketId, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not ($ticket.PSObject.Properties.Name -contains "PendingReplies")) { return $null }

        $pendingReplies = @($ticket.PendingReplies)
        foreach ($pending in $pendingReplies) {
            if (-not $pending) { continue }
            $pendingDraftId = ""
            try { if ($pending.PSObject.Properties.Name -contains "DraftId") { $pendingDraftId = ([string]($pending.DraftId + "")).Trim() } } catch { $pendingDraftId = "" }
            if (-not [string]::Equals($pendingDraftId, $draftKey, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

            $previousStateValue = ""
            try {
                if ($pending.PSObject.Properties.Name -contains "SendState") {
                    $previousStateValue = Normalize-QOTTicketPendingReplyState -SendState ([string]$pending.SendState)
                }
            } catch { $previousStateValue = "" }
            try { $pending.SendState = $stateValue } catch { $pending | Add-Member -NotePropertyName SendState -NotePropertyValue $stateValue -Force }
            try { $pending.LastAttemptAt = $nowStamp } catch { $pending | Add-Member -NotePropertyName LastAttemptAt -NotePropertyValue $nowStamp -Force }
            try { $pending.FailureNote = $failureNoteValue } catch { $pending | Add-Member -NotePropertyName FailureNote -NotePropertyValue $failureNoteValue -Force }
            try { $pending.LastError = $failureNoteValue } catch { $pending | Add-Member -NotePropertyName LastError -NotePropertyValue $failureNoteValue -Force }
            if ($RetryCount -ge 0) {
                try { $pending.RetryCount = [int]$RetryCount } catch { $pending | Add-Member -NotePropertyName RetryCount -NotePropertyValue ([int]$RetryCount) -Force }
            } elseif ($pending.PSObject.Properties.Name -notcontains "RetryCount") {
                try { $pending | Add-Member -NotePropertyName RetryCount -NotePropertyValue 0 -Force } catch { }
            }
            try { $pending.NextAttemptAt = ([string]($NextAttemptAt + "")).Trim() } catch { $pending | Add-Member -NotePropertyName NextAttemptAt -NotePropertyValue ([string]($NextAttemptAt + "")).Trim() -Force }
            $sentStampValue = ([string]($SentAt + "")).Trim()
            if ([string]::Equals($stateValue, "Sent", [System.StringComparison]::OrdinalIgnoreCase) -and [string]::IsNullOrWhiteSpace($sentStampValue)) {
                $sentStampValue = $nowStamp
            }
            try { $pending.SentAt = $sentStampValue } catch { $pending | Add-Member -NotePropertyName SentAt -NotePropertyValue $sentStampValue -Force }
            try {
                if (-not ($pending.PSObject.Properties.Name -contains "ReplyId")) {
                    $pending | Add-Member -NotePropertyName ReplyId -NotePropertyValue $draftKey -Force
                }
            } catch { }

            $savedEntry = [pscustomobject]@{
                ReplyId       = [string]($(if ($pending.PSObject.Properties.Name -contains "ReplyId") { $pending.ReplyId } else { $draftKey }) + "")
                TicketId      = $resolvedTicketId
                DraftId       = $draftKey
                Subject       = [string]($pending.Subject + "")
                Body          = [string]($pending.Body + "")
                To            = [string]($(if ($pending.PSObject.Properties.Name -contains "To") { $pending.To } else { "" }) + "")
                MessageId     = [string]($(if ($pending.PSObject.Properties.Name -contains "MessageId") { $pending.MessageId } else { "" }) + "")
                ConversationId = [string]($(if ($pending.PSObject.Properties.Name -contains "ConversationId") { $pending.ConversationId } else { "" }) + "")
                SourceMessageId = [string]($(if ($pending.PSObject.Properties.Name -contains "SourceMessageId") { $pending.SourceMessageId } else { "" }) + "")
                SenderMailbox = [string]($(if ($pending.PSObject.Properties.Name -contains "SenderMailbox") { $pending.SenderMailbox } else { "" }) + "")
                CreatedAt     = [string]($pending.CreatedAt + "")
                LastAttemptAt = [string]($pending.LastAttemptAt + "")
                NextAttemptAt = [string]($pending.NextAttemptAt + "")
                SendState     = $stateValue
                FailureNote   = $failureNoteValue
                LastError     = $failureNoteValue
                RetryCount    = [int]$pending.RetryCount
                SentAt        = [string]($pending.SentAt + "")
                DuplicateSuppressed = $false
            }

            $ticket.PendingReplies = @($pendingReplies)
            try {
                if ($ticket.PSObject.Properties.Name -contains "UpdatedAt") {
                    $ticket.UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                } else {
                    $ticket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Force
                }
            } catch { }

            Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
            try {
                Write-QOTicketsCoreLog ("Tickets: Pending reply state changed. TicketId='{0}' DraftId='{1}' From='{2}' To='{3}' RetryCount={4} Note='{5}'." -f `
                    $resolvedTicketId, `
                    $draftKey, `
                    $(if ([string]::IsNullOrWhiteSpace($previousStateValue)) { "(unknown)" } else { $previousStateValue }), `
                    $stateValue, `
                    [int]$savedEntry.RetryCount, `
                    $failureNoteValue)
            } catch { }
            return $savedEntry
        }
    }

    return $null
}

function Remove-QOTTicketPendingReply {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $draftKey = ([string]($DraftId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) { return $false }
    if ([string]::IsNullOrWhiteSpace($draftKey)) { return $false }

    $db = Get-QOTickets -Quiet
    $removed = $false

    foreach ($ticket in @($db.Tickets)) {
        if (-not $ticket) { continue }

        $currentTicketId = ""
        try { if ($ticket.PSObject.Properties.Name -contains "Id") { $currentTicketId = ([string]($ticket.Id + "")).Trim() } } catch { $currentTicketId = "" }
        if (-not [string]::Equals($currentTicketId, $resolvedTicketId, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not ($ticket.PSObject.Properties.Name -contains "PendingReplies")) { return $false }

        $remainingReplies = @()
        foreach ($pending in @($ticket.PendingReplies)) {
            if (-not $pending) { continue }
            $pendingDraftId = ""
            try { if ($pending.PSObject.Properties.Name -contains "DraftId") { $pendingDraftId = ([string]($pending.DraftId + "")).Trim() } } catch { $pendingDraftId = "" }
            if ([string]::Equals($pendingDraftId, $draftKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                $removed = $true
                continue
            }
            $remainingReplies += $pending
        }

        if ($removed) {
            $ticket.PendingReplies = @($remainingReplies)
            try {
                if ($ticket.PSObject.Properties.Name -contains "UpdatedAt") {
                    $ticket.UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                } else {
                    $ticket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Force
                }
            } catch { }

            Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
            try { Write-QOTicketsCoreLog ("Tickets: Pending reply removed from storage. TicketId='{0}' DraftId='{1}'." -f $resolvedTicketId, $draftKey) } catch { }
        }

        break
    }

    return $removed
}

function Get-QOTNextPendingReply {
    param(
        [int]$StaleSendingSeconds = 600
    )

    $nowUtc = (Get-Date).ToUniversalTime()
    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($entry in @(Get-QOTicketPendingReplies)) {
        if (-not $entry) { continue }

        $stateValue = Normalize-QOTTicketPendingReplyState -SendState ([string]$entry.SendState)
        if ($stateValue -eq "Failed") { continue }

        $createdUtc = Get-QOTTicketPendingReplyTimestampUtc -Value $entry.CreatedAt
        if ($createdUtc -eq [datetime]::MinValue) { $createdUtc = $nowUtc }
        $lastAttemptUtc = Get-QOTTicketPendingReplyTimestampUtc -Value $entry.LastAttemptAt
        $nextAttemptUtc = Get-QOTTicketPendingReplyTimestampUtc -Value $entry.NextAttemptAt
        if ($nextAttemptUtc -ne [datetime]::MinValue -and $nextAttemptUtc -gt $nowUtc) { continue }

        $eligible = $false
        $isStaleStale = $false
        if ($stateValue -eq "Queued") {
            $eligible = $true
        } elseif ($stateValue -eq "Sending") {
            if ($lastAttemptUtc -eq [datetime]::MinValue) {
                $eligible = $true
                $isStaleStale = $true
            } else {
                $elapsedSeconds = ($nowUtc - $lastAttemptUtc).TotalSeconds
                if ($elapsedSeconds -ge $StaleSendingSeconds) {
                    $eligible = $true
                    $isStaleStale = $true
                }
            }
        }

        if (-not $eligible) { continue }

        # If this was a stale "Sending" reply, reset it to "Queued" in the database
        # This prevents the entry from getting stuck in "Sending" state if the queue runner crashes
        if ($isStaleStale) {
            try {
                $ticketId = [string]$entry.TicketId
                $draftId = [string]$entry.DraftId
                $retryCount = 0
                try { $retryCount = [int]$entry.RetryCount } catch { $retryCount = 0 }
                Set-QOTTicketPendingReplyState -TicketId $ticketId -DraftId $draftId -SendState "Queued" -FailureNote "" -RetryCount $retryCount -NextAttemptAt ""
            } catch { }
        }

        $candidates.Add([pscustomobject]@{
            TicketId       = [string]$entry.TicketId
            DraftId        = [string]$entry.DraftId
            Subject        = [string]$entry.Subject
            Body           = [string]$entry.Body
            CreatedAt      = [string]$entry.CreatedAt
            LastAttemptAt  = [string]$entry.LastAttemptAt
            NextAttemptAt  = [string]$entry.NextAttemptAt
            SendState      = "Queued"
            FailureNote    = [string]$entry.FailureNote
            RetryCount     = [int]$entry.RetryCount
            SortCreatedUtc = $createdUtc
        }) | Out-Null
    }

    $nextEntry = @(
        $candidates |
            Sort-Object -Property @(
                @{ Expression = { $_.SortCreatedUtc } ; Descending = $false },
                @{ Expression = { [int]$_.RetryCount } ; Descending = $false },
                @{ Expression = { [string]$_.DraftId } ; Descending = $false }
            ) |
            Select-Object -First 1
    )

    if ($nextEntry.Count -eq 0) { return $null }
    return $nextEntry[0]
}

function Get-QOTTicketsReplyQueueMutexName {
    Initialize-QOTicketStorage

    $storePath = ""
    try { $storePath = [string](Get-QOTicketsStorePath) } catch { $storePath = "" }
    if ([string]::IsNullOrWhiteSpace($storePath)) {
        $storePath = "qot-ticket-store"
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($storePath.ToLowerInvariant())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        $hashHex = ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
        return ("Global\QOTReplyQueue_" + $hashHex.Substring(0, 24))
    } finally {
        try { $sha.Dispose() } catch { }
    }
}

function Get-QOTTicketPendingReply {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $draftKey = ([string]($DraftId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId) -or [string]::IsNullOrWhiteSpace($draftKey)) { return $null }

    return @(
        Get-QOTicketPendingReplies -TicketId $resolvedTicketId |
            Where-Object {
                if (-not $_) { return $false }
                $entryDraftId = ""
                try { if ($_.PSObject.Properties.Name -contains "DraftId") { $entryDraftId = ([string]($_.DraftId + "")).Trim() } } catch { $entryDraftId = "" }
                return [string]::Equals($entryDraftId, $draftKey, [System.StringComparison]::OrdinalIgnoreCase)
            } |
            Select-Object -First 1
    )[0]
}

function Get-QOTPendingReplyQueueSnapshot {
    param(
        [AllowNull()][string]$TicketId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $entries = New-Object System.Collections.Generic.List[object]
    $pendingReplies = @()

    try {
        if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) {
            $pendingReplies = @(Get-QOTicketPendingReplies)
        } else {
            $pendingReplies = @(Get-QOTicketPendingReplies -TicketId $resolvedTicketId)
        }
    } catch { $pendingReplies = @() }

    $queueCandidates = New-Object System.Collections.Generic.List[object]
    $queueKeyIndex = @{}
    foreach ($entry in @($pendingReplies)) {
        if (-not $entry) { continue }

        $entryTicketId = ""
        $entryDraftId = ""
        $entrySubject = ""
        $entryBody = ""
        $createdAt = ""
        $lastAttemptAt = ""
        $nextAttemptAt = ""
        $failureNote = ""
        $retryCount = 0
        try { if ($entry.PSObject.Properties.Name -contains "TicketId") { $entryTicketId = ([string]($entry.TicketId + "")).Trim() } } catch { $entryTicketId = "" }
        try { if ($entry.PSObject.Properties.Name -contains "DraftId") { $entryDraftId = ([string]($entry.DraftId + "")).Trim() } } catch { $entryDraftId = "" }
        try { if ($entry.PSObject.Properties.Name -contains "Subject") { $entrySubject = ([string]($entry.Subject + "")).Trim() } } catch { $entrySubject = "" }
        try { if ($entry.PSObject.Properties.Name -contains "Body") { $entryBody = [string]($entry.Body + "") } } catch { $entryBody = "" }
        try { if ($entry.PSObject.Properties.Name -contains "CreatedAt") { $createdAt = ([string]($entry.CreatedAt + "")).Trim() } } catch { $createdAt = "" }
        try { if ($entry.PSObject.Properties.Name -contains "LastAttemptAt") { $lastAttemptAt = ([string]($entry.LastAttemptAt + "")).Trim() } } catch { $lastAttemptAt = "" }
        try { if ($entry.PSObject.Properties.Name -contains "NextAttemptAt") { $nextAttemptAt = ([string]($entry.NextAttemptAt + "")).Trim() } } catch { $nextAttemptAt = "" }
        try { if ($entry.PSObject.Properties.Name -contains "FailureNote") { $failureNote = ([string]($entry.FailureNote + "")).Trim() } } catch { $failureNote = "" }
        try { if ($entry.PSObject.Properties.Name -contains "RetryCount") { $retryCount = [int]$entry.RetryCount } } catch { $retryCount = 0 }

        $stateValue = Normalize-QOTTicketPendingReplyState -SendState ([string]$entry.SendState)
        $isFailed = $stateValue -eq "Failed"
        $isSending = $stateValue -eq "Sending"
        $isQueued = $stateValue -eq "Queued"
        $isActive = $isQueued -or $isSending
        $createdUtc = Get-QOTTicketPendingReplyTimestampUtc -Value $createdAt
        if ($createdUtc -eq [datetime]::MinValue) {
            $createdUtc = Get-QOTTicketPendingReplyTimestampUtc -Value $lastAttemptAt
        }
        if ($createdUtc -eq [datetime]::MinValue) {
            $createdUtc = (Get-Date).ToUniversalTime()
        }

        $queueKey = ($entryTicketId.ToLowerInvariant() + "|" + $entryDraftId.ToLowerInvariant())
        if ($isActive -and -not [string]::IsNullOrWhiteSpace($entryDraftId)) {
            $queueCandidates.Add([pscustomobject]@{
                QueueKey      = $queueKey
                SortStateRank = $(if ($isSending) { 0 } else { 1 })
                SortCreatedUtc = $createdUtc
                RetryCount    = $retryCount
                DraftId       = $entryDraftId
            }) | Out-Null
        }

        $entries.Add([pscustomobject]@{
            TicketId       = $entryTicketId
            DraftId        = $entryDraftId
            Subject        = $entrySubject
            Body           = $entryBody
            CreatedAt      = $createdAt
            LastAttemptAt  = $lastAttemptAt
            NextAttemptAt  = $nextAttemptAt
            SendState      = $stateValue
            FailureNote    = $failureNote
            RetryCount     = $retryCount
            QueueKey       = $queueKey
            QueuePosition  = 0
            QueueTotal     = 0
            IsQueued       = $isQueued
            IsSending      = $isSending
            IsFailed       = $isFailed
            IsActive       = $isActive
        }) | Out-Null
    }

    $queueOrderedEntries = @(
        $queueCandidates |
            Sort-Object -Property @(
                @{ Expression = { [int]$_.SortStateRank } ; Descending = $false },
                @{ Expression = { $_.SortCreatedUtc } ; Descending = $false },
                @{ Expression = { [int]$_.RetryCount } ; Descending = $false },
                @{ Expression = { [string]$_.DraftId } ; Descending = $false }
            )
    )
    $queuePosition = 0
    foreach ($queuedEntry in $queueOrderedEntries) {
        if (-not $queuedEntry) { continue }
        $queueKey = ""
        try { $queueKey = [string]$queuedEntry.QueueKey } catch { $queueKey = "" }
        if ([string]::IsNullOrWhiteSpace($queueKey)) { continue }
        $queuePosition++
        $queueKeyIndex[$queueKey] = $queuePosition
    }

    $queueTotal = $queueKeyIndex.Count
    $resultEntries = New-Object System.Collections.Generic.List[object]
    $queuedCount = 0
    $sendingCount = 0
    $failedCount = 0
    foreach ($entry in @($entries.ToArray())) {
        if (-not $entry) { continue }

        $entryQueuePosition = 0
        try {
            if ($entry.IsActive -and $queueKeyIndex.ContainsKey([string]$entry.QueueKey)) {
                $entryQueuePosition = [int]$queueKeyIndex[[string]$entry.QueueKey]
            }
        } catch { $entryQueuePosition = 0 }

        if ($entry.IsQueued) { $queuedCount++ }
        if ($entry.IsSending) { $sendingCount++ }
        if ($entry.IsFailed) { $failedCount++ }

        $resultEntries.Add([pscustomobject]@{
            TicketId       = [string]$entry.TicketId
            DraftId        = [string]$entry.DraftId
            Subject        = [string]$entry.Subject
            Body           = [string]$entry.Body
            CreatedAt      = [string]$entry.CreatedAt
            LastAttemptAt  = [string]$entry.LastAttemptAt
            NextAttemptAt  = [string]$entry.NextAttemptAt
            SendState      = [string]$entry.SendState
            FailureNote    = [string]$entry.FailureNote
            RetryCount     = [int]$entry.RetryCount
            QueuePosition  = $entryQueuePosition
            QueueTotal     = $(if ($entry.IsActive) { $queueTotal } else { 0 })
            IsQueued       = [bool]$entry.IsQueued
            IsSending      = [bool]$entry.IsSending
            IsFailed       = [bool]$entry.IsFailed
            IsActive       = [bool]$entry.IsActive
        }) | Out-Null
    }

    return [pscustomobject]@{
        Entries      = @($resultEntries.ToArray())
        TotalCount   = @($pendingReplies).Count
        ActiveCount  = $queueTotal
        QueuedCount  = $queuedCount
        SendingCount = $sendingCount
        FailedCount  = $failedCount
        WorkerRunning = [bool](Test-QOTicketsReplyQueueWorkerRunning)
    }
}

function Repair-QOTPendingReplyQueueState {
    param(
        [int]$StaleSendingSeconds = 600,
        [switch]$RecoverOrphanedSending,
        [switch]$Quiet
    )

    if ($StaleSendingSeconds -lt 30) { $StaleSendingSeconds = 30 }

    $workerRunning = $false
    try { $workerRunning = [bool](Test-QOTicketsReplyQueueWorkerRunning) } catch { $workerRunning = $false }

    $db = Get-QOTickets -Quiet
    $updated = $false
    $normalizedCount = 0
    $recoveredCount = 0
    $removedCount = 0
    $nowUtc = (Get-Date).ToUniversalTime()

    foreach ($ticket in @($db.Tickets)) {
        if (-not $ticket) { continue }
        if (-not ($ticket.PSObject.Properties.Name -contains "PendingReplies")) { continue }

        $ticketId = ""
        try { if ($ticket.PSObject.Properties.Name -contains "Id") { $ticketId = ([string]($ticket.Id + "")).Trim() } } catch { $ticketId = "" }
        $cleanPendingReplies = New-Object System.Collections.Generic.List[object]

        foreach ($pending in @($ticket.PendingReplies)) {
            if (-not $pending) { continue }

            $draftId = ""
            try { if ($pending.PSObject.Properties.Name -contains "DraftId") { $draftId = ([string]($pending.DraftId + "")).Trim() } } catch { $draftId = "" }
            if ([string]::IsNullOrWhiteSpace($draftId)) {
                try { $draftId = [guid]::NewGuid().ToString("N") } catch { $draftId = ([string](Get-Date -Format "yyyyMMddHHmmssfff")) }
                try { $pending | Add-Member -NotePropertyName DraftId -NotePropertyValue $draftId -Force } catch { }
                $updated = $true
                $normalizedCount++
                try { Write-QOTicketsCoreLog ("Tickets: Repaired pending reply missing DraftId. TicketId='{0}' DraftId='{1}'." -f $ticketId, $draftId) "WARN" } catch { }
            }

            try {
                if (-not ($pending.PSObject.Properties.Name -contains "ReplyId") -or [string]::IsNullOrWhiteSpace([string]$pending.ReplyId)) {
                    $pending | Add-Member -NotePropertyName ReplyId -NotePropertyValue $draftId -Force
                    $updated = $true
                    $normalizedCount++
                }
            } catch { }

            $bodyValue = ""
            try { if ($pending.PSObject.Properties.Name -contains "Body") { $bodyValue = [string]($pending.Body + "") } } catch { $bodyValue = "" }
            if ([string]::IsNullOrWhiteSpace($bodyValue.Trim())) {
                $updated = $true
                $removedCount++
                try { Write-QOTicketsCoreLog ("Tickets: Removed invalid pending reply without body. TicketId='{0}' DraftId='{1}'." -f $ticketId, $draftId) "WARN" } catch { }
                continue
            }

            $stateValue = "Queued"
            try {
                if ($pending.PSObject.Properties.Name -contains "SendState") {
                    $stateValue = Normalize-QOTTicketPendingReplyState -SendState ([string]$pending.SendState)
                }
            } catch { $stateValue = "Queued" }

            if ([string]::Equals($stateValue, "Pending", [System.StringComparison]::OrdinalIgnoreCase)) {
                try { $pending.SendState = "Queued" } catch { $pending | Add-Member -NotePropertyName SendState -NotePropertyValue "Queued" -Force }
                $updated = $true
                $normalizedCount++
                $stateValue = "Queued"
            }

            $lastAttemptUtc = [datetime]::MinValue
            try {
                if ($pending.PSObject.Properties.Name -contains "LastAttemptAt") {
                    $lastAttemptUtc = Get-QOTTicketPendingReplyTimestampUtc -Value $pending.LastAttemptAt
                }
            } catch { $lastAttemptUtc = [datetime]::MinValue }

            $isStaleSending = $false
            if ([string]::Equals($stateValue, "Sending", [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($lastAttemptUtc -eq [datetime]::MinValue) {
                    $isStaleSending = $true
                } else {
                    try { $isStaleSending = (($nowUtc - $lastAttemptUtc).TotalSeconds -ge $StaleSendingSeconds) } catch { $isStaleSending = $true }
                }
            }

            if ([string]::Equals($stateValue, "Sending", [System.StringComparison]::OrdinalIgnoreCase) -and (($RecoverOrphanedSending -and -not $workerRunning) -or $isStaleSending)) {
                $recoveryNote = "Reply marked failed because the previous background send stopped unexpectedly. Use Retry to queue a clean new attempt."
                try { $pending.SendState = "Failed" } catch { $pending | Add-Member -NotePropertyName SendState -NotePropertyValue "Failed" -Force }
                try { $pending.FailureNote = $recoveryNote } catch { $pending | Add-Member -NotePropertyName FailureNote -NotePropertyValue $recoveryNote -Force }
                try { $pending.LastError = $recoveryNote } catch { $pending | Add-Member -NotePropertyName LastError -NotePropertyValue $recoveryNote -Force }
                try { $pending.NextAttemptAt = "" } catch { $pending | Add-Member -NotePropertyName NextAttemptAt -NotePropertyValue "" -Force }
                $updated = $true
                $recoveredCount++
                try { Write-QOTicketsCoreLog ("Tickets: Marked stuck sending reply as failed. TicketId='{0}' DraftId='{1}' WorkerRunning={2} Stale={3}." -f $ticketId, $draftId, $workerRunning, $isStaleSending) "WARN" } catch { }
            }

            $cleanPendingReplies.Add($pending) | Out-Null
        }

        try { $ticket.PendingReplies = @($cleanPendingReplies.ToArray()) } catch { }
    }

    if ($updated) {
        Save-QOTickets -Database $db -SkipBodyOptimization -Quiet
    }

    if (-not $Quiet -and ($updated -or $normalizedCount -gt 0 -or $recoveredCount -gt 0 -or $removedCount -gt 0)) {
        try {
            Write-QOTicketsCoreLog ("Tickets: Queue repair completed. Updated={0}; Normalized={1}; RecoveredSending={2}; RemovedInvalid={3}; WorkerRunning={4}" -f $updated, $normalizedCount, $recoveredCount, $removedCount, $workerRunning)
        } catch { }
    }

    return [pscustomobject]@{
        Updated         = $updated
        NormalizedCount = $normalizedCount
        RecoveredCount  = $recoveredCount
        RemovedInvalid  = $removedCount
        WorkerRunning   = $workerRunning
    }
}

function Test-QOTicketsReplyQueueWorkerRunning {
    try {
        $mutexName = [string](Get-QOTTicketsReplyQueueMutexName)
        if ([string]::IsNullOrWhiteSpace($mutexName)) { return $false }

        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
        $lockTaken = $false
        try {
            try {
                $lockTaken = $mutex.WaitOne(0, $false)
            } catch [System.Threading.AbandonedMutexException] {
                $lockTaken = $true
            }

            if ($lockTaken) {
                try { $mutex.ReleaseMutex() } catch { }
                return $false
            }

            return $true
        } finally {
            if ($mutex) {
                try { $mutex.Dispose() } catch { }
            }
        }
    } catch {
        return $false
    }
}

function Get-QOTTicketsReplyQueueToolkitRoot {
    $candidateRoots = New-Object System.Collections.Generic.List[string]

    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$PSScriptRoot)) {
            $candidateRoots.Add([string]$PSScriptRoot) | Out-Null
        }
    } catch { }

    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$script:PSScriptRoot)) {
            $candidateRoots.Add([string]$script:PSScriptRoot) | Out-Null
        }
    } catch { }

    try {
        if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Module -and -not [string]::IsNullOrWhiteSpace([string]$MyInvocation.MyCommand.Module.Path)) {
            $candidateRoots.Add((Split-Path -Parent ([string]$MyInvocation.MyCommand.Module.Path))) | Out-Null
        }
    } catch { }

    try {
        $moduleInfo = @(Get-Module Tickets -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($moduleInfo -and -not [string]::IsNullOrWhiteSpace([string]$moduleInfo.Path)) {
            $candidateRoots.Add((Split-Path -Parent ([string]$moduleInfo.Path))) | Out-Null
        }
    } catch { }

    foreach ($moduleRoot in @($candidateRoots)) {
        if ([string]::IsNullOrWhiteSpace([string]$moduleRoot)) { continue }
        try {
            $resolvedRootCandidates = @(
                [string]$moduleRoot,
                (Split-Path -Parent ([string]$moduleRoot)),
                (Split-Path -Parent (Split-Path -Parent ([string]$moduleRoot)))
            )
            foreach ($toolkitRoot in @($resolvedRootCandidates)) {
                if ([string]::IsNullOrWhiteSpace([string]$toolkitRoot)) { continue }
                if (Test-Path -LiteralPath (Join-Path $toolkitRoot "src\Core\Tickets.psm1")) {
                    return $toolkitRoot
                }
            }
        } catch { }
    }

    return ""
}

function Get-QOTTicketsReplyQueueRunnerPath {
    $toolkitRoot = Get-QOTTicketsReplyQueueToolkitRoot
    if ([string]::IsNullOrWhiteSpace($toolkitRoot)) { return "" }

    try {
        $candidatePath = Join-Path $toolkitRoot "src\Tickets\Tickets.Email.ReplyQueueRunner.ps1"
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    } catch { }

    return ""
}

function Get-QOTTicketsWorkerSourcePath {
    $toolkitRoot = Get-QOTTicketsReplyQueueToolkitRoot
    if ([string]::IsNullOrWhiteSpace($toolkitRoot)) { return "" }

    try {
        $candidatePath = Join-Path $toolkitRoot "src\Tickets\Quinn.Tickets.Worker.cs"
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    } catch { }

    return ""
}

function Get-QOTTicketsWorkerExePath {
    try {
        $buildDir = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Bin"
        if (-not (Test-Path -LiteralPath $buildDir)) {
            New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
        }
        return (Join-Path $buildDir "Quinn.Tickets.Worker.exe")
    } catch {
        return ""
    }
}

function Get-QOTTicketsWorkerRuntimeRoot {
    try {
        $runtimeRoot = Join-Path $env:LOCALAPPDATA "QuinnOptimiserToolkit\Runtime\ReplyWorker"
        if (-not (Test-Path -LiteralPath $runtimeRoot)) {
            New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
        }
        return $runtimeRoot
    } catch {
        return $env:TEMP
    }
}

function Get-QOTTicketsWorkerCompilerPath {
    foreach ($candidate in @(
        (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
        (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
    )) {
        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate)) {
                return $candidate
            }
        } catch { }
    }

    try {
        $resolved = Get-Command csc.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved -and -not [string]::IsNullOrWhiteSpace([string]$resolved.Source)) {
            return [string]$resolved.Source
        }
    } catch { }

    return ""
}

function Ensure-QOTTicketsWorker {
    $sourcePath = Get-QOTTicketsWorkerSourcePath
    $exePath = Get-QOTTicketsWorkerExePath
    if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath)) {
        throw "Tickets worker source file is unavailable."
    }
    if ([string]::IsNullOrWhiteSpace($exePath)) {
        throw "Tickets worker output path could not be resolved."
    }

    $mutex = $null
    $lockTaken = $false
    try {
        $mutex = New-Object System.Threading.Mutex($false, "Local\QOTTicketsWorkerBuild")
        try {
            $lockTaken = $mutex.WaitOne(30000, $false)
        } catch [System.Threading.AbandonedMutexException] {
            $lockTaken = $true
        }
        if (-not $lockTaken) {
            throw "Timed out waiting to build the tickets worker."
        }

        $needsBuild = $true
        try {
            if (Test-Path -LiteralPath $exePath) {
                $sourceInfo = Get-Item -LiteralPath $sourcePath -ErrorAction Stop
                $exeInfo = Get-Item -LiteralPath $exePath -ErrorAction Stop
                if ($exeInfo.Length -gt 0 -and $exeInfo.LastWriteTimeUtc -ge $sourceInfo.LastWriteTimeUtc) {
                    $needsBuild = $false
                }
            }
        } catch { $needsBuild = $true }

        if (-not $needsBuild) {
            return $exePath
        }

        $compilerPath = Get-QOTTicketsWorkerCompilerPath
        if ([string]::IsNullOrWhiteSpace($compilerPath) -or -not (Test-Path -LiteralPath $compilerPath)) {
            throw "C# compiler not found for tickets worker build."
        }

        $outputDir = Split-Path -Parent $exePath
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $responsePath = Join-Path $outputDir ("Quinn.Tickets.Worker." + [guid]::NewGuid().ToString("N") + ".rsp")
        try {
            @(
                '/nologo'
                '/target:exe'
                '/optimize+'
                '/utf8output'
                '/langversion:default'
                ('/out:"' + $exePath + '"')
                '/r:System.Runtime.Serialization.dll'
                '/r:System.Security.dll'
                ('"' + $sourcePath + '"')
            ) | Set-Content -LiteralPath $responsePath -Encoding UTF8 -ErrorAction Stop

            $compileOutput = & $compilerPath ("@" + $responsePath) 2>&1
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exePath)) {
                $detail = ""
                try { $detail = (($compileOutput | ForEach-Object { [string]$_ }) -join " ").Trim() } catch { $detail = "" }
                if ([string]::IsNullOrWhiteSpace($detail)) {
                    $detail = "Unknown compiler failure."
                }
                throw ("Tickets worker build failed: " + $detail)
            }
            try { Write-QOTicketsCoreLog ("Tickets: Built worker executable at '{0}'." -f $exePath) } catch { }
            return $exePath
        } finally {
            try {
                if (Test-Path -LiteralPath $responsePath) {
                    Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        }
    } finally {
        if ($lockTaken -and $mutex) {
            try { $null = $mutex.ReleaseMutex() } catch { }
        }
        if ($mutex) {
            try { $mutex.Dispose() } catch { }
        }
    }
}

function Convert-QOTReplyQueueProcessArgumentString {
    param(
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $segments = foreach ($argument in @($Arguments)) {
        $text = [string]($argument + "")
        if ([string]::IsNullOrWhiteSpace($text)) {
            '""'
            continue
        }

        if ($text -notmatch '[\s"]') {
            $text
            continue
        }

        '"' + (($text -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    }

    return ($segments -join ' ')
}

function Test-QOTCurrentProcessElevated {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Start-QOTicketsReplyQueueWorker {
    param(
        [AllowNull()][string]$Reason = "manual"
    )

    $snapshot = Get-QOTPendingReplyQueueSnapshot
    $activeCount = 0
    try { $activeCount = [int]$snapshot.ActiveCount } catch { $activeCount = 0 }
    if ($activeCount -le 0) {
        return [pscustomobject]@{
            Started        = $false
            AlreadyRunning = $false
            ActiveCount    = 0
            Note           = "No active pending replies were found."
        }
    }

    if (Test-QOTicketsReplyQueueWorkerRunning) {
        return [pscustomobject]@{
            Started        = $false
            AlreadyRunning = $true
            ActiveCount    = $activeCount
            Note           = "Reply queue worker is already running."
        }
    }

    $toolkitRoot = Get-QOTTicketsReplyQueueToolkitRoot
    $runnerPath = Get-QOTTicketsReplyQueueRunnerPath
    if ([string]::IsNullOrWhiteSpace($toolkitRoot) -or [string]::IsNullOrWhiteSpace($runnerPath)) {
        throw "Reply queue runner script is unavailable."
    }

    $exePath = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $exePath)) { $exePath = "powershell.exe" }

    $argList = @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-STA",
        "-File", $runnerPath,
        "-ToolkitRoot", $toolkitRoot
    )

    $workingDirectory = $toolkitRoot
    if ([string]::IsNullOrWhiteSpace($workingDirectory) -or -not (Test-Path -LiteralPath $workingDirectory)) {
        $workingDirectory = $env:TEMP
    }

    $isElevated = $false
    try {
        $elevatedCheckCmd = Get-Command Test-QOTProcessElevated -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($elevatedCheckCmd) {
            $isElevated = [bool](& $elevatedCheckCmd)
        } else {
            $isElevated = [bool](Test-QOTCurrentProcessElevated)
        }
    } catch { $isElevated = [bool](Test-QOTCurrentProcessElevated) }

    if ($isElevated) {
        $startLimitedProcessCmd = Get-Command Start-QOTLimitedScheduledProcess -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($startLimitedProcessCmd) {
            $argumentString = ""
            try {
                $convertArgsCmd = Get-Command ConvertTo-QOTProcessArgumentString -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($convertArgsCmd) {
                    $argumentString = [string](& $convertArgsCmd -Arguments $argList)
                } else {
                    $argumentString = Convert-QOTReplyQueueProcessArgumentString -Arguments $argList
                }
            } catch {
                $argumentString = Convert-QOTReplyQueueProcessArgumentString -Arguments $argList
            }

            $null = & $startLimitedProcessCmd -FilePath $exePath -ArgumentString $argumentString -WorkingDirectory $workingDirectory -TaskNamePrefix "QOTReplyQueue"
            try { Write-QOTicketsCoreLog ("Tickets: Reply queue worker started via limited scheduled process. Reason='{0}' ActiveCount={1}" -f $Reason, $activeCount) } catch { }
            return [pscustomobject]@{
                Started        = $true
                AlreadyRunning = $false
                ActiveCount    = $activeCount
                Note           = "Reply queue worker started."
            }
        }

        try { Write-QOTicketsCoreLog "Tickets: Reply queue worker is starting elevated because limited-process helper is unavailable." "WARN" } catch { }
    }

    $argumentString = Convert-QOTReplyQueueProcessArgumentString -Arguments $argList
    $workerProcess = Start-Process -FilePath $exePath -ArgumentList $argumentString -WorkingDirectory $workingDirectory -WindowStyle Hidden -PassThru
    $workerPid = 0
    try { if ($workerProcess) { $workerPid = [int]$workerProcess.Id } } catch { $workerPid = 0 }
    try { Write-QOTicketsCoreLog ("Tickets: Reply queue worker started in detached process. Reason='{0}' ActiveCount={1} PID={2} Runner='{3}'" -f $Reason, $activeCount, $workerPid, $runnerPath) } catch { }
    return [pscustomobject]@{
        Started        = $true
        AlreadyRunning = $false
        ActiveCount    = $activeCount
        ProcessId      = $workerPid
        Note           = "Reply queue worker started."
    }
}

function Initialize-QOTicketsReplyQueueService {
    param(
        [AllowNull()][string]$Reason = "startup"
    )

    try {
        $recoverOrphanedSending = ($Reason -match '(?i)startup|rehydrat|tickets-ui')
        $null = Repair-QOTPendingReplyQueueState -RecoverOrphanedSending:$recoverOrphanedSending -Quiet
    } catch {
        try { Write-QOTicketsCoreLog ("Tickets: Queue repair failed during initialization. Reason='{0}' Error='{1}'" -f $Reason, $_.Exception.Message) "WARN" } catch { }
    }

    $snapshot = Get-QOTPendingReplyQueueSnapshot
    $activeCount = 0
    $queuedCount = 0
    $sendingCount = 0
    try { $activeCount = [int]$snapshot.ActiveCount } catch { $activeCount = 0 }
    try { $queuedCount = [int]$snapshot.QueuedCount } catch { $queuedCount = 0 }
    try { $sendingCount = [int]$snapshot.SendingCount } catch { $sendingCount = 0 }
    try { Write-QOTicketsCoreLog ("Tickets: Queue health check. Reason='{0}' Active={1} Queued={2} Sending={3}" -f $Reason, $activeCount, $queuedCount, $sendingCount) } catch { }

    $shouldLogStartupLoad = ($Reason -match '(?i)startup')
    if ($shouldLogStartupLoad) {
        foreach ($entry in @($snapshot.Entries)) {
            if (-not $entry) { continue }
            $entryDraftId = ""
            $entryTicketId = ""
            $entryState = ""
            $entryIsActive = $false
            try { if ($entry.PSObject.Properties.Name -contains "DraftId") { $entryDraftId = ([string]($entry.DraftId + "")).Trim() } } catch { $entryDraftId = "" }
            try { if ($entry.PSObject.Properties.Name -contains "TicketId") { $entryTicketId = ([string]($entry.TicketId + "")).Trim() } } catch { $entryTicketId = "" }
            try { if ($entry.PSObject.Properties.Name -contains "SendState") { $entryState = ([string]($entry.SendState + "")).Trim() } } catch { $entryState = "" }
            try { if ($entry.PSObject.Properties.Name -contains "IsActive") { $entryIsActive = [bool]$entry.IsActive } } catch { $entryIsActive = $false }
            if ([string]::IsNullOrWhiteSpace($entryDraftId)) { continue }

            try { Write-QOTicketsCoreLog ("Tickets: Pending reply loaded from storage. TicketId='{0}' DraftId='{1}' State='{2}'." -f $entryTicketId, $entryDraftId, $entryState) } catch { }
            if ($entryIsActive) {
                try { Write-QOTicketsCoreLog ("Tickets: Pending reply added to active queue. TicketId='{0}' DraftId='{1}' State='{2}' Reason='{3}'." -f $entryTicketId, $entryDraftId, $entryState, $Reason) } catch { }
            }
        }
    }

    if ($activeCount -le 0) {
        return [pscustomobject]@{
            Rehydrated     = $false
            ActiveCount    = 0
            QueuedCount    = 0
            SendingCount   = 0
            WorkerRunning  = $false
            WorkerStarted  = $false
            Note           = "No active pending replies were found."
        }
    }

    $workerRunning = $false
    try { $workerRunning = [bool]$snapshot.WorkerRunning } catch { $workerRunning = $false }
    $workerStarted = $false
    if (-not $workerRunning) {
        $workerResult = Start-QOTicketsReplyQueueWorker -Reason $Reason
        try { $workerStarted = [bool]$workerResult.Started } catch { $workerStarted = $false }
        $workerRunning = [bool](Test-QOTicketsReplyQueueWorkerRunning)
    } else {
        try { Write-QOTicketsCoreLog ("Tickets: Reply queue service rehydrated {0} active replies; worker already running." -f $activeCount) } catch { }
    }

    return [pscustomobject]@{
        Rehydrated     = $true
        ActiveCount    = $activeCount
        QueuedCount    = $queuedCount
        SendingCount   = $sendingCount
        WorkerRunning  = $workerRunning
        WorkerStarted  = $workerStarted
        Note           = $(if ($workerStarted) { "Reply queue worker started." } elseif ($workerRunning) { "Reply queue worker already running." } else { "Reply queue worker could not be confirmed." })
    }
}

function Queue-QOTTicketPendingReply {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [AllowNull()][string]$DraftId,
        [AllowNull()]$Ticket
    )

    $savedEntry = Add-QOTTicketPendingReply -TicketId $TicketId -Subject $Subject -Body $Body -DraftId $DraftId -SendState "Queued" -Ticket $Ticket
    $duplicateSuppressed = $false
    try { if ($savedEntry -and ($savedEntry.PSObject.Properties.Name -contains "DuplicateSuppressed")) { $duplicateSuppressed = [bool]$savedEntry.DuplicateSuppressed } } catch { $duplicateSuppressed = $false }
    if ($duplicateSuppressed) {
        try { Write-QOTicketsCoreLog ("Tickets: Pending reply enqueue reused existing queued entry. TicketId='{0}' DraftId='{1}'." -f [string]$savedEntry.TicketId, [string]$savedEntry.DraftId) } catch { }
    } else {
        try { Write-QOTicketsCoreLog ("Tickets: Pending reply added to active queue. TicketId='{0}' DraftId='{1}' State='Queued' Reason='enqueue'." -f [string]$savedEntry.TicketId, [string]$savedEntry.DraftId) } catch { }
    }
    try { Write-QOTicketsCoreLog ("Tickets: Worker launch requested. Reason='{0}' TicketId='{1}' DraftId='{2}'." -f $(if ($duplicateSuppressed) { "enqueue-duplicate" } else { "enqueue" }), [string]$savedEntry.TicketId, [string]$savedEntry.DraftId) } catch { }
    $serviceResult = Initialize-QOTicketsReplyQueueService -Reason $(if ($duplicateSuppressed) { "enqueue-duplicate" } else { "enqueue" })

    return [pscustomobject]@{
        ReplyId        = [string]$savedEntry.ReplyId
        TicketId       = [string]$savedEntry.TicketId
        DraftId        = [string]$savedEntry.DraftId
        Subject        = [string]$savedEntry.Subject
        Body           = [string]$savedEntry.Body
        To             = [string]$savedEntry.To
        MessageId      = [string]$savedEntry.MessageId
        ConversationId = [string]$savedEntry.ConversationId
        SourceMessageId = [string]$savedEntry.SourceMessageId
        SenderMailbox  = [string]$savedEntry.SenderMailbox
        CreatedAt      = [string]$savedEntry.CreatedAt
        LastAttemptAt  = [string]$savedEntry.LastAttemptAt
        NextAttemptAt  = [string]$savedEntry.NextAttemptAt
        SendState      = [string]$savedEntry.SendState
        FailureNote    = [string]$savedEntry.FailureNote
        LastError      = [string]$savedEntry.LastError
        RetryCount     = [int]$savedEntry.RetryCount
        SentAt         = [string]$savedEntry.SentAt
        DuplicateSuppressed = $duplicateSuppressed
        WorkerRunning  = [bool]$serviceResult.WorkerRunning
        WorkerStarted  = [bool]$serviceResult.WorkerStarted
        ActiveCount    = [int]$serviceResult.ActiveCount
    }
}

function Retry-QOTTicketPendingReply {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId
    )

    $existingEntry = Get-QOTTicketPendingReply -TicketId $TicketId -DraftId $DraftId
    if (-not $existingEntry) {
        throw ("Pending reply not found: " + $DraftId)
    }

    $stateValue = Normalize-QOTTicketPendingReplyState -SendState ([string]$existingEntry.SendState)
    if ($stateValue -eq "Sending" -and (Test-QOTicketsReplyQueueWorkerRunning)) {
        throw "Reply is already sending in the background."
    }

    $subjectValue = ""
    $bodyValue = ""
    try { if ($existingEntry.PSObject.Properties.Name -contains "Subject") { $subjectValue = ([string]($existingEntry.Subject + "")).Trim() } } catch { $subjectValue = "" }
    try { if ($existingEntry.PSObject.Properties.Name -contains "Body") { $bodyValue = [string]($existingEntry.Body + "") } } catch { $bodyValue = "" }
    if ([string]::IsNullOrWhiteSpace($subjectValue)) { throw "Reply subject is required before retrying." }
    if ([string]::IsNullOrWhiteSpace($bodyValue.Trim())) { throw "Reply body is required before retrying." }

    $retryMetadataTicket = [pscustomobject]@{
        Id                  = ([string]($TicketId + "")).Trim()
        EmailTo             = [string]($(if ($existingEntry.PSObject.Properties.Name -contains "To") { $existingEntry.To } else { "" }) + "")
        EmailMessageId      = [string]($(if ($existingEntry.PSObject.Properties.Name -contains "MessageId") { $existingEntry.MessageId } else { "" }) + "")
        EmailConversationId = [string]($(if ($existingEntry.PSObject.Properties.Name -contains "ConversationId") { $existingEntry.ConversationId } else { "" }) + "")
        SourceMessageId     = [string]($(if ($existingEntry.PSObject.Properties.Name -contains "SourceMessageId") { $existingEntry.SourceMessageId } else { "" }) + "")
        SourceMailbox       = [string]($(if ($existingEntry.PSObject.Properties.Name -contains "SenderMailbox") { $existingEntry.SenderMailbox } else { "" }) + "")
    }
    $oldDraftId = ([string]($DraftId + "")).Trim()
    $newDraftId = [guid]::NewGuid().ToString("N")
    $removed = [bool](Remove-QOTTicketPendingReply -TicketId $TicketId -DraftId $oldDraftId)
    if (-not $removed) {
        throw ("Pending reply could not be removed before retrying: " + $oldDraftId)
    }

    $savedEntry = Add-QOTTicketPendingReply -TicketId $TicketId -Subject $subjectValue -Body $bodyValue -DraftId $newDraftId -SendState "Queued" -Ticket $retryMetadataTicket
    try { Write-QOTicketsCoreLog ("Tickets: Pending reply added to active queue. TicketId='{0}' DraftId='{1}' RetriedFromDraftId='{2}' State='Queued' Reason='retry'." -f [string]$savedEntry.TicketId, [string]$savedEntry.DraftId, $oldDraftId) } catch { }
    $serviceResult = Initialize-QOTicketsReplyQueueService -Reason "retry"

    return [pscustomobject]@{
        ReplyId        = [string]$savedEntry.ReplyId
        TicketId       = [string]$savedEntry.TicketId
        DraftId        = [string]$savedEntry.DraftId
        OldDraftId     = $oldDraftId
        RetriedFromDraftId = $oldDraftId
        Subject        = [string]$savedEntry.Subject
        Body           = [string]$savedEntry.Body
        To             = [string]$savedEntry.To
        MessageId      = [string]$savedEntry.MessageId
        ConversationId = [string]$savedEntry.ConversationId
        SourceMessageId = [string]$savedEntry.SourceMessageId
        SenderMailbox  = [string]$savedEntry.SenderMailbox
        CreatedAt      = [string]$savedEntry.CreatedAt
        LastAttemptAt  = [string]$savedEntry.LastAttemptAt
        NextAttemptAt  = [string]$savedEntry.NextAttemptAt
        SendState      = [string]$savedEntry.SendState
        FailureNote    = [string]$savedEntry.FailureNote
        LastError      = [string]$savedEntry.LastError
        RetryCount     = [int]$savedEntry.RetryCount
        SentAt         = [string]$savedEntry.SentAt
        DuplicateSuppressed = $false
        WorkerRunning  = [bool]$serviceResult.WorkerRunning
        WorkerStarted  = [bool]$serviceResult.WorkerStarted
        ActiveCount    = [int]$serviceResult.ActiveCount
    }
}

function Cancel-QOTTicketPendingReply {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId
    )

    $existingEntry = Get-QOTTicketPendingReply -TicketId $TicketId -DraftId $DraftId
    if (-not $existingEntry) {
        return [pscustomobject]@{
            Cancelled = $false
            Reason    = "Pending reply not found."
        }
    }

    $stateValue = Normalize-QOTTicketPendingReplyState -SendState ([string]$existingEntry.SendState)
    if ($stateValue -eq "Sending" -and (Test-QOTicketsReplyQueueWorkerRunning)) {
        return [pscustomobject]@{
            Cancelled = $false
            Reason    = "Reply is already sending in the background."
        }
    }

    $removed = [bool](Remove-QOTTicketPendingReply -TicketId $TicketId -DraftId $DraftId)
    if ($removed) {
        try { Write-QOTicketsCoreLog ("Tickets: Pending reply removed from active queue. TicketId='{0}' DraftId='{1}'." -f $TicketId, $DraftId) } catch { }
    }
    return [pscustomobject]@{
        Cancelled = $removed
        Reason    = $(if ($removed) { "Reply removed from the queue." } else { "Reply could not be removed from the queue." })
    }
}

function Complete-QOTTicketReplySend {
    param(
        [Parameter(Mandatory)]$Ticket,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)]$SendResult,
        [string]$Status,
        [AllowNull()][string]$PendingReplyDraftId
    )

    $result = $SendResult
    $success = $false
    try { if ($SendResult.PSObject.Properties.Name -contains "Success") { $success = [bool]$SendResult.Success } } catch { $success = $false }
    if (-not $success) { return $result }

    $subjectValue = ([string]$Subject).Trim()
    $bodyValue = ([string]$Body).Trim()
    $ticketToUpdate = $Ticket

    try {
        $ticketIdForRefresh = ""
        try { if ($Ticket -and ($Ticket.PSObject.Properties.Name -contains "Id")) { $ticketIdForRefresh = ([string]($Ticket.Id + "")).Trim() } } catch { $ticketIdForRefresh = "" }
        if (-not [string]::IsNullOrWhiteSpace($ticketIdForRefresh)) {
            $latestTicket = @(
                @(Get-QOTickets -Quiet).Tickets |
                    Where-Object {
                        $_ -and
                        ($_.PSObject.Properties.Name -contains "Id") -and
                        [string]::Equals(([string]$_.Id).Trim(), $ticketIdForRefresh, [System.StringComparison]::OrdinalIgnoreCase)
                    } |
                    Select-Object -First 1
            )
            if ($latestTicket -is [System.Array]) {
                if ($latestTicket.Count -gt 0) { $latestTicket = $latestTicket[0] } else { $latestTicket = $null }
            }
            if ($latestTicket) {
                $ticketToUpdate = $latestTicket
                foreach ($prop in @($Ticket.PSObject.Properties)) {
                    if (-not $prop) { continue }
                    $propName = ([string]($prop.Name + "")).Trim()
                    if ([string]::IsNullOrWhiteSpace($propName)) { continue }
                    if ($propName -eq "Id") { continue }

                    $incomingValue = $prop.Value
                    $incomingIsMeaningful = $false
                    if ($null -ne $incomingValue) {
                        if ($incomingValue -is [System.Array]) {
                            $incomingIsMeaningful = (@($incomingValue).Count -gt 0)
                        } else {
                            $incomingText = ""
                            try { $incomingText = ([string]($incomingValue + "")).Trim() } catch { $incomingText = "" }
                            $incomingIsMeaningful = (-not [string]::IsNullOrWhiteSpace($incomingText))
                        }
                    }

                    if (-not ($ticketToUpdate.PSObject.Properties.Name -contains $propName)) {
                        try { $ticketToUpdate | Add-Member -NotePropertyName $propName -NotePropertyValue $incomingValue -Force } catch { }
                        continue
                    }

                    $existingValue = $null
                    $existingIsMeaningful = $false
                    try { $existingValue = $ticketToUpdate.$propName } catch { $existingValue = $null }
                    if ($null -ne $existingValue) {
                        if ($existingValue -is [System.Array]) {
                            $existingIsMeaningful = (@($existingValue).Count -gt 0)
                        } else {
                            $existingText = ""
                            try { $existingText = ([string]($existingValue + "")).Trim() } catch { $existingText = "" }
                            $existingIsMeaningful = (-not [string]::IsNullOrWhiteSpace($existingText))
                        }
                    }

                    if ((-not $existingIsMeaningful) -and $incomingIsMeaningful) {
                        try { $ticketToUpdate.$propName = $incomingValue } catch { }
                    }
                }
            }
        }

        $preferredSenderMailbox = Get-QOTicketPreferredSenderMailbox -Ticket $ticketToUpdate
        $replyRecipient = Get-QOTicketPrimaryEmailAddress -Ticket $ticketToUpdate
        $sentConversationId = ""
        $sentEntryId = ""
        $sentStoreId = ""
        try { if ($result.PSObject.Properties.Name -contains "ConversationId") { $sentConversationId = ([string]($result.ConversationId + "")).Trim() } } catch { $sentConversationId = "" }
        try { if ($result.PSObject.Properties.Name -contains "SentEntryId") { $sentEntryId = ([string]($result.SentEntryId + "")).Trim() } } catch { $sentEntryId = "" }
        try { if ($result.PSObject.Properties.Name -contains "SentStoreId") { $sentStoreId = ([string]($result.SentStoreId + "")).Trim() } } catch { $sentStoreId = "" }

        $replyEntry = [pscustomobject]@{
            ReplyId        = ([string]($PendingReplyDraftId + "")).Trim()
            Subject        = $subjectValue
            Body           = $bodyValue
            CreatedAt      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            SentAt         = (Get-Date).ToUniversalTime().ToString("o")
            Type           = "TechnicianReply"
            EntryType      = "TechnicianReply"
            To             = $replyRecipient
            FromMailbox    = $preferredSenderMailbox
            ConversationId = $sentConversationId
            SentEntryId    = $sentEntryId
            SentStoreId    = $sentStoreId
        }

        $existingReplies = @()
        try {
            if ($ticketToUpdate.PSObject.Properties.Name -contains "Replies") {
                $existingReplies = @($ticketToUpdate.Replies)
            }
        } catch { $existingReplies = @() }

        $updatedReplies = @(Merge-QOTTicketActivityEntries -PrimaryEntries @($existingReplies) -SecondaryEntries @($replyEntry))
        $ticketToUpdate.Replies = @($updatedReplies)

        try {
            $firstResponseExists = $false
            if ($ticketToUpdate.PSObject.Properties.Name -contains "FirstResponseAt") {
                $firstResponseExists = -not [string]::IsNullOrWhiteSpace([string]$ticketToUpdate.FirstResponseAt)
            }
            if (-not $firstResponseExists) {
                if ($ticketToUpdate.PSObject.Properties.Name -contains "FirstResponseAt") {
                    $ticketToUpdate.FirstResponseAt = $replyEntry.CreatedAt
                } else {
                    $ticketToUpdate | Add-Member -NotePropertyName FirstResponseAt -NotePropertyValue $replyEntry.CreatedAt -Force
                }
            }
        } catch { }

        if (-not [string]::IsNullOrWhiteSpace($sentConversationId)) {
            try {
                if ($ticketToUpdate.PSObject.Properties.Name -contains "EmailConversationId") {
                    if ([string]::IsNullOrWhiteSpace([string]$ticketToUpdate.EmailConversationId)) {
                        $ticketToUpdate.EmailConversationId = $sentConversationId
                    }
                } else {
                    $ticketToUpdate | Add-Member -NotePropertyName EmailConversationId -NotePropertyValue $sentConversationId -Force
                }
            } catch { }
        }

        if (-not [string]::IsNullOrWhiteSpace($sentEntryId)) {
            try {
                if ($ticketToUpdate.PSObject.Properties.Name -contains "LastOutboundMessageId") {
                    $ticketToUpdate.LastOutboundMessageId = $sentEntryId
                } else {
                    $ticketToUpdate | Add-Member -NotePropertyName LastOutboundMessageId -NotePropertyValue $sentEntryId -Force
                }
            } catch { }
        }
        if (-not [string]::IsNullOrWhiteSpace($sentStoreId)) {
            try {
                if ($ticketToUpdate.PSObject.Properties.Name -contains "LastOutboundStoreId") {
                    $ticketToUpdate.LastOutboundStoreId = $sentStoreId
                } else {
                    $ticketToUpdate | Add-Member -NotePropertyName LastOutboundStoreId -NotePropertyValue $sentStoreId -Force
                }
            } catch { }
        }

        if (-not [string]::IsNullOrWhiteSpace($Status)) {
            $statusValue = [string]$Status
            if ($statusValue -eq "Open") { $statusValue = "In Progress" }
            if ($script:ValidTicketStatuses -contains $statusValue) {
                $ticketToUpdate.Status = $statusValue
            }
        }

        try {
            $ticketIdValue = ""
            try { if ($ticketToUpdate.PSObject.Properties.Name -contains "Id") { $ticketIdValue = ([string]($ticketToUpdate.Id + "")).Trim() } } catch { $ticketIdValue = "" }
            if (-not [string]::IsNullOrWhiteSpace($ticketIdValue)) {
                $latestPendingReplies = @()
                try {
                    $latestTicket = @(
                        @(Get-QOTickets -Quiet).Tickets |
                            Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $ticketIdValue) } |
                            Select-Object -First 1
                    )
                    if ($latestTicket -is [System.Array]) {
                        if ($latestTicket.Count -gt 0) { $latestTicket = $latestTicket[0] } else { $latestTicket = $null }
                    }
                    if ($latestTicket -and ($latestTicket.PSObject.Properties.Name -contains "PendingReplies")) {
                        $latestPendingReplies = @($latestTicket.PendingReplies)
                    }
                } catch { $latestPendingReplies = @() }

                if (-not [string]::IsNullOrWhiteSpace([string]$PendingReplyDraftId)) {
                    $remainingPendingReplies = @()
                    foreach ($pendingReply in @($latestPendingReplies)) {
                        if (-not $pendingReply) { continue }
                        $pendingDraftId = ""
                        try { if ($pendingReply.PSObject.Properties.Name -contains "DraftId") { $pendingDraftId = ([string]($pendingReply.DraftId + "")).Trim() } } catch { $pendingDraftId = "" }
                        if ([string]::Equals($pendingDraftId, ([string]$PendingReplyDraftId).Trim(), [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                        $remainingPendingReplies += $pendingReply
                    }
                    $latestPendingReplies = @($remainingPendingReplies)
                }

                if ($ticketToUpdate.PSObject.Properties.Name -contains "PendingReplies") {
                    $ticketToUpdate.PendingReplies = @($latestPendingReplies)
                } else {
                    $ticketToUpdate | Add-Member -NotePropertyName PendingReplies -NotePropertyValue @($latestPendingReplies) -Force
                }
            }
        } catch { }

        $updatedAtStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        if ($ticketToUpdate.PSObject.Properties.Name -contains "UpdatedAt") {
            $ticketToUpdate.UpdatedAt = $updatedAtStamp
        } else {
            $ticketToUpdate | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue $updatedAtStamp -Force
        }
        $null = Update-QOTicket -Ticket $ticketToUpdate

        if ($Ticket -and ($Ticket -ne $ticketToUpdate)) {
            try {
                foreach ($prop in @($ticketToUpdate.PSObject.Properties)) {
                    if (-not $prop) { continue }
                    if ($Ticket.PSObject.Properties.Name -contains $prop.Name) {
                        try { $Ticket.$($prop.Name) = $prop.Value } catch { }
                    } else {
                        try { $Ticket | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force } catch { }
                    }
                }
            } catch { }
        }

        try {
            if ($result.PSObject.Properties.Name -contains "Persisted") {
                $result.Persisted = $true
            } else {
                $result | Add-Member -NotePropertyName Persisted -NotePropertyValue $true -Force
            }
        } catch { }

        return $result
    } catch {
        $persistError = $_.Exception.Message
        try { Write-QOTicketsCoreLog ("Tickets: Reply persistence after send failed. TicketId='{0}' Error='{1}'." -f ([string]($ticketToUpdate.Id + "")).Trim(), $persistError) "WARN" } catch { }
        try {
            if ($result.PSObject.Properties.Name -contains "Persisted") {
                $result.Persisted = $false
            } else {
                $result | Add-Member -NotePropertyName Persisted -NotePropertyValue $false -Force
            }
        } catch { }
        try {
            if ($result.PSObject.Properties.Name -contains "PersistError") {
                $result.PersistError = $persistError
            } else {
                $result | Add-Member -NotePropertyName PersistError -NotePropertyValue $persistError -Force
            }
        } catch { }
        return $result
    }
}

function Send-QOTicketReply {
    param(
        [Parameter(Mandatory)]$Ticket,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [string]$Status,
        [AllowNull()][string]$PendingReplyDraftId
    )

    $subjectValue = ([string]$Subject).Trim()
    $bodyValue = ([string]$Body).Trim()
    $ticketToUpdate = $Ticket

    if ([string]::IsNullOrWhiteSpace($subjectValue)) {
        throw "Reply subject is required."
    }
    if ([string]::IsNullOrWhiteSpace($bodyValue)) {
        throw "Reply body is required."
    }

    try {
        $ticketIdForRefresh = ""
        try { if ($Ticket -and ($Ticket.PSObject.Properties.Name -contains "Id")) { $ticketIdForRefresh = ([string]($Ticket.Id + "")).Trim() } } catch { $ticketIdForRefresh = "" }
        if (-not [string]::IsNullOrWhiteSpace($ticketIdForRefresh)) {
            $latestTicket = @(
                @(Get-QOTickets -Quiet).Tickets |
                    Where-Object {
                        $_ -and
                        ($_.PSObject.Properties.Name -contains "Id") -and
                        [string]::Equals(([string]$_.Id).Trim(), $ticketIdForRefresh, [System.StringComparison]::OrdinalIgnoreCase)
                    } |
                    Select-Object -First 1
            )
            if ($latestTicket -is [System.Array]) {
                if ($latestTicket.Count -gt 0) { $latestTicket = $latestTicket[0] } else { $latestTicket = $null }
            }
            if ($latestTicket) {
                $ticketToUpdate = $latestTicket
                foreach ($prop in @($Ticket.PSObject.Properties)) {
                    if (-not $prop) { continue }
                    $propName = ([string]($prop.Name + "")).Trim()
                    if ([string]::IsNullOrWhiteSpace($propName)) { continue }
                    if ($propName -eq "Id") { continue }

                    $incomingValue = $prop.Value
                    $incomingIsMeaningful = $false
                    if ($null -ne $incomingValue) {
                        if ($incomingValue -is [System.Array]) {
                            $incomingIsMeaningful = (@($incomingValue).Count -gt 0)
                        } else {
                            $incomingText = ""
                            try { $incomingText = ([string]($incomingValue + "")).Trim() } catch { $incomingText = "" }
                            $incomingIsMeaningful = (-not [string]::IsNullOrWhiteSpace($incomingText))
                        }
                    }

                    if (-not ($ticketToUpdate.PSObject.Properties.Name -contains $propName)) {
                        try { $ticketToUpdate | Add-Member -NotePropertyName $propName -NotePropertyValue $incomingValue -Force } catch { }
                        continue
                    }

                    $existingValue = $null
                    $existingIsMeaningful = $false
                    try { $existingValue = $ticketToUpdate.$propName } catch { $existingValue = $null }
                    if ($null -ne $existingValue) {
                        if ($existingValue -is [System.Array]) {
                            $existingIsMeaningful = (@($existingValue).Count -gt 0)
                        } else {
                            $existingText = ""
                            try { $existingText = ([string]($existingValue + "")).Trim() } catch { $existingText = "" }
                            $existingIsMeaningful = (-not [string]::IsNullOrWhiteSpace($existingText))
                        }
                    }

                    if ((-not $existingIsMeaningful) -and $incomingIsMeaningful) {
                        try { $ticketToUpdate.$propName = $incomingValue } catch { }
                    }
                }
            }
        }
    } catch { $ticketToUpdate = $Ticket }

    $result = $null
    $null = Import-QOTOutlookIntegrationModule
    $preferredSenderMailbox = Get-QOTicketPreferredSenderMailbox -Ticket $ticketToUpdate
    $hasReplyReference = Test-QOTicketHasReplyReference -Ticket $ticketToUpdate
    $preferOutboundEmailSend = Test-QOTicketPrefersOutboundEmailSend -Ticket $ticketToUpdate

    if ($hasReplyReference) {
        if ($preferOutboundEmailSend) {
            try {
                Write-QOTicketsCoreLog ("Tickets: Reply send is using the Outlook reply path for a self-addressed thread. TicketId='{0}'." -f ([string]($ticketToUpdate.Id + "")).Trim())
            } catch { }
        }
        if (Get-Command Send-QOTicketOutlookReply -ErrorAction SilentlyContinue) {
            $ticketIdForSend = ""
            try { if ($ticketToUpdate.PSObject.Properties.Name -contains "Id") { $ticketIdForSend = [string]$ticketToUpdate.Id } } catch { $ticketIdForSend = "" }
            $result = Send-QOTicketOutlookReply -Ticket $ticketToUpdate -Subject $subjectValue -Body $bodyValue -FromMailbox $preferredSenderMailbox -TicketId $ticketIdForSend

            $shouldFallbackToOutboundEmail = $false
            $replyFailureNote = ""
            $replySendSucceeded = $false
            try { $replySendSucceeded = [bool]$result.Success } catch { $replySendSucceeded = $false }
            try { if ($result.PSObject.Properties.Name -contains "Note") { $replyFailureNote = ([string]($result.Note + "")).Trim() } } catch { $replyFailureNote = "" }

            if (-not $replySendSucceeded) {
                if (-not [string]::IsNullOrWhiteSpace($replyFailureNote)) {
                    $shouldFallbackToOutboundEmail = (
                        $replyFailureNote -match '(?i)original email not found in outlook' -or
                        $replyFailureNote -match '(?i)item cannot be found' -or
                        $replyFailureNote -match '(?i)mapi_e_not_found'
                    )
                }
            }

            if ($shouldFallbackToOutboundEmail -and (Get-Command Send-QOTicketOutlookEmail -ErrorAction SilentlyContinue)) {
                $recipientEmail = Get-QOTicketPrimaryEmailAddress -Ticket $ticketToUpdate
                if (-not [string]::IsNullOrWhiteSpace($recipientEmail)) {
                    try {
                        Write-QOTicketsCoreLog ("Tickets: Reply fallback is sending as a normal Outlook email because the original Outlook item could not be found. TicketId='{0}' To='{1}'." -f $ticketIdForSend, $recipientEmail) "WARN"
                    } catch { }

                    $fallbackResult = Send-QOTicketOutlookEmail -To $recipientEmail -Subject $subjectValue -Body $bodyValue -FromMailbox $preferredSenderMailbox -TicketId $ticketIdForSend
                    $fallbackSucceeded = $false
                    try { $fallbackSucceeded = [bool]$fallbackResult.Success } catch { $fallbackSucceeded = $false }
                    if ($fallbackSucceeded) {
                        try {
                            Write-QOTicketsCoreLog ("Tickets: Reply fallback email send succeeded. TicketId='{0}' To='{1}'." -f $ticketIdForSend, $recipientEmail)
                        } catch { }
                        $result = $fallbackResult
                    } else {
                        $fallbackFailureNote = ""
                        try { if ($fallbackResult.PSObject.Properties.Name -contains "Note") { $fallbackFailureNote = ([string]($fallbackResult.Note + "")).Trim() } } catch { $fallbackFailureNote = "" }
                        try {
                            Write-QOTicketsCoreLog ("Tickets: Reply fallback email send failed. TicketId='{0}' To='{1}' ReplyFailure='{2}' FallbackFailure='{3}'." -f $ticketIdForSend, $recipientEmail, $replyFailureNote, $fallbackFailureNote) "WARN"
                        } catch { }
                    }
                } else {
                    try {
                        Write-QOTicketsCoreLog ("Tickets: Reply fallback skipped because no recipient email address could be resolved. TicketId='{0}' ReplyFailure='{1}'." -f $ticketIdForSend, $replyFailureNote) "WARN"
                    } catch { }
                }
            }
        } else {
            return [pscustomobject]@{
                Success = $false
                Note    = "Outlook reply function not available."
            }
        }
    }
    elseif (Get-Command Send-QOTicketOutlookEmail -ErrorAction SilentlyContinue) {
        $recipientEmail = Get-QOTicketPrimaryEmailAddress -Ticket $ticketToUpdate
        if ([string]::IsNullOrWhiteSpace($recipientEmail)) {
            return [pscustomobject]@{
                Success = $false
                Note    = "Ticket has no customer email address."
            }
        }
        $ticketIdForSend = ""
        try { if ($ticketToUpdate.PSObject.Properties.Name -contains "Id") { $ticketIdForSend = [string]$ticketToUpdate.Id } } catch { $ticketIdForSend = "" }
        $result = Send-QOTicketOutlookEmail -To $recipientEmail -Subject $subjectValue -Body $bodyValue -FromMailbox $preferredSenderMailbox -TicketId $ticketIdForSend
    }
    else {
        return [pscustomobject]@{
            Success = $false
            Note    = "Outlook email function not available."
        }
    }

    $success = $false
    try { $success = [bool]$result.Success } catch { $success = $false }

    if ($success) {
        $result = Complete-QOTTicketReplySend -Ticket $Ticket -Subject $subjectValue -Body $bodyValue -SendResult $result -Status $Status -PendingReplyDraftId $PendingReplyDraftId
    }

    return $result
}


$exports = @(
    "Initialize-QOTicketStorage",
    "Reset-QOTicketStorageCache",
    "Get-QOTicketsStorePath",
    "Ensure-QOTicketsStoreDirectory",
    "Get-QOTickets",
    "Save-QOTickets",
    "New-QOTicket",
    "Add-QOTicket",
    "Update-QOTicket",
    "Remove-QOTicket",
    "Restore-QOTickets",
    "Set-QOTicketsStatus",
    "Get-QOTicketStatuses",
    "Set-QOTicketsPriority",
    "Get-QOTicketPriorities",
    "Set-QOTicketsAssignedTo",
    "Get-QOTicketAssignees",
    "Get-QOTicketsByBucket",
    "Get-QOTicketsByFolder",
    "Get-QOTicketsFiltered",
    "Get-QOTMonitoredMailboxAddresses",
    "Get-QOTicketAnalyticsSnapshot",
    "Export-QOTicketsToExcelSpreadsheet",
    "Add-QOTicketFromEmail",
    "Sync-QOTicketsFromEmail",
    "Add-QOTicketNote",
    "Remove-QOTicketNote",
    "Rename-QOTicket",
    "Get-QOTicketPendingReplies",
    "Get-QOTTicketPendingReply",
    "Get-QOTPendingReplyQueueSnapshot",
    "Add-QOTTicketPendingReply",
    "Set-QOTTicketPendingReplyState",
    "Remove-QOTTicketPendingReply",
    "Get-QOTNextPendingReply",
    "Get-QOTTicketsReplyQueueMutexName",
    "Test-QOTicketsReplyQueueWorkerRunning",
    "Start-QOTicketsReplyQueueWorker",
    "Initialize-QOTicketsReplyQueueService",
    "Queue-QOTTicketPendingReply",
    "Retry-QOTTicketPendingReply",
    "Cancel-QOTTicketPendingReply",
    "Get-QOTTicketsWorkerExePath",
    "Ensure-QOTTicketsWorker",
    "Get-QOTTicketsWorkerRuntimeRoot",
    "New-QOTTicketReplyWorkerPayload",
    "Complete-QOTTicketReplySend",
    "Send-QOTicketReply"
)

# Only export Outlook sync if it actually exists (module loaded)
if (Get-Command Sync-QOTicketsFromOutlook -ErrorAction SilentlyContinue) {
    $exports += "Sync-QOTicketsFromOutlook"
}

Export-ModuleMember -Function $exports
