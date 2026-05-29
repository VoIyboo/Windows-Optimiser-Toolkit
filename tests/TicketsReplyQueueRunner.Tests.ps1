$repoRoot = Split-Path -Parent $PSScriptRoot
$queueRunnerPath = Join-Path $repoRoot "src\Tickets\Tickets.Email.ReplyQueueRunner.ps1"

Describe "Tickets reply queue runner" {
    It "resolves required queue commands from the imported core module exports" {
        $runnerSource = Get-Content -LiteralPath $queueRunnerPath -Raw

        $runnerSource | Should Match 'function Resolve-QOTReplyQueueRunnerCommand'
        $runnerSource | Should Match '\$ModuleInfo\.ExportedCommands'
        $runnerSource | Should Match '\$qualifiedName = \("\{0\}\\\{1\}" -f \[string\]\$ModuleInfo\.Name, \$CommandName\)'
        $runnerSource | Should Match '\$buildQualifiedCommandName = \{'
        $runnerSource | Should Match 'Get-Command -Name \$qualifiedRequiredCommand'
        $runnerSource | Should Match 'foreach \(\$exportedKey in @\(\$ModuleInfo\.ExportedCommands\.Keys\)\)'
        $runnerSource | Should Match '\(\[string\]\$exportedKey\) -ieq \$CommandName'
        $runnerSource | Should Match 'Resolve-QOTReplyQueueRunnerCommand -ModuleInfo \$coreModule -CommandName \$requiredCommand'
        $runnerSource | Should Match 'Get-QOTPendingReplyQueueSnapshot'
        $runnerSource | Should Match '& \$getQueueSnapshotCmd'
        $runnerSource | Should Match 'Ensure-QOTTicketsWorker'
        $runnerSource | Should Match 'Get-QOTTicketsWorkerRuntimeRoot'
        $runnerSource | Should Match 'New-QOTTicketReplyWorkerPayload'
        $runnerSource | Should Match 'Complete-QOTTicketReplySend'
        $runnerSource | Should Match 'Invoke-QOTReplyQueueSendIsolated -WorkerExePath \$replyWorkerExePath -Payload \$payload -RuntimeRoot \$replyWorkerRuntimeRoot'
    }

    It "drains a persisted queued reply and removes it from the pending store" {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-reply-queue-runner-" + [guid]::NewGuid().ToString("N"))
        $coreDir = Join-Path $tempRoot "src\Core"
        $coreModulePath = Join-Path $coreDir "Tickets.psm1"
        $statePath = Join-Path $tempRoot "state.json"

        try {
            $null = New-Item -ItemType Directory -Path $coreDir -Force

            @'
function Get-TestStatePath {
    return (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "state.json")
}

function Read-TestState {
    $path = Get-TestStatePath
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Write-TestState {
    param([Parameter(Mandatory)]$State)

    $path = Get-TestStatePath
    $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-QOTicketsStorePath {
    return (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "tickets.json")
}

function Get-WorkerPath {
    return (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "fake-worker.cmd")
}

function Ensure-QOTTicketsWorker {
    $path = Get-WorkerPath
    if (-not (Test-Path -LiteralPath $path)) {
@" 
@echo off
> "%~5" echo {"Success":true,"Note":"Reply sent.","ConversationId":"conv-1","SentEntryId":"entry-1","SentStoreId":"store-1"}
exit /b 0
"@ | Set-Content -LiteralPath $path -Encoding ASCII
    }
    return $path
}

function Get-QOTTicketsWorkerRuntimeRoot {
    return (Split-Path -Parent (Get-WorkerPath))
}

function Get-QOTTicketsReplyQueueMutexName {
    return "Local\QOTReplyQueueRunnerTest"
}

function Get-QOTickets {
    param([switch]$Quiet)

    $state = Read-TestState
    return [pscustomobject]@{
        Tickets = @($state.Tickets)
    }
}

function Get-QOTTicketPendingReplies {
    param([string]$TicketId)

    $state = Read-TestState
    $pending = @($state.PendingReplies)
    if ([string]::IsNullOrWhiteSpace([string]$TicketId)) {
        return $pending
    }

    return @(
        $pending |
            Where-Object {
                $_ -and
                ($_.PSObject.Properties.Name -contains "TicketId") -and
                ([string]$_.TicketId -eq [string]$TicketId)
            }
    )
}

function Get-QOTNextPendingReply {
    param([int]$StaleSendingSeconds = 600)

    $state = Read-TestState
    return @(
        @($state.PendingReplies) |
            Where-Object {
                $_ -and
                ($_.PSObject.Properties.Name -contains "SendState") -and
                ([string]$_.SendState -match '^(?i)(Queued|Pending)$')
            } |
            Select-Object -First 1
    )[0]
}

function Get-QOTPendingReplyQueueSnapshot {
    $state = Read-TestState
    $entries = @($state.PendingReplies)
    return [pscustomobject]@{
        Entries = @(
            $entries |
                ForEach-Object {
                    if (-not $_) { return }
                    [pscustomobject]@{
                        TicketId = [string]$_.TicketId
                        DraftId = [string]$_.DraftId
                        SendState = [string]$_.SendState
                        IsActive = ([string]$_.SendState -match '^(?i)(Queued|Pending|Sending)$')
                    }
                }
        )
    }
}

function Set-QOTTicketPendingReplyState {
    param(
        [string]$TicketId,
        [string]$DraftId,
        [string]$SendState,
        [string]$FailureNote,
        [int]$RetryCount = -1,
        [string]$NextAttemptAt = ""
    )

    $state = Read-TestState
    foreach ($pending in @($state.PendingReplies)) {
        if (-not $pending) { continue }
        if ([string]$pending.TicketId -ne [string]$TicketId) { continue }
        if ([string]$pending.DraftId -ne [string]$DraftId) { continue }

        $pending.SendState = $SendState
        $pending.FailureNote = $FailureNote
        $pending.NextAttemptAt = $NextAttemptAt
        if ($RetryCount -ge 0) {
            $pending.RetryCount = $RetryCount
        }
        $pending.LastAttemptAt = "2026-05-08T00:00:05.0000000Z"
        Write-TestState -State $state
        return $pending
    }

    return $null
}

function Remove-QOTTicketPendingReply {
    param(
        [string]$TicketId,
        [string]$DraftId
    )

    $state = Read-TestState
    $state.PendingReplies = @(
        @($state.PendingReplies) |
            Where-Object {
                if (-not $_) { return $false }
                return (-not (([string]$_.TicketId -eq [string]$TicketId) -and ([string]$_.DraftId -eq [string]$DraftId)))
            }
    )
    Write-TestState -State $state
    return $true
}

function New-QOTTicketReplyWorkerPayload {
    param(
        [Parameter(Mandatory)]$Ticket,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [string]$PendingReplyDraftId
    )

    return [pscustomobject]@{
        TicketId = [string]$Ticket.Id
        PendingReplyDraftId = [string]$PendingReplyDraftId
        Subject = $Subject
        Body = $Body
        To = "customer@example.com"
        SenderMailbox = "support@example.com"
        SourceMessageId = ""
        SourceStoreId = ""
        EmailMessageId = ""
    }
}

function Complete-QOTTicketReplySend {
    param(
        [Parameter(Mandatory)]$Ticket,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)]$SendResult,
        [string]$Status,
        [string]$PendingReplyDraftId
    )

    $state = Read-TestState
    $state.SentReplies = @($state.SentReplies) + @([pscustomobject]@{
        TicketId = [string]$Ticket.Id
        DraftId = [string]$PendingReplyDraftId
        Subject = $Subject
        Body = $Body
        SentEntryId = [string]$SendResult.SentEntryId
        SentStoreId = [string]$SendResult.SentStoreId
    })
    Write-TestState -State $state

    if ($SendResult.PSObject.Properties.Name -contains "Persisted") {
        $SendResult.Persisted = $true
    } else {
        $SendResult | Add-Member -NotePropertyName Persisted -NotePropertyValue $true -Force
    }
    return $SendResult
}

Export-ModuleMember -Function Get-QOTicketsStorePath, Ensure-QOTTicketsWorker, Get-QOTTicketsWorkerRuntimeRoot, Get-QOTTicketsReplyQueueMutexName, Get-QOTickets, Get-QOTTicketPendingReplies, Get-QOTPendingReplyQueueSnapshot, Get-QOTNextPendingReply, Set-QOTTicketPendingReplyState, Remove-QOTTicketPendingReply, New-QOTTicketReplyWorkerPayload, Complete-QOTTicketReplySend
'@ | Set-Content -LiteralPath $coreModulePath -Encoding UTF8

            @'
{
  "Tickets": [
    {
      "Id": "ticket-1"
    }
  ],
  "PendingReplies": [
    {
      "TicketId": "ticket-1",
      "DraftId": "draft-1",
      "Subject": "Queued subject",
      "Body": "Queued body",
      "CreatedAt": "2026-05-08T00:00:00.0000000Z",
      "LastAttemptAt": "2026-05-08T00:00:00.0000000Z",
      "NextAttemptAt": "",
      "SendState": "Queued",
      "FailureNote": "",
      "RetryCount": 0
    }
  ],
  "SentReplies": []
}
'@ | Set-Content -LiteralPath $statePath -Encoding UTF8

            $powershellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
            $arguments = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $queueRunnerPath,
                "-ToolkitRoot", $tempRoot
            )

            & $powershellExe @arguments | Out-Null

            $LASTEXITCODE | Should Be 0
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            @($state.PendingReplies).Count | Should Be 0
            @($state.SentReplies).Count | Should Be 1
            $state.SentReplies[0].DraftId | Should Be "draft-1"
            $state.SentReplies[0].Subject | Should Be "Queued subject"
        } finally {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
