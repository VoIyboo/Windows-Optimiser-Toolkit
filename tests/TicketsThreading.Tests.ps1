$repoRoot = Split-Path -Parent $PSScriptRoot
$outlookModule = Import-Module (Join-Path $repoRoot "src\Tickets\Tickets.Email.Outlook.psm1") -Force -PassThru -ErrorAction Stop
$ticketsUiModule = Import-Module (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Force -PassThru -ErrorAction Stop

Describe "Ticket email threading" {
    It "matches customer replies back to an app-created ticket by customer and normalized subject" {
        InModuleScope $outlookModule.Name {
            $existing = [pscustomobject]@{
                Id = "ticket-1"
                Subject = "Printer help"
                EmailTo = "customer@example.test"
                SenderEmail = "customer@example.test"
                SourceMailbox = "support@example.test"
                CreatedAt = "2026-04-10 09:00:00"
            }

            $incoming = [pscustomobject]@{
                Id = "ticket-2"
                Subject = "RE: Printer help"
                EmailFrom = "Customer <customer@example.test>"
                SenderEmail = "customer@example.test"
                SourceMailbox = "support@example.test"
                EmailReceived = "2026-04-10 09:05:00"
                CreatedAt = "2026-04-10 09:05:00"
            }

            $existingKeys = @(Get-QOTTicketIdentityKeys -Ticket $existing)
            $incomingKeys = @(Get-QOTTicketIdentityKeys -Ticket $incoming)

            (@($existingKeys | Where-Object { $incomingKeys -contains $_ -and $_ -like "thread:*" }).Count -gt 0) | Should Be $true
        }
    }

    It "stores a new incoming Outlook message on the matched ticket instead of losing the reply body" {
        InModuleScope $outlookModule.Name {
            $existing = [pscustomobject]@{
                Id = "ticket-1"
                Subject = "Printer help"
                EmailTo = "customer@example.test"
                EmailConversationId = "conv-123"
                EmailMessageId = "<original@example.test>"
                SourceMessageId = "entry-original"
                IncomingMessages = @()
                UpdatedAt = "2026-04-10 09:00:00"
            }

            $incoming = [pscustomobject]@{
                Subject = "RE: Printer help"
                EmailFrom = "Customer <customer@example.test>"
                SenderName = "Customer"
                SenderEmail = "customer@example.test"
                SourceMailbox = "support@example.test"
                SourceMessageId = "entry-reply"
                SourceStoreId = "store-1"
                EmailMessageId = "<reply@example.test>"
                EmailConversationId = "conv-123"
                CreatedAt = "2026-04-10 09:05:00"
                UpdatedAt = "2026-04-10 09:05:00"
                EmailBody = "Here is the customer reply body."
            }

            $changed = Update-QOTExistingTicketFromMailItem -ExistingTicket $existing -IncomingTicket $incoming
            $changed | Should Be $true
            @($existing.IncomingMessages).Count | Should Be 1
            $existing.IncomingMessages[0].Body | Should Be "Here is the customer reply body."

            $changedAgain = Update-QOTExistingTicketFromMailItem -ExistingTicket $existing -IncomingTicket $incoming
            $changedAgain | Should Be $false
            @($existing.IncomingMessages).Count | Should Be 1
        }
    }

    It "includes stored incoming customer replies in the ticket details timeline" {
        InModuleScope $ticketsUiModule.Name {
            Mock Get-QOTickets { return [pscustomobject]@{ Tickets = @() } }

            $ticket = [pscustomobject]@{
                Id = "ticket-1"
                Subject = "Printer help"
                EmailFrom = "Customer <customer@example.test>"
                CreatedAt = "2026-04-10 09:00:00"
                EmailBody = "Original message"
                IncomingMessages = @(
                    [pscustomobject]@{
                        Subject = "RE: Printer help"
                        Body = "Customer follow-up"
                        From = "customer@example.test"
                        CreatedAt = "2026-04-10 09:05:00"
                    }
                )
                Replies = @()
                Notes = @()
            }

            $model = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            $incoming = @($model.Events | Where-Object { $_.Kind -eq "Incoming" })

            $incoming.Count | Should Be 1
            $incoming[0].Body | Should Be "Customer follow-up"
        }
    }
}
