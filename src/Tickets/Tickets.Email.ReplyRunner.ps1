param(
    [Parameter(Mandatory=$true)][string]$ToolkitRoot,
    [string]$ReplyCommand = "Send-QOTicketReply",
    [Parameter(Mandatory=$true)][string]$PayloadPath,
    [string]$ResultPath,
    [switch]$TransportOnly
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

function Write-QOTReplyRunnerLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = "INFO"
    )

    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logPath = Join-Path $logDir "ReplyRunner.log"
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -LiteralPath $logPath -Value ("[{0}] [{1}] {2}" -f $stamp, $Level.ToUpperInvariant(), $Message) -Encoding UTF8
    } catch { }
}

function New-QOTReplyRunnerResult {
    param(
        [bool]$Success = $false,
        [string]$Note = ""
    )

    return [pscustomobject]@{
        Success = [bool]$Success
        Note    = [string]$Note
    }
}

function Write-QOTReplyRunnerResult {
    param(
        [Parameter(Mandatory=$true)]$Result
    )

    $json = $Result | ConvertTo-Json -Depth 10 -Compress
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        try {
            $json | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }

    $json
}

$dispatchStarted = $false
try {
    Write-QOTReplyRunnerLog ("Reply runner starting. ToolkitRoot='{0}' PayloadPath='{1}' ResultPath='{2}' ReplyCommand='{3}'" -f $ToolkitRoot, $PayloadPath, $ResultPath, $ReplyCommand)
    if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
        throw "Toolkit root path is required."
    }

    if ([string]::IsNullOrWhiteSpace($PayloadPath) -or -not (Test-Path -LiteralPath $PayloadPath)) {
        throw "Reply payload file is missing."
    }

    $coreModulePath = Join-Path $ToolkitRoot "src\Core\Tickets.psm1"
    if (-not (Test-Path -LiteralPath $coreModulePath)) {
        throw ("Core tickets module not found: " + $coreModulePath)
    }

    Import-Module -Name $coreModulePath -Global -Force -ErrorAction Stop -WarningAction SilentlyContinue

    $replyCmd = Get-Command -Name $ReplyCommand -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $replyCmd) {
        throw ("Reply command unavailable: " + $ReplyCommand)
    }
    if (-not (Get-Command -Name "Get-QOTickets" -ErrorAction SilentlyContinue)) {
        throw "Ticket storage command unavailable."
    }

    $payloadRaw = [IO.File]::ReadAllText($PayloadPath)
    if ([string]::IsNullOrWhiteSpace($payloadRaw)) {
        throw "Reply payload was empty."
    }

    $payload = $payloadRaw | ConvertFrom-Json -ErrorAction Stop
    $ticketId = ""
    $subject = ""
    $body = ""
    $pendingReplyDraftId = ""
    try { if ($payload.PSObject.Properties.Name -contains "TicketId") { $ticketId = ([string]$payload.TicketId).Trim() } } catch { $ticketId = "" }
    try { if ($payload.PSObject.Properties.Name -contains "Subject") { $subject = ([string]$payload.Subject).Trim() } } catch { $subject = "" }
    try { if ($payload.PSObject.Properties.Name -contains "Body") { $body = [string]$payload.Body } } catch { $body = "" }
    try { if ($payload.PSObject.Properties.Name -contains "PendingReplyDraftId") { $pendingReplyDraftId = ([string]$payload.PendingReplyDraftId).Trim() } } catch { $pendingReplyDraftId = "" }

    if ([string]::IsNullOrWhiteSpace($ticketId)) {
        throw "Reply payload is missing TicketId."
    }
    if ([string]::IsNullOrWhiteSpace($subject)) {
        throw "Reply subject is required."
    }
    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "Reply body is required."
    }

    $db = Get-QOTickets -Quiet
    $ticket = @(
        @($db.Tickets) |
            Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $ticketId) } |
            Select-Object -First 1
    )
    if ($ticket -is [System.Array]) {
        if ($ticket.Count -gt 0) { $ticket = $ticket[0] } else { $ticket = $null }
    }

    if (-not $ticket) {
        Write-QOTReplyRunnerLog ("Reply runner could not find ticket '{0}'." -f $ticketId) "WARN"
        Write-QOTReplyRunnerResult -Result (New-QOTReplyRunnerResult -Success:$false -Note ("Ticket not found: " + $ticketId))
        exit 0
    }

    $replyParams = @{ Ticket = $ticket; Subject = $subject; Body = $body; PendingReplyDraftId = $pendingReplyDraftId }
    if ($TransportOnly) { $replyParams.TransportOnly = $true }
    $dispatchStarted = $true
    $rawResult = & $replyCmd @replyParams
    if ($null -eq $rawResult -or $rawResult.Success -isnot [bool]) {
        throw "Reply transport did not return an explicit submission result."
    }

    Write-QOTReplyRunnerLog ("Reply runner completed. Success={0} Note='{1}' TicketId='{2}'" -f $rawResult.Success, $rawResult.Note, $ticketId)
    Write-QOTReplyRunnerResult -Result $rawResult
    exit 0
}
catch {
    $failure = New-QOTReplyRunnerResult -Success:$false -Note ("Reply runner failed: " + $_.Exception.Message)
    Write-QOTReplyRunnerLog ("Reply runner failed. " + $_.Exception.Message) "ERROR"
    if ($dispatchStarted) {
        $failure.Note = "Outlook did not confirm submission. Check Outbox and Sent Items before resending."
        $failure | Add-Member -NotePropertyName SubmissionUnconfirmed -NotePropertyValue $true
    }
    Write-QOTReplyRunnerResult -Result $failure
    exit 1
}
