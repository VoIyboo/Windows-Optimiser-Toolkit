$repoRoot = Split-Path -Parent $PSScriptRoot
$ticketsModule = Import-Module (Join-Path $repoRoot "src\Core\Tickets.psm1") -Force -PassThru -ErrorAction Stop

Describe "Tickets core reply queue service" {
    It "starts the detached queue worker with hidden PowerShell launch settings" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Core\Tickets.psm1") -Raw

        $moduleSource | Should Match 'function Start-QOTicketsReplyQueueWorker'
        $moduleSource | Should Match '\"-NoProfile\"'
        $moduleSource | Should Match '\"-ExecutionPolicy\", \"Bypass\"'
        $moduleSource | Should Match '\"-WindowStyle\", \"Hidden\"'
        $moduleSource | Should Match 'Start-Process -FilePath \$exePath -ArgumentList \$argumentString -WorkingDirectory \$workingDirectory -WindowStyle Hidden -PassThru'
    }

    It "builds a queue snapshot with restored active counts and positions" {
        InModuleScope $ticketsModule.Name {
            Mock Get-QOTicketPendingReplies {
                return @(
                    [pscustomobject]@{
                        TicketId      = "ticket-1"
                        DraftId       = "draft-sending"
                        Subject       = "Sending now"
                        Body          = "Body one"
                        CreatedAt     = "2026-05-10T00:00:00.0000000Z"
                        LastAttemptAt = "2026-05-10T00:01:00.0000000Z"
                        NextAttemptAt = ""
                        SendState     = "Sending"
                        FailureNote   = ""
                        RetryCount    = 1
                    },
                    [pscustomobject]@{
                        TicketId      = "ticket-2"
                        DraftId       = "draft-queued"
                        Subject       = "Queued next"
                        Body          = "Body two"
                        CreatedAt     = "2026-05-10T00:02:00.0000000Z"
                        LastAttemptAt = "2026-05-10T00:02:00.0000000Z"
                        NextAttemptAt = "2026-05-10T00:03:00.0000000Z"
                        SendState     = "Queued"
                        FailureNote   = "Outlook busy"
                        RetryCount    = 2
                    },
                    [pscustomobject]@{
                        TicketId      = "ticket-3"
                        DraftId       = "draft-failed"
                        Subject       = "Failed"
                        Body          = "Body three"
                        CreatedAt     = "2026-05-10T00:04:00.0000000Z"
                        LastAttemptAt = "2026-05-10T00:05:00.0000000Z"
                        NextAttemptAt = ""
                        SendState     = "Failed"
                        FailureNote   = "Mailbox unavailable"
                        RetryCount    = 4
                    }
                )
            }
            Mock Test-QOTicketsReplyQueueWorkerRunning { return $true }

            $snapshot = Get-QOTPendingReplyQueueSnapshot

            $snapshot.ActiveCount | Should Be 2
            $snapshot.QueuedCount | Should Be 1
            $snapshot.SendingCount | Should Be 1
            $snapshot.FailedCount | Should Be 1
            $snapshot.WorkerRunning | Should Be $true

            $sendingEntry = @($snapshot.Entries | Where-Object { $_.DraftId -eq "draft-sending" })[0]
            $queuedEntry = @($snapshot.Entries | Where-Object { $_.DraftId -eq "draft-queued" })[0]
            $failedEntry = @($snapshot.Entries | Where-Object { $_.DraftId -eq "draft-failed" })[0]

            $sendingEntry.QueuePosition | Should Be 1
            $queuedEntry.QueuePosition | Should Be 2
            $queuedEntry.QueueTotal | Should Be 2
            $failedEntry.QueuePosition | Should Be 0
            $failedEntry.QueueTotal | Should Be 0
        }
    }

    It "rehydrates restored active replies by starting the worker when needed" {
        InModuleScope $ticketsModule.Name {
            Mock Write-QOTicketsCoreLog {}
            Mock Get-QOTPendingReplyQueueSnapshot {
                return [pscustomobject]@{
                    Entries       = @(
                        [pscustomobject]@{
                            TicketId   = "ticket-1"
                            DraftId    = "draft-1"
                            SendState  = "Queued"
                            IsActive   = $true
                        }
                    )
                    ActiveCount   = 2
                    QueuedCount   = 1
                    SendingCount  = 1
                    FailedCount   = 0
                    WorkerRunning = $false
                }
            }
            Mock Start-QOTicketsReplyQueueWorker {
                param([string]$Reason)
                return [pscustomobject]@{
                    Started        = $true
                    AlreadyRunning = $false
                    ActiveCount    = 2
                    Note           = "Reply queue worker started."
                }
            }
            Mock Test-QOTicketsReplyQueueWorkerRunning { return $true }

            $result = Initialize-QOTicketsReplyQueueService -Reason "startup-test"

            $result.Rehydrated | Should Be $true
            $result.ActiveCount | Should Be 2
            $result.WorkerStarted | Should Be $true
            $result.WorkerRunning | Should Be $true
            Assert-MockCalled Start-QOTicketsReplyQueueWorker -Times 1 -Exactly -ParameterFilter { $Reason -eq "startup-test" }
            Assert-MockCalled Write-QOTicketsCoreLog -Times 1 -ParameterFilter { $Message -match 'Pending reply loaded from storage' }
            Assert-MockCalled Write-QOTicketsCoreLog -Times 1 -ParameterFilter { $Message -match 'Pending reply added to active queue' }
        }
    }

    It "retries a failed reply as a clean new queued attempt" {
        InModuleScope $ticketsModule.Name {
            Mock Write-QOTicketsCoreLog {}
            Mock Get-QOTTicketPendingReply {
                return [pscustomobject]@{
                    TicketId      = "ticket-1"
                    DraftId       = "draft-1"
                    Subject       = "Failed reply"
                    Body          = "Retry me"
                    CreatedAt     = "2026-05-10T00:00:00.0000000Z"
                    LastAttemptAt = "2026-05-10T00:01:00.0000000Z"
                    NextAttemptAt = "2026-05-10T00:06:00.0000000Z"
                    SendState     = "Failed"
                    FailureNote   = "Outlook unavailable"
                    RetryCount    = 3
                }
            }
            Mock Remove-QOTTicketPendingReply { return $true }
            Mock Add-QOTTicketPendingReply {
                param(
                    [string]$TicketId,
                    [string]$Subject,
                    [string]$Body,
                    [string]$DraftId,
                    [string]$SendState,
                    [AllowNull()]$Ticket
                )

                return [pscustomobject]@{
                    ReplyId       = $DraftId
                    TicketId      = $TicketId
                    DraftId       = $DraftId
                    Subject       = $Subject
                    Body          = $Body
                    To            = ""
                    MessageId     = ""
                    ConversationId = ""
                    SourceMessageId = ""
                    SenderMailbox = ""
                    CreatedAt     = "2026-05-10T00:02:00.0000000Z"
                    LastAttemptAt = "2026-05-10T00:02:00.0000000Z"
                    NextAttemptAt = ""
                    SendState     = $SendState
                    FailureNote   = ""
                    LastError     = ""
                    RetryCount    = 0
                    SentAt        = ""
                    DuplicateSuppressed = $false
                }
            }
            Mock Initialize-QOTicketsReplyQueueService {
                return [pscustomobject]@{
                    WorkerRunning = $true
                    WorkerStarted = $false
                    ActiveCount   = 1
                }
            }

            $result = Retry-QOTTicketPendingReply -TicketId "ticket-1" -DraftId "draft-1"

            $result.SendState | Should Be "Queued"
            $result.NextAttemptAt | Should Be ""
            $result.OldDraftId | Should Be "draft-1"
            $result.DraftId | Should Not Be "draft-1"
            $result.Subject | Should Be "Failed reply"
            $result.Body | Should Be "Retry me"
            Assert-MockCalled Write-QOTicketsCoreLog -Times 1 -Scope It -ParameterFilter { $Message -match "Reason='retry'" }
            Assert-MockCalled Remove-QOTTicketPendingReply -Times 1 -Exactly -Scope It -ParameterFilter {
                $TicketId -eq "ticket-1" -and
                $DraftId -eq "draft-1"
            }
            Assert-MockCalled Add-QOTTicketPendingReply -Times 1 -Exactly -Scope It -ParameterFilter {
                $TicketId -eq "ticket-1" -and
                $Subject -eq "Failed reply" -and
                $Body -eq "Retry me" -and
                $SendState -eq "Queued" -and
                $DraftId -ne "draft-1"
            }
        }
    }

    It "marks stale sending replies failed during startup queue repair" {
        InModuleScope $ticketsModule.Name {
            $staleAttempt = (Get-Date).ToUniversalTime().AddHours(-2).ToString("o")
            $pendingReply = [pscustomobject]@{
                ReplyId       = "draft-stale"
                DraftId       = "draft-stale"
                Subject       = "Stale send"
                Body          = "This should not stay sending"
                CreatedAt     = $staleAttempt
                LastAttemptAt = $staleAttempt
                NextAttemptAt = ""
                SendState     = "Sending"
                FailureNote   = ""
                RetryCount    = 1
                LastError     = ""
                SentAt        = ""
            }
            $db = [pscustomobject]@{
                Tickets = @(
                    [pscustomobject]@{
                        Id             = "ticket-1"
                        PendingReplies = @($pendingReply)
                    }
                )
            }

            Mock Write-QOTicketsCoreLog {}
            Mock Test-QOTicketsReplyQueueWorkerRunning { return $false }
            Mock Get-QOTickets { return $db }
            Mock Save-QOTickets {}

            $result = Repair-QOTPendingReplyQueueState -StaleSendingSeconds 60 -RecoverOrphanedSending

            $result.Updated | Should Be $true
            $result.RecoveredCount | Should Be 1
            $pendingReply.SendState | Should Be "Failed"
            $pendingReply.FailureNote | Should Match "Use Retry"
            Assert-MockCalled Save-QOTickets -Times 1 -Exactly -Scope It
            Assert-MockCalled Write-QOTicketsCoreLog -Times 1 -Scope It -ParameterFilter { $Message -match "Marked stuck sending reply as failed" }
        }
    }

    It "does not cancel a reply that is already being sent by the worker" {
        InModuleScope $ticketsModule.Name {
            Mock Write-QOTicketsCoreLog {}
            Mock Get-QOTTicketPendingReply {
                return [pscustomobject]@{
                    TicketId   = "ticket-1"
                    DraftId    = "draft-1"
                    SendState  = "Sending"
                    RetryCount = 1
                }
            }
            Mock Test-QOTicketsReplyQueueWorkerRunning { return $true }
            Mock Remove-QOTTicketPendingReply { return $true }

            $result = Cancel-QOTTicketPendingReply -TicketId "ticket-1" -DraftId "draft-1"

            $result.Cancelled | Should Be $false
            $result.Reason | Should Match "already sending"
            Assert-MockCalled Remove-QOTTicketPendingReply -Times 0 -Exactly -Scope It
            Assert-MockCalled Write-QOTicketsCoreLog -Times 0 -Scope It -ParameterFilter { $Message -match 'removed from active queue' }
        }
    }

    It "logs when a pending reply is removed from storage and the active queue" {
        InModuleScope $ticketsModule.Name {
            Mock Write-QOTicketsCoreLog {}
            Mock Get-QOTTicketPendingReply {
                return [pscustomobject]@{
                    TicketId   = "ticket-1"
                    DraftId    = "draft-1"
                    SendState  = "Queued"
                    RetryCount = 1
                }
            }
            Mock Test-QOTicketsReplyQueueWorkerRunning { return $false }
            Mock Remove-QOTTicketPendingReply { return $true }

            $result = Cancel-QOTTicketPendingReply -TicketId "ticket-1" -DraftId "draft-1"

            $result.Cancelled | Should Be $true
            Assert-MockCalled Remove-QOTTicketPendingReply -Times 1 -Exactly -Scope It
            Assert-MockCalled Write-QOTicketsCoreLog -Times 1 -Scope It -ParameterFilter { $Message -match 'removed from active queue' }
        }
    }

    AfterAll {
        Remove-Module $ticketsModule.Name -Force -ErrorAction SilentlyContinue
        Remove-Module Tickets -Force -ErrorAction SilentlyContinue
    }
}
