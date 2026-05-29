$repoRoot = Split-Path -Parent $PSScriptRoot
Remove-Module Tickets.UI, Tickets, Tickets.Email.Outlook -Force -ErrorAction SilentlyContinue
$outlookModule = Import-Module (Join-Path $repoRoot "src\Tickets\Tickets.Email.Outlook.psm1") -Force -PassThru -ErrorAction Stop

Describe "Tickets reply Outlook fallback" {
    It "retries reply attach with Outlook startup enabled when fast attach fails" {
        InModuleScope $outlookModule.Name {
            function Initialize-QOTicketsCoreApi {}
            function Write-QOTOutlookSyncLog { param($Message, $Level) }
            function Get-QOTMonitoredMailboxAddresses { return @() }
            $script:NoStartAttachAttempts = 0
            $script:StartupAttachAttempts = 0
            function Get-QOTOutlookNamespace {
                param([switch]$AllowStartOutlook)
                if (-not $AllowStartOutlook) {
                    $script:NoStartAttachAttempts++
                    throw "Classic Outlook is not running. Open Outlook and retry."
                }

                $script:StartupAttachAttempts++
                return [pscustomobject]@{ Name = "MAPI" }
            }

            $fakeReply = New-Object psobject
            $fakeReply | Add-Member -NotePropertyName Subject -NotePropertyValue ""
            $fakeReply | Add-Member -NotePropertyName HTMLBody -NotePropertyValue "<div>thread</div>"
            $fakeReply | Add-Member -NotePropertyName Body -NotePropertyValue ""
            $fakeReply | Add-Member -MemberType ScriptMethod -Name GetInspector -Value { return $null }
            $fakeReply | Add-Member -MemberType ScriptMethod -Name Send -Value { return $null }
            $script:FakeReplyForFallbackTest = $fakeReply

            $fakeMailItem = New-Object psobject
            $fakeMailItem | Add-Member -MemberType ScriptMethod -Name Reply -Value { return $script:FakeReplyForFallbackTest }
            $script:FakeMailItemForFallbackTest = $fakeMailItem

            function Find-QOTOutlookMessageByInternetId { return $script:FakeMailItemForFallbackTest }

            $ticket = [pscustomobject]@{
                Id = "ticket-1"
                EmailMessageId = "message@example.test"
            }

            $result = Send-QOTicketOutlookReply -Ticket $ticket -Subject "Test reply" -Body "hello"

            $result.Success | Should Be $true
            $script:NoStartAttachAttempts | Should Be 1
            $script:StartupAttachAttempts | Should Be 1
        }
    }

    It "retries with a simpler reply draft when Outlook rejects the rich send attempt" {
        InModuleScope $outlookModule.Name {
            function Initialize-QOTicketsCoreApi {}
            function Write-QOTOutlookSyncLog { param($Message, $Level) }
            function Get-QOTMonitoredMailboxAddresses { return @() }

            $script:RetryReplyInvocationCount = 0

            $richReply = New-Object psobject
            $richReply | Add-Member -NotePropertyName Subject -NotePropertyValue ""
            $richReply | Add-Member -NotePropertyName HTMLBody -NotePropertyValue "<div>thread</div>"
            $richReply | Add-Member -NotePropertyName Body -NotePropertyValue ""
            $richReply | Add-Member -MemberType ScriptMethod -Name Send -Value { throw "Value does not fall within the expected range." }

            $plainReply = New-Object psobject
            $plainReply | Add-Member -NotePropertyName Subject -NotePropertyValue ""
            $plainReply | Add-Member -NotePropertyName HTMLBody -NotePropertyValue ""
            $plainReply | Add-Member -NotePropertyName Body -NotePropertyValue ""
            $plainReply | Add-Member -MemberType ScriptMethod -Name Send -Value { return $null }

            $fakeMailItem = New-Object psobject
            $fakeMailItem | Add-Member -MemberType ScriptMethod -Name Reply -Value {
                $script:RetryReplyInvocationCount++
                if ($script:RetryReplyInvocationCount -eq 1) {
                    return $script:RichReplyForRetryTest
                }

                return $script:PlainReplyForRetryTest
            }
            $script:RichReplyForRetryTest = $richReply
            $script:PlainReplyForRetryTest = $plainReply

            $fakeMapi = New-Object psobject
            $fakeMapi | Add-Member -NotePropertyName Name -NotePropertyValue "MAPI"
            $fakeMapi | Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value { param($SourceId, $StoreId) return $script:RetryMailItemForRetryTest }
            $script:RetryMailItemForRetryTest = $fakeMailItem
            $script:RetryMAPIForRetryTest = $fakeMapi
            function Get-QOTOutlookNamespace { return $script:RetryMAPIForRetryTest }

            $ticket = [pscustomobject]@{
                Id = "ticket-retry-1"
                SourceMessageId = "source-message-1"
                SourceStoreId = "source-store-1"
            }

            $result = Send-QOTicketOutlookReply -Ticket $ticket -Subject "Retry reply" -Body "hello"

            $result.Success | Should Be $true
            $script:RetryReplyInvocationCount | Should Be 2
            $script:RichReplyForRetryTest.HTMLBody | Should Match "hello"
            $script:PlainReplyForRetryTest.Body | Should Match "hello"
        }
    }

    It "applies the configured sender mailbox to Outlook replies" {
        InModuleScope $outlookModule.Name {
            Mock Initialize-QOTicketsCoreApi {}
            Mock Write-QOTOutlookSyncLog {}
            Mock Get-QOTOutlookNamespace {
                $accounts = New-Object psobject
                $accounts | Add-Member -NotePropertyName Count -NotePropertyValue 0
                $accounts | Add-Member -MemberType ScriptMethod -Name Item -Value { param([int]$Index) return $null }

                return [pscustomobject]@{
                    Name = "MAPI"
                    Accounts = $accounts
                }
            }
            function Get-QOTMonitoredMailboxAddresses { return @("shared@example.test") }

            $fakeReply = New-Object psobject
            $fakeReply | Add-Member -NotePropertyName Subject -NotePropertyValue ""
            $fakeReply | Add-Member -NotePropertyName HTMLBody -NotePropertyValue "<div>thread</div>"
            $fakeReply | Add-Member -NotePropertyName Body -NotePropertyValue ""
            $fakeReply | Add-Member -NotePropertyName SentOnBehalfOfName -NotePropertyValue ""
            $fakeReply | Add-Member -MemberType ScriptMethod -Name GetInspector -Value { return $null }
            $fakeReply | Add-Member -MemberType ScriptMethod -Name Send -Value { return $null }

            $fakeMailItem = New-Object psobject
            $fakeMailItem | Add-Member -MemberType ScriptMethod -Name Reply -Value { return $fakeReply }

            Mock Find-QOTOutlookMessageByInternetId { return $fakeMailItem }

            $ticket = [pscustomobject]@{
                Id = "ticket-2"
                EmailMessageId = "message-2@example.test"
                SourceMailbox = "shared@example.test"
            }

            $result = Send-QOTicketOutlookReply -Ticket $ticket -Subject "Configured sender" -Body "hello"

            $result.Success | Should Be $true
            $fakeReply.SentOnBehalfOfName | Should Be "shared@example.test"
        }
    }

    It "uses the matching Outlook account without setting on-behalf sender" {
        InModuleScope $outlookModule.Name {
            Mock Write-QOTOutlookSyncLog {}
            function Get-QOTMonitoredMailboxAddresses { return @("primary@example.test") }
            function Get-QOTOutlookAccountForMailbox {
                return [pscustomobject]@{ SmtpAddress = "primary@example.test" }
            }

            $fakeMail = New-Object psobject
            $fakeMail | Add-Member -NotePropertyName SendUsingAccount -NotePropertyValue $null
            $fakeMail | Add-Member -NotePropertyName SentOnBehalfOfName -NotePropertyValue ""

            $result = Set-QOTOutlookMailSender -MailItem $fakeMail -MAPI ([pscustomobject]@{}) -MailboxAddress "primary@example.test"

            $result | Should Be "primary@example.test"
            $fakeMail.SendUsingAccount.SmtpAddress | Should Be "primary@example.test"
            $fakeMail.SentOnBehalfOfName | Should Be ""
        }
    }

    It "uses the only Outlook account when monitored mailbox settings are empty" {
        InModuleScope $outlookModule.Name {
            Mock Write-QOTOutlookSyncLog {}
            function Get-QOTMonitoredMailboxAddresses { return @() }

            $account = [pscustomobject]@{ SmtpAddress = "amillar@sumo.com.au"; DisplayName = "Aaron Millar"; UserName = "amillar@sumo.com.au" }
            $accounts = New-Object psobject
            $accounts | Add-Member -NotePropertyName Count -NotePropertyValue 1
            $accounts | Add-Member -MemberType ScriptMethod -Name Item -Value { param([int]$Index) return $script:QOTSingleMailboxAccount }
            $script:QOTSingleMailboxAccount = $account

            $fakeMail = New-Object psobject
            $fakeMail | Add-Member -NotePropertyName SendUsingAccount -NotePropertyValue $null
            $fakeMail | Add-Member -NotePropertyName SentOnBehalfOfName -NotePropertyValue ""

            $result = Set-QOTOutlookMailSender -MailItem $fakeMail -MAPI ([pscustomobject]@{ Accounts = $accounts }) -MailboxAddress "amillar@sumo.com.au"

            $result | Should Be "amillar@sumo.com.au"
            $fakeMail.SendUsingAccount.SmtpAddress | Should Be "amillar@sumo.com.au"
            $fakeMail.SentOnBehalfOfName | Should Be ""
        }
    }

    It "auto-detects the only Outlook mailbox for sync when settings are empty" {
        InModuleScope $outlookModule.Name {
            Mock Initialize-QOTicketsCoreApi {}
            Mock Write-QOTOutlookSyncLog {}
            function Get-QOTMonitoredMailboxAddresses { return @() }
            function Get-QOTickets { return [pscustomobject]@{ Tickets = @() } }
            function Save-QOTickets { param($Database) return $true }
            function Get-QOTLastEmailSyncUtc { return [datetime]"1970-01-01T00:00:00Z" }
            function Get-QOTEffectiveEmailCutoffUtc { param([datetime]$LastSyncUtc) return [datetime]"1970-01-01T00:00:00Z" }
            function Set-QOTLastSuccessfulEmailSyncUtc { param([datetime]$UtcTime) }
            function Set-QOTLastEmailSyncUtc { param([datetime]$UtcTime) }

            $account = [pscustomobject]@{ SmtpAddress = "amillar@sumo.com.au"; DisplayName = "Aaron Millar"; UserName = "amillar@sumo.com.au" }
            $accounts = New-Object psobject
            $accounts | Add-Member -NotePropertyName Count -NotePropertyValue 1
            $accounts | Add-Member -MemberType ScriptMethod -Name Item -Value { param([int]$Index) return $script:QOTSyncSingleMailboxAccount }
            $script:QOTSyncSingleMailboxAccount = $account

            $items = New-Object psobject
            $items | Add-Member -MemberType ScriptMethod -Name Sort -Value { param($Field, $Descending) return $null }
            $items | Add-Member -MemberType ScriptMethod -Name Item -Value { param([int]$Index) return $null }
            $inbox = [pscustomobject]@{ Items = $items }

            Mock Get-QOTOutlookNamespace { return [pscustomobject]@{ Name = "MAPI"; Accounts = $accounts } }
            Mock Get-QOTMailboxInboxFolder { return $inbox }

            $result = Sync-QOTicketsFromOutlook -AllowStartOutlook

            $result.Success | Should Be $true
            $result.Note | Should Match "MailboxesOk=1"
            $result.Note | Should Match "MailboxesFailed=0"
        }
    }

    It "falls back to creating an Outlook COM instance when active-object attach never appears" {
        InModuleScope $outlookModule.Name {
            Mock Write-QOTOutlookSyncLog {}
            Mock Start-Sleep {}
            Mock Start-Process {
                $process = New-Object psobject
                $process | Add-Member -MemberType ScriptMethod -Name WaitForInputIdle -Value { param([int]$Milliseconds) return $true }
                return $process
            }
            function Test-QOTCurrentProcessElevated { return $false }
            function New-QOTOutlookComApplication {
                $app = New-Object psobject
                $app | Add-Member -MemberType ScriptMethod -Name GetNamespace -Value { param([string]$Name) return [pscustomobject]@{ Name = $Name } }
                return $app
            }

            $result = Get-QOTOutlookNamespace -AllowStartOutlook

            $result.Name | Should Be "MAPI"
        }
    }

    It "recovers the only historical mailbox when monitored settings are empty" {
        InModuleScope $outlookModule.Name {
            Mock Write-QOTOutlookSyncLog {}
            function Get-QOTMonitoredMailboxAddresses { return @() }
            function Get-QOTickets {
                return [pscustomobject]@{
                    Tickets = @(
                        [pscustomobject]@{ SourceMailbox = "amillar@sumo.com.au" },
                        [pscustomobject]@{ SourceMailbox = "AMillar@sumo.com.au" }
                    )
                }
            }

            $result = @(Get-QOTEffectiveMonitoredMailboxAddresses -PersistWhenSingle)

            $result.Count | Should Be 1
            $result[0] | Should Be "amillar@sumo.com.au"
        }
    }
}
