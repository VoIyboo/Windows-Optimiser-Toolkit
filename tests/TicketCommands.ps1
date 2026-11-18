# Called by WindowSmoke.Tests.ps1 with its isolated toolkit, settings and mail.
param([Parameter(Mandatory)][string]$FixtureSource)
$ErrorActionPreference = 'Stop'
$uiPath = Join-Path $FixtureSource 'Tickets/Tickets.UI.psm1'
$uiCode = [IO.File]::ReadAllText($uiPath)
$uiCode = $uiCode.Replace('$dialog.WindowStartupLocation = "CenterOwner"', '$dialog.WindowStartupLocation = "Manual"; $dialog.Left = -32000; $dialog.Top = -32000; $dialog.ShowInTaskbar = $false; $dialog.ShowActivated = $false')
Add-Type -TypeDefinition 'public static class QuinnTicketPrompt { public static string Show(params object[] values) { return "Yes"; } }'
$uiCode = $uiCode.Replace('[System.Windows.MessageBox]::Show(', '[QuinnTicketPrompt]::Show(')
# Capture the actual worker payload after the UI serializes it. All external
# integrations are disabled by the parent fixture.
$workerLaunch = '$process = Start-Process -FilePath $exePath -ArgumentList $argumentString -WorkingDirectory $workingDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop'
if (!$uiCode.Contains($workerLaunch)) { throw 'Cannot locate the ticket background action launch' }
$uiCode = $uiCode.Replace($workerLaunch, '$process = Start-QuinnFixtureTicketAction $ActionName $payloadPath $resultPath')
[IO.File]::WriteAllText($uiPath, $uiCode, [Text.UTF8Encoding]::new($true))

$global:QuinnTicketActions = [Collections.Generic.List[object]]::new()
$global:QuinnTicketDiagnostics = [Collections.Generic.List[string]]::new()
Add-TestOverrides 'Tickets/Tickets.UI.psm1' @(
    'function Write-QOTicketsUILog($Message,$Level) { $global:QuinnTicketDiagnostics.Add([string]$Message) }'
)
function global:Start-QuinnFixtureTicketAction($Action, $PayloadPath, $ResultPath) {
    if ($Action -notin 'queue-reply','save-note') { throw "Unexpected ticket action $Action" }
    $payload = [IO.File]::ReadAllText($PayloadPath) | ConvertFrom-Json
    $global:QuinnTicketActions.Add([pscustomobject]@{ Action=$Action; Payload=$payload })
    $result = @{ Success=$true; TicketId=$payload.TicketId; DraftId=$payload.DraftId; NoteId=$payload.NoteId }
    if ($global:QuinnFailNextTicketAction) {
        $result.Success = $false
        $result.Note = 'Fixture failed to save'
        $global:QuinnFailNextTicketAction = $false
    }
    [IO.File]::WriteAllText($ResultPath, (ConvertTo-Json $result))
    [pscustomobject]@{ HasExited=$true; ExitCode=0 }
}

function global:Get-QuinnTestControls($root, [type]$type) {
    if ($root -is $type) { $root }
    foreach ($child in [Windows.LogicalTreeHelper]::GetChildren($root)) {
        if ($child -is [Windows.DependencyObject]) { Get-QuinnTestControls $child $type }
    }
}
function global:Invoke-QuinnTestClick($control) {
    $control.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
}

function Open-QuinnTestTicket($grid, $id) {
    $grid.SelectedItem = $grid.Items | Where-Object Id -eq $id
    $source = [Windows.PresentationSource]::FromVisual($grid)
    $enter = [Windows.Input.KeyEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,$source,0,[Windows.Input.Key]::Enter)
    $enter.RoutedEvent = [Windows.UIElement]::PreviewKeyDownEvent
    $grid.RaiseEvent($enter)
    $grid.UpdateLayout()
    return $enter.Handled
}

function Invoke-QuinnTestTicketScenario($window, $FixtureSource) {
    Invoke-QuinnTestClick ($window.FindName('BtnNavTickets'))
    $window.UpdateLayout()
    $grid = $window.FindName('TicketsGrid')
    $interaction = @{ Opened=$false; KeptDraft=$false; ButtonsFit=$false; Sending=$false; InvalidAddressKept=$false; Error=$null }
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(50)
    $timer.Add_Tick({
        $dialog = [Windows.Application]::Current.Windows | Where-Object Title -eq 'New ticket' | Select-Object -First 1
        if (!$dialog) { return }
        $timer.Stop()
        try {
            $interaction.Opened = $true
            $boxes = @(Get-QuinnTestControls $dialog ([Windows.Controls.TextBox]))
            $create = Get-QuinnTestControls $dialog ([Windows.Controls.Button]) | Where-Object Content -eq 'Create'
            if ($interaction.Sending) {
                $boxes[0].Text = 'Second customer'
                $toggle = Get-QuinnTestControls $dialog ([Windows.Controls.CheckBox])
                $toggle.IsChecked = $true
                Invoke-QuinnTestClick $toggle
                $dialog.Height = 440
                $boxes[3].Text = 'invalid@'
                $boxes[4].Text = 'A fixture message'
                Invoke-QuinnTestClick $create
                $interaction.InvalidAddressKept = $dialog.IsVisible -and $boxes[4].Text -eq 'A fixture message'
                if ($dialog.IsVisible) {
                    $boxes[3].Text = "o'brien@example.invalid"
                    Invoke-QuinnTestClick $create
                }
                return
            }
            $dialog.UpdateLayout()
            $buttonEnd = $create.TranslatePoint([Windows.Point]::new(0,$create.ActualHeight), $dialog)
            $interaction.ButtonsFit = $buttonEnd.Y -le $dialog.ActualHeight
            $boxes[2].Text = 'Keep this note'
            Invoke-QuinnTestClick $create
            $interaction.KeptDraft = $dialog.IsVisible -and $boxes[2].Text -eq 'Keep this note'
            if ($dialog.IsVisible) {
                $boxes[0].Text = 'Printer test'
                Invoke-QuinnTestClick $create
            }
        } catch { $interaction.Error = $_.Exception.Message }
        finally { if ($dialog.IsVisible) { $dialog.Close() } }
    }.GetNewClosure())
    $timer.Start()
    try { Invoke-QuinnTestClick ($window.FindName('BtnRailTicketNew')) } finally { $timer.Stop() }
    if ($interaction.Error) { throw $interaction.Error }
    Assert $interaction.Opened 'New ticket opens from the Tickets tab'
    Assert $interaction.KeptDraft 'Correcting a missing title preserves the new ticket and its note'
    Assert $interaction.ButtonsFit 'Create is inside the new ticket window'
    Assert ($grid.Items.Count -eq 1 -and $grid.SelectedItem.Title -eq 'Printer test') 'Creating a ticket adds and selects the saved row'
    $core = Get-Module Tickets -All | Where-Object Path -like "$FixtureSource*" | Select-Object -First 1
    $ticketId = $grid.SelectedItem.Id
    $db = & $core { Get-QOTickets -Quiet }
    Assert ($db.Tickets[0].Notes[0].Body -eq 'Keep this note') 'Initial note survives a round trip through the store'
    Invoke-QuinnTestClick ($window.FindName('BtnRailTicketDelete'))
    $db = & $core { Get-QOTickets -Quiet }
    Assert ($db.Tickets[0].Folder -eq 'Deleted') 'The delete button moves the selected ticket to Deleted'

    # Route the actual right click from a realised row of the deleted-ticket view.
    $ticketUi = Get-Module Tickets.UI -All | Where-Object Path -like "$FixtureSource*" | Select-Object -First 1
    $menu = & $ticketUi { $script:TicketsRowContextMenu }
    $menu.Opacity = 0
    $filterMenu = $window.FindName('BtnTicketsFilterMenu').ContextMenu
    $filterMenu.Opacity = 0
    Invoke-QuinnTestClick ($window.FindName('BtnRailTicketFilter'))
    $deletedFilter = $filterMenu.Items | Where-Object Header -eq 'Deleted'
    Assert ($filterMenu.IsOpen -and !$deletedFilter.IsChecked -and $grid.Items.Count -eq 0) 'Deleting removes the ticket from the default view'
    $deletedFilter.IsChecked = $true
    $filterMenu.IsOpen = $false
    Assert ($grid.Items.Count -eq 1 -and $grid.Items[0].Id -eq $ticketId) 'The Deleted filter reveals the original ticket'
    $grid.SelectedIndex = 0
    $grid.UpdateLayout()
    $row = $grid.ItemContainerGenerator.ContainerFromIndex(0)
    $rightClick = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Right)
    $rightClick.RoutedEvent = [Windows.Input.Mouse]::PreviewMouseUpEvent
    $row.RaiseEvent($rightClick)
    $restore = $menu.Items | Where-Object Header -eq 'Undelete'
    Assert ($menu.IsOpen -and $restore.IsEnabled) "Right-clicking a deleted row offers Undelete (open=$($menu.IsOpen), enabled=$($restore.IsEnabled), handled=$($rightClick.Handled))"
    $restore.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
    $menu.IsOpen = $false
    $db = & $core { Get-QOTickets -Quiet }
    Assert ($db.Tickets.Count -eq 1 -and $db.Tickets[0].Id -eq $ticketId -and $db.Tickets[0].Folder -ne 'Deleted') 'Undelete restores the same ticket'

    foreach ($change in @(@{Menu='Set status*'; Field='Status'; Value='Pending'}, @{Menu='Set priority*'; Field='Priority'; Value='High'})) {
        $grid.SelectedIndex = 0
        $grid.UpdateLayout()
        $row = $grid.ItemContainerGenerator.ContainerFromIndex(0)
        $click = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Right)
        $click.RoutedEvent = [Windows.Input.Mouse]::PreviewMouseUpEvent
        $row.RaiseEvent($click)
        $parentItem = $menu.Items | Where-Object Header -like $change.Menu
        $choice = $parentItem.Items | Where-Object Tag -eq $change.Value
        Assert ($menu.IsOpen -and $parentItem.IsEnabled -and $null -ne $choice) "An active row offers $($change.Value) in its $($change.Field) menu"
        $choice.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
        $menu.IsOpen = $false
        $db = & $core { Get-QOTickets -Quiet }
        Assert ($db.Tickets[0].($change.Field) -eq $change.Value) "The $($change.Field) menu saves $($change.Value) on the restored ticket"
    }

    $settings = Get-Module Settings -All | Where-Object Path -like "$FixtureSource*" | Select-Object -First 1
    & $settings { $null = Set-QOMonitoredMailboxAddresses -Addresses @('help@example.invalid') }
    $interaction.Sending = $true
    $timer.Start()
    try { Invoke-QuinnTestClick ($window.FindName('BtnNewTicket')) } finally { $timer.Stop() }
    if ($interaction.Error) { throw $interaction.Error }
    Assert $interaction.InvalidAddressKept 'An invalid address leaves the message open for correction'
    $db = & $core { Get-QOTickets -Quiet }
    $first = $db.Tickets | Where-Object Id -eq $ticketId
    $second = $db.Tickets | Where-Object Title -eq 'Second customer'
    $draft = @($second.PendingReplies)[0]
    $queue = & $core { Get-QOTPendingReplyQueueSnapshot }
    Assert ($queue.ActiveCount -eq 1 -and $queue.Entries[0].TicketId -eq $second.Id -and @($first.PendingReplies).Count -eq 0 -and $draft.To -ceq "o'brien@example.invalid" -and $draft.SenderMailbox -eq 'help@example.invalid' -and $draft.Body -eq 'A fixture message') 'The initial email queues once against its own ticket, exact recipient and sender mailbox'

    Assert ((Open-QuinnTestTicket $grid $second.Id) -and $window.FindName('TicketDetailsPanel').IsVisible) 'Enter opens the selected customer ticket'
    $send = $window.FindName('BtnSendTicketReply')
    $body = $window.FindName('TicketReplyText')
    Invoke-QuinnTestClick ($window.FindName('BtnComposeReplyCustomer'))
    $subject = $window.FindName('TicketReplySubject').Text
    $body.Text = 'A follow-up for the second customer'
    Assert ($send.IsEnabled -and $send.Content -eq 'Send reply' -and $subject -like '*Second customer*') 'The customer reply can be submitted using the ticket subject'
    Invoke-QuinnTestClick $send
    Wait-For { $global:QuinnTicketActions.Count -gt 0 }
    $reply = $global:QuinnTicketActions[0]
    Assert ($reply.Action -eq 'queue-reply' -and $reply.Payload.TicketId -eq $second.Id -and $reply.Payload.Subject -ceq $subject -and $reply.Payload.Body -eq 'A follow-up for the second customer' -and $reply.Payload.ExpectedRoute.To -ceq "o'brien@example.invalid" -and $reply.Payload.ExpectedRoute.SenderMailbox -ceq 'help@example.invalid') 'The compose action hands the selected ticket, subject, body, recipient and sender to the reply worker'
    Invoke-QuinnTestClick ($window.FindName('BtnComposeInternalNote'))
    $body.Text = 'Private troubleshooting note'
    & $ticketUi { $null = Invoke-QOTicketsGridRefresh -Grid $script:TicketsGrid -GetTicketsCmd (Get-Command Get-QOTickets) }
    Assert ($send.IsEnabled -and $send.Content -eq 'Save internal note' -and $body.Text -eq 'Private troubleshooting note') 'A ticket refresh preserves internal note mode and its draft'
    Invoke-QuinnTestClick $send
    Wait-For { $global:QuinnTicketActions.Count -gt 1 }
    $note = $global:QuinnTicketActions[1]
    Assert ($global:QuinnTicketActions.Count -eq 2 -and $note.Action -eq 'save-note' -and $note.Payload.TicketId -eq $second.Id -and $note.Payload.Note -eq 'Private troubleshooting note' -and $note.Payload.NoteId -and !$note.Payload.ExpectedRoute) 'An internal note goes only to the note worker for the selected ticket'
    $replySuccess = "Tickets: Background reply queue persistence completed. TicketId='$($second.Id)' DraftId='$($reply.Payload.DraftId)'."
    $noteSuccess = "Tickets: Background internal note persisted. TicketId='$($second.Id)' NoteId='$($note.Payload.NoteId)'*"
    Wait-For { $global:QuinnTicketDiagnostics -contains $replySuccess -and ($global:QuinnTicketDiagnostics -like $noteSuccess) }
    if (!($global:QuinnTicketDiagnostics -contains $replySuccess) -or !($global:QuinnTicketDiagnostics -like $noteSuccess)) {
        Write-Host ($global:QuinnTicketDiagnostics -match 'background|watcher|failed|handoff' | Select-Object -Last 20 | Out-String)
        & $ticketUi { $script:TicketsBackgroundActionTimers | Select-Object @{Name='TimerRunning';Expression={$_.Timer.IsEnabled}},ResultPath | Out-Host }
    }
    Assert (($global:QuinnTicketDiagnostics -contains $replySuccess) -and [bool]($global:QuinnTicketDiagnostics -like $noteSuccess)) 'The UI reads both result files and confirms the reply and note on the selected ticket'

    $noteButton = $window.FindName('BtnComposeInternalNote')
    $replyButton = $window.FindName('BtnComposeReplyCustomer')
    $backButton = $window.FindName('BtnRailTicketBack')
    $body.Text = 'Sensitive internal draft'
    Invoke-QuinnTestClick $replyButton
    $replyWasEmpty = !$body.Text
    $body.Text = 'Public draft'
    & $ticketUi { $null = Invoke-QOTicketsFilterSafely -Grid $script:TicketsGrid -ForceRefresh }
    $validAfterRefresh = $send.IsEnabled -and $body.Text -eq 'Public draft'
    Invoke-QuinnTestClick $noteButton
    $noteRestored = $body.Text -eq 'Sensitive internal draft'
    Invoke-QuinnTestClick $backButton
    $null = Open-QuinnTestTicket $grid $first.Id
    $otherWasEmpty = !$body.Text
    $body.Text = 'First customer only'
    Invoke-QuinnTestClick $backButton
    $null = Open-QuinnTestTicket $grid $second.Id
    $restoredAfterNavigation = $send.Content -eq 'Save internal note' -and $body.Text -eq 'Sensitive internal draft'
    Invoke-QuinnTestClick $replyButton
    $publicRestored = $body.Text -eq 'Public draft'
    Assert $replyWasEmpty 'Choosing customer reply cannot expose an unsent internal note'
    Assert $validAfterRefresh 'Refreshing a manual ticket preserves its valid reply and send button'
    Assert $noteRestored 'Switching between reply and internal note retains the separate drafts'
    Assert ($otherWasEmpty -and $restoredAfterNavigation -and $publicRestored) 'Opening another customer keeps both drafts with their original ticket'

    $current = & $core { param($id) (Get-QOTickets -Quiet).Tickets | Where-Object Id -eq $id } $second.Id
    $current.EmailTo = 'changed@example.invalid'
    $null = & $core { param($item) Update-QOTicket $item } $current
    & $ticketUi { $null = Invoke-QOTicketsFilterSafely -Grid $script:TicketsGrid -ForceRefresh }
    Assert ($grid.SelectedItem.EmailTo -eq 'changed@example.invalid') 'The queue reflects a contact correction made during composition'
    $beforeRouteCheck = $global:QuinnTicketActions.Count
    Invoke-QuinnTestClick $send
    Assert ($global:QuinnTicketActions.Count -eq $beforeRouteCheck -and $body.Text -eq 'Public draft') 'A contact change holds the original draft before any reply is queued'
    $body.Clear()
    $body.Text = 'Reviewed reply for the corrected address'
    Invoke-QuinnTestClick $send
    $latest = $global:QuinnTicketActions | Select-Object -Last 1
    Assert ($global:QuinnTicketActions.Count -eq $beforeRouteCheck+1 -and $latest.Payload.ExpectedRoute.To -ceq 'changed@example.invalid' -and $latest.Payload.Body -ceq 'Reviewed reply for the corrected address') 'A freshly composed reply uses the reviewed customer address'
    Invoke-QuinnTestClick $noteButton
    $body.Text = 'Private note awaiting storage'
    $global:QuinnFailNextTicketAction = $true
    Invoke-QuinnTestClick $send
    Invoke-QuinnTestClick $replyButton
    $body.Text = 'An unrelated customer reply'
    Wait-For { $global:QuinnTicketDiagnostics -like '*Background internal note save failed*Fixture failed to save*' }
    Assert ($body.Text -eq 'An unrelated customer reply') 'A delayed note failure cannot overwrite a customer reply'
    Invoke-QuinnTestClick $noteButton
    Assert ($body.Text -eq 'Private note awaiting storage') 'A failed note is restored to its private draft after switching modes'
}

Add-Type -AssemblyName PresentationFramework
$scenario = @{ Ran=$false; Error=$null }
$driveTicketScenario = ${function:Invoke-QuinnTestTicketScenario}
$onReady = [Windows.Threading.DispatcherTimer]::new()
$onReady.Interval = [timespan]::FromMilliseconds(100)
$onReady.Add_Tick({
    $window = [Windows.Application]::Current.MainWindow
    if (!$window -or !$window.IsVisible -or !$window.FindName('BtnNavTickets')) { return }
    $onReady.Stop()
    try { & $driveTicketScenario $window $FixtureSource; $scenario.Ran = $true }
    catch { $scenario.Error = $_ }
    finally { Request-QOTMainWindowClose -Window $window }
}.GetNewClosure())
$onReady.Start()
try { Start-QOTMainWindow } finally { $onReady.Stop() }
if ($scenario.Error) { throw $scenario.Error }
Assert $scenario.Ran 'Ticket commands completed through the normal application window'
