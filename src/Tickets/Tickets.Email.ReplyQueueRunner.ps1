param(
    [Parameter(Mandatory=$true)][string]$ToolkitRoot,
    [string]$ReplyCommand = "Send-QOTicketReply",
    [int]$MaxFailureRetries = 5,
    [int]$StaleSendingSeconds = 600,
    [int]$ReplySendTimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

function Write-QOTReplyQueueRunnerLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = "INFO"
    )

    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logPath = Join-Path $logDir "ReplyQueueRunner.log"
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -LiteralPath $logPath -Value ("[{0}] [{1}] {2}" -f $stamp, $Level.ToUpperInvariant(), $Message) -Encoding UTF8
    } catch { }
}

function Get-QOTReplyQueueRetryDelaySeconds {
    param([int]$RetryCount)

    $attempt = [Math]::Max(1, [int]$RetryCount)
    return [Math]::Min(300, (15 * [Math]::Pow(2, ($attempt - 1))))
}

function Test-QOTReplyQueueFailureRecoverable {
    param([AllowNull()][string]$FailureNote)

    $noteValue = ([string]($FailureNote + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($noteValue)) { return $true }

    foreach ($pattern in @(
        'classic outlook is not running',
        'unable to access classic outlook',
        'outlook com unavailable',
        'could not attach to classic outlook',
        'reply runner failed',
        'reply runner returned no output',
        'output parse failed',
        'processing -file',
        'does not have a ''.ps1'' extension',
        'server execution failed',
        'timed out',
        'temporary',
        'busy',
        'retry'
    )) {
        if ($noteValue -match [regex]::Escape($pattern)) {
            return $true
        }
    }

    return $false
}

function Resolve-QOTReplyQueueRunnerCommand {
    param(
        [AllowNull()]$ModuleInfo,
        [Parameter(Mandatory=$true)][string]$CommandName
    )

    $resolvedCommand = $null
    try {
        $resolvedCommand = @(Get-Command -Name $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($resolvedCommand -is [System.Array]) {
            if ($resolvedCommand.Count -gt 0) { $resolvedCommand = $resolvedCommand[0] } else { $resolvedCommand = $null }
        }
    } catch { $resolvedCommand = $null }
    if ($resolvedCommand) { return $resolvedCommand }

    if ($ModuleInfo) {
        try {
            $qualifiedName = ("{0}\{1}" -f [string]$ModuleInfo.Name, $CommandName)
            $resolvedCommand = @(Get-Command -Name $qualifiedName -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($resolvedCommand -is [System.Array]) {
                if ($resolvedCommand.Count -gt 0) { $resolvedCommand = $resolvedCommand[0] } else { $resolvedCommand = $null }
            }
        } catch { $resolvedCommand = $null }
        if ($resolvedCommand) { return $resolvedCommand }

        try {
            if ($ModuleInfo.ExportedCommands) {
                $resolvedKey = $null
                foreach ($exportedKey in @($ModuleInfo.ExportedCommands.Keys)) {
                    if (([string]$exportedKey) -ieq $CommandName) {
                        $resolvedKey = $exportedKey
                        break
                    }
                }
                if ($null -ne $resolvedKey) {
                    $resolvedCommand = $ModuleInfo.ExportedCommands[$resolvedKey]
                }
            }
        } catch { $resolvedCommand = $null }
        if ($resolvedCommand) { return $resolvedCommand }

        try {
            $resolvedCommand = @(Get-Command -Module $ModuleInfo.Name -Name $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($resolvedCommand -is [System.Array]) {
                if ($resolvedCommand.Count -gt 0) { $resolvedCommand = $resolvedCommand[0] } else { $resolvedCommand = $null }
            }
        } catch { $resolvedCommand = $null }
        if ($resolvedCommand) { return $resolvedCommand }

    }

    return $null
}

function ConvertFrom-QOTReplyQueueRunnerJson {
    param(
        [Parameter(Mandatory=$true)][string]$RawOutput
    )

    $trimmed = ([string]($RawOutput + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "Runner output was empty."
    }

    $firstBrace = $trimmed.IndexOf('{')
    if ($firstBrace -gt 0) {
        $trimmed = $trimmed.Substring($firstBrace)
    }

    return ($trimmed | ConvertFrom-Json -ErrorAction Stop)
}

function Read-QOTReplyQueueChildResult {
    param(
        [AllowNull()][string]$ResultPath,
        [AllowNull()][string]$StandardOutputPath,
        [AllowNull()][string]$StandardErrorPath,
        [int]$ExitCode = 0
    )

    $rawOutput = ""
    $stdoutText = ""
    $stderrText = ""
    try {
        if (-not [string]::IsNullOrWhiteSpace($ResultPath) -and (Test-Path -LiteralPath $ResultPath)) {
            $rawOutput = [string](Get-Content -LiteralPath $ResultPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawOutput = "" }
    try {
        if (-not [string]::IsNullOrWhiteSpace($StandardOutputPath) -and (Test-Path -LiteralPath $StandardOutputPath)) {
            $stdoutText = ([string](Get-Content -LiteralPath $StandardOutputPath -Raw -ErrorAction SilentlyContinue)).Trim()
        }
    } catch { $stdoutText = "" }
    try {
        if (-not [string]::IsNullOrWhiteSpace($StandardErrorPath) -and (Test-Path -LiteralPath $StandardErrorPath)) {
            $stderrText = ([string](Get-Content -LiteralPath $StandardErrorPath -Raw -ErrorAction SilentlyContinue)).Trim()
        }
    } catch { $stderrText = "" }

    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        $details = New-Object System.Collections.Generic.List[string]
        if ($ExitCode -ne 0) { $details.Add(("ExitCode=" + [string]$ExitCode)) | Out-Null }
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) { $details.Add(("STDERR: " + $stderrText)) | Out-Null }
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) { $details.Add(("STDOUT: " + $stdoutText)) | Out-Null }
        $note = "Reply runner returned no output."
        if ($details.Count -gt 0) {
            $note += " " + (($details.ToArray()) -join " | ")
        }
        return [pscustomobject]@{
            Success = $false
            Note    = $note
        }
    }

    try {
        $parsed = ConvertFrom-QOTReplyQueueRunnerJson -RawOutput $rawOutput
    } catch {
        return [pscustomobject]@{
            Success = $false
            Note    = ("Reply runner output parse failed: " + $_.Exception.Message)
        }
    }

    $success = $false
    $note = ""
    try { if ($parsed.PSObject.Properties.Name -contains "Success") { $success = [bool]$parsed.Success } } catch { $success = $false }
    try { if ($parsed.PSObject.Properties.Name -contains "Note") { $note = [string]$parsed.Note } } catch { $note = "" }
    if ($parsed.PSObject.Properties.Name -notcontains "Success") {
        if ($note -notmatch '(?i)\b(failed|unavailable|not found|required|missing|error)\b') {
            $success = $true
        }
    }

    if ($parsed.PSObject.Properties.Name -notcontains "Success") {
        try { $parsed | Add-Member -NotePropertyName Success -NotePropertyValue $success -Force } catch { }
    } else {
        try { $parsed.Success = $success } catch { }
    }
    if ($parsed.PSObject.Properties.Name -notcontains "Note") {
        try { $parsed | Add-Member -NotePropertyName Note -NotePropertyValue $note -Force } catch { }
    }

    return $parsed
}

function Invoke-QOTReplyQueueSendIsolated {
    param(
        [Parameter(Mandatory=$true)][string]$WorkerExePath,
        [Parameter(Mandatory=$true)]$Payload,
        [Parameter(Mandatory=$true)][string]$RuntimeRoot,
        [int]$TimeoutSeconds = 120
    )

    if ($TimeoutSeconds -lt 30) { $TimeoutSeconds = 30 }
    if ([string]::IsNullOrWhiteSpace($WorkerExePath) -or -not (Test-Path -LiteralPath $WorkerExePath)) {
        return [pscustomobject]@{
            Success = $false
            Note    = ("Reply worker executable is unavailable: " + $WorkerExePath)
        }
    }

    $tempRoot = ([string]($RuntimeRoot + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        $tempRoot = $env:TEMP
    }
    if (-not (Test-Path -LiteralPath $tempRoot)) {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    }

    $nonce = [guid]::NewGuid().ToString("N")
    $payloadPath = Join-Path $tempRoot ("reply-payload-" + $nonce + ".json")
    $resultPath = Join-Path $tempRoot ("reply-result-" + $nonce + ".json")

    $cleanupPaths = @($payloadPath, $resultPath)
    $replyProcess = $null
    try {
        ($payload | ConvertTo-Json -Depth 8 -Compress) | Set-Content -LiteralPath $payloadPath -Encoding UTF8 -ErrorAction Stop

        $argList = @(
            "send-reply",
            "--payload", $payloadPath,
            "--result", $resultPath
        )
        $quotedArgList = foreach ($argument in @($argList)) {
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
        $argumentString = ($quotedArgList -join ' ')

        $workingDirectory = Split-Path -Parent $WorkerExePath
        if ([string]::IsNullOrWhiteSpace($workingDirectory) -or -not (Test-Path -LiteralPath $workingDirectory)) {
            $workingDirectory = $env:TEMP
        }
        $replyProcess = Start-Process -FilePath $WorkerExePath -ArgumentList $argumentString -WorkingDirectory $workingDirectory -WindowStyle Hidden -PassThru
        $deadlineUtc = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)

        while ((Get-Date).ToUniversalTime() -lt $deadlineUtc) {
            Start-Sleep -Milliseconds 750

            try {
                if (Test-Path -LiteralPath $resultPath) {
                    $resultInfo = Get-Item -LiteralPath $resultPath -ErrorAction SilentlyContinue
                    if ($resultInfo -and $resultInfo.Length -gt 0) {
                        $exitCode = 0
                        try { if ($replyProcess) { $exitCode = [int]$replyProcess.ExitCode } } catch { $exitCode = 0 }
                        return (Read-QOTReplyQueueChildResult -ResultPath $resultPath -StandardOutputPath "" -StandardErrorPath "" -ExitCode $exitCode)
                    }
                }
            } catch { }

            try {
                if ($replyProcess -and $replyProcess.HasExited) { break }
            } catch { }
        }

        try {
            if ($replyProcess -and -not $replyProcess.HasExited) {
                try { $replyProcess.Kill() } catch { }
                try { $replyProcess.WaitForExit(5000) | Out-Null } catch { }
                return [pscustomobject]@{
                    Success = $false
                    Note    = ("Reply timed out after {0} seconds." -f [int]$TimeoutSeconds)
                }
            }
        } catch { }

        $processExitCode = 0
        try { if ($replyProcess) { $processExitCode = [int]$replyProcess.ExitCode } } catch { $processExitCode = 0 }
        return (Read-QOTReplyQueueChildResult -ResultPath $resultPath -StandardOutputPath "" -StandardErrorPath "" -ExitCode $processExitCode)
    } catch {
        return [pscustomobject]@{
            Success = $false
            Note    = ("Reply runner failed: " + $_.Exception.Message)
        }
    } finally {
        foreach ($cleanupPath in @($cleanupPaths)) {
            try {
                if (-not [string]::IsNullOrWhiteSpace([string]$cleanupPath) -and (Test-Path -LiteralPath $cleanupPath)) {
                    Remove-Item -LiteralPath $cleanupPath -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        }
    }
}

try {
    Write-QOTReplyQueueRunnerLog ("Reply queue runner starting. ToolkitRoot='{0}' ReplyCommand='{1}'" -f $ToolkitRoot, $ReplyCommand)

    if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
        throw "Toolkit root path is required."
    }

    $coreModulePath = Join-Path $ToolkitRoot "src\Core\Tickets.psm1"
    if (-not (Test-Path -LiteralPath $coreModulePath)) {
        throw ("Core tickets module not found: " + $coreModulePath)
    }

    $coreModule = Import-Module -Name $coreModulePath -Global -Force -PassThru -ErrorAction Stop -WarningAction SilentlyContinue | Select-Object -First 1
    if (-not $coreModule) {
        throw ("Core tickets module could not be imported: " + $coreModulePath)
    }

    $buildQualifiedCommandName = {
        param([Parameter(Mandatory=$true)][string]$CommandName)
        return ("{0}\{1}" -f [string]$coreModule.Name, $CommandName)
    }.GetNewClosure()

    $requiredCommands = @{}
    foreach ($requiredCommand in @(
        "Get-QOTickets",
        "Get-QOTPendingReplyQueueSnapshot",
        "Get-QOTNextPendingReply",
        "Set-QOTTicketPendingReplyState",
        "Remove-QOTTicketPendingReply",
        "Get-QOTTicketsReplyQueueMutexName",
        "Ensure-QOTTicketsWorker",
        "Get-QOTTicketsWorkerRuntimeRoot",
        "New-QOTTicketReplyWorkerPayload",
        "Complete-QOTTicketReplySend"
    )) {
        $resolvedRequiredCommand = $null
        $qualifiedRequiredCommand = & $buildQualifiedCommandName -CommandName $requiredCommand
        try {
            $resolvedRequiredCommand = @(Get-Command -Name $qualifiedRequiredCommand -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($resolvedRequiredCommand -is [System.Array]) {
                if ($resolvedRequiredCommand.Count -gt 0) { $resolvedRequiredCommand = $resolvedRequiredCommand[0] } else { $resolvedRequiredCommand = $null }
            }
        } catch { $resolvedRequiredCommand = $null }
        if (-not $resolvedRequiredCommand) {
            $resolvedRequiredCommand = Resolve-QOTReplyQueueRunnerCommand -ModuleInfo $coreModule -CommandName $requiredCommand
        }
        if (-not $resolvedRequiredCommand) {
            throw ("Required queue command unavailable: " + $requiredCommand)
        }
        $requiredCommands[$requiredCommand] = $resolvedRequiredCommand
    }

    $getTicketsCmd = $requiredCommands["Get-QOTickets"]
    $getQueueSnapshotCmd = $requiredCommands["Get-QOTPendingReplyQueueSnapshot"]
    $getNextPendingReplyCmd = $requiredCommands["Get-QOTNextPendingReply"]
    $setPendingReplyStateCmd = $requiredCommands["Set-QOTTicketPendingReplyState"]
    $removePendingReplyCmd = $requiredCommands["Remove-QOTTicketPendingReply"]
    $getMutexNameCmd = $requiredCommands["Get-QOTTicketsReplyQueueMutexName"]
    $ensureWorkerCmd = $requiredCommands["Ensure-QOTTicketsWorker"]
    $getWorkerRuntimeRootCmd = $requiredCommands["Get-QOTTicketsWorkerRuntimeRoot"]
    $buildReplyPayloadCmd = $requiredCommands["New-QOTTicketReplyWorkerPayload"]
    $completeReplySendCmd = $requiredCommands["Complete-QOTTicketReplySend"]
    $replyWorkerExePath = [string](& $ensureWorkerCmd)
    $replyWorkerRuntimeRoot = [string](& $getWorkerRuntimeRootCmd)
    if ([string]::IsNullOrWhiteSpace($replyWorkerExePath) -or -not (Test-Path -LiteralPath $replyWorkerExePath)) {
        throw "Reply worker executable is unavailable."
    }

    $mutexName = [string](& $getMutexNameCmd)
    if ([string]::IsNullOrWhiteSpace($mutexName)) {
        throw "Reply queue mutex name could not be resolved."
    }

    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $lockTaken = $false

    try {
        try {
            $lockTaken = $mutex.WaitOne(0, $false)
        } catch [System.Threading.AbandonedMutexException] {
            $lockTaken = $true
        }

        if (-not $lockTaken) {
            Write-QOTReplyQueueRunnerLog "Another reply queue runner is already active. Exiting."
            exit 0
        }

        while ($true) {
            $nextEntry = & $getNextPendingReplyCmd -StaleSendingSeconds $StaleSendingSeconds
            if (-not $nextEntry) {
                $remainingActiveReplies = @()
                try {
                    $queueSnapshot = & $getQueueSnapshotCmd
                    if ($queueSnapshot -and ($queueSnapshot.PSObject.Properties.Name -contains "Entries")) {
                        $remainingActiveReplies = @(
                            @($queueSnapshot.Entries) |
                                Where-Object {
                                    if (-not $_) { return $false }
                                    $isActive = $false
                                    try { if ($_.PSObject.Properties.Name -contains "IsActive") { $isActive = [bool]$_.IsActive } } catch { $isActive = $false }
                                    if ($isActive) { return $true }
                                    $stateValue = ""
                                    try { if ($_.PSObject.Properties.Name -contains "SendState") { $stateValue = ([string]($_.SendState + "")).Trim() } } catch { $stateValue = "" }
                                    return ($stateValue -match '^(?i)(Queued|Pending|Sending)$')
                                }
                        )
                    }
                } catch { $remainingActiveReplies = @() }

                if ($remainingActiveReplies.Count -gt 0) {
                    Write-QOTReplyQueueRunnerLog ("Reply queue runner is waiting for {0} queued replies to become due." -f $remainingActiveReplies.Count)
                    Start-Sleep -Seconds 15
                    continue
                }

                Write-QOTReplyQueueRunnerLog "Reply queue runner found no pending replies. Exiting."
                break
            }

            $ticketId = ([string]($nextEntry.TicketId + "")).Trim()
            $draftId = ([string]($nextEntry.DraftId + "")).Trim()
            $subject = ([string]($nextEntry.Subject + "")).Trim()
            $body = [string]($nextEntry.Body + "")
            $retryCount = 0
            try { $retryCount = [int]$nextEntry.RetryCount } catch { $retryCount = 0 }

            if ([string]::IsNullOrWhiteSpace($ticketId) -or [string]::IsNullOrWhiteSpace($draftId)) {
                Write-QOTReplyQueueRunnerLog "Reply queue entry was missing TicketId or DraftId. Skipping malformed entry." "WARN"
                Start-Sleep -Seconds 2
                continue
            }

            if ([string]::Equals(([string]($nextEntry.SendState + "")).Trim(), "Sending", [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-QOTReplyQueueRunnerLog ("Recovering stale sending reply DraftId='{0}' TicketId='{1}'." -f $draftId, $ticketId) "WARN"
            }

            $null = & $setPendingReplyStateCmd -TicketId $ticketId -DraftId $draftId -SendState Sending -FailureNote "" -RetryCount $retryCount -NextAttemptAt ""

            $db = & $getTicketsCmd -Quiet
            $ticket = @(
                @($db.Tickets) |
                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $ticketId) } |
                    Select-Object -First 1
            )
            if ($ticket -is [System.Array]) {
                if ($ticket.Count -gt 0) { $ticket = $ticket[0] } else { $ticket = $null }
            }

            if (-not $ticket) {
                Write-QOTReplyQueueRunnerLog ("Reply queue runner could not find ticket '{0}'. Marking reply as failed." -f $ticketId) "WARN"
                $null = & $setPendingReplyStateCmd -TicketId $ticketId -DraftId $draftId -SendState Failed -FailureNote ("Ticket not found: " + $ticketId) -RetryCount ($retryCount + 1) -NextAttemptAt ""
                continue
            }

            Write-QOTReplyQueueRunnerLog ("Sending queued reply DraftId='{0}' TicketId='{1}' RetryCount={2}" -f $draftId, $ticketId, $retryCount)
            $sendStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $payload = & $buildReplyPayloadCmd -Ticket $ticket -Subject $subject -Body $body -PendingReplyDraftId $draftId
            $rawResult = Invoke-QOTReplyQueueSendIsolated -WorkerExePath $replyWorkerExePath -Payload $payload -RuntimeRoot $replyWorkerRuntimeRoot -TimeoutSeconds $ReplySendTimeoutSeconds
            try { if ($sendStopwatch) { $sendStopwatch.Stop() } } catch { }

            $success = $false
            $note = ""
            try { if ($rawResult -and ($rawResult.PSObject.Properties.Name -contains "Success")) { $success = [bool]$rawResult.Success } } catch { $success = $false }
            try { if ($rawResult -and ($rawResult.PSObject.Properties.Name -contains "Note")) { $note = ([string]($rawResult.Note + "")).Trim() } } catch { $note = "" }
            if ([string]::IsNullOrWhiteSpace($note)) {
                $note = if ($success) { "Reply sent." } else { "Reply failed." }
            }
            Write-QOTReplyQueueRunnerLog ("Reply send completed. DraftId='{0}' TicketId='{1}' Success={2} DurationMs={3} Note='{4}'" -f $draftId, $ticketId, $success, [int]$sendStopwatch.Elapsed.TotalMilliseconds, $note)

            if ($success) {
                try {
                    $rawResult = & $completeReplySendCmd -Ticket $ticket -Subject $subject -Body $body -SendResult $rawResult -PendingReplyDraftId $draftId
                } catch {
                    Write-QOTReplyQueueRunnerLog ("Reply send succeeded but persistence completion failed. DraftId='{0}' TicketId='{1}' Error='{2}'" -f $draftId, $ticketId, $_.Exception.Message) "WARN"
                }
                try { $null = & $removePendingReplyCmd -TicketId $ticketId -DraftId $draftId } catch { }
                Write-QOTReplyQueueRunnerLog ("Queued reply sent successfully. DraftId='{0}' TicketId='{1}'" -f $draftId, $ticketId)
                continue
            }

            $nextRetryCount = $retryCount + 1
            $recoverable = Test-QOTReplyQueueFailureRecoverable -FailureNote $note
            if ($recoverable -and $nextRetryCount -lt $MaxFailureRetries) {
                $delaySeconds = [int](Get-QOTReplyQueueRetryDelaySeconds -RetryCount $nextRetryCount)
                $nextAttemptAt = (Get-Date).ToUniversalTime().AddSeconds($delaySeconds).ToString("o")
                $null = & $setPendingReplyStateCmd -TicketId $ticketId -DraftId $draftId -SendState Queued -FailureNote $note -RetryCount $nextRetryCount -NextAttemptAt $nextAttemptAt
                Write-QOTReplyQueueRunnerLog ("Queued reply failed and will retry in {0}s. DraftId='{1}' TicketId='{2}' Note='{3}'" -f $delaySeconds, $draftId, $ticketId, $note) "WARN"
                Start-Sleep -Seconds ([Math]::Min($delaySeconds, 10))
                continue
            }

            $null = & $setPendingReplyStateCmd -TicketId $ticketId -DraftId $draftId -SendState Failed -FailureNote $note -RetryCount $nextRetryCount -NextAttemptAt ""
            Write-QOTReplyQueueRunnerLog ("Queued reply marked failed. DraftId='{0}' TicketId='{1}' Note='{2}'" -f $draftId, $ticketId, $note) "WARN"
        }
    } finally {
        if ($lockTaken -and $mutex) {
            try { $mutex.ReleaseMutex() } catch { }
        }
        if ($mutex) {
            try { $mutex.Dispose() } catch { }
        }
    }

    exit 0
} catch {
    Write-QOTReplyQueueRunnerLog ("Reply queue runner failed. " + $_.Exception.Message) "ERROR"
    exit 1
}
