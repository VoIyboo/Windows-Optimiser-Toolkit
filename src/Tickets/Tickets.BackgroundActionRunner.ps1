param(
    [Parameter(Mandatory=$true)][string]$ToolkitRoot,
    [Parameter(Mandatory=$true)][string]$Action,
    [Parameter(Mandatory=$true)][string]$PayloadPath,
    [string]$ResultPath
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

function Write-QOTBackgroundActionLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = "INFO"
    )

    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logPath = Join-Path $logDir "BackgroundActionRunner.log"
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -LiteralPath $logPath -Value ("[{0}] [{1}] {2}" -f $stamp, $Level.ToUpperInvariant(), $Message) -Encoding UTF8
    } catch { }
}

function New-QOTBackgroundActionResult {
    param(
        [bool]$Success = $false,
        [string]$Note = "",
        [AllowNull()][hashtable]$Fields
    )

    $result = [pscustomobject]@{
        Success = [bool]$Success
        Note    = [string]$Note
        Action  = [string]$Action
    }

    foreach ($fieldName in @($Fields.Keys)) {
        $nameValue = ([string]($fieldName + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($nameValue)) { continue }
        try { $result | Add-Member -NotePropertyName $nameValue -NotePropertyValue $Fields[$fieldName] -Force } catch { }
    }

    return $result
}

function Write-QOTBackgroundActionResult {
    param(
        [Parameter(Mandatory=$true)]$Result
    )

    $json = $Result | ConvertTo-Json -Depth 12 -Compress
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        try {
            $json | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }

    $json
}

try {
    Write-QOTBackgroundActionLog ("Background action runner starting. Action='{0}' ToolkitRoot='{1}' PayloadPath='{2}' ResultPath='{3}'." -f $Action, $ToolkitRoot, $PayloadPath, $ResultPath)

    if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
        throw "Toolkit root path is required."
    }
    if ([string]::IsNullOrWhiteSpace($PayloadPath) -or -not (Test-Path -LiteralPath $PayloadPath)) {
        throw "Background action payload file is missing."
    }

    $coreModulePath = Join-Path $ToolkitRoot "src\Core\Tickets.psm1"
    if (-not (Test-Path -LiteralPath $coreModulePath)) {
        throw ("Core tickets module not found: " + $coreModulePath)
    }

    Import-Module -Name $coreModulePath -Global -Force -ErrorAction Stop -WarningAction SilentlyContinue

    $payloadRaw = [string](Get-Content -LiteralPath $PayloadPath -Raw -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace($payloadRaw)) {
        throw "Background action payload was empty."
    }

    $payload = $payloadRaw | ConvertFrom-Json -ErrorAction Stop

    switch -Regex (([string]($Action + "")).Trim()) {
        '^(?i)queue-reply$' {
            $ticketId = ""
            $subject = ""
            $body = ""
            $draftId = ""
            try { if ($payload.PSObject.Properties.Name -contains "TicketId") { $ticketId = ([string]$payload.TicketId).Trim() } } catch { $ticketId = "" }
            try { if ($payload.PSObject.Properties.Name -contains "Subject") { $subject = ([string]$payload.Subject).Trim() } } catch { $subject = "" }
            try { if ($payload.PSObject.Properties.Name -contains "Body") { $body = [string]$payload.Body } } catch { $body = "" }
            try { if ($payload.PSObject.Properties.Name -contains "DraftId") { $draftId = ([string]$payload.DraftId).Trim() } } catch { $draftId = "" }

            if ([string]::IsNullOrWhiteSpace($ticketId)) { throw "Queue reply payload is missing TicketId." }
            if ([string]::IsNullOrWhiteSpace($subject)) { throw "Queue reply payload is missing Subject." }
            if ([string]::IsNullOrWhiteSpace($body)) { throw "Queue reply payload is missing Body." }

            $db = Get-QOTickets -Quiet
            $ticket = @(
                @($db.Tickets) |
                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $ticketId) } |
                    Select-Object -First 1
            )
            if ($ticket -is [System.Array]) {
                if ($ticket.Count -gt 0) { $ticket = $ticket[0] } else { $ticket = $null }
            }

            $queueResult = Queue-QOTTicketPendingReply -TicketId $ticketId -Subject $subject -Body $body -DraftId $draftId -Ticket $ticket
            $note = "Reply queued."
            $duplicateSuppressed = $false
            try { if ($queueResult.PSObject.Properties.Name -contains "DuplicateSuppressed") { $duplicateSuppressed = [bool]$queueResult.DuplicateSuppressed } } catch { $duplicateSuppressed = $false }
            if ($duplicateSuppressed) { $note = "Reply already queued." }

            Write-QOTBackgroundActionLog ("Background queue-reply completed. TicketId='{0}' DraftId='{1}' DuplicateSuppressed={2}." -f $ticketId, [string]$queueResult.DraftId, $duplicateSuppressed)
            Write-QOTBackgroundActionResult -Result (New-QOTBackgroundActionResult -Success:$true -Note $note -Fields @{
                TicketId            = [string]$queueResult.TicketId
                DraftId             = [string]$queueResult.DraftId
                ReplyId             = [string]$queueResult.ReplyId
                SendState           = [string]$queueResult.SendState
                DuplicateSuppressed = $duplicateSuppressed
                WorkerRunning       = [bool]$queueResult.WorkerRunning
                WorkerStarted       = [bool]$queueResult.WorkerStarted
                ActiveCount         = [int]$queueResult.ActiveCount
            })
            exit 0
        }
        '^(?i)retry-reply$' {
            $ticketId = ""
            $draftId = ""
            try { if ($payload.PSObject.Properties.Name -contains "TicketId") { $ticketId = ([string]$payload.TicketId).Trim() } } catch { $ticketId = "" }
            try { if ($payload.PSObject.Properties.Name -contains "DraftId") { $draftId = ([string]$payload.DraftId).Trim() } } catch { $draftId = "" }
            if ([string]::IsNullOrWhiteSpace($ticketId) -or [string]::IsNullOrWhiteSpace($draftId)) {
                throw "Retry reply payload is missing TicketId or DraftId."
            }

            $retryResult = Retry-QOTTicketPendingReply -TicketId $ticketId -DraftId $draftId
            $newDraftId = ""
            try { if ($retryResult.PSObject.Properties.Name -contains "DraftId") { $newDraftId = ([string]$retryResult.DraftId).Trim() } } catch { $newDraftId = "" }
            Write-QOTBackgroundActionLog ("Background retry-reply completed. TicketId='{0}' OldDraftId='{1}' NewDraftId='{2}'." -f $ticketId, $draftId, $newDraftId)
            Write-QOTBackgroundActionResult -Result (New-QOTBackgroundActionResult -Success:$true -Note "Reply requeued." -Fields @{
                TicketId           = [string]$retryResult.TicketId
                DraftId            = [string]$retryResult.DraftId
                OldDraftId         = $draftId
                RetriedFromDraftId = $draftId
                ReplyId            = [string]$retryResult.ReplyId
                Subject            = [string]$retryResult.Subject
                Body               = [string]$retryResult.Body
                CreatedAt          = [string]$retryResult.CreatedAt
                LastAttemptAt      = [string]$retryResult.LastAttemptAt
                NextAttemptAt      = [string]$retryResult.NextAttemptAt
                SendState          = [string]$retryResult.SendState
                FailureNote        = [string]$retryResult.FailureNote
                WorkerRunning      = [bool]$retryResult.WorkerRunning
                WorkerStarted      = [bool]$retryResult.WorkerStarted
                ActiveCount        = [int]$retryResult.ActiveCount
            })
            exit 0
        }
        '^(?i)cancel-reply$' {
            $ticketId = ""
            $draftId = ""
            try { if ($payload.PSObject.Properties.Name -contains "TicketId") { $ticketId = ([string]$payload.TicketId).Trim() } } catch { $ticketId = "" }
            try { if ($payload.PSObject.Properties.Name -contains "DraftId") { $draftId = ([string]$payload.DraftId).Trim() } } catch { $draftId = "" }
            if ([string]::IsNullOrWhiteSpace($ticketId) -or [string]::IsNullOrWhiteSpace($draftId)) {
                throw "Cancel reply payload is missing TicketId or DraftId."
            }

            $cancelResult = Cancel-QOTTicketPendingReply -TicketId $ticketId -DraftId $draftId
            $cancelled = $false
            $note = "Reply could not be removed from the queue."
            try { if ($cancelResult.PSObject.Properties.Name -contains "Cancelled") { $cancelled = [bool]$cancelResult.Cancelled } } catch { $cancelled = $false }
            try { if ($cancelResult.PSObject.Properties.Name -contains "Reason") { $note = ([string]($cancelResult.Reason + "")).Trim() } } catch { $note = "Reply could not be removed from the queue." }

            Write-QOTBackgroundActionLog ("Background cancel-reply completed. TicketId='{0}' DraftId='{1}' Cancelled={2}." -f $ticketId, $draftId, $cancelled)
            Write-QOTBackgroundActionResult -Result (New-QOTBackgroundActionResult -Success:$cancelled -Note $note -Fields @{
                TicketId   = $ticketId
                DraftId    = $draftId
                Cancelled  = $cancelled
            })
            exit 0
        }
        '^(?i)save-note$' {
            $ticketId = ""
            $noteText = ""
            $author = ""
            $noteId = ""
            try { if ($payload.PSObject.Properties.Name -contains "TicketId") { $ticketId = ([string]$payload.TicketId).Trim() } } catch { $ticketId = "" }
            try { if ($payload.PSObject.Properties.Name -contains "Note") { $noteText = ([string]$payload.Note).Trim() } } catch { $noteText = "" }
            try { if ($payload.PSObject.Properties.Name -contains "Author") { $author = ([string]$payload.Author).Trim() } } catch { $author = "" }
            try { if ($payload.PSObject.Properties.Name -contains "NoteId") { $noteId = ([string]$payload.NoteId).Trim() } } catch { $noteId = "" }
            if ([string]::IsNullOrWhiteSpace($ticketId) -or [string]::IsNullOrWhiteSpace($noteText)) {
                throw "Save note payload is missing TicketId or Note."
            }
            if ([string]::IsNullOrWhiteSpace($author)) { $author = "User" }
            if ([string]::IsNullOrWhiteSpace($noteId)) { $noteId = [guid]::NewGuid().ToString("N") }

            $savedTicket = Add-QOTicketNote -Id $ticketId -Note $noteText -Author $author -NoteId $noteId
            $updatedAt = ""
            $noteCount = 0
            $storePath = ""
            try { if ($savedTicket -and ($savedTicket.PSObject.Properties.Name -contains "UpdatedAt")) { $updatedAt = ([string]($savedTicket.UpdatedAt + "")).Trim() } } catch { $updatedAt = "" }
            try { if ($savedTicket -and ($savedTicket.PSObject.Properties.Name -contains "Notes")) { $noteCount = @($savedTicket.Notes | Where-Object { $_ }).Count } } catch { $noteCount = 0 }
            try { $storePath = [string](Get-QOTicketsStorePath) } catch { $storePath = "" }
            Write-QOTBackgroundActionLog ("Background save-note completed. TicketId='{0}' NoteId='{1}' Author='{2}' Collection='Notes' StorePath='{3}' NoteCount={4}." -f $ticketId, $noteId, $author, $storePath, $noteCount)
            Write-QOTBackgroundActionResult -Result (New-QOTBackgroundActionResult -Success:$true -Note "Internal note saved." -Fields @{
                TicketId   = $ticketId
                NoteId     = $noteId
                Author     = $author
                UpdatedAt  = $updatedAt
                NoteCount  = $noteCount
                StorePath  = $storePath
            })
            exit 0
        }
        '^(?i)delete-note$' {
            $ticketId = ""
            $noteId = ""
            try { if ($payload.PSObject.Properties.Name -contains "TicketId") { $ticketId = ([string]$payload.TicketId).Trim() } } catch { $ticketId = "" }
            try { if ($payload.PSObject.Properties.Name -contains "NoteId") { $noteId = ([string]$payload.NoteId).Trim() } } catch { $noteId = "" }
            if ([string]::IsNullOrWhiteSpace($ticketId) -or [string]::IsNullOrWhiteSpace($noteId)) {
                throw "Delete note payload is missing TicketId or NoteId."
            }

            $deleteResult = Remove-QOTicketNote -Id $ticketId -NoteId $noteId
            $removed = $false
            $removedCount = 0
            try { if ($deleteResult.PSObject.Properties.Name -contains "Removed") { $removed = [bool]$deleteResult.Removed } } catch { $removed = $false }
            try { if ($deleteResult.PSObject.Properties.Name -contains "Count") { $removedCount = [int]$deleteResult.Count } } catch { $removedCount = 0 }

            Write-QOTBackgroundActionLog ("Background delete-note completed. TicketId='{0}' NoteId='{1}' Removed={2} Count={3}." -f $ticketId, $noteId, $removed, $removedCount)
            Write-QOTBackgroundActionResult -Result (New-QOTBackgroundActionResult -Success:$removed -Note $(if ($removed) { "Internal note deleted." } else { "Internal note not found." }) -Fields @{
                TicketId = $ticketId
                NoteId   = $noteId
                Removed  = $removed
                Count    = $removedCount
            })
            exit 0
        }
        default {
            throw ("Unsupported background action: " + $Action)
        }
    }
}
catch {
    $failureResult = New-QOTBackgroundActionResult -Success:$false -Note ("Background action failed: " + $_.Exception.Message)
    Write-QOTBackgroundActionLog ("Background action runner failed. Action='{0}' Error='{1}'" -f $Action, $_.Exception.Message) "ERROR"
    Write-QOTBackgroundActionResult -Result $failureResult
    exit 1
}
