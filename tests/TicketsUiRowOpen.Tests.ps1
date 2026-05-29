$repoRoot = Split-Path -Parent $PSScriptRoot
$ticketsUiModule = Import-Module (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Force -PassThru -ErrorAction Stop

Describe "Tickets UI row opening guards" {
    It "binds the row-open event helpers explicitly for WPF callbacks" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw

        $moduleSource | Should Match 'Get-Command Test-QOTicketsRenderableListItem -CommandType Function'
        $moduleSource | Should Match 'Get-Command Write-QOTicketsUILog -CommandType Function'
        $moduleSource | Should Match '& \$testRenderableTicketCmd -Ticket \$Ticket'
    }

    It "returns module-bound local helper scriptblocks for callback-safe execution" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw

        $moduleSource | Should Match 'function Resolve-QOTicketsLocalFunction'
        $moduleSource | Should Match '\$ExecutionContext\.SessionState\.Module\.NewBoundScriptBlock\(\$functionItem\.ScriptBlock\)'
    }

    It "binds reply-send helpers explicitly for WPF callbacks" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw

        $moduleSource | Should Match 'Get-Command Test-QOTProcessElevated -CommandType Function'
        $moduleSource | Should Match 'Get-Command Show-QOTicketsOpenPulse -CommandType Function'
        $moduleSource | Should Match 'Get-Command ConvertTo-QOTProcessArgumentString -CommandType Function'
        $moduleSource | Should Match 'Get-Command Read-QOTicketsReplyRunnerResult -CommandType Function'
        $moduleSource | Should Match 'Get-Command Test-QOTicketsReplyOperationCompleted -CommandType Function'
        $moduleSource | Should Match '& \$replySendElevatedCheckCmd'
        $moduleSource | Should Match '& \$replySendWriteLogCmd'
        $moduleSource | Should Match '& \$replySendProcessArgsCmd -Arguments \$argList'
        $moduleSource | Should Match '& \$replySendReadRunnerResultCmd -ResultPath \$script:TicketsReplyRunnerResultPath'
        $moduleSource | Should Match '& \$replySendTestReplyCompletedCmd'
    }

    It "defines shared dark ticket context menu styles and applies them to runtime menus" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw
        $xamlSource = Get-Content (Join-Path $repoRoot "src\UI\MainWindow.xaml") -Raw

        $xamlSource | Should Match 'x:Key="QOTContextMenuStyle"'
        $xamlSource | Should Match 'x:Key="QOTMenuItemStyle"'
        $xamlSource | Should Match 'x:Key="QOTSeparatorStyle"'
        $xamlSource | Should Match 'QOTMenuBackgroundBrush'
        $xamlSource | Should Match 'QOTMenuBorderBrush'
        $xamlSource | Should Match 'DropShadowEffect'
        $xamlSource | Should Match 'CornerRadius="10"'
        $xamlSource | Should Match 'CheckGlyph'
        $moduleSource | Should Match 'function Apply-QOTTicketsContextMenuTheme'
        $moduleSource | Should Match 'function Apply-QOTTicketsMenuItemTheme'
        $moduleSource | Should Match 'function New-QOTTicketsStyledSeparator'
        $moduleSource | Should Match 'Resolve-QOTicketsLocalFunction -Name "Apply-QOTTicketsMenuItemTheme"'
        $moduleSource | Should Match 'Resolve-QOTicketsLocalFunction -Name "Apply-QOTTicketsContextMenuTheme"'
        $moduleSource | Should Match 'Resolve-QOTicketsLocalFunction -Name "New-QOTTicketsStyledSeparator"'
        $moduleSource | Should Match '& \$applyTicketsContextMenuThemeCmd -ContextMenu \$script:TicketsFilterMenu -Window \$Window'
        $moduleSource | Should Match '& \$applyTicketsContextMenuThemeCmd -ContextMenu \$script:TicketsRowContextMenu -Window \$Window'
        $moduleSource | Should Match '& \$applyTicketsContextMenuThemeCmd -ContextMenu \$menu -Window \$Window'
        $moduleSource | Should Match '& \$newTicketsStyledSeparatorCmd -Window \$Window'
    }

    It "surfaces a visible tickets startup error panel instead of leaving the tab blank" {
        $mainWindowModuleSource = Get-Content (Join-Path $repoRoot "src\UI\MainWindow.UI.psm1") -Raw
        $xamlSource = Get-Content (Join-Path $repoRoot "src\UI\MainWindow.xaml") -Raw

        $xamlSource | Should Match 'x:Name="TicketsStartupErrorPanel"'
        $xamlSource | Should Match 'x:Name="TicketsStartupErrorText"'
        $mainWindowModuleSource | Should Match 'function Show-QOTTicketsStartupFailurePanel'
        $mainWindowModuleSource | Should Match 'Tickets failed to initialise'
        $mainWindowModuleSource | Should Match 'Show-QOTTicketsStartupFailurePanel -Window \$window -Message \$ticketFailureMessage'
    }

    It "uses the Outlook bridge instead of blocking admin reply sends" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw

        $moduleSource | Should Match 'Reply send requested while toolkit is elevated; using Outlook bridge runner\.'
        $moduleSource | Should Match 'Sending via Outlook bridge\.\.\.'
        $moduleSource | Should Match 'Start-QOTLimitedScheduledProcess'
        $moduleSource | Should Match 'Get-Command Start-QOTLimitedScheduledProcess -CommandType Function'
        $moduleSource | Should Match 'Ensure-QOTTicketsWorker'
        $moduleSource | Should Match '& \$replySendStartLimitedProcessCmd -FilePath \$replyWorkerExePath'
        $moduleSource | Should Match 'Elevated reply worker launched as limited scheduled task\.'
        $moduleSource | Should Match '\$script:TicketsReplyMode = "result-file"'
        $moduleSource | Should Not Match 'qot_reply_launch_'
        $moduleSource | Should Not Match 'ShellExecute\(\$exePath, \$argumentString'
        $moduleSource | Should Not Match 'Outlook replies cannot be sent while Quinn Optimiser Toolkit is running as Administrator'
    }

    It "wires optimistic reply feedback and resend affordances" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw
        $xamlSource = Get-Content (Join-Path $repoRoot "src\UI\MainWindow.xaml") -Raw

        $moduleSource | Should Match '\$script:TicketsOptimisticRepliesByTicketId = @\{\}'
        $moduleSource | Should Match 'Reply is sending in the background'
        $moduleSource | Should Match 'Reply queued and will send in the background'
        $moduleSource | Should Match 'ReplyQueued'
        $moduleSource | Should Match 'ReplySending'
        $moduleSource | Should Match 'Sending now in the background'
        $moduleSource | Should Match 'Queued to send after earlier replies finish'
        $moduleSource | Should Match '\{0\} sending, \{1\} queued in the background'
        $moduleSource | Should Match 'Reply failed\. You can resend it\.'
        $moduleSource | Should Match 'BtnRetryFailedTicketReply'
        $moduleSource | Should Match 'Get-QOTicketsLatestFailedOptimisticReply'
        $moduleSource | Should Match 'Remove-QOTicketsResolvedOptimisticReplies'
        $moduleSource | Should Match 'Get-QOTPendingReplyQueueSnapshot'
        $moduleSource | Should Match 'Queue-QOTTicketPendingReply'
        $moduleSource | Should Match 'Retry-QOTTicketPendingReply'
        $moduleSource | Should Match 'Cancel-QOTTicketPendingReply'
        $moduleSource | Should Match 'Delete/cancel queued reply'
        $moduleSource | Should Match 'PendingReplyTicketId'
        $moduleSource | Should Match 'PendingReplyDraftId'
        $moduleSource | Should Match 'Attempts: '
        $moduleSource | Should Match 'Last error: '
        $moduleSource | Should Match 'background queue service'
        $moduleSource | Should Match 'Queue position \{0\} of \{1\}'
        $moduleSource | Should Match 'Merge-QOTTicketVisiblePendingReplyEntries -OptimisticReplies \$optimisticReplies -QueuedReplies \$queuedReplySnapshots'
        $moduleSource | Should Match 'Resolve-QOTicketsLocalFunction -Name "Get-QOTicketsQueuedReplyEntries"'
        $moduleSource | Should Match 'Resolve-QOTicketsLocalFunction -Name "Merge-QOTTicketVisiblePendingReplyEntries"'
        $moduleSource | Should Match 'Tickets: Retry clicked\. TicketId='
        $moduleSource | Should Match 'Tickets: Delete clicked\. TicketId='
        $moduleSource | Should Match 'Tickets: Queue UI refreshed\. Reason='
        $moduleSource | Should Match 'Refresh-QOTicketsAfterLocalMutation -Grid \$grid -PreferredDetailsTicket \$ticket'
        $moduleSource | Should Match 'Refresh-QOTicketsAfterLocalMutation -Grid \$grid -PreferredDetailsTicket \$ticketForRefresh'
        $moduleSource | Should Not Match 'if \(\$pendingReplies\.Count -gt 0\)[\s\S]{0,500}\$btnSendReply\.IsEnabled = \$false'
        $moduleSource | Should Match 'Sending reply\.\.\.'
        $moduleSource | Should Match 'Reply queued\.\.\.'
        $moduleSource | Should Match 'if \(\$btnSendReply -and \[string\]::Equals\(\[string\]\$script:TicketsComposeMode, "Reply"'
        $moduleSource | Should Match '\$script:TicketsReplyRetryDraftId = ""'
        $moduleSource | Should Match 'ToolTip = \$\(if \(\$isSendingReply\)'
        $moduleSource | Should Match 'ToolTip = "Delete/cancel queued reply"'
        $moduleSource | Should Match '\$retryButton\.Content = \[string\]\(\[char\]0xE72C\)'
        $moduleSource | Should Match '\$cancelButton\.Content = \[string\]\(\[char\]0xE74D\)'
        $moduleSource | Should Match '\$script:TicketsRetryReplyHandler\.Invoke\(\$sender, \$args\)'
        $moduleSource | Should Match '\$script:TicketsCancelReplyHandler\.Invoke\(\$sender, \$args\)'
        $moduleSource | Should Match '\$requestedRetryDraftId = ""'
        $moduleSource | Should Not Match '\$btnRetryFailedReply\.Visibility = "Visible"'
        $xamlSource | Should Match 'x:Name="TicketReplyStatusText"'
        $xamlSource | Should Match 'x:Name="BtnRetryFailedTicketReply"'
    }

    It "prefers lightweight ticket refresh while reply queue activity is underway" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw

        $moduleSource | Should Match '\$script:TicketsReplyUiRefreshUntilUtc = \[datetime\]::MinValue'
        $moduleSource | Should Match '\$script:TicketsQueuedReplyEntriesCacheByTicketId = @\{\}'
        $moduleSource | Should Match '\$queueLightweightDetailsRefresh = \{'
        $moduleSource | Should Match 'function Set-QOTicketsReplyUiRefreshWindow'
        $moduleSource | Should Match 'Get-QOTicketsQueuedReplyEntries -TicketId \$resolvedTicketId -Ticket \$Ticket -PreferCached:\$PreferCached'
        $moduleSource | Should Match 'Update-QOTicketDetailsView -Ticket \$refreshTicket -DetailsPanel \$detailsPanel -BodyText \$ticketBodyText -ReplySubject \$ticketReplySubject -ReplyText \$ticketReplyText -ReplyButton \$btnSendReply -Chevron \$detailsChevron -PreferCurrentTicket -PreferCachedPendingReplies'
        $moduleSource | Should Match '\$preferLightweightRefresh = \$false'
        $moduleSource | Should Match 'Get-QOTPendingReplyQueueSnapshot'
        $moduleSource | Should Match 'Refresh-QOTicketsAfterLocalMutation -Grid \$Grid -PreferredDetailsTicket \$preferredDetailsTicket'
        $moduleSource | Should Match '\$queueWorkerKickTimer = \[System\.Windows\.Threading\.DispatcherTimer\]::new\(\)'
        $moduleSource | Should Match '\$queueWorkerKickTimer\.Interval = \[TimeSpan\]::FromMilliseconds\(150\)'
        $moduleSource | Should Match 'Set-QOTicketsReplyUiRefreshWindow -Seconds 90'
    }

    It "launches reply and sync PowerShell helpers with hidden window arguments" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw

        $moduleSource | Should Match -- '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -EncodedCommand'
        $moduleSource | Should Match 'Start-Process -FilePath \$exePath -ArgumentList \$argList -WorkingDirectory \$workingDirectory -WindowStyle Hidden'
        $moduleSource | Should Match 'Start-Process -FilePath \$exePath -ArgumentList \$argumentString -PassThru -WindowStyle Hidden -RedirectStandardOutput \$stdoutPath -RedirectStandardError \$stderrPath -ErrorAction Stop'
        $moduleSource | Should Match '\"-NoProfile\"'
        $moduleSource | Should Match '\"-ExecutionPolicy\", \"Bypass\"'
        $moduleSource | Should Match '\"-WindowStyle\", \"Hidden\"'
    }

    It "tracks optimistic replies and surfaces them in the thread model" {
        InModuleScope $ticketsUiModule.Name {
            $script:TicketsOptimisticRepliesByTicketId = @{}

            $ticket = [pscustomobject]@{
                Id               = "ticket-optimistic-1"
                Subject          = "RE: Quinn test"
                EmailFrom        = "aaron@example.com"
                Body             = "Original message"
                IncomingMessages = @()
                Notes            = @()
                Replies          = @()
            }

            $entry = Add-QOTicketsOptimisticReply -TicketId $ticket.Id -Subject "RE: Quinn test" -Body "Pending body"
            $entry.SendState | Should Be "Pending"

            $pendingModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            (@($pendingModel.Events | Where-Object { $_.Kind -eq "ReplyPending" })).Count | Should Be 1
            $pendingEvent = @($pendingModel.Events | Where-Object { $_.Kind -eq "ReplyPending" })[0]
            $pendingEvent.TicketId | Should Be $ticket.Id
            $pendingEvent.DraftId | Should Be $entry.DraftId

            $null = Set-QOTicketsOptimisticReplyState -TicketId $ticket.Id -DraftId $entry.DraftId -SendState Sending -FailureNote ""
            $sendingModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            $sendingEvent = @($sendingModel.Events | Where-Object { $_.Kind -eq "ReplySending" })[0]
            $sendingEvent.Title | Should Match 'Reply sending'
            $sendingEvent.Body | Should Be 'Pending body'
            $sendingEvent.StatusNote | Should Match 'Sending now in the background'

            $null = Set-QOTicketsOptimisticReplyState -TicketId $ticket.Id -DraftId $entry.DraftId -SendState Queued -FailureNote ""
            $queuedModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            $queuedEvent = @($queuedModel.Events | Where-Object { $_.Kind -eq "ReplyQueued" })[0]
            $queuedEvent.Title | Should Match 'Reply queued'
            $queuedEvent.Body | Should Be 'Pending body'
            $queuedEvent.StatusNote | Should Match 'Queued to send after earlier replies finish'

            $null = Set-QOTicketsOptimisticReplyState -TicketId $ticket.Id -DraftId $entry.DraftId -SendState Pending -FailureNote ""

            $script:TicketsOptimisticRepliesByTicketId = @{}
            Mock Get-QOTPendingReplyQueueSnapshot {
                return [pscustomobject]@{
                    Entries = @(
                        [pscustomobject]@{
                            TicketId       = $ticket.Id
                            Subject        = "RE: Quinn test"
                            Body           = "Queued-only body"
                            DraftId        = "queued-only-1"
                            CreatedAt      = (Get-Date).ToUniversalTime().ToString("o")
                            LastAttemptAt  = (Get-Date).ToUniversalTime().ToString("o")
                            NextAttemptAt  = ""
                            SendState      = "Queued"
                            FailureNote    = ""
                            RetryCount     = 2
                            QueuePosition  = 1
                            QueueTotal     = 1
                        }
                    )
                }
            }
            $queueOnlyModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            $queueOnlyEvent = @($queueOnlyModel.Events | Where-Object { $_.Kind -eq "ReplyQueued" })[0]
            $queueOnlyEvent.Body | Should Match 'Queued-only body'
            $queueOnlyEvent.DraftId | Should Be "queued-only-1"
            $queueOnlyEvent.StatusNote | Should Match 'Queue position 1 of 1'

            $entry = Add-QOTicketsOptimisticReply -TicketId $ticket.Id -Subject "RE: Quinn test" -Body "Stale optimistic body" -DraftId "queued-only-1"
            $null = Set-QOTicketsOptimisticReplyState -TicketId $ticket.Id -DraftId $entry.DraftId -SendState Failed -FailureNote "Stale optimistic failure"
            $queuePreferredModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            $queuePreferredEvent = @($queuePreferredModel.Events | Where-Object { $_.DraftId -eq "queued-only-1" })[0]
            $queuePreferredEvent.Body | Should Match 'Queued-only body'
            $queuePreferredEvent.Body | Should Not Match 'Stale optimistic failure'
            Remove-QOTicketsOptimisticReply -TicketId $ticket.Id -DraftId "queued-only-1"
            $entry = Add-QOTicketsOptimisticReply -TicketId $ticket.Id -Subject "RE: Quinn test" -Body "Pending body"
            $null = Set-QOTicketsOptimisticReplyState -TicketId $ticket.Id -DraftId $entry.DraftId -SendState Pending -FailureNote ""

            $ticket.Replies = @(
                [pscustomobject]@{
                    Subject   = "RE: Quinn test"
                    Body      = "Pending body"
                    CreatedAt = (Get-Date).AddMinutes(-10).ToString("yyyy-MM-dd HH:mm:ss")
                }
            )
            $oldDuplicateModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            (@($oldDuplicateModel.Events | Where-Object { $_.Kind -eq "ReplyPending" })).Count | Should Be 1
            @(Get-QOTicketsOptimisticReplyEntries -TicketId $ticket.Id).Count | Should Be 1

            $ticket.Replies = @(
                [pscustomobject]@{
                    Subject   = "RE: Quinn test"
                    Body      = "Pending body"
                    CreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
            )
            $resolvedModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            (@($resolvedModel.Events | Where-Object { $_.Kind -eq "ReplyPending" })).Count | Should Be 0
            @(Get-QOTicketsOptimisticReplyEntries -TicketId $ticket.Id).Count | Should Be 0

            $entry = Add-QOTicketsOptimisticReply -TicketId $ticket.Id -Subject "RE: Quinn test" -Body "Retry body"
            $null = Set-QOTicketsOptimisticReplyState -TicketId $ticket.Id -DraftId $entry.DraftId -SendState Failed -FailureNote "Outlook unavailable"
            $failedEntry = Get-QOTicketsLatestFailedOptimisticReply -TicketId $ticket.Id
            $failedEntry.DraftId | Should Be $entry.DraftId

            $failedModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            $failedEvent = @($failedModel.Events | Where-Object { $_.Kind -eq "ReplyFailed" })[0]
            $failedEvent.Title | Should Match 'Reply failed'
            $failedEvent.Body | Should Be 'Retry body'
            $failedEvent.StatusNote | Should Match 'Outlook unavailable'
            $failedEvent.TicketId | Should Be $ticket.Id
            $failedEvent.DraftId | Should Be $entry.DraftId

            $ticket.Replies += @(
                [pscustomobject]@{
                    Subject   = "RE: Quinn test"
                    Body      = "Retry body"
                    CreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
            )
            $sentAfterFailureModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel
            (@($sentAfterFailureModel.Events | Where-Object { $_.Kind -eq "ReplyFailed" })).Count | Should Be 0
            @(Get-QOTicketsOptimisticReplyEntries -TicketId $ticket.Id).Count | Should Be 0

            Remove-QOTicketsOptimisticReply -TicketId $ticket.Id -DraftId $entry.DraftId
            @(Get-QOTicketsOptimisticReplyEntries -TicketId $ticket.Id).Count | Should Be 0
        }
    }

    It "uses cached pending replies for lightweight ticket refreshes without forcing a queue snapshot read" {
        InModuleScope $ticketsUiModule.Name {
            $script:TicketsQueuedReplyEntriesCacheByTicketId = @{}

            Mock Resolve-QOTicketsCoreCommand {
                throw "queue snapshot should not be resolved"
            } -ParameterFilter { $CommandName -eq "Get-QOTPendingReplyQueueSnapshot" }

            $ticket = [pscustomobject]@{
                Id            = "ticket-cached-pending-1"
                Subject       = "Cached pending reply"
                PendingReplies = @(
                    [pscustomobject]@{
                        TicketId      = "ticket-cached-pending-1"
                        DraftId       = "draft-cached-1"
                        Subject       = "RE: Cached pending reply"
                        Body          = "Cached body"
                        CreatedAt     = (Get-Date).ToUniversalTime().ToString("o")
                        LastAttemptAt = (Get-Date).ToUniversalTime().ToString("o")
                        NextAttemptAt = ""
                        SendState     = "Queued"
                        FailureNote   = ""
                        RetryCount    = 0
                    }
                )
            }

            $entries = @(Get-QOTicketsQueuedReplyEntries -Ticket $ticket -PreferCached)

            $entries.Count | Should Be 1
            $entries[0].DraftId | Should Be "draft-cached-1"
            Assert-MockCalled Resolve-QOTicketsCoreCommand -Times 0 -Exactly -ParameterFilter { $CommandName -eq "Get-QOTPendingReplyQueueSnapshot" }
        }
    }

    It "adds and removes optimistic internal notes locally so note taking stays instant" {
        InModuleScope $ticketsUiModule.Name {
            $script:AllTickets = @(
                [pscustomobject]@{
                    Id      = "ticket-local-note-1"
                    Subject = "Local note ticket"
                    Notes   = @()
                }
            )

            $entry = Add-QOTicketsLocalInternalNote -TicketId "ticket-local-note-1" -Note "Cached note body" -Author "Taylor" -ClientNoteId "note-local-1"

            $entry.ClientNoteId | Should Be "note-local-1"
            @($script:AllTickets[0].Notes).Count | Should Be 1
            $script:AllTickets[0].Notes[0].IsPendingPersist | Should Be $true

            $removed = Remove-QOTicketsLocalInternalNote -TicketId "ticket-local-note-1" -ClientNoteId "note-local-1"

            $removed | Should BeGreaterThan 0
            @($script:AllTickets[0].Notes).Count | Should Be 0
        }
    }

    It "rehydrates full ticket details from the store when the UI is holding a shell ticket" {
        InModuleScope $ticketsUiModule.Name {
            $script:TicketsOptimisticRepliesByTicketId = @{}
            $script:TicketsCoreCommandCache = @{}
            Mock Get-QOTPendingReplyQueueSnapshot { return [pscustomobject]@{ Entries = @() } }
            Mock Get-QOTickets {
                return [pscustomobject]@{
                    Tickets = @(
                        [pscustomobject]@{
                            Id               = "ticket-shell-details-1"
                            Subject          = "Shell subject"
                            EmailFrom        = "Alice Example <alice@example.test>"
                            AssignedTo       = "Jamie"
                            EmailBody        = "Stored body"
                            IncomingMessages = @(
                                [pscustomobject]@{
                                    Body      = "Customer follow-up"
                                    CreatedAt = "2026-05-10 10:00:00"
                                }
                            )
                            Notes            = @()
                            Replies          = @()
                        }
                    )
                }
            }

            $shellTicket = [pscustomobject]@{
                Id      = "ticket-shell-details-1"
                Subject = "Shell subject"
            }

            $detailsModel = Get-QOTicketDetailsBodyText -Ticket $shellTicket -AsModel
            $resolvedTicket = Resolve-QOTTicketDetailsSourceTicket -Ticket $shellTicket
            $contactModel = Get-QOTicketContactHeaderModel -Ticket $resolvedTicket

            $contactModel.PrimaryText | Should Be "alice@example.test"
            $contactModel.MetaText | Should Be "Assigned to Jamie"
            $detailsModel.DetailsText | Should Match "Stored body"
            $detailsModel.DetailsText | Should Match "Customer follow-up"
        }
    }

    It "rehydrates contact and body details from a shell ticket without relying on bare sibling function lookup" {
        InModuleScope $ticketsUiModule.Name {
            $script:TicketsOptimisticRepliesByTicketId = @{}
            $script:TicketsCoreCommandCache = @{}
            Mock Get-QOTPendingReplyQueueSnapshot { return [pscustomobject]@{ Entries = @() } }
            Mock Get-QOTickets {
                return [pscustomobject]@{
                    Tickets = @(
                        [pscustomobject]@{
                            Id                  = "ticket-shell-details-2"
                            Subject             = "Another shell subject"
                            EmailFrom           = "Bob Example <bob@example.test>"
                            SenderName          = "Bob Example"
                            SenderEmail         = "bob@example.test"
                            AssignedTo          = "Casey"
                            EmailBody           = "Stored shell body"
                            EmailMessageId      = "message-2"
                            IncomingMessages    = @()
                            Notes               = @()
                            Replies             = @()
                        }
                    )
                }
            }

            $shellTicket = [pscustomobject]@{
                Id      = "ticket-shell-details-2"
                Subject = "Another shell subject"
            }

            $contactModel = Get-QOTicketContactHeaderModel -Ticket $shellTicket
            $detailsModel = Get-QOTicketDetailsBodyText -Ticket $shellTicket -AsModel

            $contactModel.PrimaryText | Should Be "bob@example.test"
            $contactModel.MetaText | Should Be "Assigned to Casey"
            $detailsModel.DetailsText | Should Match "Stored shell body"
        }
    }

    It "loads the stored body file for a shell ticket on first open without needing a reply refresh" {
        InModuleScope $ticketsUiModule.Name {
            $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-ticket-body-" + [guid]::NewGuid().ToString("N"))
            $storeDir = Join-Path $tempRoot "store"
            $bodiesDir = Join-Path $storeDir "Bodies"
            $storePath = Join-Path $storeDir "Tickets.json"
            $bodyPath = Join-Path $bodiesDir "ticket-shell-details-3.txt"

            try {
                $script:TicketsOptimisticRepliesByTicketId = @{}
                $script:TicketsCoreCommandCache = @{}
                $null = New-Item -ItemType Directory -Path $bodiesDir -Force
                "Body loaded from disk" | Set-Content -LiteralPath $bodyPath -Encoding UTF8

                Mock Get-QOTPendingReplyQueueSnapshot { return [pscustomobject]@{ Entries = @() } }
                Mock Get-QOTickets {
                    return [pscustomobject]@{
                        Tickets = @(
                            [pscustomobject]@{
                                Id               = "ticket-shell-details-3"
                                Subject          = "Stored body from file"
                                EmailFrom        = "Casey Example <casey@example.test>"
                                EmailBodyPath    = $bodyPath
                                IncomingMessages = @()
                                Notes            = @()
                                Replies          = @()
                            }
                        )
                    }
                }

                $shellTicket = [pscustomobject]@{
                    Id      = "ticket-shell-details-3"
                    Subject = "Stored body from file"
                }

                $detailsModel = Get-QOTicketDetailsBodyText -Ticket $shellTicket -AsModel

                $detailsModel.DetailsText | Should Match "Body loaded from disk"
                $detailsModel.DetailsText | Should Not Match "No email body found for this ticket."
            } finally {
                if (Test-Path -LiteralPath $tempRoot) {
                    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    It "renders stored body and reply history into the detail panel for a shell ticket" {
        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null

            $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-ticket-render-" + [guid]::NewGuid().ToString("N"))
            $storeDir = Join-Path $tempRoot "store"
            $bodiesDir = Join-Path $storeDir "Bodies"
            $bodyPath = Join-Path $bodiesDir "ticket-shell-render-1.txt"

            try {
                $script:TicketsOptimisticRepliesByTicketId = @{}
                $script:TicketsCoreCommandCache = @{}
                $script:TicketsSummaryHeaderText = [System.Windows.Controls.TextBlock]::new()
                $script:TicketsHeaderTitleText = [System.Windows.Controls.TextBlock]::new()
                $null = New-Item -ItemType Directory -Path $bodiesDir -Force
                "Main body from disk" | Set-Content -LiteralPath $bodyPath -Encoding UTF8

                Mock Get-QOTPendingReplyQueueSnapshot { return [pscustomobject]@{ Entries = @() } }
                Mock Get-QOTickets {
                    return [pscustomobject]@{
                        Tickets = @(
                            [pscustomobject]@{
                                Id               = "ticket-shell-render-1"
                                Subject          = "Rendered shell body"
                                EmailFrom        = "Jamie Example <jamie@example.test>"
                                SenderName       = "Jamie Example"
                                SenderEmail      = "jamie@example.test"
                                AssignedTo       = "Pat"
                                EmailBodyPath    = $bodyPath
                                IncomingMessages = @(
                                    [pscustomobject]@{
                                        Subject   = "RE: Rendered shell body"
                                        Body      = "Customer follow-up"
                                        CreatedAt = "2026-05-11 09:30:00"
                                        From      = "Jamie Example <jamie@example.test>"
                                    }
                                )
                                Replies          = @(
                                    [pscustomobject]@{
                                        Subject   = "RE: Rendered shell body"
                                        Body      = "Reply history already saved"
                                        CreatedAt = "2026-05-11 09:35:00"
                                    }
                                )
                                Notes            = @()
                            }
                        )
                    }
                }

                $shellTicket = [pscustomobject]@{
                    Id      = "ticket-shell-render-1"
                    Subject = "Rendered shell body"
                }

                $bodyPanel = [System.Windows.Controls.StackPanel]::new()
                $replySubject = [System.Windows.Controls.TextBox]::new()
                $replyText = [System.Windows.Controls.TextBox]::new()
                $replyButton = [System.Windows.Controls.Button]::new()
                $detailPanel = [System.Windows.Controls.Border]::new()
                $chevron = [System.Windows.Controls.TextBlock]::new()

                Update-QOTicketDetailsView -Ticket $shellTicket -DetailsPanel $detailPanel -BodyText $bodyPanel -ReplySubject $replySubject -ReplyText $replyText -ReplyButton $replyButton -Chevron $chevron

                $flattenText = {
                    param([AllowNull()]$Element)
                    $parts = New-Object System.Collections.Generic.List[string]
                    if (-not $Element) { return "" }
                    if ($Element -is [System.Windows.Controls.TextBlock]) {
                        try {
                            $textValue = [string]($Element.Text + "")
                            if (-not [string]::IsNullOrWhiteSpace($textValue)) { $parts.Add($textValue) | Out-Null }
                        } catch { }
                    }
                    if ($Element -is [System.Windows.Controls.Panel]) {
                        foreach ($child in @($Element.Children)) {
                            $childText = & $flattenText $child
                            if (-not [string]::IsNullOrWhiteSpace($childText)) { $parts.Add($childText) | Out-Null }
                        }
                    } elseif ($Element -is [System.Windows.Controls.Border]) {
                        $childText = & $flattenText $Element.Child
                        if (-not [string]::IsNullOrWhiteSpace($childText)) { $parts.Add($childText) | Out-Null }
                    } elseif ($Element -is [System.Windows.Controls.ContentControl]) {
                        $childText = & $flattenText $Element.Content
                        if (-not [string]::IsNullOrWhiteSpace($childText)) { $parts.Add($childText) | Out-Null }
                    }
                    return ($parts -join "`n")
                }

                $renderedText = & $flattenText $bodyPanel

                @($bodyPanel.Children).Count | Should BeGreaterThan 0
                $renderedText | Should Match "Main body from disk"
                $renderedText | Should Match "Customer follow-up"
                $renderedText | Should Match "Reply history already saved"
                $renderedText | Should Not Match "No email body found for this ticket."
            } finally {
                if (Test-Path -LiteralPath $tempRoot) {
                    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    It "does not show the no-body placeholder when replies or notes already exist" {
        InModuleScope $ticketsUiModule.Name {
            $ticket = [pscustomobject]@{
                Id               = "ticket-thread-activity-1"
                Subject          = "Reply-only thread"
                EmailFrom        = "Taylor Example <taylor@example.test>"
                Body             = ""
                EmailBody        = ""
                IncomingMessages = @()
                Notes            = @(
                    [pscustomobject]@{
                        Body      = "Investigating this now"
                        CreatedAt = "2026-05-11 09:15:00"
                        Author    = "Quinn"
                    }
                )
                Replies          = @(
                    [pscustomobject]@{
                        Subject   = "RE: Reply-only thread"
                        Body      = "Reply history already saved"
                        CreatedAt = "2026-05-11 09:30:00"
                    }
                )
            }

            $detailsModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel

            $detailsModel.DetailsText | Should Match "Reply history already saved"
            $detailsModel.DetailsText | Should Match "Investigating this now"
            $detailsModel.DetailsText | Should Not Match "No email body found for this ticket."
            (@($detailsModel.Events | Where-Object { $_.Title -match 'No email body found' })).Count | Should Be 0
        }
    }

    It "rehydrates a richer stored ticket by normalized subject when the selected shell ticket is partial" {
        InModuleScope $ticketsUiModule.Name {
            $script:TicketsCoreCommandCache = @{}
            Mock Get-QOTickets {
                return [pscustomobject]@{
                    Tickets = @(
                        [pscustomobject]@{
                            Id               = "ticket-normalized-subject-1"
                            Subject          = "test 6"
                            Title            = "test 6"
                            SenderName       = "Aaron Millar"
                            SenderEmail      = "amillar@sumo.com.au"
                            EmailBodyPreview = "Stored preview body"
                            IncomingMessages = @(
                                [pscustomobject]@{
                                    Body      = "Stored customer history"
                                    CreatedAt = "2026-05-11 13:45:00"
                                }
                            )
                            Replies          = @()
                            Notes            = @()
                        }
                    )
                }
            }

            $shellTicket = [pscustomobject]@{
                Subject = "RE: test 6"
                Title   = "RE: test 6"
            }

            $resolvedTicket = Resolve-QOTTicketDetailsSourceTicket -Ticket $shellTicket
            $detailsModel = Get-QOTicketDetailsBodyText -Ticket $shellTicket -AsModel

            $resolvedTicket.Subject | Should Be "test 6"
            $resolvedTicket.SenderEmail | Should Be "amillar@sumo.com.au"
            $detailsModel.DetailsText | Should Match "Stored preview body"
            $detailsModel.DetailsText | Should Match "Stored customer history"
        }
    }

    It "treats preview and generic history fields as stored activity" {
        InModuleScope $ticketsUiModule.Name {
            $ticket = [pscustomobject]@{
                Id          = "ticket-generic-history-1"
                Subject     = "History-backed ticket"
                Preview     = ""
                EmailBody   = ""
                Body        = ""
                Messages    = @(
                    [pscustomobject]@{
                        Title     = "Message event"
                        Content   = "Conversation content"
                        CreatedAt = "2026-05-11 14:00:00"
                    }
                )
                History     = @(
                    [pscustomobject]@{
                        Title     = "History event"
                        Body      = "History body"
                        CreatedAt = "2026-05-11 14:05:00"
                    }
                )
                Conversation = @(
                    [pscustomobject]@{
                        Subject   = "Conversation event"
                        Message   = "Conversation body"
                        CreatedAt = "2026-05-11 14:10:00"
                    }
                )
            }

            (Test-QOTicketHasStoredActivity -Ticket $ticket) | Should Be $true
            $detailsModel = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel

            $detailsModel.DetailsText | Should Match "Conversation content"
            $detailsModel.DetailsText | Should Match "History body"
            $detailsModel.DetailsText | Should Match "Conversation body"
            $detailsModel.DetailsText | Should Not Match "No email body found for this ticket."
            @($detailsModel.Events).Count | Should BeGreaterThan 0
        }
    }

    It "prefers the richer stored ticket when only sent replies and internal notes exist on reload" {
        InModuleScope $ticketsUiModule.Name {
            $script:AllTickets = @(
                [pscustomobject]@{
                    Id = "ticket-alias-activity-1"
                    Subject = "Alias-backed timeline"
                    SentReplies = @(
                        [pscustomobject]@{
                            Subject = "RE: Alias-backed timeline"
                            Body = "Stored sent reply"
                            CreatedAt = "2026-05-12 09:00:00"
                        }
                    )
                    InternalNotes = @(
                        [pscustomobject]@{
                            Body = "Stored internal note"
                            CreatedAt = "2026-05-12 08:55:00"
                            Author = "Morgan"
                        }
                    )
                }
            )

            $shellTicket = [pscustomobject]@{
                Id = "ticket-alias-activity-1"
                Subject = "Alias-backed timeline"
            }

            $detailsModel = Get-QOTicketDetailsBodyText -Ticket $shellTicket -AsModel
            $resolvedTicket = Resolve-QOTTicketDetailsSourceTicket -Ticket $shellTicket

            @($resolvedTicket.Replies).Count | Should Be 1
            @($resolvedTicket.Notes).Count | Should Be 1
            @($resolvedTicket.SentReplies).Count | Should Be 0
            @($resolvedTicket.InternalNotes).Count | Should Be 0
            $detailsModel.DetailsText | Should Match "Stored sent reply"
            $detailsModel.DetailsText | Should Match "Stored internal note"
        }
    }

    It "logs ticket detail hydration diagnostics with field and count information" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw

        $moduleSource | Should Match 'Tickets: Detail hydration\. RenderPath='
        $moduleSource | Should Match 'FullReloadAttempted='
        $moduleSource | Should Match 'BodyFields='
        $moduleSource | Should Match 'ReplyCount='
        $moduleSource | Should Match 'PendingReplyCount='
        $moduleSource | Should Match 'HistoryCount='
    }

    It "rejects placeholder-like objects as ticket rows" {
        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null

            (Test-QOTicketsRenderableListItem -Ticket ([pscustomobject]@{})) | Should Be $false
            (Test-QOTicketsRenderableListItem -Ticket ([pscustomobject]@{ Id = ""; Subject = "" })) | Should Be $false
            (Test-QOTicketsRenderableListItem -Ticket ([pscustomobject]@{ Id = "ticket-1"; Subject = "" })) | Should Be $true
            (Test-QOTicketsRenderableListItem -Ticket ([pscustomobject]@{ Subject = "Hello" })) | Should Be $true
        }
    }

    It "does not resolve blank grid chrome or placeholder rows as tickets" {
        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null

            $grid = [System.Windows.Controls.DataGrid]::new()
            $blankElement = [System.Windows.Controls.Border]::new()
            $blankElement.DataContext = [pscustomobject]@{}
            $ticketElement = [System.Windows.Controls.Border]::new()
            $ticketElement.DataContext = [pscustomobject]@{ Id = "ticket-2"; Subject = "Real ticket" }
            $placeholderRow = [System.Windows.Controls.DataGridRow]::new()
            $placeholderRow.Item = [pscustomobject]@{}

            (Resolve-QOTicketFromGridHit -Grid $grid -Hit $blankElement) | Should Be $null
            (Resolve-QOTicketFromGridHit -Grid $grid -Hit $placeholderRow -RequireRowHit) | Should Be $null
            (Resolve-QOTicketFromGridHit -Grid $grid -Hit $ticketElement).Id | Should Be "ticket-2"
        }
    }

    It "keeps queued reply timeline order stable by original created time" {
        InModuleScope $ticketsUiModule.Name {
            $ticket = [pscustomobject]@{
                Id = "ticket-stable-order"
                Subject = "Stable queue ordering"
                CreatedAt = "2026-05-14T00:00:00.0000000Z"
                EmailBody = "Original email body"
                PendingReplies = @(
                    [pscustomobject]@{
                        TicketId = "ticket-stable-order"
                        DraftId = "draft-old"
                        Subject = "Older draft"
                        Body = "Older queued reply"
                        CreatedAt = "2026-05-14T01:00:00.0000000Z"
                        LastAttemptAt = "2026-05-14T03:00:00.0000000Z"
                        SendState = "Queued"
                        FailureNote = ""
                        RetryCount = 0
                    },
                    [pscustomobject]@{
                        TicketId = "ticket-stable-order"
                        DraftId = "draft-new"
                        Subject = "Newer draft"
                        Body = "Newer queued reply"
                        CreatedAt = "2026-05-14T02:00:00.0000000Z"
                        LastAttemptAt = "2026-05-14T02:05:00.0000000Z"
                        SendState = "Sending"
                        FailureNote = ""
                        RetryCount = 1
                    }
                )
            }

            $model = Get-QOTicketDetailsBodyText -Ticket $ticket -AsModel -PreferCurrentTicket -PreferCachedPendingReplies
            $replyEvents = @($model.Events | Where-Object { $_.Kind -match '^Reply' })

            $replyEvents.Count | Should Be 2
            $replyEvents[0].DraftId | Should Be "draft-old"
            $replyEvents[1].DraftId | Should Be "draft-new"
            $replyEvents[0].When.ToUniversalTime().ToString("o") | Should Be "2026-05-14T01:00:00.0000000Z"
        }
    }

    It "keeps a queued reply timeline identity stable when only status changes" {
        InModuleScope $ticketsUiModule.Name {
            $makeTicket = {
                param([string]$State, [string]$LastAttemptAt)
                [pscustomobject]@{
                    Id = "ticket-status-stable"
                    Subject = "Stable status"
                    CreatedAt = "2026-05-14T00:00:00.0000000Z"
                    EmailBody = "Original email body"
                    PendingReplies = @(
                        [pscustomobject]@{
                            TicketId = "ticket-status-stable"
                            DraftId = "draft-same"
                            Subject = "Same draft"
                            Body = "Same reply body"
                            CreatedAt = "2026-05-14T01:00:00.0000000Z"
                            LastAttemptAt = $LastAttemptAt
                            SendState = $State
                            FailureNote = ""
                            RetryCount = 0
                        }
                    )
                }
            }

            $queuedModel = Get-QOTicketDetailsBodyText -Ticket (& $makeTicket "Queued" "2026-05-14T01:05:00.0000000Z") -AsModel -PreferCurrentTicket -PreferCachedPendingReplies
            $sendingModel = Get-QOTicketDetailsBodyText -Ticket (& $makeTicket "Sending" "2026-05-14T02:30:00.0000000Z") -AsModel -PreferCurrentTicket -PreferCachedPendingReplies
            $queuedReply = @($queuedModel.Events | Where-Object { $_.DraftId -eq "draft-same" })[0]
            $sendingReply = @($sendingModel.Events | Where-Object { $_.DraftId -eq "draft-same" })[0]

            $queuedReply.ItemId | Should Be $sendingReply.ItemId
            $queuedReply.When.ToUniversalTime().ToString("o") | Should Be $sendingReply.When.ToUniversalTime().ToString("o")
            $queuedReply.Body | Should Be "Same reply body"
            $sendingReply.Body | Should Be "Same reply body"
            $queuedReply.StatusNote | Should Match "Queued"
            $sendingReply.StatusNote | Should Match "Sending"
        }
    }

    AfterAll {
        Remove-Module $ticketsUiModule.Name -Force -ErrorAction SilentlyContinue
        Remove-Module Tickets -Force -ErrorAction SilentlyContinue
    }
}
