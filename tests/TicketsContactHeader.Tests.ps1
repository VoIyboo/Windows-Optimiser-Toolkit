$repoRoot = Split-Path -Parent $PSScriptRoot
$ticketsUiModule = Import-Module (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Force -PassThru -ErrorAction Stop

Describe "Ticket contact header" {
    It "uses the email address from the message body when Outlook only stored a legacy Exchange sender" {
        InModuleScope $ticketsUiModule.Name {
            $ticket = [pscustomobject]@{
                Id               = "ticket-legacy-sender"
                Source           = "Outlook"
                EmailFrom        = "/O=EXCHANGELABS/OU=EXCHANGE ADMINISTRATIVE GROUP/CN=RECIPIENTS/CN=A13A21D92447489DBF805412CBEF63BB-92F324EF-3F"
                EmailBodyPreview = "hello`r`n`r`nCheers,`r`nAaron Millar`r`nEmail:  amillar@sumo.com.au"
                AssignedTo       = "Unassigned"
            }

            $model = Get-QOTicketContactHeaderModel -Ticket $ticket

            $model.PrimaryText | Should Be "amillar@sumo.com.au"
            $model.Initials | Should Be "AM"
        }
    }

    It "uses the request/customer address on manually-created email tickets" {
        InModuleScope $ticketsUiModule.Name {
            function Get-QOTMonitoredMailboxAddresses { return @("support@example.test") }

            $ticket = [pscustomobject]@{
                Id         = "manual-request"
                Source     = "Manual"
                EmailTo    = "customer@example.test"
                AssignedTo = "Unassigned"
            }

            $model = Get-QOTicketContactHeaderModel -Ticket $ticket

            $model.PrimaryText | Should Be "customer@example.test"
            $model.MetaText | Should Be "Unassigned"
        }
    }

    It "does not treat the monitored mailbox as the customer when only EmailTo is available" {
        InModuleScope $ticketsUiModule.Name {
            function Get-QOTMonitoredMailboxAddresses { return @("support@example.test") }

            $ticket = [pscustomobject]@{
                Id         = "mailbox-only"
                Source     = "Outlook"
                EmailTo    = "support@example.test"
                AssignedTo = "Unassigned"
            }

            $model = Get-QOTicketContactHeaderModel -Ticket $ticket

            $model.PrimaryText | Should Be "Email sender unavailable"
        }
    }
}
