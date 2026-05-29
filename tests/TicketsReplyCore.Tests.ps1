$repoRoot = Split-Path -Parent $PSScriptRoot
$ticketsModule = Import-Module (Join-Path $repoRoot "src\Core\Tickets.psm1") -Force -PassThru -ErrorAction Stop

Describe "Tickets core reply sending" {
    It "falls back to a new outbound email when a ticket has no Outlook reply reference" {
        InModuleScope $ticketsModule.Name {
            Mock Import-QOTOutlookIntegrationModule { return $true }
            Mock Send-QOTicketOutlookEmail {
                param(
                    [string]$To,
                    [string]$Subject,
                    [string]$Body,
                    [string]$FromMailbox,
                    [string]$TicketId
                )

                return [pscustomobject]@{
                    Success = $true
                    Note = ("sent to " + $To + " from " + $FromMailbox)
                    ConversationId = "conv-outbound-1"
                    SentEntryId = "sent-entry-1"
                    SentStoreId = "sent-store-1"
                    TicketId = $TicketId
                }
            }
            Mock Send-QOTicketOutlookReply { throw "reply path should not be used for manual outbound tickets" }
            Mock Update-QOTicket { return $true }

            $ticket = [pscustomobject]@{
                Id = "ticket-outbound-1"
                Subject = "Customer follow-up"
                EmailTo = "customer@example.test"
                SourceMailbox = "shared@example.test"
                Replies = @()
            }

            $result = Send-QOTicketReply -Ticket $ticket -Subject "Customer follow-up" -Body "Hello from QOT"

            $result.Success | Should Be $true
            $ticket.Replies.Count | Should Be 1
            $ticket.Replies[0].To | Should Be "customer@example.test"
            $ticket.Replies[0].FromMailbox | Should Be "shared@example.test"
            $ticket.Replies[0].ConversationId | Should Be "conv-outbound-1"
            $ticket.EmailConversationId | Should Be "conv-outbound-1"
            $ticket.LastOutboundMessageId | Should Be "sent-entry-1"
            Assert-MockCalled Send-QOTicketOutlookEmail -Times 1 -Exactly -ParameterFilter {
                $To -eq "customer@example.test" -and
                $Subject -eq "Customer follow-up" -and
                $Body -eq "Hello from QOT" -and
                $FromMailbox -eq "shared@example.test" -and
                $TicketId -eq "ticket-outbound-1"
            }
            Assert-MockCalled Send-QOTicketOutlookReply -Times 0 -Exactly
        }
    }

    It "lets the Outlook layer auto-select a sender mailbox for manual outbound emails" {
        InModuleScope $ticketsModule.Name {
            Mock Import-QOTOutlookIntegrationModule { return $true }
            function Get-QOTMonitoredMailboxAddresses { return @() }
            Mock Send-QOTicketOutlookEmail {
                param(
                    [string]$To,
                    [string]$Subject,
                    [string]$Body,
                    [string]$FromMailbox,
                    [string]$TicketId
                )

                return [pscustomobject]@{
                    Success = $true
                    Note = ("sent to " + $To)
                    ConversationId = "conv-outbound-2"
                    SentEntryId = "sent-entry-2"
                    SentStoreId = "sent-store-2"
                    TicketId = $TicketId
                }
            }
            Mock Send-QOTicketOutlookReply { throw "reply path should not be used for manual outbound tickets" }
            Mock Update-QOTicket { return $true }

            $ticket = [pscustomobject]@{
                Id = "ticket-outbound-2"
                Subject = "Customer follow-up"
                EmailTo = "customer@example.test"
                Replies = @()
            }

            $result = Send-QOTicketReply -Ticket $ticket -Subject "Customer follow-up" -Body "Hello from QOT"

            $result.Success | Should Be $true
            Assert-MockCalled Send-QOTicketOutlookEmail -Times 1 -Exactly -ParameterFilter {
                $To -eq "customer@example.test" -and
                $Subject -eq "Customer follow-up" -and
                $Body -eq "Hello from QOT" -and
                [string]::IsNullOrWhiteSpace($FromMailbox) -and
                $TicketId -eq "ticket-outbound-2"
            }
            Assert-MockCalled Send-QOTicketOutlookReply -Times 0 -Exactly
        }
    }

    It "uses the threaded Outlook reply path for self-addressed Outlook tickets when a reply reference exists" {
        InModuleScope $ticketsModule.Name {
            Mock Import-QOTOutlookIntegrationModule { return $true }
            function Get-QOTMonitoredMailboxAddresses { return @("amillar@sumo.com.au") }
            Mock Send-QOTicketOutlookEmail { throw "outbound email path should not be used for self-addressed mailbox tickets with a reply reference" }
            Mock Send-QOTicketOutlookReply {
                param(
                    $Ticket,
                    [string]$Subject,
                    [string]$Body,
                    [string]$FromMailbox,
                    [string]$TicketId
                )

                return [pscustomobject]@{
                    Success = $true
                    Note = "sent as threaded reply"
                    ConversationId = "conv-self-reply"
                    SentEntryId = "sent-self-reply-entry"
                    SentStoreId = "sent-self-reply-store"
                    TicketId = $TicketId
                }
            }
            Mock Update-QOTicket { return $true }

            $ticket = [pscustomobject]@{
                Id = "ticket-self-addressed"
                Subject = "Quinn Tool Test"
                EmailFrom = "Aaron Millar <amillar@sumo.com.au>"
                EmailTo = "amillar@sumo.com.au"
                SenderEmail = "amillar@sumo.com.au"
                SourceMailbox = "amillar@sumo.com.au"
                SourceMessageId = "source-message-self"
                Replies = @()
            }

            $result = Send-QOTicketReply -Ticket $ticket -Subject "RE: Quinn Tool Test" -Body "test"

            $result.Success | Should Be $true
            $ticket.Replies.Count | Should Be 1
            $ticket.Replies[0].To | Should Be "amillar@sumo.com.au"
            $ticket.Replies[0].FromMailbox | Should Be "amillar@sumo.com.au"
            $ticket.Replies[0].ConversationId | Should Be "conv-self-reply"
            $ticket.LastOutboundMessageId | Should Be "sent-self-reply-entry"
            Assert-MockCalled Send-QOTicketOutlookReply -Times 1 -Exactly -Scope It -ParameterFilter {
                $Ticket.Id -eq "ticket-self-addressed" -and
                $Subject -eq "RE: Quinn Tool Test" -and
                $Body -eq "test" -and
                $FromMailbox -eq "amillar@sumo.com.au" -and
                $TicketId -eq "ticket-self-addressed"
            }
            Assert-MockCalled Send-QOTicketOutlookEmail -Times 0 -Exactly -Scope It
        }
    }

    It "preserves newer queued replies when a queued send succeeds" {
        InModuleScope $ticketsModule.Name {
            Mock Import-QOTOutlookIntegrationModule { return $true }
            Mock Send-QOTicketOutlookEmail {
                return [pscustomobject]@{
                    Success = $true
                    Note = "sent"
                    ConversationId = "conv-queued-1"
                    SentEntryId = "sent-queued-entry-1"
                    SentStoreId = "sent-queued-store-1"
                }
            }
            Mock Send-QOTicketOutlookReply { throw "reply path should not be used for manual outbound tickets" }
            Mock Update-QOTicket { return $true }
            Mock Get-QOTickets {
                return [pscustomobject]@{
                    Tickets = @(
                        [pscustomobject]@{
                            Id = "ticket-queued-1"
                            PendingReplies = @(
                                [pscustomobject]@{
                                    DraftId = "draft-1"
                                    Subject = "Queued one"
                                    Body = "Body one"
                                    CreatedAt = "2026-05-08T00:00:00.0000000Z"
                                    LastAttemptAt = "2026-05-08T00:00:00.0000000Z"
                                    SendState = "Sending"
                                    FailureNote = ""
                                    RetryCount = 0
                                },
                                [pscustomobject]@{
                                    DraftId = "draft-2"
                                    Subject = "Queued two"
                                    Body = "Body two"
                                    CreatedAt = "2026-05-08T00:01:00.0000000Z"
                                    LastAttemptAt = "2026-05-08T00:01:00.0000000Z"
                                    SendState = "Queued"
                                    FailureNote = ""
                                    RetryCount = 0
                                }
                            )
                        }
                    )
                }
            }

            $ticket = [pscustomobject]@{
                Id = "ticket-queued-1"
                Subject = "Customer follow-up"
                EmailTo = "customer@example.test"
                SourceMailbox = "shared@example.test"
                Replies = @()
                PendingReplies = @(
                    [pscustomobject]@{
                        DraftId = "draft-1"
                        Subject = "Queued one"
                        Body = "Body one"
                        CreatedAt = "2026-05-08T00:00:00.0000000Z"
                        LastAttemptAt = "2026-05-08T00:00:00.0000000Z"
                        SendState = "Sending"
                        FailureNote = ""
                        RetryCount = 0
                    }
                )
            }

            $result = Send-QOTicketReply -Ticket $ticket -Subject "Customer follow-up" -Body "Hello from QOT" -PendingReplyDraftId "draft-1"

            $result.Success | Should Be $true
            $ticket.PendingReplies.Count | Should Be 1
            $ticket.PendingReplies[0].DraftId | Should Be "draft-2"
            $ticket.PendingReplies[0].Body | Should Be "Body two"
        }
    }

    It "rehydrates the full stored ticket before saving reply updates from a shell ticket" {
        InModuleScope $ticketsModule.Name {
            Mock Import-QOTOutlookIntegrationModule { return $true }
            Mock Send-QOTicketOutlookEmail {
                param(
                    [string]$To,
                    [string]$Subject,
                    [string]$Body,
                    [string]$FromMailbox,
                    [string]$TicketId
                )

                return [pscustomobject]@{
                    Success = $true
                    Note = "sent"
                    ConversationId = "conv-shell-1"
                    SentEntryId = "sent-shell-entry-1"
                    SentStoreId = "sent-shell-store-1"
                    TicketId = $TicketId
                }
            }
            Mock Send-QOTicketOutlookReply { throw "reply path should not be used for manual outbound tickets" }
            Mock Update-QOTicket { return $true }
            Mock Get-QOTickets {
                return [pscustomobject]@{
                    Tickets = @(
                        [pscustomobject]@{
                            Id = "ticket-shell-refresh-1"
                            Subject = "Stored subject"
                            EmailTo = "customer@example.test"
                            EmailFrom = "Alice <alice@example.test>"
                            SenderName = "Alice"
                            SenderEmail = "alice@example.test"
                            SourceMailbox = "shared@example.test"
                            Replies = @()
                            PendingReplies = @()
                        }
                    )
                }
            }

            $ticket = [pscustomobject]@{
                Id = "ticket-shell-refresh-1"
                Subject = "Stored subject"
                Replies = @()
                PendingReplies = @()
            }

            $result = Send-QOTicketReply -Ticket $ticket -Subject "Stored subject" -Body "Hello from QOT"

            $result.Success | Should Be $true
            $ticket.EmailTo | Should Be "customer@example.test"
            $ticket.SenderEmail | Should Be "alice@example.test"
            $ticket.Replies.Count | Should Be 1
            Assert-MockCalled Send-QOTicketOutlookEmail -Times 1 -Exactly -ParameterFilter {
                $To -eq "customer@example.test" -and
                $TicketId -eq "ticket-shell-refresh-1"
            }
            Assert-MockCalled Update-QOTicket -Times 1 -Exactly -ParameterFilter {
                $Ticket.Id -eq "ticket-shell-refresh-1" -and
                $Ticket.PSObject.Properties.Name -contains "EmailTo" -and
                $Ticket.EmailTo -eq "customer@example.test" -and
                $Ticket.PSObject.Properties.Name -contains "SenderEmail" -and
                $Ticket.SenderEmail -eq "alice@example.test"
            }
        }
    }

    It "normalizes persisted note and reply aliases so timeline activity reloads consistently" {
        InModuleScope $ticketsModule.Name {
            $db = [pscustomobject]@{
                Tickets = @(
                    [pscustomobject]@{
                        Id = "ticket-normalize-1"
                        Subject = "Reload me"
                        Notes = @()
                        InternalNotes = @(
                            [pscustomobject]@{
                                Body = "Stored internal note"
                                CreatedAt = "2026-05-12 10:00:00"
                                Author = "Casey"
                            }
                        )
                        Replies = @()
                        SentReplies = @(
                            [pscustomobject]@{
                                Subject = "RE: Reload me"
                                Body = "Stored sent reply"
                                CreatedAt = "2026-05-12 10:05:00"
                            }
                        )
                        PendingReplies = @(
                            [pscustomobject]@{
                                DraftId = "draft-normalize-1"
                                Subject = "Queued reply"
                                Body = "Queued body"
                                SendState = "pending"
                            }
                        )
                    }
                )
            }

            $normalized = Normalize-QOTicketDatabase -Database $db
            $ticket = @($normalized.Tickets)[0]

            @($ticket.Notes).Count | Should Be 1
            @($ticket.InternalNotes).Count | Should Be 0
            $ticket.Notes[0].Type | Should Be "InternalNote"

            @($ticket.Replies).Count | Should Be 1
            @($ticket.SentReplies).Count | Should Be 0
            $ticket.Replies[0].Type | Should Be "TechnicianReply"

            $ticket.PendingReplies[0].ReplyId | Should Be "draft-normalize-1"
            $ticket.PendingReplies[0].SendState | Should Be "Queued"
            $ticket.PendingReplies[0].LastError | Should Be ""

            foreach ($propName in @("Messages", "History", "Conversation", "SystemEvents", "Events", "Timeline", "Activity", "AuditTrail")) {
                (($ticket.PSObject.Properties.Name -contains $propName)) | Should Be $true
                @($ticket.$propName).Count | Should Be 0
            }
        }
    }

    It "stores internal notes only in the canonical note collection" {
        InModuleScope $ticketsModule.Name {
            Mock Save-QOTickets {}
            Mock Get-QOTickets {
                return [pscustomobject]@{
                    Tickets = @(
                        [pscustomobject]@{
                            Id = "ticket-note-sync-1"
                            Subject = "Ticket note sync"
                            Notes = @()
                            InternalNotes = @()
                        }
                    )
                }
            }

            $ticket = Add-QOTicketNote -Id "ticket-note-sync-1" -Note "Persist this note" -Author "Jordan" -NoteId "note-sync-1"

            @($ticket.Notes).Count | Should Be 1
            @($ticket.InternalNotes).Count | Should Be 0
            $ticket.Notes[0].NoteId | Should Be "note-sync-1"
            $ticket.Notes[0].Body | Should Be "Persist this note"
            Assert-MockCalled Save-QOTickets -Times 1 -Exactly
        }
    }

    It "stores completed replies only in the canonical reply collection" {
        InModuleScope $ticketsModule.Name {
            Mock Import-QOTOutlookIntegrationModule { return $true }
            Mock Send-QOTicketOutlookEmail {
                return [pscustomobject]@{
                    Success = $true
                    Note = "sent"
                    ConversationId = "conv-history-1"
                    SentEntryId = "sent-history-entry-1"
                    SentStoreId = "sent-history-store-1"
                    TicketId = "ticket-history-1"
                }
            }
            Mock Send-QOTicketOutlookReply { throw "reply path should not be used for manual outbound tickets" }
            Mock Update-QOTicket { return $true }

            $ticket = [pscustomobject]@{
                Id = "ticket-history-1"
                Subject = "History reply"
                EmailTo = "customer@example.test"
                SourceMailbox = "shared@example.test"
                Replies = @()
                SentReplies = @()
            }

            $result = Send-QOTicketReply -Ticket $ticket -Subject "History reply" -Body "Stored body"

            $result.Success | Should Be $true
            @($ticket.Replies).Count | Should Be 1
            @($ticket.SentReplies).Count | Should Be 0
            $ticket.Replies[0].Body | Should Be "Stored body"
        }
    }
}
