# src\Tickets\Tickets.UI.psm1
# UI wiring for Tickets tab (NO core logic in here)

$ErrorActionPreference = "Stop"

# Core Tickets module is required (-Stop). Logging and Settings are best-effort
# but their failures are now logged via QOTImportHelper instead of swallowed.
Import-Module (Join-Path $PSScriptRoot "..\Core\Tickets.psm1") -Global -Force -ErrorAction Stop
. (Join-Path $PSScriptRoot "..\Core\QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\Core\Logging\Logging.psm1") -ImporterContext 'Tickets.UI' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\Core\Settings.psm1")        -ImporterContext 'Tickets.UI' -Global -Force

# -------------------------
# State
# -------------------------
$script:TicketsGrid = $null
$script:TicketsDetailsPanel = $null
$script:TicketsDetailsChevron = $null
$script:TicketsHeaderTitleText = $null
$script:TicketsSummaryHeaderText = $null
$script:TicketsContactAvatar = $null
$script:TicketsContactAvatarText = $null
$script:TicketsContactPrimaryText = $null
$script:TicketsContactMetaText = $null
$script:TicketsContactStatusDot = $null
$script:TicketsBodyText = $null
$script:TicketsComposeInternalButton = $null
$script:TicketsComposeReplyButton = $null
$script:TicketsComposeSubjectRow = $null
$script:TicketsReplySubject = $null
$script:TicketsReplyText = $null
$script:TicketsReplyButton = $null
$script:TicketsReplyStatusText = $null
$script:TicketsRetryReplyButton = $null
$script:TicketsSelectionSyncTimer = $null
$script:TicketsSelectionSyncTickHandler = $null
$script:TicketsLastDetailsTicketKey = ""
$script:TicketsDetailsForceClosed = $false
$script:TicketsListViewStateBeforeDetails = $null
$script:TicketsEmailSyncInProgress = $false
$script:TicketsContentRenderedHandler = $null
$script:TicketsSyncStatusText = $null
$script:TicketsSyncWorkerStarted = $false
$script:TicketsSyncFailureCount = 0
$script:TicketsSyncNextAttemptUtc = [datetime]::MinValue
$script:TicketsLastSuccessfulSyncUtc = $null
$script:TicketsLastSyncAttemptUtc = $null
$script:TicketsSyncLastFailureNote = ""
$script:TicketsSyncRunCounter = 0
$script:TicketsSyncActiveRunId = 0
$script:TicketsSyncLastStartUtc = [datetime]::MinValue
$script:TicketsSyncActiveTimeoutSeconds = 0
$script:TicketsSyncTimer = $null
$script:TicketsSyncRunspace = $null
$script:TicketsSyncPowerShell = $null
$script:TicketsSyncAsyncResult = $null
$script:TicketsSyncCompletionTimer = $null
$script:TicketsSyncProcess = $null
$script:TicketsSyncRunnerStdOutPath = ""
$script:TicketsSyncRunnerStdErrPath = ""
$script:TicketsSyncRunnerResultPath = ""
$script:TicketsSyncRunnerTaskName = ""
$script:TicketsSyncRunnerCommandPath = ""
$script:TicketsSyncMode = ""
$script:TicketsReplySendInProgress = $false
$script:TicketsReplyTimeoutSeconds = 300
$script:TicketsReplyStartUtc = [datetime]::MinValue
$script:TicketsReplyRunspace = $null
$script:TicketsReplyPowerShell = $null
$script:TicketsReplyAsyncResult = $null
$script:TicketsReplyCompletionTimer = $null
$script:TicketsReplyCompletionTickHandler = $null
$script:TicketsReplyWatchdogTimer = $null
$script:TicketsReplyWatchdogTickHandler = $null
$script:TicketsReplyProcess = $null
$script:TicketsReplyRunnerPayloadPath = ""
$script:TicketsReplyRunnerStdOutPath = ""
$script:TicketsReplyRunnerStdErrPath = ""
$script:TicketsReplyRunnerResultPath = ""
$script:TicketsReplyRunnerTaskName = ""
$script:TicketsReplyRunnerCommandPath = ""
$script:TicketsReplyMode = ""
$script:TicketsReplyRetryDraftId = ""
$script:TicketsReplyQueuedSends = New-Object System.Collections.Queue
$script:TicketsReplyQueueDrainHandler = $null
$script:TicketsReplyQueueKickTimer = $null
$script:TicketsReplyQueueKickTickHandler = $null
$script:TicketsReplyUiRefreshUntilUtc = [datetime]::MinValue
$script:TicketsQueuedReplyEntriesCacheByTicketId = @{}
$script:TicketsBackgroundActionTimers = New-Object System.Collections.ArrayList
$script:TicketsSuppressedPendingReplyDraftIdsByTicketId = @{}
$script:TicketsIncrementalMergeTimer = $null
$script:TicketsIncrementalMergeTickHandler = $null
$script:TicketsIncrementalMergeQueue = $null
$script:TicketsIncrementalMergeExistingKeys = $null
$script:TicketsIncrementalMergeProcessed = 0
$script:TicketsIncrementalMergeAdded = 0
$script:TicketsIncrementalMergeNeedsRefresh = $false
$script:TicketsContactLookupCache = @{}
$script:TicketsCoreCommandCache = @{}
$script:TicketsWindow = $null
$script:TicketsGridItemsSourceLock = New-Object System.Object

# Centralized event handler registry to prevent handler stacking on module reload
# Each entry: @{ Target = <control>; Event = <name>; Handler = <delegate>; RoutedEvent = <RoutedEvent or $null> }
$script:TicketsRegisteredHandlers = New-Object System.Collections.Generic.List[object]

# Stored handlers to avoid double wiring
$script:TicketsLoadedHandler  = $null
$script:TicketsNewHandler     = $null
$script:TicketsDeleteHandler  = $null
$script:TicketsToggleDetailsHandler = $null
$script:TicketsToggleDetailsPreviewHandler = $null
$script:TicketsSelectionChangedHandler = $null
$script:TicketsRowDoubleClickHandler = $null
$script:TicketsRowPreviewDoubleClickHandler = $null
$script:TicketsRowPreviewMouseDownHandler = $null
$script:TicketsRowPreviewMouseUpHandler = $null
$script:TicketsRowMouseUpHandler = $null
$script:TicketsGridKeyDownHandler = $null
$script:TicketsOpenDetailsInProgress = $false
$script:TicketsLastLeftClickUtc = [datetime]::MinValue
$script:TicketsLastLeftClickTicketKey = ""
$script:TicketsLastPointerDownTicket = $null
$script:TicketsQueuedDetailsRefreshTimer = $null
$script:TicketsQueuedDetailsRefreshTickHandler = $null
$script:TicketsQueuedDetailsRefreshTicket = $null
$script:TicketsQueuedDetailsRefreshTicketId = ""
$script:TicketsQueuedDetailsRefreshGeneration = 0
$script:TicketsDetailsViewGeneration = 0
$script:TicketsDetailsViewClosing = $false
$script:TicketsCurrentAssigneeDisplayName = $null
$script:TicketsRowEditHandler = $null
$script:TicketsSendReplyHandler = $null
$script:TicketsRetryReplyHandler = $null
$script:TicketsCancelReplyHandler = $null
$script:TicketsDeleteNoteHandler = $null
$script:TicketsComposeModeInternalHandler = $null
$script:TicketsComposeModeReplyHandler = $null
$script:TicketsFilterButtonHandler = $null
$script:TicketsSyncStatusClickHandler = $null
$script:TicketsSyncWorkerTickHandler = $null
$script:TicketsOpenPulseTimer = $null
$script:TicketsUndeleteHandler = $null
$script:TicketsAddNoteHandler = $null
$script:TicketsCloseHandler = $null
$script:TicketsAssignMenuItemHandler = $null
$script:TicketsAssignCustomMenuItemHandler = $null
$script:TicketsClaimMenuItemHandler = $null
$script:TicketsClaimMenuItem = $null
$script:TicketsOpenMenuItem = $null
$script:TicketsOpenMenuItemHandler = $null
$script:TicketsOpenFromContextCmd = $null
$script:TicketsActiveTicketId = ""
$script:TicketsOptimisticRepliesByTicketId = @{}
$script:TicketsComposeModeByTicketId = @{}

$script:TicketsFileWatcher = $null
$script:TicketsFileWatcherEvents = @()
$script:TicketsFileRefreshTimer = $null
$script:TicketsFileRefreshTickHandler = $null
$script:TicketsStorePath = ""
$script:TicketsStoreLastWriteUtc = [datetime]::MinValue
$script:TicketsCurrentView = "Filtered"
$script:TicketsShowSyncStatus = $true
$script:TicketsLastSyncStatusMessage = ""
$script:TicketsBackgroundPollMinSeconds = 300
$script:TicketsBackgroundPollMaxSeconds = 300
$script:TicketsBackgroundBatchSize = 25
$script:TicketsStartupBatchSize = 25
$script:TicketsFilterState = $null
$script:TicketsFilterMenu = $null
$script:TicketsFilterOpenCheckbox = $null
$script:TicketsFilterClosedCheckbox = $null
$script:TicketsFilterDeletedCheckbox = $null
$script:TicketsFilterSortPriorityMenuItem = $null
$script:TicketsFilterSortNewestMenuItem = $null
$script:TicketsFilterSortOldestMenuItem = $null
$script:TicketsFilterAssigneeMenuItem = $null
$script:TicketsFilterAssigneeAllMenuItem = $null
$script:TicketsFilterAssigneeUnassignedMenuItem = $null
$script:TicketsFilterAssigneeDynamicMenuItems = @()
$script:TicketsFilterCheckboxHandler = $null
$script:TicketsFilterStatusCheckedHandler = $null
$script:TicketsFilterStatusUncheckedHandler = $null
$script:TicketsFilterStatusClickHandler = $null
$script:TicketsFilterMenuClosedHandler = $null
$script:TicketsWindowClosingHandler = $null
$script:AllTickets = $null
$script:TicketsFilteredItems = $null
$script:TicketsLoadedStoreWriteUtc = [datetime]::MinValue
$script:TicketsContextMenuSelection = @()
$script:TicketsFilterDefaults = [pscustomobject]@{
    ShowOpen             = $true
    ShowClosed           = $true
    ShowDeleted          = $false
    SortMode             = "Priority"
    AssigneeFilter       = "All"
}
$script:ShowOpen = $true
$script:ShowClosed = $true
$script:ShowDeleted = $false
$script:TicketsSortMode = "Priority"
$script:TicketsAssigneeFilter = "All"
$script:TicketsComposeMode = "Reply"

function Write-QOTicketsUILog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    try {
        switch ($Level) {
            'ERROR' { if (Get-Command Write-QOTLogError -ErrorAction SilentlyContinue) { Write-QOTLogError $Message; return } }
            'WARN'  { if (Get-Command Write-QOTLogWarn  -ErrorAction SilentlyContinue) { Write-QOTLogWarn  $Message; return } }
            default { if (Get-Command Write-QOTLogInfo  -ErrorAction SilentlyContinue) { Write-QOTLogInfo  $Message; return } }
        }
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $Message $Level
            return
        }
    } catch { }

    # absolute fallback, never crash the UI
    try {
        $fallbackDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null
        $fallbackPath = Join-Path $fallbackDir "TicketsUI.log"
        Add-Content -LiteralPath $fallbackPath -Value ("[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message) -Encoding UTF8
    } catch { }
}

Write-QOTicketsUILog "=== Tickets.UI.psm1 LOADED ==="

# -------------------------
# Centralized event handler registry
# -------------------------
# Tracks every event handler registered to UI controls so they can be cleanly
# removed when the module reloads or the window closes, preventing handler stacking.

function Register-QOTicketEventHandler {
    <#
    .SYNOPSIS
    Registers an event handler to a control and tracks it for later cleanup.
    .DESCRIPTION
    For simple .NET events (Click, SelectionChanged, etc), pass -Event with the event name.
    For WPF routed events (PreviewMouseLeftButtonDown, etc), pass -RoutedEvent with the
    [System.Windows.RoutedEvent] reference.
    The handler is registered AND tracked in $script:TicketsRegisteredHandlers.
    .EXAMPLE
    Register-QOTicketEventHandler -Target $btnNew -Event "Click" -Handler $newHandler
    .EXAMPLE
    Register-QOTicketEventHandler -Target $grid -RoutedEvent ([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent) -Handler $h
    #>
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)]$Handler,
        [string]$Event,
        [System.Windows.RoutedEvent]$RoutedEvent
    )

    if (-not $Target -or -not $Handler) { return }
    if (-not $script:TicketsRegisteredHandlers) {
        $script:TicketsRegisteredHandlers = New-Object System.Collections.Generic.List[object]
    }

    try {
        if ($RoutedEvent) {
            $Target.AddHandler($RoutedEvent, $Handler)
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Event)) {
            $addMethod = "Add_" + $Event
            $Target.$addMethod.Invoke($Handler)
        }
        else {
            Write-QOTicketsUILog "Tickets: Register-QOTicketEventHandler called without Event or RoutedEvent." "WARN"
            return
        }

        $entry = [pscustomobject]@{
            Target      = $Target
            Event       = $Event
            Handler     = $Handler
            RoutedEvent = $RoutedEvent
        }
        $script:TicketsRegisteredHandlers.Add($entry) | Out-Null
    }
    catch {
        Write-QOTicketsUILog ("Tickets: Failed to register event handler. " + $_.Exception.Message) "WARN"
    }
}

function Unregister-QOTicketEventHandlers {
    <#
    .SYNOPSIS
    Removes every event handler tracked in $script:TicketsRegisteredHandlers.
    .DESCRIPTION
    Call this at the start of UI initialization to clear stale handlers from any
    previous module load, and on window close to release all handlers.
    Safe to call multiple times; each handler removal is wrapped in try/catch.
    #>
    if (-not $script:TicketsRegisteredHandlers -or $script:TicketsRegisteredHandlers.Count -eq 0) {
        return
    }

    $removedCount = 0
    foreach ($entry in @($script:TicketsRegisteredHandlers)) {
        if (-not $entry -or -not $entry.Target -or -not $entry.Handler) { continue }

        try {
            if ($entry.RoutedEvent) {
                $entry.Target.RemoveHandler($entry.RoutedEvent, $entry.Handler)
            }
            elseif (-not [string]::IsNullOrWhiteSpace($entry.Event)) {
                $removeMethod = "Remove_" + $entry.Event
                $entry.Target.$removeMethod.Invoke($entry.Handler)
            }
            $removedCount++
        }
        catch {
            # Removal failed (control may already be disposed). Continue cleanup.
        }
    }

    try { $script:TicketsRegisteredHandlers.Clear() } catch { }
    Write-QOTicketsUILog ("Tickets: Unregister-QOTicketEventHandlers removed {0} handler(s)." -f $removedCount)
}

function Get-QOTicketIdValue {
    param(
        [AllowNull()]$Ticket
    )

    if (-not $Ticket) { return "" }
    foreach ($propName in @("Id", "TicketId", "SelectedTicketId")) {
        try {
            if ($Ticket.PSObject.Properties.Name -contains $propName) {
                $value = ([string]($Ticket.$propName + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return $value
                }
            }
        } catch { }
    }
    foreach ($nestedProp in @("Ticket", "SourceTicket", "SelectedTicket")) {
        try {
            if ($Ticket.PSObject.Properties.Name -contains $nestedProp) {
                $nestedTicket = $Ticket.$nestedProp
                if ($nestedTicket) {
                    $nestedId = [string](Get-QOTicketIdValue -Ticket $nestedTicket)
                    if (-not [string]::IsNullOrWhiteSpace($nestedId)) {
                        return $nestedId
                    }
                }
            }
        } catch { }
    }
    return ""
}

function Test-QOTicketDetailsViewActive {
    param(
        [AllowNull()][string]$TicketId,
        [AllowNull()][int]$Generation = -1,
        [switch]$AllowCollapsed
    )

    $expectedTicketId = ([string]($TicketId + "")).Trim()
    $activeTicketId = ""
    try { $activeTicketId = ([string]($script:TicketsActiveTicketId + "")).Trim() } catch { $activeTicketId = "" }

    if ($script:TicketsDetailsViewClosing) { return $false }
    if ([string]::IsNullOrWhiteSpace($activeTicketId)) { return $false }
    if (([int]$Generation -ge 0) -and ([int]$script:TicketsDetailsViewGeneration -ne [int]$Generation)) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($expectedTicketId) -and -not [string]::Equals($activeTicketId, $expectedTicketId, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }

    try {
        if ((-not $AllowCollapsed) -and $script:TicketsDetailsPanel -and -not [string]::Equals([string]$script:TicketsDetailsPanel.Visibility, "Visible", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    } catch { }

    return $true
}

function Stop-QOTicketQueuedDetailsRefresh {
    param([AllowNull()][string]$Reason)

    $reasonText = ([string]($Reason + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($reasonText)) { $reasonText = "unspecified" }
    try {
        if ($script:TicketsQueuedDetailsRefreshTimer -and $script:TicketsQueuedDetailsRefreshTimer.IsEnabled) {
            $script:TicketsQueuedDetailsRefreshTimer.Stop()
        }
    } catch { }
    try { $script:TicketsQueuedDetailsRefreshTicket = $null } catch { }
    try { $script:TicketsQueuedDetailsRefreshTicketId = "" } catch { }
    try { $script:TicketsQueuedDetailsRefreshGeneration = 0 } catch { }
    try { Write-QOTicketsUILog ("Tickets: Queued detail refresh stopped. Reason='{0}'." -f $reasonText) } catch { }
}

function Get-QOTicketPropertyTextValue {
    param(
        [AllowNull()]$Ticket,
        [string[]]$PropertyNames
    )

    if (-not $Ticket) { return "" }
    foreach ($propName in @($PropertyNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        try {
            if ($Ticket.PSObject.Properties.Name -contains $propName) {
                $value = ([string]($Ticket.$propName + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return $value
                }
            }
        } catch { }
    }
    foreach ($nestedProp in @("Ticket", "SourceTicket", "SelectedTicket")) {
        try {
            if ($Ticket.PSObject.Properties.Name -contains $nestedProp) {
                $nestedTicket = $Ticket.$nestedProp
                if ($nestedTicket) {
                    $nestedValue = [string](Get-QOTicketPropertyTextValue -Ticket $nestedTicket -PropertyNames $PropertyNames)
                    if (-not [string]::IsNullOrWhiteSpace($nestedValue)) {
                        return $nestedValue
                    }
                }
            }
        } catch { }
    }
    return ""
}

function Get-QOTTicketPreferredSubject {
    param(
        [AllowNull()]$Ticket
    )

    if (-not $Ticket) { return "" }

    return [string](Get-QOTicketPropertyTextValue -Ticket $Ticket -PropertyNames @("Subject", "Title", "TicketName"))
}

function Normalize-QOTTicketThreadKey {
    param(
        [AllowNull()][string]$Subject
    )

    $value = ([string]($Subject + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }

    $value = ($value -replace '[\r\n]+', ' ').Trim()
    for ($i = 0; $i -lt 6; $i++) {
        $next = ($value -replace '^(?i)\s*((RE|FW|FWD)\s*:\s*)+', '').Trim()
        if ($next -eq $value) { break }
        $value = $next
    }

    return (($value -replace '\s+', ' ').Trim().ToLowerInvariant())
}

function Find-QOTTicketMatchInCollection {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][object[]]$Items
    )

    if (-not $Ticket) { return $null }
    $sourceItems = @($Items | Where-Object { $_ })
    if ($sourceItems.Count -eq 0) { return $null }

    $ticketId = Get-QOTicketIdValue -Ticket $Ticket
    $emailMessageId = [string](Get-QOTicketPropertyTextValue -Ticket $Ticket -PropertyNames @("EmailMessageId", "InternetMessageId", "MessageId"))
    $sourceMessageId = [string](Get-QOTicketPropertyTextValue -Ticket $Ticket -PropertyNames @("SourceMessageId", "OutlookEntryId", "EntryId"))
    $bodyPath = [string](Get-QOTicketPropertyTextValue -Ticket $Ticket -PropertyNames @("EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath", "PreviewPath"))
    $threadKey = Normalize-QOTTicketThreadKey -Subject (Get-QOTTicketPreferredSubject -Ticket $Ticket)

    $matches = @(
        $sourceItems |
            Where-Object {
                if (-not $_) { return $false }
                $candidateId = Get-QOTicketIdValue -Ticket $_
                $candidateEmailMessageId = [string](Get-QOTicketPropertyTextValue -Ticket $_ -PropertyNames @("EmailMessageId", "InternetMessageId", "MessageId"))
                $candidateSourceMessageId = [string](Get-QOTicketPropertyTextValue -Ticket $_ -PropertyNames @("SourceMessageId", "OutlookEntryId", "EntryId"))
                $candidateBodyPath = [string](Get-QOTicketPropertyTextValue -Ticket $_ -PropertyNames @("EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath", "PreviewPath"))
                $candidateThreadKey = Normalize-QOTTicketThreadKey -Subject (Get-QOTTicketPreferredSubject -Ticket $_)

                if ((-not [string]::IsNullOrWhiteSpace($ticketId)) -and [string]::Equals($candidateId, $ticketId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
                if ((-not [string]::IsNullOrWhiteSpace($emailMessageId)) -and [string]::Equals($candidateEmailMessageId, $emailMessageId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
                if ((-not [string]::IsNullOrWhiteSpace($sourceMessageId)) -and [string]::Equals($candidateSourceMessageId, $sourceMessageId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
                if ((-not [string]::IsNullOrWhiteSpace($bodyPath)) -and [string]::Equals($candidateBodyPath, $bodyPath, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
                if ((-not [string]::IsNullOrWhiteSpace($threadKey)) -and [string]::Equals($candidateThreadKey, $threadKey, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
                return $false
            }
    )
    if ($matches.Count -eq 0) { return $null }

    return @(
        $matches |
            Sort-Object `
                @{ Expression = {
                    $score = 0
                    try { if (-not [string]::IsNullOrWhiteSpace([string](Get-QOTicketPropertyTextValue -Ticket $_ -PropertyNames @("EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath")))) { $score += 500 } } catch { }
                    try { if (-not [string]::IsNullOrWhiteSpace([string](Get-QOTicketPropertyTextValue -Ticket $_ -PropertyNames @("EmailBody", "Body", "HtmlBody", "TextBody", "EmailBodyPreview", "BodyPreview", "Preview")))) { $score += 200 } } catch { }
                    try { if (-not [string]::IsNullOrWhiteSpace([string](Get-QOTicketPropertyTextValue -Ticket $_ -PropertyNames @("EmailFrom", "SenderEmail", "SenderName")))) { $score += 50 } } catch { }
                    return $score
                }; Descending = $true }, `
                @{ Expression = {
                    try {
                        if ($_.PSObject.Properties.Name -contains "UpdatedAt") { return [datetime]$_.UpdatedAt }
                        if ($_.PSObject.Properties.Name -contains "CreatedAt") { return [datetime]$_.CreatedAt }
                    } catch { }
                    return [datetime]::MinValue
                }; Descending = $true } |
            Select-Object -First 1
    )[0]
}


function Get-QOTicketsOptimisticReplyEntries {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][string]$TicketId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) {
        $resolvedTicketId = Get-QOTicketIdValue -Ticket $Ticket
    }
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) { return @() }

    try {
        if ($script:TicketsOptimisticRepliesByTicketId -isnot [hashtable]) {
            $script:TicketsOptimisticRepliesByTicketId = @{}
        }
        if ($script:TicketsOptimisticRepliesByTicketId.ContainsKey($resolvedTicketId)) {
            return @($script:TicketsOptimisticRepliesByTicketId[$resolvedTicketId] | Where-Object { $_ })
        }
    } catch { }
    return @()
}

function Get-QOTicketsQueuedReplyEntries {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][string]$TicketId,
        [switch]$PreferCached
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) {
        $resolvedTicketId = Get-QOTicketIdValue -Ticket $Ticket
    }
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) { return @() }

    if ($PreferCached) {
        try {
            $cachedEntries = @()
            $hasCachedEntries = $false
            if ($Ticket -and ($Ticket.PSObject.Properties.Name -contains "PendingReplies")) {
                $cachedEntries = @($Ticket.PendingReplies | Where-Object { $_ })
                $hasCachedEntries = ($cachedEntries.Count -gt 0)
            }
            if ((-not $hasCachedEntries) -and $script:TicketsQueuedReplyEntriesCacheByTicketId -is [hashtable] -and $script:TicketsQueuedReplyEntriesCacheByTicketId.ContainsKey($resolvedTicketId)) {
                $cachedEntries = @($script:TicketsQueuedReplyEntriesCacheByTicketId[$resolvedTicketId] | Where-Object { $_ })
                $hasCachedEntries = ($cachedEntries.Count -gt 0)
            }
            if ($hasCachedEntries) {
                return @(Remove-QOTicketsSuppressedPendingReplyEntries -TicketId $resolvedTicketId -Entries $cachedEntries)
            }
        } catch { }
    }

    try {
        $getQueueSnapshotCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTPendingReplyQueueSnapshot"
        if ($getQueueSnapshotCmd) {
            $snapshot = & $getQueueSnapshotCmd -TicketId $resolvedTicketId
            if ($snapshot -and ($snapshot.PSObject.Properties.Name -contains "Entries")) {
                $entries = @($snapshot.Entries | Where-Object { $_ })
                try {
                    if ($script:TicketsQueuedReplyEntriesCacheByTicketId -isnot [hashtable]) {
                        $script:TicketsQueuedReplyEntriesCacheByTicketId = @{}
                    }
                    $script:TicketsQueuedReplyEntriesCacheByTicketId[$resolvedTicketId] = @($entries)
                } catch { }
                return @(Remove-QOTicketsSuppressedPendingReplyEntries -TicketId $resolvedTicketId -Entries $entries)
            }
        }
    } catch { }

    $getPendingRepliesCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTTicketPendingReplies"
    if (-not $getPendingRepliesCmd) { return @() }

    try {
        $entries = @(& $getPendingRepliesCmd -TicketId $resolvedTicketId)
        try {
            if ($script:TicketsQueuedReplyEntriesCacheByTicketId -isnot [hashtable]) {
                $script:TicketsQueuedReplyEntriesCacheByTicketId = @{}
            }
            $script:TicketsQueuedReplyEntriesCacheByTicketId[$resolvedTicketId] = @($entries)
        } catch { }
        return @(Remove-QOTicketsSuppressedPendingReplyEntries -TicketId $resolvedTicketId -Entries $entries)
    } catch { return @() }
}

function Add-QOTicketsSuppressedPendingReplyDraftId {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $draftKey = ([string]($DraftId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId) -or [string]::IsNullOrWhiteSpace($draftKey)) { return }

    try {
        if ($script:TicketsSuppressedPendingReplyDraftIdsByTicketId -isnot [hashtable]) {
            $script:TicketsSuppressedPendingReplyDraftIdsByTicketId = @{}
        }

        $draftIds = @()
        if ($script:TicketsSuppressedPendingReplyDraftIdsByTicketId.ContainsKey($resolvedTicketId)) {
            $draftIds = @($script:TicketsSuppressedPendingReplyDraftIdsByTicketId[$resolvedTicketId] | Where-Object { $_ })
        }
        if ($draftIds -notcontains $draftKey) {
            $draftIds += $draftKey
        }
        $script:TicketsSuppressedPendingReplyDraftIdsByTicketId[$resolvedTicketId] = @($draftIds)
    } catch { }
}

function Remove-QOTicketsSuppressedPendingReplyDraftId {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $draftKey = ([string]($DraftId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId) -or [string]::IsNullOrWhiteSpace($draftKey)) { return }

    try {
        if ($script:TicketsSuppressedPendingReplyDraftIdsByTicketId -isnot [hashtable]) {
            $script:TicketsSuppressedPendingReplyDraftIdsByTicketId = @{}
        }
        if (-not $script:TicketsSuppressedPendingReplyDraftIdsByTicketId.ContainsKey($resolvedTicketId)) { return }

        $remaining = @(
            @($script:TicketsSuppressedPendingReplyDraftIdsByTicketId[$resolvedTicketId] | Where-Object { $_ }) |
                Where-Object { -not [string]::Equals(([string]($_ + "")).Trim(), $draftKey, [System.StringComparison]::OrdinalIgnoreCase) }
        )

        if ($remaining.Count -gt 0) {
            $script:TicketsSuppressedPendingReplyDraftIdsByTicketId[$resolvedTicketId] = @($remaining)
        } else {
            [void]$script:TicketsSuppressedPendingReplyDraftIdsByTicketId.Remove($resolvedTicketId)
        }
    } catch { }
}

function Remove-QOTicketsSuppressedPendingReplyEntries {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [AllowNull()][object[]]$Entries
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) { return @($Entries | Where-Object { $_ }) }

    try {
        if ($script:TicketsSuppressedPendingReplyDraftIdsByTicketId -isnot [hashtable]) {
            $script:TicketsSuppressedPendingReplyDraftIdsByTicketId = @{}
        }
        if (-not $script:TicketsSuppressedPendingReplyDraftIdsByTicketId.ContainsKey($resolvedTicketId)) {
            return @($Entries | Where-Object { $_ })
        }

        $suppressedDraftIds = @($script:TicketsSuppressedPendingReplyDraftIdsByTicketId[$resolvedTicketId] | Where-Object { $_ })
        if ($suppressedDraftIds.Count -eq 0) {
            [void]$script:TicketsSuppressedPendingReplyDraftIdsByTicketId.Remove($resolvedTicketId)
            return @($Entries | Where-Object { $_ })
        }

        return @(
            @($Entries | Where-Object { $_ }) |
                Where-Object {
                    $entryDraftId = ""
                    try { if ($_.PSObject.Properties.Name -contains "DraftId") { $entryDraftId = ([string]($_.DraftId + "")).Trim() } } catch { $entryDraftId = "" }
                    if ([string]::IsNullOrWhiteSpace($entryDraftId)) { return $true }
                    return ($suppressedDraftIds -notcontains $entryDraftId)
                }
        )
    } catch {
        return @($Entries | Where-Object { $_ })
    }
}

function Update-QOTicketObjectFromSource {
    param(
        [AllowNull()]$Target,
        [AllowNull()]$Source
    )

    if (-not $Target -or -not $Source) { return $Target }
    if ([object]::ReferenceEquals($Target, $Source)) { return $Target }

    foreach ($prop in @($Source.PSObject.Properties)) {
        if (-not $prop) { continue }
        $propName = ([string]($prop.Name + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($propName)) { continue }
        try {
            if ($Target.PSObject.Properties.Name -contains $propName) {
                $Target.$propName = $prop.Value
            } else {
                $Target | Add-Member -NotePropertyName $propName -NotePropertyValue $prop.Value -Force
            }
        } catch { }
    }

    return $Target
}

function Sync-QOTTicketLivePendingReplies {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][string]$TicketId,
        [switch]$PreferCached
    )

    if (-not $Ticket) { return $Ticket }

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) {
        $resolvedTicketId = Get-QOTicketIdValue -Ticket $Ticket
    }
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) { return $Ticket }

    $queuedReplies = @()
    try { $queuedReplies = @(Get-QOTicketsQueuedReplyEntries -TicketId $resolvedTicketId -Ticket $Ticket -PreferCached:$PreferCached) } catch { $queuedReplies = @() }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "PendingReplies") {
            $Ticket.PendingReplies = @($queuedReplies)
        } else {
            $Ticket | Add-Member -NotePropertyName PendingReplies -NotePropertyValue @($queuedReplies) -Force
        }
    } catch { }

    return $Ticket
}

function Merge-QOTTicketVisiblePendingReplyEntries {
    param(
        [AllowNull()][object[]]$OptimisticReplies,
        [AllowNull()][object[]]$QueuedReplies
    )

    $mergedEntries = New-Object System.Collections.Generic.List[object]
    $queuedDraftIds = @{}

    foreach ($queuedReply in @($QueuedReplies | Where-Object { $_ })) {
        $queuedDraftId = ""
        try { if ($queuedReply.PSObject.Properties.Name -contains "DraftId") { $queuedDraftId = ([string]($queuedReply.DraftId + "")).Trim() } } catch { $queuedDraftId = "" }
        if (-not [string]::IsNullOrWhiteSpace($queuedDraftId)) {
            $queuedDraftIds[$queuedDraftId] = $true
        }
        $mergedEntries.Add($queuedReply) | Out-Null
    }

    foreach ($optimisticReply in @($OptimisticReplies | Where-Object { $_ })) {
        $optimisticDraftId = ""
        try { if ($optimisticReply.PSObject.Properties.Name -contains "DraftId") { $optimisticDraftId = ([string]($optimisticReply.DraftId + "")).Trim() } } catch { $optimisticDraftId = "" }
        if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $queuedDraftIds.ContainsKey($optimisticDraftId)) {
            continue
        }
        $mergedEntries.Add($optimisticReply) | Out-Null
    }

    try { return @($mergedEntries.ToArray()) } catch { return @() }
}

function Set-QOTicketsOptimisticReplyEntries {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [AllowNull()][object[]]$Entries
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) { return }

    try {
        if ($script:TicketsOptimisticRepliesByTicketId -isnot [hashtable]) {
            $script:TicketsOptimisticRepliesByTicketId = @{}
        }

        $cleanEntries = @($Entries | Where-Object { $_ })
        if ($cleanEntries.Count -gt 0) {
            $script:TicketsOptimisticRepliesByTicketId[$resolvedTicketId] = @($cleanEntries)
        } else {
            [void]$script:TicketsOptimisticRepliesByTicketId.Remove($resolvedTicketId)
        }
    } catch { }
}

function Add-QOTicketsOptimisticReply {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [AllowNull()][string]$DraftId,
        [AllowNull()][datetime]$CreatedAt = (Get-Date)
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $subjectValue = ([string]($Subject + "")).Trim()
    $bodyValue = ([string]($Body + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) { throw "Ticket Id is required." }
    if ([string]::IsNullOrWhiteSpace($subjectValue)) { throw "Reply subject is required." }
    if ([string]::IsNullOrWhiteSpace($bodyValue)) { throw "Reply body is required." }

    $draftKey = ([string]($DraftId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($draftKey)) {
        $draftKey = [guid]::NewGuid().ToString("N")
    }

    $createdStamp = $CreatedAt
    if (-not $createdStamp -or $createdStamp -eq [datetime]::MinValue) {
        $createdStamp = Get-Date
    }
    $createdText = $createdStamp.ToString("o")

    $entry = [pscustomobject]@{
        DraftId      = $draftKey
        Subject      = $subjectValue
        Body         = $bodyValue
        CreatedAt    = $createdText
        LastAttemptAt = $createdText
        SendState    = "Pending"
        FailureNote  = ""
        RetryCount   = 0
    }

    $entries = @(Get-QOTicketsOptimisticReplyEntries -TicketId $resolvedTicketId)
    Set-QOTicketsOptimisticReplyEntries -TicketId $resolvedTicketId -Entries (@($entries) + @($entry))
    return $entry
}

function Set-QOTicketsOptimisticReplyState {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId,
        [ValidateSet("Pending","Queued","Sending","Failed")][string]$SendState,
        [AllowNull()][string]$FailureNote
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $draftKey = ([string]($DraftId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId) -or [string]::IsNullOrWhiteSpace($draftKey)) { return $null }

    $entries = @(Get-QOTicketsOptimisticReplyEntries -TicketId $resolvedTicketId)
    if ($entries.Count -eq 0) { return $null }

    $matchedEntry = $null
    $nowText = (Get-Date).ToString("o")
    foreach ($entry in $entries) {
        if (-not $entry) { continue }
        $entryDraftId = ""
        try { if ($entry.PSObject.Properties.Name -contains "DraftId") { $entryDraftId = ([string]($entry.DraftId + "")).Trim() } } catch { $entryDraftId = "" }
        if ($entryDraftId -ne $draftKey) { continue }

        if ($entry.PSObject.Properties.Name -contains "SendState") {
            $entry.SendState = $SendState
        } else {
            $entry | Add-Member -NotePropertyName SendState -NotePropertyValue $SendState -Force
        }

        if ($entry.PSObject.Properties.Name -contains "LastAttemptAt") {
            $entry.LastAttemptAt = $nowText
        } else {
            $entry | Add-Member -NotePropertyName LastAttemptAt -NotePropertyValue $nowText -Force
        }

        if ([string]::Equals($SendState, "Pending", [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($SendState, "Sending", [System.StringComparison]::OrdinalIgnoreCase)) {
            $retryCount = 0
            try { if ($entry.PSObject.Properties.Name -contains "RetryCount") { $retryCount = [int]$entry.RetryCount } } catch { $retryCount = 0 }
            $retryCount++
            if ($entry.PSObject.Properties.Name -contains "RetryCount") {
                $entry.RetryCount = $retryCount
            } else {
                $entry | Add-Member -NotePropertyName RetryCount -NotePropertyValue $retryCount -Force
            }

            if ($entry.PSObject.Properties.Name -contains "FailureNote") {
                $entry.FailureNote = ""
            } else {
                $entry | Add-Member -NotePropertyName FailureNote -NotePropertyValue "" -Force
            }
        } elseif ([string]::Equals($SendState, "Queued", [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($entry.PSObject.Properties.Name -contains "FailureNote") {
                $entry.FailureNote = ""
            } else {
                $entry | Add-Member -NotePropertyName FailureNote -NotePropertyValue "" -Force
            }
        } else {
            $failureValue = ([string]($FailureNote + "")).Trim()
            if ($entry.PSObject.Properties.Name -contains "FailureNote") {
                $entry.FailureNote = $failureValue
            } else {
                $entry | Add-Member -NotePropertyName FailureNote -NotePropertyValue $failureValue -Force
            }
        }

        $matchedEntry = $entry
        break
    }

    Set-QOTicketsOptimisticReplyEntries -TicketId $resolvedTicketId -Entries $entries
    return $matchedEntry
}

function Remove-QOTicketsOptimisticReply {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $draftKey = ([string]($DraftId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId) -or [string]::IsNullOrWhiteSpace($draftKey)) { return }

    $entries = @(Get-QOTicketsOptimisticReplyEntries -TicketId $resolvedTicketId)
    if ($entries.Count -eq 0) { return }

    $remainingEntries = @(
        $entries |
            Where-Object {
                if (-not $_) { return $false }
                $entryDraftId = ""
                try { if ($_.PSObject.Properties.Name -contains "DraftId") { $entryDraftId = ([string]($_.DraftId + "")).Trim() } } catch { $entryDraftId = "" }
                return ($entryDraftId -ne $draftKey)
            }
    )
    Set-QOTicketsOptimisticReplyEntries -TicketId $resolvedTicketId -Entries $remainingEntries
}

function Remove-QOTicketsLocalPendingReply {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$DraftId,
        [AllowNull()]$Ticket
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $draftKey = ([string]($DraftId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId) -or [string]::IsNullOrWhiteSpace($draftKey)) { return }

    try { Remove-QOTicketsOptimisticReply -TicketId $resolvedTicketId -DraftId $draftKey } catch { }

    try {
        if ($script:TicketsQueuedReplyEntriesCacheByTicketId -is [hashtable] -and $script:TicketsQueuedReplyEntriesCacheByTicketId.ContainsKey($resolvedTicketId)) {
            $remainingCached = @(
                @($script:TicketsQueuedReplyEntriesCacheByTicketId[$resolvedTicketId] | Where-Object { $_ }) |
                    Where-Object {
                        $entryDraftId = ""
                        try { if ($_.PSObject.Properties.Name -contains "DraftId") { $entryDraftId = ([string]($_.DraftId + "")).Trim() } } catch { $entryDraftId = "" }
                        return (-not [string]::Equals($entryDraftId, $draftKey, [System.StringComparison]::OrdinalIgnoreCase))
                    }
            )
            if ($remainingCached.Count -gt 0) {
                $script:TicketsQueuedReplyEntriesCacheByTicketId[$resolvedTicketId] = @($remainingCached)
            } else {
                [void]$script:TicketsQueuedReplyEntriesCacheByTicketId.Remove($resolvedTicketId)
            }
        }
    } catch { }

    try {
        if ($Ticket -and ($Ticket.PSObject.Properties.Name -contains "PendingReplies")) {
            $Ticket.PendingReplies = @(
                @($Ticket.PendingReplies | Where-Object { $_ }) |
                    Where-Object {
                        $entryDraftId = ""
                        try { if ($_.PSObject.Properties.Name -contains "DraftId") { $entryDraftId = ([string]($_.DraftId + "")).Trim() } } catch { $entryDraftId = "" }
                        return (-not [string]::Equals($entryDraftId, $draftKey, [System.StringComparison]::OrdinalIgnoreCase))
                    }
            )
        }
    } catch { }

    try {
        if ($script:TicketsReplyQueuedSends -is [System.Collections.Queue] -and $script:TicketsReplyQueuedSends.Count -gt 0) {
            $rebuiltQueue = New-Object System.Collections.Queue
            foreach ($queuedSend in @($script:TicketsReplyQueuedSends.ToArray())) {
                if (-not $queuedSend) { continue }
                $queuedTicketId = ""
                $queuedDraftId = ""
                try { if ($queuedSend.PSObject.Properties.Name -contains "TicketId") { $queuedTicketId = ([string]($queuedSend.TicketId + "")).Trim() } } catch { $queuedTicketId = "" }
                try { if ($queuedSend.PSObject.Properties.Name -contains "DraftId") { $queuedDraftId = ([string]($queuedSend.DraftId + "")).Trim() } } catch { $queuedDraftId = "" }
                if ([string]::Equals($queuedTicketId, $resolvedTicketId, [System.StringComparison]::OrdinalIgnoreCase) -and
                    [string]::Equals($queuedDraftId, $draftKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $rebuiltQueue.Enqueue($queuedSend)
            }
            $script:TicketsReplyQueuedSends = $rebuiltQueue
        }
    } catch { }
}

function Add-QOTicketsLocalInternalNote {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$Note,
        [Parameter(Mandatory)][string]$Author,
        [Parameter(Mandatory)][string]$ClientNoteId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $noteBody = ([string]($Note + "")).Trim()
    $noteAuthor = ([string]($Author + "")).Trim()
    $noteKey = ([string]($ClientNoteId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId) -or [string]::IsNullOrWhiteSpace($noteBody) -or [string]::IsNullOrWhiteSpace($noteKey)) { return $null }
    if ([string]::IsNullOrWhiteSpace($noteAuthor)) { $noteAuthor = "User" }

    $noteCreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $noteEntry = [pscustomobject]@{
        NoteId          = $noteKey
        Body            = $noteBody
        CreatedAt       = $noteCreatedAt
        Author          = $noteAuthor
        Type            = "InternalNote"
        EntryType       = "InternalNote"
        ClientNoteId    = $noteKey
        IsPendingPersist = $true
    }

    foreach ($candidate in @($script:AllTickets)) {
        if (-not $candidate) { continue }
        $candidateTicketId = ""
        try { $candidateTicketId = Get-QOTicketIdValue -Ticket $candidate } catch { $candidateTicketId = "" }
        if (-not [string]::Equals($candidateTicketId, $resolvedTicketId, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $existingNotes = @()
        try { if ($candidate.PSObject.Properties.Name -contains "Notes") { $existingNotes = @($candidate.Notes | Where-Object { $_ }) } } catch { $existingNotes = @() }
        $duplicateFound = $false
        foreach ($existingNote in $existingNotes) {
            if (-not $existingNote) { continue }
            $existingClientNoteId = ""
            try { if ($existingNote.PSObject.Properties.Name -contains "ClientNoteId") { $existingClientNoteId = ([string]($existingNote.ClientNoteId + "")).Trim() } } catch { $existingClientNoteId = "" }
            if ([string]::Equals($existingClientNoteId, $noteKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                $duplicateFound = $true
                break
            }
        }
        if ($duplicateFound) { continue }

        try {
            if ($candidate.PSObject.Properties.Name -contains "Notes") {
                $candidate.Notes = @($existingNotes) + @($noteEntry)
            } else {
                $candidate | Add-Member -NotePropertyName Notes -NotePropertyValue @($noteEntry) -Force
            }
            try { Write-QOTicketsUILog ("Tickets: Internal note added to memory. TicketId='{0}' NoteId='{1}' Collection='Notes' NoteCount={2}." -f $resolvedTicketId, $noteKey, @($candidate.Notes).Count) } catch { }
        } catch { }
    }

    return $noteEntry
}

function Remove-QOTicketsLocalInternalNote {
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][Alias("ClientNoteId")][string]$NoteId,
        [AllowNull()]$Ticket
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    $noteKey = ([string]($NoteId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId) -or [string]::IsNullOrWhiteSpace($noteKey)) { return 0 }

    $removedCount = 0
    $removeFromTicket = {
        param([AllowNull()]$Candidate)

        if (-not $Candidate) { return 0 }
        $candidateTicketId = ""
        try { $candidateTicketId = Get-QOTicketIdValue -Ticket $Candidate } catch { $candidateTicketId = "" }
        if (-not [string]::Equals($candidateTicketId, $resolvedTicketId, [System.StringComparison]::OrdinalIgnoreCase)) { return 0 }

        $candidateRemoved = 0
        foreach ($noteCollectionName in @("Notes", "InternalNotes")) {
            if (-not ($Candidate.PSObject.Properties.Name -contains $noteCollectionName)) { continue }
            $remainingNotes = @()
            foreach ($existingNote in @($Candidate.$noteCollectionName)) {
                if (-not $existingNote) { continue }
                $matchesNote = $false
                foreach ($noteIdProp in @("NoteId", "ClientNoteId", "Id")) {
                    $existingNoteId = ""
                    try {
                        if ($existingNote.PSObject.Properties.Name -contains $noteIdProp) {
                            $existingNoteId = ([string]($existingNote.$noteIdProp + "")).Trim()
                        }
                    } catch { $existingNoteId = "" }
                    if (-not [string]::IsNullOrWhiteSpace($existingNoteId) -and [string]::Equals($existingNoteId, $noteKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $matchesNote = $true
                        break
                    }
                }
                if ($matchesNote) {
                    $candidateRemoved++
                    continue
                }
                $remainingNotes += $existingNote
            }

            try { $Candidate.$noteCollectionName = @($remainingNotes) } catch { }
        }

        return $candidateRemoved
    }.GetNewClosure()

    try { $removedCount += [int](& $removeFromTicket $Ticket) } catch { }
    foreach ($candidate in @($script:AllTickets)) {
        if (-not $candidate) { continue }
        try { $removedCount += [int](& $removeFromTicket $candidate) } catch { }
    }

    return $removedCount
}

function Sync-QOTTicketCanonicalActivityAliases {
    param(
        [AllowNull()]$Ticket
    )

    if (-not $Ticket) { return $Ticket }

    try {
        $notes = @()
        $internalNotes = @()
        try { if ($Ticket.PSObject.Properties.Name -contains "Notes") { $notes = @($Ticket.Notes | Where-Object { $_ }) } } catch { $notes = @() }
        try { if ($Ticket.PSObject.Properties.Name -contains "InternalNotes") { $internalNotes = @($Ticket.InternalNotes | Where-Object { $_ }) } } catch { $internalNotes = @() }
        if (($notes.Count -eq 0) -and ($internalNotes.Count -gt 0)) {
            if ($Ticket.PSObject.Properties.Name -contains "Notes") {
                $Ticket.Notes = @($internalNotes)
            } else {
                $Ticket | Add-Member -NotePropertyName Notes -NotePropertyValue @($internalNotes) -Force
            }
        }
        if ($Ticket.PSObject.Properties.Name -contains "InternalNotes") {
            $Ticket.InternalNotes = @()
        }
    } catch { }

    try {
        $replies = @()
        $sentReplies = @()
        try { if ($Ticket.PSObject.Properties.Name -contains "Replies") { $replies = @($Ticket.Replies | Where-Object { $_ }) } } catch { $replies = @() }
        try { if ($Ticket.PSObject.Properties.Name -contains "SentReplies") { $sentReplies = @($Ticket.SentReplies | Where-Object { $_ }) } } catch { $sentReplies = @() }
        if (($replies.Count -eq 0) -and ($sentReplies.Count -gt 0)) {
            if ($Ticket.PSObject.Properties.Name -contains "Replies") {
                $Ticket.Replies = @($sentReplies)
            } else {
                $Ticket | Add-Member -NotePropertyName Replies -NotePropertyValue @($sentReplies) -Force
            }
        }
        if ($Ticket.PSObject.Properties.Name -contains "SentReplies") {
            $Ticket.SentReplies = @()
        }
    } catch { }

    return $Ticket
}

function Get-QOTicketsReplyMatchKey {
    param(
        [AllowNull()]$Reply
    )

    if (-not $Reply) { return "" }

    $subjectValue = ""
    $bodyValue = ""
    try {
        if ($Reply.PSObject.Properties.Name -contains "Subject") {
            $subjectValue = ([string]($Reply.Subject + "")).Trim()
        }
    } catch { $subjectValue = "" }
    try {
        if ($Reply.PSObject.Properties.Name -contains "Body") {
            $bodyValue = [string]($Reply.Body + "")
        } else {
            $bodyValue = [string]($Reply + "")
        }
    } catch { $bodyValue = "" }

    $bodyValue = $bodyValue.Replace("`r`n", "`n").Replace("`r", "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($bodyValue)) { return "" }

    return ($subjectValue.ToLowerInvariant() + "`n" + $bodyValue)
}

function Get-QOTicketsReplyCreatedUtc {
    param(
        [AllowNull()]$Reply
    )

    if (-not $Reply) { return [datetime]::MinValue }

    foreach ($propertyName in @("CreatedAt", "LastAttemptAt")) {
        $rawValue = ""
        try {
            if ($Reply.PSObject.Properties.Name -contains $propertyName) {
                $rawValue = [string]($Reply.$propertyName + "")
            }
        } catch { $rawValue = "" }
        if ([string]::IsNullOrWhiteSpace($rawValue)) { continue }

        try {
            $createdValue = [datetime]$rawValue
            if ($createdValue.Kind -eq [System.DateTimeKind]::Unspecified) {
                $createdValue = [datetime]::SpecifyKind($createdValue, [System.DateTimeKind]::Local)
            }
            return $createdValue.ToUniversalTime()
        } catch { }
    }

    return [datetime]::MinValue
}

function Remove-QOTicketsResolvedOptimisticReplies {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][string]$TicketId
    )

    $resolvedTicketId = ([string]($TicketId + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId)) {
        $resolvedTicketId = Get-QOTicketIdValue -Ticket $Ticket
    }
    if ([string]::IsNullOrWhiteSpace($resolvedTicketId) -or -not $Ticket) { return 0 }

    $entries = @(Get-QOTicketsOptimisticReplyEntries -TicketId $resolvedTicketId)
    if ($entries.Count -eq 0) { return 0 }

    $savedReplies = @()
    try {
        if ($Ticket.PSObject.Properties.Name -contains "Replies") {
            $savedReplies = @($Ticket.Replies)
        }
    } catch { $savedReplies = @() }
    if ($savedReplies.Count -eq 0) { return 0 }

    $savedReplyMatches = New-Object System.Collections.ArrayList
    foreach ($reply in $savedReplies) {
        $replyKey = Get-QOTicketsReplyMatchKey -Reply $reply
        if (-not [string]::IsNullOrWhiteSpace($replyKey)) {
            [void]$savedReplyMatches.Add([pscustomobject]@{
                Key        = $replyKey
                CreatedUtc = Get-QOTicketsReplyCreatedUtc -Reply $reply
            })
        }
    }
    if ($savedReplyMatches.Count -eq 0) { return 0 }

    $remainingEntries = @()
    $removedCount = 0
    foreach ($entry in $entries) {
        if (-not $entry) { continue }

        $entryKey = Get-QOTicketsReplyMatchKey -Reply $entry
        if ([string]::IsNullOrWhiteSpace($entryKey)) {
            $remainingEntries += $entry
            continue
        }

        $matchIndex = -1
        $entryCreatedUtc = Get-QOTicketsReplyCreatedUtc -Reply $entry
        for ($i = 0; $i -lt $savedReplyMatches.Count; $i++) {
            $savedMatch = $savedReplyMatches[$i]
            $savedKey = ""
            $savedCreatedUtc = [datetime]::MinValue
            try { $savedKey = [string]$savedMatch.Key } catch { $savedKey = "" }
            try { $savedCreatedUtc = [datetime]$savedMatch.CreatedUtc } catch { $savedCreatedUtc = [datetime]::MinValue }

            $isFreshMatch = $true
            if ($entryCreatedUtc -ne [datetime]::MinValue -and $savedCreatedUtc -ne [datetime]::MinValue) {
                $isFreshMatch = ($savedCreatedUtc -ge $entryCreatedUtc.AddSeconds(-5))
            }

            if ($isFreshMatch -and [string]::Equals($savedKey, $entryKey, [System.StringComparison]::Ordinal)) {
                $matchIndex = $i
                break
            }
        }

        if ($matchIndex -ge 0) {
            $savedReplyMatches.RemoveAt($matchIndex)
            $removedCount++
            continue
        }

        $remainingEntries += $entry
    }

    if ($removedCount -gt 0) {
        Set-QOTicketsOptimisticReplyEntries -TicketId $resolvedTicketId -Entries $remainingEntries
        try {
            $stillPending = @(
                $remainingEntries |
                    Where-Object {
                        $_ -and
                        ($_.PSObject.Properties.Name -contains "SendState") -and
                        (([string]($_.SendState + "")).Trim() -match '^(?i)(Pending|Queued|Sending)$')
                    }
            )
            if ($stillPending.Count -eq 0) {
                $script:TicketsReplySendInProgress = $false
                $script:TicketsReplyStartUtc = [datetime]::MinValue
            }
        } catch { }
    }

    return $removedCount
}

function Get-QOTicketsLatestFailedOptimisticReply {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][string]$TicketId
    )

    $entries = @(
        Get-QOTicketsOptimisticReplyEntries -Ticket $Ticket -TicketId $TicketId |
            Where-Object {
                $_ -and
                ($_.PSObject.Properties.Name -contains "SendState") -and
                [string]::Equals(([string]($_.SendState + "")).Trim(), "Failed", [System.StringComparison]::OrdinalIgnoreCase)
            }
    )
    if ($entries.Count -eq 0) {
        try {
            $entries = @(
                Get-QOTicketsQueuedReplyEntries -Ticket $Ticket -TicketId $TicketId |
                    Where-Object {
                        $_ -and
                        ($_.PSObject.Properties.Name -contains "SendState") -and
                        [string]::Equals(([string]($_.SendState + "")).Trim(), "Failed", [System.StringComparison]::OrdinalIgnoreCase)
                    }
            )
        } catch { $entries = @() }
    }
    if ($entries.Count -eq 0) { return $null }

    return @(
        $entries |
            Sort-Object -Property @{
                Expression = {
                    $stamp = ""
                    try {
                        if ($_.PSObject.Properties.Name -contains "LastAttemptAt") {
                            $stamp = [string]$_.LastAttemptAt
                        } elseif ($_.PSObject.Properties.Name -contains "CreatedAt") {
                            $stamp = [string]$_.CreatedAt
                        }
                    } catch { $stamp = "" }

                    try {
                        if (-not [string]::IsNullOrWhiteSpace($stamp)) { return [datetime]$stamp }
                    } catch { }
                    return [datetime]::MinValue
                }
                Descending = $true
            }
    )[0]
}

function Get-QOTicketsLastSuccessfulSyncLabel {
    $defaultLabel = "Last successful email sync: Never"
    try {
        try {
            $persistedLastSyncUtc = Get-QOTicketsPersistedLastSuccessfulSyncUtc
            if ($persistedLastSyncUtc -and $persistedLastSyncUtc -is [datetime]) {
                $persistedLastSyncUtc = [datetime]::SpecifyKind($persistedLastSyncUtc.ToUniversalTime(), [System.DateTimeKind]::Utc)
                $currentLastSyncUtc = $script:TicketsLastSuccessfulSyncUtc
                $shouldUsePersisted = $false
                if (-not $currentLastSyncUtc -or $currentLastSyncUtc -isnot [datetime] -or $currentLastSyncUtc -eq [datetime]::MinValue) {
                    $shouldUsePersisted = $true
                } else {
                    try {
                        $currentLastSyncUtc = ([datetime]$currentLastSyncUtc).ToUniversalTime()
                        if ($persistedLastSyncUtc -gt $currentLastSyncUtc) {
                            $shouldUsePersisted = $true
                        }
                    } catch {
                        $shouldUsePersisted = $true
                    }
                }

                if ($shouldUsePersisted) {
                    $script:TicketsLastSuccessfulSyncUtc = $persistedLastSyncUtc
                }
            }
        } catch { }

        $lastSyncUtc = $script:TicketsLastSuccessfulSyncUtc
        if (-not $lastSyncUtc) { return $defaultLabel }
        if ($lastSyncUtc -isnot [datetime]) { return $defaultLabel }
        if ($lastSyncUtc -eq [datetime]::MinValue) { return $defaultLabel }

        $utcValue = [datetime]::SpecifyKind($lastSyncUtc, [System.DateTimeKind]::Utc)
        $localValue = $utcValue.ToLocalTime()
        return ("Last successful email sync: {0}" -f $localValue.ToString("g"))
    } catch {
        return $defaultLabel
    }
}

function Get-QOTicketsPersistedLastSuccessfulSyncUtc {
    try {
        if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) { return $null }
        $settings = Get-QOSettings
        if (-not $settings) { return $null }
        if ($settings.PSObject.Properties.Name -notcontains "Tickets") { return $null }
        if (-not $settings.Tickets) { return $null }
        if ($settings.Tickets.PSObject.Properties.Name -notcontains "EmailIntegration") { return $null }
        if (-not $settings.Tickets.EmailIntegration) { return $null }

        $candidateValues = @()
        if ($settings.Tickets.EmailIntegration.PSObject.Properties.Name -contains "LastSuccessfulSyncUtc") {
            $candidateValues += @([string]($settings.Tickets.EmailIntegration.LastSuccessfulSyncUtc + ""))
        }
        if ($settings.Tickets.EmailIntegration.PSObject.Properties.Name -contains "LastSyncUtc") {
            $candidateValues += @([string]($settings.Tickets.EmailIntegration.LastSyncUtc + ""))
        }

        foreach ($candidate in @($candidateValues)) {
            $rawValue = ([string]($candidate + "")).Trim()
            if ([string]::IsNullOrWhiteSpace($rawValue)) { continue }
            try {
                $parsed = [datetime]::Parse($rawValue)
                return $parsed.ToUniversalTime()
            } catch { }
        }

        return $null
    } catch {
        return $null
    }
}

function Test-QOTicketsHasRecentSuccessfulSync {
    param(
        [int]$WithinSeconds = 180
    )

    try {
        $lastSyncUtc = $script:TicketsLastSuccessfulSyncUtc
        if (-not $lastSyncUtc) { return $false }
        if ($lastSyncUtc -isnot [datetime]) { return $false }
        if ($lastSyncUtc -eq [datetime]::MinValue) { return $false }

        $thresholdSeconds = [math]::Max(5, [int]$WithinSeconds)
        $utcValue = [datetime]::SpecifyKind($lastSyncUtc, [System.DateTimeKind]::Utc)
        $ageSeconds = ((Get-Date).ToUniversalTime() - $utcValue).TotalSeconds
        return ($ageSeconds -ge 0 -and $ageSeconds -le $thresholdSeconds)
    } catch {
        return $false
    }
}

function Test-QOTicketsHasSuccessfulSyncTimestamp {
    try {
        $lastSyncUtc = $script:TicketsLastSuccessfulSyncUtc
        if (-not $lastSyncUtc) { return $false }
        if ($lastSyncUtc -isnot [datetime]) { return $false }
        if ($lastSyncUtc -eq [datetime]::MinValue) { return $false }
        return $true
    } catch {
        return $false
    }
}

function Get-QOTicketsSyncStatusDisplayState {
    param(
        [string]$DisplayLabel,
        [string]$Message
    )

    $displayText = $DisplayLabel
    $toolTipParts = @()
    $messageText = ""

    try { $messageText = ([string]($Message + "")).Trim() } catch { $messageText = "" }
    if (-not [string]::IsNullOrWhiteSpace($messageText)) {
        $normalized = $messageText.ToLowerInvariant()
        $hasSuccessfulSync = Test-QOTicketsHasSuccessfulSyncTimestamp
        $showMessageInline = $false

        if (-not $hasSuccessfulSync) {
            $showMessageInline = $true
        }
        elseif (
            $normalized.StartsWith("background sync") -or
            $normalized.StartsWith("email sync loading") -or
            $normalized.StartsWith("checking outlook") -or
            $normalized.StartsWith("open outlook") -or
            $normalized.StartsWith("classic outlook is not open") -or
            $normalized.StartsWith("outlook reconnecting") -or
            $normalized.StartsWith("manual sync") -or
            $normalized.StartsWith("sync failed") -or
            $normalized.StartsWith("sync unavailable") -or
            $normalized.StartsWith("recovered stale sync") -or
            $normalized.StartsWith("tickets ready")
        ) {
            $showMessageInline = $true
        }

        if ($showMessageInline) {
            $displayText = $messageText
            if (-not [string]::IsNullOrWhiteSpace($DisplayLabel) -and $DisplayLabel -ne $displayText) {
                $toolTipParts += @($DisplayLabel)
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($messageText) -and $messageText -ne $DisplayLabel) {
            $toolTipParts += @($messageText)
        }
    }

    if ($messageText.ToLowerInvariant().StartsWith("open outlook") -or $messageText.ToLowerInvariant().StartsWith("classic outlook is not open")) {
        $toolTipParts += @("Open Classic Outlook and sign in. QOT will attach automatically once Outlook is ready.")
    }
    $toolTipParts += @("Click to sync now.")
    $toolTipText = @(
        $toolTipParts |
            ForEach-Object { ([string]($_ + "")).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    ) -join [Environment]::NewLine

    if ([string]::IsNullOrWhiteSpace($displayText)) {
        $displayText = "Click to sync now."
    }
    if ([string]::IsNullOrWhiteSpace($toolTipText)) {
        $toolTipText = $null
    }

    return [pscustomobject]@{
        Text    = $displayText
        ToolTip = $toolTipText
    }
}

function Format-QOTicketSummaryHeaderText {
    param([AllowNull()][string[]]$SummaryLines)

    $parts = @(
        @($SummaryLines) |
            ForEach-Object { ([string]($_ + "")).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($parts.Count -eq 0) { return "" }
    return [string]($parts -join "  |  ")
}

function Set-QOTicketSummaryHeader {
    param(
        [AllowNull()][System.Windows.Controls.TextBlock]$SummaryControl,
        [AllowNull()][string[]]$SummaryLines
    )

    if (-not $SummaryControl) { return }

    $summaryText = ""
    try { $summaryText = Format-QOTicketSummaryHeaderText -SummaryLines $SummaryLines } catch { $summaryText = "" }
    $hasText = (-not [string]::IsNullOrWhiteSpace($summaryText))

    try {
        if ($SummaryControl.Dispatcher.CheckAccess()) {
            $SummaryControl.Text = $summaryText
            $SummaryControl.Visibility = if ($hasText) { "Visible" } else { "Collapsed" }
        } else {
            $SummaryControl.Dispatcher.BeginInvoke([action]{
                $SummaryControl.Text = $summaryText
                $SummaryControl.Visibility = if ($hasText) { "Visible" } else { "Collapsed" }
            }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        }
    } catch { }
}

function Get-QOTicketContactInitials {
    param([AllowNull()][string]$Value)

    $raw = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return "--" }

    if ($raw -like "*@*") {
        try { $raw = ([string]$raw.Split("@")[0]).Trim() } catch { }
    }

    $parts = @(
        ($raw -split '[^A-Za-z0-9]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    )

    if ($parts.Count -ge 2) {
        $initials = ([string]$parts[0].Substring(0,1) + [string]$parts[1].Substring(0,1)).ToUpperInvariant()
        return $initials
    }

    if ($parts.Count -eq 1) {
        $one = [string]$parts[0]
        if ($one.Length -ge 2) {
            return $one.Substring(0,2).ToUpperInvariant()
        }
        if ($one.Length -eq 1) {
            return $one.ToUpperInvariant()
        }
    }

    return "--"
}

function Get-QOTicketFirstEmailFromText {
    param([AllowNull()][string]$Value)

    $text = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }

    $match = [regex]::Match($text, '(?i)([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})')
    if (-not $match.Success) { return "" }

    return ([string]$match.Groups[1].Value).Trim()
}

function Resolve-QOTicketBodyPath {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][string]$BodyPath
    )

    $resolvedPath = ([string]($BodyPath + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        try {
            $ticketIdForBody = Get-QOTicketIdValue -Ticket $Ticket
            if (-not [string]::IsNullOrWhiteSpace($ticketIdForBody)) {
                $safeId = ($ticketIdForBody -replace '[^a-zA-Z0-9\-_]', '_')
                if (-not [string]::IsNullOrWhiteSpace($safeId)) {
                    $getStorePathCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTicketsStorePath"
                    if ($getStorePathCmd) {
                        $storePath = [string](& $getStorePathCmd)
                        if (-not [string]::IsNullOrWhiteSpace($storePath)) {
                            $baseDir = Split-Path -Parent $storePath
                            $fallbackBodyPath = Join-Path (Join-Path $baseDir "Bodies") ($safeId + ".txt")
                            if (Test-Path -LiteralPath $fallbackBodyPath) {
                                return $fallbackBodyPath
                            }
                        }
                    }
                }
            }
        } catch { }
        return ""
    }

    try {
        if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
            $getStorePathCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTicketsStorePath"
            if ($getStorePathCmd) {
                $storePath = [string](& $getStorePathCmd)
                if (-not [string]::IsNullOrWhiteSpace($storePath)) {
                    $baseDir = Split-Path -Parent $storePath
                    $candidatePath = Join-Path $baseDir $resolvedPath
                    if (Test-Path -LiteralPath $candidatePath) {
                        $resolvedPath = $candidatePath
                    }
                }
            }
        }
    } catch { }

    try {
        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            $ticketIdForBody = Get-QOTicketIdValue -Ticket $Ticket
            if (-not [string]::IsNullOrWhiteSpace($ticketIdForBody)) {
                $safeId = ($ticketIdForBody -replace '[^a-zA-Z0-9\-_]', '_')
                if (-not [string]::IsNullOrWhiteSpace($safeId)) {
                    $getStorePathCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTicketsStorePath"
                    if ($getStorePathCmd) {
                        $storePath = [string](& $getStorePathCmd)
                        if (-not [string]::IsNullOrWhiteSpace($storePath)) {
                            $baseDir = Split-Path -Parent $storePath
                            $fallbackBodyPath = Join-Path (Join-Path $baseDir "Bodies") ($safeId + ".txt")
                            if (Test-Path -LiteralPath $fallbackBodyPath) {
                                $resolvedPath = $fallbackBodyPath
                            }
                        }
                    }
                }
            }
        }
    } catch { }

    return $resolvedPath
}

function Convert-QOTicketHtmlToPlainText {
    param([AllowNull()][string]$Html)

    $value = [string]($Html + "")
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }

    try {
        $value = $value -replace '(?is)<(script|style)\b[^>]*>.*?</\1>', ' '
        $value = $value -replace '(?i)<br\s*/?>', "`r`n"
        $value = $value -replace '(?i)</(p|div|li|tr|table|section|article|blockquote|h[1-6])\s*>', "`r`n"
        $value = $value -replace '(?i)<li\b[^>]*>', ' - '
        $value = $value -replace '(?s)<[^>]+>', ' '
        $value = [System.Net.WebUtility]::HtmlDecode($value)
        $value = $value -replace "[\u00A0\u2007\u202F]", " "
        $value = $value -replace '\r?\n[ \t]+', "`r`n"
        $value = $value -replace '[ \t]{2,}', ' '
        $value = $value -replace '(\r?\n){3,}', "`r`n`r`n"
        return $value.Trim()
    } catch {
        return ([string]($Html + "")).Trim()
    }
}

function Read-QOTicketBodyFilePreview {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxChars = 220000
    )

    if ($MaxChars -lt 1024) { $MaxChars = 1024 }
    if (-not (Test-Path -LiteralPath $Path)) { return "" }

    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream, $true)
        $buffer = New-Object char[] $MaxChars
        $read = $reader.ReadBlock($buffer, 0, $MaxChars)
        if ($read -le 0) { return "" }
        $text = New-Object string ($buffer, 0, $read)
        if (-not $reader.EndOfStream) {
            $text += "`r`n`r`n[Body truncated for display.]"
        }
        return ([string]($text + "")).Trim()
    } finally {
        if ($reader) { $reader.Dispose() }
    }
}

function Get-QOTicketDisplayBodyInfo {
    param(
        [AllowNull()]$Ticket,
        [switch]$PreviewOnly
    )

    $result = [pscustomobject]@{
        Text     = ""
        Source   = "None"
        Property = ""
        BodyPath = ""
        Length   = 0
    }

    if (-not $Ticket) { return $result }

    $trySetResult = {
        param(
            [AllowNull()][string]$Text,
            [AllowNull()][string]$Source,
            [AllowNull()][string]$Property,
            [AllowNull()][string]$BodyPath
        )

        $value = ([string]($Text + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) { return $false }
        $result.Text = $value
        $result.Source = ([string]($Source + "")).Trim()
        $result.Property = ([string]($Property + "")).Trim()
        $result.BodyPath = ([string]($BodyPath + "")).Trim()
        $result.Length = $value.Length
        return $true
    }.GetNewClosure()

    if (-not $PreviewOnly) {
        foreach ($pathPropName in @("EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath")) {
            $bodyPath = ""
            try {
                if ($Ticket.PSObject.Properties.Name -contains $pathPropName) {
                    $bodyPath = ([string]($Ticket.$pathPropName + "")).Trim()
                }
            } catch { $bodyPath = "" }
            if ([string]::IsNullOrWhiteSpace($bodyPath)) { continue }

            try { $bodyPath = Resolve-QOTicketBodyPath -Ticket $Ticket -BodyPath $bodyPath } catch { }
            if ([string]::IsNullOrWhiteSpace($bodyPath)) { continue }

            try {
                $fileText = Read-QOTicketBodyFilePreview -Path $bodyPath
                if ($pathPropName -match 'Html') {
                    $fileText = Convert-QOTicketHtmlToPlainText -Html $fileText
                }
                if (& $trySetResult -Text $fileText -Source "BodyPath" -Property $pathPropName -BodyPath $bodyPath) {
                    return $result
                }
            } catch {
                try { Write-QOTicketsUILog ("Tickets: Failed to read email body file '{0}'. {1}" -f $bodyPath, $_.Exception.Message) "WARN" } catch { }
            }
        }

        foreach ($bodyPropName in @("EmailBody", "Body", "TextBody", "HtmlBody")) {
            try {
                if (-not ($Ticket.PSObject.Properties.Name -contains $bodyPropName)) { continue }
                $bodyValue = [string]($Ticket.$bodyPropName + "")
                if ($bodyPropName -eq "HtmlBody") {
                    $bodyValue = Convert-QOTicketHtmlToPlainText -Html $bodyValue
                }
                if (& $trySetResult -Text $bodyValue -Source "InlineBody" -Property $bodyPropName -BodyPath "") {
                    return $result
                }
            } catch { }
        }
    }

    foreach ($previewPropName in @("EmailBodyPreview", "BodyPreview", "Preview")) {
        try {
            if (-not ($Ticket.PSObject.Properties.Name -contains $previewPropName)) { continue }
            if (& $trySetResult -Text ([string]($Ticket.$previewPropName + "")) -Source "Preview" -Property $previewPropName -BodyPath "") {
                return $result
            }
        } catch { }
    }

    return $result
}

function Test-QOTicketEmailIsMonitoredMailbox {
    param([AllowNull()][string]$EmailAddress)

    $email = (Get-QOTicketFirstEmailFromText -Value $EmailAddress).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($email)) { return $false }

    try {
        if (-not (Get-Command Get-QOTMonitoredMailboxAddresses -ErrorAction SilentlyContinue)) { return $false }
        foreach ($mailbox in @(Get-QOTMonitoredMailboxAddresses)) {
            $candidate = (Get-QOTicketFirstEmailFromText -Value ([string]($mailbox + ""))).Trim().ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate -eq $email) {
                return $true
            }
        }
    } catch { }

    return $false
}

function Get-QOTicketSenderFallbackInfo {
    param([AllowNull()]$Ticket)

    $result = [pscustomobject]@{
        SenderEmail = ""
        SenderName  = ""
    }

    if (-not $Ticket) { return $result }

    $bodyText = ""
    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailBodyPath") {
            $bodyPath = ([string]($Ticket.EmailBodyPath + "")).Trim()
            $bodyPath = Resolve-QOTicketBodyPath -Ticket $Ticket -BodyPath $bodyPath
            if (-not [string]::IsNullOrWhiteSpace($bodyPath) -and (Test-Path -LiteralPath $bodyPath)) {
                $bodyText = Get-Content -LiteralPath $bodyPath -Raw -ErrorAction SilentlyContinue
            }
        }
    } catch { $bodyText = "" }

    if ([string]::IsNullOrWhiteSpace($bodyText)) {
        foreach ($propName in @("EmailBody", "EmailBodyPreview")) {
            try {
                if ([string]::IsNullOrWhiteSpace($bodyText) -and $Ticket.PSObject.Properties.Name -contains $propName) {
                    $bodyText = ([string]($Ticket.$propName + "")).Trim()
                }
            } catch { }
        }
    }

    $emailMatches = @(
        [regex]::Match($bodyText, '(?im)^\s*From:\s*(?<name>[^<\r\n]+?)\s*<(?<email>[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})>'),
        [regex]::Match($bodyText, '(?im)^\s*From:\s*(?<email>[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})\b'),
        [regex]::Match($bodyText, '(?im)^\s*Email:\s*(?<email>[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})\b')
    )

    foreach ($match in $emailMatches) {
        if (-not $match.Success) { continue }
        try {
            $email = ([string]$match.Groups['email'].Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($email)) {
                $result.SenderEmail = $email
                break
            }
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($result.SenderEmail)) {
        $anyEmail = Get-QOTicketFirstEmailFromText -Value $bodyText
        if (-not [string]::IsNullOrWhiteSpace($anyEmail)) {
            $result.SenderEmail = $anyEmail
        }
    }

    foreach ($match in $emailMatches) {
        if (-not $match.Success) { continue }
        try {
            $name = ([string]$match.Groups['name'].Value).Trim(' ', '"', "'", '<', '>')
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $result.SenderName = $name
                break
            }
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($result.SenderName)) {
        $signatureMatch = [regex]::Match($bodyText, '(?ms)(?:Regards|Kind regards|Cheers|Thanks)[,\s]*\r?\n(?<name>[^\r\n]+)')
        if ($signatureMatch.Success) {
            try {
                $signatureName = ([string]$signatureMatch.Groups['name'].Value).Trim()
                if (-not [string]::IsNullOrWhiteSpace($signatureName) -and $signatureName.Length -le 80) {
                    $result.SenderName = $signatureName
                }
            } catch { }
        }
    }

    if ([string]::IsNullOrWhiteSpace($result.SenderEmail)) {
        foreach ($propName in @("RequesterEmail", "RequestEmail", "CustomerEmail", "ContactEmail", "EmailAddress", "EmailTo")) {
            try {
                if (-not ($Ticket.PSObject.Properties.Name -contains $propName)) { continue }
                $candidate = Get-QOTicketFirstEmailFromText -Value ([string]($Ticket.$propName + ""))
                if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                if ($propName -eq "EmailTo" -and (Test-QOTicketEmailIsMonitoredMailbox -EmailAddress $candidate)) { continue }
                $result.SenderEmail = $candidate
                break
            } catch { }
        }
    }

    return $result
}

function Get-QOTicketContactHeaderModel {
    param([AllowNull()]$Ticket)

    $model = [pscustomobject]@{
        PrimaryText      = "Email sender unavailable"
        MetaText         = "Unassigned"
        Initials         = "--"
        StatusDotColor   = "#6B7280"
        AvatarBackColor  = "#4B5563"
    }

    if (-not $Ticket) { return $model }

    try {
        $resolveDetailsTicketCmd = Resolve-QOTicketsLocalFunction -Name "Resolve-QOTTicketDetailsSourceTicket"
        if ($resolveDetailsTicketCmd) {
            $resolvedTicket = & $resolveDetailsTicketCmd -Ticket $Ticket
            if ($resolvedTicket) { $Ticket = $resolvedTicket }
        }
    } catch { }

    $fromRaw = ""
    $sourceRaw = ""
    $senderNameHint = ""
    $assigneeRaw = ""
    foreach ($senderProp in @("EmailFrom", "From", "Sender", "SenderEmail", "SenderAddress", "EmailSender", "EmailAddress", "ContactEmail")) {
        try {
            if ([string]::IsNullOrWhiteSpace($fromRaw) -and $Ticket.PSObject.Properties.Name -contains $senderProp) {
                $fromRaw = ([string]($Ticket.$senderProp + "")).Trim()
            }
        } catch { }
    }
    foreach ($nameProp in @("SenderName", "FromName", "DisplayName", "ContactName", "Author", "CreatedBy")) {
        try {
            if ([string]::IsNullOrWhiteSpace($senderNameHint) -and $Ticket.PSObject.Properties.Name -contains $nameProp) {
                $senderNameHint = ([string]($Ticket.$nameProp + "")).Trim()
            }
        } catch { }
    }
    try { if ($Ticket.PSObject.Properties.Name -contains "Source") { $sourceRaw = ([string]($Ticket.Source + "")).Trim() } } catch { $sourceRaw = "" }
    try { if ($Ticket.PSObject.Properties.Name -contains "AssignedTo") { $assigneeRaw = ([string]($Ticket.AssignedTo + "")).Trim() } } catch { $assigneeRaw = "" }

    $senderName = ""
    $senderEmail = ""
    $looksLikeLegacyExchangeDn = $false
    if (-not [string]::IsNullOrWhiteSpace($fromRaw)) {
        if ($fromRaw -match '^\s*/O=' -or $fromRaw -match '/CN=RECIPIENTS/') {
            $looksLikeLegacyExchangeDn = $true
        }
        $match = [regex]::Match($fromRaw, '^\s*"?([^"<]+?)"?\s*<\s*([^>]+)\s*>\s*$')
        if ($match.Success) {
            $senderName = ([string]$match.Groups[1].Value).Trim()
            $senderEmail = ([string]$match.Groups[2].Value).Trim()
        } else {
            if ($fromRaw -like "*@*" -and -not $looksLikeLegacyExchangeDn) {
                $senderEmail = $fromRaw
            } elseif (-not $looksLikeLegacyExchangeDn) {
                $senderName = $fromRaw
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($senderName) -and -not [string]::IsNullOrWhiteSpace($senderNameHint)) {
        $senderName = $senderNameHint
    }

    if (([string]::IsNullOrWhiteSpace($senderName) -and [string]::IsNullOrWhiteSpace($senderEmail)) -or $looksLikeLegacyExchangeDn) {
        $contactCacheKey = ""
        try {
            if ($Ticket.PSObject.Properties.Name -contains "Id") {
                $contactCacheKey = ([string]($Ticket.Id + "")).Trim()
            }
        } catch { $contactCacheKey = "" }
        if ([string]::IsNullOrWhiteSpace($contactCacheKey)) {
            try {
                if ($Ticket.PSObject.Properties.Name -contains "EmailMessageId") {
                    $contactCacheKey = ("internet:" + ([string]($Ticket.EmailMessageId + "")).Trim().ToLowerInvariant())
                }
            } catch { $contactCacheKey = "" }
        }
        if ([string]::IsNullOrWhiteSpace($contactCacheKey)) {
            try {
                if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") {
                    $contactCacheKey = ("source:" + ([string]($Ticket.SourceMessageId + "")).Trim().ToLowerInvariant())
                }
            } catch { $contactCacheKey = "" }
        }

        $liveContact = $null
        if (-not [string]::IsNullOrWhiteSpace($contactCacheKey) -and $script:TicketsContactLookupCache.ContainsKey($contactCacheKey)) {
            $liveContact = $script:TicketsContactLookupCache[$contactCacheKey]
        }

        if ($liveContact) {
            try { if ([string]::IsNullOrWhiteSpace($senderName)) { $senderName = ([string]($liveContact.SenderName + "")).Trim() } } catch { }
            try { if ([string]::IsNullOrWhiteSpace($senderEmail)) { $senderEmail = ([string]($liveContact.SenderEmail + "")).Trim() } } catch { }
            if ([string]::IsNullOrWhiteSpace($fromRaw) -or $looksLikeLegacyExchangeDn) {
                try { $fromRaw = ([string]($liveContact.DisplayFrom + "")).Trim() } catch { $fromRaw = "" }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($senderEmail) -or $looksLikeLegacyExchangeDn) {
        try {
            $fallbackSender = Get-QOTicketSenderFallbackInfo -Ticket $Ticket
            if ($fallbackSender) {
                if ([string]::IsNullOrWhiteSpace($senderEmail)) {
                    $senderEmail = ([string]($fallbackSender.SenderEmail + "")).Trim()
                }
                if ([string]::IsNullOrWhiteSpace($senderName)) {
                    $senderName = ([string]($fallbackSender.SenderName + "")).Trim()
                }
            }
        } catch { }
    }

    $primary = ""
    if (-not [string]::IsNullOrWhiteSpace($senderEmail)) {
        $primary = $senderEmail
    } elseif (-not [string]::IsNullOrWhiteSpace($senderName)) {
        $primary = $senderName
    } elseif (-not [string]::IsNullOrWhiteSpace($fromRaw)) {
        $primary = $fromRaw
    }
    if ([string]::IsNullOrWhiteSpace($primary)) {
        if ([string]::Equals($sourceRaw, "Manual", [System.StringComparison]::OrdinalIgnoreCase)) {
            $primary = "Manual ticket"
        } else {
            $primary = "Email sender unavailable"
        }
    }

    $meta = "Unassigned"
    $statusDotColor = "#6B7280"
    $avatarBackColor = "#A855F7"
    if (-not [string]::IsNullOrWhiteSpace($assigneeRaw) -and -not [string]::Equals($assigneeRaw, "unassigned", [System.StringComparison]::OrdinalIgnoreCase)) {
        $meta = ("Assigned to " + $assigneeRaw)
        $statusDotColor = "#22C55E"
    }
    if ([string]::Equals($sourceRaw, "Manual", [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::IsNullOrWhiteSpace($fromRaw) -and
        [string]::IsNullOrWhiteSpace($senderNameHint) -and
        [string]::IsNullOrWhiteSpace($senderEmail)) {
        $avatarBackColor = "#475569"
        if ([string]::Equals($meta, "Unassigned", [System.StringComparison]::OrdinalIgnoreCase)) {
            $meta = "Manual ticket"
        }
    }

    $initialSeed = $senderName
    if ([string]::IsNullOrWhiteSpace($initialSeed)) {
        $initialSeed = $senderEmail
    }
    if ([string]::IsNullOrWhiteSpace($initialSeed)) {
        $initialSeed = $primary
    }

    return [pscustomobject]@{
        PrimaryText      = $primary
        MetaText         = $meta
        Initials         = (Get-QOTicketContactInitials -Value $initialSeed)
        StatusDotColor   = $statusDotColor
        AvatarBackColor  = $avatarBackColor
    }
}

function Set-QOTicketContactHeader {
    param([AllowNull()]$Ticket)

    if (-not $script:TicketsContactPrimaryText) { return }
    if (-not $script:TicketsContactAvatarText) { return }
    if (-not $script:TicketsContactMetaText) { return }
    if (-not $script:TicketsContactStatusDot) { return }

    $model = Get-QOTicketContactHeaderModel -Ticket $Ticket

    $primaryTextControl = $script:TicketsContactPrimaryText
    $avatarTextControl = $script:TicketsContactAvatarText
    $metaTextControl = $script:TicketsContactMetaText
    $statusDotControl = $script:TicketsContactStatusDot
    $avatarControl = $script:TicketsContactAvatar
    $primaryTextValue = [string]$model.PrimaryText
    $avatarTextValue = [string]$model.Initials
    $metaTextValue = [string]$model.MetaText
    $statusDotColorValue = [string]$model.StatusDotColor
    $avatarBackColorValue = [string]$model.AvatarBackColor

    $apply = {
        $brushConverter = [System.Windows.Media.BrushConverter]::new()
        $primaryTextControl.Text = $primaryTextValue
        $avatarTextControl.Text = $avatarTextValue
        $metaTextControl.Text = $metaTextValue
        $statusDotControl.Fill = $brushConverter.ConvertFromString($statusDotColorValue)
        if ($avatarControl) {
            $avatarControl.Background = $brushConverter.ConvertFromString($avatarBackColorValue)
        }
    }.GetNewClosure()

    try {
        if ($primaryTextControl.Dispatcher.CheckAccess()) {
            & $apply
        } else {
            $primaryTextControl.Dispatcher.BeginInvoke([action]$apply, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        }
    } catch {
        try { Write-QOTicketsUILog ("Tickets: Failed to update contact header: " + $_.Exception.Message) "WARN" } catch { }
    }
}

function Normalize-QOTicketsAssigneeFilterValue {
    param([AllowNull()][string]$Value)

    $normalized = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) { return "All" }
    if ($normalized.StartsWith("@")) { $normalized = $normalized.TrimStart("@") }

    switch ($normalized.ToLowerInvariant()) {
        "all" { return "All" }
        "unassigned" { return "Unassigned" }
        "none" { return "Unassigned" }
        "n/a" { return "Unassigned" }
        "na" { return "Unassigned" }
        "null" { return "Unassigned" }
        default { return $normalized }
    }
}

function Get-QOTicketsDefaultFilterState {
    return [pscustomobject]@{
        ShowOpen             = [bool]$script:TicketsFilterDefaults.ShowOpen
        ShowClosed           = [bool]$script:TicketsFilterDefaults.ShowClosed
        ShowDeleted          = [bool]$script:TicketsFilterDefaults.ShowDeleted
        SortMode             = [string]$script:TicketsFilterDefaults.SortMode
        AssigneeFilter       = [string]$script:TicketsFilterDefaults.AssigneeFilter
    }
}

function Get-QOTicketsFilterState {
    if (-not $script:TicketsFilterState) {
        $script:TicketsFilterState = Get-QOTicketsDefaultFilterState
    }

    foreach ($prop in @("ShowOpen", "ShowClosed", "ShowDeleted", "SortMode", "AssigneeFilter")) {
        if ($script:TicketsFilterState.PSObject.Properties.Name -notcontains $prop) {
            $script:TicketsFilterState | Add-Member -NotePropertyName $prop -NotePropertyValue (Get-QOTicketsDefaultFilterState.$prop) -Force
        }
        if ($null -eq $script:TicketsFilterState.$prop) {
            $script:TicketsFilterState.$prop = Get-QOTicketsDefaultFilterState.$prop
        }
    }

    # Backward compatibility with older persisted setting.
    if ($script:TicketsFilterState.PSObject.Properties.Name -contains "SortPriorityHighToLow" -and
        $script:TicketsFilterState.PSObject.Properties.Name -notcontains "SortMode") {
        $legacyPrioritySort = $true
        try { $legacyPrioritySort = [bool]$script:TicketsFilterState.SortPriorityHighToLow } catch { $legacyPrioritySort = $true }
        $legacySortMode = if ($legacyPrioritySort) { "Priority" } else { "Newest" }
        $script:TicketsFilterState | Add-Member -NotePropertyName SortMode -NotePropertyValue $legacySortMode -Force
    }

    try {
        if (-not (Get-Command Get-QOTicketListViewSettings -ErrorAction SilentlyContinue)) {
            try { Import-Module (Join-Path $PSScriptRoot "..\Core\Settings.psm1") -Force -ErrorAction SilentlyContinue } catch { }
        }
        $getListViewCmd = Resolve-QOTicketsLocalFunction -Name "Get-QOTicketListViewSettings"
        if (-not $getListViewCmd) {
            $getListViewCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketListViewSettings -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketListViewSettings"
        }
        if ($getListViewCmd) {
            $savedState = & $getListViewCmd
            if ($savedState) {
                try { $script:TicketsFilterState.ShowOpen = [bool]$savedState.ShowOpen } catch { }
                try { $script:TicketsFilterState.ShowClosed = [bool]$savedState.ShowClosed } catch { }
                try { $script:TicketsFilterState.ShowDeleted = [bool]$savedState.ShowDeleted } catch { }
                try {
                    $savedSortMode = ([string]($savedState.SortMode + "")).Trim()
                    switch ($savedSortMode.ToLowerInvariant()) {
                        "newest" { $script:TicketsFilterState.SortMode = "Newest" }
                        "oldest" { $script:TicketsFilterState.SortMode = "Oldest" }
                        default { $script:TicketsFilterState.SortMode = "Priority" }
                    }
                } catch { }
                try {
                    $script:TicketsFilterState.AssigneeFilter = Normalize-QOTicketsAssigneeFilterValue -Value ([string]$savedState.AssigneeFilter)
                } catch { }
            }
        }
    } catch { }

    return $script:TicketsFilterState
}

function Save-QOTicketsFilterState {
    param(
        [Parameter(Mandatory)][bool]$ShowOpen,
        [Parameter(Mandatory)][bool]$ShowClosed,
        [Parameter(Mandatory)][bool]$ShowDeleted,
        [Parameter(Mandatory)][string]$SortMode,
        [AllowNull()][string]$AssigneeFilter = "All"
    )

    try {
        if (-not (Get-Command Set-QOTicketListViewSettings -ErrorAction SilentlyContinue)) {
            try { Import-Module (Join-Path $PSScriptRoot "..\Core\Settings.psm1") -Force -ErrorAction SilentlyContinue } catch { }
        }
        $setListViewCmd = Resolve-QOTicketsLocalFunction -Name "Set-QOTicketListViewSettings"
        if (-not $setListViewCmd) {
            $setListViewCmd = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTicketListViewSettings -ErrorAction SilentlyContinue) -CommandName "Set-QOTicketListViewSettings"
        }
        if (-not $setListViewCmd) { return $false }
        $normalizedAssigneeFilter = Normalize-QOTicketsAssigneeFilterValue -Value $AssigneeFilter
        $null = & $setListViewCmd -ShowOpen $ShowOpen -ShowClosed $ShowClosed -ShowDeleted $ShowDeleted -SortMode $SortMode -AssigneeFilter $normalizedAssigneeFilter
        return $true
    } catch {
        Write-QOTicketsUILog ("Tickets: Persisting filter/sort settings failed. " + $_.Exception.Message) "WARN"
        return $false
    }
}

function Set-QOTicketsFilterRuntimeState {
    param(
        [Parameter(Mandatory)][bool]$ShowOpen,
        [Parameter(Mandatory)][bool]$ShowClosed,
        [Parameter(Mandatory)][bool]$ShowDeleted,
        [Parameter(Mandatory)][string]$SortMode,
        [AllowNull()][string]$AssigneeFilter = "All",
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid
    )

    $normalizedSortMode = ([string]($SortMode + "")).Trim()
    switch ($normalizedSortMode.ToLowerInvariant()) {
        "newest" { $normalizedSortMode = "Newest" }
        "oldest" { $normalizedSortMode = "Oldest" }
        default { $normalizedSortMode = "Priority" }
    }

    $showOpenValue = [bool]$ShowOpen
    $showClosedValue = [bool]$ShowClosed
    $showDeletedValue = [bool]$ShowDeleted
    if (-not ($showOpenValue -or $showClosedValue -or $showDeletedValue)) {
        $showOpenValue = $true
    }

    $script:ShowOpen = $showOpenValue
    $script:ShowClosed = $showClosedValue
    $script:ShowDeleted = $showDeletedValue
    $script:TicketsSortMode = $normalizedSortMode
    $script:TicketsAssigneeFilter = Normalize-QOTicketsAssigneeFilterValue -Value $AssigneeFilter
    if ($Grid) {
        $script:TicketsGrid = $Grid
    }
}

function Write-QOTicketsFilterLog {
    param(
        [bool]$Open,
        [bool]$Closed,
        [bool]$Deleted
    )

    $message = ("Tickets filter updated: Open={0}, Closed={1}, Deleted={2}" -f $Open, $Closed, $Deleted)
    try {
        if (Get-Command Write-QOTLogInfo -ErrorAction SilentlyContinue) {
            Write-QOTLogInfo $message
            return
        }
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $message "INFO"
            return
        }
    } catch { }

    try {
        $fallbackDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null
        $fallbackPath = Join-Path $fallbackDir "TicketsUI.log"
        Add-Content -LiteralPath $fallbackPath -Value ("[{0}] [INFO] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $message) -Encoding UTF8
    } catch { }
}

function Resolve-QOTInvokable {
    param(
        [AllowNull()]$Candidate,
        [AllowNull()][string]$CommandName
    )

    $resolved = $null

    if ($Candidate -is [System.Management.Automation.CommandInfo] -or
        $Candidate -is [scriptblock] -or
        $Candidate -is [string]) {
        $resolved = $Candidate
    }
    elseif ($Candidate -is [System.Collections.IEnumerable] -and $Candidate -isnot [string]) {
        foreach ($entry in @($Candidate)) {
            if ($entry -is [System.Management.Automation.CommandInfo] -or
                $entry -is [scriptblock] -or
                $entry -is [string]) {
                $resolved = $entry
                break
            }
        }
    }

    if (-not $resolved -and -not [string]::IsNullOrWhiteSpace([string]$CommandName)) {
        try {
            $resolved = @(Get-Command -Name $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($resolved -is [System.Array]) {
                if ($resolved.Count -gt 0) { $resolved = $resolved[0] } else { $resolved = $null }
            }
        } catch {
            $resolved = $null
        }
    }

    return $resolved
}

function Resolve-QOTicketsLocalFunction {
    param([Parameter(Mandatory)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }

    try {
        $functionItem = Get-Item -LiteralPath ("Function:\{0}" -f $Name) -ErrorAction SilentlyContinue
        if ($functionItem -and $functionItem.ScriptBlock) {
            try {
                if ($ExecutionContext.SessionState.Module) {
                    return $ExecutionContext.SessionState.Module.NewBoundScriptBlock($functionItem.ScriptBlock)
                }
            } catch { }
            return $functionItem.ScriptBlock
        }
    } catch { }

    return $null
}

function Get-QOTTicketsWindowResource {
    param(
        [AllowNull()]$Window,
        [Parameter(Mandatory)][string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return $null }

    $resolvedWindow = $Window
    if (-not $resolvedWindow) {
        try { $resolvedWindow = $script:TicketsWindow } catch { $resolvedWindow = $null }
    }
    if (-not $resolvedWindow) { return $null }

    try {
        if ($resolvedWindow.Resources.Contains($Key)) {
            return $resolvedWindow.Resources[$Key]
        }
    } catch { }

    try {
        $resource = $resolvedWindow.TryFindResource($Key)
        if ($null -ne $resource) { return $resource }
    } catch { }

    return $null
}

function Apply-QOTTicketsSeparatorTheme {
    param(
        [AllowNull()][System.Windows.Controls.Separator]$Separator,
        [AllowNull()]$Window
    )

    if (-not $Separator) { return $Separator }

    $separatorStyle = Get-QOTTicketsWindowResource -Window $Window -Key "QOTSeparatorStyle"
    if ($separatorStyle) {
        try { $Separator.Style = $separatorStyle } catch { }
    }
    return $Separator
}

function Apply-QOTTicketsMenuItemTheme {
    param(
        [AllowNull()][System.Windows.Controls.MenuItem]$MenuItem,
        [AllowNull()]$Window
    )

    if (-not $MenuItem) { return $MenuItem }

    $menuItemStyle = Get-QOTTicketsWindowResource -Window $Window -Key "QOTMenuItemStyle"
    if ($menuItemStyle) {
        try { $MenuItem.Style = $menuItemStyle } catch { }
        try { $MenuItem.ItemContainerStyle = $menuItemStyle } catch { }
    }

    foreach ($childItem in @($MenuItem.Items)) {
        if ($childItem -is [System.Windows.Controls.MenuItem]) {
            Apply-QOTTicketsMenuItemTheme -MenuItem $childItem -Window $Window | Out-Null
        } elseif ($childItem -is [System.Windows.Controls.Separator]) {
            Apply-QOTTicketsSeparatorTheme -Separator $childItem -Window $Window | Out-Null
        }
    }

    return $MenuItem
}

function Apply-QOTTicketsContextMenuTheme {
    param(
        [AllowNull()][System.Windows.Controls.ContextMenu]$ContextMenu,
        [AllowNull()]$Window
    )

    if (-not $ContextMenu) { return $ContextMenu }

    $contextMenuStyle = Get-QOTTicketsWindowResource -Window $Window -Key "QOTContextMenuStyle"
    if ($contextMenuStyle) {
        try { $ContextMenu.Style = $contextMenuStyle } catch { }
    }

    $menuItemStyle = Get-QOTTicketsWindowResource -Window $Window -Key "QOTMenuItemStyle"
    if ($menuItemStyle) {
        try { $ContextMenu.ItemContainerStyle = $menuItemStyle } catch { }
    }

    foreach ($childItem in @($ContextMenu.Items)) {
        if ($childItem -is [System.Windows.Controls.MenuItem]) {
            Apply-QOTTicketsMenuItemTheme -MenuItem $childItem -Window $Window | Out-Null
        } elseif ($childItem -is [System.Windows.Controls.Separator]) {
            Apply-QOTTicketsSeparatorTheme -Separator $childItem -Window $Window | Out-Null
        }
    }

    return $ContextMenu
}

function New-QOTTicketsStyledSeparator {
    param([AllowNull()]$Window)

    $separator = New-Object System.Windows.Controls.Separator
    Apply-QOTTicketsSeparatorTheme -Separator $separator -Window $Window | Out-Null
    return $separator
}

function Resolve-QOTicketsCoreCommand {
    param([Parameter(Mandatory)][string]$CommandName)

    $nameValue = ([string]($CommandName + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($nameValue)) { return $null }

    $resolvedCommand = $null
    try {
        $resolvedCommand = @(Get-Command -Name $nameValue -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($resolvedCommand -is [System.Array]) {
            if ($resolvedCommand.Count -gt 0) { $resolvedCommand = $resolvedCommand[0] } else { $resolvedCommand = $null }
        }
    } catch { $resolvedCommand = $null }

    if (-not $resolvedCommand) {
        try {
            if ($script:TicketsCoreCommandCache -isnot [hashtable]) {
                $script:TicketsCoreCommandCache = @{}
            }
            if ($script:TicketsCoreCommandCache.ContainsKey($nameValue)) {
                return $script:TicketsCoreCommandCache[$nameValue]
            }
        } catch { }
    }

    $coreModule = $null
    if (-not $resolvedCommand) {
        try { $coreModule = @(Get-Module -Name "Tickets" | Select-Object -First 1)[0] } catch { $coreModule = $null }
        if ($coreModule) {
            try {
                $qualifiedName = ("{0}\{1}" -f [string]$coreModule.Name, $nameValue)
                $resolvedCommand = @(Get-Command -Name $qualifiedName -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($resolvedCommand -is [System.Array]) {
                    if ($resolvedCommand.Count -gt 0) { $resolvedCommand = $resolvedCommand[0] } else { $resolvedCommand = $null }
                }
            } catch { $resolvedCommand = $null }
        }
    }

    if (-not $resolvedCommand -and $coreModule) {
        try {
            if ($coreModule.ExportedCommands) {
                foreach ($exportedKey in @($coreModule.ExportedCommands.Keys)) {
                    if (([string]$exportedKey) -ieq $nameValue) {
                        $resolvedCommand = $coreModule.ExportedCommands[$exportedKey]
                        break
                    }
                }
            }
        } catch { $resolvedCommand = $null }
    }

    if ($resolvedCommand) {
        try {
            if ($script:TicketsCoreCommandCache -isnot [hashtable]) {
                $script:TicketsCoreCommandCache = @{}
            }
            $script:TicketsCoreCommandCache[$nameValue] = $resolvedCommand
        } catch { }
    }

    return $resolvedCommand
}

function Test-QOTicketHasStoredActivity {
    param([AllowNull()]$Ticket)

    if (-not $Ticket) { return $false }

    try {
        foreach ($textProp in @("EmailBody", "Body", "HtmlBody", "TextBody", "Preview", "EmailBodyPreview", "BodyPreview")) {
            if ($Ticket.PSObject.Properties.Name -contains $textProp) {
                $value = ([string]($Ticket.$textProp + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $true }
            }
        }
    } catch { }

    try {
        foreach ($pathProp in @("EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath", "PreviewPath")) {
            if ($Ticket.PSObject.Properties.Name -contains $pathProp) {
                $resolvedPath = Resolve-QOTicketBodyPath -Ticket $Ticket -BodyPath ([string]($Ticket.$pathProp + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($resolvedPath) -and (Test-Path -LiteralPath $resolvedPath)) {
                    return $true
                }
            }
        }
    } catch { }

    foreach ($listProp in @("IncomingMessages", "Replies", "Notes", "PendingReplies", "Messages", "History", "Conversation", "SentReplies", "InternalNotes", "SystemEvents", "Events", "Timeline", "Activity", "AuditTrail")) {
        try {
            if ($Ticket.PSObject.Properties.Name -contains $listProp) {
                if (@($Ticket.$listProp | Where-Object { $_ }).Count -gt 0) { return $true }
            }
        } catch { }
    }

    return $false
}

function Get-QOTTicketDetailsRenderModel {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][string]$RenderPath = "Default",
        [switch]$PreferCurrentTicket,
        [switch]$PreferCachedPendingReplies
    )

    $renderStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $resolvedTicket = $Ticket
    if (-not $PreferCurrentTicket) {
        try {
            $resolveDetailsTicketCmd = Resolve-QOTicketsLocalFunction -Name "Resolve-QOTTicketDetailsSourceTicket"
            if ($resolveDetailsTicketCmd) {
                $resolvedTicket = & $resolveDetailsTicketCmd -Ticket $Ticket
            } else {
                $resolvedTicket = Resolve-QOTTicketDetailsSourceTicket -Ticket $Ticket
            }
        } catch {
            $resolvedTicket = $Ticket
        }
    }
    if (-not $resolvedTicket) { $resolvedTicket = $Ticket }
    try { $resolvedTicket = Sync-QOTTicketLivePendingReplies -Ticket $resolvedTicket -PreferCached:$PreferCachedPendingReplies } catch { }
    try {
        if ($Ticket -and $resolvedTicket -and -not [object]::ReferenceEquals($Ticket, $resolvedTicket)) {
            $null = Update-QOTicketObjectFromSource -Target $Ticket -Source $resolvedTicket
        }
    } catch { }

    $ticketIdForLog = ""
    $subjectForLog = ""
    try { $ticketIdForLog = Get-QOTicketIdValue -Ticket $Ticket } catch { $ticketIdForLog = "" }
    try { $subjectForLog = Get-QOTTicketPreferredSubject -Ticket $resolvedTicket } catch { $subjectForLog = "" }

    $detailsModel = $null
    $detailsText = ""
    $summaryLines = @()
    $eventItems = @()
    $getDetailsCmd = $null
    try { $getDetailsCmd = Resolve-QOTicketsLocalFunction -Name "Get-QOTicketDetailsBodyText" } catch { $getDetailsCmd = $null }

    try {
        if ($getDetailsCmd) {
            $detailsModel = & $getDetailsCmd -Ticket $resolvedTicket -AsModel -PreferCurrentTicket -PreferCachedPendingReplies:$PreferCachedPendingReplies
        } else {
            $detailsModel = Get-QOTicketDetailsBodyText -Ticket $resolvedTicket -AsModel -PreferCurrentTicket -PreferCachedPendingReplies:$PreferCachedPendingReplies
        }
    } catch {
        $detailsModel = $null
        try { Write-QOTicketsUILog ("Tickets: Detail model resolution failed: " + $_.Exception.Message) "WARN" } catch { }
    }

    try { if ($detailsModel -and ($detailsModel.PSObject.Properties.Name -contains "DetailsText")) { $detailsText = [string]$detailsModel.DetailsText } } catch { $detailsText = "" }
    try { if ($detailsModel -and ($detailsModel.PSObject.Properties.Name -contains "SummaryLines")) { $summaryLines = @($detailsModel.SummaryLines) } } catch { $summaryLines = @() }
    try { if ($detailsModel -and ($detailsModel.PSObject.Properties.Name -contains "Events")) { $eventItems = @($detailsModel.Events) } } catch { $eventItems = @() }

    $hasStoredActivity = $false
    try { $hasStoredActivity = [bool](Test-QOTicketHasStoredActivity -Ticket $resolvedTicket) } catch { $hasStoredActivity = $false }
    if ((@($eventItems).Count -eq 0) -and $hasStoredActivity) {
        try {
            if ($getDetailsCmd) {
                $detailsModel = & $getDetailsCmd -Ticket $resolvedTicket -AsModel -PreferCurrentTicket -PreferCachedPendingReplies:$PreferCachedPendingReplies
            } else {
                $detailsModel = Get-QOTicketDetailsBodyText -Ticket $resolvedTicket -AsModel -PreferCurrentTicket -PreferCachedPendingReplies:$PreferCachedPendingReplies
            }
        } catch { }
        try { if ($detailsModel -and ($detailsModel.PSObject.Properties.Name -contains "DetailsText")) { $detailsText = [string]$detailsModel.DetailsText } } catch { }
        try { if ($detailsModel -and ($detailsModel.PSObject.Properties.Name -contains "SummaryLines")) { $summaryLines = @($detailsModel.SummaryLines) } } catch { }
        try { if ($detailsModel -and ($detailsModel.PSObject.Properties.Name -contains "Events")) { $eventItems = @($detailsModel.Events) } } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($detailsText)) {
        try {
            if ($getDetailsCmd) {
                $detailsText = [string](& $getDetailsCmd -Ticket $resolvedTicket -PreferCurrentTicket -PreferCachedPendingReplies:$PreferCachedPendingReplies)
            } else {
                $detailsText = [string](Get-QOTicketDetailsBodyText -Ticket $resolvedTicket -PreferCurrentTicket -PreferCachedPendingReplies:$PreferCachedPendingReplies)
            }
        } catch {
            $detailsText = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($detailsText) -and (@($eventItems).Count -gt 0)) {
        try {
            $detailsText = ((@($eventItems) | ForEach-Object {
                $titleText = ([string]($_.Title + "")).Trim()
                $bodyText = ([string]($_.Body + "")).Trim()
                if ([string]::IsNullOrWhiteSpace($titleText)) { $titleText = "Update" }
                if ([string]::IsNullOrWhiteSpace($bodyText)) { return $null }
                return ($titleText + "`r`n" + $bodyText)
            } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n`r`n").Trim()
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($detailsText) -and (@($eventItems).Count -eq 0)) {
        try {
            $displayBodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $resolvedTicket
            $displayBodyText = ""
            if ($displayBodyInfo) {
                $displayBodyText = ([string]($displayBodyInfo.Text + "")).Trim()
            }
            if (-not [string]::IsNullOrWhiteSpace($displayBodyText)) {
                $mainDate = [datetime]::MinValue
                try {
                    if ($resolvedTicket -and ($resolvedTicket.PSObject.Properties.Name -contains "CreatedAt")) {
                        $mainDate = [datetime]$resolvedTicket.CreatedAt
                    }
                } catch { $mainDate = [datetime]::MinValue }
                $detailsText = $displayBodyText
                $mainFromLine = [string](Get-QOTicketPropertyTextValue -Ticket $resolvedTicket -PropertyNames @("EmailFrom", "SenderName", "SenderEmail", "From", "Sender"))
                if ([string]::IsNullOrWhiteSpace($mainFromLine)) { $mainFromLine = "Email sender unavailable" }
                $eventItems = @(
                    [pscustomobject]@{
                        When      = $mainDate
                        SortOrder = 10
                        Kind      = "Email"
                        Title     = ("Main email from " + $mainFromLine)
                        Body      = $detailsText
                    }
                )
            }
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($detailsText) -and $hasStoredActivity) {
        $detailsText = "Ticket activity is available but could not be rendered."
    }

    try {
        $bodyFieldPresence = @()
        foreach ($fieldName in @("EmailBody", "Body", "HtmlBody", "TextBody", "Preview", "EmailBodyPreview", "BodyPreview", "EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath", "PreviewPath")) {
            if ($resolvedTicket -and ($resolvedTicket.PSObject.Properties.Name -contains $fieldName)) {
                $valueText = ([string]($resolvedTicket.$fieldName + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($valueText)) {
                    $bodyFieldPresence += $fieldName
                }
            }
        }
        $replyCount = 0
        $pendingCount = 0
        $historyCount = 0
        $displayBodyInfo = $null
        try { if ($resolvedTicket.PSObject.Properties.Name -contains "Replies") { $replyCount = @($resolvedTicket.Replies | Where-Object { $_ }).Count } } catch { $replyCount = 0 }
        try { if ($resolvedTicket.PSObject.Properties.Name -contains "PendingReplies") { $pendingCount = @($resolvedTicket.PendingReplies | Where-Object { $_ }).Count } } catch { $pendingCount = 0 }
        try { $displayBodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $resolvedTicket } catch { $displayBodyInfo = $null }
        try {
            foreach ($historyProp in @("IncomingMessages", "Notes", "Messages", "History", "Conversation", "SentReplies", "InternalNotes", "SystemEvents", "Events", "Timeline", "Activity", "AuditTrail")) {
                if ($resolvedTicket.PSObject.Properties.Name -contains $historyProp) {
                    $historyCount += @($resolvedTicket.$historyProp | Where-Object { $_ }).Count
                }
            }
        } catch { $historyCount = 0 }
        Write-QOTicketsUILog ("Tickets: Detail hydration. RenderPath={0}; TicketId={1}; Subject={2}; FullReloadAttempted={3}; ResolvedTicketId={4}; BodyFields={5}; DetailsLength={6}; EventCount={7}; ReplyCount={8}; PendingReplyCount={9}; HistoryCount={10}; DisplaySource={11}; DisplayProperty={12}; DisplayLength={13}" -f `
            ([string]($RenderPath + "")).Trim(), `
            $ticketIdForLog, `
            $subjectForLog, `
            $(if (-not [string]::IsNullOrWhiteSpace($ticketIdForLog)) { "Yes" } else { "No" }), `
            (Get-QOTicketIdValue -Ticket $resolvedTicket), `
            ($(if ($bodyFieldPresence.Count -gt 0) { $bodyFieldPresence -join "," } else { "None" })), `
            ([string]$detailsText).Length, `
            @($eventItems).Count, `
            $replyCount, `
            $pendingCount, `
            $historyCount, `
            $(if ($displayBodyInfo) { $displayBodyInfo.Source } else { "None" }), `
            $(if ($displayBodyInfo) { $displayBodyInfo.Property } else { "" }), `
            $(if ($displayBodyInfo) { $displayBodyInfo.Length } else { 0 }))
    } catch { }

    try { Write-QOTicketsUILog ("Tickets: Detail open time. RenderPath={0}; TicketId={1}; DurationMs={2}" -f ([string]($RenderPath + "")).Trim(), (Get-QOTicketIdValue -Ticket $resolvedTicket), [int]$renderStopwatch.Elapsed.TotalMilliseconds) } catch { }

    return [pscustomobject]@{
        Ticket            = $resolvedTicket
        DetailsModel      = $detailsModel
        DetailsText       = $detailsText
        SummaryLines      = @($summaryLines)
        Events            = @($eventItems)
        HasStoredActivity = $hasStoredActivity
    }
}

function Set-QOTicketsReplyUiRefreshWindow {
    param([int]$Seconds = 90)

    $windowSeconds = [Math]::Max(5, [int]$Seconds)
    try {
        $script:TicketsReplyUiRefreshUntilUtc = (Get-Date).ToUniversalTime().AddSeconds($windowSeconds)
    } catch {
        $script:TicketsReplyUiRefreshUntilUtc = [datetime]::MinValue
    }
}

function Get-QOTicketsAllItems {
    try {
        $storePath = ""
        $currentWriteUtc = [datetime]::MinValue
        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$script:TicketsStorePath)) {
                $storePath = [string]$script:TicketsStorePath
            } else {
                $getStorePathCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTicketsStorePath"
                if ($getStorePathCmd) {
                    $storePath = [string](& $getStorePathCmd)
                }
            }
        } catch { $storePath = "" }
        try {
            if (-not [string]::IsNullOrWhiteSpace($storePath) -and (Test-Path -LiteralPath $storePath)) {
                $currentWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($storePath)
            }
        } catch { $currentWriteUtc = [datetime]::MinValue }

        if ($null -ne $script:AllTickets) {
            $cachedItems = @($script:AllTickets)
            if ($cachedItems.Count -gt 0) {
                if (($currentWriteUtc -ne [datetime]::MinValue) -and ($script:TicketsLoadedStoreWriteUtc -ne [datetime]::MinValue) -and ($currentWriteUtc -eq $script:TicketsLoadedStoreWriteUtc)) {
                    Write-QOTicketsUILog ("Tickets: Reusing cached ticket list. Count={0}" -f $cachedItems.Count)
                    return $cachedItems
                }
                if ([string]::IsNullOrWhiteSpace($storePath)) {
                    Write-QOTicketsUILog ("Tickets: Reusing cached ticket list without resolved store path. Count={0}" -f $cachedItems.Count)
                    return $cachedItems
                }
            }
        }

        $items = $null
        $getTicketsCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTickets"
        if ($getTicketsCmd) {
            $items = & $getTicketsCmd
        }

        if ($null -eq $items) { return @() }

        if ($items.PSObject.Properties.Name -contains "Tickets") {
            $tickets = @($items.Tickets)
            $script:AllTickets = $tickets
            $script:TicketsLoadedStoreWriteUtc = $currentWriteUtc
            if (-not [string]::IsNullOrWhiteSpace($storePath)) { $script:TicketsStorePath = $storePath }
            Write-QOTicketsUILog ("Tickets: Loaded {0} items for grid (Tickets property)." -f $tickets.Count)
            return $tickets
        }

        $list = @($items)
        $script:AllTickets = $list
        $script:TicketsLoadedStoreWriteUtc = $currentWriteUtc
        if (-not [string]::IsNullOrWhiteSpace($storePath)) { $script:TicketsStorePath = $storePath }
        Write-QOTicketsUILog ("Tickets: Loaded {0} items for grid (direct)." -f $list.Count)
        return $list
    }
    catch {
        $msg = $_.Exception.Message
        $stack = $_.Exception.StackTrace
        $inner = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { "" }

        Write-QOTicketsUILog ("Tickets: Load failed. Error: " + $msg) "ERROR"
        if ($inner) { Write-QOTicketsUILog ("Tickets: InnerException: " + $inner) "ERROR" }
        if ($stack) { Write-QOTicketsUILog ("Tickets: StackTrace: " + $stack) "ERROR" }

        $popupMessage = "Tickets failed to load.`n`nError: " + $msg
        if ($inner) { $popupMessage += "`nInner: " + $inner }
        [System.Windows.MessageBox]::Show(
            $popupMessage,
            "Quinn Optimiser Toolkit",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        return @()
    }
}

function Get-QOTicketsVisibleItems {
    param(
        [object[]]$Items,
        [Parameter(Mandatory)]$FilterState
    )

    $showOpen = [bool]$FilterState.ShowOpen
    $showClosed = [bool]$FilterState.ShowClosed
    $showDeleted = [bool]$FilterState.ShowDeleted
    $assigneeFilter = "All"
    try { $assigneeFilter = Normalize-QOTicketsAssigneeFilterValue -Value ([string]$FilterState.AssigneeFilter) } catch { $assigneeFilter = "All" }

    if (-not ($showOpen -or $showClosed -or $showDeleted)) {
        return @()
    }

    return @(
        $Items |
            Where-Object {
                if ($null -eq $_) { return $false }

                $isDeleted = $false
                try { $isDeleted = [bool]$_.IsDeleted } catch { $isDeleted = $false }
                $statusValue = ""
                try {
                    if ($_.PSObject.Properties.Name -contains "Status") {
                        $statusValue = [string]$_.Status
                    }
                } catch { }
                $statusNormalized = ""
                try { $statusNormalized = ([string]($statusValue + "")).Trim().ToLowerInvariant() } catch { $statusNormalized = "" }
                $isClosed = ($statusNormalized -eq "closed" -or $statusNormalized -eq "completed")
                $isOpen = (-not $isDeleted) -and (-not $isClosed)
                $matchesState = ($showOpen -and $isOpen) -or
                                ($showClosed -and (-not $isDeleted) -and $isClosed) -or
                                ($showDeleted -and $isDeleted)
                if (-not $matchesState) { return $false }

                $assignedTo = "Unassigned"
                try {
                    if ($_.PSObject.Properties.Name -contains "AssignedTo") {
                        $assignedTo = Normalize-QOTicketsAssigneeFilterValue -Value ([string]$_.AssignedTo)
                    }
                } catch { $assignedTo = "Unassigned" }

                if ($assigneeFilter -eq "All") { return $true }
                return ($assignedTo -ieq $assigneeFilter)
            }
    )
}

function Get-QOTicketPrioritySortRank {
    param([AllowNull()]$Ticket)

    $priorityRaw = ""
    try {
        if ($Ticket -and $Ticket.PSObject.Properties.Name -contains "Priority") {
            $priorityRaw = [string]$Ticket.Priority
        }
    } catch { $priorityRaw = "" }

    switch (([string]($priorityRaw + "")).Trim().ToLowerInvariant()) {
        "critical" { return 4 }
        "high" { return 3 }
        "medium" { return 2 }
        "normal" { return 2 }
        "low" { return 1 }
        default { return 2 }
    }
}

function Get-QOTicketCreatedSortTicks {
    param([AllowNull()]$Ticket)

    $createdRaw = ""
    try {
        if ($Ticket -and $Ticket.PSObject.Properties.Name -contains "CreatedAt") {
            $createdRaw = [string]$Ticket.CreatedAt
        } elseif ($Ticket -and $Ticket.PSObject.Properties.Name -contains "Created") {
            $createdRaw = [string]$Ticket.Created
        }
    } catch { $createdRaw = "" }

    if ([string]::IsNullOrWhiteSpace($createdRaw)) { return 0L }

    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($createdRaw, [ref]$parsed)) {
        return [int64]$parsed.Ticks
    }

    return 0L
}

function New-QOTicketsObservableCollection {
    param([object[]]$Items)

    $collection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($item in @($Items)) {
        $collection.Add($item) | Out-Null
    }
    return (, $collection)
}

function Set-QOTicketsVisibleItemsSource {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()][object[]]$Items
    )

    $itemsArray = @($Items)
    $collection = $script:TicketsFilteredItems
    if (-not $collection -or $collection -isnot [System.Collections.ObjectModel.ObservableCollection[object]]) {
        $collection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        $script:TicketsFilteredItems = $collection
    }

    $needsReset = $true
    try {
        if ($collection.Count -eq $itemsArray.Count) {
            $needsReset = $false
            for ($i = 0; $i -lt $itemsArray.Count; $i++) {
                if (-not [object]::ReferenceEquals($collection[$i], $itemsArray[$i])) {
                    $needsReset = $true
                    break
                }
            }
        }
    } catch { $needsReset = $true }

    if ($needsReset) {
        # Use lock to prevent concurrent modification race condition
        [System.Threading.Monitor]::Enter($script:TicketsGridItemsSourceLock)
        try {
            try { $collection.Clear() } catch { }
            foreach ($item in $itemsArray) {
                try { $collection.Add($item) | Out-Null } catch { }
            }
        } finally {
            [System.Threading.Monitor]::Exit($script:TicketsGridItemsSourceLock)
        }
    }

    try {
        if (-not [object]::ReferenceEquals($Grid.ItemsSource, $collection)) {
            $Grid.ItemsSource = $collection
        }
    } catch { }

    return $collection
}

function Apply-TicketsFilter {
    if (-not $script:TicketsGrid) { return }

    if ($null -eq $script:AllTickets) {
        $script:AllTickets = @()
    }

    if (@($script:AllTickets).Count -eq 0 -and $script:TicketsGrid.ItemsSource) {
        try { $script:AllTickets = @($script:TicketsGrid.ItemsSource) } catch { }
    }
    
    $filterState = [pscustomobject]@{
        ShowOpen             = [bool]$script:ShowOpen
        ShowClosed           = [bool]$script:ShowClosed
        ShowDeleted          = [bool]$script:ShowDeleted
        SortMode             = [string]$script:TicketsSortMode
        AssigneeFilter       = [string]$script:TicketsAssigneeFilter
    }

    $filtered = @(Get-QOTicketsVisibleItems -Items $script:AllTickets -FilterState $filterState)
    if ($filtered.Count -gt 1) {
        switch (([string]($script:TicketsSortMode + "")).Trim().ToLowerInvariant()) {
            "newest" {
                $filtered = @(
                    $filtered |
                        Sort-Object -Property @{ Expression = { Get-QOTicketCreatedSortTicks -Ticket $_ }; Descending = $true }
                )
            }
            "oldest" {
                $filtered = @(
                    $filtered |
                        Sort-Object -Property @{ Expression = { Get-QOTicketCreatedSortTicks -Ticket $_ }; Descending = $false }
                )
            }
            default {
                $filtered = @(
                    $filtered |
                        Sort-Object -Property `
                            @{ Expression = { Get-QOTicketPrioritySortRank -Ticket $_ }; Descending = $true }, `
                            @{ Expression = { Get-QOTicketCreatedSortTicks -Ticket $_ }; Descending = $true }
                )
            }
        }
    }
    $previousSelectionId = ""
    $previousSelection = $null
    $detailsWasOpen = $false
    try {
        $previousSelection = $script:TicketsGrid.SelectedItem
        if (-not $previousSelection) { $previousSelection = $script:TicketsGrid.CurrentItem }
    } catch { $previousSelection = $null }
    try {
        if ($previousSelection -and $previousSelection.PSObject.Properties.Name -contains "Id") {
            $previousSelectionId = ([string]($previousSelection.Id + "")).Trim()
        }
    } catch { $previousSelectionId = "" }
    try {
        if ($script:TicketsDetailsPanel) {
            $detailsWasOpen = ($script:TicketsDetailsPanel.Visibility -eq "Visible")
        }
    } catch { $detailsWasOpen = $false }

    $newItemsSource = Set-QOTicketsVisibleItemsSource -Grid $script:TicketsGrid -Items $filtered

    $restoredSelection = $null
    if (-not [string]::IsNullOrWhiteSpace($previousSelectionId)) {
        foreach ($candidate in @($filtered)) {
            if (-not $candidate) { continue }
            $candidateId = ""
            try {
                if ($candidate.PSObject.Properties.Name -contains "Id") {
                    $candidateId = ([string]($candidate.Id + "")).Trim()
                }
            } catch { $candidateId = "" }
            if ($candidateId -eq $previousSelectionId) {
                $restoredSelection = $candidate
                break
            }
        }
    }

    if ($restoredSelection) {
        try {
            $script:TicketsGrid.SelectedItem = $restoredSelection
            $script:TicketsGrid.CurrentItem = $restoredSelection
            $script:TicketsGrid.ScrollIntoView($restoredSelection)
        } catch { }
    }

    if ($detailsWasOpen -and $restoredSelection -and (-not $script:TicketsDetailsForceClosed)) {
        try {
            Update-QOTicketDetailsView `
                -Ticket $restoredSelection `
                -DetailsPanel $script:TicketsDetailsPanel `
                -BodyText $script:TicketsBodyText `
                -ReplySubject $script:TicketsReplySubject `
                -ReplyText $script:TicketsReplyText `
                -ReplyButton $script:TicketsReplyButton `
                -Chevron $script:TicketsDetailsChevron
        } catch { }
    }
}

function Invoke-QOTicketsFilterSafely {
    param(
        [switch]$ForceRefresh,
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid
    )

    if (-not $script:TicketsGrid -and $Grid) {
        $script:TicketsGrid = $Grid
    }

    try {
        # Always invoke the function from this module scope.
        # Resolving via Get-Command can hit another imported module instance and no-op.
        Apply-TicketsFilter
        return $true
    }
    catch {
        Write-QOTicketsUILog ("Tickets: Apply-TicketsFilter failed; skipping filter. " + $_.Exception.Message) "WARN"
        if ($ForceRefresh -and $script:TicketsGrid) {
            try { $script:TicketsGrid.Items.Refresh() } catch { }
        }
        return $false
    }
}

function Refresh-QOTicketsAfterLocalMutation {
    param(
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()]$PreferredDetailsTicket,
        [switch]$PreferCurrentTicket,
        [switch]$PreferCachedPendingReplies
    )

    if (-not $Grid) { return }

    $refreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lightweightOnly = $false
    try { $lightweightOnly = [bool]($PreferCurrentTicket -and $PreferCachedPendingReplies) } catch { $lightweightOnly = $false }
    if ($lightweightOnly) {
        try { $Grid.Items.Refresh() } catch { }
    } else {
        try { $null = Invoke-QOTicketsFilterSafely -ForceRefresh -Grid $Grid } catch { }
    }

    $detailsTicket = $PreferredDetailsTicket
    if (-not $detailsTicket) {
        try { $detailsTicket = $Grid.SelectedItem } catch { $detailsTicket = $null }
    }
    if (-not $detailsTicket) {
        try { $detailsTicket = $Grid.CurrentItem } catch { $detailsTicket = $null }
    }

    try {
        if (-not $PreferCurrentTicket) {
            $latestDetailsTicket = Resolve-QOTTicketDetailsSourceTicket -Ticket $detailsTicket
            if ($detailsTicket -and $latestDetailsTicket -and -not [object]::ReferenceEquals($detailsTicket, $latestDetailsTicket)) {
                $null = Update-QOTicketObjectFromSource -Target $detailsTicket -Source $latestDetailsTicket
            } elseif ($latestDetailsTicket) {
                $detailsTicket = $latestDetailsTicket
            }
        }
        try { $detailsTicket = Sync-QOTTicketLivePendingReplies -Ticket $detailsTicket -PreferCached:$PreferCachedPendingReplies } catch { }
    } catch { }

    if ($script:TicketsDetailsPanel -and $detailsTicket) {
        $shouldUpdateDetails = $false
        try {
            $isDetailsVisible = ($script:TicketsDetailsPanel.Visibility -eq "Visible")
            if ($isDetailsVisible) {
                $shouldUpdateDetails = $true
            }
        } catch { $shouldUpdateDetails = $false }

        if ($shouldUpdateDetails) {
            try {
                Update-QOTicketDetailsView -Ticket $detailsTicket -DetailsPanel $script:TicketsDetailsPanel -BodyText $script:TicketsBodyText -ReplySubject $script:TicketsReplySubject -ReplyText $script:TicketsReplyText -ReplyButton $script:TicketsReplyButton -Chevron $script:TicketsDetailsChevron -PreferCurrentTicket:$PreferCurrentTicket -PreferCachedPendingReplies:$PreferCachedPendingReplies
            } catch { }
        }
    }

    # Avoid immediate self-triggered file auto-refresh after local write.
    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$script:TicketsStorePath) -and (Test-Path -LiteralPath $script:TicketsStorePath)) {
            $latestWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($script:TicketsStorePath)
            $script:TicketsStoreLastWriteUtc = $latestWriteUtc
            $script:TicketsLoadedStoreWriteUtc = $latestWriteUtc
        }
    } catch { }
    try { Write-QOTicketsUILog ("Tickets: Ticket refresh duration {0} ms." -f [int]$refreshStopwatch.Elapsed.TotalMilliseconds) } catch { }
}

function Refresh-QOTicketsGrid {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string]$View
    )

    $gridRefreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Write-QOTicketsUILog "Tickets: Grid refresh started."
        $loadedTickets = @(Get-QOTicketsAllItems)
        $script:AllTickets = $loadedTickets
        Update-QOTicketDisplayFields -Tickets $script:AllTickets
        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$script:TicketsStorePath) -and (Test-Path -LiteralPath $script:TicketsStorePath)) {
                $script:TicketsLoadedStoreWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($script:TicketsStorePath)
            }
        } catch { }
        Invoke-QOTicketsFilterSafely -ForceRefresh -Grid $Grid
        $sourceType = "<null>"
        $itemsSource = $null
        try {
            $itemsSource = $Grid.ItemsSource
            if ($null -ne $itemsSource) {
                $sourceType = $itemsSource.GetType().FullName
            }
        } catch { }

        $itemSourceCount = 0
        try {
            if ($null -ne $itemsSource) {
                $itemSourceCount = @($itemsSource | ForEach-Object { $_ }).Count
            }
        } catch { }

        $gridCount = 0
        try { $gridCount = $Grid.Items.Count } catch { }

        Write-QOTicketsUILog ("Tickets: ItemsSource set. Type={0}; Items={1}; GridCount={2}" -f $sourceType, $itemSourceCount, $gridCount)
        Write-QOTicketsUILog ("Tickets: Grid refresh completed. DurationMs={0}" -f [int]$gridRefreshStopwatch.Elapsed.TotalMilliseconds)
    }
    catch {
        $msg = $_.Exception.Message
        $stack = $_.Exception.StackTrace
        $inner = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { "" }

        Write-QOTicketsUILog ("Tickets: Grid refresh failed. Error: " + $msg) "ERROR"
        if ($inner) { Write-QOTicketsUILog ("Tickets: InnerException: " + $inner) "ERROR" }
        if ($stack) { Write-QOTicketsUILog ("Tickets: StackTrace: " + $stack) "ERROR" }

        $popupMessage = "Load tickets failed.`n`nError: " + $msg
        if ($inner) { $popupMessage += "`nInner: " + $inner }
        [System.Windows.MessageBox]::Show(
            $popupMessage,
            "Quinn Optimiser Toolkit",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
}

function Set-QOTicketDetailsVisibility {
    param(
        [AllowNull()][System.Windows.UIElement]$DetailsPanel,
        [AllowNull()][System.Windows.Controls.TextBlock]$Chevron,
        [AllowNull()][System.Windows.Controls.DataGrid]$TicketsGrid,
        [bool]$IsOpen
    )

    if ($IsOpen) {
        try { $script:TicketsDetailsViewClosing = $false } catch { }
    } else {
        try { Write-QOTicketsUILog ("Tickets: Detail view unloading. ActiveTicketId='{0}'." -f ([string]($script:TicketsActiveTicketId + "")).Trim()) } catch { }
        try { $script:TicketsDetailsViewClosing = $true } catch { }
        try { $script:TicketsDetailsViewGeneration = [int]$script:TicketsDetailsViewGeneration + 1 } catch { $script:TicketsDetailsViewGeneration = 1 }
        try { Stop-QOTicketQueuedDetailsRefresh -Reason "detail-close" } catch { }
        try { $script:TicketsActiveTicketId = "" } catch { }
        try { Write-QOTicketsUILog "Tickets: Selected ticket cleared for detail lifecycle." } catch { }
    }

    if ($DetailsPanel) {
        $DetailsPanel.Visibility = if ($IsOpen) { "Visible" } else { "Collapsed" }
    }
    if ($Chevron) {
        # Keep this button as a dedicated "Back to list" affordance.
        $Chevron.Text = ([char]0xE72B)
    }

    $effectiveGrid = $null
    try {
        if ($TicketsGrid) {
            $effectiveGrid = $TicketsGrid
        } elseif ($script:TicketsGrid) {
            $effectiveGrid = $script:TicketsGrid
        }
    } catch { $effectiveGrid = $null }

    if ($effectiveGrid) {
        try {
            $effectiveGrid.Visibility = if ($IsOpen) { "Collapsed" } else { "Visible" }
            $effectiveGrid.IsHitTestVisible = (-not $IsOpen)
        } catch { }
    }
}

function Find-QOTicketsScrollViewer {
    param(
        [AllowNull()][System.Windows.DependencyObject]$Root,
        # Depth limit prevents stack overflow on pathologically deep visual
        # trees or (theoretically) a tree containing a cycle. 64 is well past
        # any real-world WPF visual tree depth.
        [int]$Depth = 0,
        [int]$MaxDepth = 64
    )

    if (-not $Root) { return $null }
    if ($Depth -ge $MaxDepth) {
        try { Write-QOTicketsUILog ("Find-QOTicketsScrollViewer aborted at depth {0} (limit {1}). Possible cycle or extremely deep visual tree." -f $Depth, $MaxDepth) "WARN" } catch { }
        return $null
    }
    if ($Root -is [System.Windows.Controls.ScrollViewer]) { return $Root }

    $childCount = 0
    try { $childCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root) } catch { $childCount = 0 }
    for ($index = 0; $index -lt $childCount; $index++) {
        $child = $null
        try { $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Root, $index) } catch { $child = $null }
        if (-not $child) { continue }

        $resolved = $null
        try { $resolved = Find-QOTicketsScrollViewer -Root $child -Depth ($Depth + 1) -MaxDepth $MaxDepth } catch { $resolved = $null }
        if ($resolved) { return $resolved }
    }

    return $null
}

function Get-QOTicketsGridScrollViewer {
    param([AllowNull()][System.Windows.Controls.DataGrid]$Grid)

    if (-not $Grid) { return $null }

    try { $Grid.ApplyTemplate() } catch { }
    try { $Grid.UpdateLayout() } catch { }

    try { return (Find-QOTicketsScrollViewer -Root $Grid) } catch { }
    return $null
}

function Find-QOTicketsAncestorOfType {
    param(
        [AllowNull()]$Element,
        [Parameter(Mandatory)][Type]$Type
    )

    $current = $Element
    while ($current) {
        if ($Type.IsInstanceOfType($current)) { return $current }
        try {
            if ($current -is [System.Windows.Media.Visual] -or $current -is [System.Windows.Media.Media3D.Visual3D]) {
                $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
            } elseif ($current -is [System.Windows.FrameworkContentElement]) {
                $current = $current.Parent
                if (-not $current) { $current = [System.Windows.LogicalTreeHelper]::GetParent($current) }
            } else {
                $current = [System.Windows.LogicalTreeHelper]::GetParent($current)
            }
        } catch {
            $current = $null
        }
    }

    return $null
}

function Test-QOTicketsScrollChromeElement {
    param([AllowNull()]$Element)

    if (-not $Element) { return $false }
    try {
        if ($Element -is [System.Windows.Controls.Primitives.ScrollBar]) { return $true }
        if ($Element -is [System.Windows.Controls.Primitives.RepeatButton]) { return $true }
        if ($Element -is [System.Windows.Controls.Primitives.Thumb]) { return $true }
        if ($Element -is [System.Windows.Controls.Primitives.Track]) { return $true }
    } catch { }

    foreach ($chromeType in @(
        [System.Windows.Controls.Primitives.ScrollBar],
        [System.Windows.Controls.Primitives.RepeatButton],
        [System.Windows.Controls.Primitives.Thumb],
        [System.Windows.Controls.Primitives.Track]
    )) {
        try {
            $chromeParent = Find-QOTicketsAncestorOfType -Element $Element -Type $chromeType
            if ($chromeParent) { return $true }
        } catch { }
    }

    return $false
}

function Test-QOTicketsScrollBarGutterPoint {
    param(
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()][System.Windows.Point]$Point
    )

    if (-not $Grid) { return $false }

    $pointValue = $Point
    if ($null -eq $pointValue) { return $false }

    $gridWidth = 0.0
    $gridHeight = 0.0
    try { $gridWidth = [double]$Grid.ActualWidth } catch { $gridWidth = 0.0 }
    try { $gridHeight = [double]$Grid.ActualHeight } catch { $gridHeight = 0.0 }
    if ($gridWidth -le 0 -or $gridHeight -le 0) { return $false }

    $x = 0.0
    $y = 0.0
    try { $x = [double]$pointValue.X } catch { $x = 0.0 }
    try { $y = [double]$pointValue.Y } catch { $y = 0.0 }
    if ($x -lt 0 -or $y -lt 0 -or $x -gt $gridWidth -or $y -gt $gridHeight) { return $false }

    $scrollViewer = $null
    try { $scrollViewer = Get-QOTicketsGridScrollViewer -Grid $Grid } catch { $scrollViewer = $null }

    $hasVisibleVerticalBar = $false
    if ($scrollViewer) {
        try { $hasVisibleVerticalBar = ($scrollViewer.ComputedVerticalScrollBarVisibility -eq [System.Windows.Visibility]::Visible) } catch { $hasVisibleVerticalBar = $false }
    }
    if (-not $hasVisibleVerticalBar) { return $false }

    $gutterWidth = 22.0
    try {
        $gutterWidth = [math]::Max(
            22.0,
            [double][System.Windows.SystemParameters]::VerticalScrollBarWidth + 8.0
        )
    } catch { $gutterWidth = 22.0 }

    return ($x -ge ($gridWidth - $gutterWidth))
}

function Test-QOTicketsRenderableListItem {
    param([AllowNull()]$Ticket)

    if (-not $Ticket) { return $false }
    if ($Ticket -is [System.Windows.Data.CollectionViewGroup]) { return $false }

    try {
        $typeName = [string]$Ticket.GetType().FullName
        if ($typeName -match 'MS\.Internal\.NamedObject|NewItemPlaceholder') { return $false }
    } catch { }

    $propertyNames = @()
    try { $propertyNames = @($Ticket.PSObject.Properties.Name) } catch { $propertyNames = @() }
    if ($propertyNames.Count -eq 0) { return $false }

    foreach ($identityProperty in @("Id", "EmailMessageId", "OutlookEntryId", "Subject", "Title", "TicketName", "CreatedAt", "EmailReceived", "EmailFrom", "SenderEmail")) {
        if ($propertyNames -notcontains $identityProperty) { continue }
        try {
            $value = ([string]($Ticket.$identityProperty + "")).Trim()
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $true }
        } catch { }
    }

    return $false
}

function Resolve-QOTicketFromGridHit {
    param(
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()]$Hit,
        [switch]$RequireRowHit
    )

    if (-not $Grid -or -not $Hit) { return $null }
    if (Test-QOTicketsScrollChromeElement -Element $Hit) { return $null }

    $row = $null
    try { $row = [System.Windows.Controls.ItemsControl]::ContainerFromElement($Grid, $Hit) } catch { $row = $null }
    if ($row -and $row -isnot [System.Windows.Controls.DataGridRow]) {
        try { $row = Find-QOTicketsAncestorOfType -Element $row -Type ([System.Windows.Controls.DataGridRow]) } catch { $row = $null }
    }
    if (-not $row) {
        try { $row = Find-QOTicketsAncestorOfType -Element $Hit -Type ([System.Windows.Controls.DataGridRow]) } catch { $row = $null }
    }
    if ($row -and $row.Item -and (Test-QOTicketsRenderableListItem -Ticket $row.Item)) { return $row.Item }

    if ($RequireRowHit) { return $null }

    if ($Hit -is [System.Windows.FrameworkElement]) {
        try {
            $dc = $Hit.DataContext
            if ($dc -and (Test-QOTicketsRenderableListItem -Ticket $dc)) {
                return $dc
            }
        } catch { }
    }

    return $null
}

function Save-QOTicketsListViewState {
    param(
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()]$AnchorTicket
    )

    if (-not $Grid) { return $null }

    $selectedTicket = $AnchorTicket
    if (-not $selectedTicket) {
        try { $selectedTicket = $Grid.SelectedItem } catch { $selectedTicket = $null }
    }
    if (-not $selectedTicket) {
        try { $selectedTicket = $Grid.CurrentItem } catch { $selectedTicket = $null }
    }

    $selectionKey = ""
    try { $selectionKey = [string](Get-QOTicketSelectionKey -Ticket $selectedTicket) } catch { $selectionKey = "" }

    $verticalOffset = 0.0
    $hasVerticalOffset = $false
    $scrollViewer = $null
    try { $scrollViewer = Get-QOTicketsGridScrollViewer -Grid $Grid } catch { $scrollViewer = $null }
    if ($scrollViewer) {
        try {
            $verticalOffset = [double]$scrollViewer.VerticalOffset
            $hasVerticalOffset = $true
        } catch {
            $verticalOffset = 0.0
            $hasVerticalOffset = $false
        }
    }

    return [pscustomobject]@{
        SelectionKey      = $selectionKey
        VerticalOffset    = $verticalOffset
        HasVerticalOffset = $hasVerticalOffset
    }
}

function Restore-QOTicketsListViewState {
    param(
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()]$State
    )

    if (-not $Grid -or -not $State) { return $false }

    $restoreAction = [action]{
        $selectionKey = ""
        try { $selectionKey = [string]($State.SelectionKey + "") } catch { $selectionKey = "" }

        $restoredTicket = $null
        if (-not [string]::IsNullOrWhiteSpace($selectionKey)) {
            $candidateItems = @()
            try {
                if ($Grid.ItemsSource) {
                    $candidateItems = @($Grid.ItemsSource)
                } else {
                    $candidateItems = @($Grid.Items)
                }
            } catch { $candidateItems = @() }

            foreach ($candidate in @($candidateItems)) {
                if (-not $candidate) { continue }
                $candidateKey = ""
                try { $candidateKey = [string](Get-QOTicketSelectionKey -Ticket $candidate) } catch { $candidateKey = "" }
                if ($candidateKey -eq $selectionKey) {
                    $restoredTicket = $candidate
                    break
                }
            }
        }

        try { $Grid.UpdateLayout() | Out-Null } catch { }

        if ($restoredTicket) {
            try { $Grid.SelectedItem = $restoredTicket } catch { }
            try { $Grid.CurrentItem = $restoredTicket } catch { }
            try { $Grid.ScrollIntoView($restoredTicket) } catch { }
        }

        $hasVerticalOffset = $false
        try { $hasVerticalOffset = [bool]$State.HasVerticalOffset } catch { $hasVerticalOffset = $false }
        if ($hasVerticalOffset) {
            $scrollViewer = $null
            try { $scrollViewer = Get-QOTicketsGridScrollViewer -Grid $Grid } catch { $scrollViewer = $null }
            if ($scrollViewer) {
                $targetOffset = 0.0
                try { $targetOffset = [double]$State.VerticalOffset } catch { $targetOffset = 0.0 }
                try {
                    $maxOffset = [double]$scrollViewer.ScrollableHeight
                    $targetOffset = [math]::Max(0.0, [math]::Min($targetOffset, $maxOffset))
                } catch { }
                try { $scrollViewer.ScrollToVerticalOffset($targetOffset) } catch { }
            }
        }

        try { $Grid.UpdateLayout() | Out-Null } catch { }
    }.GetNewClosure()

    try { & $restoreAction } catch { return $false }

    try {
        if ($Grid.Dispatcher) {
            $null = $Grid.Dispatcher.BeginInvoke($restoreAction, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    } catch { }

    return $true
}

function Convert-QOTDisplayDateText {
    param([AllowNull()]$Value)

    $raw = ""
    try { $raw = ([string]($Value + "")).Trim() } catch { $raw = "" }
    if ([string]::IsNullOrWhiteSpace($raw)) { return "" }

    $parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [System.Globalization.DateTimeStyles]::AssumeLocal
    $invariantFormats = @(
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-ddTHH:mm:ss",
        "yyyy-MM-ddTHH:mm:ssK",
        "yyyy-MM-ddTHH:mm:ss.fffK",
        "o"
    )

    if ([datetime]::TryParseExact($raw, $invariantFormats, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        $culture = [System.Globalization.CultureInfo]::CurrentCulture
        $format = "{0} {1}" -f $culture.DateTimeFormat.ShortDatePattern, $culture.DateTimeFormat.ShortTimePattern
        return $parsed.ToString($format, $culture)
    }
    if ([datetime]::TryParse($raw, [System.Globalization.CultureInfo]::CurrentCulture, $styles, [ref]$parsed)) {
        $culture = [System.Globalization.CultureInfo]::CurrentCulture
        $format = "{0} {1}" -f $culture.DateTimeFormat.ShortDatePattern, $culture.DateTimeFormat.ShortTimePattern
        return $parsed.ToString($format, $culture)
    }

    return $raw
}

function Update-QOTicketDisplayFields {
    param([AllowNull()][object[]]$Tickets)

    foreach ($ticket in @($Tickets)) {
        if ($null -eq $ticket) { continue }

        $createdRaw = ""
        try {
            if ($ticket.PSObject.Properties.Name -contains "CreatedAt") {
                $createdRaw = [string]$ticket.CreatedAt
            } elseif ($ticket.PSObject.Properties.Name -contains "Created") {
                $createdRaw = [string]$ticket.Created
            }
        } catch { $createdRaw = "" }

        $createdDisplay = Convert-QOTDisplayDateText -Value $createdRaw
        if ($ticket.PSObject.Properties.Name -contains "CreatedAtDisplay") {
            try { $ticket.CreatedAtDisplay = $createdDisplay } catch { }
        } else {
            try { $ticket | Add-Member -NotePropertyName CreatedAtDisplay -NotePropertyValue $createdDisplay -Force } catch { }
        }
    }
}

function Get-QOTicketDetailsBodyText {
    param(
        [AllowNull()]$Ticket,
        [switch]$AsModel,
        [switch]$PreferCurrentTicket,
        [switch]$PreferCachedPendingReplies
    )

    if (-not $Ticket) {
        return "Double-click a ticket to view email body and reply."
    }

    if (-not $PreferCurrentTicket) {
        try {
            $resolveDetailsTicketCmd = Resolve-QOTicketsLocalFunction -Name "Resolve-QOTTicketDetailsSourceTicket"
            if ($resolveDetailsTicketCmd) {
                $resolvedTicket = & $resolveDetailsTicketCmd -Ticket $Ticket
                if ($resolvedTicket) { $Ticket = $resolvedTicket }
            } else {
                $Ticket = Resolve-QOTTicketDetailsSourceTicket -Ticket $Ticket
            }
        } catch {
            try { Write-QOTicketsUILog ("Tickets: Details source resolution fallback failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }

    $ticketId = ""
    try {
        if ($Ticket.PSObject.Properties.Name -contains "Id") {
            $ticketId = ([string]($Ticket.Id + "")).Trim()
        }
    } catch { $ticketId = "" }

    $allTicketsCache = @()
    if ((-not $PreferCurrentTicket) -and -not [string]::IsNullOrWhiteSpace($ticketId)) {
        try {
            if ($script:AllTickets) {
                $allTicketsCache = @($script:AllTickets)
            }
        } catch { $allTicketsCache = @() }

        if (@($allTicketsCache).Count -eq 0) {
            try {
                $getTicketsCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTickets"
                if ($getTicketsCmd) {
                    $dbLatest = & $getTicketsCmd -Quiet
                    if ($dbLatest -and ($dbLatest.PSObject.Properties.Name -contains "Tickets")) {
                        $allTicketsCache = @($dbLatest.Tickets)
                    }
                }
            } catch { $allTicketsCache = @() }
        }

        if (@($allTicketsCache).Count -gt 0) {
            try {
                $latestTicket = $null
                $resolveDetailsTicketCmd = Resolve-QOTicketsLocalFunction -Name "Resolve-QOTTicketDetailsSourceTicket"
                if ($resolveDetailsTicketCmd) {
                    $latestTicket = & $resolveDetailsTicketCmd -Ticket $Ticket
                } else {
                    $latestTicket = Resolve-QOTTicketDetailsSourceTicket -Ticket $Ticket
                }
                if ($latestTicket) { $Ticket = $latestTicket }
            } catch { }
        }
    }
    try { $Ticket = Sync-QOTTicketLivePendingReplies -Ticket $Ticket -TicketId $ticketId -PreferCached:$PreferCachedPendingReplies } catch { }
    try { $Ticket = Sync-QOTTicketCanonicalActivityAliases -Ticket $Ticket } catch { }

    $getDate = {
        param([AllowNull()]$Value)
        $raw = ""
        try { $raw = ([string]($Value + "")).Trim() } catch { $raw = "" }
        if ([string]::IsNullOrWhiteSpace($raw)) { return [datetime]::MinValue }
        $dt = [datetime]::MinValue
        if ([datetime]::TryParse($raw, [ref]$dt)) { return $dt }
        return [datetime]::MinValue
    }.GetNewClosure()

    $buildThreadKey = {
        param([AllowNull()][string]$Subject)
        $value = ([string]($Subject + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) { return "" }
        $value = ($value -replace '[\r\n]+', ' ').Trim()
        for ($i = 0; $i -lt 6; $i++) {
            $next = ($value -replace '^(?i)\s*((RE|FW|FWD)\s*:\s*)+', '').Trim()
            if ($next -eq $value) { break }
            $value = $next
        }
        return (($value -replace '\s+', ' ').Trim().ToLowerInvariant())
    }.GetNewClosure()

    $resolveBodyPathCmd = $null
    try { $resolveBodyPathCmd = Resolve-QOTicketsLocalFunction -Name "Resolve-QOTicketBodyPath" } catch { $resolveBodyPathCmd = $null }

    $getBodyForTicket = {
        param([AllowNull()]$InputTicket)

        if (-not $InputTicket) { return "" }
        try {
            $bodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $InputTicket
            return ([string]($bodyInfo.Text + "")).Trim()
        } catch {
            return ""
        }
    }.GetNewClosure()

    $events = New-Object System.Collections.Generic.List[object]
    $eventKeys = New-Object System.Collections.Generic.HashSet[string]
    $canonicalEventKeys = New-Object System.Collections.Generic.HashSet[string]
    $addEvent = {
        param(
            [AllowNull()][datetime]$When,
            [AllowNull()][string]$Kind,
            [AllowNull()][string]$Title,
            [AllowNull()][string]$Body,
            [int]$SortOrder = 100,
            [AllowNull()][hashtable]$Metadata
        )
        $bodyText = ([string]($Body + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($bodyText)) { return }
        $maxBodyChars = 12000
        if ($bodyText.Length -gt $maxBodyChars) {
            $bodyText = $bodyText.Substring(0, $maxBodyChars) + "`r`n`r`n[Entry truncated.]"
        }
        $dt = $When
        if (-not $dt -or $dt -eq [datetime]::MinValue) { $dt = [datetime]::MinValue }
        $kindValue = ([string]($Kind + "")).Trim()
        $titleValue = ([string]($Title + "")).Trim()
        $kindForKey = $kindValue.ToLowerInvariant()
        $titleForKey = $titleValue.ToLowerInvariant()
        $familyForKey = $kindForKey
        if ($kindForKey -match 'note|internalnote' -or $titleForKey -match '^internal note') {
            $familyForKey = "note"
        } elseif ($kindForKey -match 'replyqueued|replypending|replysending|replyfailed') {
            $familyForKey = "pendingreply"
        } elseif ($kindForKey -match 'reply|technicianreply') {
            $familyForKey = "reply"
        }
        $stableItemId = ""
        if ($Metadata) {
            foreach ($identityKey in @("ItemId", "TimelineItemId", "PendingReplyDraftId", "DraftId", "ReplyId", "NoteId", "MessageId", "SourceMessageId", "Id")) {
                try {
                    if ($Metadata.ContainsKey($identityKey)) {
                        $identityValue = ([string]($Metadata[$identityKey] + "")).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($identityValue)) {
                            $stableItemId = ($identityKey.ToLowerInvariant() + ":" + $identityValue)
                            break
                        }
                    }
                } catch { }
            }
        }
        $canonicalDate = ""
        if ($dt -and $dt -ne [datetime]::MinValue) { $canonicalDate = $dt.ToString("o") }
        $canonicalBody = (($bodyText -replace '\s+', ' ').Trim()).ToLowerInvariant()
        if ($canonicalBody.Length -gt 600) { $canonicalBody = $canonicalBody.Substring(0, 600) }
        $canonicalKeySeed = $(if (-not [string]::IsNullOrWhiteSpace($stableItemId)) { ($familyForKey + "|" + $stableItemId) } else { ($familyForKey + "|" + $canonicalDate + "|" + $canonicalBody) })
        if (-not [string]::IsNullOrWhiteSpace($canonicalBody) -and -not $canonicalEventKeys.Add($canonicalKeySeed)) { return }
        $keySeed = $(if (-not [string]::IsNullOrWhiteSpace($stableItemId)) { $stableItemId } else { (([string]($Kind + "")).Trim() + "|" + ([string]($Title + "")).Trim() + "|" + $(if ($dt -and $dt -ne [datetime]::MinValue) { $dt.ToString("o") } else { "" }) + "|" + $bodyText.Substring(0, [Math]::Min(240, $bodyText.Length))) })
        if (-not $eventKeys.Add($keySeed)) { return }
        $eventObject = [pscustomobject]@{
            When      = $dt
            SortOrder = $SortOrder
            Kind      = $kindValue
            Title     = $titleValue
            Body      = $bodyText
            ItemId    = $stableItemId
        }
        if ($Metadata) {
            foreach ($key in @($Metadata.Keys)) {
                $propertyName = ([string]($key + "")).Trim()
                if ([string]::IsNullOrWhiteSpace($propertyName)) { continue }
                try { $eventObject | Add-Member -NotePropertyName $propertyName -NotePropertyValue $Metadata[$key] -Force } catch { }
            }
        }
        $events.Add($eventObject) | Out-Null
    }.GetNewClosure()

    $subjectSummary = ""
    $fromSummary = ""
    $statusSummary = ""
    $prioritySummary = ""
    $assignedSummary = ""
    $createdSummary = ""
    try { if ($Ticket.PSObject.Properties.Name -contains "Subject") { $subjectSummary = ([string]($Ticket.Subject + "")).Trim() } } catch { }
    try { if ($Ticket.PSObject.Properties.Name -contains "EmailFrom") { $fromSummary = ([string]($Ticket.EmailFrom + "")).Trim() } } catch { }
    try { if ($Ticket.PSObject.Properties.Name -contains "Status") { $statusSummary = [string]$Ticket.Status } } catch { }
    try { if ($Ticket.PSObject.Properties.Name -contains "Priority") { $prioritySummary = [string]$Ticket.Priority } } catch { }
    try { if ($Ticket.PSObject.Properties.Name -contains "AssignedTo") { $assignedSummary = [string]$Ticket.AssignedTo } } catch { }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "CreatedAt") {
            $createdSummary = Convert-QOTDisplayDateText -Value ([string]$Ticket.CreatedAt)
        }
    } catch { }

    $primaryBody = & $getBodyForTicket $Ticket
    if ([string]::IsNullOrWhiteSpace($primaryBody)) {
        try {
            $previewBodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $Ticket -PreviewOnly
            if ($previewBodyInfo -and -not [string]::IsNullOrWhiteSpace([string]$previewBodyInfo.Text)) {
                $primaryBody = [string]$previewBodyInfo.Text
            }
        } catch { }
    }
    $mainDate = [datetime]::MinValue
    try { if ($Ticket.PSObject.Properties.Name -contains "CreatedAt") { $mainDate = & $getDate $Ticket.CreatedAt } } catch { $mainDate = [datetime]::MinValue }
    $mainTitle = "Main email"
    if (-not [string]::IsNullOrWhiteSpace($fromSummary)) {
        $mainTitle = ("Main email from " + $fromSummary)
    }
    & $addEvent -When $mainDate -Kind "Email" -Title $mainTitle -Body $primaryBody -SortOrder 10

    $incomingMessages = @()
    try { if ($Ticket.PSObject.Properties.Name -contains "IncomingMessages") { $incomingMessages = @($Ticket.IncomingMessages) } } catch { $incomingMessages = @() }
    foreach ($incoming in $incomingMessages) {
        if (-not $incoming) { continue }
        $incomingBody = ""
        $incomingCreated = [datetime]::MinValue
        $incomingSubject = ""
        $incomingFrom = ""
        try { $incomingBody = & $getBodyForTicket $incoming } catch { $incomingBody = "" }
        if ([string]::IsNullOrWhiteSpace($incomingBody)) {
            try { if ($incoming.PSObject.Properties.Name -contains "Body") { $incomingBody = [string]$incoming.Body } else { $incomingBody = [string]$incoming } } catch { $incomingBody = "" }
        }
        try { if ($incoming.PSObject.Properties.Name -contains "CreatedAt") { $incomingCreated = & $getDate $incoming.CreatedAt } } catch { $incomingCreated = [datetime]::MinValue }
        try { if ($incoming.PSObject.Properties.Name -contains "Subject") { $incomingSubject = ([string]($incoming.Subject + "")).Trim() } } catch { $incomingSubject = "" }
        try {
            if ($incoming.PSObject.Properties.Name -contains "From") {
                $incomingFrom = ([string]($incoming.From + "")).Trim()
            } elseif ($incoming.PSObject.Properties.Name -contains "SenderEmail") {
                $incomingFrom = ([string]($incoming.SenderEmail + "")).Trim()
            }
        } catch { $incomingFrom = "" }

        $incomingTitle = "Customer reply"
        if (-not [string]::IsNullOrWhiteSpace($incomingFrom)) {
            $incomingTitle = ("Customer reply from " + $incomingFrom)
        }
        if (-not [string]::IsNullOrWhiteSpace($incomingSubject)) {
            $incomingTitle = ($incomingTitle + " - " + $incomingSubject)
        }
        & $addEvent -When $incomingCreated -Kind "Incoming" -Title $incomingTitle -Body $incomingBody -SortOrder 20
    }

    $notes = @()
    try { if ($Ticket.PSObject.Properties.Name -contains "Notes") { $notes = @($Ticket.Notes) } } catch { $notes = @() }
    foreach ($n in $notes) {
        if (-not $n) { continue }
        $noteBody = ""
        $noteCreated = [datetime]::MinValue
        $noteAuthor = "Voly"
        try { $noteBody = & $getBodyForTicket $n } catch { $noteBody = "" }
        if ([string]::IsNullOrWhiteSpace($noteBody)) {
            try { if ($n.PSObject.Properties.Name -contains "Body") { $noteBody = [string]$n.Body } else { $noteBody = [string]$n } } catch { $noteBody = "" }
        }
        try { if ($n.PSObject.Properties.Name -contains "CreatedAt") { $noteCreated = & $getDate $n.CreatedAt } } catch { $noteCreated = [datetime]::MinValue }
        try { if ($n.PSObject.Properties.Name -contains "Author") { $noteAuthor = ([string]($n.Author + "")).Trim() } } catch { $noteAuthor = "Voly" }
        if ([string]::IsNullOrWhiteSpace($noteAuthor)) { $noteAuthor = "Voly" }
        $noteId = ""
        try {
            foreach ($noteIdProp in @("NoteId", "Id")) {
                if ([string]::IsNullOrWhiteSpace($noteId) -and $n.PSObject.Properties.Name -contains $noteIdProp) {
                    $noteId = ([string]($n.$noteIdProp + "")).Trim()
                }
            }
        } catch { $noteId = "" }
        & $addEvent -When $noteCreated -Kind "Note" -Title ("Internal note (" + $noteAuthor + ")") -Body $noteBody -SortOrder 30 -Metadata @{
            ItemId = $(if (-not [string]::IsNullOrWhiteSpace($noteId)) { "note:" + $noteId } else { "" })
            NoteId = $noteId
            ClientNoteId = $noteId
            TicketId = $ticketId
        }
    }

    $genericActivityCollections = @(
        @{ Name = "Messages";      DefaultKind = "Message";      DefaultTitle = "Conversation message"; SortOrder = 25 },
        @{ Name = "History";       DefaultKind = "History";      DefaultTitle = "Ticket history";       SortOrder = 35 },
        @{ Name = "Conversation";  DefaultKind = "Conversation"; DefaultTitle = "Conversation item";    SortOrder = 25 },
        @{ Name = "SystemEvents";  DefaultKind = "SystemEvent";  DefaultTitle = "System event";         SortOrder = 50 },
        @{ Name = "Events";        DefaultKind = "SystemEvent";  DefaultTitle = "System event";         SortOrder = 50 },
        @{ Name = "Timeline";      DefaultKind = "Timeline";     DefaultTitle = "Timeline event";       SortOrder = 35 },
        @{ Name = "Activity";      DefaultKind = "Activity";     DefaultTitle = "Activity event";       SortOrder = 35 },
        @{ Name = "AuditTrail";    DefaultKind = "SystemEvent";  DefaultTitle = "Audit event";          SortOrder = 50 }
    )
    foreach ($collectionDefinition in $genericActivityCollections) {
        $collectionName = [string]$collectionDefinition.Name
        $collectionItems = @()
        try {
            if ($Ticket.PSObject.Properties.Name -contains $collectionName) {
                $collectionItems = @($Ticket.$collectionName)
            }
        } catch { $collectionItems = @() }

        foreach ($item in $collectionItems) {
            if (-not $item) { continue }

            $itemBody = ""
            $itemCreated = [datetime]::MinValue
            $itemTitle = ""
            $itemKind = [string]$collectionDefinition.DefaultKind

            try { $itemBody = & $getBodyForTicket $item } catch { $itemBody = "" }
            if ([string]::IsNullOrWhiteSpace($itemBody)) {
                foreach ($fallbackProp in @("Body", "Text", "Message", "Content", "Preview", "Summary", "EmailBody", "HtmlBody", "TextBody")) {
                    try {
                        if ([string]::IsNullOrWhiteSpace($itemBody) -and $item.PSObject.Properties.Name -contains $fallbackProp) {
                            $itemBody = ([string]($item.$fallbackProp + "")).Trim()
                        }
                    } catch { }
                }
            }
            if ([string]::IsNullOrWhiteSpace($itemBody) -and ($item -is [string])) {
                $itemBody = ([string]$item).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($itemBody)) { continue }

            foreach ($dateProp in @("CreatedAt", "SentAt", "ReceivedAt", "UpdatedAt", "When", "Timestamp", "Date")) {
                try {
                    if (($itemCreated -eq [datetime]::MinValue) -and $item.PSObject.Properties.Name -contains $dateProp) {
                        $itemCreated = & $getDate $item.$dateProp
                    }
                } catch { }
            }
            foreach ($titleProp in @("Title", "Subject", "Label", "Type")) {
                try {
                    if ([string]::IsNullOrWhiteSpace($itemTitle) -and $item.PSObject.Properties.Name -contains $titleProp) {
                        $itemTitle = ([string]($item.$titleProp + "")).Trim()
                    }
                } catch { }
            }
            foreach ($kindProp in @("Kind", "Direction", "EntryType", "MessageType")) {
                try {
                    if ($item.PSObject.Properties.Name -contains $kindProp) {
                        $kindValue = ([string]($item.$kindProp + "")).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($kindValue)) {
                            $itemKind = $kindValue
                            break
                        }
                    }
                } catch { }
            }
            if ([string]::IsNullOrWhiteSpace($itemTitle)) {
                $itemTitle = [string]$collectionDefinition.DefaultTitle
            }
            $itemId = ""
            try {
                foreach ($itemIdProp in @("TimelineItemId", "ItemId", "NoteId", "ReplyId", "DraftId", "MessageId", "SourceMessageId", "Id")) {
                    if ([string]::IsNullOrWhiteSpace($itemId) -and $item.PSObject.Properties.Name -contains $itemIdProp) {
                        $itemId = ([string]($item.$itemIdProp + "")).Trim()
                    }
                }
            } catch { $itemId = "" }
            if ([string]::Equals($itemKind, "InternalNote", [System.StringComparison]::OrdinalIgnoreCase)) {
                $itemKind = "Note"
                if ([string]::Equals($itemTitle, [string]$collectionDefinition.DefaultTitle, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $noteAuthor = ""
                    try {
                        foreach ($noteAuthorProp in @("Author", "CreatedBy", "User", "Technician")) {
                            if ([string]::IsNullOrWhiteSpace($noteAuthor) -and $item.PSObject.Properties.Name -contains $noteAuthorProp) {
                                $noteAuthor = ([string]($item.$noteAuthorProp + "")).Trim()
                            }
                        }
                    } catch { $noteAuthor = "" }
                    if ([string]::IsNullOrWhiteSpace($noteAuthor)) { $noteAuthor = "Voly" }
                    $itemTitle = ("Internal note (" + $noteAuthor + ")")
                }
            } elseif ([string]::Equals($itemKind, "TechnicianReply", [System.StringComparison]::OrdinalIgnoreCase)) {
                $itemKind = "Reply"
                if ([string]::Equals($itemTitle, [string]$collectionDefinition.DefaultTitle, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $itemTitle = "Reply sent to customer"
                }
            } elseif ($itemKind -match '^(?i)(SystemEvent|System|Audit|Timeline|Activity)$') {
                $itemKind = "SystemEvent"
            }

            & $addEvent -When $itemCreated -Kind $itemKind -Title $itemTitle -Body $itemBody -SortOrder ([int]$collectionDefinition.SortOrder) -Metadata @{
                ItemId = $(if (-not [string]::IsNullOrWhiteSpace($itemId)) { ($collectionName.ToLowerInvariant() + ":" + $itemId) } else { "" })
                TimelineItemId = $itemId
            }
        }
    }

    $replies = @()
    try { if ($Ticket.PSObject.Properties.Name -contains "Replies") { $replies = @($Ticket.Replies) } } catch { $replies = @() }
    foreach ($r in $replies) {
        if (-not $r) { continue }
        $replyBody = ""
        $replyCreated = [datetime]::MinValue
        $replySubject = ""
        try { $replyBody = & $getBodyForTicket $r } catch { $replyBody = "" }
        if ([string]::IsNullOrWhiteSpace($replyBody)) {
            try { if ($r.PSObject.Properties.Name -contains "Body") { $replyBody = [string]$r.Body } else { $replyBody = [string]$r } } catch { $replyBody = "" }
        }
        try { if ($r.PSObject.Properties.Name -contains "CreatedAt") { $replyCreated = & $getDate $r.CreatedAt } } catch { $replyCreated = [datetime]::MinValue }
        try { if ($r.PSObject.Properties.Name -contains "Subject") { $replySubject = ([string]($r.Subject + "")).Trim() } } catch { $replySubject = "" }
        $sentReplyId = ""
        try {
            foreach ($replyIdProp in @("ReplyId", "DraftId", "Id")) {
                if ([string]::IsNullOrWhiteSpace($sentReplyId) -and $r.PSObject.Properties.Name -contains $replyIdProp) {
                    $sentReplyId = ([string]($r.$replyIdProp + "")).Trim()
                }
            }
        } catch { $sentReplyId = "" }
        $replyTitle = "Reply sent to customer"
        if (-not [string]::IsNullOrWhiteSpace($replySubject)) {
            $replyTitle = ("Reply sent - " + $replySubject)
        }
        & $addEvent -When $replyCreated -Kind "Reply" -Title $replyTitle -Body $replyBody -SortOrder 40 -Metadata @{
            ItemId = $(if (-not [string]::IsNullOrWhiteSpace($sentReplyId)) { "reply:" + $sentReplyId } else { "" })
            ReplyId = $sentReplyId
        }
    }

    $removeResolvedRepliesLocalCmd = $null
    $getOptimisticRepliesLocalCmd = $null
    $getQueuedRepliesLocalCmd = $null
    $mergeVisibleRepliesLocalCmd = $null
    try { $removeResolvedRepliesLocalCmd = Resolve-QOTicketsLocalFunction -Name "Remove-QOTicketsResolvedOptimisticReplies" } catch { $removeResolvedRepliesLocalCmd = $null }
    try { $getOptimisticRepliesLocalCmd = Resolve-QOTicketsLocalFunction -Name "Get-QOTicketsOptimisticReplyEntries" } catch { $getOptimisticRepliesLocalCmd = $null }
    try { $getQueuedRepliesLocalCmd = Resolve-QOTicketsLocalFunction -Name "Get-QOTicketsQueuedReplyEntries" } catch { $getQueuedRepliesLocalCmd = $null }
    try { $mergeVisibleRepliesLocalCmd = Resolve-QOTicketsLocalFunction -Name "Merge-QOTTicketVisiblePendingReplyEntries" } catch { $mergeVisibleRepliesLocalCmd = $null }

    try {
        if ($removeResolvedRepliesLocalCmd) {
            $null = & $removeResolvedRepliesLocalCmd -Ticket $Ticket
        } else {
            $null = Remove-QOTicketsResolvedOptimisticReplies -Ticket $Ticket
        }
    } catch { }
    $optimisticReplies = @()
    try {
        if ($getOptimisticRepliesLocalCmd) {
            $optimisticReplies = @(& $getOptimisticRepliesLocalCmd -Ticket $Ticket)
        } else {
            $optimisticReplies = @(Get-QOTicketsOptimisticReplyEntries -Ticket $Ticket)
        }
    } catch { $optimisticReplies = @() }
    $queuedReplies = @()
    try {
        if ($getQueuedRepliesLocalCmd) {
            $queuedReplies = @(& $getQueuedRepliesLocalCmd -Ticket $Ticket -TicketId $ticketId -PreferCached:$PreferCachedPendingReplies)
        } else {
            $queuedReplies = @(Get-QOTicketsQueuedReplyEntries -Ticket $Ticket -TicketId $ticketId -PreferCached:$PreferCachedPendingReplies)
        }
    } catch { $queuedReplies = @() }
    if ($mergeVisibleRepliesLocalCmd) {
        $visiblePendingReplies = @(& $mergeVisibleRepliesLocalCmd -OptimisticReplies $optimisticReplies -QueuedReplies $queuedReplies)
    } else {
        $visiblePendingReplies = @(Merge-QOTTicketVisiblePendingReplyEntries -OptimisticReplies $optimisticReplies -QueuedReplies $queuedReplies)
    }
    foreach ($r in $visiblePendingReplies) {
        if (-not $r) { continue }

        $replyBody = ""
        $replyCreated = [datetime]::MinValue
        $replySubject = ""
        $replyState = ""
        $failureNote = ""
        $replyDraftId = ""
        $replyEntryTicketId = ""
        $queuePosition = 0
        $queueTotal = 0
        $retryCount = 0
        try { if ($r.PSObject.Properties.Name -contains "Body") { $replyBody = ([string]($r.Body + "")).Trim() } } catch { $replyBody = "" }
        try {
            if ($r.PSObject.Properties.Name -contains "CreatedAt") {
                $replyCreated = & $getDate $r.CreatedAt
            } elseif ($r.PSObject.Properties.Name -contains "LastAttemptAt") {
                $replyCreated = & $getDate $r.LastAttemptAt
            }
        } catch { $replyCreated = [datetime]::MinValue }
        try { if ($r.PSObject.Properties.Name -contains "Subject") { $replySubject = ([string]($r.Subject + "")).Trim() } } catch { $replySubject = "" }
        try { if ($r.PSObject.Properties.Name -contains "SendState") { $replyState = ([string]($r.SendState + "")).Trim() } } catch { $replyState = "" }
        try { if ($r.PSObject.Properties.Name -contains "FailureNote") { $failureNote = ([string]($r.FailureNote + "")).Trim() } } catch { $failureNote = "" }
        try { if ($r.PSObject.Properties.Name -contains "DraftId") { $replyDraftId = ([string]($r.DraftId + "")).Trim() } } catch { $replyDraftId = "" }
        try { if ($r.PSObject.Properties.Name -contains "TicketId") { $replyEntryTicketId = ([string]($r.TicketId + "")).Trim() } } catch { $replyEntryTicketId = "" }
        try { if ($r.PSObject.Properties.Name -contains "QueuePosition") { $queuePosition = [int]$r.QueuePosition } } catch { $queuePosition = 0 }
        try { if ($r.PSObject.Properties.Name -contains "QueueTotal") { $queueTotal = [int]$r.QueueTotal } } catch { $queueTotal = 0 }
        try { if ($r.PSObject.Properties.Name -contains "RetryCount") { $retryCount = [int]$r.RetryCount } } catch { $retryCount = 0 }
        $replyLastAttemptAtValue = ""
        $replyNextAttemptAtValue = ""
        try { if ($r.PSObject.Properties.Name -contains "LastAttemptAt") { $replyLastAttemptAtValue = ([string]($r.LastAttemptAt + "")).Trim() } } catch { $replyLastAttemptAtValue = "" }
        try { if ($r.PSObject.Properties.Name -contains "NextAttemptAt") { $replyNextAttemptAtValue = ([string]($r.NextAttemptAt + "")).Trim() } } catch { $replyNextAttemptAtValue = "" }
        if ([string]::IsNullOrWhiteSpace($replyBody)) { continue }

        $replyKind = "ReplyPending"
        $replyTitlePrefix = "Reply pending"
        $replyStatusNote = "Pending send."
        if ([string]::Equals($replyState, "Queued", [System.StringComparison]::OrdinalIgnoreCase)) {
            $replyKind = "ReplyQueued"
            $replyTitlePrefix = "Reply queued"
            $replyStatusNote = "Queued to send after earlier replies finish."
            if ($queuePosition -gt 0 -and $queueTotal -gt 0) {
                $replyStatusNote = ("Queued to send after earlier replies finish. Queue position {0} of {1}." -f $queuePosition, $queueTotal)
            }
        } elseif ([string]::Equals($replyState, "Sending", [System.StringComparison]::OrdinalIgnoreCase)) {
            $replyKind = "ReplySending"
            $replyTitlePrefix = "Reply sending"
            $replyStatusNote = "Sending now in the background."
        }
        $replyTitle = ($replyTitlePrefix + " to customer")
        if (-not [string]::IsNullOrWhiteSpace($replySubject)) {
            $replyTitle = ($replyTitlePrefix + " - " + $replySubject)
        }
        if ([string]::Equals($replyState, "Failed", [System.StringComparison]::OrdinalIgnoreCase)) {
            $replyKind = "ReplyFailed"
            $replyTitle = "Reply failed to send"
            if (-not [string]::IsNullOrWhiteSpace($replySubject)) {
                $replyTitle = ("Reply failed - " + $replySubject)
            }
            if (-not [string]::IsNullOrWhiteSpace($failureNote)) {
                $replyStatusNote = "Send failed: " + $failureNote
            }
        }

        & $addEvent -When $replyCreated -Kind $replyKind -Title $replyTitle -Body $replyBody -SortOrder 45 -Metadata @{
            ItemId              = $(if (-not [string]::IsNullOrWhiteSpace($replyDraftId)) { "pending-reply:" + $replyDraftId } else { "" })
            TicketId             = $(if (-not [string]::IsNullOrWhiteSpace($replyEntryTicketId)) { $replyEntryTicketId } else { $ticketId })
            DraftId              = $replyDraftId
            PendingReplyTicketId = $(if (-not [string]::IsNullOrWhiteSpace($replyEntryTicketId)) { $replyEntryTicketId } else { $ticketId })
            PendingReplyDraftId  = $replyDraftId
            SendState            = $replyState
            FailureNote          = $failureNote
            StatusNote           = $replyStatusNote
            QueuePosition        = $queuePosition
            QueueTotal           = $queueTotal
            RetryCount           = $retryCount
            LastAttemptAt        = $replyLastAttemptAtValue
            NextAttemptAt        = $replyNextAttemptAtValue
        }
    }

    # Include related incoming emails with same thread subject so the IT person sees the running conversation.
    $threadSubject = $subjectSummary
    if ([string]::IsNullOrWhiteSpace($threadSubject)) {
        try { if ($Ticket.PSObject.Properties.Name -contains "Title") { $threadSubject = [string]$Ticket.Title } } catch { $threadSubject = "" }
    }
    $threadKey = & $buildThreadKey $threadSubject
    if (-not [string]::IsNullOrWhiteSpace($threadKey)) {
        try {
            $allTickets = $allTicketsCache
            if ($allTickets.Count -eq 0) {
                $db = $null
                $getTicketsCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTickets"
                if ($getTicketsCmd) {
                    $db = & $getTicketsCmd -Quiet
                }
                $allTickets = @()
                if ($db -and ($db.PSObject.Properties.Name -contains "Tickets")) {
                    $allTickets = @($db.Tickets)
                } elseif ($db) {
                    $allTickets = @($db)
                }
            }

            $currentId = ""
            try { if ($Ticket.PSObject.Properties.Name -contains "Id") { $currentId = [string]$Ticket.Id } } catch { $currentId = "" }

            foreach ($other in $allTickets) {
                if (-not $other) { continue }
                $otherId = ""
                try { if ($other.PSObject.Properties.Name -contains "Id") { $otherId = [string]$other.Id } } catch { $otherId = "" }
                if (-not [string]::IsNullOrWhiteSpace($currentId) -and $otherId -eq $currentId) { continue }
                $otherSubject = ""
                try {
                    if ($other.PSObject.Properties.Name -contains "Subject") { $otherSubject = [string]$other.Subject }
                    elseif ($other.PSObject.Properties.Name -contains "Title") { $otherSubject = [string]$other.Title }
                } catch { $otherSubject = "" }
                $otherKey = & $buildThreadKey $otherSubject
                if ([string]::IsNullOrWhiteSpace($otherKey) -or $otherKey -ne $threadKey) { continue }

                $otherBody = & $getBodyForTicket $other
                if ([string]::IsNullOrWhiteSpace($otherBody)) { continue }

                $otherCreated = [datetime]::MinValue
                try {
                    if ($other.PSObject.Properties.Name -contains "CreatedAt") { $otherCreated = & $getDate $other.CreatedAt }
                    elseif ($other.PSObject.Properties.Name -contains "UpdatedAt") { $otherCreated = & $getDate $other.UpdatedAt }
                } catch { $otherCreated = [datetime]::MinValue }

                $otherFrom = ""
                try { if ($other.PSObject.Properties.Name -contains "EmailFrom") { $otherFrom = ([string]($other.EmailFrom + "")).Trim() } } catch { $otherFrom = "" }
                $otherTitle = "Customer reply"
                if (-not [string]::IsNullOrWhiteSpace($otherFrom)) {
                    $otherTitle = ("Customer reply from " + $otherFrom)
                }
                & $addEvent -When $otherCreated -Kind "Incoming" -Title $otherTitle -Body $otherBody -SortOrder 20
            }
        } catch {
            try { Write-QOTicketsUILog ("Tickets: Related email thread merge failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }

    $summaryParts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($statusSummary)) { $summaryParts.Add("Status: $statusSummary") | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($prioritySummary)) { $summaryParts.Add("Priority: $prioritySummary") | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($assignedSummary)) { $summaryParts.Add("Assigned to: $assignedSummary") | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($createdSummary)) { $summaryParts.Add("Created: $createdSummary") | Out-Null }

    $sections = New-Object System.Collections.Generic.List[string]

    $orderedEvents = @(
        $events |
            Sort-Object `
                @{ Expression = { if ($_.When -and $_.When -ne [datetime]::MinValue) { 0 } else { 1 } }; Ascending = $true }, `
                @{ Expression = { if ($_.When) { $_.When } else { [datetime]::MinValue } }; Ascending = $true }, `
                @{ Expression = { $_.SortOrder }; Ascending = $true }, `
                @{ Expression = {
                    try {
                        if ($_.PSObject.Properties.Name -contains "ItemId") { return ([string]($_.ItemId + "")).Trim() }
                    } catch { }
                    try {
                        if ($_.PSObject.Properties.Name -contains "DraftId") { return ([string]($_.DraftId + "")).Trim() }
                    } catch { }
                    return ""
                }; Ascending = $true }
    )
    if ($orderedEvents.Count -eq 0) {
        $sections.Add("This email did not include readable body content.") | Out-Null
    } else {
        $sections.Add("Activity`r`n--------") | Out-Null
        foreach ($evt in $orderedEvents) {
            if (-not $evt) { continue }
            $whenText = "Time unknown"
            try {
                if ($evt.When -and $evt.When -ne [datetime]::MinValue) {
                    $whenText = Convert-QOTDisplayDateText -Value $evt.When.ToString("o")
                }
            } catch { $whenText = "Time unknown" }
            $titleText = ([string]($evt.Title + "")).Trim()
            if ([string]::IsNullOrWhiteSpace($titleText)) { $titleText = "Update" }
            $bodyText = ([string]($evt.Body + "")).Trim()
            $sections.Add(("[{0}] {1}`r`n{2}" -f $whenText, $titleText, $bodyText)) | Out-Null
        }
    }
    try {
        $typeCounts = @{}
        foreach ($evt in @($orderedEvents)) {
            if (-not $evt) { continue }
            $kindValue = "Unknown"
            try { $kindValue = ([string]($evt.Kind + "")).Trim() } catch { $kindValue = "Unknown" }
            if ([string]::IsNullOrWhiteSpace($kindValue)) { $kindValue = "Unknown" }
            if (-not $typeCounts.ContainsKey($kindValue)) { $typeCounts[$kindValue] = 0 }
            $typeCounts[$kindValue] = [int]$typeCounts[$kindValue] + 1
        }
        $typeSummary = @(
            $typeCounts.Keys |
                Sort-Object |
                ForEach-Object { ("{0}={1}" -f $_, [int]$typeCounts[$_]) }
        ) -join ", "
        Write-QOTicketsUILog ("Tickets: Timeline items rebuilt. TicketId='{0}' Total={1} Types='{2}'." -f $ticketId, @($orderedEvents).Count, $typeSummary)
    } catch { }

    $detailsText = ($sections -join "`r`n`r`n")
    $maxDetailsChars = 220000
    if (-not [string]::IsNullOrWhiteSpace($detailsText) -and $detailsText.Length -gt $maxDetailsChars) {
        $detailsText = $detailsText.Substring(0, $maxDetailsChars) + "`r`n`r`n[Ticket activity truncated for performance.]"
    }
    if ($AsModel) {
        return [pscustomobject]@{
            SummaryLines = @($summaryParts)
            Events       = @($orderedEvents)
            DetailsText  = [string]$detailsText
        }
    }
    return $detailsText
}

function Set-QOTicketDetailsBodyContent {
    param(
        [AllowNull()]$BodyControl,
        [AllowNull()][string[]]$SummaryLines,
        [AllowNull()][object[]]$Events,
        [AllowNull()][string]$FallbackText
    )

    if (-not $BodyControl) { return }

    $summary = @($SummaryLines)
    $eventItems = @($Events)
    $fallbackValue = ([string]($FallbackText + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($fallbackValue)) {
        $fallbackValue = "Double-click a ticket to view email body and reply."
    }

    if ($BodyControl -is [System.Windows.Controls.Panel]) {
        try {
            $bodyPanel = [System.Windows.Controls.Panel]$BodyControl
            try { $bodyPanel.Children.Clear() } catch { }

            $newTextBlock = {
                param(
                    [AllowNull()][string]$Text,
                    [AllowNull()][string]$Foreground = "#E5E7EB",
                    [double]$FontSize = 13,
                    [string]$FontWeight = "Normal",
                    [int]$Left = 0,
                    [int]$Top = 0,
                    [int]$Right = 0,
                    [int]$Bottom = 0
                )
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = [string]($Text + "")
                $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Foreground)
                $tb.FontSize = $FontSize
                $tb.FontWeight = $FontWeight
                $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
                $tb.Margin = [System.Windows.Thickness]::new($Left,$Top,$Right,$Bottom)
                return $tb
            }.GetNewClosure()

            if ($eventItems.Count -eq 0) {
                $bodyPanel.Children.Add((& $newTextBlock -Text $fallbackValue -Foreground "#E5E7EB" -FontSize 13)) | Out-Null
                return
            }

            foreach ($evt in $eventItems) {
                if (-not $evt) { continue }
                $titleText = ""
                $bodyText = ""
                $kindText = ""
                $whenText = "Time unknown"
                try { $titleText = ([string]($evt.Title + "")).Trim() } catch { $titleText = "" }
                try { $bodyText = ([string]($evt.Body + "")).Trim() } catch { $bodyText = "" }
                try { $kindText = ([string]($evt.Kind + "")).Trim() } catch { $kindText = "" }
                if ([string]::IsNullOrWhiteSpace($titleText)) { $titleText = "Update" }
                if ([string]::IsNullOrWhiteSpace($bodyText)) { continue }
                try {
                    if ($evt.When -and $evt.When -ne [datetime]::MinValue) {
                        $whenText = Convert-QOTDisplayDateText -Value $evt.When.ToString("o")
                    }
                } catch { $whenText = "Time unknown" }

                $noteMatch = [regex]::Match($titleText, '^Internal note \((?<author>.+)\)$')
                if ($noteMatch.Success) {
                    $authorValue = ([string]$noteMatch.Groups["author"].Value).Trim()
                    if ([string]::IsNullOrWhiteSpace($authorValue)) { $authorValue = "User" }
                    $noteTicketId = ""
                    $noteId = ""
                    try {
                        if ($evt.PSObject.Properties.Name -contains "TicketId") {
                            $noteTicketId = ([string]($evt.TicketId + "")).Trim()
                        }
                    } catch { $noteTicketId = "" }
                    try {
                        foreach ($noteIdProp in @("NoteId", "ClientNoteId", "Id")) {
                            if ([string]::IsNullOrWhiteSpace($noteId) -and $evt.PSObject.Properties.Name -contains $noteIdProp) {
                                $noteId = ([string]($evt.$noteIdProp + "")).Trim()
                            }
                        }
                        if ([string]::IsNullOrWhiteSpace($noteId) -and $evt.PSObject.Properties.Name -contains "ItemId") {
                            $itemIdValue = ([string]($evt.ItemId + "")).Trim()
                            if ($itemIdValue -match '^(?i)(noteid|note|itemid):(?<id>.+)$') {
                                $noteId = ([string]$Matches["id"]).Trim()
                            }
                        }
                    } catch { $noteId = "" }

                    $noteWrap = New-Object System.Windows.Controls.Border
                    $noteWrap.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3A321D")
                    $noteWrap.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D4A93A")
                    $noteWrap.BorderThickness = [System.Windows.Thickness]::new(1)
                    $noteWrap.CornerRadius = [System.Windows.CornerRadius]::new(4)
                    $noteWrap.Padding = [System.Windows.Thickness]::new(8,6,8,6)
                    $noteWrap.Margin = [System.Windows.Thickness]::new(0,4,0,8)

                    $noteStack = New-Object System.Windows.Controls.StackPanel
                    $noteStack.Orientation = [System.Windows.Controls.Orientation]::Vertical

                    $meta = New-Object System.Windows.Controls.TextBlock
                    $meta.TextWrapping = [System.Windows.TextWrapping]::Wrap
                    $meta.Margin = [System.Windows.Thickness]::new(0,0,0,4)

                    $runAuthor = New-Object System.Windows.Documents.Run($authorValue)
                    $runAuthor.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEF3C7")
                    $runAuthor.FontWeight = [System.Windows.FontWeights]::SemiBold
                    $meta.Inlines.Add($runAuthor) | Out-Null

                    $runDate = New-Object System.Windows.Documents.Run(("  " + $whenText))
                    $runDate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E5E7EB")
                    $meta.Inlines.Add($runDate) | Out-Null

                    $runLock = New-Object System.Windows.Documents.Run(("  " + [string]([char]0xE72E)))
                    $runLock.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
                    $runLock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FCD34D")
                    $meta.Inlines.Add($runLock) | Out-Null

                    $runLabel = New-Object System.Windows.Documents.Run(" Internal note")
                    $runLabel.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
                    $runLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FCD34D")
                    $runLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
                    $meta.Inlines.Add($runLabel) | Out-Null

                    $noteHeaderGrid = New-Object System.Windows.Controls.Grid
                    $noteHeaderGrid.Margin = [System.Windows.Thickness]::new(0,0,0,4)
                    $noteHeaderTextColumn = New-Object System.Windows.Controls.ColumnDefinition
                    $noteHeaderTextColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                    $noteHeaderActionColumn = New-Object System.Windows.Controls.ColumnDefinition
                    $noteHeaderActionColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
                    $noteHeaderGrid.ColumnDefinitions.Add($noteHeaderTextColumn) | Out-Null
                    $noteHeaderGrid.ColumnDefinitions.Add($noteHeaderActionColumn) | Out-Null

                    $meta.Margin = [System.Windows.Thickness]::new(0,0,8,0)
                    [System.Windows.Controls.Grid]::SetColumn($meta, 0)
                    $noteHeaderGrid.Children.Add($meta) | Out-Null

                    if (-not [string]::IsNullOrWhiteSpace($noteId)) {
                        $deleteNoteButton = New-Object System.Windows.Controls.Button
                        $deleteNoteButton.Content = [string]([char]0xE74D)
                        $deleteNoteButton.ToolTip = "Delete internal note"
                        $deleteNoteButton.Width = 26
                        $deleteNoteButton.Height = 26
                        $deleteNoteButton.Padding = [System.Windows.Thickness]::new(0)
                        $deleteNoteButton.Margin = [System.Windows.Thickness]::new(8,0,0,0)
                        $deleteNoteButton.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
                        $deleteNoteButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
                        $deleteNoteButton.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
                        $deleteNoteButton.FontSize = 12
                        $deleteNoteButton.Background = [System.Windows.Media.Brushes]::Transparent
                        $deleteNoteButton.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FDE68A")
                        $deleteNoteButton.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D4A93A")
                        $deleteNoteButton.BorderThickness = [System.Windows.Thickness]::new(1)
                        try { $deleteNoteButton.Cursor = [System.Windows.Input.Cursors]::Hand } catch { }
                        $deleteNoteButton.Tag = [pscustomobject]@{
                            TicketId     = $noteTicketId
                            NoteId       = $noteId
                            ClientNoteId = $noteId
                        }
                        $deleteNoteButton.Add_Click([System.Windows.RoutedEventHandler]{
                            param($sender, $args)
                            try {
                                $tagNoteId = ""
                                try {
                                    if ($sender -and $sender.Tag -and ($sender.Tag.PSObject.Properties.Name -contains "NoteId")) {
                                        $tagNoteId = ([string]($sender.Tag.NoteId + "")).Trim()
                                    }
                                } catch { $tagNoteId = "" }
                                try { Write-QOTicketsUILog ("Tickets: Delete note timeline button clicked with NoteId='{0}'." -f $tagNoteId) } catch { }
                                if ($script:TicketsDeleteNoteHandler) {
                                    $script:TicketsDeleteNoteHandler.Invoke($sender, $args)
                                }
                                try { if ($args) { $args.Handled = $true } } catch { }
                            } catch {
                                try { Write-QOTicketsUILog ("Tickets: Internal note delete icon action failed: " + $_.Exception.Message) "WARN" } catch { }
                            }
                        }.GetNewClosure())
                        [System.Windows.Controls.Grid]::SetColumn($deleteNoteButton, 1)
                        $noteHeaderGrid.Children.Add($deleteNoteButton) | Out-Null
                    }

                    $noteStack.Children.Add($noteHeaderGrid) | Out-Null

                    $noteBody = New-Object System.Windows.Controls.TextBlock
                    $noteBody.Text = $bodyText
                    $noteBody.TextWrapping = [System.Windows.TextWrapping]::Wrap
                    $noteBody.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFF7E6")
                    $noteStack.Children.Add($noteBody) | Out-Null

                    $noteWrap.Child = $noteStack
                    $bodyPanel.Children.Add($noteWrap) | Out-Null
                    continue
                }

                if ([string]::Equals($kindText, "ReplyPending", [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($kindText, "ReplyQueued", [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($kindText, "ReplySending", [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($kindText, "ReplyFailed", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isFailedReply = [string]::Equals($kindText, "ReplyFailed", [System.StringComparison]::OrdinalIgnoreCase)
                    $isQueuedReply = [string]::Equals($kindText, "ReplyQueued", [System.StringComparison]::OrdinalIgnoreCase)
                    $isSendingReply = [string]::Equals($kindText, "ReplySending", [System.StringComparison]::OrdinalIgnoreCase)
                    if ($isFailedReply) {
                        $replyBackgroundColor = "#2B1217"
                        $replyBorderColor = "#F87171"
                        $replyHeaderColor = "#FCA5A5"
                        $replyBodyColor = "#FEE2E2"
                    } elseif ($isQueuedReply) {
                        $replyBackgroundColor = "#111827"
                        $replyBorderColor = "#94A3B8"
                        $replyHeaderColor = "#CBD5E1"
                        $replyBodyColor = "#E5E7EB"
                    } elseif ($isSendingReply) {
                        $replyBackgroundColor = "#10213A"
                        $replyBorderColor = "#60A5FA"
                        $replyHeaderColor = "#BFDBFE"
                        $replyBodyColor = "#E5E7EB"
                    } else {
                        $replyBackgroundColor = "#172033"
                        $replyBorderColor = "#60A5FA"
                        $replyHeaderColor = "#BFDBFE"
                        $replyBodyColor = "#E5E7EB"
                    }
                    $replyWrap = New-Object System.Windows.Controls.Border
                    $replyWrap.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($replyBackgroundColor)
                    $replyWrap.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($replyBorderColor)
                    $replyWrap.BorderThickness = [System.Windows.Thickness]::new(1)
                    $replyWrap.CornerRadius = [System.Windows.CornerRadius]::new(4)
                    $replyWrap.Padding = [System.Windows.Thickness]::new(8,6,8,6)
                    $replyWrap.Margin = [System.Windows.Thickness]::new(0,4,0,8)

                    $replyStack = New-Object System.Windows.Controls.StackPanel
                    $replyStack.Orientation = [System.Windows.Controls.Orientation]::Vertical

                    $replyMeta = New-Object System.Windows.Controls.TextBlock
                    $replyMeta.TextWrapping = [System.Windows.TextWrapping]::Wrap
                    $replyMeta.Margin = [System.Windows.Thickness]::new(0,0,0,4)

                    $replyLabel = New-Object System.Windows.Documents.Run($titleText)
                    $replyLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($replyHeaderColor)
                    $replyLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
                    $replyMeta.Inlines.Add($replyLabel) | Out-Null

                    $replyDate = New-Object System.Windows.Documents.Run(("  " + $whenText))
                    $replyDate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
                    $replyMeta.Inlines.Add($replyDate) | Out-Null

                    $replyHeaderGrid = New-Object System.Windows.Controls.Grid
                    $replyHeaderGrid.Margin = [System.Windows.Thickness]::new(0,0,0,4)
                    $replyHeaderTextColumn = New-Object System.Windows.Controls.ColumnDefinition
                    $replyHeaderTextColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                    $replyHeaderActionColumn = New-Object System.Windows.Controls.ColumnDefinition
                    $replyHeaderActionColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
                    $replyHeaderGrid.ColumnDefinitions.Add($replyHeaderTextColumn) | Out-Null
                    $replyHeaderGrid.ColumnDefinitions.Add($replyHeaderActionColumn) | Out-Null

                    $replyMeta.Margin = [System.Windows.Thickness]::new(0,0,8,0)
                    [System.Windows.Controls.Grid]::SetColumn($replyMeta, 0)
                    $replyHeaderGrid.Children.Add($replyMeta) | Out-Null

                    $replyTicketId = ""
                    $replyDraftId = ""
                    $replyFailureNote = ""
                    $replyRetryCount = 0
                    $replyLastAttemptAt = ""
                    $replyNextAttemptAt = ""
                    $replyStatusNote = ""
                    $replyQueuePosition = 0
                    $replyQueueTotal = 0
                    try {
                        if ($evt.PSObject.Properties.Name -contains "PendingReplyTicketId") {
                            $replyTicketId = ([string]($evt.PendingReplyTicketId + "")).Trim()
                        } elseif ($evt.PSObject.Properties.Name -contains "TicketId") {
                            $replyTicketId = ([string]($evt.TicketId + "")).Trim()
                        }
                    } catch { $replyTicketId = "" }
                    try {
                        if ($evt.PSObject.Properties.Name -contains "PendingReplyDraftId") {
                            $replyDraftId = ([string]($evt.PendingReplyDraftId + "")).Trim()
                        } elseif ($evt.PSObject.Properties.Name -contains "DraftId") {
                            $replyDraftId = ([string]($evt.DraftId + "")).Trim()
                        }
                    } catch { $replyDraftId = "" }
                    try { if ($evt.PSObject.Properties.Name -contains "FailureNote") { $replyFailureNote = ([string]($evt.FailureNote + "")).Trim() } } catch { $replyFailureNote = "" }
                    try { if ($evt.PSObject.Properties.Name -contains "RetryCount") { $replyRetryCount = [int]$evt.RetryCount } } catch { $replyRetryCount = 0 }
                    try { if ($evt.PSObject.Properties.Name -contains "LastAttemptAt") { $replyLastAttemptAt = ([string]($evt.LastAttemptAt + "")).Trim() } } catch { $replyLastAttemptAt = "" }
                    try { if ($evt.PSObject.Properties.Name -contains "NextAttemptAt") { $replyNextAttemptAt = ([string]($evt.NextAttemptAt + "")).Trim() } } catch { $replyNextAttemptAt = "" }
                    try { if ($evt.PSObject.Properties.Name -contains "StatusNote") { $replyStatusNote = ([string]($evt.StatusNote + "")).Trim() } } catch { $replyStatusNote = "" }
                    try { if ($evt.PSObject.Properties.Name -contains "QueuePosition") { $replyQueuePosition = [int]$evt.QueuePosition } } catch { $replyQueuePosition = 0 }
                    try { if ($evt.PSObject.Properties.Name -contains "QueueTotal") { $replyQueueTotal = [int]$evt.QueueTotal } } catch { $replyQueueTotal = 0 }

                    $statusParts = New-Object System.Collections.Generic.List[string]
                    if (-not [string]::IsNullOrWhiteSpace($replyStatusNote)) {
                        $statusParts.Add($replyStatusNote) | Out-Null
                    }
                    if ($replyRetryCount -gt 0) {
                        $statusParts.Add(("Attempts: " + $replyRetryCount)) | Out-Null
                    }
                    if (-not [string]::IsNullOrWhiteSpace($replyLastAttemptAt)) {
                        $lastAttemptLabel = $replyLastAttemptAt
                        try { $lastAttemptLabel = Convert-QOTDisplayDateText -Value $replyLastAttemptAt } catch { }
                        $statusParts.Add(("Last try: " + $lastAttemptLabel)) | Out-Null
                    }
                    if (-not [string]::IsNullOrWhiteSpace($replyNextAttemptAt)) {
                        $nextAttemptLabel = $replyNextAttemptAt
                        try { $nextAttemptLabel = Convert-QOTDisplayDateText -Value $replyNextAttemptAt } catch { }
                        $statusParts.Add(("Next retry: " + $nextAttemptLabel)) | Out-Null
                    }
                    if (-not [string]::IsNullOrWhiteSpace($replyFailureNote)) {
                        $statusParts.Add(("Last error: " + $replyFailureNote)) | Out-Null
                    }
                    $replyStatusTooltip = ""
                    try { if ($statusParts.Count -gt 0) { $replyStatusTooltip = ($statusParts -join " | ") } } catch { $replyStatusTooltip = "" }
                    if (-not [string]::IsNullOrWhiteSpace($replyStatusTooltip)) {
                        try { $replyWrap.ToolTip = $replyStatusTooltip } catch { }
                    }

                    if (-not [string]::IsNullOrWhiteSpace($replyDraftId)) {
                        $replyActions = New-Object System.Windows.Controls.StackPanel
                        $replyActions.Orientation = [System.Windows.Controls.Orientation]::Horizontal
                        $replyActions.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right

                        $retryButton = New-Object System.Windows.Controls.Button
                        $retryButton.Content = [string]([char]0xE72C)
                        $retryButton.ToolTip = $(if ($isSendingReply) { "Reply is already sending." } elseif ($isFailedReply) { "Retry failed reply" } else { "Retry this queued reply now" })
                        $retryButton.Width = 26
                        $retryButton.Height = 26
                        $retryButton.Padding = [System.Windows.Thickness]::new(0)
                        $retryButton.Margin = [System.Windows.Thickness]::new(8,0,0,0)
                        $retryButton.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
                        $retryButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
                        $retryButton.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
                        $retryButton.FontSize = 12
                        $retryButton.Background = [System.Windows.Media.Brushes]::Transparent
                        $retryButton.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($isFailedReply) { "#FCA5A5" } else { "#BFDBFE" }))
                        $retryButton.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($isFailedReply) { "#F87171" } else { "#60A5FA" }))
                        $retryButton.BorderThickness = [System.Windows.Thickness]::new(1)
                        $retryButton.IsEnabled = (-not $isSendingReply)
                        try { $retryButton.Cursor = [System.Windows.Input.Cursors]::Hand } catch { }
                        $retryButton.Tag = [pscustomobject]@{
                            TicketId             = $replyTicketId
                            DraftId              = $replyDraftId
                            PendingReplyTicketId = $replyTicketId
                            PendingReplyDraftId  = $replyDraftId
                        }
                        $retryButton.Add_Click([System.Windows.RoutedEventHandler]{
                            param($sender, $args)
                            try {
                                $tagDraftId = ""
                                try {
                                    if ($sender -and $sender.Tag -and ($sender.Tag.PSObject.Properties.Name -contains "PendingReplyDraftId")) {
                                        $tagDraftId = ([string]($sender.Tag.PendingReplyDraftId + "")).Trim()
                                    }
                                } catch { $tagDraftId = "" }
                                try { Write-QOTicketsUILog ("Tickets: Retry reply timeline button clicked with DraftId='{0}'." -f $tagDraftId) } catch { }
                                if ($script:TicketsRetryReplyHandler) {
                                    $script:TicketsRetryReplyHandler.Invoke($sender, $args)
                                } else {
                                    try { Write-QOTicketsUILog "Tickets: Retry reply timeline button ignored because handler is not attached." "WARN" } catch { }
                                }
                                try { if ($args) { $args.Handled = $true } } catch { }
                            } catch {
                                try { Write-QOTicketsUILog ("Tickets: Failed reply retry icon action failed: " + $_.Exception.Message) "WARN" } catch { }
                            }
                        }.GetNewClosure())
                        $replyActions.Children.Add($retryButton) | Out-Null

                        $cancelButton = New-Object System.Windows.Controls.Button
                        $cancelButton.Content = [string]([char]0xE74D)
                        $cancelButton.ToolTip = "Delete/cancel queued reply"
                        $cancelButton.Width = 26
                        $cancelButton.Height = 26
                        $cancelButton.Padding = [System.Windows.Thickness]::new(0)
                        $cancelButton.Margin = [System.Windows.Thickness]::new(6,0,0,0)
                        $cancelButton.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
                        $cancelButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
                        $cancelButton.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
                        $cancelButton.FontSize = 12
                        $cancelButton.Background = [System.Windows.Media.Brushes]::Transparent
                        $cancelButton.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FDE68A")
                        $cancelButton.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
                        $cancelButton.BorderThickness = [System.Windows.Thickness]::new(1)
                        try { $cancelButton.Cursor = [System.Windows.Input.Cursors]::Hand } catch { }
                        $cancelButton.Tag = [pscustomobject]@{
                            TicketId             = $replyTicketId
                            DraftId              = $replyDraftId
                            PendingReplyTicketId = $replyTicketId
                            PendingReplyDraftId  = $replyDraftId
                        }
                        $cancelButton.Add_Click([System.Windows.RoutedEventHandler]{
                            param($sender, $args)
                            try {
                                $tagDraftId = ""
                                try {
                                    if ($sender -and $sender.Tag -and ($sender.Tag.PSObject.Properties.Name -contains "PendingReplyDraftId")) {
                                        $tagDraftId = ([string]($sender.Tag.PendingReplyDraftId + "")).Trim()
                                    }
                                } catch { $tagDraftId = "" }
                                try { Write-QOTicketsUILog ("Tickets: Delete reply timeline button clicked with DraftId='{0}'." -f $tagDraftId) } catch { }
                                if ($script:TicketsCancelReplyHandler) {
                                    $script:TicketsCancelReplyHandler.Invoke($sender, $args)
                                } else {
                                    try { Write-QOTicketsUILog "Tickets: Delete reply timeline button ignored because handler is not attached." "WARN" } catch { }
                                }
                                try { if ($args) { $args.Handled = $true } } catch { }
                            } catch {
                                try { Write-QOTicketsUILog ("Tickets: Pending reply cancel icon action failed: " + $_.Exception.Message) "WARN" } catch { }
                            }
                        }.GetNewClosure())
                        $replyActions.Children.Add($cancelButton) | Out-Null

                        [System.Windows.Controls.Grid]::SetColumn($replyActions, 1)
                        $replyHeaderGrid.Children.Add($replyActions) | Out-Null
                    }

                    $replyStack.Children.Add($replyHeaderGrid) | Out-Null

                    $replyBodyText = New-Object System.Windows.Controls.TextBlock
                    $replyBodyText.Text = $bodyText
                    $replyBodyText.TextWrapping = [System.Windows.TextWrapping]::Wrap
                    $replyBodyText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($replyBodyColor)
                    $replyStack.Children.Add($replyBodyText) | Out-Null

                    if (-not [string]::IsNullOrWhiteSpace($replyStatusTooltip)) {
                        $replyStatusText = New-Object System.Windows.Controls.TextBlock
                        $replyStatusText.Text = $replyStatusTooltip
                        $replyStatusText.TextWrapping = [System.Windows.TextWrapping]::Wrap
                        $replyStatusText.Margin = [System.Windows.Thickness]::new(0,6,0,0)
                        $replyStatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
                        $replyStatusText.FontSize = 11
                        $replyStack.Children.Add($replyStatusText) | Out-Null
                    }

                    $replyWrap.Child = $replyStack
                    $bodyPanel.Children.Add($replyWrap) | Out-Null
                    continue
                }

                $bodyPanel.Children.Add((& $newTextBlock -Text ("[{0}] {1}" -f $whenText, $titleText) -Foreground "#93C5FD" -FontSize 12 -FontWeight "SemiBold" -Top 4 -Bottom 2)) | Out-Null
                $bodyPanel.Children.Add((& $newTextBlock -Text $bodyText -Foreground "#E5E7EB" -FontSize 13 -Bottom 8)) | Out-Null
            }
            return
        } catch {
            try { Write-QOTicketsUILog ("Tickets: Panel details rendering failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }

    if ($BodyControl -is [System.Windows.Controls.RichTextBox]) {
        try {
            $doc = New-Object System.Windows.Documents.FlowDocument
            $doc.PagePadding = [System.Windows.Thickness]::new(0)
            $doc.Background = [System.Windows.Media.Brushes]::Transparent
            $doc.Blocks.Clear()
            $plain = New-Object System.Windows.Documents.Paragraph
            $plain.Margin = [System.Windows.Thickness]::new(0)
            $plain.Inlines.Add((New-Object System.Windows.Documents.Run($fallbackValue))) | Out-Null
            $plain.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E5E7EB")
            $doc.Blocks.Add($plain)
            $BodyControl.Document = $doc
            return
        } catch {
            try { Write-QOTicketsUILog ("Tickets: RichText fallback rendering failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }

    try {
        if ($BodyControl -is [System.Windows.Controls.TextBlock]) {
            $BodyControl.Text = $fallbackValue
            return
        }
        if ($BodyControl.PSObject.Properties.Name -contains "Text") {
            $BodyControl.Text = $fallbackValue
            return
        }
    } catch { }
}

function Update-QOTicketDetailsView {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][System.Windows.UIElement]$DetailsPanel,
        [AllowNull()]$BodyText,
        [AllowNull()][System.Windows.Controls.TextBox]$ReplySubject,
        [AllowNull()][System.Windows.Controls.TextBox]$ReplyText,
        [AllowNull()][System.Windows.Controls.Button]$ReplyButton,
        [AllowNull()][System.Windows.Controls.TextBlock]$Chevron,
        [switch]$PreferCurrentTicket,
        [switch]$PreferCachedPendingReplies,
        [switch]$RequireActiveDetailView
    )

    if (-not $Ticket) {
        if ($BodyText) {
            Set-QOTicketDetailsBodyContent -BodyControl $BodyText -SummaryLines @() -Events @() -FallbackText "Double-click a ticket to view email body and reply."
        }
        try { Set-QOTicketSummaryHeader -SummaryControl $script:TicketsSummaryHeaderText -SummaryLines @() } catch { }
        try { Set-QOTicketContactHeader -Ticket $null } catch { }
        if ($ReplySubject) { $ReplySubject.Text = "" }
        if ($ReplyText) { $ReplyText.Text = "" }
        if ($ReplyButton) { $ReplyButton.IsEnabled = $false }
        try { if ($script:TicketsHeaderTitleText) { $script:TicketsHeaderTitleText.Text = "Tickets" } } catch { }
        Set-QOTicketDetailsVisibility -DetailsPanel $DetailsPanel -Chevron $Chevron -IsOpen:$false
        return
    }

    $refreshTicketId = ""
    try { $refreshTicketId = Get-QOTicketIdValue -Ticket $Ticket } catch { $refreshTicketId = "" }
    if ($RequireActiveDetailView -and -not (Test-QOTicketDetailsViewActive -TicketId $refreshTicketId)) {
        try { Write-QOTicketsUILog ("Tickets: Timeline refresh ignored because ticket/view is no longer active. TicketId='{0}' ActiveTicketId='{1}'." -f $refreshTicketId, ([string]($script:TicketsActiveTicketId + "")).Trim()) } catch { }
        return
    }
    $composeModeBeforeRefresh = ""
    try { $composeModeBeforeRefresh = ([string]($script:TicketsComposeMode + "")).Trim() } catch { $composeModeBeforeRefresh = "" }
    try {
        if (($script:TicketsComposeModeByTicketId -is [hashtable]) -and
            (-not [string]::IsNullOrWhiteSpace($refreshTicketId)) -and
            $script:TicketsComposeModeByTicketId.ContainsKey($refreshTicketId)) {
            $rememberedComposeMode = ([string]($script:TicketsComposeModeByTicketId[$refreshTicketId] + "")).Trim()
            if ($rememberedComposeMode -match '^(?i)(Reply|Note)$') {
                $script:TicketsComposeMode = $rememberedComposeMode
            }
        }
    } catch { }
    try { Write-QOTicketsUILog ("Tickets: Timeline refresh start. TicketId='{0}' RenderPath='DetailRefresh' ComposeModeBefore='{1}'." -f $refreshTicketId, $composeModeBeforeRefresh) } catch { }

    $detailsRenderModel = $null
    $resolvedTicket = $Ticket
    try {
        $resolveDetailsRenderCmd = Resolve-QOTicketsLocalFunction -Name "Get-QOTTicketDetailsRenderModel"
        if ($resolveDetailsRenderCmd) {
            $detailsRenderModel = & $resolveDetailsRenderCmd -Ticket $Ticket -RenderPath "DetailRefresh" -PreferCurrentTicket:$PreferCurrentTicket -PreferCachedPendingReplies:$PreferCachedPendingReplies
        } else {
            $detailsRenderModel = Get-QOTTicketDetailsRenderModel -Ticket $Ticket -RenderPath "DetailRefresh" -PreferCurrentTicket:$PreferCurrentTicket -PreferCachedPendingReplies:$PreferCachedPendingReplies
        }
    } catch {
        $detailsRenderModel = $null
        try { Write-QOTicketsUILog ("Tickets: Update details render model failed: " + $_.Exception.Message) "WARN" } catch { }
        try { Write-QOTicketsUILog ("Tickets: Update details render model stack: " + $_.ScriptStackTrace) "WARN" } catch { }
    }
    try {
        if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "Ticket")) {
            $resolvedTicket = $detailsRenderModel.Ticket
        }
    } catch { $resolvedTicket = $Ticket }
    if (-not $PreferCurrentTicket) {
        try {
            $sourceResolveCmd = Resolve-QOTicketsLocalFunction -Name "Resolve-QOTTicketDetailsSourceTicket"
            if ($sourceResolveCmd) {
                $latestResolvedTicket = & $sourceResolveCmd -Ticket $resolvedTicket
            } else {
                $latestResolvedTicket = Resolve-QOTTicketDetailsSourceTicket -Ticket $resolvedTicket
            }
            if ($latestResolvedTicket) { $resolvedTicket = $latestResolvedTicket }
        } catch { }
    }
    if (-not $resolvedTicket) { $resolvedTicket = $Ticket }
    try { $resolvedTicket = Sync-QOTTicketLivePendingReplies -Ticket $resolvedTicket -PreferCached:$PreferCachedPendingReplies } catch { }
    try {
        if ($Ticket -and $resolvedTicket -and -not [object]::ReferenceEquals($Ticket, $resolvedTicket)) {
            $null = Update-QOTicketObjectFromSource -Target $Ticket -Source $resolvedTicket
        }
    } catch { }
    if (-not $RequireActiveDetailView) {
        try {
            $resolvedRefreshTicketId = Get-QOTicketIdValue -Ticket $resolvedTicket
            if (-not [string]::IsNullOrWhiteSpace($resolvedRefreshTicketId)) { $refreshTicketId = $resolvedRefreshTicketId }
            $script:TicketsDetailsViewClosing = $false
            $script:TicketsActiveTicketId = $refreshTicketId
        } catch { }
    }

    if ($RequireActiveDetailView -and -not (Test-QOTicketDetailsViewActive -TicketId $refreshTicketId)) {
        try { Write-QOTicketsUILog ("Tickets: Timeline refresh ignored after hydration because ticket/view is no longer active. TicketId='{0}' ActiveTicketId='{1}'." -f $refreshTicketId, ([string]($script:TicketsActiveTicketId + "")).Trim()) } catch { }
        return
    }

    if ($BodyText) {
        $detailsText = ""
        $summaryLines = @()
        $eventItems = @()
        $displayBodyInfo = $null
        try { if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "DetailsText")) { $detailsText = [string]$detailsRenderModel.DetailsText } } catch { $detailsText = "" }
        try { if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "SummaryLines")) { $summaryLines = @($detailsRenderModel.SummaryLines) } } catch { $summaryLines = @() }
        try { if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "Events")) { $eventItems = @($detailsRenderModel.Events) } } catch { $eventItems = @() }
        try { $displayBodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $resolvedTicket } catch { $displayBodyInfo = $null }
        if (([string]::IsNullOrWhiteSpace($detailsText)) -and (@($eventItems).Count -eq 0) -and $displayBodyInfo -and (-not [string]::IsNullOrWhiteSpace([string]($displayBodyInfo.Text + "")))) {
            $detailsText = ([string]($displayBodyInfo.Text + "")).Trim()
            $fromLine = [string](Get-QOTicketPropertyTextValue -Ticket $resolvedTicket -PropertyNames @("EmailFrom", "SenderName", "SenderEmail", "From", "Sender"))
            if ([string]::IsNullOrWhiteSpace($fromLine)) { $fromLine = "Email sender unavailable" }
            $eventItems = @(
                [pscustomobject]@{
                    When      = [datetime]::MinValue
                    SortOrder = 10
                    Kind      = "Email"
                    Title     = ("Main email from " + $fromLine)
                    Body      = $detailsText
                }
            )
        }
        if ([string]::IsNullOrWhiteSpace($detailsText) -and (@($eventItems).Count -eq 0)) {
            try {
                if (Test-QOTicketHasStoredActivity -Ticket $resolvedTicket) {
                    $detailsText = "Ticket activity is available but could not be rendered."
                }
            } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($detailsText) -and (@($eventItems).Count -eq 0)) {
            $detailsText = "This email did not include readable body content."
        }
        try {
            $typeCounts = @{}
            foreach ($eventItem in @($eventItems)) {
                $kind = "Unknown"
                try { $kind = ([string]($eventItem.Kind + "")).Trim() } catch { $kind = "Unknown" }
                if ([string]::IsNullOrWhiteSpace($kind)) { $kind = "Unknown" }
                if (-not $typeCounts.ContainsKey($kind)) { $typeCounts[$kind] = 0 }
                $typeCounts[$kind] = [int]$typeCounts[$kind] + 1
            }
            $typeSummary = (@($typeCounts.Keys) | Sort-Object | ForEach-Object { "{0}={1}" -f $_, $typeCounts[$_] }) -join ","
            if ([string]::IsNullOrWhiteSpace($typeSummary)) { $typeSummary = "none" }
            Write-QOTicketsUILog ("Tickets: Timeline items rebuilt. TicketId='{0}' Count={1} Types='{2}'." -f (Get-QOTicketIdValue -Ticket $resolvedTicket), @($eventItems).Count, $typeSummary)
        } catch { }
        try {
            Write-QOTicketsUILog ("Tickets: Legacy details render. Input={0}; Resolved={1}; DisplaySource={2}; DisplayProperty={3}; DisplayLength={4}; EventCount={5}; DetailsLength={6}" -f `
                (Get-QOTicketLogLabel -Ticket $Ticket), `
                (Get-QOTicketLogLabel -Ticket $resolvedTicket), `
                $(if ($displayBodyInfo) { [string]$displayBodyInfo.Source } else { "" }), `
                $(if ($displayBodyInfo) { [string]$displayBodyInfo.Property } else { "" }), `
                $(if ($displayBodyInfo) { [string]$displayBodyInfo.Length } else { "0" }), `
                @($eventItems).Count, `
                ([string]($detailsText + "")).Length)
        } catch { }
        try { Set-QOTicketSummaryHeader -SummaryControl $script:TicketsSummaryHeaderText -SummaryLines $summaryLines } catch { }
        try { Set-QOTicketContactHeader -Ticket $resolvedTicket } catch { }
        Set-QOTicketDetailsBodyContent -BodyControl $BodyText -SummaryLines $summaryLines -Events $eventItems -FallbackText $detailsText
    }
    if ($ReplySubject) {
        $subjectValue = [string](Get-QOTTicketPreferredSubject -Ticket $resolvedTicket)

        if ($subjectValue) {
            if ($subjectValue -notmatch '^(RE|FW|FWD):') {
                $subjectValue = "RE: " + $subjectValue
            }
        }

        $ReplySubject.Text = $subjectValue

        $headerSubject = ([string]($subjectValue + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($headerSubject)) { $headerSubject = "No subject" }
        if ($headerSubject.Length -gt 90) { $headerSubject = $headerSubject.Substring(0, 90) + "..." }
        try {
            if ($script:TicketsHeaderTitleText) {
                $script:TicketsHeaderTitleText.Text = ("Tickets - " + $headerSubject)
            }
        } catch { }
    }
    if ($ReplyButton) {
        $canReply = $false
        try {
            if ($resolvedTicket.PSObject.Properties.Name -contains "SourceMessageId") {
                if (-not [string]::IsNullOrWhiteSpace([string]$resolvedTicket.SourceMessageId)) { $canReply = $true }
            }
            if (-not $canReply -and ($resolvedTicket.PSObject.Properties.Name -contains "EmailMessageId")) {
                if (-not [string]::IsNullOrWhiteSpace([string]$resolvedTicket.EmailMessageId)) { $canReply = $true }
            }
        } catch { $canReply = $false }

        $currentComposeMode = ""
        try { $currentComposeMode = ([string]($script:TicketsComposeMode + "")).Trim() } catch { $currentComposeMode = "" }
        if ([string]::Equals($currentComposeMode, "Note", [System.StringComparison]::OrdinalIgnoreCase)) {
            $ReplyButton.IsEnabled = $true
            try { $ReplyButton.Content = "Save internal note" } catch { }
        } else {
            $ReplyButton.IsEnabled = $canReply
            try { $ReplyButton.Content = "Send reply" } catch { }
        }
    }
    Set-QOTicketDetailsVisibility -DetailsPanel $DetailsPanel -Chevron $Chevron -IsOpen:$true
    try { Write-QOTicketsUILog ("Tickets: Compose mode after refresh. TicketId='{0}' Mode='{1}'." -f $refreshTicketId, ([string]($script:TicketsComposeMode + "")).Trim()) } catch { }
    try { Write-QOTicketsUILog ("Tickets: Timeline refresh end. TicketId='{0}'." -f $refreshTicketId) } catch { }
}

function Get-QOParentVisual {
    param(
        [AllowNull()]$Element,
        [Parameter(Mandatory)][Type]$Type
    )

    $current = $Element
    while ($current) {
        if ($Type.IsInstanceOfType($current)) {
            return $current
        }

        $next = $null
        try {
            if ($current -is [System.Windows.Media.Visual] -or $current -is [System.Windows.Media.Media3D.Visual3D]) {
                $next = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
            } elseif ($current -is [System.Windows.FrameworkContentElement]) {
                $next = $current.Parent
                if (-not $next) { $next = [System.Windows.LogicalTreeHelper]::GetParent($current) }
            } elseif ($current -is [System.Windows.ContentElement]) {
                $next = [System.Windows.LogicalTreeHelper]::GetParent($current)
            } elseif ($current -is [System.Windows.DependencyObject]) {
                $next = [System.Windows.LogicalTreeHelper]::GetParent($current)
            }
        } catch {
            $next = $null
        }

        if ($null -eq $next -or [object]::ReferenceEquals($next, $current)) {
            break
        }
        $current = $next
    }
    return $null
}

function Get-QOVisualChildByType {
    param(
        [AllowNull()][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][Type]$Type,
        [AllowNull()][string]$Name,
        # Depth guard - WPF visual trees beyond 64 levels indicate a cycle
        # or pathologically nested template that we should not recurse into.
        [int]$Depth = 0,
        [int]$MaxDepth = 64
    )

    if (-not $Root) { return $null }
    if ($Depth -ge $MaxDepth) {
        try { Write-QOTicketsUILog ("Get-QOVisualChildByType aborted at depth {0} (limit {1}) looking for type '{2}'. Possible cycle or deep tree." -f $Depth, $MaxDepth, $Type.FullName) "WARN" } catch { }
        return $null
    }

    try {
        $childrenCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root)
    } catch {
        return $null
    }

    for ($index = 0; $index -lt $childrenCount; $index++) {
        $child = $null
        try { $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Root, $index) } catch { $child = $null }
        if (-not $child) { continue }

        if ($Type.IsInstanceOfType($child)) {
            if ([string]::IsNullOrWhiteSpace([string]$Name)) {
                return $child
            }
            $childName = ""
            try {
                if ($child -is [System.Windows.FrameworkElement]) { $childName = [string]$child.Name }
            } catch { $childName = "" }
            if ($childName -eq $Name) { return $child }
        }

        $descendant = Get-QOVisualChildByType -Root $child -Type $Type -Name $Name -Depth ($Depth + 1) -MaxDepth $MaxDepth
        if ($descendant) { return $descendant }
    }

    return $null
}

function Get-QOTSelectedTickets {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [switch]$AllowContextFallback
    )

    $selected = @()
    try { $selected = @($Grid.SelectedItems | Where-Object { $null -ne $_ }) } catch { $selected = @() }

    if ($selected.Count -eq 0) {
        try {
            if ($null -ne $Grid.SelectedItem) {
                $selected = @($Grid.SelectedItem)
            }
        } catch { }
    }

    if ($selected.Count -eq 0 -and $AllowContextFallback) {
        try {
            if ($script:TicketsContextMenuSelection) {
                $selected = @($script:TicketsContextMenuSelection | Where-Object { $null -ne $_ })
            }
        } catch { }
    }

    return @($selected)
}

function Invoke-QOTicketStatusChangeForItems {
    param(
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()][object[]]$PreferredItems,
        [Parameter(Mandatory)][string]$StatusValue,
        [AllowNull()]$GetSelectedTicketsCmd,
        [AllowNull()]$SetStatusCmd,
        [AllowNull()]$GetTicketsCmd,
        [AllowNull()][string]$View
)

    try {
        $effectiveGrid = $Grid
        if (-not $effectiveGrid) {
            try { $effectiveGrid = $script:TicketsGrid } catch { $effectiveGrid = $null }
        }
        if (-not $effectiveGrid) {
            Write-QOTicketsUILog "Tickets: Status change skipped because grid reference is unavailable." "WARN"
            return $false
        }

        $effectiveGetSelectedCmd = Resolve-QOTInvokable -Candidate $GetSelectedTicketsCmd -CommandName "Get-QOTSelectedTickets"
        $effectiveSetStatusCmd = Resolve-QOTInvokable -Candidate $SetStatusCmd -CommandName "Set-QOTicketsStatus"
        $effectiveGetTicketsCmd = Resolve-QOTInvokable -Candidate $GetTicketsCmd -CommandName "Get-QOTicketsByBucket"
        if (-not $effectiveGetTicketsCmd) {
            $effectiveGetTicketsCmd = Resolve-QOTInvokable -Candidate $null -CommandName "Get-QOTicketsByFolder"
        }
        if (-not $effectiveGetTicketsCmd) {
            $effectiveGetTicketsCmd = Resolve-QOTInvokable -Candidate $null -CommandName "Get-QOTickets"
        }

        $newStatus = ([string]($StatusValue + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($newStatus)) { return $false }

        $selectedItems = @($PreferredItems | Where-Object { $null -ne $_ })
        if ($selectedItems.Count -eq 0) {
            if ($effectiveGetSelectedCmd) {
                try {
                    $selectedItems = @(& $effectiveGetSelectedCmd -Grid $effectiveGrid -AllowContextFallback)
                } catch {
                    Write-QOTicketsUILog ("Tickets: Failed to resolve selected tickets for status change. " + $_.Exception.Message) "WARN"
                    $selectedItems = @()
                }
            }
            if ($selectedItems.Count -eq 0) {
                try {
                    if ($null -ne $effectiveGrid.SelectedItem) { $selectedItems = @($effectiveGrid.SelectedItem) }
                } catch { $selectedItems = @() }
            }
        }
        if ($selectedItems.Count -eq 0) { return $false }

        foreach ($item in $selectedItems) {
            if ($null -eq $item) { continue }
            try { $item.Status = $newStatus } catch { }
        }
        $ids = @(
            $selectedItems |
                Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") } |
                ForEach-Object { $_.Id }
        )
        if ($ids.Count -eq 0) { return $false }

        $persisted = $false
        if ($effectiveSetStatusCmd) {
            try {
                $persistSw = [System.Diagnostics.Stopwatch]::StartNew()
                $null = & $effectiveSetStatusCmd -Id $ids -Status $newStatus
                $persistSw.Stop()
                $persistMs = [math]::Round([double]$persistSw.Elapsed.TotalMilliseconds, 2)
                if ($persistMs -ge 400) {
                    Write-QOTicketsUILog ("Tickets: Status persist took {0} ms for {1} ticket(s)." -f $persistMs, $ids.Count) "WARN"
                } else {
                    Write-QOTicketsUILog ("Tickets: Status persist took {0} ms for {1} ticket(s)." -f $persistMs, $ids.Count)
                }
                $persisted = $true
            } catch {
                Write-QOTicketsUILog ("Tickets: Persisting status change failed. " + $_.Exception.Message) "ERROR"
            }
        } else {
            Write-QOTicketsUILog "Tickets: Set status command unavailable; visual status updated only." "WARN"
        }

        try {
            $detailsTicket = $null
            if ($selectedItems.Count -gt 0) { $detailsTicket = $selectedItems[0] }
            Refresh-QOTicketsAfterLocalMutation -Grid $effectiveGrid -PreferredDetailsTicket $detailsTicket
        } catch {
            Write-QOTicketsUILog ("Tickets: Local status refresh failed. " + $_.Exception.Message) "WARN"
        }

        return $persisted
    } catch {
        Write-QOTicketsUILog ("Tickets: Status change helper failed. " + $_.Exception.Message) "ERROR"
        return $false
    }
}

function Invoke-QOTicketAssigneeChangeForItems {
    param(
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()][object[]]$PreferredItems,
        [AllowNull()][string]$AssigneeValue,
        [AllowNull()]$GetSelectedTicketsCmd,
        [AllowNull()]$SetAssignedToCmd,
        [AllowNull()]$UpdateTicketCmd,
        [AllowNull()]$GetTicketsCmd,
        [AllowNull()][string]$View
)

    try {
        $effectiveGrid = $Grid
        if (-not $effectiveGrid) {
            try { $effectiveGrid = $script:TicketsGrid } catch { $effectiveGrid = $null }
        }
        if (-not $effectiveGrid) {
            Write-QOTicketsUILog "Tickets: Assignee change skipped because grid reference is unavailable." "WARN"
            return $false
        }

        $effectiveGetSelectedCmd = Resolve-QOTInvokable -Candidate $GetSelectedTicketsCmd -CommandName "Get-QOTSelectedTickets"
        $effectiveSetAssignedCmd = Resolve-QOTInvokable -Candidate $SetAssignedToCmd -CommandName "Set-QOTicketsAssignedTo"
        $effectiveUpdateCmd = Resolve-QOTInvokable -Candidate $UpdateTicketCmd -CommandName "Update-QOTicket"
        $effectiveGetTicketsCmd = Resolve-QOTInvokable -Candidate $GetTicketsCmd -CommandName "Get-QOTicketsByBucket"
        if (-not $effectiveGetTicketsCmd) {
            $effectiveGetTicketsCmd = Resolve-QOTInvokable -Candidate $null -CommandName "Get-QOTicketsByFolder"
        }
        if (-not $effectiveGetTicketsCmd) {
            $effectiveGetTicketsCmd = Resolve-QOTInvokable -Candidate $null -CommandName "Get-QOTickets"
        }

        $newAssignee = ([string]($AssigneeValue + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($newAssignee)) { $newAssignee = "Unassigned" }

        $selectedItems = @($PreferredItems | Where-Object { $null -ne $_ })
        if ($selectedItems.Count -eq 0) {
            if ($effectiveGetSelectedCmd) {
                try {
                    $selectedItems = @(& $effectiveGetSelectedCmd -Grid $effectiveGrid -AllowContextFallback)
                } catch {
                    Write-QOTicketsUILog ("Tickets: Failed to resolve selected tickets for assignee change. " + $_.Exception.Message) "WARN"
                    $selectedItems = @()
                }
            }
            if ($selectedItems.Count -eq 0) {
                try {
                    if ($null -ne $effectiveGrid.SelectedItem) { $selectedItems = @($effectiveGrid.SelectedItem) }
                } catch { $selectedItems = @() }
            }
        }
        if ($selectedItems.Count -eq 0) { return $false }

        foreach ($item in $selectedItems) {
            if ($null -eq $item) { continue }
            try { $item.AssignedTo = $newAssignee } catch { }
        }
        $ids = @(
            $selectedItems |
                Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") } |
                ForEach-Object { $_.Id }
        )
        if ($ids.Count -eq 0) { return $false }

        $persisted = $false
        if ($effectiveSetAssignedCmd) {
            try {
                $persistSw = [System.Diagnostics.Stopwatch]::StartNew()
                $null = & $effectiveSetAssignedCmd -Id $ids -AssignedTo $newAssignee
                $persistSw.Stop()
                $persistMs = [math]::Round([double]$persistSw.Elapsed.TotalMilliseconds, 2)
                if ($persistMs -ge 400) {
                    Write-QOTicketsUILog ("Tickets: Assignee persist took {0} ms for {1} ticket(s)." -f $persistMs, $ids.Count) "WARN"
                } else {
                    Write-QOTicketsUILog ("Tickets: Assignee persist took {0} ms for {1} ticket(s)." -f $persistMs, $ids.Count)
                }
                $persisted = $true
            } catch {
                Write-QOTicketsUILog ("Tickets: Persisting assignee change failed. " + $_.Exception.Message) "ERROR"
            }
        }

        if (-not $persisted -and $effectiveUpdateCmd) {
            try {
                foreach ($item in $selectedItems) {
                    if ($null -eq $item) { continue }
                    $null = & $effectiveUpdateCmd -Ticket $item
                }
                $persisted = $true
            } catch {
                Write-QOTicketsUILog ("Tickets: Fallback assignee update failed. " + $_.Exception.Message) "ERROR"
            }
        }

        try {
            $detailsTicket = $null
            if ($selectedItems.Count -gt 0) { $detailsTicket = $selectedItems[0] }
            Refresh-QOTicketsAfterLocalMutation -Grid $effectiveGrid -PreferredDetailsTicket $detailsTicket
        } catch {
            Write-QOTicketsUILog ("Tickets: Local assignee refresh failed. " + $_.Exception.Message) "WARN"
        }

        return $persisted
    } catch {
        Write-QOTicketsUILog ("Tickets: Assignee change helper failed. " + $_.Exception.Message) "ERROR"
        try { if ($effectiveGrid.Items) { $effectiveGrid.Items.Refresh() } } catch { }
        return $false
    }
}

function Invoke-QOTicketPriorityChangeForItems {
    param(
        [AllowNull()][System.Windows.Controls.DataGrid]$Grid,
        [AllowNull()][object[]]$PreferredItems,
        [AllowNull()][string]$PriorityValue,
        [AllowNull()]$GetSelectedTicketsCmd,
        [AllowNull()]$SetPriorityCmd,
        [AllowNull()]$UpdateTicketCmd,
        [AllowNull()]$GetTicketsCmd,
        [AllowNull()][string]$View
    )

    try {
        $effectiveGrid = $Grid
        if (-not $effectiveGrid) {
            try { $effectiveGrid = $script:TicketsGrid } catch { $effectiveGrid = $null }
        }
        if (-not $effectiveGrid) {
            Write-QOTicketsUILog "Tickets: Priority change skipped because grid reference is unavailable." "WARN"
            return $false
        }

        $effectiveGetSelectedCmd = Resolve-QOTInvokable -Candidate $GetSelectedTicketsCmd -CommandName "Get-QOTSelectedTickets"
        $effectiveSetPriorityCmd = Resolve-QOTInvokable -Candidate $SetPriorityCmd -CommandName "Set-QOTicketsPriority"
        $effectiveUpdateCmd = Resolve-QOTInvokable -Candidate $UpdateTicketCmd -CommandName "Update-QOTicket"
        $effectiveGetTicketsCmd = Resolve-QOTInvokable -Candidate $GetTicketsCmd -CommandName "Get-QOTicketsByBucket"
        if (-not $effectiveGetTicketsCmd) { $effectiveGetTicketsCmd = Resolve-QOTInvokable -Candidate $null -CommandName "Get-QOTicketsByFolder" }
        if (-not $effectiveGetTicketsCmd) { $effectiveGetTicketsCmd = Resolve-QOTInvokable -Candidate $null -CommandName "Get-QOTickets" }

        $newPriority = ([string]($PriorityValue + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($newPriority)) { return $false }

        $selectedItems = @($PreferredItems | Where-Object { $null -ne $_ })
        if ($selectedItems.Count -eq 0) {
            if ($effectiveGetSelectedCmd) {
                try { $selectedItems = @(& $effectiveGetSelectedCmd -Grid $effectiveGrid -AllowContextFallback) } catch { $selectedItems = @() }
            }
            if ($selectedItems.Count -eq 0) {
                try { $selectedItems = @($effectiveGrid.SelectedItems | Where-Object { $null -ne $_ }) } catch { $selectedItems = @() }
            }
            if ($selectedItems.Count -eq 0) {
                try { if ($null -ne $effectiveGrid.SelectedItem) { $selectedItems = @($effectiveGrid.SelectedItem) } } catch { $selectedItems = @() }
            }
        }
        if ($selectedItems.Count -eq 0) { return $false }

        foreach ($item in $selectedItems) {
            if ($null -eq $item) { continue }
            try { $item.Priority = $newPriority } catch { }
        }
        $ids = @(
            $selectedItems |
                Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") } |
                ForEach-Object { $_.Id }
        )
        if ($ids.Count -eq 0) { return $false }

        $persisted = $false
        if ($effectiveSetPriorityCmd) {
            try {
                $persistSw = [System.Diagnostics.Stopwatch]::StartNew()
                $null = & $effectiveSetPriorityCmd -Id $ids -Priority $newPriority
                $persistSw.Stop()
                $persistMs = [math]::Round([double]$persistSw.Elapsed.TotalMilliseconds, 2)
                if ($persistMs -ge 400) {
                    Write-QOTicketsUILog ("Tickets: Priority persist took {0} ms for {1} ticket(s)." -f $persistMs, $ids.Count) "WARN"
                } else {
                    Write-QOTicketsUILog ("Tickets: Priority persist took {0} ms for {1} ticket(s)." -f $persistMs, $ids.Count)
                }
                $persisted = $true
            } catch {
                Write-QOTicketsUILog ("Tickets: Persisting priority change failed. " + $_.Exception.Message) "ERROR"
            }
        }

        if (-not $persisted -and $effectiveUpdateCmd) {
            try {
                foreach ($item in $selectedItems) {
                    if ($null -eq $item) { continue }
                    $null = & $effectiveUpdateCmd -Ticket $item
                }
                $persisted = $true
            } catch {
                Write-QOTicketsUILog ("Tickets: Fallback priority update failed. " + $_.Exception.Message) "ERROR"
            }
        }

        try {
            $detailsTicket = $null
            if ($selectedItems.Count -gt 0) { $detailsTicket = $selectedItems[0] }
            Refresh-QOTicketsAfterLocalMutation -Grid $effectiveGrid -PreferredDetailsTicket $detailsTicket
        } catch {
            Write-QOTicketsUILog ("Tickets: Local priority refresh failed. " + $_.Exception.Message) "WARN"
        }

        return $persisted
    } catch {
        Write-QOTicketsUILog ("Tickets: Priority change helper failed. " + $_.Exception.Message) "ERROR"
        return $false
    }
}

function Get-QOTCurrentAssigneeValue {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:TicketsCurrentAssigneeDisplayName)) {
        return [string]$script:TicketsCurrentAssigneeDisplayName
    }

    $candidateValues = New-Object System.Collections.Generic.List[string]

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction SilentlyContinue | Out-Null
        $currentPrincipal = [System.DirectoryServices.AccountManagement.UserPrincipal]::Current
        if ($currentPrincipal) {
            $displayName = ([string]$currentPrincipal.DisplayName).Trim()
            if (-not [string]::IsNullOrWhiteSpace($displayName)) {
                $candidateValues.Add($displayName) | Out-Null
            }
        }
    } catch { }

    $identityName = ""
    try { $identityName = ([string][System.Security.Principal.WindowsIdentity]::GetCurrent().Name).Trim() } catch { $identityName = "" }
    if (-not [string]::IsNullOrWhiteSpace($identityName)) {
        try {
            $domain = ""
            $user = ""
            if ($identityName.Contains("\")) {
                $parts = $identityName.Split("\")
                if ($parts.Length -ge 2) {
                    $domain = ([string]$parts[0]).Trim()
                    $user = ([string]$parts[$parts.Length - 1]).Trim()
                }
            } else {
                $user = $identityName
            }

            if (-not [string]::IsNullOrWhiteSpace($user)) {
                $safeDomain = $domain.Replace("'", "''")
                $safeUser = $user.Replace("'", "''")
                $fullName = ""
                if (-not [string]::IsNullOrWhiteSpace($safeDomain)) {
                    try {
                        $account = Get-CimInstance -ClassName Win32_UserAccount -Filter ("Name='{0}' AND Domain='{1}'" -f $safeUser, $safeDomain) -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($account) { $fullName = ([string]$account.FullName).Trim() }
                    } catch { }
                }
                if ([string]::IsNullOrWhiteSpace($fullName)) {
                    try {
                        $account = Get-CimInstance -ClassName Win32_UserAccount -Filter ("Name='{0}'" -f $safeUser) -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($account) { $fullName = ([string]$account.FullName).Trim() }
                    } catch { }
                }
                if (-not [string]::IsNullOrWhiteSpace($fullName)) {
                    $candidateValues.Add($fullName) | Out-Null
                }
                $candidateValues.Add($user) | Out-Null
            }
        } catch { }
    }

    try {
        $envUser = ([string][Environment]::UserName).Trim()
        if (-not [string]::IsNullOrWhiteSpace($envUser)) {
            $candidateValues.Add($envUser) | Out-Null
        }
    } catch { }

    foreach ($candidate in @($candidateValues)) {
        $value = ([string]($candidate + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($value -match '^(?i)(n/?a|null|unknown)$') { continue }
        $script:TicketsCurrentAssigneeDisplayName = $value
        return $value
    }

    $script:TicketsCurrentAssigneeDisplayName = "Me"
    return "Me"
}

function Update-QOTicketReadTracking {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()]$UpdateTicketCmd,
        [AllowNull()][string]$ReaderName
    )

    if (-not $Ticket -or -not $UpdateTicketCmd) { return }

    $readerValue = ([string]($ReaderName + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($readerValue)) {
        $readerValue = Get-QOTCurrentAssigneeValue
    }
    if ([string]::IsNullOrWhiteSpace($readerValue)) { return }

    $existingReaders = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $changed = $false

    try {
        if ($Ticket.PSObject.Properties.Name -contains "ReadBy") {
            $readBySource = $Ticket.ReadBy
            if ($readBySource -is [System.Collections.IEnumerable] -and $readBySource -isnot [string]) {
                foreach ($entry in @($readBySource)) {
                    $entryValue = ([string]($entry + "")).Trim()
                    if ([string]::IsNullOrWhiteSpace($entryValue)) { continue }
                    [void]$existingReaders.Add($entryValue)
                }
            } else {
                $entryValue = ([string]($readBySource + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($entryValue)) {
                    [void]$existingReaders.Add($entryValue)
                }
            }
        }
    } catch { }

    if (-not $existingReaders.Contains($readerValue)) {
        [void]$existingReaders.Add($readerValue)
        $changed = $true
    }

    if (-not $changed) { return }

    try {
        $sortedReaders = @($existingReaders | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object)
        if ($Ticket.PSObject.Properties.Name -contains "ReadBy") {
            $Ticket.ReadBy = @($sortedReaders)
        } else {
            $Ticket | Add-Member -NotePropertyName ReadBy -NotePropertyValue @($sortedReaders) -Force
        }

        $nowStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        if ($Ticket.PSObject.Properties.Name -contains "LastReadBy") {
            $Ticket.LastReadBy = $readerValue
        } else {
            $Ticket | Add-Member -NotePropertyName LastReadBy -NotePropertyValue $readerValue -Force
        }
        if ($Ticket.PSObject.Properties.Name -contains "LastReadAt") {
            $Ticket.LastReadAt = $nowStamp
        } else {
            $Ticket | Add-Member -NotePropertyName LastReadAt -NotePropertyValue $nowStamp -Force
        }

        $null = & $UpdateTicketCmd -Ticket $Ticket
    } catch {
        Write-QOTicketsUILog ("Tickets: Failed to persist reader metadata: " + $_.Exception.Message) "WARN"
    }
}

function Test-QOTProcessElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Set-QOTicketsSyncStatus {
    param(
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText,
        [string]$Message
    )

    if (-not $StatusText) { return }
    $messageText = ""
    try { $messageText = ([string]($Message + "")).Trim() } catch { $messageText = "" }
    if (-not [string]::IsNullOrWhiteSpace($messageText)) {
        try { $script:TicketsLastSyncStatusMessage = $messageText } catch { }
    }

    $displayLabel = Get-QOTicketsLastSuccessfulSyncLabel

    if (-not $script:TicketsShowSyncStatus) {
        try {
            if ($StatusText.Dispatcher.CheckAccess()) {
                $StatusText.Visibility = "Collapsed"
                $StatusText.Text = ""
                $StatusText.ToolTip = $null
            } else {
                $StatusText.Dispatcher.Invoke([action]{
                    $StatusText.Visibility = "Collapsed"
                    $StatusText.Text = ""
                    $StatusText.ToolTip = $null
                })
            }
        } catch { }
        return
    }

    $displayState = $null
    try {
        $displayState = Get-QOTicketsSyncStatusDisplayState -DisplayLabel $displayLabel -Message $messageText
    } catch {
        $displayState = [pscustomobject]@{
            Text    = $displayLabel
            ToolTip = $null
        }
    }

    $visibleText = $displayLabel
    $toolTipText = $null
    try { if ($displayState -and $displayState.PSObject.Properties.Name -contains "Text") { $visibleText = [string]$displayState.Text } } catch { $visibleText = $displayLabel }
    try { if ($displayState -and $displayState.PSObject.Properties.Name -contains "ToolTip") { $toolTipText = $displayState.ToolTip } } catch { $toolTipText = $null }

    if ([string]::IsNullOrWhiteSpace($toolTipText)) {
        $toolTipText = $displayLabel
    }

    try {
        if ($StatusText.Dispatcher.CheckAccess()) {
            $StatusText.Visibility = "Visible"
            $StatusText.Text = $visibleText
            $StatusText.ToolTip = $toolTipText
        } else {
            $StatusText.Dispatcher.Invoke([action]{
                $StatusText.Visibility = "Visible"
                $StatusText.Text = $visibleText
                $StatusText.ToolTip = $toolTipText
            })
        }
    } catch { }
}

function Show-QOTicketsOpenPulse {
    param(
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText,
        [Parameter(Mandatory)][string]$Message,
        [int]$DurationMilliseconds = 2200
    )

    if (-not $StatusText) { return }

    $showNow = {
        try {
            $StatusText.Text = $Message
            $StatusText.Visibility = "Visible"
        } catch { }
    }.GetNewClosure()

    $restoreLater = {
        try {
            if ($script:TicketsShowSyncStatus) {
                Set-QOTicketsSyncStatus -StatusText $StatusText -Message $null
            } else {
                $StatusText.Text = ""
                $StatusText.Visibility = "Collapsed"
                $StatusText.ToolTip = $null
            }
        } catch { }
    }.GetNewClosure()

    try {
        if ($StatusText.Dispatcher.CheckAccess()) {
            & $showNow
            if ($script:TicketsOpenPulseTimer) {
                try { $script:TicketsOpenPulseTimer.Stop() } catch { }
                $script:TicketsOpenPulseTimer = $null
            }
            $timer = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [TimeSpan]::FromMilliseconds([math]::Max(500, $DurationMilliseconds))
            $timer.Add_Tick({
                try { $timer.Stop() } catch { }
                $script:TicketsOpenPulseTimer = $null
                & $restoreLater
            }.GetNewClosure())
            $script:TicketsOpenPulseTimer = $timer
            $script:TicketsOpenPulseTimer.Start()
        } else {
            $StatusText.Dispatcher.BeginInvoke([action]{
                try { & $showNow } catch { }
            }, [System.Windows.Threading.DispatcherPriority]::Normal) | Out-Null
        }
    } catch { }
}

function Get-QOTicketDedupKey {
    param([Parameter(Mandatory)]$Ticket)

    try {
        if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") {
            $id = ([string]$Ticket.SourceMessageId).Trim()
            if ($id) { return ("msg:" + $id.ToLowerInvariant()) }
        }
    } catch { }

    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailMessageId") {
            $id = ([string]$Ticket.EmailMessageId).Trim()
            if ($id) { return ("msg:" + $id.ToLowerInvariant()) }
        }
    } catch { }

    $subject = ""
    $received = ""
    try { if ($Ticket.PSObject.Properties.Name -contains "Subject") { $subject = ([string]$Ticket.Subject).Trim().ToLowerInvariant() } } catch { }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailReceived") {
            $received = ([string]$Ticket.EmailReceived).Trim().ToLowerInvariant()
        } elseif ($Ticket.PSObject.Properties.Name -contains "CreatedAt") {
            $received = ([string]$Ticket.CreatedAt).Trim().ToLowerInvariant()
        }
    } catch { }

    if (-not $subject -and -not $received) { return "" }
    return ("hash:{0}|{1}" -f $subject, $received)
}

function Get-QOTicketSelectionKey {
    param([AllowNull()]$Ticket)

    if (-not $Ticket) { return "" }

    $key = ""
    try { $key = [string](Get-QOTicketDedupKey -Ticket $Ticket) } catch { $key = "" }
    if (-not [string]::IsNullOrWhiteSpace($key)) { return $key }

    try {
        if ($Ticket.PSObject.Properties.Name -contains "Id") {
            $id = ([string]$Ticket.Id).Trim()
            if ($id) { return ("id:" + $id) }
        }
    } catch { }

    try {
        $subjectPart = ""
        $createdPart = ""
        if ($Ticket.PSObject.Properties.Name -contains "Subject") { $subjectPart = [string]$Ticket.Subject }
        if ($Ticket.PSObject.Properties.Name -contains "CreatedAt") { $createdPart = [string]$Ticket.CreatedAt }
        $key = ("fallback:{0}|{1}" -f $subjectPart, $createdPart).Trim('|')
        if ($key -ne "fallback:") { return $key }
    } catch { }

    try { return ("ref:" + [string][System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Ticket)) } catch { }
    return ""
}

function Get-QOTicketLogLabel {
    param([AllowNull()]$Ticket)

    if (-not $Ticket) { return "Ticket=(null)" }

    $idValue = ""
    $subjectValue = ""
    try {
        if ($Ticket.PSObject.Properties.Name -contains "Id") {
            $idValue = ([string]$Ticket.Id).Trim()
        }
    } catch { $idValue = "" }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "Subject") {
            $subjectValue = ([string]$Ticket.Subject).Trim()
        } elseif ($Ticket.PSObject.Properties.Name -contains "TicketName") {
            $subjectValue = ([string]$Ticket.TicketName).Trim()
        }
    } catch { $subjectValue = "" }

    if ([string]::IsNullOrWhiteSpace($subjectValue)) { $subjectValue = "(no subject)" }
    if ([string]::IsNullOrWhiteSpace($idValue)) { $idValue = "(no id)" }
    return ("Id={0}; Subject={1}" -f $idValue, $subjectValue)
}

function Merge-QOTicketsIntoGridCollection {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [object[]]$IncomingTickets,
        [AllowNull()][System.Collections.Generic.HashSet[string]]$ExistingKeys,
        [switch]$SkipFilterRefresh
    )

    if (-not $Grid -or -not $IncomingTickets -or $IncomingTickets.Count -eq 0) { return 0 }

    if (-not $script:AllTickets) {
        $script:AllTickets = @(Get-QOTicketsAllItems)
    }

    $localExistingKeys = $ExistingKeys
    if (-not $localExistingKeys) {
        $localExistingKeys = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($ticket in @($script:AllTickets)) {
            if (-not $ticket) { continue }
            $key = Get-QOTicketDedupKey -Ticket $ticket
            if ($key) { [void]$localExistingKeys.Add($key) }
        }
    }

    $addedCount = 0
    foreach ($ticket in @($IncomingTickets)) {
        if (-not $ticket) { continue }
        $key = Get-QOTicketDedupKey -Ticket $ticket
        if ($key -and $localExistingKeys.Contains($key)) { continue }

        $script:AllTickets += @($ticket)
        if ($key) { [void]$localExistingKeys.Add($key) }

        $visible = @(Get-QOTicketsVisibleItems -Items @($ticket) -FilterState ([pscustomobject]@{
            ShowOpen             = [bool]$script:ShowOpen
            ShowClosed           = [bool]$script:ShowClosed
            ShowDeleted          = [bool]$script:ShowDeleted
            SortMode             = [string]$script:TicketsSortMode
        }))

        if ($visible.Count -gt 0) {
            $itemsSource = $Grid.ItemsSource
            if ($itemsSource -is [System.Collections.ObjectModel.ObservableCollection[object]]) {
                # Use lock to prevent concurrent modification race condition
                [System.Threading.Monitor]::Enter($script:TicketsGridItemsSourceLock)
                try {
                    $itemsSource.Add($ticket) | Out-Null
                } finally {
                    [System.Threading.Monitor]::Exit($script:TicketsGridItemsSourceLock)
                }
            } else {
                Invoke-QOTicketsFilterSafely -ForceRefresh -Grid $Grid
            }
        }
        $addedCount++
    }

    if ($addedCount -gt 0 -and (-not $SkipFilterRefresh)) {
        # Keep live ordering correct while tickets stream in.
        Invoke-QOTicketsFilterSafely -ForceRefresh -Grid $Grid
    }

    return $addedCount
}

function Stop-QOTicketsIncrementalMerge {
    try {
        if ($script:TicketsIncrementalMergeTimer -and $script:TicketsIncrementalMergeTickHandler) {
            try { $script:TicketsIncrementalMergeTimer.Remove_Tick($script:TicketsIncrementalMergeTickHandler) } catch { }
        }
        if ($script:TicketsIncrementalMergeTimer) {
            try { $script:TicketsIncrementalMergeTimer.Stop() } catch { }
        }
    } catch { }

    $script:TicketsIncrementalMergeTimer = $null
    $script:TicketsIncrementalMergeTickHandler = $null
    $script:TicketsIncrementalMergeQueue = $null
    $script:TicketsIncrementalMergeExistingKeys = $null
    $script:TicketsIncrementalMergeProcessed = 0
    $script:TicketsIncrementalMergeAdded = 0
    $script:TicketsIncrementalMergeNeedsRefresh = $false
}

function Start-QOTicketsIncrementalMerge {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [object[]]$IncomingTickets,
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText
    )

    $ticketsToQueue = @($IncomingTickets | Where-Object { $null -ne $_ })
    if ($ticketsToQueue.Count -eq 0) { return 0 }

    $queueWasRunning = $false
    try {
        $queueWasRunning = [bool]($script:TicketsIncrementalMergeTimer -and $script:TicketsIncrementalMergeTimer.IsEnabled)
    } catch { $queueWasRunning = $false }

    if (-not $script:TicketsIncrementalMergeQueue -or (-not $queueWasRunning)) {
        $script:TicketsIncrementalMergeQueue = New-Object 'System.Collections.Generic.Queue[object]'
    }

    if (-not $queueWasRunning) {
        $script:TicketsIncrementalMergeProcessed = 0
        $script:TicketsIncrementalMergeAdded = 0
        $script:TicketsIncrementalMergeNeedsRefresh = $false
        $script:TicketsIncrementalMergeExistingKeys = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($existingTicket in @($script:AllTickets)) {
            if (-not $existingTicket) { continue }
            $existingKey = Get-QOTicketDedupKey -Ticket $existingTicket
            if ($existingKey) { [void]$script:TicketsIncrementalMergeExistingKeys.Add($existingKey) }
        }
    }

    foreach ($ticket in $ticketsToQueue) {
        try { $script:TicketsIncrementalMergeQueue.Enqueue($ticket) } catch { }
    }

    if ($queueWasRunning) {
        return [int]$ticketsToQueue.Count
    }

    $script:TicketsIncrementalMergeTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:TicketsIncrementalMergeTimer.Interval = [TimeSpan]::FromMilliseconds(85)
    $refreshFilter = Get-Command Invoke-QOTicketsFilterSafely -CommandType Function -ErrorAction Stop
    $writeLog = Get-Command Write-QOTicketsUILog -CommandType Function -ErrorAction Stop
    $setSyncStatus = Get-Command Set-QOTicketsSyncStatus -CommandType Function -ErrorAction Stop
    $getLastSyncLabel = Get-Command Get-QOTicketsLastSuccessfulSyncLabel -CommandType Function -ErrorAction Stop
    $stopIncrementalMerge = Get-Command Stop-QOTicketsIncrementalMerge -CommandType Function -ErrorAction Stop
    $mergeIntoGrid = Get-Command Merge-QOTicketsIntoGridCollection -CommandType Function -ErrorAction Stop

    $script:TicketsIncrementalMergeTickHandler = {
        try {
            if (-not $script:TicketsIncrementalMergeQueue -or $script:TicketsIncrementalMergeQueue.Count -le 0) {
                if ($script:TicketsIncrementalMergeNeedsRefresh) {
                    try { & $refreshFilter -ForceRefresh -Grid $Grid } catch { }
                    $script:TicketsIncrementalMergeNeedsRefresh = $false
                }

                $processed = [int]$script:TicketsIncrementalMergeProcessed
                $added = [int]$script:TicketsIncrementalMergeAdded
                & $writeLog ("Tickets: Incremental merge completed. Processed={0} Added={1}" -f $processed, $added)
                & $setSyncStatus -StatusText $StatusText -Message (& $getLastSyncLabel)
                & $stopIncrementalMerge
                return
            }

            $nextTicket = $null
            try { $nextTicket = $script:TicketsIncrementalMergeQueue.Dequeue() } catch { $nextTicket = $null }
            if (-not $nextTicket) { return }

            $merged = 0
            try {
                $merged = [int](& $mergeIntoGrid -Grid $Grid -IncomingTickets @($nextTicket) -ExistingKeys $script:TicketsIncrementalMergeExistingKeys -SkipFilterRefresh)
            } catch { $merged = 0 }

            $script:TicketsIncrementalMergeProcessed = [int]$script:TicketsIncrementalMergeProcessed + 1
            if ($merged -gt 0) {
                $script:TicketsIncrementalMergeAdded = [int]$script:TicketsIncrementalMergeAdded + $merged
                $script:TicketsIncrementalMergeNeedsRefresh = $true
            }

            $queueRemaining = 0
            try { $queueRemaining = [int]$script:TicketsIncrementalMergeQueue.Count } catch { $queueRemaining = 0 }
            $processedNow = [int]$script:TicketsIncrementalMergeProcessed

            if ($script:TicketsIncrementalMergeNeedsRefresh -and (($processedNow % 4 -eq 0) -or ($queueRemaining -eq 0))) {
                try { & $refreshFilter -ForceRefresh -Grid $Grid } catch { }
                $script:TicketsIncrementalMergeNeedsRefresh = $false
            }

            if ($queueRemaining -gt 0) {
                $total = $processedNow + $queueRemaining
                & $setSyncStatus -StatusText $StatusText -Message ("Updating tickets {0}/{1}..." -f $processedNow, $total)
            }
        } catch {
            & $writeLog ("Tickets: Incremental merge tick failed. " + $_.Exception.Message) "WARN"
            & $stopIncrementalMerge
        }
    }.GetNewClosure()

    $script:TicketsIncrementalMergeTimer.Add_Tick($script:TicketsIncrementalMergeTickHandler)
    $script:TicketsIncrementalMergeTimer.Start()
    return [int]$ticketsToQueue.Count
}

function Get-QOTicketsSyncBackoffSeconds {
    param([int]$FailureCount)

    if ($FailureCount -lt 1) { return 300 }

    switch ([math]::Min([int]$FailureCount, 3)) {
        1 { return 15 }
        2 { return 30 }
        default { return 60 }
    }
}

function Get-QOTicketsSyncSuccessPollSeconds {
    return 300
}

function Test-QOTicketsSyncFailureLooksRecoverable {
    param([AllowNull()][string]$Note)

    $noteText = ""
    try { $noteText = ([string]($Note + "")).Trim() } catch { $noteText = "" }
    if ([string]::IsNullOrWhiteSpace($noteText)) { return $true }

    return ($noteText -match '(?i)outlook|classic outlook|mapi|com unavailable|could not attach|not running|returned nothing|timed out|timeout|no output|startup|attach|rpc|call was rejected')
}

function Get-QOTicketsSyncRetryDelayLabel {
    param(
        [datetime]$NextAttemptUtc
    )

    try {
        $remainingSeconds = [int][math]::Ceiling(($NextAttemptUtc - (Get-Date).ToUniversalTime()).TotalSeconds)
        if ($remainingSeconds -lt 1) { return "now" }
        if ($remainingSeconds -lt 120) { return ("{0}s" -f $remainingSeconds) }
        return ("{0}m" -f [math]::Ceiling($remainingSeconds / 60.0))
    } catch {
        return "soon"
    }
}

function Get-QOTicketsSyncRecoveringStatusMessage {
    param(
        [AllowNull()][datetime]$NextAttemptUtc = $script:TicketsSyncNextAttemptUtc
    )

    $delayLabel = Get-QOTicketsSyncRetryDelayLabel -NextAttemptUtc $NextAttemptUtc
    if ($delayLabel -eq "now") {
        return "Open Outlook to enable ticket sync... retrying now"
    }

    return ("Open Outlook to enable ticket sync... retry in {0}" -f $delayLabel)
}

function Convert-QOTicketsSyncResultObject {
    param(
        [AllowNull()]$RawResult,
        [bool]$TimedOut = $false,
        [string]$DefaultNote = ""
    )

    if ($TimedOut) {
        return [pscustomobject]@{
            TimedOut    = $true
            Success     = $false
            Note        = (if ([string]::IsNullOrWhiteSpace($DefaultNote)) { "Outlook sync timed out." } else { $DefaultNote })
            Added       = 0
            Updated     = 0
            AddedTickets = @()
        }
    }

    if (-not $RawResult) {
        $note = if ([string]::IsNullOrWhiteSpace($DefaultNote)) { "Outlook sync returned nothing." } else { $DefaultNote }
        return [pscustomobject]@{
            TimedOut    = $false
            Success     = $false
            Note        = $note
            Added       = 0
            Updated     = 0
            AddedTickets = @()
        }
    }

    $note = ""
    $added = 0
    $updated = 0
    $addedTickets = @()
    $success = $true

    try { if ($RawResult.PSObject.Properties.Name -contains "Note") { $note = [string]$RawResult.Note } } catch { $note = "" }
    try { if ($RawResult.PSObject.Properties.Name -contains "Added") { $added = [int]$RawResult.Added } } catch { $added = 0 }
    try { if ($RawResult.PSObject.Properties.Name -contains "Updated") { $updated = [int]$RawResult.Updated } } catch { $updated = 0 }
    try { if ($RawResult.PSObject.Properties.Name -contains "AddedTickets") { $addedTickets = @($RawResult.AddedTickets) } } catch { $addedTickets = @() }
    try {
        if ($RawResult.PSObject.Properties.Name -contains "Success") {
            $success = [bool]$RawResult.Success
        }
        elseif ($note -match '(?i)\b(failed|unavailable|not loaded|not found|required)\b') {
            $success = $false
        }
    } catch { $success = $false }

    if ([string]::IsNullOrWhiteSpace($note) -and -not [string]::IsNullOrWhiteSpace($DefaultNote)) {
        $note = $DefaultNote
    }

    return [pscustomobject]@{
        TimedOut    = $false
        Success     = $success
        Note        = $note
        Added       = $added
        Updated     = $updated
        AddedTickets = @($addedTickets)
    }
}

function ConvertFrom-QOTRunnerJson {
    param(
        [Parameter(Mandatory)][string]$RawOutput
    )

    try {
        return ($RawOutput | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        $startIndex = $RawOutput.IndexOf('{')
        $endIndex = $RawOutput.LastIndexOf('}')
        if ($startIndex -ge 0 -and $endIndex -gt $startIndex) {
            $jsonCandidate = $RawOutput.Substring($startIndex, ($endIndex - $startIndex + 1)).Trim()
            if (-not [string]::IsNullOrWhiteSpace($jsonCandidate)) {
                return ($jsonCandidate | ConvertFrom-Json -ErrorAction Stop)
            }
        }
        throw
    }
}

function ConvertTo-QOTSingleQuotedLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return "''" }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function ConvertTo-QOTProcessArgumentString {
    param(
        [AllowNull()][object[]]$Arguments
    )

    $items = @(
        foreach ($argument in @($Arguments)) {
            if ($null -eq $argument) { "" } else { [string]$argument }
        }
    )

    if ($items.Count -eq 0) { return "" }

    $scriptPath = ""
    $invocationArgs = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $items.Count; $i++) {
        $token = [string]$items[$i]
        switch -Regex ($token) {
            '^-NoLogo$' { continue }
            '^-NoProfile$' { continue }
            '^-STA$' { continue }
            '^-WindowStyle$' {
                if (($i + 1) -lt $items.Count) { $i++ }
                continue
            }
            '^-ExecutionPolicy$' {
                if (($i + 1) -lt $items.Count) { $i++ }
                continue
            }
            '^-File$' {
                if (($i + 1) -ge $items.Count) {
                    throw "PowerShell launch arguments are missing the script path after -File."
                }
                $scriptPath = [string]$items[$i + 1]
                $i++
                continue
            }
            default {
                $invocationArgs.Add($token) | Out-Null
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw "PowerShell launch arguments are missing a -File script path."
    }

    $commandParts = New-Object System.Collections.Generic.List[string]
    $commandParts.Add('&') | Out-Null
    $commandParts.Add((ConvertTo-QOTSingleQuotedLiteral -Value $scriptPath)) | Out-Null

    for ($i = 0; $i -lt $invocationArgs.Count; $i++) {
        $token = [string]$invocationArgs[$i]
        if ($token.StartsWith('-')) {
            $commandParts.Add($token) | Out-Null
            if (($i + 1) -lt $invocationArgs.Count) {
                $nextToken = [string]$invocationArgs[$i + 1]
                if (-not $nextToken.StartsWith('-')) {
                    $commandParts.Add((ConvertTo-QOTSingleQuotedLiteral -Value $nextToken)) | Out-Null
                    $i++
                }
            }
            continue
        }

        $commandParts.Add((ConvertTo-QOTSingleQuotedLiteral -Value $token)) | Out-Null
    }

    $scriptText = @(
        '$ErrorActionPreference = ''Stop'''
        ($commandParts -join ' ')
        'exit $LASTEXITCODE'
    ) -join "`r`n"

    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptText))
    return ('-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -EncodedCommand {0}' -f $encodedCommand)
}

function ConvertTo-QOTBatchQuotedPath {
    param([AllowNull()][string]$Value)

    $pathValue = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($pathValue)) { return '""' }
    return '"' + $pathValue.Replace('"', '') + '"'
}

function Remove-QOTLimitedScheduledProcessArtifacts {
    param(
        [AllowNull()][string]$TaskName,
        [AllowNull()][string]$CommandPath
    )

    $taskValue = ([string]($TaskName + "")).Trim()
    if (-not [string]::IsNullOrWhiteSpace($taskValue)) {
        try {
            $null = & schtasks.exe /Delete /TN $taskValue /F 2>$null
        } catch { }
    }

    $commandValue = ([string]($CommandPath + "")).Trim()
    if (-not [string]::IsNullOrWhiteSpace($commandValue)) {
        try {
            if (Test-Path -LiteralPath $commandValue) {
                Remove-Item -LiteralPath $commandValue -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }
}

function Start-QOTLimitedScheduledProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [AllowNull()][string]$ArgumentString,
        [AllowNull()][string]$WorkingDirectory,
        [AllowNull()][string]$TaskNamePrefix = "QOTRunner"
    )

    $exeValue = ([string]($FilePath + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($exeValue)) { throw "Runner executable path is required." }

    $workDirValue = ([string]($WorkingDirectory + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($workDirValue) -or -not (Test-Path -LiteralPath $workDirValue)) {
        $workDirValue = $env:TEMP
    }

    $prefixValue = ([string]($TaskNamePrefix + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($prefixValue)) { $prefixValue = "QOTRunner" }
    $prefixValue = ($prefixValue -replace '[^A-Za-z0-9_-]', '')
    if ([string]::IsNullOrWhiteSpace($prefixValue)) { $prefixValue = "QOTRunner" }

    $taskName = "{0}-{1}" -f $prefixValue, ([guid]::NewGuid().ToString("N"))
    $commandPath = Join-Path $env:TEMP ("{0}_{1}.cmd" -f $prefixValue, ([guid]::NewGuid().ToString("N")))
    $exitPath = Join-Path $env:TEMP ("{0}_{1}.exit" -f $prefixValue, ([guid]::NewGuid().ToString("N")))

    $quotedExe = ConvertTo-QOTBatchQuotedPath -Value $exeValue
    $quotedWorkDir = ConvertTo-QOTBatchQuotedPath -Value $workDirValue
    $quotedExitPath = ConvertTo-QOTBatchQuotedPath -Value $exitPath
    $argumentValue = ([string]($ArgumentString + "")).Trim()
    $argumentSuffix = ""
    if (-not [string]::IsNullOrWhiteSpace($argumentValue)) {
        $argumentSuffix = " " + $argumentValue
    }
    $runLine = $quotedExe + $argumentSuffix

    $batchLines = @(
        "@echo off",
        ("cd /d " + $quotedWorkDir),
        $runLine,
        'set "QOT_EXIT=%ERRORLEVEL%"',
        ("echo %QOT_EXIT%>" + $quotedExitPath),
        ("schtasks.exe /Delete /TN " + (ConvertTo-QOTBatchQuotedPath -Value $taskName) + " /F >nul 2>&1"),
        'del "%~f0" >nul 2>&1',
        'exit /b %QOT_EXIT%'
    )

    try {
        $batchLines | Set-Content -LiteralPath $commandPath -Encoding ASCII -Force

        $service = New-Object -ComObject Schedule.Service
        $service.Connect()
        $rootFolder = $service.GetFolder("\")
        $taskDefinition = $service.NewTask(0)
        $taskDefinition.RegistrationInfo.Description = "Quinn Optimiser Toolkit elevated bridge runner"
        $taskDefinition.Principal.UserId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $taskDefinition.Principal.LogonType = 3
        $taskDefinition.Principal.RunLevel = 0
        $taskDefinition.Settings.Enabled = $true
        $taskDefinition.Settings.Hidden = $true
        $taskDefinition.Settings.ExecutionTimeLimit = "PT10M"
        $taskDefinition.Settings.DisallowStartIfOnBatteries = $false
        $taskDefinition.Settings.StopIfGoingOnBatteries = $false

        $action = $taskDefinition.Actions.Create(0)
        $action.Path = $env:ComSpec
        $action.Arguments = ('/d /c ' + (ConvertTo-QOTBatchQuotedPath -Value $commandPath))
        $action.WorkingDirectory = $workDirValue

        $registeredTask = $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3, $null)
        $null = $registeredTask.Run($null)

        return [pscustomobject]@{
            TaskName    = $taskName
            CommandPath = $commandPath
            ExitPath    = $exitPath
        }
    } catch {
        $failureMessage = $_.Exception.Message
        Remove-QOTLimitedScheduledProcessArtifacts -TaskName $taskName -CommandPath $commandPath
        try { if (Test-Path -LiteralPath $exitPath) { Remove-Item -LiteralPath $exitPath -Force -ErrorAction SilentlyContinue } } catch { }
        throw ("Limited scheduled runner launch failed: " + $failureMessage)
    }
}

function Read-QOTicketsReplyRunnerResult {
    param(
        [AllowNull()][string]$ResultPath,
        [AllowNull()][string]$StdOutPath,
        [AllowNull()][string]$StdErrPath
    )

    $rawOutput = ""
    $rawError = ""

    try {
        if (-not [string]::IsNullOrWhiteSpace($ResultPath) -and (Test-Path -LiteralPath $ResultPath)) {
            $rawOutput = [string](Get-Content -LiteralPath $ResultPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawOutput = "" }
    try {
        if ([string]::IsNullOrWhiteSpace($rawOutput) -and -not [string]::IsNullOrWhiteSpace($StdOutPath) -and (Test-Path -LiteralPath $StdOutPath)) {
            $rawOutput = [string](Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawOutput = "" }
    try {
        if (-not [string]::IsNullOrWhiteSpace($StdErrPath) -and (Test-Path -LiteralPath $StdErrPath)) {
            $rawError = [string](Get-Content -LiteralPath $StdErrPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawError = "" }

    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        $note = "Reply runner returned no output."
        if (-not [string]::IsNullOrWhiteSpace($rawError)) {
            $note = ([string]$rawError).Trim()
        }
        return [pscustomobject]@{ Success = $false; Note = $note }
    }

    try {
        $parsed = ConvertFrom-QOTRunnerJson -RawOutput $rawOutput
    } catch {
        $parsePreview = ([string]$rawOutput).Trim()
        if ($parsePreview.Length -gt 220) {
            $parsePreview = $parsePreview.Substring(0, 220) + "..."
        }
        return [pscustomobject]@{
            Success = $false
            Note    = ("Reply runner output parse failed: " + $_.Exception.Message + " | " + $parsePreview)
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

function Read-QOTicketsBackgroundActionRunnerResult {
    param(
        [AllowNull()][string]$ResultPath,
        [AllowNull()][string]$StdOutPath,
        [AllowNull()][string]$StdErrPath
    )

    $rawOutput = ""
    $rawError = ""

    try {
        if (-not [string]::IsNullOrWhiteSpace($ResultPath) -and (Test-Path -LiteralPath $ResultPath)) {
            $rawOutput = [string](Get-Content -LiteralPath $ResultPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawOutput = "" }
    try {
        if ([string]::IsNullOrWhiteSpace($rawOutput) -and -not [string]::IsNullOrWhiteSpace($StdOutPath) -and (Test-Path -LiteralPath $StdOutPath)) {
            $rawOutput = [string](Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawOutput = "" }
    try {
        if (-not [string]::IsNullOrWhiteSpace($StdErrPath) -and (Test-Path -LiteralPath $StdErrPath)) {
            $rawError = [string](Get-Content -LiteralPath $StdErrPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawError = "" }

    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        $note = "Background action runner returned no output."
        if (-not [string]::IsNullOrWhiteSpace($rawError)) {
            $note = ([string]$rawError).Trim()
        }
        return [pscustomobject]@{
            Success = $false
            Note    = $note
        }
    }

    try {
        $parsed = ConvertFrom-QOTRunnerJson -RawOutput $rawOutput
    } catch {
        $parsePreview = ([string]$rawOutput).Trim()
        if ($parsePreview.Length -gt 220) {
            $parsePreview = $parsePreview.Substring(0, 220) + "..."
        }
        return [pscustomobject]@{
            Success = $false
            Note    = ("Background action runner output parse failed: " + $_.Exception.Message + " | " + $parsePreview)
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
        try { $parsed | Add-Member -NotePropertyName Success -NotePropertyValue $success -Force } catch { }
    }
    if ($parsed.PSObject.Properties.Name -notcontains "Note") {
        try { $parsed | Add-Member -NotePropertyName Note -NotePropertyValue $note -Force } catch { }
    }

    return $parsed
}

function Test-QOTicketsReplyOperationCompleted {
    param(
        [AllowNull()]$AsyncResult = $script:TicketsReplyAsyncResult,
        [AllowNull()][string]$Mode = $script:TicketsReplyMode,
        [AllowNull()][string]$ResultPath = $script:TicketsReplyRunnerResultPath
    )

    $modeValue = ([string]($Mode + "")).Trim().ToLowerInvariant()
    switch ($modeValue) {
        "result-file" {
            $resultPathValue = ([string]($ResultPath + "")).Trim()
            if ([string]::IsNullOrWhiteSpace($resultPathValue)) { return $false }
            try {
                if (-not (Test-Path -LiteralPath $resultPathValue)) { return $false }
                $resultInfo = Get-Item -LiteralPath $resultPathValue -ErrorAction Stop
                return ($resultInfo.Length -gt 0)
            } catch {
                return $false
            }
        }
        default {
            if (-not $AsyncResult) { return $false }
            try { return [bool]$AsyncResult.IsCompleted } catch { return $false }
        }
    }
}

function Read-QOTicketsSyncRunnerResult {
    param(
        [AllowNull()][string]$ResultPath,
        [AllowNull()][string]$StdOutPath,
        [AllowNull()][string]$StdErrPath
    )

    $rawOutput = ""
    $rawError = ""

    try {
        if (-not [string]::IsNullOrWhiteSpace($ResultPath) -and (Test-Path -LiteralPath $ResultPath)) {
            $rawOutput = [string](Get-Content -LiteralPath $ResultPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawOutput = "" }
    try {
        if ([string]::IsNullOrWhiteSpace($rawOutput) -and -not [string]::IsNullOrWhiteSpace($StdOutPath) -and (Test-Path -LiteralPath $StdOutPath)) {
            $rawOutput = [string](Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawOutput = "" }
    try {
        if (-not [string]::IsNullOrWhiteSpace($StdErrPath) -and (Test-Path -LiteralPath $StdErrPath)) {
            $rawError = [string](Get-Content -LiteralPath $StdErrPath -Raw -ErrorAction SilentlyContinue)
        }
    } catch { $rawError = "" }

    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        $note = "Outlook sync returned no output."
        if (-not [string]::IsNullOrWhiteSpace($rawError)) {
            $note = ([string]$rawError).Trim()
        }
        return (Convert-QOTicketsSyncResultObject -RawResult $null -DefaultNote $note)
    }

    try {
        $parsed = ConvertFrom-QOTRunnerJson -RawOutput $rawOutput
        return (Convert-QOTicketsSyncResultObject -RawResult $parsed)
    } catch {
        $parsePreview = ([string]$rawOutput).Trim()
        if ($parsePreview.Length -gt 220) {
            $parsePreview = $parsePreview.Substring(0, 220) + "..."
        }
        return (Convert-QOTicketsSyncResultObject -RawResult $null -DefaultNote ("Outlook sync output parse failed: " + $_.Exception.Message + " | " + $parsePreview))
    }
}

function Test-QOTicketsSyncOperationCompleted {
    param(
        [AllowNull()]$Process = $script:TicketsSyncProcess,
        [AllowNull()]$AsyncResult = $script:TicketsSyncAsyncResult,
        [AllowNull()][string]$Mode = $script:TicketsSyncMode,
        [AllowNull()][string]$ResultPath = $script:TicketsSyncRunnerResultPath
    )

    $modeValue = ([string]($Mode + "")).Trim().ToLowerInvariant()
    switch ($modeValue) {
        "child-process" {
            if (-not $Process) { return $false }
            try { return [bool]$Process.HasExited } catch { return $false }
        }
        "result-file" {
            $resultPathValue = ([string]($ResultPath + "")).Trim()
            if ([string]::IsNullOrWhiteSpace($resultPathValue)) { return $false }
            try {
                if (-not (Test-Path -LiteralPath $resultPathValue)) { return $false }
                $resultInfo = Get-Item -LiteralPath $resultPathValue -ErrorAction Stop
                return ($resultInfo.Length -gt 0)
            } catch {
                return $false
            }
        }
        default {
            if (-not $AsyncResult) { return $false }
            try { return [bool]$AsyncResult.IsCompleted } catch { return $false }
        }
    }
}

function Stop-QOTicketsSyncExecution {
    param(
        [switch]$StopActiveOperation
    )

    try {
        if ($script:TicketsSyncCompletionTimer) {
            try { $script:TicketsSyncCompletionTimer.Stop() } catch { }
        }
    } catch { }

    try {
        if ($script:TicketsSyncMode -eq "child-process") {
            if ($script:TicketsSyncProcess) {
                if ($StopActiveOperation) {
                    try {
                        if (-not $script:TicketsSyncProcess.HasExited) {
                            $script:TicketsSyncProcess.Kill()
                            try { $null = $script:TicketsSyncProcess.WaitForExit(5000) } catch { }
                        }
                    } catch { }
                }
                try { $script:TicketsSyncProcess.Dispose() } catch { }
            }
        }
        else {
            if ($script:TicketsSyncPowerShell) {
                if ($StopActiveOperation) {
                    try { $script:TicketsSyncPowerShell.Stop() } catch { }
                }
                try { $script:TicketsSyncPowerShell.Dispose() } catch { }
            }
            if ($script:TicketsSyncRunspace) {
                try { $script:TicketsSyncRunspace.Dispose() } catch { }
            }
        }
    } catch { }
}

function Clear-QOTicketsSyncExecutionState {
    param(
        [switch]$RemoveRunnerFiles
    )

    if ($RemoveRunnerFiles) {
        foreach ($path in @($script:TicketsSyncRunnerStdOutPath, $script:TicketsSyncRunnerStdErrPath, $script:TicketsSyncRunnerResultPath, $script:TicketsSyncRunnerCommandPath)) {
            if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
            try {
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        }
        try { Remove-QOTLimitedScheduledProcessArtifacts -TaskName $script:TicketsSyncRunnerTaskName -CommandPath $script:TicketsSyncRunnerCommandPath } catch { }
    }

    $script:TicketsSyncProcess = $null
    $script:TicketsSyncRunnerStdOutPath = ""
    $script:TicketsSyncRunnerStdErrPath = ""
    $script:TicketsSyncRunnerResultPath = ""
    $script:TicketsSyncRunnerTaskName = ""
    $script:TicketsSyncRunnerCommandPath = ""
    $script:TicketsSyncMode = ""
    $script:TicketsSyncPowerShell = $null
    $script:TicketsSyncRunspace = $null
    $script:TicketsSyncAsyncResult = $null
    $script:TicketsSyncCompletionTimer = $null
}

function Start-TicketsEmailSyncAsync {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [Parameter(Mandatory)]$SyncCmd,
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText,
        [int]$MaxPerMailbox = 120,
        [int]$TimeoutSeconds = 120,
        [switch]$RespectNextAttempt
    )

    if ($script:TicketsEmailSyncInProgress) {
        $completedRunFinalised = $false
        try {
            if (($script:TicketsSyncActiveRunId -gt 0) -and (Test-QOTicketsSyncOperationCompleted)) {
                Write-QOTicketsUILog ("Tickets: Start sync detected completed run #{0}; finalising before starting a new run." -f $script:TicketsSyncActiveRunId)
                $completedRunFinalised = [bool](Complete-TicketsEmailSyncAsyncRun -Grid $Grid -GetTicketsCmd $GetTicketsCmd -StatusText $StatusText -RunId ([int]$script:TicketsSyncActiveRunId))
            }
        } catch { $completedRunFinalised = $false }

        if (-not $completedRunFinalised -and $script:TicketsEmailSyncInProgress) {
            $canRecoverStaleRun = $false
            try {
                $lastStartUtc = $script:TicketsSyncLastStartUtc
                $elapsedSeconds = 0
                if ($lastStartUtc -and $lastStartUtc -ne [datetime]::MinValue) {
                    $elapsedSeconds = ((Get-Date).ToUniversalTime() - $lastStartUtc).TotalSeconds
                } else {
                    # In-progress with no start timestamp is invalid; recover immediately.
                    $canRecoverStaleRun = $true
                }
                $maxAllowed = [math]::Max(120, [int]$script:TicketsSyncActiveTimeoutSeconds + 30)
                if ($elapsedSeconds -ge $maxAllowed) {
                    $canRecoverStaleRun = $true
                    Write-QOTicketsUILog ("Tickets: Start sync detected stale in-flight run after {0}s; forcing recovery." -f [math]::Round($elapsedSeconds, 1)) "WARN"
                }
            } catch { $canRecoverStaleRun = $false }

            if ($canRecoverStaleRun) {
                Stop-QOTicketsSyncExecution -StopActiveOperation
                Clear-QOTicketsSyncExecutionState -RemoveRunnerFiles
                $script:TicketsEmailSyncInProgress = $false
                $script:TicketsSyncActiveRunId = 0
                $script:TicketsSyncActiveTimeoutSeconds = 0
                $script:TicketsSyncLastStartUtc = [datetime]::MinValue
                $script:TicketsSyncFailureCount = [int]$script:TicketsSyncFailureCount + 1
                $script:TicketsSyncLastFailureNote = "Previous sync run stopped responding."
                $backoffSeconds = Get-QOTicketsSyncBackoffSeconds -FailureCount $script:TicketsSyncFailureCount
                $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddSeconds($backoffSeconds)
                Set-QOTicketsSyncStatus -StatusText $StatusText -Message (Get-QOTicketsSyncRecoveringStatusMessage -NextAttemptUtc $script:TicketsSyncNextAttemptUtc)
            }
        }

        if ($completedRunFinalised -and $RespectNextAttempt) {
            return
        }
    }

    if ($script:TicketsEmailSyncInProgress) {
        try {
            $activeRunLabel = if ($script:TicketsSyncActiveRunId -gt 0) { [string]$script:TicketsSyncActiveRunId } else { "unknown" }
            Write-QOTicketsUILog ("Tickets: Async sync start skipped because run {0} is still active." -f $activeRunLabel) "WARN"
        } catch { }
        return
    }

    if ($RespectNextAttempt) {
        $nowUtc = (Get-Date).ToUniversalTime()
        $nextAttemptUtc = $script:TicketsSyncNextAttemptUtc
        if ($nextAttemptUtc -and $nextAttemptUtc -is [datetime] -and $nextAttemptUtc -ne [datetime]::MinValue -and $nowUtc -lt $nextAttemptUtc) {
            return
        }
    }

    $script:TicketsEmailSyncInProgress = $true
    try { $script:TicketsLastSyncAttemptUtc = (Get-Date).ToUniversalTime() } catch { }
    Set-QOTicketsSyncStatus -StatusText $StatusText -Message "Background sync running..."
    $script:TicketsSyncRunCounter = [int]$script:TicketsSyncRunCounter + 1
    $runId = [int]$script:TicketsSyncRunCounter
    $script:TicketsSyncActiveRunId = $runId
    $script:TicketsSyncLastStartUtc = (Get-Date).ToUniversalTime()
    $script:TicketsSyncActiveTimeoutSeconds = [int][math]::Min(900, [int][math]::Max(60, $TimeoutSeconds))

    Stop-QOTicketsSyncExecution
    Clear-QOTicketsSyncExecutionState -RemoveRunnerFiles

    $syncCmdName = ""
    $syncModulePath = $null
    $resolvedSyncCmd = Resolve-QOTInvokable -Candidate $SyncCmd -CommandName "Sync-QOTicketsFromEmail"
    try {
        if ($resolvedSyncCmd -is [System.Management.Automation.CommandInfo]) {
            $syncCmdName = [string]$resolvedSyncCmd.Name
            if ($resolvedSyncCmd.Module -and $resolvedSyncCmd.Module.Path) {
                $syncModulePath = [string]$resolvedSyncCmd.Module.Path
            }
        }
        elseif ($resolvedSyncCmd -is [string]) {
            $syncCmdName = ([string]$resolvedSyncCmd).Trim()
            if (-not [string]::IsNullOrWhiteSpace($syncCmdName)) {
                $cmdByName = Get-Command -Name $syncCmdName -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($cmdByName -and $cmdByName.Module -and $cmdByName.Module.Path) {
                    $syncModulePath = [string]$cmdByName.Module.Path
                }
            }
        }
        elseif ($SyncCmd -and $SyncCmd.Name) {
            $syncCmdName = [string]$SyncCmd.Name
            if ($SyncCmd.Module -and $SyncCmd.Module.Path) {
                $syncModulePath = [string]$SyncCmd.Module.Path
            }
        }
    } catch { }

    $syncRunnerPath = $null
    $toolkitRootPath = ""
    try {
        $toolkitRootPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    } catch {
        $toolkitRootPath = ""
    }

    if (-not [string]::IsNullOrWhiteSpace($toolkitRootPath)) {
        try {
            $candidateSyncRunner = Join-Path $toolkitRootPath "src\Tickets\Tickets.Email.SyncRunner.ps1"
            if (Test-Path -LiteralPath $candidateSyncRunner) {
                $syncRunnerPath = $candidateSyncRunner
            }
        } catch { $syncRunnerPath = $null }
    }

    $runnerMode = if (-not [string]::IsNullOrWhiteSpace($syncRunnerPath)) { "child-process" } else { "runspace" }
    Write-QOTicketsUILog ("Tickets: Starting async email sync run #{0}. Cmd='{1}' MaxPerMailbox={2} Timeout={3}s Runner={4}" -f $runId, $syncCmdName, $MaxPerMailbox, $script:TicketsSyncActiveTimeoutSeconds, $runnerMode)

    try {
        if ($runnerMode -eq "child-process") {
            $stdoutPath = Join-Path $env:TEMP ("qot_sync_{0}_{1}.json" -f $PID, ([guid]::NewGuid().ToString("N")))
            $stderrPath = Join-Path $env:TEMP ("qot_sync_{0}_{1}.err" -f $PID, ([guid]::NewGuid().ToString("N")))
            $resultPath = Join-Path $env:TEMP ("qot_sync_{0}_{1}.result.json" -f $PID, ([guid]::NewGuid().ToString("N")))
            $exePath = Join-Path $env:WINDIR "System32\\WindowsPowerShell\\v1.0\\powershell.exe"
            if (-not (Test-Path -LiteralPath $exePath)) { $exePath = "powershell.exe" }

            $argList = @(
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-WindowStyle", "Hidden",
                "-STA",
                "-File", $syncRunnerPath,
                "-ToolkitRoot", $toolkitRootPath,
                "-SyncCommand", $syncCmdName,
                "-MaxPerMailbox", [string]$MaxPerMailbox,
                "-ResultPath", $resultPath
            )
            $argumentString = ConvertTo-QOTProcessArgumentString -Arguments $argList

            if (Test-QOTProcessElevated) {
                $workingDirectory = $toolkitRootPath
                if ([string]::IsNullOrWhiteSpace($workingDirectory) -or -not (Test-Path -LiteralPath $workingDirectory)) {
                    $workingDirectory = $env:TEMP
                }
                $limitedLaunch = Start-QOTLimitedScheduledProcess -FilePath $exePath -ArgumentString $argumentString -WorkingDirectory $workingDirectory -TaskNamePrefix "QOTSync"
                $script:TicketsSyncProcess = $null
                $script:TicketsSyncMode = "result-file"
                try { $script:TicketsSyncRunnerTaskName = [string]$limitedLaunch.TaskName } catch { $script:TicketsSyncRunnerTaskName = "" }
                try { $script:TicketsSyncRunnerCommandPath = [string]$limitedLaunch.CommandPath } catch { $script:TicketsSyncRunnerCommandPath = "" }
                Write-QOTicketsUILog ("Tickets: Elevated sync run #{0} launched as limited scheduled task for Outlook COM access." -f $runId)
            } else {
                $script:TicketsSyncProcess = Start-Process -FilePath $exePath -ArgumentList $argumentString -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
                $script:TicketsSyncMode = "child-process"
            }
            $script:TicketsSyncRunnerStdOutPath = $stdoutPath
            $script:TicketsSyncRunnerStdErrPath = $stderrPath
            $script:TicketsSyncRunnerResultPath = $resultPath
        }
        else {
            $script:TicketsSyncRunspace = [runspacefactory]::CreateRunspace()
            try { $script:TicketsSyncRunspace.ApartmentState = [System.Threading.ApartmentState]::STA } catch { }
            try { $script:TicketsSyncRunspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread } catch { }
            $script:TicketsSyncRunspace.Open()

            $script:TicketsSyncPowerShell = [powershell]::Create()
            $script:TicketsSyncPowerShell.Runspace = $script:TicketsSyncRunspace
            $null = $script:TicketsSyncPowerShell.AddScript({
                param(
                    [string]$SyncCmdName,
                    [string]$SyncModulePath,
                    [int]$MaxPerMailbox
                )

                $ErrorActionPreference = "Stop"
                if ($MaxPerMailbox -lt 1) { $MaxPerMailbox = 1 }
                if ($MaxPerMailbox -gt 500) { $MaxPerMailbox = 500 }

                if ([string]::IsNullOrWhiteSpace($SyncCmdName)) {
                    return [pscustomobject]@{ Success = $false; Added = 0; Updated = 0; AddedTickets = @(); Note = "Sync command unavailable" }
                }

                if (-not [string]::IsNullOrWhiteSpace($SyncModulePath) -and (Test-Path -LiteralPath $SyncModulePath)) {
                    Import-Module -Name $SyncModulePath -Force -ErrorAction Stop
                }

                try {
                    return (& $SyncCmdName -MaxPerMailbox $MaxPerMailbox)
                } catch {
                    return [pscustomobject]@{
                        Success     = $false
                        Added       = 0
                        Updated     = 0
                        AddedTickets = @()
                        Note        = $_.Exception.Message
                    }
                }
            }).AddArgument($syncCmdName).AddArgument($syncModulePath).AddArgument($MaxPerMailbox)

            $script:TicketsSyncAsyncResult = $script:TicketsSyncPowerShell.BeginInvoke()
            $script:TicketsSyncMode = "runspace"
        }
    } catch {
        Stop-QOTicketsSyncExecution -StopActiveOperation
        Clear-QOTicketsSyncExecutionState -RemoveRunnerFiles
        $script:TicketsEmailSyncInProgress = $false
        $script:TicketsSyncActiveRunId = 0
        $script:TicketsSyncActiveTimeoutSeconds = 0
        $script:TicketsSyncLastStartUtc = [datetime]::MinValue
        $script:TicketsSyncFailureCount = [int]$script:TicketsSyncFailureCount + 1
        $script:TicketsSyncLastFailureNote = [string]$_.Exception.Message
        $backoff = Get-QOTicketsSyncBackoffSeconds -FailureCount $script:TicketsSyncFailureCount
        $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddSeconds($backoff)
        Write-QOTicketsUILog ("Tickets: Failed to start async sync run #{0}. Next retry in {1}s. Reason: {2}" -f $runId, $backoff, $_.Exception.Message) "ERROR"
        Set-QOTicketsSyncStatus -StatusText $StatusText -Message (Get-QOTicketsSyncRecoveringStatusMessage -NextAttemptUtc $script:TicketsSyncNextAttemptUtc)
        return
    }

    $syncTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $syncTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $syncStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $syncTimer.Add_Tick({
        if ($script:TicketsSyncActiveRunId -ne $runId) {
            $syncTimer.Stop()
            $syncStopwatch.Stop()
            return
        }

        $isCompleted = $false
        try { $isCompleted = [bool](Test-QOTicketsSyncOperationCompleted) } catch { $isCompleted = $false }

        $timedOut = $false
        if ($syncStopwatch.Elapsed.TotalSeconds -ge $script:TicketsSyncActiveTimeoutSeconds -and -not $isCompleted) {
            $timedOut = $true
            Stop-QOTicketsSyncExecution -StopActiveOperation
            try { Write-QOTicketsUILog ("Tickets: Async sync run #{0} hit timeout at {1}s." -f $runId, [math]::Round($syncStopwatch.Elapsed.TotalSeconds, 1)) "WARN" } catch { }
        }

        if (-not $timedOut -and -not $isCompleted) {
            return
        }

        Complete-TicketsEmailSyncAsyncRun -Grid $Grid -GetTicketsCmd $GetTicketsCmd -StatusText $StatusText -RunId $runId -TimedOut:$timedOut | Out-Null
    }.GetNewClosure())

    $script:TicketsSyncCompletionTimer = $syncTimer
    $script:TicketsSyncCompletionTimer.Start()
}

function Complete-TicketsEmailSyncAsyncRun {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText,
        [Parameter(Mandatory)][int]$RunId,
        [switch]$TimedOut
    )

    if ($RunId -lt 1) { return $false }
    if ($script:TicketsSyncActiveRunId -ne $RunId) { return $false }

    $mode = [string]$script:TicketsSyncMode
    $asyncResult = $script:TicketsSyncAsyncResult
    $syncPowerShell = $script:TicketsSyncPowerShell
    $syncRunspace = $script:TicketsSyncRunspace
    $syncProcess = $script:TicketsSyncProcess
    $resultPath = [string]$script:TicketsSyncRunnerResultPath
    $stdoutPath = [string]$script:TicketsSyncRunnerStdOutPath
    $stderrPath = [string]$script:TicketsSyncRunnerStdErrPath

    if (-not $TimedOut -and -not (Test-QOTicketsSyncOperationCompleted -Process $syncProcess -AsyncResult $asyncResult -Mode $mode)) { return $false }

    try {
        if ($script:TicketsSyncCompletionTimer) {
            $script:TicketsSyncCompletionTimer.Stop()
        }
    } catch { }

    $result = $null
    $completionError = $null
    if ($TimedOut) {
        $result = Convert-QOTicketsSyncResultObject -RawResult $null -TimedOut $true -DefaultNote "Outlook sync timed out."
    }
    else {
        try {
            if ($mode -eq "child-process") {
                if ($syncProcess) {
                    try { $null = $syncProcess.WaitForExit(5000) } catch { }
                }
                $result = Read-QOTicketsSyncRunnerResult -ResultPath $resultPath -StdOutPath $stdoutPath -StdErrPath $stderrPath
            }
            elseif ($mode -eq "result-file") {
                $result = Read-QOTicketsSyncRunnerResult -ResultPath $resultPath -StdOutPath $stdoutPath -StdErrPath $stderrPath
            }
            else {
                $output = @($syncPowerShell.EndInvoke($asyncResult))
                if ($output.Count -gt 0) {
                    $result = Convert-QOTicketsSyncResultObject -RawResult $output[-1]
                }
                else {
                    $result = Convert-QOTicketsSyncResultObject -RawResult $null -DefaultNote "Outlook sync returned nothing."
                }
            }
        }
        catch {
            $completionError = $_.Exception
        }
    }

    $elapsedSeconds = 0
    try {
        if ($script:TicketsSyncLastStartUtc -and $script:TicketsSyncLastStartUtc -ne [datetime]::MinValue) {
            $elapsedSeconds = ((Get-Date).ToUniversalTime() - $script:TicketsSyncLastStartUtc).TotalSeconds
        }
    } catch { $elapsedSeconds = 0 }

    Stop-QOTicketsSyncExecution
    Clear-QOTicketsSyncExecutionState -RemoveRunnerFiles
    $script:TicketsEmailSyncInProgress = $false
    $script:TicketsSyncActiveRunId = 0
    $script:TicketsSyncActiveTimeoutSeconds = 0
    $script:TicketsSyncLastStartUtc = [datetime]::MinValue

    $outTimedOut = $false
    $success = $false
    $added = 0
    $updated = 0
    $note = ""
    $addedTickets = @()

    if ($completionError) {
        $note = [string]$completionError.Message
    }

    try { if ($result -and $result.PSObject.Properties.Name -contains "TimedOut") { $outTimedOut = [bool]$result.TimedOut } } catch { }
    try { if ($result -and $result.PSObject.Properties.Name -contains "Success") { $success = [bool]$result.Success } } catch { }
    try { if ($result -and $result.PSObject.Properties.Name -contains "Added") { $added = [int]$result.Added } } catch { }
    try { if ($result -and $result.PSObject.Properties.Name -contains "Updated") { $updated = [int]$result.Updated } } catch { }
    try { if ($result -and $result.PSObject.Properties.Name -contains "Note") { $note = [string]$result.Note } } catch { }
    try { if ($result -and $result.PSObject.Properties.Name -contains "AddedTickets") { $addedTickets = @($result.AddedTickets) } } catch { }

    if ($outTimedOut -or (-not $success) -or $completionError) {
        $script:TicketsSyncFailureCount = [int]$script:TicketsSyncFailureCount + 1
        $backoff = Get-QOTicketsSyncBackoffSeconds -FailureCount $script:TicketsSyncFailureCount
        $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddSeconds($backoff)
        $script:TicketsSyncLastFailureNote = [string]$note
        Write-QOTicketsUILog ("Tickets: Background email sync run #{0} failed after {1}s. Next retry in {2}s. Reason: {3}" -f $RunId, [math]::Round($elapsedSeconds, 1), $backoff, $note) "WARN"
        $shortNote = ""
        try { $shortNote = ([string]$note).Trim() } catch { $shortNote = "" }
        if ($shortNote.Length -gt 90) { $shortNote = $shortNote.Substring(0, 90) + "..." }
        if (Test-QOTicketsSyncFailureLooksRecoverable -Note $note) {
            Set-QOTicketsSyncStatus -StatusText $StatusText -Message (Get-QOTicketsSyncRecoveringStatusMessage -NextAttemptUtc $script:TicketsSyncNextAttemptUtc)
        }
        else {
            $delayLabel = Get-QOTicketsSyncRetryDelayLabel -NextAttemptUtc $script:TicketsSyncNextAttemptUtc
            Set-QOTicketsSyncStatus -StatusText $StatusText -Message ("Background sync retrying in {0}" -f $delayLabel)
        }
        return $true
    }

    $script:TicketsSyncFailureCount = 0
    $script:TicketsSyncLastFailureNote = ""
    $script:TicketsLastSuccessfulSyncUtc = (Get-Date).ToUniversalTime()
    $nextPollSeconds = Get-QOTicketsSyncSuccessPollSeconds
    $script:TicketsSyncNextAttemptUtc = $script:TicketsLastSuccessfulSyncUtc.AddSeconds($nextPollSeconds)

    $incomingTickets = @($addedTickets | Where-Object { $null -ne $_ })
    if ($incomingTickets.Count -gt 0) {
        $queuedCount = Start-QOTicketsIncrementalMerge -Grid $Grid -IncomingTickets $incomingTickets -StatusText $StatusText
        Write-QOTicketsUILog ("Tickets: Background email sync run #{0} finished in {1}s. Added={2} Updated={3} QueuedForMerge={4}. Note={5}" -f $RunId, [math]::Round($elapsedSeconds, 1), $added, $updated, $queuedCount, $note)
    }
    elseif ($updated -gt 0) {
        try { Invoke-QOTicketsGridRefresh -Grid $Grid -GetTicketsCmd $GetTicketsCmd } catch { }
        Write-QOTicketsUILog ("Tickets: Background email sync run #{0} finished in {1}s. Added=0 Updated={2}. Note={3}" -f $RunId, [math]::Round($elapsedSeconds, 1), $updated, $note)
        Set-QOTicketsSyncStatus -StatusText $StatusText -Message (Get-QOTicketsLastSuccessfulSyncLabel)
    }
    else {
        Write-QOTicketsUILog ("Tickets: Background email sync run #{0} finished in {1}s. Added={2} Updated=0 Merged=0. Note={3}" -f $RunId, [math]::Round($elapsedSeconds, 1), $added, $note)
        Set-QOTicketsSyncStatus -StatusText $StatusText -Message (Get-QOTicketsLastSuccessfulSyncLabel)
    }

    return $true
}

function Start-QOTicketsAutoSyncWorker {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [AllowNull()]$SyncCmd,
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText
    )

    if ($script:TicketsSyncWorkerStarted) {
        $timerAlive = $false
        try {
            $timerAlive = [bool]($script:TicketsSyncTimer -and $script:TicketsSyncTimer.IsEnabled)
        } catch { $timerAlive = $false }
        if ($timerAlive) { return }
        # Worker state got stale; rebuild it cleanly.
        $script:TicketsSyncWorkerStarted = $false
    }

    if (-not $SyncCmd) {
        # Retry command resolution lazily so autosync can recover if modules loaded late.
        try {
            $SyncCmd = Resolve-QOTInvokable -Candidate (Get-Command Sync-QOTicketsFromEmail -ErrorAction SilentlyContinue) -CommandName "Sync-QOTicketsFromEmail"
        } catch { $SyncCmd = $null }
    }

    $script:TicketsSyncWorkerStarted = $true
    if (-not $SyncCmd) {
        $script:TicketsSyncFailureCount = [math]::Max(1, [int]$script:TicketsSyncFailureCount)
        $script:TicketsSyncLastFailureNote = "Sync command not available."
        $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddSeconds((Get-QOTicketsSyncBackoffSeconds -FailureCount $script:TicketsSyncFailureCount))
        Write-QOTicketsUILog "Tickets: Sync command not available yet. Auto-sync worker will keep retrying." "WARN"
        Set-QOTicketsSyncStatus -StatusText $StatusText -Message ("Email sync loading... retry in {0}" -f (Get-QOTicketsSyncRetryDelayLabel -NextAttemptUtc $script:TicketsSyncNextAttemptUtc))
    }
    else {
        $script:TicketsSyncNextAttemptUtc = [datetime]::MinValue
        Set-QOTicketsSyncStatus -StatusText $StatusText -Message "Background sync every 5 minutes"
    }

    $script:TicketsSyncTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:TicketsSyncTimer.Interval = [TimeSpan]::FromSeconds(1)
    if ($script:TicketsSyncNextAttemptUtc -eq [datetime]::MinValue) {
        $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddSeconds((Get-QOTicketsSyncSuccessPollSeconds))
    }
    $script:TicketsSyncWorkerTickHandler = {
        if ($script:TicketsEmailSyncInProgress) {
            try {
                if ($script:TicketsSyncActiveRunId -gt 0) {
                    $completedNow = $false
                    try { $completedNow = [bool](Test-QOTicketsSyncOperationCompleted) } catch { $completedNow = $false }
                    if ($completedNow) {
                        Write-QOTicketsUILog ("Tickets: Worker detected completed async sync run #{0}; finalising." -f $script:TicketsSyncActiveRunId)
                        Complete-TicketsEmailSyncAsyncRun -Grid $Grid -GetTicketsCmd $GetTicketsCmd -StatusText $StatusText -RunId ([int]$script:TicketsSyncActiveRunId) | Out-Null
                        return
                    }
                }

                $shouldForceReset = $false
                $resetReason = ""
                $lastStart = $script:TicketsSyncLastStartUtc
                $mode = ([string]($script:TicketsSyncMode + "")).Trim().ToLowerInvariant()

                if ([string]::IsNullOrWhiteSpace($mode)) {
                    $shouldForceReset = $true
                    $resetReason = "missing sync mode"
                }
                elseif ($mode -eq "child-process") {
                    if (-not $script:TicketsSyncProcess -or -not $script:TicketsSyncCompletionTimer) {
                        $shouldForceReset = $true
                        $resetReason = "missing child-process sync handles"
                    }
                }
                elseif ($mode -eq "result-file") {
                    if ([string]::IsNullOrWhiteSpace([string]$script:TicketsSyncRunnerResultPath) -or -not $script:TicketsSyncCompletionTimer) {
                        $shouldForceReset = $true
                        $resetReason = "missing result-file sync handles"
                    }
                }
                elseif (-not $script:TicketsSyncAsyncResult -or -not $script:TicketsSyncPowerShell -or -not $script:TicketsSyncRunspace -or -not $script:TicketsSyncCompletionTimer) {
                    $shouldForceReset = $true
                    $resetReason = "missing runspace sync handles"
                }
                elseif (-not $lastStart -or $lastStart -eq [datetime]::MinValue) {
                    $shouldForceReset = $true
                    $resetReason = "missing sync start timestamp"
                }
                else {
                    $elapsed = ((Get-Date).ToUniversalTime() - $lastStart).TotalSeconds
                    $maxAllowed = [math]::Max(120, [int]$script:TicketsSyncActiveTimeoutSeconds + 30)
                    if ($elapsed -ge $maxAllowed) {
                        $shouldForceReset = $true
                        $resetReason = ("elapsed {0}s >= {1}s timeout window" -f [math]::Round($elapsed, 1), $maxAllowed)
                    }
                }

                if ($shouldForceReset) {
                    Write-QOTicketsUILog ("Tickets: Sync watchdog forcing reset ({0})." -f $resetReason) "WARN"
                    Stop-QOTicketsSyncExecution -StopActiveOperation
                    Clear-QOTicketsSyncExecutionState -RemoveRunnerFiles
                    $script:TicketsEmailSyncInProgress = $false
                    $script:TicketsSyncActiveRunId = 0
                    $script:TicketsSyncActiveTimeoutSeconds = 0
                    $script:TicketsSyncLastStartUtc = [datetime]::MinValue
                    $script:TicketsSyncFailureCount = [int]$script:TicketsSyncFailureCount + 1
                    $script:TicketsSyncLastFailureNote = $resetReason
                    $backoffSeconds = Get-QOTicketsSyncBackoffSeconds -FailureCount $script:TicketsSyncFailureCount
                    $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddSeconds($backoffSeconds)
                    Set-QOTicketsSyncStatus -StatusText $StatusText -Message (Get-QOTicketsSyncRecoveringStatusMessage -NextAttemptUtc $script:TicketsSyncNextAttemptUtc)
                }
            } catch { }
            return
        }

        $nowUtc = (Get-Date).ToUniversalTime()
        if ($nowUtc -lt $script:TicketsSyncNextAttemptUtc) {
            if ([int]$script:TicketsSyncFailureCount -gt 0) {
                try {
                    $lastFailure = [string]($script:TicketsSyncLastFailureNote + "")
                    if (Test-QOTicketsSyncFailureLooksRecoverable -Note $lastFailure) {
                        Set-QOTicketsSyncStatus -StatusText $StatusText -Message (Get-QOTicketsSyncRecoveringStatusMessage -NextAttemptUtc $script:TicketsSyncNextAttemptUtc)
                    }
                    else {
                        $delayLabel = Get-QOTicketsSyncRetryDelayLabel -NextAttemptUtc $script:TicketsSyncNextAttemptUtc
                        Set-QOTicketsSyncStatus -StatusText $StatusText -Message ("Background sync retrying in {0}" -f $delayLabel)
                    }
                } catch { }
            }
            return
        }

        if (-not $SyncCmd) {
            try {
                $SyncCmd = Resolve-QOTInvokable -Candidate (Get-Command Sync-QOTicketsFromEmail -ErrorAction SilentlyContinue) -CommandName "Sync-QOTicketsFromEmail"
            } catch { $SyncCmd = $null }

            if (-not $SyncCmd) {
                $script:TicketsSyncFailureCount = [int]$script:TicketsSyncFailureCount + 1
                $script:TicketsSyncLastFailureNote = "Sync command not available."
                $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddSeconds((Get-QOTicketsSyncBackoffSeconds -FailureCount $script:TicketsSyncFailureCount))
                Write-QOTicketsUILog "Tickets: Sync command still unavailable; retry remains scheduled." "WARN"
                Set-QOTicketsSyncStatus -StatusText $StatusText -Message ("Email sync loading... retry in {0}" -f (Get-QOTicketsSyncRetryDelayLabel -NextAttemptUtc $script:TicketsSyncNextAttemptUtc))
                return
            }

            $script:TicketsSyncFailureCount = 0
            $script:TicketsSyncLastFailureNote = ""
            Write-QOTicketsUILog "Tickets: Sync command became available; starting auto-sync."
        }

        Start-TicketsEmailSyncAsync -Grid $Grid -GetTicketsCmd $GetTicketsCmd -SyncCmd $SyncCmd -StatusText $StatusText -MaxPerMailbox $script:TicketsBackgroundBatchSize -RespectNextAttempt
    }.GetNewClosure()

    $script:TicketsSyncTimer.Add_Tick($script:TicketsSyncWorkerTickHandler)
    $script:TicketsSyncTimer.Start()
}


function Invoke-QOTicketsEmailSyncAndRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [Parameter(Mandatory)]$SyncCmd,
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText,
        [switch]$Force,
        [int]$MaxPerMailbox = 0
    )

    $requestedMax = 0
    if ($MaxPerMailbox -gt 0) {
        $requestedMax = [int]$MaxPerMailbox
    } elseif ($Force) {
        $requestedMax = 200
    } else {
        $requestedMax = [int]$script:TicketsStartupBatchSize
    }
    if ($requestedMax -lt 1) { $requestedMax = 1 }
    if ($requestedMax -gt 500) { $requestedMax = 500 }
    Start-TicketsEmailSyncAsync -Grid $Grid -GetTicketsCmd $GetTicketsCmd -SyncCmd $SyncCmd -StatusText $StatusText -MaxPerMailbox $requestedMax
}

function Invoke-QOTicketsManualSyncRequest {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [AllowNull()]$SyncCmd,
        [AllowNull()][System.Windows.Controls.TextBlock]$StatusText,
        [AllowNull()]$InvokeSyncCmd,
        [int]$MaxPerMailbox = 0
    )

    try {
        if (-not $SyncCmd) {
            try {
                $SyncCmd = Resolve-QOTInvokable -Candidate (Get-Command Sync-QOTicketsFromEmail -ErrorAction SilentlyContinue) -CommandName "Sync-QOTicketsFromEmail"
            } catch { $SyncCmd = $null }
            if (-not $SyncCmd) {
                $script:TicketsSyncFailureCount = [math]::Max(1, [int]$script:TicketsSyncFailureCount)
                $script:TicketsSyncLastFailureNote = "Sync command not available."
                $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddSeconds((Get-QOTicketsSyncBackoffSeconds -FailureCount $script:TicketsSyncFailureCount))
                Write-QOTicketsUILog "Tickets: Header sync click found sync command unavailable; auto-sync will keep retrying." "WARN"
                Set-QOTicketsSyncStatus -StatusText $StatusText -Message ("Email sync loading... retry in {0}" -f (Get-QOTicketsSyncRetryDelayLabel -NextAttemptUtc $script:TicketsSyncNextAttemptUtc))
                return $false
            }
        }

        if ($script:TicketsEmailSyncInProgress) {
            Set-QOTicketsSyncStatus -StatusText $StatusText -Message "Background sync already running..."
            return $false
        }

        $requestedMax = [int]$MaxPerMailbox
        if ($requestedMax -lt 1) {
            $requestedMax = [int]$script:TicketsBackgroundBatchSize
        }
        if ($requestedMax -lt 1) { $requestedMax = 25 }
        if ($requestedMax -gt 500) { $requestedMax = 500 }

        Write-QOTicketsUILog "Tickets: Header sync click requested manual email sync."
        Set-QOTicketsSyncStatus -StatusText $StatusText -Message "Manual sync requested..."

        if ($InvokeSyncCmd) {
            & $InvokeSyncCmd -Grid $Grid -GetTicketsCmd $GetTicketsCmd -SyncCmd $SyncCmd -StatusText $StatusText -MaxPerMailbox $requestedMax
        }
        else {
            Invoke-QOTicketsEmailSyncAndRefresh -Grid $Grid -GetTicketsCmd $GetTicketsCmd -SyncCmd $SyncCmd -StatusText $StatusText -MaxPerMailbox $requestedMax
        }

        return $true
    } catch {
        Write-QOTicketsUILog ("Tickets: Header sync click failed: " + $_.Exception.Message) "ERROR"
        Set-QOTicketsSyncStatus -StatusText $StatusText -Message "Manual sync failed to start"
        return $false
    }
}

function Invoke-QOTicketsGridRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [string]$View
    )

    $selectedTicketBefore = $null
    $selectedIdBefore = ""
    $selectedSubjectBefore = ""
    $selectedCreatedBefore = ""
    $detailsWasOpen = $false
    try { $selectedTicketBefore = $Grid.SelectedItem } catch { $selectedTicketBefore = $null }
    if (-not $selectedTicketBefore) {
        try { $selectedTicketBefore = $Grid.CurrentItem } catch { $selectedTicketBefore = $null }
    }
    try {
        if ($selectedTicketBefore -and ($selectedTicketBefore.PSObject.Properties.Name -contains "Id")) {
            $selectedIdBefore = ([string]($selectedTicketBefore.Id + "")).Trim()
        }
    } catch { $selectedIdBefore = "" }
    try {
        if ($selectedTicketBefore -and ($selectedTicketBefore.PSObject.Properties.Name -contains "Subject")) {
            $selectedSubjectBefore = ([string]($selectedTicketBefore.Subject + "")).Trim()
        }
    } catch { $selectedSubjectBefore = "" }
    try {
        if ($selectedTicketBefore -and ($selectedTicketBefore.PSObject.Properties.Name -contains "CreatedAt")) {
            $selectedCreatedBefore = ([string]($selectedTicketBefore.CreatedAt + "")).Trim()
        }
    } catch { $selectedCreatedBefore = "" }
    try {
        if ($script:TicketsDetailsPanel) {
            $detailsWasOpen = ($script:TicketsDetailsPanel.Visibility -eq "Visible")
        }
    } catch { $detailsWasOpen = $false }

    Refresh-QOTicketsGrid -Grid $Grid -GetTicketsCmd $GetTicketsCmd -View $View

    $view = $null
    try { $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($Grid.ItemsSource) } catch { $view = $null }
    if ($view -and $view -is [System.ComponentModel.ICollectionView]) {
        try { $view.Refresh() } catch { }
    }

    $selectedTicketAfter = $null
    $itemsAfter = @()
    try { $itemsAfter = @($Grid.ItemsSource) } catch { $itemsAfter = @() }
    if (-not $selectedTicketAfter -and -not [string]::IsNullOrWhiteSpace($selectedIdBefore)) {
        foreach ($item in $itemsAfter) {
            if (-not $item) { continue }
            $idValue = ""
            try {
                if ($item.PSObject.Properties.Name -contains "Id") {
                    $idValue = ([string]($item.Id + "")).Trim()
                }
            } catch { $idValue = "" }
            if ($idValue -eq $selectedIdBefore) { $selectedTicketAfter = $item; break }
        }
    }
    if (-not $selectedTicketAfter -and -not [string]::IsNullOrWhiteSpace($selectedSubjectBefore)) {
        foreach ($item in $itemsAfter) {
            if (-not $item) { continue }
            $subjectValue = ""
            $createdValue = ""
            try { if ($item.PSObject.Properties.Name -contains "Subject") { $subjectValue = ([string]($item.Subject + "")).Trim() } } catch { $subjectValue = "" }
            try { if ($item.PSObject.Properties.Name -contains "CreatedAt") { $createdValue = ([string]($item.CreatedAt + "")).Trim() } } catch { $createdValue = "" }
            if ($subjectValue -eq $selectedSubjectBefore) {
                if ([string]::IsNullOrWhiteSpace($selectedCreatedBefore) -or $createdValue -eq $selectedCreatedBefore) {
                    $selectedTicketAfter = $item
                    break
                }
            }
        }
    }

    if ($selectedTicketAfter) {
        try { $Grid.SelectedItem = $selectedTicketAfter } catch { }
        try { $Grid.CurrentItem = $selectedTicketAfter } catch { }
        try { $Grid.ScrollIntoView($selectedTicketAfter) } catch { }
    }

    if ($detailsWasOpen -and $script:TicketsDetailsPanel) {
        $detailsTicket = $selectedTicketAfter
        if (-not $detailsTicket) {
            try { $detailsTicket = $Grid.SelectedItem } catch { $detailsTicket = $null }
        }
        if ($detailsTicket) {
            try {
                Update-QOTicketDetailsView -Ticket $detailsTicket -DetailsPanel $script:TicketsDetailsPanel -BodyText $script:TicketsBodyText -ReplySubject $script:TicketsReplySubject -ReplyText $script:TicketsReplyText -ReplyButton $script:TicketsReplyButton -Chevron $script:TicketsDetailsChevron
            } catch { }
        }
    }
}

function Start-QOTicketsStoreAutoRefresh {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [Parameter(Mandatory)]$GetTicketsCmd,
        [AllowNull()]$GetStorePathCmd,
        [AllowNull()]$RefreshCmd
    )

    if (-not $GetStorePathCmd) {
        Write-QOTicketsUILog "Tickets: Auto refresh disabled (Get-QOTicketsStorePath unavailable)." "WARN"
        return
    }

    try {
        if ($script:TicketsFileRefreshTimer) {
            if ($script:TicketsFileRefreshTickHandler) {
                $script:TicketsFileRefreshTimer.Remove_Tick($script:TicketsFileRefreshTickHandler)
            }
            $script:TicketsFileRefreshTimer.Stop()
            $script:TicketsFileRefreshTimer = $null
        }
    } catch { }

    $script:TicketsStorePath = ""
    $script:TicketsStoreLastWriteUtc = [datetime]::MinValue
    $effectiveRefreshCmd = Resolve-QOTInvokable -Candidate $RefreshCmd -CommandName "Invoke-QOTicketsGridRefresh"
    if (-not $effectiveRefreshCmd) {
        try { $effectiveRefreshCmd = ${function:Invoke-QOTicketsGridRefresh} } catch { $effectiveRefreshCmd = $null }
    }

    try {
        $resolvedPath = [string](& $GetStorePathCmd)
        if (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
            $script:TicketsStorePath = $resolvedPath.Trim()
            if (Test-Path -LiteralPath $script:TicketsStorePath) {
                $script:TicketsStoreLastWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($script:TicketsStorePath)
            }
        }
    } catch {
        Write-QOTicketsUILog ("Tickets: Unable to resolve ticket store path for auto refresh. " + $_.Exception.Message) "WARN"
    }

    $script:TicketsFileRefreshTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:TicketsFileRefreshTimer.Interval = [TimeSpan]::FromSeconds(2)
    $script:TicketsFileRefreshTickHandler = {
        try {
            if ($script:TicketsEmailSyncInProgress) { return }
            if ($script:TicketsIncrementalMergeTimer -and $script:TicketsIncrementalMergeTimer.IsEnabled) { return }

            $storePath = [string]$script:TicketsStorePath
            if ([string]::IsNullOrWhiteSpace($storePath)) {
                $storePath = [string](& $GetStorePathCmd)
                if ([string]::IsNullOrWhiteSpace($storePath)) { return }
                $storePath = $storePath.Trim()
                $script:TicketsStorePath = $storePath
            }

            if (-not (Test-Path -LiteralPath $storePath)) { return }
            $currentWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($storePath)
            if ($currentWriteUtc -eq [datetime]::MinValue) { return }

            if ($script:TicketsStoreLastWriteUtc -eq [datetime]::MinValue) {
                $script:TicketsStoreLastWriteUtc = $currentWriteUtc
                return
            }

            if ($currentWriteUtc -le $script:TicketsStoreLastWriteUtc) { return }

            $script:TicketsStoreLastWriteUtc = $currentWriteUtc
            $preferLightweightRefresh = $false
            try {
                $refreshUntilUtc = [datetime]$script:TicketsReplyUiRefreshUntilUtc
                if ($refreshUntilUtc -and $refreshUntilUtc -ne [datetime]::MinValue) {
                    $preferLightweightRefresh = ((Get-Date).ToUniversalTime() -le $refreshUntilUtc)
                }
            } catch { $preferLightweightRefresh = $false }
            if (-not $preferLightweightRefresh) {
                try {
                    $getQueueSnapshotCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTPendingReplyQueueSnapshot"
                    if ($getQueueSnapshotCmd) {
                        $queueSnapshot = & $getQueueSnapshotCmd
                        $activeReplyCount = 0
                        try { if ($queueSnapshot -and ($queueSnapshot.PSObject.Properties.Name -contains "ActiveCount")) { $activeReplyCount = [int]$queueSnapshot.ActiveCount } } catch { $activeReplyCount = 0 }
                        $preferLightweightRefresh = ($activeReplyCount -gt 0)
                    }
                } catch { $preferLightweightRefresh = $false }
            }

            if ($preferLightweightRefresh) {
                $preferredDetailsTicket = $null
                try { $preferredDetailsTicket = $Grid.SelectedItem } catch { $preferredDetailsTicket = $null }
                if (-not $preferredDetailsTicket) {
                    try { $preferredDetailsTicket = $Grid.CurrentItem } catch { $preferredDetailsTicket = $null }
                }
                try { Refresh-QOTicketsAfterLocalMutation -Grid $Grid -PreferredDetailsTicket $preferredDetailsTicket -PreferCurrentTicket -PreferCachedPendingReplies } catch { }
                return
            }

            if ($effectiveRefreshCmd) {
                & $effectiveRefreshCmd -Grid $Grid -GetTicketsCmd $GetTicketsCmd -View $script:TicketsCurrentView
            } else {
                try { Refresh-QOTicketsGrid -Grid $Grid -GetTicketsCmd $GetTicketsCmd -View $script:TicketsCurrentView } catch { }
            }
        } catch { }
    }.GetNewClosure()

    $script:TicketsFileRefreshTimer.Add_Tick($script:TicketsFileRefreshTickHandler)
    $script:TicketsFileRefreshTimer.Start()
}

function Stop-QOTicketsFileWatcher {
    <#
    .SYNOPSIS
    Stops any active FileSystemWatcher and unregisters its event subscriptions.
    .DESCRIPTION
    The Tickets UI tracks at most one FileSystemWatcher at a time in
    $script:TicketsFileWatcher and its subscriptions in
    $script:TicketsFileWatcherEvents. This function:
      1. Unregisters every event subscription (Unregister-Event by Id)
      2. Sets EnableRaisingEvents = $false on the watcher
      3. Disposes the watcher
      4. Nulls out script-level references so the next call is a no-op

    Safe to call when no watcher is active. Wrapped in try/catch at every
    step so one stuck subscription cannot prevent the rest of the cleanup.
    Returns the number of watchers it actually disposed (0 or 1) so callers
    can log activity.

    Call this:
      * At the top of Initialize-QOTicketsUI before creating a fresh watcher,
        so a module reload doesn't stack old watchers on top of new ones.
      * From the window Closing handler so the watcher does not outlive the UI.
    #>
    $disposed = 0

    try {
        foreach ($evt in @($script:TicketsFileWatcherEvents)) {
            if (-not $evt) { continue }
            try { Unregister-Event -SubscriptionId $evt.Id -ErrorAction SilentlyContinue } catch { }
        }
    } catch { }
    $script:TicketsFileWatcherEvents = @()

    if ($script:TicketsFileWatcher) {
        try { $script:TicketsFileWatcher.EnableRaisingEvents = $false } catch { }
        try {
            $script:TicketsFileWatcher.Dispose()
            $disposed = 1
        }
        catch {
            try { Write-QOTicketsUILog ("Tickets: Stop-QOTicketsFileWatcher Dispose failed. " + $_.Exception.Message) "WARN" } catch { }
        }
        $script:TicketsFileWatcher = $null
    }

    if ($disposed -gt 0) {
        try { Write-QOTicketsUILog "Tickets: File watcher disposed and subscriptions cleared." } catch { }
    }
    return $disposed
}

function Initialize-QOTicketsUI {
    param([Parameter(Mandatory)]$Window)

    Add-Type -AssemblyName PresentationFramework | Out-Null
    Write-QOTicketsUILog "Tickets: Initialize-QOTicketsUI start."

    # Clear any handlers tracked from a previous module load before re-registering.
    # This prevents handlers stacking up if Initialize-QOTicketsUI is called more than once.
    try { Unregister-QOTicketEventHandlers } catch { Write-QOTicketsUILog ("Tickets: Pre-init handler cleanup failed: " + $_.Exception.Message) "WARN" }

    # Capture core commands now
    $getTicketsCmd = $null
    $getTicketsCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketsByBucket -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketsByBucket"
    if (-not $getTicketsCmd) {
        $getTicketsCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketsByFolder -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketsByFolder"
    }
    if (-not $getTicketsCmd) {
        $getTicketsCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTickets -ErrorAction SilentlyContinue) -CommandName "Get-QOTickets"
    }

    $newTicketCmd  = Resolve-QOTInvokable -Candidate (Get-Command New-QOTicket -ErrorAction SilentlyContinue) -CommandName "New-QOTicket"
    $addTicketCmd  = Resolve-QOTInvokable -Candidate (Get-Command Add-QOTicket -ErrorAction SilentlyContinue) -CommandName "Add-QOTicket"
    $updateTicketCmd = Resolve-QOTInvokable -Candidate (Get-Command Update-QOTicket -ErrorAction SilentlyContinue) -CommandName "Update-QOTicket"
    $removeCmd     = Resolve-QOTInvokable -Candidate (Get-Command Remove-QOTicket -ErrorAction SilentlyContinue) -CommandName "Remove-QOTicket"
    $restoreCmd    = Resolve-QOTInvokable -Candidate (Get-Command Restore-QOTickets -ErrorAction SilentlyContinue) -CommandName "Restore-QOTickets"
    $setStatusCmd  = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTicketsStatus -ErrorAction SilentlyContinue) -CommandName "Set-QOTicketsStatus"
    $setPriorityCmd = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTicketsPriority -ErrorAction SilentlyContinue) -CommandName "Set-QOTicketsPriority"
    $setAssignedToCmd = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTicketsAssignedTo -ErrorAction SilentlyContinue) -CommandName "Set-QOTicketsAssignedTo"
    $addNoteCmd = Resolve-QOTInvokable -Candidate (Get-Command Add-QOTicketNote -ErrorAction SilentlyContinue) -CommandName "Add-QOTicketNote"
    $renameTicketCmd = Resolve-QOTInvokable -Candidate (Get-Command Rename-QOTicket -ErrorAction SilentlyContinue) -CommandName "Rename-QOTicket"
    $sendReplyCmd = Resolve-QOTInvokable -Candidate (Get-Command Send-QOTicketReply -ErrorAction SilentlyContinue) -CommandName "Send-QOTicketReply"
    $getCurrentAssigneeCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTCurrentAssigneeValue -ErrorAction SilentlyContinue) -CommandName "Get-QOTCurrentAssigneeValue"
    $updateReadTrackingCmd = Resolve-QOTInvokable -Candidate (Get-Command Update-QOTicketReadTracking -ErrorAction SilentlyContinue) -CommandName "Update-QOTicketReadTracking"
    $getParentVisualCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOParentVisual -ErrorAction SilentlyContinue) -CommandName "Get-QOParentVisual"
    $getSelectedTicketsCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTSelectedTickets -ErrorAction SilentlyContinue) -CommandName "Get-QOTSelectedTickets"
    $getStatusesCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketStatuses -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketStatuses"
    $getPrioritiesCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketPriorities -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketPriorities"
    $getAssigneesCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketAssignees -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketAssignees"
    $getStorePathCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketsStorePath -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketsStorePath"
    $getMonitoredMailboxesCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction SilentlyContinue) -CommandName "Get-QOMonitoredMailboxAddresses"
    if (-not $getMonitoredMailboxesCmd) {
        $getMonitoredMailboxesCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOMonitoredAddresses -ErrorAction SilentlyContinue) -CommandName "Get-QOMonitoredAddresses"
    }

    $syncCmd = Resolve-QOTInvokable -Candidate (Get-Command Sync-QOTicketsFromEmail -ErrorAction SilentlyContinue) -CommandName "Sync-QOTicketsFromEmail"

    $getTicketsCmd = Resolve-QOTInvokable -Candidate $getTicketsCmd -CommandName "Get-QOTicketsByBucket"
    $newTicketCmd = Resolve-QOTInvokable -Candidate $newTicketCmd -CommandName "New-QOTicket"
    $addTicketCmd = Resolve-QOTInvokable -Candidate $addTicketCmd -CommandName "Add-QOTicket"
    $updateTicketCmd = Resolve-QOTInvokable -Candidate $updateTicketCmd -CommandName "Update-QOTicket"
    $removeCmd = Resolve-QOTInvokable -Candidate $removeCmd -CommandName "Remove-QOTicket"
    $restoreCmd = Resolve-QOTInvokable -Candidate $restoreCmd -CommandName "Restore-QOTickets"
    $setStatusCmd = Resolve-QOTInvokable -Candidate $setStatusCmd -CommandName "Set-QOTicketsStatus"
    $setPriorityCmd = Resolve-QOTInvokable -Candidate $setPriorityCmd -CommandName "Set-QOTicketsPriority"
    $setAssignedToCmd = Resolve-QOTInvokable -Candidate $setAssignedToCmd -CommandName "Set-QOTicketsAssignedTo"
    $addNoteCmd = Resolve-QOTInvokable -Candidate $addNoteCmd -CommandName "Add-QOTicketNote"
    $renameTicketCmd = Resolve-QOTInvokable -Candidate $renameTicketCmd -CommandName "Rename-QOTicket"
    $sendReplyCmd = Resolve-QOTInvokable -Candidate $sendReplyCmd -CommandName "Send-QOTicketReply"
    $getCurrentAssigneeCmd = Resolve-QOTInvokable -Candidate $getCurrentAssigneeCmd -CommandName "Get-QOTCurrentAssigneeValue"
    $updateReadTrackingCmd = Resolve-QOTInvokable -Candidate $updateReadTrackingCmd -CommandName "Update-QOTicketReadTracking"
    $getParentVisualCmd = Resolve-QOTInvokable -Candidate $getParentVisualCmd -CommandName "Get-QOParentVisual"
    $getSelectedTicketsCmd = Resolve-QOTInvokable -Candidate $getSelectedTicketsCmd -CommandName "Get-QOTSelectedTickets"
    $getVisualChildByTypeCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOVisualChildByType -ErrorAction SilentlyContinue) -CommandName "Get-QOVisualChildByType"
    if (-not $getVisualChildByTypeCmd) {
        try { $getVisualChildByTypeCmd = ${function:Get-QOVisualChildByType} } catch { $getVisualChildByTypeCmd = $null }
    }
    $getStatusesCmd = Resolve-QOTInvokable -Candidate $getStatusesCmd -CommandName "Get-QOTicketStatuses"
    $getPrioritiesCmd = Resolve-QOTInvokable -Candidate $getPrioritiesCmd -CommandName "Get-QOTicketPriorities"
    $getAssigneesCmd = Resolve-QOTInvokable -Candidate $getAssigneesCmd -CommandName "Get-QOTicketAssignees"
    $getStorePathCmd = Resolve-QOTInvokable -Candidate $getStorePathCmd -CommandName "Get-QOTicketsStorePath"
    $setTicketListViewCmd = Resolve-QOTicketsLocalFunction -Name "Set-QOTicketListViewSettings"
    if (-not $setTicketListViewCmd) {
        $setTicketListViewCmd = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTicketListViewSettings -ErrorAction SilentlyContinue) -CommandName "Set-QOTicketListViewSettings"
    }
    $syncCmd = Resolve-QOTInvokable -Candidate $syncCmd -CommandName "Sync-QOTicketsFromEmail"
    if ($syncCmd) {
        $syncCmdNameResolved = ""
        try { $syncCmdNameResolved = [string]$syncCmd.Name } catch { $syncCmdNameResolved = [string]$syncCmd }
        Write-QOTicketsUILog ("Tickets: Sync command resolved: " + $syncCmdNameResolved)
    } else {
        Write-QOTicketsUILog "Tickets: Sync command could not be resolved in Initialize-QOTicketsUI." "WARN"
    }
    $invokeGridRefreshCmd = Resolve-QOTInvokable -Candidate (Get-Command Invoke-QOTicketsGridRefresh -ErrorAction SilentlyContinue) -CommandName "Invoke-QOTicketsGridRefresh"
    if (-not $invokeGridRefreshCmd) {
        try { $invokeGridRefreshCmd = ${function:Invoke-QOTicketsGridRefresh} } catch { $invokeGridRefreshCmd = $null }
    }
    $invokeEmailSyncRefreshCmd = Resolve-QOTInvokable -Candidate (Get-Command Invoke-QOTicketsEmailSyncAndRefresh -ErrorAction SilentlyContinue) -CommandName "Invoke-QOTicketsEmailSyncAndRefresh"
    if (-not $invokeEmailSyncRefreshCmd) {
        try { $invokeEmailSyncRefreshCmd = ${function:Invoke-QOTicketsEmailSyncAndRefresh} } catch { $invokeEmailSyncRefreshCmd = $null }
    }
    $invokeTicketStatusChangeCmd = Resolve-QOTInvokable -Candidate (Get-Command Invoke-QOTicketStatusChangeForItems -ErrorAction SilentlyContinue) -CommandName "Invoke-QOTicketStatusChangeForItems"
    if (-not $invokeTicketStatusChangeCmd) {
        try { $invokeTicketStatusChangeCmd = ${function:Invoke-QOTicketStatusChangeForItems} } catch { $invokeTicketStatusChangeCmd = $null }
    }
    $invokeTicketAssigneeChangeCmd = Resolve-QOTInvokable -Candidate (Get-Command Invoke-QOTicketAssigneeChangeForItems -ErrorAction SilentlyContinue) -CommandName "Invoke-QOTicketAssigneeChangeForItems"
    if (-not $invokeTicketAssigneeChangeCmd) {
        try { $invokeTicketAssigneeChangeCmd = ${function:Invoke-QOTicketAssigneeChangeForItems} } catch { $invokeTicketAssigneeChangeCmd = $null }
    }
    $invokeTicketPriorityChangeCmd = Resolve-QOTInvokable -Candidate (Get-Command Invoke-QOTicketPriorityChangeForItems -ErrorAction SilentlyContinue) -CommandName "Invoke-QOTicketPriorityChangeForItems"
    if (-not $invokeTicketPriorityChangeCmd) {
        try { $invokeTicketPriorityChangeCmd = ${function:Invoke-QOTicketPriorityChangeForItems} } catch { $invokeTicketPriorityChangeCmd = $null }
    }
    $updateTicketDetailsViewCmd = Resolve-QOTInvokable -Candidate (Get-Command Update-QOTicketDetailsView -ErrorAction SilentlyContinue) -CommandName "Update-QOTicketDetailsView"
    if (-not $updateTicketDetailsViewCmd) {
        try { $updateTicketDetailsViewCmd = ${function:Update-QOTicketDetailsView} } catch { $updateTicketDetailsViewCmd = $null }
    }
    try {
        if (${function:Update-QOTicketDetailsView}) {
            $updateTicketDetailsViewCmd = ${function:Update-QOTicketDetailsView}.GetNewClosure()
        }
    } catch { }
    $getTicketDetailsBodyTextCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketDetailsBodyText -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketDetailsBodyText"
    if (-not $getTicketDetailsBodyTextCmd) {
        try { $getTicketDetailsBodyTextCmd = ${function:Get-QOTicketDetailsBodyText} } catch { $getTicketDetailsBodyTextCmd = $null }
    }
    try {
        if (${function:Get-QOTicketDetailsBodyText}) {
            $getTicketDetailsBodyTextCmd = ${function:Get-QOTicketDetailsBodyText}.GetNewClosure()
        }
    } catch { }
    $resolveTicketDetailsSourceCmd = Resolve-QOTicketsLocalFunction -Name "Resolve-QOTTicketDetailsSourceTicket"
    if (-not $resolveTicketDetailsSourceCmd) {
        $resolveTicketDetailsSourceCmd = Resolve-QOTInvokable -Candidate (Get-Command Resolve-QOTTicketDetailsSourceTicket -ErrorAction SilentlyContinue) -CommandName "Resolve-QOTTicketDetailsSourceTicket"
    }
    $setTicketDetailsBodyContentCmd = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTicketDetailsBodyContent -ErrorAction SilentlyContinue) -CommandName "Set-QOTicketDetailsBodyContent"
    if (-not $setTicketDetailsBodyContentCmd) {
        try { $setTicketDetailsBodyContentCmd = ${function:Set-QOTicketDetailsBodyContent} } catch { $setTicketDetailsBodyContentCmd = $null }
    }
    try {
        if (${function:Set-QOTicketDetailsBodyContent}) {
            $setTicketDetailsBodyContentCmd = ${function:Set-QOTicketDetailsBodyContent}.GetNewClosure()
        }
    } catch { }
    $setTicketDetailsVisibilityCmd = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTicketDetailsVisibility -ErrorAction SilentlyContinue) -CommandName "Set-QOTicketDetailsVisibility"
    if (-not $setTicketDetailsVisibilityCmd) {
        try { $setTicketDetailsVisibilityCmd = ${function:Set-QOTicketDetailsVisibility} } catch { $setTicketDetailsVisibilityCmd = $null }
    }
    try {
        if (${function:Set-QOTicketDetailsVisibility}) {
            $setTicketDetailsVisibilityCmd = ${function:Set-QOTicketDetailsVisibility}.GetNewClosure()
        }
    } catch { }
    $getTicketSelectionKeyCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketSelectionKey -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketSelectionKey"
    if (-not $getTicketSelectionKeyCmd) {
        try { $getTicketSelectionKeyCmd = ${function:Get-QOTicketSelectionKey} } catch { $getTicketSelectionKeyCmd = $null }
    }
    try {
        if (${function:Get-QOTicketSelectionKey}) {
            $getTicketSelectionKeyCmd = ${function:Get-QOTicketSelectionKey}.GetNewClosure()
        }
    } catch { }
    $getTicketLogLabelCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketLogLabel -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketLogLabel"
    if (-not $getTicketLogLabelCmd) {
        try { $getTicketLogLabelCmd = ${function:Get-QOTicketLogLabel} } catch { $getTicketLogLabelCmd = $null }
    }
    try {
        if (${function:Get-QOTicketLogLabel}) {
            $getTicketLogLabelCmd = ${function:Get-QOTicketLogLabel}.GetNewClosure()
        }
    } catch { }
    $getTicketIdValueCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketIdValue -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketIdValue"
    $getOptimisticReplyEntriesCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketsOptimisticReplyEntries -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketsOptimisticReplyEntries"
    if (-not $getOptimisticReplyEntriesCmd) {
        $getOptimisticReplyEntriesCmd = Resolve-QOTicketsLocalFunction -Name "Get-QOTicketsOptimisticReplyEntries"
    }
    $getQueuedReplyEntriesCmd = Resolve-QOTicketsLocalFunction -Name "Get-QOTicketsQueuedReplyEntries"
    $mergeVisiblePendingRepliesCmd = Resolve-QOTicketsLocalFunction -Name "Merge-QOTTicketVisiblePendingReplyEntries"
    $addOptimisticReplyCmd = Resolve-QOTInvokable -Candidate (Get-Command Add-QOTicketsOptimisticReply -ErrorAction SilentlyContinue) -CommandName "Add-QOTicketsOptimisticReply"
    $setOptimisticReplyStateCmd = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTicketsOptimisticReplyState -ErrorAction SilentlyContinue) -CommandName "Set-QOTicketsOptimisticReplyState"
    $removeOptimisticReplyCmd = Resolve-QOTInvokable -Candidate (Get-Command Remove-QOTicketsOptimisticReply -ErrorAction SilentlyContinue) -CommandName "Remove-QOTicketsOptimisticReply"
    $removeResolvedOptimisticRepliesCmd = Resolve-QOTInvokable -Candidate (Get-Command Remove-QOTicketsResolvedOptimisticReplies -ErrorAction SilentlyContinue) -CommandName "Remove-QOTicketsResolvedOptimisticReplies"
    $getLatestFailedOptimisticReplyCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketsLatestFailedOptimisticReply -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketsLatestFailedOptimisticReply"
    $getTicketPendingRepliesCmd = Resolve-QOTInvokable -Candidate (Get-Command Get-QOTicketPendingReplies -ErrorAction SilentlyContinue) -CommandName "Get-QOTicketPendingReplies"
    $addTicketPendingReplyCmd = Resolve-QOTInvokable -Candidate (Get-Command Add-QOTTicketPendingReply -ErrorAction SilentlyContinue) -CommandName "Add-QOTTicketPendingReply"
    $setTicketPendingReplyStateCmd = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTTicketPendingReplyState -ErrorAction SilentlyContinue) -CommandName "Set-QOTTicketPendingReplyState"
    $queueTicketPendingReplyCmd = Resolve-QOTInvokable -Candidate (Get-Command Queue-QOTTicketPendingReply -ErrorAction SilentlyContinue) -CommandName "Queue-QOTTicketPendingReply"
    $retryTicketPendingReplyCmd = Resolve-QOTInvokable -Candidate (Get-Command Retry-QOTTicketPendingReply -ErrorAction SilentlyContinue) -CommandName "Retry-QOTTicketPendingReply"
    $cancelTicketPendingReplyCmd = Resolve-QOTInvokable -Candidate (Get-Command Cancel-QOTTicketPendingReply -ErrorAction SilentlyContinue) -CommandName "Cancel-QOTTicketPendingReply"
    $initializeReplyQueueServiceCmd = Resolve-QOTInvokable -Candidate (Get-Command Initialize-QOTicketsReplyQueueService -ErrorAction SilentlyContinue) -CommandName "Initialize-QOTicketsReplyQueueService"
    $applyTicketsMenuItemThemeCmd = Resolve-QOTicketsLocalFunction -Name "Apply-QOTTicketsMenuItemTheme"
    if (-not $applyTicketsMenuItemThemeCmd) {
        try { $applyTicketsMenuItemThemeCmd = ${function:Apply-QOTTicketsMenuItemTheme} } catch { $applyTicketsMenuItemThemeCmd = $null }
    }
    $applyTicketsContextMenuThemeCmd = Resolve-QOTicketsLocalFunction -Name "Apply-QOTTicketsContextMenuTheme"
    if (-not $applyTicketsContextMenuThemeCmd) {
        try { $applyTicketsContextMenuThemeCmd = ${function:Apply-QOTTicketsContextMenuTheme} } catch { $applyTicketsContextMenuThemeCmd = $null }
    }
    $newTicketsStyledSeparatorCmd = Resolve-QOTicketsLocalFunction -Name "New-QOTTicketsStyledSeparator"
    if (-not $newTicketsStyledSeparatorCmd) {
        try { $newTicketsStyledSeparatorCmd = ${function:New-QOTTicketsStyledSeparator} } catch { $newTicketsStyledSeparatorCmd = $null }
    }
    $stopIncrementalMergeLocalCmd = Resolve-QOTicketsLocalFunction -Name "Stop-QOTicketsIncrementalMerge"
    if (-not $stopIncrementalMergeLocalCmd) {
        try { $stopIncrementalMergeLocalCmd = ${function:Stop-QOTicketsIncrementalMerge} } catch { $stopIncrementalMergeLocalCmd = $null }
    }

    # Capture UI local function commands
    

    # Capture stable local references
    $grid       = $Window.FindName("TicketsGrid")
    $btnNew     = $Window.FindName("BtnNewTicket")
    $btnDelete  = $Window.FindName("BtnDeleteTicket")
    $btnFilterMenu = $Window.FindName("BtnTicketsFilterMenu")

    $ticketsHeaderTitleText = $Window.FindName("TicketsHeaderTitleText")
    $syncStatusText = $Window.FindName("TicketsSyncStatusText")
    $btnToggleDetails = $Window.FindName("BtnToggleTicketDetails")
    $detailsPanel = $Window.FindName("TicketDetailsPanel")
    $detailsChevron = $Window.FindName("TicketDetailsChevron")
    $ticketBodyText = $Window.FindName("TicketEmailBodyText")
    $ticketSummaryHeaderText = $Window.FindName("TicketSummaryHeaderText")
    $ticketContactAvatar = $Window.FindName("TicketContactAvatar")
    $ticketContactAvatarText = $Window.FindName("TicketContactAvatarText")
    $ticketContactPrimaryText = $Window.FindName("TicketContactPrimaryText")
    $ticketContactMetaText = $Window.FindName("TicketContactMetaText")
    $ticketContactStatusDot = $Window.FindName("TicketContactStatusDot")
    $btnComposeInternalNote = $Window.FindName("BtnComposeInternalNote")
    $btnComposeReplyCustomer = $Window.FindName("BtnComposeReplyCustomer")
    $ticketComposeSubjectRow = $Window.FindName("TicketComposeSubjectRow")
    $ticketReplySubject = $Window.FindName("TicketReplySubject")
    $ticketReplyText = $Window.FindName("TicketReplyText")
    $ticketReplyStatusText = $Window.FindName("TicketReplyStatusText")
    $btnSendReply = $Window.FindName("BtnSendTicketReply")
    $btnRetryFailedReply = $Window.FindName("BtnRetryFailedTicketReply")
    Write-QOTicketsUILog "Tickets: Control lookup completed."

    if (-not $grid)       { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null; return }
    if (-not $btnNew)     { [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null; return }
    if (-not $btnDelete)  { [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null; return }
    if (-not $btnFilterMenu) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnTicketsFilterMenu") | Out-Null; return }

    if (-not $syncStatusText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketsSyncStatusText") | Out-Null; return }
    
    if (-not $btnToggleDetails) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnToggleTicketDetails") | Out-Null; return }
    if (-not $detailsPanel) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsPanel") | Out-Null; return }
    if (-not $detailsChevron) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketDetailsChevron") | Out-Null; return }
    if (-not $ticketBodyText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketEmailBodyText") | Out-Null; return }
    if (-not $ticketContactAvatar) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketContactAvatar") | Out-Null; return }
    if (-not $ticketContactAvatarText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketContactAvatarText") | Out-Null; return }
    if (-not $ticketContactPrimaryText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketContactPrimaryText") | Out-Null; return }
    if (-not $ticketContactMetaText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketContactMetaText") | Out-Null; return }
    if (-not $ticketContactStatusDot) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketContactStatusDot") | Out-Null; return }
    if (-not $btnComposeInternalNote) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnComposeInternalNote") | Out-Null; return }
    if (-not $btnComposeReplyCustomer) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnComposeReplyCustomer") | Out-Null; return }
    if (-not $ticketComposeSubjectRow) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketComposeSubjectRow") | Out-Null; return }
    if (-not $ticketReplySubject) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketReplySubject") | Out-Null; return }
    if (-not $ticketReplyText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketReplyText") | Out-Null; return }
    if (-not $ticketReplyStatusText) { [System.Windows.MessageBox]::Show("Missing XAML control: TicketReplyStatusText") | Out-Null; return }
    if (-not $btnSendReply) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnSendTicketReply") | Out-Null; return }
    if (-not $btnRetryFailedReply) { [System.Windows.MessageBox]::Show("Missing XAML control: BtnRetryFailedTicketReply") | Out-Null; return }

    $script:TicketsGrid = $grid
    $script:TicketsDetailsPanel = $detailsPanel
    $script:TicketsDetailsChevron = $detailsChevron
    $script:TicketsHeaderTitleText = $ticketsHeaderTitleText
    $script:TicketsSummaryHeaderText = $ticketSummaryHeaderText
    $script:TicketsContactAvatar = $ticketContactAvatar
    $script:TicketsContactAvatarText = $ticketContactAvatarText
    $script:TicketsContactPrimaryText = $ticketContactPrimaryText
    $script:TicketsContactMetaText = $ticketContactMetaText
    $script:TicketsContactStatusDot = $ticketContactStatusDot
    $script:TicketsBodyText = $ticketBodyText
    $script:TicketsComposeInternalButton = $btnComposeInternalNote
    $script:TicketsComposeReplyButton = $btnComposeReplyCustomer
    $script:TicketsComposeSubjectRow = $ticketComposeSubjectRow
    $script:TicketsReplySubject = $ticketReplySubject
    $script:TicketsReplyText = $ticketReplyText
    $script:TicketsReplyStatusText = $ticketReplyStatusText
    $script:TicketsReplyButton = $btnSendReply
    $script:TicketsRetryReplyButton = $btnRetryFailedReply
    $script:TicketsSyncStatusText = $syncStatusText
    $script:TicketsWindow = $Window
    $script:TicketsEmailSyncInProgress = $false
    $script:TicketsOpenDetailsInProgress = $false
    $script:TicketsOpenFromContextCmd = $null
    $script:TicketsLastLeftClickUtc = [datetime]::MinValue
    $script:TicketsLastLeftClickTicketKey = ""
    $script:TicketsSyncActiveRunId = 0
    $script:TicketsSyncRunCounter = [int]$script:TicketsSyncRunCounter
    $script:TicketsSyncLastStartUtc = [datetime]::MinValue
    $script:TicketsSyncActiveTimeoutSeconds = 0
    Clear-QOTicketsSyncExecutionState
    try {
        if (-not $script:TicketsLastSuccessfulSyncUtc -or $script:TicketsLastSuccessfulSyncUtc -eq [datetime]::MinValue) {
            $persistedLastSyncUtc = Get-QOTicketsPersistedLastSuccessfulSyncUtc
            if ($persistedLastSyncUtc -and $persistedLastSyncUtc -is [datetime]) {
                $script:TicketsLastSuccessfulSyncUtc = [datetime]::SpecifyKind($persistedLastSyncUtc, [System.DateTimeKind]::Utc)
            }
        }
    } catch { }
    Write-QOTicketsUILog "Tickets: Double-click handler patch active (2026-03-11)."
    try { if ($script:TicketsHeaderTitleText) { $script:TicketsHeaderTitleText.Text = "Tickets" } } catch { }
    try { Set-QOTicketContactHeader -Ticket $null } catch { }

    $getConfiguredSenderMailboxes = {
        try {
            if (-not $getMonitoredMailboxesCmd) { return @() }
            return @(
                @(& $getMonitoredMailboxesCmd) |
                    ForEach-Object { ([string]($_ + "")).Trim() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )
        } catch {
            return @()
        }
    }.GetNewClosure()

    $getPrimaryTicketEmailAddress = {
        param([AllowNull()]$Ticket)
        if (-not $Ticket) { return "" }

        foreach ($propName in @("EmailTo", "SenderEmail", "ContactEmail", "EmailFrom")) {
            $rawValue = ""
            try {
                if ($Ticket.PSObject.Properties.Name -contains $propName) {
                    $rawValue = ([string]($Ticket.$propName + "")).Trim()
                }
            } catch { $rawValue = "" }
            if ([string]::IsNullOrWhiteSpace($rawValue)) { continue }

            $match = [regex]::Match($rawValue, '(?i)([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})')
            if ($match.Success) {
                return ([string]$match.Groups[1].Value).Trim()
            }
        }

        return ""
    }.GetNewClosure()

    $ticketHasReplyReference = {
        param([AllowNull()]$Ticket)
        if (-not $Ticket) { return $false }

        try {
            if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") {
                if (-not [string]::IsNullOrWhiteSpace([string]$Ticket.SourceMessageId)) { return $true }
            }
        } catch { }
        try {
            if ($Ticket.PSObject.Properties.Name -contains "EmailMessageId") {
                if (-not [string]::IsNullOrWhiteSpace([string]$Ticket.EmailMessageId)) { return $true }
            }
        } catch { }

        return $false
    }.GetNewClosure()

    $getPreferredSenderMailbox = {
        param([AllowNull()]$Ticket)

        $sourceMailbox = ""
        try {
            if ($Ticket -and ($Ticket.PSObject.Properties.Name -contains "SourceMailbox")) {
                $sourceMailbox = ([string]($Ticket.SourceMailbox + "")).Trim()
            }
        } catch { $sourceMailbox = "" }
        if (-not [string]::IsNullOrWhiteSpace($sourceMailbox)) {
            return $sourceMailbox
        }

        $configuredMailboxes = @(& $getConfiguredSenderMailboxes)
        if ($configuredMailboxes.Count -eq 1) {
            return ([string]$configuredMailboxes[0]).Trim()
        }

        return ""
    }.GetNewClosure()

    $canTicketReply = {
        param([AllowNull()]$Ticket)
        if (-not $Ticket) { return $false }
        try {
            if (& $ticketHasReplyReference $Ticket) { return $true }

            $recipientEmail = [string](& $getPrimaryTicketEmailAddress $Ticket)
            $senderMailbox = [string](& $getPreferredSenderMailbox $Ticket)
            if ((-not [string]::IsNullOrWhiteSpace($recipientEmail)) -and (-not [string]::IsNullOrWhiteSpace($senderMailbox))) {
                return $true
            }
        } catch { }
        return $false
    }.GetNewClosure()

    $isTicketVisibleInDetails = {
        param([AllowNull()][string]$TicketIdValue)

        $targetTicketId = ([string]($TicketIdValue + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($targetTicketId)) { return $false }

        return [bool](Test-QOTicketDetailsViewActive -TicketId $targetTicketId)
    }.GetNewClosure()

    $resolveVisibleTicketById = {
        param(
            [AllowNull()][string]$TicketIdValue,
            [switch]$AllowSelectedFallback
        )

        $targetTicketId = ([string]($TicketIdValue + "")).Trim()
        $resolvedTicket = $null

        if (-not [string]::IsNullOrWhiteSpace($targetTicketId)) {
            try {
                $resolvedTicket = @(
                    @($grid.ItemsSource) |
                        Where-Object {
                            if (-not $_) { return $false }
                            $candidateTicketId = ""
                            try {
                                if ($getTicketIdValueCmd) {
                                    $candidateTicketId = ([string](& $getTicketIdValueCmd -Ticket $_)).Trim()
                                } elseif ($_.PSObject.Properties.Name -contains "Id") {
                                    $candidateTicketId = ([string]($_.Id + "")).Trim()
                                }
                            } catch { $candidateTicketId = "" }
                            return [string]::Equals($candidateTicketId, $targetTicketId, [System.StringComparison]::OrdinalIgnoreCase)
                        } |
                        Select-Object -First 1
                )
                if ($resolvedTicket -is [System.Array]) {
                    if ($resolvedTicket.Count -gt 0) { $resolvedTicket = $resolvedTicket[0] } else { $resolvedTicket = $null }
                }
            } catch { $resolvedTicket = $null }
        }

        if (-not $resolvedTicket -and $AllowSelectedFallback) {
            try { $resolvedTicket = $grid.SelectedItem } catch { $resolvedTicket = $null }
            if ($resolvedTicket -and -not [string]::IsNullOrWhiteSpace($targetTicketId)) {
                $selectedTicketId = ""
                try {
                    if ($getTicketIdValueCmd) {
                        $selectedTicketId = ([string](& $getTicketIdValueCmd -Ticket $resolvedTicket)).Trim()
                    } elseif ($resolvedTicket.PSObject.Properties.Name -contains "Id") {
                        $selectedTicketId = ([string]($resolvedTicket.Id + "")).Trim()
                    }
                } catch { $selectedTicketId = "" }
                if (-not [string]::Equals($selectedTicketId, $targetTicketId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $resolvedTicket = $null
                }
            }
        }

        return $resolvedTicket
    }.GetNewClosure()

    $updateReplyComposeFeedback = {
        param([AllowNull()]$Ticket)

        try {
            if (-not $ticketReplyStatusText -and -not $btnRetryFailedReply) { return }

            $ticketId = ""
            try {
                if ($getTicketIdValueCmd) {
                    $ticketId = ([string](& $getTicketIdValueCmd -Ticket $Ticket)).Trim()
                } elseif ($Ticket -and ($Ticket.PSObject.Properties.Name -contains "Id")) {
                    $ticketId = ([string]($Ticket.Id + "")).Trim()
                }
            } catch { $ticketId = "" }

            if ($removeResolvedOptimisticRepliesCmd -and $Ticket -and -not [string]::IsNullOrWhiteSpace($ticketId)) {
                try { $null = & $removeResolvedOptimisticRepliesCmd -Ticket $Ticket -TicketId $ticketId } catch { }
            }

            $optimisticReplies = @()
            if (-not [string]::IsNullOrWhiteSpace($ticketId) -and $getOptimisticReplyEntriesCmd) {
                try { $optimisticReplies = @(& $getOptimisticReplyEntriesCmd -TicketId $ticketId) } catch { $optimisticReplies = @() }
            }
            $queuedReplySnapshots = @()
            if (-not [string]::IsNullOrWhiteSpace($ticketId)) {
                try {
                    if ($getQueuedReplyEntriesCmd) {
                        $queuedReplySnapshots = @(& $getQueuedReplyEntriesCmd -TicketId $ticketId)
                    } else {
                        $queuedReplySnapshots = @(Get-QOTicketsQueuedReplyEntries -TicketId $ticketId)
                    }
                } catch { $queuedReplySnapshots = @() }
            }
            if ($mergeVisiblePendingRepliesCmd) {
                $visibleReplyEntries = @(& $mergeVisiblePendingRepliesCmd -OptimisticReplies $optimisticReplies -QueuedReplies $queuedReplySnapshots)
            } else {
                $visibleReplyEntries = @(Merge-QOTTicketVisiblePendingReplyEntries -OptimisticReplies $optimisticReplies -QueuedReplies $queuedReplySnapshots)
            }

            $pendingReplies = @(
                $visibleReplyEntries |
                    Where-Object {
                        $_ -and
                        ($_.PSObject.Properties.Name -contains "SendState") -and
                        (([string]($_.SendState + "")).Trim() -match '^(?i)(Pending|Queued|Sending)$')
                    }
            )
            $sendingReplies = @(
                $pendingReplies |
                    Where-Object {
                        $_ -and
                        ($_.PSObject.Properties.Name -contains "SendState") -and
                        [string]::Equals(([string]($_.SendState + "")).Trim(), "Sending", [System.StringComparison]::OrdinalIgnoreCase)
                    }
            )
            $queuedReplies = @(
                $pendingReplies |
                    Where-Object {
                        $_ -and
                        ($_.PSObject.Properties.Name -contains "SendState") -and
                        (([string]($_.SendState + "")).Trim() -match '^(?i)(Queued|Pending)$')
                    }
            )

            $failedReply = $null
            if (-not [string]::IsNullOrWhiteSpace($ticketId) -and $getLatestFailedOptimisticReplyCmd) {
                try { $failedReply = & $getLatestFailedOptimisticReplyCmd -TicketId $ticketId } catch { $failedReply = $null }
            }
            if (-not $failedReply -and $queuedReplySnapshots.Count -gt 0) {
                try {
                    $failedReply = @(
                        $queuedReplySnapshots |
                            Where-Object {
                                if (-not $_) { return $false }
                                $entryState = ""
                                try { if ($_.PSObject.Properties.Name -contains "SendState") { $entryState = ([string]($_.SendState + "")).Trim() } } catch { $entryState = "" }
                                return [string]::Equals($entryState, "Failed", [System.StringComparison]::OrdinalIgnoreCase)
                            } |
                            Sort-Object -Property @(
                                @{ Expression = {
                                    try { if ($_.PSObject.Properties.Name -contains "LastAttemptAt") { return ([string]($_.LastAttemptAt + "")).Trim() } } catch { }
                                    return ""
                                }; Descending = $true },
                                @{ Expression = {
                                    try { if ($_.PSObject.Properties.Name -contains "DraftId") { return ([string]($_.DraftId + "")).Trim() } } catch { }
                                    return ""
                                }; Descending = $false }
                            ) |
                            Select-Object -First 1
                    )[0]
                } catch { $failedReply = $null }
            }

            if ($ticketReplyStatusText) {
                $ticketReplyStatusText.Visibility = "Collapsed"
                $ticketReplyStatusText.Text = ""
                $ticketReplyStatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#93C5FD")
            }
            if ($btnSendReply) {
                try {
                    $btnSendReply.Content = if ([string]::Equals([string]$script:TicketsComposeMode, "Note", [System.StringComparison]::OrdinalIgnoreCase)) { "Save internal note" } else { "Send reply" }
                } catch { }
            }
            if ($btnRetryFailedReply) {
                $btnRetryFailedReply.Visibility = "Collapsed"
                $btnRetryFailedReply.IsEnabled = $false
            }

            if ($pendingReplies.Count -gt 0) {
                if ($ticketReplyStatusText) {
                    $sendingCount = @($sendingReplies).Count
                    $queuedCount = @($queuedReplies).Count
                    if ($sendingCount -gt 0 -and $queuedCount -gt 0) {
                        $ticketReplyStatusText.Text = ("{0} sending, {1} queued in the background..." -f $sendingCount, $queuedCount)
                    } elseif ($sendingCount -gt 1) {
                        $ticketReplyStatusText.Text = ("{0} replies are sending in the background..." -f $sendingCount)
                    } elseif ($sendingCount -eq 1) {
                        $ticketReplyStatusText.Text = "Sending reply..."
                    } elseif ($queuedCount -gt 1) {
                        $ticketReplyStatusText.Text = ("{0} replies are queued to send..." -f $queuedCount)
                    } else {
                        $ticketReplyStatusText.Text = "Reply queued..."
                    }
                    $ticketReplyStatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#93C5FD")
                    $ticketReplyStatusText.Visibility = "Visible"
                }
                if ($btnSendReply -and [string]::Equals([string]$script:TicketsComposeMode, "Reply", [System.StringComparison]::OrdinalIgnoreCase)) {
                    try { $btnSendReply.IsEnabled = $true } catch { }
                    try { $btnSendReply.Content = "Send reply" } catch { }
                }
                return
            }

            if ($failedReply) {
                if ($ticketReplyStatusText) {
                    $ticketReplyStatusText.Text = "Reply failed. You can resend it."
                    $ticketReplyStatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FCA5A5")
                    $ticketReplyStatusText.Visibility = "Visible"
                }
            }
            if ($btnSendReply -and [string]::Equals([string]$script:TicketsComposeMode, "Reply", [System.StringComparison]::OrdinalIgnoreCase)) {
                try { $btnSendReply.IsEnabled = $true } catch { }
            }
        } catch {
            try { Write-QOTicketsUILog ("Tickets: Reply compose feedback update failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }.GetNewClosure()

    $setComposeMode = {
        param(
            [AllowNull()][string]$Mode,
            [switch]$PreserveText,
            [switch]$SkipFocus
        )

        try {
            $normalizedMode = if ([string]::Equals([string]$Mode, "Note", [System.StringComparison]::OrdinalIgnoreCase)) { "Note" } else { "Reply" }
            $script:TicketsComposeMode = $normalizedMode
            try {
                $composeTicketId = ([string]($script:TicketsActiveTicketId + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($composeTicketId)) {
                    if ($script:TicketsComposeModeByTicketId -isnot [hashtable]) {
                        $script:TicketsComposeModeByTicketId = @{}
                    }
                    $script:TicketsComposeModeByTicketId[$composeTicketId] = $normalizedMode
                }
            } catch { }
            $isNoteMode = ($normalizedMode -eq "Note")

            if ($btnComposeInternalNote) {
                $btnComposeInternalNote.Background = "Transparent"
                $btnComposeInternalNote.BorderBrush = "Transparent"
                $btnComposeInternalNote.BorderThickness = "0"
                $btnComposeInternalNote.Foreground = if ($isNoteMode) { "#60A5FA" } else { "#9CA3AF" }
                $btnComposeInternalNote.FontWeight = if ($isNoteMode) { "SemiBold" } else { "Normal" }
            }
            if ($btnComposeReplyCustomer) {
                $btnComposeReplyCustomer.Background = "Transparent"
                $btnComposeReplyCustomer.BorderBrush = "Transparent"
                $btnComposeReplyCustomer.BorderThickness = "0"
                $btnComposeReplyCustomer.Foreground = if ($isNoteMode) { "#9CA3AF" } else { "#60A5FA" }
                $btnComposeReplyCustomer.FontWeight = if ($isNoteMode) { "Normal" } else { "SemiBold" }
            }
            if ($ticketComposeSubjectRow) {
                $ticketComposeSubjectRow.Visibility = "Collapsed"
            }
            if ($btnSendReply) {
                $btnSendReply.Content = if ($isNoteMode) { "Save internal note" } else { "Send reply" }
                try {
                    $existingTag = $btnSendReply.Tag
                    if ($null -eq $existingTag -or $existingTag -isnot [psobject]) {
                        $existingTag = [pscustomobject]@{}
                    }
                    if ($existingTag.PSObject.Properties.Name -contains "ComposeAction") {
                        $existingTag.ComposeAction = $normalizedMode
                    } else {
                        $existingTag | Add-Member -NotePropertyName ComposeAction -NotePropertyValue $normalizedMode -Force
                    }
                    $btnSendReply.Tag = $existingTag
                } catch { }
            }
            if (-not $PreserveText) {
                try { if ($ticketReplyText) { $ticketReplyText.Text = "" } } catch { }
            }
            if (-not $SkipFocus) {
                try { if ($ticketReplyText) { $null = $ticketReplyText.Focus() } } catch { }
            }
        } catch {
            try { Write-QOTicketsUILog ("Tickets: Set compose mode failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }.GetNewClosure()

    $invokeDetailsUpdate = {
        param([AllowNull()]$Ticket)
        try {
            $detailsOpenStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            if (-not $Ticket) {
                try { $script:TicketsActiveTicketId = "" } catch { }
                try {
                    if ($ticketBodyText) {
                        if ($setTicketDetailsBodyContentCmd) {
                            & $setTicketDetailsBodyContentCmd -BodyControl $ticketBodyText -SummaryLines @() -Events @() -FallbackText "Double-click a ticket to view email body and reply."
                        } else {
                            Set-QOTicketDetailsBodyContent -BodyControl $ticketBodyText -SummaryLines @() -Events @() -FallbackText "Double-click a ticket to view email body and reply."
                        }
                    }
                } catch { }
                try { Set-QOTicketSummaryHeader -SummaryControl $ticketSummaryHeaderText -SummaryLines @() } catch { }
                try { Set-QOTicketContactHeader -Ticket $null } catch { }
                try { if ($ticketReplySubject) { $ticketReplySubject.Text = "" } } catch { }
                try { if ($ticketReplyText) { $ticketReplyText.Text = "" } } catch { }
                try { if ($btnSendReply) { $btnSendReply.IsEnabled = $false } } catch { }
                try { if ($ticketReplyStatusText) { $ticketReplyStatusText.Visibility = "Collapsed"; $ticketReplyStatusText.Text = "" } } catch { }
                try { if ($btnRetryFailedReply) { $btnRetryFailedReply.Visibility = "Collapsed"; $btnRetryFailedReply.IsEnabled = $false } } catch { }
                try { if ($btnComposeInternalNote) { $btnComposeInternalNote.IsEnabled = $false } } catch { }
                try { if ($btnComposeReplyCustomer) { $btnComposeReplyCustomer.IsEnabled = $false } } catch { }
                try { if ($ticketsHeaderTitleText) { $ticketsHeaderTitleText.Text = "Tickets" } } catch { }
                try { & $setComposeMode -Mode "Reply" -PreserveText:$false -SkipFocus } catch { }
                try {
                    if ($setTicketDetailsVisibilityCmd) {
                        & $setTicketDetailsVisibilityCmd -DetailsPanel $detailsPanel -Chevron $detailsChevron -TicketsGrid $grid -IsOpen:$false
                    } else {
                        Set-QOTicketDetailsVisibility -DetailsPanel $detailsPanel -Chevron $detailsChevron -TicketsGrid $grid -IsOpen:$false
                    }
                } catch { }
                return
            }

            $detailsTicket = $Ticket
            $detailsRenderModel = $null
            $requestedTicketId = ""
            $openGeneration = 0
            try { $requestedTicketId = Get-QOTicketIdValue -Ticket $Ticket } catch { $requestedTicketId = "" }
            try { $script:TicketsDetailsViewClosing = $false } catch { }
            try { $script:TicketsDetailsViewGeneration = [int]$script:TicketsDetailsViewGeneration + 1 } catch { $script:TicketsDetailsViewGeneration = 1 }
            try { $openGeneration = [int]$script:TicketsDetailsViewGeneration } catch { $openGeneration = 0 }
            try { $script:TicketsActiveTicketId = $requestedTicketId } catch { }
            try { Write-QOTicketsUILog ("Tickets: Timeline refresh start. TicketId='{0}' RenderPath='InitialOpen' Generation={1}." -f $requestedTicketId, $openGeneration) } catch { }

            # CRITICAL: Resolve ticket to get fresh data from store BEFORE building render model
            # This ensures notes and replies from Tickets.json are loaded on first open
            try {
                if ($resolveTicketDetailsSourceCmd) {
                    $detailsTicket = & $resolveTicketDetailsSourceCmd -Ticket $Ticket
                } else {
                    $detailsTicket = Resolve-QOTTicketDetailsSourceTicket -Ticket $Ticket
                }
            } catch { $detailsTicket = $Ticket }
            if (-not $detailsTicket) { $detailsTicket = $Ticket }

            # Now build render model from the fresh ticket data
            try {
                $resolveRenderModelCmd = Resolve-QOTicketsLocalFunction -Name "Get-QOTTicketDetailsRenderModel"
                if ($resolveRenderModelCmd) {
                    $detailsRenderModel = & $resolveRenderModelCmd -Ticket $detailsTicket -RenderPath "InitialOpen" -PreferCurrentTicket -PreferCachedPendingReplies
                } else {
                    $detailsRenderModel = Get-QOTTicketDetailsRenderModel -Ticket $detailsTicket -RenderPath "InitialOpen" -PreferCurrentTicket -PreferCachedPendingReplies
                }
            } catch { $detailsRenderModel = $null }

            # Update the original ticket object with resolved data
            try {
                if ($Ticket -and $detailsTicket -and -not [object]::ReferenceEquals($Ticket, $detailsTicket)) {
                    $null = Update-QOTicketObjectFromSource -Target $Ticket -Source $detailsTicket
                }
            } catch { }
            try { $detailsTicket = Sync-QOTTicketLivePendingReplies -Ticket $detailsTicket -PreferCached } catch { }
            try {
                $resolvedOpenTicketId = Get-QOTicketIdValue -Ticket $detailsTicket
                if ([string]::IsNullOrWhiteSpace($requestedTicketId)) {
                    $requestedTicketId = $resolvedOpenTicketId
                    $script:TicketsActiveTicketId = $requestedTicketId
                }
                if (-not (Test-QOTicketDetailsViewActive -TicketId $requestedTicketId -Generation $openGeneration -AllowCollapsed)) {
                    Write-QOTicketsUILog ("Tickets: Timeline refresh ignored after initial hydration because ticket/view is no longer active. TicketId='{0}' ActiveTicketId='{1}' Generation={2}/{3}." -f $requestedTicketId, ([string]($script:TicketsActiveTicketId + "")).Trim(), $openGeneration, $script:TicketsDetailsViewGeneration)
                    return
                }
            } catch { }
            try {
                $needsLocalTimelineRebuild = $false
                $localActivityCount = 0
                foreach ($activityProp in @("Notes", "Replies", "PendingReplies")) {
                    try {
                        if ($detailsTicket -and ($detailsTicket.PSObject.Properties.Name -contains $activityProp)) {
                            $localActivityCount += @($detailsTicket.$activityProp | Where-Object { $_ }).Count
                        }
                    } catch { }
                }
                $existingEventCount = 0
                try { if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "Events")) { $existingEventCount = @($detailsRenderModel.Events).Count } } catch { $existingEventCount = 0 }
                $needsLocalTimelineRebuild = ($localActivityCount -gt 0 -and $existingEventCount -le 1)
                if ($needsLocalTimelineRebuild) {
                    $rebuildRenderModelCmd = Resolve-QOTicketsLocalFunction -Name "Get-QOTTicketDetailsRenderModel"
                    if ($rebuildRenderModelCmd) {
                        $detailsRenderModel = & $rebuildRenderModelCmd -Ticket $detailsTicket -RenderPath "InitialOpenLocal" -PreferCurrentTicket -PreferCachedPendingReplies
                    } else {
                        $detailsRenderModel = Get-QOTTicketDetailsRenderModel -Ticket $detailsTicket -RenderPath "InitialOpenLocal" -PreferCurrentTicket -PreferCachedPendingReplies
                    }
                    try { Write-QOTicketsUILog ("Tickets: Initial timeline rebuilt from local hydrated state. TicketId='{0}' ActivityCount={1}." -f $requestedTicketId, $localActivityCount) } catch { }
                }
            } catch { }
            try {
                $selectedLogBodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $Ticket
                $resolvedLogBodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $detailsTicket
                Write-QOTicketsUILog ("Tickets: Details render target. Input={0}; Resolved={1}; InputBody={2}/{3}/{4}; ResolvedBody={5}/{6}/{7}" -f `
                    (Get-QOTicketLogLabel -Ticket $Ticket), `
                    (Get-QOTicketLogLabel -Ticket $detailsTicket), `
                    $selectedLogBodyInfo.Source, `
                    $selectedLogBodyInfo.Property, `
                    $selectedLogBodyInfo.Length, `
                    $resolvedLogBodyInfo.Source, `
                    $resolvedLogBodyInfo.Property, `
                    $resolvedLogBodyInfo.Length)
            } catch { }

            try {
                $activeId = ""
                if ($detailsTicket.PSObject.Properties.Name -contains "Id") {
                    $activeId = ([string]($detailsTicket.Id + "")).Trim()
                }
                $script:TicketsActiveTicketId = $activeId
                $notesOnOpen = 0
                $repliesOnOpen = 0
                $pendingOnOpen = 0
                try { if ($detailsTicket.PSObject.Properties.Name -contains "Notes") { $notesOnOpen = @($detailsTicket.Notes | Where-Object { $_ }).Count } } catch { $notesOnOpen = 0 }
                try { if ($detailsTicket.PSObject.Properties.Name -contains "Replies") { $repliesOnOpen = @($detailsTicket.Replies | Where-Object { $_ }).Count } } catch { $repliesOnOpen = 0 }
                try { if ($detailsTicket.PSObject.Properties.Name -contains "PendingReplies") { $pendingOnOpen = @($detailsTicket.PendingReplies | Where-Object { $_ }).Count } } catch { $pendingOnOpen = 0 }
                Write-QOTicketsUILog ("Tickets: Ticket reopened. TicketId='{0}' Notes={1} Replies={2} PendingReplies={3}." -f $activeId, $notesOnOpen, $repliesOnOpen, $pendingOnOpen)
                Write-QOTicketsUILog ("Tickets: Ticket opened. TicketId='{0}'." -f $activeId)
                Write-QOTicketsUILog ("Tickets: Persisted notes count loaded. TicketId='{0}' Count={1}." -f $activeId, $notesOnOpen)
                Write-QOTicketsUILog ("Tickets: Persisted reply count loaded. TicketId='{0}' Replies={1} PendingReplies={2}." -f $activeId, $repliesOnOpen, $pendingOnOpen)
            } catch { }

            $detailsBody = ""
            $detailsModel = $null
            $summaryLines = @()
            $eventItems = @()
            $hasStoredActivity = $false
            try { if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "DetailsModel")) { $detailsModel = $detailsRenderModel.DetailsModel } } catch { $detailsModel = $null }
            try { if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "DetailsText")) { $detailsBody = [string]$detailsRenderModel.DetailsText } } catch { $detailsBody = "" }
            try { if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "SummaryLines")) { $summaryLines = @($detailsRenderModel.SummaryLines) } } catch { $summaryLines = @() }
            try { if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "Events")) { $eventItems = @($detailsRenderModel.Events) } } catch { $eventItems = @() }
            try { if ($detailsRenderModel -and ($detailsRenderModel.PSObject.Properties.Name -contains "HasStoredActivity")) { $hasStoredActivity = [bool]$detailsRenderModel.HasStoredActivity } } catch { $hasStoredActivity = $false }
            if ((@($eventItems).Count -eq 0) -and ($detailsTicket)) {
                try {
                    $hydratedActivityCount = 0
                    foreach ($activityProp in @("Notes", "Replies", "PendingReplies")) {
                        try {
                            if ($detailsTicket.PSObject.Properties.Name -contains $activityProp) {
                                $hydratedActivityCount += @($detailsTicket.$activityProp | Where-Object { $_ }).Count
                            }
                        } catch { }
                    }
                    if ($hydratedActivityCount -gt 0) {
                        $directDetailsModel = Get-QOTicketDetailsBodyText -Ticket $detailsTicket -AsModel -PreferCurrentTicket -PreferCachedPendingReplies
                        if ($directDetailsModel) {
                            try { if ($directDetailsModel.PSObject.Properties.Name -contains "DetailsText") { $detailsBody = [string]$directDetailsModel.DetailsText } } catch { }
                            try { if ($directDetailsModel.PSObject.Properties.Name -contains "SummaryLines") { $summaryLines = @($directDetailsModel.SummaryLines) } } catch { }
                            try { if ($directDetailsModel.PSObject.Properties.Name -contains "Events") { $eventItems = @($directDetailsModel.Events) } } catch { }
                            try { Write-QOTicketsUILog ("Tickets: Initial timeline rebuilt directly from hydrated ticket. TicketId='{0}' ActivityCount={1} EventCount={2}." -f ([string]($script:TicketsActiveTicketId + "")).Trim(), $hydratedActivityCount, @($eventItems).Count) } catch { }
                        }
                    }
                } catch {
                    try { Write-QOTicketsUILog ("Tickets: Initial direct hydrated timeline rebuild failed. TicketId='{0}' Error='{1}'." -f ([string]($script:TicketsActiveTicketId + "")).Trim(), $_.Exception.Message) "WARN" } catch { }
                }
            }
            try {
                $initialTypeCounts = @{}
                foreach ($eventItem in @($eventItems)) {
                    $kind = "Unknown"
                    try { $kind = ([string]($eventItem.Kind + "")).Trim() } catch { $kind = "Unknown" }
                    if ([string]::IsNullOrWhiteSpace($kind)) { $kind = "Unknown" }
                    if (-not $initialTypeCounts.ContainsKey($kind)) { $initialTypeCounts[$kind] = 0 }
                    $initialTypeCounts[$kind] = [int]$initialTypeCounts[$kind] + 1
                }
                $initialTypeSummary = (@($initialTypeCounts.Keys) | Sort-Object | ForEach-Object { "{0}={1}" -f $_, $initialTypeCounts[$_] }) -join ","
                if ([string]::IsNullOrWhiteSpace($initialTypeSummary)) { $initialTypeSummary = "none" }
                Write-QOTicketsUILog ("Tickets: Timeline final item count by type. TicketId='{0}' Count={1} Types='{2}'." -f ([string]($script:TicketsActiveTicketId + "")).Trim(), @($eventItems).Count, $initialTypeSummary)
            } catch { }
            if ([string]::IsNullOrWhiteSpace($detailsBody) -and (@($eventItems).Count -eq 0)) {
                try {
                    $displayBodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $detailsTicket
                    $displayBodyText = ""
                    if ($displayBodyInfo) {
                        $displayBodyText = ([string]($displayBodyInfo.Text + "")).Trim()
                    }
                    if (-not [string]::IsNullOrWhiteSpace($displayBodyText)) {
                        $detailsBody = $displayBodyText
                        $fromLine = [string](Get-QOTicketPropertyTextValue -Ticket $detailsTicket -PropertyNames @("EmailFrom", "SenderName", "SenderEmail", "From", "Sender"))
                        if ([string]::IsNullOrWhiteSpace($fromLine)) { $fromLine = "Email sender unavailable" }
                        $eventItems = @(
                            [pscustomobject]@{
                                When      = [datetime]::MinValue
                                SortOrder = 10
                                Kind      = "Email"
                                Title     = ("Main email from " + $fromLine)
                                Body      = $detailsBody
                            }
                        )
                    }
                } catch { }
            }
            if ([string]::IsNullOrWhiteSpace($detailsBody) -and (@($eventItems).Count -eq 0) -and $hasStoredActivity) {
                $detailsBody = "Ticket activity is available but could not be rendered."
            }
            if ([string]::IsNullOrWhiteSpace($detailsBody) -and (@($eventItems).Count -eq 0)) { $detailsBody = "This email did not include readable body content." }
            try {
                $typeCounts = @{}
                foreach ($eventItem in @($eventItems)) {
                    $kind = "Unknown"
                    try { $kind = ([string]($eventItem.Kind + "")).Trim() } catch { $kind = "Unknown" }
                    if ([string]::IsNullOrWhiteSpace($kind)) { $kind = "Unknown" }
                    if (-not $typeCounts.ContainsKey($kind)) { $typeCounts[$kind] = 0 }
                    $typeCounts[$kind] = [int]$typeCounts[$kind] + 1
                }
                $typeSummary = (@($typeCounts.Keys) | Sort-Object | ForEach-Object { "{0}={1}" -f $_, $typeCounts[$_] }) -join ","
                if ([string]::IsNullOrWhiteSpace($typeSummary)) { $typeSummary = "none" }
                Write-QOTicketsUILog ("Tickets: Timeline items rebuilt. TicketId='{0}' Count={1} Types='{2}'." -f (Get-QOTicketIdValue -Ticket $detailsTicket), @($eventItems).Count, $typeSummary)
            } catch { }
            try {
                if ($ticketBodyText) {
                    $timelineRenderStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    try { Set-QOTicketSummaryHeader -SummaryControl $ticketSummaryHeaderText -SummaryLines $summaryLines } catch { }
                    try { Set-QOTicketContactHeader -Ticket $detailsTicket } catch { }
                    if ($setTicketDetailsBodyContentCmd) {
                        & $setTicketDetailsBodyContentCmd -BodyControl $ticketBodyText -SummaryLines $summaryLines -Events $eventItems -FallbackText $detailsBody
                    } else {
                        Set-QOTicketDetailsBodyContent -BodyControl $ticketBodyText -SummaryLines $summaryLines -Events $eventItems -FallbackText $detailsBody
                    }
                    try { Write-QOTicketsUILog ("Tickets: Timeline render duration {0} ms." -f [int]$timelineRenderStopwatch.Elapsed.TotalMilliseconds) } catch { }
                }
            } catch {
                try { Write-QOTicketsUILog ("Tickets: Details body render failed: " + $_.Exception.Message) "WARN" } catch { }
                try { Set-QOTicketSummaryHeader -SummaryControl $ticketSummaryHeaderText -SummaryLines @() } catch { }
                try { Set-QOTicketContactHeader -Ticket $detailsTicket } catch { }
                try {
                    if ($ticketBodyText -and ($ticketBodyText -is [System.Windows.Controls.Panel])) {
                        $ticketBodyText.Children.Clear()
                        $fallbackText = New-Object System.Windows.Controls.TextBlock
                        $fallbackText.Text = $detailsBody
                        $fallbackText.TextWrapping = [System.Windows.TextWrapping]::Wrap
                        $fallbackText.Foreground = [System.Windows.Media.Brushes]::White
                        $ticketBodyText.Children.Add($fallbackText) | Out-Null
                    }
                } catch { }
            }

            $subjectValue = ""
            try {
                if ($detailsTicket.PSObject.Properties.Name -contains "Subject") {
                    $subjectValue = [string]$detailsTicket.Subject
                } elseif ($detailsTicket.PSObject.Properties.Name -contains "Title") {
                    $subjectValue = [string]$detailsTicket.Title
                }
            } catch { $subjectValue = "" }
            if ((& $ticketHasReplyReference $detailsTicket) -and
                -not [string]::IsNullOrWhiteSpace($subjectValue) -and
                $subjectValue -notmatch '^(RE|FW|FWD):') {
                $subjectValue = "RE: " + $subjectValue
            }
            try { if ($ticketReplySubject) { $ticketReplySubject.Text = $subjectValue } } catch { }
            try {
                if ($ticketsHeaderTitleText) {
                    $headerSubject = ([string]($subjectValue + "")).Trim()
                    if ([string]::IsNullOrWhiteSpace($headerSubject)) { $headerSubject = "No subject" }
                    if ($headerSubject.Length -gt 90) { $headerSubject = $headerSubject.Substring(0, 90) + "..." }
                    $ticketsHeaderTitleText.Text = ("Tickets - " + $headerSubject)
                }
            } catch { }

            try { if ($btnComposeInternalNote) { $btnComposeInternalNote.IsEnabled = $true } } catch { }
            try { if ($btnComposeReplyCustomer) { $btnComposeReplyCustomer.IsEnabled = $true } } catch { }

            $canReply = $false
            try { $canReply = [bool](& $canTicketReply $detailsTicket) } catch { $canReply = $false }

            $targetMode = ""
            $composeModeBeforeOpenRefresh = ""
            try { $composeModeBeforeOpenRefresh = ([string]($script:TicketsComposeMode + "")).Trim() } catch { $composeModeBeforeOpenRefresh = "" }
            try {
                $modeTicketId = Get-QOTicketIdValue -Ticket $detailsTicket
                if (($script:TicketsComposeModeByTicketId -is [hashtable]) -and
                    (-not [string]::IsNullOrWhiteSpace($modeTicketId)) -and
                    $script:TicketsComposeModeByTicketId.ContainsKey($modeTicketId)) {
                    $targetMode = ([string]($script:TicketsComposeModeByTicketId[$modeTicketId] + "")).Trim()
                }
            } catch { $targetMode = "" }
            if ([string]::IsNullOrWhiteSpace($targetMode)) { $targetMode = [string]$script:TicketsComposeMode }
            if ([string]::IsNullOrWhiteSpace($targetMode)) { $targetMode = "Reply" }
            if (([string]::Equals($targetMode, "Reply", [System.StringComparison]::OrdinalIgnoreCase)) -and (-not $canReply)) {
                $targetMode = "Note"
            }
            try { Write-QOTicketsUILog ("Tickets: Compose mode before refresh. TicketId='{0}' Mode='{1}' Target='{2}'." -f (Get-QOTicketIdValue -Ticket $detailsTicket), $composeModeBeforeOpenRefresh, $targetMode) } catch { }
            try { & $setComposeMode -Mode $targetMode -PreserveText -SkipFocus } catch { }
            try { Write-QOTicketsUILog ("Tickets: Compose mode after refresh. TicketId='{0}' Mode='{1}'." -f (Get-QOTicketIdValue -Ticket $detailsTicket), ([string]($script:TicketsComposeMode + "")).Trim()) } catch { }

            try {
                if ($btnSendReply) {
                    if ([string]::Equals([string]$script:TicketsComposeMode, "Reply", [System.StringComparison]::OrdinalIgnoreCase)) {
                        $btnSendReply.IsEnabled = $canReply
                    } else {
                        $btnSendReply.IsEnabled = $true
                    }
                }
            } catch { }
            try { & $updateReplyComposeFeedback $detailsTicket } catch { }

            try {
                if ($setTicketDetailsVisibilityCmd) {
                    & $setTicketDetailsVisibilityCmd -DetailsPanel $detailsPanel -Chevron $detailsChevron -TicketsGrid $grid -IsOpen:$true
                } else {
                    Set-QOTicketDetailsVisibility -DetailsPanel $detailsPanel -Chevron $detailsChevron -TicketsGrid $grid -IsOpen:$true
                }
            } catch { }
            try { Write-QOTicketsUILog ("Tickets: Ticket open time. TicketId='{0}' DurationMs={1}" -f ([string]($script:TicketsActiveTicketId + "")).Trim(), [int]$detailsOpenStopwatch.Elapsed.TotalMilliseconds) } catch { }
            try { Write-QOTicketsUILog ("Tickets: Timeline refresh end. TicketId='{0}' RenderPath='InitialOpen'." -f ([string]($script:TicketsActiveTicketId + "")).Trim()) } catch { }
        } catch {
            try { Write-QOTicketsUILog ("Tickets: invokeDetailsUpdate failed: " + $_.Exception.Message) "WARN" } catch { }
            try { Write-QOTicketsUILog ("Tickets: invokeDetailsUpdate stack: " + $_.ScriptStackTrace) "WARN" } catch { }
        }
    }.GetNewClosure()

    $queueLightweightDetailsRefresh = {
        param([AllowNull()]$Ticket)

        try {
            $refreshTicketId = ""
            try { $refreshTicketId = Get-QOTicketIdValue -Ticket $Ticket } catch { $refreshTicketId = "" }
            if (-not (Test-QOTicketDetailsViewActive -TicketId $refreshTicketId)) {
                try { Write-QOTicketsUILog ("Tickets: Lightweight details refresh ignored because ticket/view is no longer active. TicketId='{0}' ActiveTicketId='{1}'." -f $refreshTicketId, ([string]($script:TicketsActiveTicketId + "")).Trim()) } catch { }
                return
            }

            $script:TicketsQueuedDetailsRefreshTicket = $Ticket
            $script:TicketsQueuedDetailsRefreshTicketId = $refreshTicketId
            try { $script:TicketsQueuedDetailsRefreshGeneration = [int]$script:TicketsDetailsViewGeneration } catch { $script:TicketsQueuedDetailsRefreshGeneration = 0 }
            if ($script:TicketsQueuedDetailsRefreshTimer -and $script:TicketsQueuedDetailsRefreshTimer.IsEnabled) {
                try { $script:TicketsQueuedDetailsRefreshTimer.Stop() } catch { }
            }

            if (-not $script:TicketsQueuedDetailsRefreshTimer) {
                $script:TicketsQueuedDetailsRefreshTimer = [System.Windows.Threading.DispatcherTimer]::new()
                $script:TicketsQueuedDetailsRefreshTimer.Interval = [TimeSpan]::FromMilliseconds(90)
            }

            if (-not $script:TicketsQueuedDetailsRefreshTickHandler) {
                $script:TicketsQueuedDetailsRefreshTickHandler = {
                    try {
                        if ($script:TicketsQueuedDetailsRefreshTimer) {
                            try { $script:TicketsQueuedDetailsRefreshTimer.Stop() } catch { }
                        }

                        $refreshTicket = $null
                        try { $refreshTicket = $script:TicketsQueuedDetailsRefreshTicket } catch { $refreshTicket = $null }
                        $refreshTicketId = ""
                        $refreshGeneration = 0
                        try { $refreshTicketId = ([string]($script:TicketsQueuedDetailsRefreshTicketId + "")).Trim() } catch { $refreshTicketId = "" }
                        try { $refreshGeneration = [int]$script:TicketsQueuedDetailsRefreshGeneration } catch { $refreshGeneration = 0 }
                        $script:TicketsQueuedDetailsRefreshTicket = $null
                        $script:TicketsQueuedDetailsRefreshTicketId = ""
                        $script:TicketsQueuedDetailsRefreshGeneration = 0
                        try { Write-QOTicketsUILog ("Tickets: Background queue callback received. TicketId='{0}' Generation={1}." -f $refreshTicketId, $refreshGeneration) } catch { }
                        if (-not $refreshTicket) { return }
                        if (-not (Test-QOTicketDetailsViewActive -TicketId $refreshTicketId -Generation $refreshGeneration)) {
                            try { Write-QOTicketsUILog ("Tickets: Background queue callback ignored because ticket/view is no longer active. TicketId='{0}' ActiveTicketId='{1}' Generation={2}/{3}." -f $refreshTicketId, ([string]($script:TicketsActiveTicketId + "")).Trim(), $refreshGeneration, $script:TicketsDetailsViewGeneration) } catch { }
                            return
                        }

                        Update-QOTicketDetailsView -Ticket $refreshTicket -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplySubject $ticketReplySubject -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron -PreferCurrentTicket -PreferCachedPendingReplies -RequireActiveDetailView
                    } catch {
                        try { Write-QOTicketsUILog ("Tickets: Lightweight queued details refresh failed: " + $_.Exception.Message) "WARN" } catch { }
                        try { Write-QOTicketsUILog ("Tickets: Lightweight queued details refresh stack: " + $_.ScriptStackTrace) "WARN" } catch { }
                    }
                }.GetNewClosure()
                $script:TicketsQueuedDetailsRefreshTimer.Add_Tick($script:TicketsQueuedDetailsRefreshTickHandler)
            }

            $script:TicketsQueuedDetailsRefreshTimer.Start()
        } catch {
            try { Write-QOTicketsUILog ("Tickets: Could not schedule lightweight details refresh: " + $_.Exception.Message) "WARN" } catch { }
        }
    }.GetNewClosure()

    $scrollTicketDetailsToEnd = {
        try {
            $findParentScrollViewer = {
                param([AllowNull()][System.Windows.DependencyObject]$Element)
                $current = $Element
                while ($current) {
                    if ($current -is [System.Windows.Controls.ScrollViewer]) { return $current }
                    try { $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current) } catch { $current = $null }
                }
                return $null
            }.GetNewClosure()

            $hostScroll = $null
            if ($getParentVisualCmd -and $ticketBodyText) {
                try { $hostScroll = & $getParentVisualCmd -Element $ticketBodyText -Type ([System.Windows.Controls.ScrollViewer]) } catch { $hostScroll = $null }
            }
            if (-not $hostScroll -and $ticketBodyText) {
                try { $hostScroll = & $findParentScrollViewer $ticketBodyText } catch { $hostScroll = $null }
            }
            if (-not $hostScroll -and $detailsPanel) {
                try { $hostScroll = & $getParentVisualCmd -Element $detailsPanel -Type ([System.Windows.Controls.ScrollViewer]) } catch { $hostScroll = $null }
            }
            if (-not $hostScroll -and $detailsPanel) {
                try { $hostScroll = & $findParentScrollViewer $detailsPanel } catch { $hostScroll = $null }
            }
            if ($hostScroll) {
                try { $hostScroll.UpdateLayout() } catch { }
                try { $hostScroll.ScrollToEnd() } catch { }
            }
        } catch { }
    }.GetNewClosure()

    $getTicketSelectionKeySafe = {
        param([AllowNull()]$Ticket)
        if (-not $Ticket) { return "" }
        if ($getTicketSelectionKeyCmd) {
            try { return [string](& $getTicketSelectionKeyCmd -Ticket $Ticket) } catch { }
        }
        try { return [string](Get-QOTicketSelectionKey -Ticket $Ticket) } catch { }
        return ""
    }.GetNewClosure()

    $getTicketLogLabelSafe = {
        param([AllowNull()]$Ticket)
        if (-not $Ticket) { return "Ticket=(null)" }
        if ($getTicketLogLabelCmd) {
            try { return [string](& $getTicketLogLabelCmd -Ticket $Ticket) } catch { }
        }
        try { return [string](Get-QOTicketLogLabel -Ticket $Ticket) } catch { }
        return "Ticket=(unknown)"
    }.GetNewClosure()

    $invokeGridRefresh = {
        try {
            if ($invokeGridRefreshCmd) {
                & $invokeGridRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
            } else {
                Refresh-QOTicketsGrid -Grid $grid -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
            }
        } catch {
            Write-QOTicketsUILog ("Tickets: Grid refresh helper failed: " + $_.Exception.Message) "WARN"
        }
    }.GetNewClosure()

    $refreshPendingReplyUi = {
        param(
            [AllowNull()][string]$TicketIdValue,
            [AllowNull()][string]$Reason
        )

        $targetTicketId = ([string]($TicketIdValue + "")).Trim()
        $reasonText = ([string]($Reason + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($reasonText)) { $reasonText = "pending-reply-update" }
        try { Set-QOTicketsReplyUiRefreshWindow -Seconds 90 } catch { }

        $ticketForRefresh = $null
        try {
            if (-not [string]::IsNullOrWhiteSpace($targetTicketId)) {
                $ticketForRefresh = & $resolveVisibleTicketById -TicketIdValue $targetTicketId -AllowSelectedFallback
            } else {
                $ticketForRefresh = $grid.SelectedItem
            }
        } catch { $ticketForRefresh = $null }

        try {
            if ($ticketForRefresh) {
                $null = Sync-QOTTicketLivePendingReplies -Ticket $ticketForRefresh -TicketId $targetTicketId -PreferCached
                Update-QOTicketDisplayFields -Tickets @($ticketForRefresh)
                if ($grid) { $grid.Items.Refresh() }
            } else {
                Refresh-QOTicketsAfterLocalMutation -Grid $grid -PreferredDetailsTicket $ticketForRefresh -PreferCurrentTicket -PreferCachedPendingReplies
            }
        } catch {
            try { Refresh-QOTicketsAfterLocalMutation -Grid $grid -PreferredDetailsTicket $ticketForRefresh -PreferCurrentTicket -PreferCachedPendingReplies } catch { }
        }

        if ($ticketForRefresh) {
            if (Test-QOTicketDetailsViewActive -TicketId $targetTicketId) {
                try { & $queueLightweightDetailsRefresh $ticketForRefresh } catch { }
                try { & $updateReplyComposeFeedback $ticketForRefresh } catch { }
            } else {
                try { Write-QOTicketsUILog ("Tickets: Background queue callback ignored because ticket/view is no longer active. TicketId='{0}' ActiveTicketId='{1}' Reason='{2}'." -f $targetTicketId, ([string]($script:TicketsActiveTicketId + "")).Trim(), $reasonText) } catch { }
            }
        }

        try { & $replySendWriteLogCmd ("Tickets: Queue UI refreshed. Reason='{0}' TicketId='{1}'." -f $reasonText, $targetTicketId) } catch { }
    }.GetNewClosure()

    $invokeTicketsFilterLocal = Resolve-QOTInvokable -Candidate (Get-Command Invoke-QOTicketsFilterSafely -ErrorAction SilentlyContinue) -CommandName "Invoke-QOTicketsFilterSafely"
    if (-not $invokeTicketsFilterLocal) {
        # Prefer command-name fallback over function scriptblocks so module-scoped helpers remain resolvable.
        $invokeTicketsFilterLocal = "Invoke-QOTicketsFilterSafely"
    }

    $setFilterRuntimeStateLocal = Resolve-QOTInvokable -Candidate (Get-Command Set-QOTicketsFilterRuntimeState -ErrorAction SilentlyContinue) -CommandName "Set-QOTicketsFilterRuntimeState"
    if (-not $setFilterRuntimeStateLocal) {
        $setFilterRuntimeStateLocal = "Set-QOTicketsFilterRuntimeState"
    }
    $normalizeAssigneeFilterCmd = Resolve-QOTInvokable -Candidate (Get-Command Normalize-QOTicketsAssigneeFilterValue -ErrorAction SilentlyContinue) -CommandName "Normalize-QOTicketsAssigneeFilterValue"
    if (-not $normalizeAssigneeFilterCmd) {
        try { $normalizeAssigneeFilterCmd = ${function:Normalize-QOTicketsAssigneeFilterValue} } catch { $normalizeAssigneeFilterCmd = $null }
    }
    if (-not $normalizeAssigneeFilterCmd) {
        # Keep Tickets UI startup resilient; fallback to command-name resolution at call sites.
        $normalizeAssigneeFilterCmd = "Normalize-QOTicketsAssigneeFilterValue"
    }

    # Remove previous handlers safely (now that handlers are typed delegates, Remove_ should match)

    try { if ($script:TicketsNewHandler)     { $btnNew.Remove_Click($script:TicketsNewHandler) } } catch { }
    try { if ($script:TicketsDeleteHandler)  { $btnDelete.Remove_Click($script:TicketsDeleteHandler) } } catch { }

    try { if ($script:TicketsToggleDetailsHandler) { $btnToggleDetails.Remove_Click($script:TicketsToggleDetailsHandler) } } catch { }
    try {
        if ($script:TicketsToggleDetailsPreviewHandler) {
            try { $btnToggleDetails.RemoveHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent, $script:TicketsToggleDetailsPreviewHandler) } catch { }
        }
    } catch { }
    $script:TicketsToggleDetailsPreviewHandler = $null
    try {
        if ($script:TicketsFilterCheckboxHandler) {
            foreach ($checkbox in @(
                    $script:TicketsFilterSortPriorityMenuItem,
                    $script:TicketsFilterSortNewestMenuItem,
                    $script:TicketsFilterSortOldestMenuItem)) {
                if (-not $checkbox) { continue }
                try { $checkbox.Remove_Click($script:TicketsFilterCheckboxHandler) } catch { }
            }
        }
    } catch { }
    try {
        if ($script:TicketsFilterStatusCheckedHandler) {
            foreach ($checkbox in @(
                    $script:TicketsFilterOpenCheckbox,
                    $script:TicketsFilterClosedCheckbox,
                    $script:TicketsFilterDeletedCheckbox)) {
                if (-not $checkbox) { continue }
                try { $checkbox.Remove_Checked($script:TicketsFilterStatusCheckedHandler) } catch { }
            }
        }
    } catch { }
    try {
        if ($script:TicketsFilterStatusUncheckedHandler) {
            foreach ($checkbox in @(
                    $script:TicketsFilterOpenCheckbox,
                    $script:TicketsFilterClosedCheckbox,
                    $script:TicketsFilterDeletedCheckbox)) {
                if (-not $checkbox) { continue }
                try { $checkbox.Remove_Unchecked($script:TicketsFilterStatusUncheckedHandler) } catch { }
            }
        }
    } catch { }
    try {
        if ($script:TicketsFilterStatusClickHandler) {
            foreach ($checkbox in @(
                    $script:TicketsFilterOpenCheckbox,
                    $script:TicketsFilterClosedCheckbox,
                    $script:TicketsFilterDeletedCheckbox)) {
                if (-not $checkbox) { continue }
                try { $checkbox.Remove_Click($script:TicketsFilterStatusClickHandler) } catch { }
            }
        }
    } catch { }
    try { if ($script:TicketsFilterButtonHandler) { $btnFilterMenu.Remove_Click($script:TicketsFilterButtonHandler) } } catch { }
    try { if ($script:TicketsFilterMenuClosedHandler -and $script:TicketsFilterMenu) { $script:TicketsFilterMenu.Remove_Closed($script:TicketsFilterMenuClosedHandler) } } catch { }

    # Clear dynamic menu items and their handlers to prevent memory leak
    try {
        if ($script:TicketsSetStatusMenuItem -and $script:TicketsSetStatusMenuItem.Items.Count -gt 0) {
            foreach ($menuItem in @($script:TicketsSetStatusMenuItem.Items)) {
                if ($menuItem -and $script:TicketsStatusMenuItemHandler) {
                    try { $menuItem.Remove_Click($script:TicketsStatusMenuItemHandler) } catch { }
                }
            }
            $script:TicketsSetStatusMenuItem.Items.Clear()
        }
    } catch { }
    try {
        if ($script:TicketsSetPriorityMenuItem -and $script:TicketsSetPriorityMenuItem.Items.Count -gt 0) {
            foreach ($menuItem in @($script:TicketsSetPriorityMenuItem.Items)) {
                if ($menuItem -and $script:TicketsPriorityMenuItemHandler) {
                    try { $menuItem.Remove_Click($script:TicketsPriorityMenuItemHandler) } catch { }
                }
            }
            $script:TicketsSetPriorityMenuItem.Items.Clear()
        }
    } catch { }
    try {
        if ($script:TicketsSetAssignedToMenuItem -and $script:TicketsSetAssignedToMenuItem.Items.Count -gt 0) {
            foreach ($menuItem in @($script:TicketsSetAssignedToMenuItem.Items)) {
                if ($menuItem -and ($script:TicketsAssignMenuItemHandler -or $script:TicketsAssignCustomMenuItemHandler)) {
                    try { $menuItem.Remove_Click($script:TicketsAssignMenuItemHandler) } catch { }
                    try { $menuItem.Remove_Click($script:TicketsAssignCustomMenuItemHandler) } catch { }
                }
            }
            $script:TicketsSetAssignedToMenuItem.Items.Clear()
        }
    } catch { }
    try {
        if ($script:TicketsFilterAssigneeAllMenuItem) {
            if ($script:TicketsFilterCheckboxHandler) {
                try { $script:TicketsFilterAssigneeAllMenuItem.Remove_Click($script:TicketsFilterCheckboxHandler) } catch { }
            }
            $script:TicketsFilterAssigneeAllMenuItem = $null
        }
        if ($script:TicketsFilterAssigneeUnassignedMenuItem) {
            if ($script:TicketsFilterCheckboxHandler) {
                try { $script:TicketsFilterAssigneeUnassignedMenuItem.Remove_Click($script:TicketsFilterCheckboxHandler) } catch { }
            }
            $script:TicketsFilterAssigneeUnassignedMenuItem = $null
        }
        foreach ($item in @($script:TicketsFilterAssigneeDynamicMenuItems)) {
            if ($item -and $script:TicketsFilterCheckboxHandler) {
                try { $item.Remove_Click($script:TicketsFilterCheckboxHandler) } catch { }
            }
        }
        $script:TicketsFilterAssigneeDynamicMenuItems = @()
    } catch { }

    try {
        if ($script:TicketsSyncStatusClickHandler) {
            try { $syncStatusText.RemoveHandler([System.Windows.UIElement]::MouseLeftButtonUpEvent, $script:TicketsSyncStatusClickHandler) } catch { }
            try { $syncStatusText.Remove_MouseLeftButtonUp($script:TicketsSyncStatusClickHandler) } catch { }
        }
    } catch { }
    $script:TicketsSyncStatusClickHandler = $null
    try {
        if ($script:TicketsWindowClosingHandler) {
            $Window.Remove_Closing($script:TicketsWindowClosingHandler)
        }
    } catch { }

    try {
        if ($script:TicketsSelectionChangedHandler) {
            $grid.RemoveHandler([System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent, $script:TicketsSelectionChangedHandler)
            try { $grid.Remove_SelectionChanged($script:TicketsSelectionChangedHandler) } catch { }
        }
    } catch { }
    try {
        if ($script:TicketsRowPreviewDoubleClickHandler) {
            try { $grid.RemoveHandler([System.Windows.Controls.Control]::PreviewMouseDoubleClickEvent, $script:TicketsRowPreviewDoubleClickHandler) } catch { }
            try { $grid.RemoveHandler([System.Windows.Controls.Control]::MouseDoubleClickEvent, $script:TicketsRowPreviewDoubleClickHandler) } catch { }
            try { $grid.Remove_PreviewMouseDoubleClick($script:TicketsRowPreviewDoubleClickHandler) } catch { }
        }
    } catch { }
    try {
        if ($script:TicketsRowPreviewMouseDownHandler) {
            try { $grid.RemoveHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, $script:TicketsRowPreviewMouseDownHandler) } catch { }
        }
    } catch { }
    try {
        if ($script:TicketsRowPreviewMouseUpHandler) {
            try { $grid.RemoveHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent, $script:TicketsRowPreviewMouseUpHandler) } catch { }
        }
    } catch { }
    try {
        if ($script:TicketsRowMouseUpHandler) {
            try { $grid.RemoveHandler([System.Windows.UIElement]::MouseLeftButtonUpEvent, $script:TicketsRowMouseUpHandler) } catch { }
        }
    } catch { }
    try {
        if ($script:TicketsGridKeyDownHandler) {
            try { $grid.RemoveHandler([System.Windows.UIElement]::PreviewKeyDownEvent, $script:TicketsGridKeyDownHandler) } catch { }
            try { $grid.Remove_KeyDown($script:TicketsGridKeyDownHandler) } catch { }
        }
    } catch { }
    try {
        if ($script:TicketsRowDoubleClickHandler) {
            try { $grid.RemoveHandler([System.Windows.Controls.Control]::MouseDoubleClickEvent, $script:TicketsRowDoubleClickHandler) } catch { }
            try { $grid.RemoveHandler([System.Windows.Controls.Control]::PreviewMouseDoubleClickEvent, $script:TicketsRowDoubleClickHandler) } catch { }
            try { $grid.Remove_MouseDoubleClick($script:TicketsRowDoubleClickHandler) } catch { }
        }
    } catch { }

    try {
        if ($script:TicketsRowEditHandler) {
            $grid.Remove_RowEditEnding($script:TicketsRowEditHandler)
        }
    } catch { }

    try { if ($script:TicketsSendReplyHandler) { $btnSendReply.Remove_Click($script:TicketsSendReplyHandler) } } catch { }
    try { if ($script:TicketsRetryReplyHandler) { $btnRetryFailedReply.Remove_Click($script:TicketsRetryReplyHandler) } } catch { }
    try { if ($script:TicketsComposeModeInternalHandler) { $btnComposeInternalNote.Remove_Click($script:TicketsComposeModeInternalHandler) } } catch { }
    try { if ($script:TicketsComposeModeReplyHandler) { $btnComposeReplyCustomer.Remove_Click($script:TicketsComposeModeReplyHandler) } } catch { }

    try {
        if ($script:TicketsContentRenderedHandler) {
            $Window.Remove_ContentRendered($script:TicketsContentRenderedHandler)
        }
    } catch { }

    try {
        if ($script:TicketsStatusContextMenuHandler) {
            $grid.RemoveHandler([System.Windows.UIElement]::PreviewMouseRightButtonUpEvent, $script:TicketsStatusContextMenuHandler)
            $grid.RemoveHandler([System.Windows.UIElement]::PreviewMouseRightButtonDownEvent, $script:TicketsStatusContextMenuHandler)
        }
    } catch { }
    try {
        if ($script:TicketsSelectionSyncTimer) {
            if ($script:TicketsSelectionSyncTickHandler) {
                try { $script:TicketsSelectionSyncTimer.Remove_Tick($script:TicketsSelectionSyncTickHandler) } catch { }
            }
            try { $script:TicketsSelectionSyncTimer.Stop() } catch { }
            $script:TicketsSelectionSyncTimer = $null
            $script:TicketsSelectionSyncTickHandler = $null
        }
    } catch { }

    try {
        if ($script:TicketsSyncTimer) {
            if ($script:TicketsSyncWorkerTickHandler) {
                $script:TicketsSyncTimer.Remove_Tick($script:TicketsSyncWorkerTickHandler)
            }
            $script:TicketsSyncTimer.Stop()
            $script:TicketsSyncTimer = $null
        }
    } catch { }
    try {
        if ($script:TicketsSyncCompletionTimer) {
            try { $script:TicketsSyncCompletionTimer.Stop() } catch { }
            $script:TicketsSyncCompletionTimer = $null
        }
    } catch { }
    Stop-QOTicketsSyncExecution -StopActiveOperation
    Clear-QOTicketsSyncExecutionState -RemoveRunnerFiles
    try {
        if ($script:TicketsReplyCompletionTimer) {
            if ($script:TicketsReplyCompletionTickHandler) {
                try { $script:TicketsReplyCompletionTimer.Remove_Tick($script:TicketsReplyCompletionTickHandler) } catch { }
            }
            try { $script:TicketsReplyCompletionTimer.Stop() } catch { }
            $script:TicketsReplyCompletionTimer = $null
        }
    } catch { }
    try {
        if ($script:TicketsReplyWatchdogTimer) {
            if ($script:TicketsReplyWatchdogTickHandler) {
                try { $script:TicketsReplyWatchdogTimer.Remove_Tick($script:TicketsReplyWatchdogTickHandler) } catch { }
            }
            try { $script:TicketsReplyWatchdogTimer.Stop() } catch { }
            $script:TicketsReplyWatchdogTimer = $null
        }
    } catch { }
    try {
        if ($script:TicketsReplyQueueKickTimer) {
            if ($script:TicketsReplyQueueKickTickHandler) {
                try { $script:TicketsReplyQueueKickTimer.Remove_Tick($script:TicketsReplyQueueKickTickHandler) } catch { }
            }
            try { $script:TicketsReplyQueueKickTimer.Stop() } catch { }
            $script:TicketsReplyQueueKickTimer = $null
        }
    } catch { }
    try {
        if ($script:TicketsReplyPowerShell) {
            try { $script:TicketsReplyPowerShell.Stop() } catch { }
            try { $script:TicketsReplyPowerShell.Dispose() } catch { }
            $script:TicketsReplyPowerShell = $null
        }
    } catch { }
    try {
        if ($script:TicketsReplyRunspace) {
            try { $script:TicketsReplyRunspace.Dispose() } catch { }
            $script:TicketsReplyRunspace = $null
        }
    } catch { }
    $script:TicketsReplyAsyncResult = $null
    $script:TicketsReplyCompletionTickHandler = $null
    $script:TicketsReplyWatchdogTickHandler = $null
    $script:TicketsReplyQueueKickTickHandler = $null
    try { Remove-QOTLimitedScheduledProcessArtifacts -TaskName $script:TicketsReplyRunnerTaskName -CommandPath $script:TicketsReplyRunnerCommandPath } catch { }
    $script:TicketsReplyRunnerTaskName = ""
    $script:TicketsReplyRunnerCommandPath = ""
    $script:TicketsReplySendInProgress = $false
    $script:TicketsReplyStartUtc = [datetime]::MinValue
    try {
        if ($script:TicketsReplyQueuedSends -is [System.Collections.Queue]) {
            $script:TicketsReplyQueuedSends.Clear()
        } else {
            $script:TicketsReplyQueuedSends = New-Object System.Collections.Queue
        }
    } catch {
        $script:TicketsReplyQueuedSends = New-Object System.Collections.Queue
    }
    $script:TicketsReplyQueueDrainHandler = $null
    $script:TicketsReplyQueueKickTimer = $null
    try { if ($stopIncrementalMergeLocalCmd) { & $stopIncrementalMergeLocalCmd } } catch { }
    $script:TicketsSyncWorkerStarted = $false
    $script:TicketsEmailSyncInProgress = $false
    $script:TicketsSyncActiveRunId = 0
    $script:TicketsSyncActiveTimeoutSeconds = 0
    $script:TicketsSyncLastStartUtc = [datetime]::MinValue
    try {
        if ($script:TicketsOpenPulseTimer) {
            try { $script:TicketsOpenPulseTimer.Stop() } catch { }
            $script:TicketsOpenPulseTimer = $null
        }
    } catch { }

    try {
        if ($script:TicketsFileRefreshTimer) {
            if ($script:TicketsFileRefreshTickHandler) {
                $script:TicketsFileRefreshTimer.Remove_Tick($script:TicketsFileRefreshTickHandler)
            }
            $script:TicketsFileRefreshTimer.Stop()
            $script:TicketsFileRefreshTimer = $null
        }
    } catch { }
    $script:TicketsFileRefreshTickHandler = $null
    $script:TicketsStorePath = ""
    $script:TicketsStoreLastWriteUtc = [datetime]::MinValue

    # Dispose any FileSystemWatcher and event subscriptions left behind by a
    # previous module load. Centralised in Stop-QOTicketsFileWatcher so the
    # same teardown is used here and from the window Closing handler.
    try { $null = Stop-QOTicketsFileWatcher } catch {
        try { Write-QOTicketsUILog ("Tickets: Stop-QOTicketsFileWatcher on init failed: " + $_.Exception.Message) "WARN" } catch { }
    }

    try { & $invokeDetailsUpdate $null } catch { }

    $grid.SelectionMode = [System.Windows.Controls.DataGridSelectionMode]::Extended
    try { $grid.EnableRowVirtualization = $true } catch { }
    try { $grid.EnableColumnVirtualization = $true } catch { }
    try { [System.Windows.Controls.VirtualizingPanel]::SetIsVirtualizing($grid, $true) } catch { }
    try { [System.Windows.Controls.VirtualizingPanel]::SetVirtualizationMode($grid, [System.Windows.Controls.VirtualizationMode]::Recycling) } catch { }
    try { [System.Windows.Controls.ScrollViewer]::SetCanContentScroll($grid, $true) } catch { }

    try {
        $syncStatusText.Cursor = [System.Windows.Input.Cursors]::Hand
    } catch { }
    $script:TicketsSyncStatusClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $eventArgs)
        try {
            if ($eventArgs -and $eventArgs.ChangedButton -ne [System.Windows.Input.MouseButton]::Left) {
                return
            }
        } catch { }
        try { if ($eventArgs) { $eventArgs.Handled = $true } } catch { }

        Invoke-QOTicketsManualSyncRequest -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusText $syncStatusText -InvokeSyncCmd $invokeEmailSyncRefreshCmd -MaxPerMailbox $script:TicketsBackgroundBatchSize | Out-Null
    }.GetNewClosure()
    $syncStatusText.AddHandler([System.Windows.UIElement]::MouseLeftButtonUpEvent, $script:TicketsSyncStatusClickHandler, $true)
    try { $grid.IsReadOnly = $true } catch { }

    if ($grid.ContextMenu) {
        $grid.ContextMenu = $null
    }
    $script:TicketsFilterMenu = New-Object System.Windows.Controls.ContextMenu
    $script:TicketsFilterMenu.StaysOpen = $true
    if ($applyTicketsContextMenuThemeCmd) { & $applyTicketsContextMenuThemeCmd -ContextMenu $script:TicketsFilterMenu -Window $Window | Out-Null }
    $btnFilterMenu.ContextMenu = $script:TicketsFilterMenu

    $filterState = Get-QOTicketsFilterState
    $script:ShowOpen = [bool]$filterState.ShowOpen
    $script:ShowClosed = [bool]$filterState.ShowClosed
    $script:ShowDeleted = [bool]$filterState.ShowDeleted
    $script:TicketsAssigneeFilter = "All"
    try { $script:TicketsAssigneeFilter = Normalize-QOTicketsAssigneeFilterValue -Value ([string]$filterState.AssigneeFilter) } catch { $script:TicketsAssigneeFilter = "All" }
    $script:TicketsSortMode = "Priority"
    try { $script:TicketsSortMode = ([string]($filterState.SortMode + "")).Trim() } catch { $script:TicketsSortMode = "Priority" }
    if ([string]::IsNullOrWhiteSpace($script:TicketsSortMode)) {
        $legacyPrioritySort = $true
        try { $legacyPrioritySort = [bool]$filterState.SortPriorityHighToLow } catch { $legacyPrioritySort = $true }
        $script:TicketsSortMode = if ($legacyPrioritySort) { "Priority" } else { "Newest" }
    }
    switch ($script:TicketsSortMode.ToLowerInvariant()) {
        "priority" { $script:TicketsSortMode = "Priority" }
        "newest" { $script:TicketsSortMode = "Newest" }
        "oldest" { $script:TicketsSortMode = "Oldest" }
        default { $script:TicketsSortMode = "Priority" }
    }

    $script:TicketsFilterOpenCheckbox = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterOpenCheckbox.Header = "Open"
    $script:TicketsFilterOpenCheckbox.IsCheckable = $true
    $script:TicketsFilterOpenCheckbox.IsChecked = [bool]$script:ShowOpen
    $script:TicketsFilterOpenCheckbox.IsEnabled = $true
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsFilterOpenCheckbox -Window $Window | Out-Null }
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterOpenCheckbox) | Out-Null

    $script:TicketsFilterClosedCheckbox = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterClosedCheckbox.Header = "Closed"
    $script:TicketsFilterClosedCheckbox.IsCheckable = $true
    $script:TicketsFilterClosedCheckbox.IsChecked = [bool]$script:ShowClosed
    $script:TicketsFilterClosedCheckbox.IsEnabled = $true
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsFilterClosedCheckbox -Window $Window | Out-Null }
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterClosedCheckbox) | Out-Null

    $script:TicketsFilterDeletedCheckbox = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterDeletedCheckbox.Header = "Deleted"
    $script:TicketsFilterDeletedCheckbox.IsCheckable = $true
    $script:TicketsFilterDeletedCheckbox.IsChecked = [bool]$script:ShowDeleted
    $script:TicketsFilterDeletedCheckbox.IsEnabled = $true
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsFilterDeletedCheckbox -Window $Window | Out-Null }
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterDeletedCheckbox) | Out-Null

    $script:TicketsFilterMenu.Items.Add($(if ($newTicketsStyledSeparatorCmd) { & $newTicketsStyledSeparatorCmd -Window $Window } else { New-Object System.Windows.Controls.Separator })) | Out-Null
    $script:TicketsFilterAssigneeMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterAssigneeMenuItem.Header = "Assigned to"
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsFilterAssigneeMenuItem -Window $Window | Out-Null }
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterAssigneeMenuItem) | Out-Null
    $script:TicketsFilterAssigneeAllMenuItem = $null
    $script:TicketsFilterAssigneeUnassignedMenuItem = $null
    $script:TicketsFilterAssigneeDynamicMenuItems = @()

    $script:TicketsFilterMenu.Items.Add($(if ($newTicketsStyledSeparatorCmd) { & $newTicketsStyledSeparatorCmd -Window $Window } else { New-Object System.Windows.Controls.Separator })) | Out-Null
    $script:TicketsFilterSortPriorityMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterSortPriorityMenuItem.Header = "Sort: Priority (High -> Low)"
    $script:TicketsFilterSortPriorityMenuItem.Tag = "Priority"
    $script:TicketsFilterSortPriorityMenuItem.IsCheckable = $true
    $script:TicketsFilterSortPriorityMenuItem.IsChecked = ($script:TicketsSortMode -eq "Priority")
    $script:TicketsFilterSortPriorityMenuItem.IsEnabled = $true
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsFilterSortPriorityMenuItem -Window $Window | Out-Null }
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterSortPriorityMenuItem) | Out-Null

    $script:TicketsFilterSortNewestMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterSortNewestMenuItem.Header = "Sort: Newest first"
    $script:TicketsFilterSortNewestMenuItem.Tag = "Newest"
    $script:TicketsFilterSortNewestMenuItem.IsCheckable = $true
    $script:TicketsFilterSortNewestMenuItem.IsChecked = ($script:TicketsSortMode -eq "Newest")
    $script:TicketsFilterSortNewestMenuItem.IsEnabled = $true
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsFilterSortNewestMenuItem -Window $Window | Out-Null }
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterSortNewestMenuItem) | Out-Null

    $script:TicketsFilterSortOldestMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsFilterSortOldestMenuItem.Header = "Sort: Oldest first"
    $script:TicketsFilterSortOldestMenuItem.Tag = "Oldest"
    $script:TicketsFilterSortOldestMenuItem.IsCheckable = $true
    $script:TicketsFilterSortOldestMenuItem.IsChecked = ($script:TicketsSortMode -eq "Oldest")
    $script:TicketsFilterSortOldestMenuItem.IsEnabled = $true
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsFilterSortOldestMenuItem -Window $Window | Out-Null }
    $script:TicketsFilterMenu.Items.Add($script:TicketsFilterSortOldestMenuItem) | Out-Null

    $filterOpenMenuItem = $script:TicketsFilterOpenCheckbox
    $filterClosedMenuItem = $script:TicketsFilterClosedCheckbox
    $filterDeletedMenuItem = $script:TicketsFilterDeletedCheckbox
    $filterAssigneeMenuItem = $script:TicketsFilterAssigneeMenuItem
    $sortPriorityMenuItem = $script:TicketsFilterSortPriorityMenuItem
    $sortNewestMenuItem = $script:TicketsFilterSortNewestMenuItem
    $sortOldestMenuItem = $script:TicketsFilterSortOldestMenuItem

    $updateFilterTooltip = {
        $statusLabels = @()
        if ($script:ShowOpen) { $statusLabels += "Open" }
        if ($script:ShowClosed) { $statusLabels += "Closed" }
        if ($script:ShowDeleted) { $statusLabels += "Deleted" }
        $statusSummary = if ($statusLabels.Count -gt 0) { $statusLabels -join ", " } else { "None" }

        $sortSummary = switch ($script:TicketsSortMode) {
            "Newest" { "Newest first" }
            "Oldest" { "Oldest first" }
            default { "Priority High -> Low" }
        }
        $assigneeSummary = & $normalizeAssigneeFilterCmd -Value $script:TicketsAssigneeFilter
        if ([string]::IsNullOrWhiteSpace($assigneeSummary)) { $assigneeSummary = "All" }
        $btnFilterMenu.ToolTip = ("Filter tickets (Status: {0} | Assignee: {1} | Sort: {2})" -f $statusSummary, $assigneeSummary, $sortSummary)
    }.GetNewClosure()

    $applyFilterSelection = {
        param(
            [bool]$LogChange = $false,
            [AllowNull()][string]$SortModeHint = "",
            [AllowNull()][string]$AssigneeFilterHint = ""
        )
        $previousSortMode = [string]$script:TicketsSortMode

        $script:ShowOpen = [bool]$filterOpenMenuItem.IsChecked
        $script:ShowClosed = [bool]$filterClosedMenuItem.IsChecked
        $script:ShowDeleted = [bool]$filterDeletedMenuItem.IsChecked

        $requestedSortMode = ([string]($SortModeHint + "")).Trim()
        if (-not [string]::IsNullOrWhiteSpace($requestedSortMode)) {
            $script:TicketsSortMode = $requestedSortMode
        } else {
            $checkedSortMode = ""
            try {
                if ($sortNewestMenuItem -and [bool]$sortNewestMenuItem.IsChecked) {
                    $checkedSortMode = "Newest"
                }
                elseif ($sortOldestMenuItem -and [bool]$sortOldestMenuItem.IsChecked) {
                    $checkedSortMode = "Oldest"
                }
                elseif ($sortPriorityMenuItem -and [bool]$sortPriorityMenuItem.IsChecked) {
                    $checkedSortMode = "Priority"
                }
            } catch { $checkedSortMode = "" }

            if (-not [string]::IsNullOrWhiteSpace($checkedSortMode)) {
                $script:TicketsSortMode = $checkedSortMode
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$script:TicketsSortMode)) {
                $script:TicketsSortMode = "Priority"
            }
        }
        switch ($script:TicketsSortMode.ToLowerInvariant()) {
            "newest" { $script:TicketsSortMode = "Newest" }
            "oldest" { $script:TicketsSortMode = "Oldest" }
            default { $script:TicketsSortMode = "Priority" }
        }
        $requestedAssigneeFilter = ([string]($AssigneeFilterHint + "")).Trim()
        if (-not [string]::IsNullOrWhiteSpace($requestedAssigneeFilter)) {
            $script:TicketsAssigneeFilter = & $normalizeAssigneeFilterCmd -Value $requestedAssigneeFilter
        } else {
            $checkedAssigneeFilter = ""
            foreach ($assigneeItem in @(
                    $script:TicketsFilterAssigneeAllMenuItem,
                    $script:TicketsFilterAssigneeUnassignedMenuItem
                ) + @($script:TicketsFilterAssigneeDynamicMenuItems)) {
                if (-not $assigneeItem) { continue }
                $isCheckedAssignee = $false
                try { $isCheckedAssignee = [bool]$assigneeItem.IsChecked } catch { $isCheckedAssignee = $false }
                if (-not $isCheckedAssignee) { continue }

                $assigneeTag = ""
                try { $assigneeTag = [string]($assigneeItem.Tag + "") } catch { $assigneeTag = "" }
                if ($assigneeTag.StartsWith("Assignee:", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $checkedAssigneeFilter = $assigneeTag.Substring(9)
                    break
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($checkedAssigneeFilter)) {
                $script:TicketsAssigneeFilter = & $normalizeAssigneeFilterCmd -Value $checkedAssigneeFilter
            } else {
                $script:TicketsAssigneeFilter = & $normalizeAssigneeFilterCmd -Value $script:TicketsAssigneeFilter
            }
        }

        if ($setFilterRuntimeStateLocal) {
            & $setFilterRuntimeStateLocal -ShowOpen $script:ShowOpen -ShowClosed $script:ShowClosed -ShowDeleted $script:ShowDeleted -SortMode $script:TicketsSortMode -AssigneeFilter $script:TicketsAssigneeFilter -Grid $grid
        }

        # Sort options are mutually exclusive (radio-style): only one can be checked.
        try { $script:TicketsFilterSortPriorityMenuItem.IsChecked = ($script:TicketsSortMode -eq "Priority") } catch { }
        try { $script:TicketsFilterSortNewestMenuItem.IsChecked = ($script:TicketsSortMode -eq "Newest") } catch { }
        try { $script:TicketsFilterSortOldestMenuItem.IsChecked = ($script:TicketsSortMode -eq "Oldest") } catch { }

        # Keep at least one status filter active so Tickets never reopens as a blank list by accident.
        if (-not ($script:ShowOpen -or $script:ShowClosed -or $script:ShowDeleted)) {
            $script:ShowOpen = $true
            try { $filterOpenMenuItem.IsChecked = $true } catch { }
        }

        # Keep checkbox visuals and internal state aligned.
        try { $filterOpenMenuItem.IsChecked = [bool]$script:ShowOpen } catch { }
        try { $filterClosedMenuItem.IsChecked = [bool]$script:ShowClosed } catch { }
        try { $filterDeletedMenuItem.IsChecked = [bool]$script:ShowDeleted } catch { }
        foreach ($assigneeItem in @(
                $script:TicketsFilterAssigneeAllMenuItem,
                $script:TicketsFilterAssigneeUnassignedMenuItem
            ) + @($script:TicketsFilterAssigneeDynamicMenuItems)) {
            if (-not $assigneeItem) { continue }
            $assigneeTag = ""
            try { $assigneeTag = [string]($assigneeItem.Tag + "") } catch { $assigneeTag = "" }
            $assigneeValue = ""
            if ($assigneeTag.StartsWith("Assignee:", [System.StringComparison]::OrdinalIgnoreCase)) {
                $assigneeValue = $assigneeTag.Substring(9)
            }
            $assigneeValue = & $normalizeAssigneeFilterCmd -Value $assigneeValue
            try { $assigneeItem.IsChecked = ($assigneeValue -ieq $script:TicketsAssigneeFilter) } catch { }
        }

        if (-not $script:TicketsFilterState) {
            $script:TicketsFilterState = [pscustomobject]@{
                ShowOpen             = [bool]$script:TicketsFilterDefaults.ShowOpen
                ShowClosed           = [bool]$script:TicketsFilterDefaults.ShowClosed
                ShowDeleted          = [bool]$script:TicketsFilterDefaults.ShowDeleted
                SortMode             = [string]$script:TicketsFilterDefaults.SortMode
                AssigneeFilter       = [string]$script:TicketsFilterDefaults.AssigneeFilter
            }
        }

        foreach ($prop in @("ShowOpen", "ShowClosed", "ShowDeleted", "SortMode", "AssigneeFilter")) {
            if ($script:TicketsFilterState.PSObject.Properties.Name -notcontains $prop) {
                $script:TicketsFilterState | Add-Member -NotePropertyName $prop -NotePropertyValue ($script:TicketsFilterDefaults.$prop) -Force
            }
            if ($null -eq $script:TicketsFilterState.$prop) {
                $script:TicketsFilterState.$prop = $script:TicketsFilterDefaults.$prop
            }
        }

        $state = $script:TicketsFilterState
        $state.ShowOpen = $script:ShowOpen
        $state.ShowClosed = $script:ShowClosed
        $state.ShowDeleted = $script:ShowDeleted
        $state.SortMode = $script:TicketsSortMode
        $state.AssigneeFilter = $script:TicketsAssigneeFilter

        & $updateFilterTooltip

        if ($LogChange) {
            Write-QOTicketsUILog ("Tickets filter updated: Open={0}, Closed={1}, Deleted={2}, Assignee={3}, SortMode={4}" -f $script:ShowOpen, $script:ShowClosed, $script:ShowDeleted, $script:TicketsAssigneeFilter, $script:TicketsSortMode)
        }
        $persisted = $false
        try {
            $persisted = [bool](Save-QOTicketsFilterState -ShowOpen $script:ShowOpen -ShowClosed $script:ShowClosed -ShowDeleted $script:ShowDeleted -SortMode $script:TicketsSortMode -AssigneeFilter $script:TicketsAssigneeFilter)
        } catch { $persisted = $false }
        if ((-not $persisted) -and $setTicketListViewCmd) {
            try {
                $null = & $setTicketListViewCmd -ShowOpen $script:ShowOpen -ShowClosed $script:ShowClosed -ShowDeleted $script:ShowDeleted -SortMode $script:TicketsSortMode -AssigneeFilter $script:TicketsAssigneeFilter
            } catch {
                Write-QOTicketsUILog ("Tickets: Persisting filter/sort settings failed. " + $_.Exception.Message) "WARN"
            }
        }
        if ($invokeTicketsFilterLocal) {
            & $invokeTicketsFilterLocal -ForceRefresh -Grid $grid
        } else {
            Invoke-QOTicketsFilterSafely -ForceRefresh -Grid $grid
        }
        if ($LogChange -and $grid) {
            try {
                if ($grid.Items.Count -gt 0) {
                    $topTicket = $grid.Items[0]
                    $topSubject = ""
                    $topCreated = ""
                    try { if ($topTicket -and $topTicket.PSObject.Properties.Name -contains "Subject") { $topSubject = [string]$topTicket.Subject } } catch { }
                    try { if ($topTicket -and $topTicket.PSObject.Properties.Name -contains "CreatedAtDisplay") { $topCreated = [string]$topTicket.CreatedAtDisplay } } catch { }
                    if ([string]::IsNullOrWhiteSpace($topCreated)) {
                        try { if ($topTicket -and $topTicket.PSObject.Properties.Name -contains "CreatedAt") { $topCreated = [string]$topTicket.CreatedAt } } catch { }
                    }
                    Write-QOTicketsUILog ("Tickets sort preview: Top='{0}', Created='{1}', SortMode={2}" -f $topSubject, $topCreated, $script:TicketsSortMode)
                }
            } catch { }
        }

        $sortModeChanged = (([string]($previousSortMode + "")).Trim().ToLowerInvariant() -ne ([string]($script:TicketsSortMode + "")).Trim().ToLowerInvariant())
        if ($sortModeChanged -and $grid) {
            try {
                # Make sort changes visibly obvious: clear sticky selection and jump to the first row.
                $grid.UnselectAll()
            } catch { }
            try {
                if ($grid.Items.Count -gt 0) {
                    $firstItem = $grid.Items[0]
                    $grid.ScrollIntoView($firstItem)
                }
            } catch { }
        }
    }.GetNewClosure()

    $script:TicketsFilterCheckboxHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $eventSource = $sender
            try {
                if ($eventSource -is [System.Collections.IEnumerable] -and $eventSource -isnot [string]) {
                    foreach ($candidate in @($eventSource)) {
                        if ($null -eq $candidate) { continue }
                        $hasTag = $false
                        try { $hasTag = ($candidate.PSObject.Properties.Name -contains "Tag") } catch { $hasTag = $false }
                        if ($hasTag) { $eventSource = $candidate; break }
                    }
                }
            } catch { $eventSource = $sender }

            $tagValue = ""
            try {
                if ($eventSource -and ($eventSource.PSObject.Properties.Name -contains "Tag")) {
                    $tagValue = ([string]($eventSource.Tag + "")).Trim()
                }
            } catch { $tagValue = "" }

            if ($tagValue.StartsWith("Assignee:", [System.StringComparison]::OrdinalIgnoreCase)) {
                $assigneeFilterHint = & $normalizeAssigneeFilterCmd -Value $tagValue.Substring(9)
                & $applyFilterSelection $true "" $assigneeFilterHint
                return
            }

            $sortModeHint = $tagValue

            if ($sortModeHint -ne "Priority" -and $sortModeHint -ne "Newest" -and $sortModeHint -ne "Oldest") {
                return
            }

            try {
                if ($sortPriorityMenuItem) { $sortPriorityMenuItem.IsChecked = ($sortModeHint -eq "Priority") }
                if ($sortNewestMenuItem) { $sortNewestMenuItem.IsChecked = ($sortModeHint -eq "Newest") }
                if ($sortOldestMenuItem) { $sortOldestMenuItem.IsChecked = ($sortModeHint -eq "Oldest") }
            } catch { }

            & $applyFilterSelection $true $sortModeHint
        } catch {
            Write-QOTicketsUILog ("Tickets: Filter change failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    $resolveFilterAssigneeValues = {
        $rawItems = @()
        if ($getAssigneesCmd) {
            try { $rawItems = @(& $getAssigneesCmd) } catch { $rawItems = @() }
        }

        $valueSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        [void]$valueSet.Add("Unassigned")
        foreach ($raw in @($rawItems)) {
            $normalized = & $normalizeAssigneeFilterCmd -Value ([string]$raw)
            if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq "All") { continue }
            [void]$valueSet.Add($normalized)
        }

        $currentAssignee = ""
        try { $currentAssignee = [string](& $getCurrentAssigneeCmd) } catch { $currentAssignee = "" }
        $currentAssignee = & $normalizeAssigneeFilterCmd -Value $currentAssignee
        if (-not [string]::IsNullOrWhiteSpace($currentAssignee) -and $currentAssignee -ne "All") {
            [void]$valueSet.Add($currentAssignee)
        }

        $sorted = @($valueSet | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -and $_ -ne "All" } | Sort-Object)
        return @("All") + @($sorted)
    }.GetNewClosure()

    $rebuildFilterAssigneeMenu = {
        if (-not $filterAssigneeMenuItem) { return }

        try { $filterAssigneeMenuItem.Items.Clear() } catch { }
        $script:TicketsFilterAssigneeAllMenuItem = $null
        $script:TicketsFilterAssigneeUnassignedMenuItem = $null
        $script:TicketsFilterAssigneeDynamicMenuItems = @()

        $selectedAssigneeFilter = & $normalizeAssigneeFilterCmd -Value $script:TicketsAssigneeFilter
        $assigneeValues = @(& $resolveFilterAssigneeValues)
        foreach ($assigneeValue in @($assigneeValues)) {
            $normalizedAssignee = & $normalizeAssigneeFilterCmd -Value $assigneeValue
            if ([string]::IsNullOrWhiteSpace($normalizedAssignee)) { continue }

            $item = New-Object System.Windows.Controls.MenuItem
            $item.IsCheckable = $true
            $item.IsEnabled = $true
            $item.Tag = ("Assignee:{0}" -f $normalizedAssignee)
            $item.IsChecked = ($normalizedAssignee -ieq $selectedAssigneeFilter)
            $item.Header = if ($normalizedAssignee -eq "All") { "All assignees" } else { $normalizedAssignee }
            if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $item -Window $Window | Out-Null }
            try { $item.Add_Click($script:TicketsFilterCheckboxHandler) } catch { }
            $filterAssigneeMenuItem.Items.Add($item) | Out-Null

            if ($normalizedAssignee -eq "All") {
                $script:TicketsFilterAssigneeAllMenuItem = $item
            } elseif ($normalizedAssignee -eq "Unassigned") {
                $script:TicketsFilterAssigneeUnassignedMenuItem = $item
            } else {
                $script:TicketsFilterAssigneeDynamicMenuItems += @($item)
            }
        }
    }.GetNewClosure()
    & $rebuildFilterAssigneeMenu

    $script:TicketsFilterStatusCheckedHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try { & $applyFilterSelection $true } catch {
            Write-QOTicketsUILog ("Tickets: Status filter (checked) failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    $script:TicketsFilterStatusUncheckedHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try { & $applyFilterSelection $true } catch {
            Write-QOTicketsUILog ("Tickets: Status filter (unchecked) failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    $script:TicketsFilterStatusClickHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try { & $applyFilterSelection $true } catch {
            Write-QOTicketsUILog ("Tickets: Status filter (click) failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    foreach ($checkbox in @(
            $filterOpenMenuItem,
            $filterClosedMenuItem,
            $filterDeletedMenuItem)) {
        if (-not $checkbox) { continue }
        try { $checkbox.Add_Checked($script:TicketsFilterStatusCheckedHandler) } catch { }
        try { $checkbox.Add_Unchecked($script:TicketsFilterStatusUncheckedHandler) } catch { }
    }

    foreach ($sortItem in @(
            $script:TicketsFilterSortPriorityMenuItem,
            $script:TicketsFilterSortNewestMenuItem,
            $script:TicketsFilterSortOldestMenuItem)) {
        if (-not $sortItem) { continue }
        try { $sortItem.Add_Click($script:TicketsFilterCheckboxHandler) } catch { }
    }

    $script:TicketsFilterButtonHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $cm = $btnFilterMenu.ContextMenu
            if (-not $cm) { throw "FilterButton.ContextMenu is null" }
            if ($cm -is [System.Windows.Controls.ContextMenu]) {
                try { & $rebuildFilterAssigneeMenu } catch { }
                $placementTarget = $btnFilterMenu
                try {
                    if ($btnFilterMenu.Tag -is [System.Windows.UIElement]) {
                        $placementTarget = $btnFilterMenu.Tag
                    }
                    elseif ($sender -is [System.Windows.UIElement]) {
                        $placementTarget = $sender
                    }
                } catch { $placementTarget = $btnFilterMenu }
                $cm.PlacementTarget = $placementTarget
                $cm.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
                $cm.IsOpen = $true
                try { if ($btnFilterMenu.Tag -is [System.Windows.UIElement]) { $btnFilterMenu.Tag = $null } } catch { }
            } else {
                throw "Filter menu is not a ContextMenu"
            }
        } catch {
            Write-QOTicketsUILog ("Tickets: Filter menu open failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $btnFilterMenu.Add_Click($script:TicketsFilterButtonHandler)

    $script:TicketsFilterMenuClosedHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            & $applyFilterSelection $false
        } catch {
            Write-QOTicketsUILog ("Tickets: Filter menu close persist failed: " + $_.Exception.Message) "WARN"
        }
    }.GetNewClosure()
    try { $script:TicketsFilterMenu.Add_Closed($script:TicketsFilterMenuClosedHandler) } catch { }

    $saveFilterStateCmd = Resolve-QOTicketsLocalFunction -Name "Save-QOTicketsFilterState"
    if (-not $saveFilterStateCmd) {
        $saveFilterStateCmd = Resolve-QOTInvokable -Candidate (Get-Command Save-QOTicketsFilterState -ErrorAction SilentlyContinue) -CommandName "Save-QOTicketsFilterState"
    }
    if (-not $saveFilterStateCmd) {
        try { $saveFilterStateCmd = ${function:Save-QOTicketsFilterState} } catch { $saveFilterStateCmd = $null }
    }

    $script:TicketsWindowClosingHandler = [System.ComponentModel.CancelEventHandler]{
        param($sender, $args)
        try {
            if ($saveFilterStateCmd) {
                $sortModeToPersist = ([string]($script:TicketsSortMode + "")).Trim()
                if ([string]::IsNullOrWhiteSpace($sortModeToPersist)) { $sortModeToPersist = "Priority" }
                $null = & $saveFilterStateCmd -ShowOpen ([bool]$script:ShowOpen) -ShowClosed ([bool]$script:ShowClosed) -ShowDeleted ([bool]$script:ShowDeleted) -SortMode $sortModeToPersist -AssigneeFilter ([string]$script:TicketsAssigneeFilter)
            }
        } catch {
            Write-QOTicketsUILog ("Tickets: Persisting filter state on window close failed. " + $_.Exception.Message) "WARN"
        }

        # Release every event handler tracked in the registry so they can't fire
        # against a disposed window and so their closures can be garbage-collected.
        try { Unregister-QOTicketEventHandlers } catch {
            Write-QOTicketsUILog ("Tickets: Unregister-QOTicketEventHandlers on close failed: " + $_.Exception.Message) "WARN"
        }

        # Dispose the FileSystemWatcher so it cannot keep firing change events
        # against a closed UI and accumulate background work after shutdown.
        try { $null = Stop-QOTicketsFileWatcher } catch {
            Write-QOTicketsUILog ("Tickets: Stop-QOTicketsFileWatcher on close failed: " + $_.Exception.Message) "WARN"
        }
    }.GetNewClosure()
    try { $Window.Add_Closing($script:TicketsWindowClosingHandler) } catch { }

    try {
        $loadedSortMode = ([string]($script:TicketsSortMode + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($loadedSortMode)) { $loadedSortMode = "Priority" }
        $loadedAssigneeFilter = ([string]($script:TicketsAssigneeFilter + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($loadedAssigneeFilter)) { $loadedAssigneeFilter = "All" }

        & $applyFilterSelection $false $loadedSortMode $loadedAssigneeFilter
        Write-QOTicketsUILog ("Tickets: Restored filter state on startup. Open={0}, Closed={1}, Deleted={2}, Assignee={3}, SortMode={4}" -f $script:ShowOpen, $script:ShowClosed, $script:ShowDeleted, $script:TicketsAssigneeFilter, $script:TicketsSortMode)
    } catch {
        Write-QOTicketsUILog ("Tickets: Startup filter restore failed: " + $_.Exception.Message) "WARN"
    }

    $statusMenuItems = @()
    try { $statusMenuItems = @(& $getStatusesCmd) } catch { $statusMenuItems = @("New", "In Progress", "Pending", "Closed") }
    if (@($statusMenuItems).Count -eq 0) { $statusMenuItems = @("New", "In Progress", "Pending", "Closed") }
    $statusMenuItems = @(
        $statusMenuItems |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
    if ($statusMenuItems -notcontains "New") {
        $statusMenuItems = @("New") + @($statusMenuItems)
    }

    $priorityMenuItems = @()
    if ($getPrioritiesCmd) {
        try { $priorityMenuItems = @(& $getPrioritiesCmd) } catch { $priorityMenuItems = @() }
    }
    if (@($priorityMenuItems).Count -eq 0) { $priorityMenuItems = @("Low", "Medium", "High", "Critical") }

    $resolveAssigneeMenuItems = {
        $rawItems = @()
        if ($getAssigneesCmd) {
            try { $rawItems = @(& $getAssigneesCmd) } catch { $rawItems = @() }
        }

        $nameSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        [void]$nameSet.Add("Unassigned")

        foreach ($raw in @($rawItems)) {
            $value = ([string]($raw + "")).Trim()
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            if ($value -match '^(?i)(none|n/?a|null)$') { $value = "Unassigned" }
            [void]$nameSet.Add($value)
        }

        $currentValue = ""
        try { $currentValue = [string](& $getCurrentAssigneeCmd) } catch { $currentValue = "" }
        if (-not [string]::IsNullOrWhiteSpace($currentValue)) {
            [void]$nameSet.Add($currentValue)
        }

        $sorted = @($nameSet | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object)
        return @("Unassigned") + @($sorted | Where-Object { $_ -ne "Unassigned" })
    }.GetNewClosure()

    $assigneeMenuItems = @(& $resolveAssigneeMenuItems)
    $currentAssigneeValue = ""
    try { $currentAssigneeValue = [string](& $getCurrentAssigneeCmd) } catch { $currentAssigneeValue = "Me" }
    $openTicketDetailsFromContext = $null

    $script:TicketsRowContextMenu = New-Object System.Windows.Controls.ContextMenu
    if ($applyTicketsContextMenuThemeCmd) { & $applyTicketsContextMenuThemeCmd -ContextMenu $script:TicketsRowContextMenu -Window $Window | Out-Null }
    $script:TicketsUndeleteMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsUndeleteMenuItem.Header = "Undelete"
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsUndeleteMenuItem -Window $Window | Out-Null }
    $script:TicketsRowContextMenu.Items.Add($script:TicketsUndeleteMenuItem) | Out-Null
    $script:TicketsOpenMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsOpenMenuItem.Header = "Open ticket"
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsOpenMenuItem -Window $Window | Out-Null }
    $script:TicketsRowContextMenu.Items.Add($script:TicketsOpenMenuItem) | Out-Null
    $script:TicketsCloseMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsCloseMenuItem.Header = "Close ticket"
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsCloseMenuItem -Window $Window | Out-Null }
    $script:TicketsRowContextMenu.Items.Add($script:TicketsCloseMenuItem) | Out-Null
    $script:TicketsClaimMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsClaimMenuItem.Header = ("Claim ticket ({0})" -f $currentAssigneeValue)
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsClaimMenuItem -Window $Window | Out-Null }
    $script:TicketsRowContextMenu.Items.Add($script:TicketsClaimMenuItem) | Out-Null
    $script:TicketsAddNoteMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsAddNoteMenuItem.Header = "Add note"
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsAddNoteMenuItem -Window $Window | Out-Null }
    $script:TicketsRowContextMenu.Items.Add($script:TicketsAddNoteMenuItem) | Out-Null
    $script:TicketsRenameMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsRenameMenuItem.Header = "Rename title"
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsRenameMenuItem -Window $Window | Out-Null }
    $script:TicketsRowContextMenu.Items.Add($script:TicketsRenameMenuItem) | Out-Null
    $script:TicketsSetStatusMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsSetStatusMenuItem.Header = "Set status"
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsSetStatusMenuItem -Window $Window | Out-Null }
    $script:TicketsRowContextMenu.Items.Add($script:TicketsSetStatusMenuItem) | Out-Null
    $script:TicketsSetPriorityMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsSetPriorityMenuItem.Header = "Set priority"
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsSetPriorityMenuItem -Window $Window | Out-Null }
    $script:TicketsRowContextMenu.Items.Add($script:TicketsSetPriorityMenuItem) | Out-Null
    $script:TicketsSetAssignedToMenuItem = New-Object System.Windows.Controls.MenuItem
    $script:TicketsSetAssignedToMenuItem.Header = "Assign to"
    if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $script:TicketsSetAssignedToMenuItem -Window $Window | Out-Null }
    $script:TicketsRowContextMenu.Items.Add($script:TicketsSetAssignedToMenuItem) | Out-Null

    $script:TicketsUndeleteHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $selectedItems = @(& $getSelectedTicketsCmd -Grid $grid -AllowContextFallback)
            if ($selectedItems.Count -eq 0) { return }

            $ids = @(
                $selectedItems |
                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") } |
                    ForEach-Object { $_.Id }
            )
            if ($ids.Count -eq 0) { return }

            $null = & $restoreCmd -Id $ids
            & $invokeGridRefresh
        } catch {
            Write-QOTicketsUILog ("Tickets: Undelete failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $script:TicketsUndeleteMenuItem.Add_Click($script:TicketsUndeleteHandler)

    $script:TicketsCloseHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $selectedItems = @(& $getSelectedTicketsCmd -Grid $grid -AllowContextFallback)
            if ($selectedItems.Count -eq 0) { return }

            $ids = @(
                $selectedItems |
                    Where-Object {
                        $_ -and
                        ($_.PSObject.Properties.Name -contains "Id") -and
                        (-not ($_.PSObject.Properties.Name -contains "IsDeleted" -and [bool]$_.IsDeleted))
                    } |
                    ForEach-Object { $_.Id }
            )
            if ($ids.Count -eq 0) { return }

            $null = & $setStatusCmd -Id $ids -Status "Closed"
            & $invokeGridRefresh
        } catch {
            Write-QOTicketsUILog ("Tickets: Close handler failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $script:TicketsCloseMenuItem.Add_Click($script:TicketsCloseHandler)

    $script:TicketsClaimMenuItemHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $assignedToValue = ""
            try { $assignedToValue = [string](& $getCurrentAssigneeCmd) } catch { $assignedToValue = "" }
            if ([string]::IsNullOrWhiteSpace($assignedToValue)) { $assignedToValue = "Me" }

            $selectedItems = @(& $getSelectedTicketsCmd -Grid $grid -AllowContextFallback)
            if ($selectedItems.Count -eq 0) { return }

            foreach ($item in $selectedItems) {
                if ($null -eq $item) { continue }
                try { $item.AssignedTo = $assignedToValue } catch { }
            }
            $grid.Items.Refresh()

            $ids = @(
                $selectedItems |
                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") } |
                    ForEach-Object { $_.Id }
            )
            if ($ids.Count -eq 0) { return }

            if ($setAssignedToCmd) {
                $null = & $setAssignedToCmd -Id $ids -AssignedTo $assignedToValue
            } else {
                foreach ($item in $selectedItems) {
                    if ($null -eq $item) { continue }
                    $null = & $updateTicketCmd -Ticket $item
                }
            }
            & $invokeGridRefresh
        } catch {
            Write-QOTicketsUILog ("Tickets: Claim failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $script:TicketsClaimMenuItem.Add_Click($script:TicketsClaimMenuItemHandler)

    $script:TicketsAddNoteHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $ticket = $grid.SelectedItem
            if (-not $ticket) {
                try { Show-QOTicketsOpenPulse -StatusText $syncStatusText -Message "Open a ticket first." -DurationMilliseconds 1800 } catch { }
                return
            }

            $ticketId = ""
            try { if ($ticket.PSObject.Properties.Name -contains "Id") { $ticketId = [string]$ticket.Id } } catch { $ticketId = "" }
            if ([string]::IsNullOrWhiteSpace($ticketId)) { return }

            try { Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null } catch { }
            $noteText = [Microsoft.VisualBasic.Interaction]::InputBox("Add note for selected ticket:", "Ticket note", "")
            $noteText = ([string]$noteText).Trim()
            if ([string]::IsNullOrWhiteSpace($noteText)) { return }

            if ($addNoteCmd) {
                $updatedTicket = & $addNoteCmd -Id $ticketId -Note $noteText -Author "User"
                if ($updatedTicket) { $ticket = $updatedTicket }
            } else {
                if (-not ($ticket.PSObject.Properties.Name -contains "Notes")) {
                    $ticket | Add-Member -NotePropertyName Notes -NotePropertyValue @() -Force
                }
                $ticket.Notes = @($ticket.Notes) + @([pscustomobject]@{
                    Body      = $noteText
                    CreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    Author    = "User"
                })
                $ticket.UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                $null = & $updateTicketCmd -Ticket $ticket
            }

            & $invokeGridRefresh
            try { & $invokeDetailsUpdate $grid.SelectedItem } catch { }
        } catch {
            Write-QOTicketsUILog ("Tickets: Add note failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $script:TicketsAddNoteMenuItem.Add_Click($script:TicketsAddNoteHandler)

    $startInlineRenameTicket = {
        param(
            [AllowNull()]$Ticket,
            [switch]$DeferredPass
        )
        try {
            if (-not $Ticket) { return $false }
            if (-not $grid.Columns -or $grid.Columns.Count -lt 1) { return $false }

            $targetColumn = $grid.Columns[0]
            if (-not $targetColumn) { return $false }

            $resolveParentVisualForRename = {
                param(
                    [AllowNull()]$Element,
                    [Parameter(Mandatory)][Type]$Type
                )

                $current = $Element
                while ($current) {
                    if ($Type.IsInstanceOfType($current)) { return $current }
                    try {
                        if ($current -is [System.Windows.Media.Visual] -or $current -is [System.Windows.Media.Media3D.Visual3D]) {
                            $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
                        } elseif ($current -is [System.Windows.FrameworkContentElement]) {
                            $current = $current.Parent
                            if (-not $current) { $current = [System.Windows.LogicalTreeHelper]::GetParent($current) }
                        } else {
                            $current = [System.Windows.LogicalTreeHelper]::GetParent($current)
                        }
                    } catch {
                        $current = $null
                    }
                }
                return $null
            }.GetNewClosure()

            $findVisualChildByType = {
                param(
                    [AllowNull()]$Root,
                    [Parameter(Mandatory)][Type]$Type,
                    # Depth guard - stops runaway recursion if the visual tree
                    # is unexpectedly deep or contains a cycle.
                    [int]$Depth = 0,
                    [int]$MaxDepth = 64
                )

                if (-not $Root) { return $null }
                if ($Depth -ge $MaxDepth) {
                    try { Write-QOTicketsUILog ("findVisualChildByType aborted at depth {0} looking for '{1}'." -f $Depth, $Type.FullName) "WARN" } catch { }
                    return $null
                }
                try {
                    if ($Type.IsInstanceOfType($Root)) { return $Root }
                } catch { }

                $childCount = 0
                try { $childCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root) } catch { $childCount = 0 }
                for ($idx = 0; $idx -lt $childCount; $idx++) {
                    $child = $null
                    try { $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Root, $idx) } catch { $child = $null }
                    if (-not $child) { continue }
                    $resolved = & $findVisualChildByType -Root $child -Type $Type -Depth ($Depth + 1) -MaxDepth $MaxDepth
                    if ($resolved) { return $resolved }
                }
                return $null
            }.GetNewClosure()

            try { $grid.SelectedItems.Clear() } catch { }
            try { $grid.SelectedItem = $Ticket } catch { }
            try { $grid.CurrentCell = New-Object System.Windows.Controls.DataGridCellInfo($Ticket, $targetColumn) } catch { }
            try { $grid.ScrollIntoView($Ticket, $targetColumn) } catch { }
            try { $null = $grid.Focus() } catch { }
            try { $grid.UpdateLayout() } catch { }

            $cellContent = $null
            try { $cellContent = $targetColumn.GetCellContent($Ticket) } catch { $cellContent = $null }
            $cell = $null
            if ($cellContent) {
                try { $cell = & $resolveParentVisualForRename -Element $cellContent -Type ([System.Windows.Controls.DataGridCell]) } catch { $cell = $null }
            }

            if (-not $cell) {
                try {
                    $row = [System.Windows.Controls.DataGridRow]$grid.ItemContainerGenerator.ContainerFromItem($Ticket)
                    if ($row) {
                        $presenter = & $findVisualChildByType -Root $row -Type ([System.Windows.Controls.DataGridCellsPresenter])
                        if (-not $presenter) {
                            try {
                                $null = $row.ApplyTemplate()
                                $presenter = & $findVisualChildByType -Root $row -Type ([System.Windows.Controls.DataGridCellsPresenter])
                            } catch { $presenter = $null }
                        }
                        if ($presenter) {
                            try {
                                $cell = [System.Windows.Controls.DataGridCell]$presenter.ItemContainerGenerator.ContainerFromIndex(0)
                            } catch { $cell = $null }
                            if (-not $cell) {
                                try {
                                    $cell = & $findVisualChildByType -Root $presenter -Type ([System.Windows.Controls.DataGridCell])
                                } catch { $cell = $null }
                            }
                        }
                    }
                } catch { $cell = $null }
            }

            if ($cell) {
                try { $cell.IsSelected = $true } catch { }
                try { $null = $cell.Focus() } catch { }
            }

            $editStarted = $false
            try { $editStarted = [bool]$grid.BeginEdit() } catch { $editStarted = $false }
            if (-not $editStarted -and $cell) {
                try { $editStarted = [bool]$cell.IsEditing } catch { $editStarted = $false }
            }
            if (-not $editStarted) {
                if (-not $DeferredPass) {
                    $ticketToEdit = $Ticket
                    try {
                        $null = $grid.Dispatcher.BeginInvoke([action]{
                            try { $null = & $startInlineRenameTicket -Ticket $ticketToEdit -DeferredPass } catch { }
                        }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::Input)
                        return $true
                    } catch { }
                }
                return $false
            }

            try { $grid.UpdateLayout() } catch { }

            $findInlineEditor = {
                param(
                    [AllowNull()]$Root,
                    [int]$Depth = 0,
                    [int]$MaxDepth = 64
                )
                if (-not $Root) { return $null }
                if ($Depth -ge $MaxDepth) {
                    try { Write-QOTicketsUILog ("findInlineEditor aborted at depth {0}." -f $Depth) "WARN" } catch { }
                    return $null
                }
                if ($Root -is [System.Windows.Controls.TextBox]) {
                    $editorName = ""
                    try { $editorName = [string]$Root.Name } catch { $editorName = "" }
                    if ([string]::IsNullOrWhiteSpace($editorName) -or $editorName -eq "TicketTitleInlineEditor") {
                        return $Root
                    }
                }
                $children = 0
                try { $children = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root) } catch { $children = 0 }
                for ($idx = 0; $idx -lt $children; $idx++) {
                    $child = $null
                    try { $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Root, $idx) } catch { $child = $null }
                    if (-not $child) { continue }
                    $resolved = & $findInlineEditor -Root $child -Depth ($Depth + 1) -MaxDepth $MaxDepth
                    if ($resolved) { return $resolved }
                }
                return $null
            }.GetNewClosure()

            $editor = $null
            if ($cell) {
                try { $editor = & $findInlineEditor -Root $cell } catch { $editor = $null }
            }
            if (-not $editor -and $cellContent) {
                try { $editor = & $findInlineEditor -Root $cellContent } catch { $editor = $null }
            }
            if (-not $editor) {
                try {
                    $currentContent = $null
                    $currentItem = $null
                    try { $currentItem = $grid.CurrentItem } catch { $currentItem = $null }
                    if ($currentItem) {
                        $currentContent = $targetColumn.GetCellContent($currentItem)
                    } elseif ($Ticket) {
                        $currentContent = $targetColumn.GetCellContent($Ticket)
                    }
                    if ($currentContent) { $editor = & $findInlineEditor -Root $currentContent }
                } catch { $editor = $null }
            }

            if (-not $editor) {
                if (-not $DeferredPass) {
                    $ticketToEdit = $Ticket
                    try {
                        $null = $grid.Dispatcher.BeginInvoke([action]{
                            try { $null = & $startInlineRenameTicket -Ticket $ticketToEdit -DeferredPass } catch { }
                        }.GetNewClosure(), [System.Windows.Threading.DispatcherPriority]::Background)
                        return $true
                    } catch { }
                }
                return $false
            }

            try { $null = $editor.Focus() } catch { }
            try { $editor.SelectAll() } catch { }
            return $true
        } catch {
            Write-QOTicketsUILog ("Tickets: Start inline rename failed: " + $_.Exception.Message) "ERROR"
            return $false
        }
    }.GetNewClosure()

    $script:TicketsRenameHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $selectedItems = @(& $getSelectedTicketsCmd -Grid $grid -AllowContextFallback)
            if ($selectedItems.Count -eq 0) { return }
            $selectedItem = $selectedItems[0]
            if (-not $selectedItem) { return }
            $null = & $startInlineRenameTicket -Ticket $selectedItem
        } catch {
            Write-QOTicketsUILog ("Tickets: Rename failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $script:TicketsRenameMenuItem.Add_Click($script:TicketsRenameHandler)

    $script:TicketsStatusMenuItemHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $senderItem = $sender
            if ($senderItem -is [System.Array]) {
                $senderItem = @($senderItem | Where-Object { $_ -is [System.Windows.Controls.MenuItem] } | Select-Object -First 1)
                if ($senderItem -is [System.Array] -and $senderItem.Count -gt 0) { $senderItem = $senderItem[0] }
            }
            $statusValue = ""
            try { if ($senderItem -is [System.Windows.Controls.MenuItem]) { $statusValue = [string]$senderItem.Tag } } catch { $statusValue = "" }
            if ([string]::IsNullOrWhiteSpace($statusValue)) { return }
            $effectiveStatusChangeCmd = $invokeTicketStatusChangeCmd
            if (-not $effectiveStatusChangeCmd) {
                try { $effectiveStatusChangeCmd = @(Get-Command Invoke-QOTicketStatusChangeForItems -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { $effectiveStatusChangeCmd = $null }
                if ($effectiveStatusChangeCmd -is [System.Array]) {
                    if ($effectiveStatusChangeCmd.Count -gt 0) { $effectiveStatusChangeCmd = $effectiveStatusChangeCmd[0] } else { $effectiveStatusChangeCmd = $null }
                }
            }
            if (-not $effectiveStatusChangeCmd) {
                try { $effectiveStatusChangeCmd = ${function:Invoke-QOTicketStatusChangeForItems} } catch { $effectiveStatusChangeCmd = $null }
            }
            if (-not $effectiveStatusChangeCmd) { throw "Status change command is unavailable." }
            $null = & $effectiveStatusChangeCmd -Grid $grid -StatusValue $statusValue -PreferredItems @() -GetSelectedTicketsCmd $getSelectedTicketsCmd -SetStatusCmd $setStatusCmd -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
        } catch {
            Write-QOTicketsUILog ("Tickets: Status change failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    $statusRootMenu = $script:TicketsSetStatusMenuItem

    $updateStatusMenuState = {
        param([object[]]$SelectedItems)

        $normalizedStatuses = @()
        foreach ($item in @($SelectedItems)) {
            if ($null -eq $item) { continue }

            $statusValue = ""
            try {
                if ($item.PSObject.Properties.Name -contains "Status") {
                    $statusValue = [string]$item.Status
                }
            } catch { $statusValue = "" }

            $statusValue = $statusValue.Trim()
            if ([string]::IsNullOrWhiteSpace($statusValue)) { $statusValue = "New" }
            if ($statusValue -eq "Open") { $statusValue = "In Progress" }
            if ($statusValue -eq "Waiting on User") { $statusValue = "Pending" }
            if ($statusValue -eq "Completed") { $statusValue = "Closed" }
            if ($statusMenuItems -notcontains $statusValue) { $statusValue = "New" }

            if ($normalizedStatuses -notcontains $statusValue) {
                $normalizedStatuses += $statusValue
            }
        }

        if ($statusRootMenu -isnot [System.Windows.Controls.MenuItem]) {
            Write-QOTicketsUILog "Tickets: Status context menu root is unavailable; skipping status menu state update." "WARN"
            return
        }

        foreach ($menuItem in @($statusRootMenu.Items)) {
            if ($menuItem -isnot [System.Windows.Controls.MenuItem]) { continue }
            $menuItem.IsCheckable = $true
            $menuItem.IsChecked = $false
            if ($normalizedStatuses.Count -eq 1 -and [string]$menuItem.Tag -eq [string]$normalizedStatuses[0]) {
                $menuItem.IsChecked = $true
            }
        }

        if ($normalizedStatuses.Count -eq 1) {
            $statusRootMenu.Header = ("Set status ({0})" -f [string]$normalizedStatuses[0])
        } elseif ($normalizedStatuses.Count -gt 1) {
            $statusRootMenu.Header = "Set status (mixed)"
        } else {
            $statusRootMenu.Header = "Set status"
        }
    }.GetNewClosure()

    foreach ($status in $statusMenuItems) {
        $menuItem = New-Object System.Windows.Controls.MenuItem
        $menuItem.Header = $status
        $menuItem.Tag = $status
        $menuItem.IsCheckable = $true
        if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $menuItem -Window $Window | Out-Null }
        $statusRootMenu.Items.Add($menuItem) | Out-Null
    }
    foreach ($menuItem in @($statusRootMenu.Items)) {
        try { $menuItem.Add_Click($script:TicketsStatusMenuItemHandler) } catch { }
    }
    & $updateStatusMenuState -SelectedItems @()

    $script:TicketsPriorityMenuItemHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $priorityValue = ([string]$sender.Tag).Trim()
            if ([string]::IsNullOrWhiteSpace($priorityValue)) { return }
            $effectivePriorityChangeCmd = $invokeTicketPriorityChangeCmd
            if (-not $effectivePriorityChangeCmd) {
                try { $effectivePriorityChangeCmd = @(Get-Command Invoke-QOTicketPriorityChangeForItems -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { $effectivePriorityChangeCmd = $null }
                if ($effectivePriorityChangeCmd -is [System.Array]) {
                    if ($effectivePriorityChangeCmd.Count -gt 0) { $effectivePriorityChangeCmd = $effectivePriorityChangeCmd[0] } else { $effectivePriorityChangeCmd = $null }
                }
            }
            if (-not $effectivePriorityChangeCmd) {
                try { $effectivePriorityChangeCmd = ${function:Invoke-QOTicketPriorityChangeForItems} } catch { $effectivePriorityChangeCmd = $null }
            }
            if (-not $effectivePriorityChangeCmd) { throw "Priority change command unavailable." }
            $null = & $effectivePriorityChangeCmd -Grid $grid -PreferredItems @() -PriorityValue $priorityValue -GetSelectedTicketsCmd $getSelectedTicketsCmd -SetPriorityCmd $setPriorityCmd -UpdateTicketCmd $updateTicketCmd -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
        } catch {
            Write-QOTicketsUILog ("Tickets: Priority update failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    foreach ($priority in $priorityMenuItems) {
        $menuItem = New-Object System.Windows.Controls.MenuItem
        $menuItem.Header = $priority
        $menuItem.Tag = $priority
        if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $menuItem -Window $Window | Out-Null }
        $script:TicketsSetPriorityMenuItem.Items.Add($menuItem) | Out-Null
    }
    foreach ($menuItem in @($script:TicketsSetPriorityMenuItem.Items)) {
        try { $menuItem.Add_Click($script:TicketsPriorityMenuItemHandler) } catch { }
    }

    $script:TicketsAssignMenuItemHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $senderItem = $sender
            if ($senderItem -is [System.Array]) {
                $senderItem = @($senderItem | Where-Object { $_ -is [System.Windows.Controls.MenuItem] } | Select-Object -First 1)
                if ($senderItem -is [System.Array] -and $senderItem.Count -gt 0) { $senderItem = $senderItem[0] }
            }
            $assignedToValue = ""
            try { if ($senderItem -is [System.Windows.Controls.MenuItem]) { $assignedToValue = [string]$senderItem.Tag } } catch { $assignedToValue = "" }
            $effectiveAssigneeChangeCmd = $invokeTicketAssigneeChangeCmd
            if (-not $effectiveAssigneeChangeCmd) {
                try { $effectiveAssigneeChangeCmd = @(Get-Command Invoke-QOTicketAssigneeChangeForItems -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { $effectiveAssigneeChangeCmd = $null }
                if ($effectiveAssigneeChangeCmd -is [System.Array]) {
                    if ($effectiveAssigneeChangeCmd.Count -gt 0) { $effectiveAssigneeChangeCmd = $effectiveAssigneeChangeCmd[0] } else { $effectiveAssigneeChangeCmd = $null }
                }
            }
            if (-not $effectiveAssigneeChangeCmd) {
                try { $effectiveAssigneeChangeCmd = ${function:Invoke-QOTicketAssigneeChangeForItems} } catch { $effectiveAssigneeChangeCmd = $null }
            }
            if (-not $effectiveAssigneeChangeCmd) { throw "Assignee change command is unavailable." }
            $null = & $effectiveAssigneeChangeCmd -Grid $grid -AssigneeValue $assignedToValue -PreferredItems @() -GetSelectedTicketsCmd $getSelectedTicketsCmd -SetAssignedToCmd $setAssignedToCmd -UpdateTicketCmd $updateTicketCmd -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
        } catch {
            Write-QOTicketsUILog ("Tickets: Assign failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    $script:TicketsAssignCustomMenuItemHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            try { Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null } catch { }

            $currentAssignee = ""
            try {
                $selectedItem = $grid.SelectedItem
                if ($selectedItem -and ($selectedItem.PSObject.Properties.Name -contains "AssignedTo")) {
                    $currentAssignee = [string]$selectedItem.AssignedTo
                }
            } catch { $currentAssignee = "" }

            $inputAssignee = [Microsoft.VisualBasic.Interaction]::InputBox("Assign selected ticket(s) to:", "Assign ticket", $currentAssignee)
            $inputAssignee = ([string]$inputAssignee).Trim()
            if (-not $inputAssignee) { $inputAssignee = "Unassigned" }
            $effectiveAssigneeChangeCmd = $invokeTicketAssigneeChangeCmd
            if (-not $effectiveAssigneeChangeCmd) {
                try { $effectiveAssigneeChangeCmd = @(Get-Command Invoke-QOTicketAssigneeChangeForItems -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { $effectiveAssigneeChangeCmd = $null }
                if ($effectiveAssigneeChangeCmd -is [System.Array]) {
                    if ($effectiveAssigneeChangeCmd.Count -gt 0) { $effectiveAssigneeChangeCmd = $effectiveAssigneeChangeCmd[0] } else { $effectiveAssigneeChangeCmd = $null }
                }
            }
            if (-not $effectiveAssigneeChangeCmd) {
                try { $effectiveAssigneeChangeCmd = ${function:Invoke-QOTicketAssigneeChangeForItems} } catch { $effectiveAssigneeChangeCmd = $null }
            }
            if (-not $effectiveAssigneeChangeCmd) { throw "Assignee change command is unavailable." }
            $null = & $effectiveAssigneeChangeCmd -Grid $grid -AssigneeValue $inputAssignee -PreferredItems @() -GetSelectedTicketsCmd $getSelectedTicketsCmd -SetAssignedToCmd $setAssignedToCmd -UpdateTicketCmd $updateTicketCmd -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
        } catch {
            Write-QOTicketsUILog ("Tickets: Assign custom failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()

    $rebuildAssignSubmenu = {
        param([AllowNull()][string]$SelectedAssignee)

        if (-not $script:TicketsSetAssignedToMenuItem) { return }

        $script:TicketsSetAssignedToMenuItem.Items.Clear()

        $dynamicAssignees = @(& $resolveAssigneeMenuItems)
        $selectedValue = ([string]($SelectedAssignee + "")).Trim()
        if ($selectedValue -and $selectedValue -ne "Unassigned" -and $dynamicAssignees -notcontains $selectedValue) {
            $dynamicAssignees = @($selectedValue) + @($dynamicAssignees)
        }

        $currentValue = ""
        try { $currentValue = [string](& $getCurrentAssigneeCmd) } catch { $currentValue = "" }
        foreach ($assignee in @($dynamicAssignees)) {
            $assigneeValue = ([string]($assignee + "")).Trim()
            if ([string]::IsNullOrWhiteSpace($assigneeValue)) { continue }

            $menuItem = New-Object System.Windows.Controls.MenuItem
            if ($assigneeValue -eq $currentValue) {
                $menuItem.Header = ("Me ({0})" -f $assigneeValue)
            } else {
                $menuItem.Header = $assigneeValue
            }
            $menuItem.Tag = $assigneeValue
            $menuItem.IsCheckable = $true
            $menuItem.IsChecked = ($selectedValue -and ($assigneeValue -eq $selectedValue))
            if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $menuItem -Window $Window | Out-Null }
            $script:TicketsSetAssignedToMenuItem.Items.Add($menuItem) | Out-Null
            try { $menuItem.Add_Click($script:TicketsAssignMenuItemHandler) } catch { }
        }

        $script:TicketsSetAssignedToMenuItem.Items.Add($(if ($newTicketsStyledSeparatorCmd) { & $newTicketsStyledSeparatorCmd -Window $Window } else { New-Object System.Windows.Controls.Separator })) | Out-Null
        $customAssignMenuItem = New-Object System.Windows.Controls.MenuItem
        $customAssignMenuItem.Header = "Set assignee..."
        if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $customAssignMenuItem -Window $Window | Out-Null }
        $script:TicketsSetAssignedToMenuItem.Items.Add($customAssignMenuItem) | Out-Null
        try { $customAssignMenuItem.Add_Click($script:TicketsAssignCustomMenuItemHandler) } catch { }
    }.GetNewClosure()

    $openStatusQuickMenu = {
        param(
            [AllowNull()][System.Windows.UIElement]$PlacementTarget,
            [AllowNull()][object[]]$SelectedItems
        )

        if (-not $PlacementTarget) { return $false }
        $items = @($SelectedItems | Where-Object { $null -ne $_ })
        if ($items.Count -eq 0) { return $false }

        $activeStatus = ""
        if ($items.Count -eq 1) {
            try {
                if ($items[0].PSObject.Properties.Name -contains "Status") {
                    $activeStatus = ([string]$items[0].Status).Trim()
                }
            } catch { $activeStatus = "" }
            if ($activeStatus -eq "Open") { $activeStatus = "In Progress" }
            if ($activeStatus -eq "Waiting on User") { $activeStatus = "Pending" }
            if ($activeStatus -eq "Completed") { $activeStatus = "Closed" }
        }

        $menu = New-Object System.Windows.Controls.ContextMenu
        if ($applyTicketsContextMenuThemeCmd) { & $applyTicketsContextMenuThemeCmd -ContextMenu $menu -Window $Window | Out-Null }
        $capturedItems = @($items)
        $openItem = New-Object System.Windows.Controls.MenuItem
        $openItem.Header = "Open ticket"
        $openItem.IsEnabled = ($capturedItems.Count -gt 0)
        if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $openItem -Window $Window | Out-Null }
        try {
            $openItem.Add_Click([System.Windows.RoutedEventHandler]{
                param($sender, $args)
                try {
                    $openCmd = $script:TicketsOpenFromContextCmd
                    if ($openCmd) {
                        $null = & $openCmd -Items $capturedItems -Source "status quick menu"
                    }
                } catch {
                    Write-QOTicketsUILog ("Tickets: Quick open from status menu failed: " + $_.Exception.Message) "ERROR"
                }
            }.GetNewClosure())
        } catch { }
        $menu.Items.Add($openItem) | Out-Null
        $menu.Items.Add($(if ($newTicketsStyledSeparatorCmd) { & $newTicketsStyledSeparatorCmd -Window $Window } else { New-Object System.Windows.Controls.Separator })) | Out-Null
        foreach ($status in @($statusMenuItems)) {
            $statusValue = ([string]($status + "")).Trim()
            if ([string]::IsNullOrWhiteSpace($statusValue)) { continue }

            $item = New-Object System.Windows.Controls.MenuItem
            $item.Header = $statusValue
            $item.Tag = $statusValue
            $item.IsCheckable = $true
            $item.IsChecked = ($activeStatus -and ($statusValue -eq $activeStatus))
            if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $item -Window $Window | Out-Null }
            $statusToApply = $statusValue
            try {
                $item.Add_Click([System.Windows.RoutedEventHandler]{
                    param($sender, $args)
                    try {
                        $effectiveStatusChangeCmd = $invokeTicketStatusChangeCmd
                        if (-not $effectiveStatusChangeCmd) {
                            try { $effectiveStatusChangeCmd = @(Get-Command Invoke-QOTicketStatusChangeForItems -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { $effectiveStatusChangeCmd = $null }
                            if ($effectiveStatusChangeCmd -is [System.Array]) {
                                if ($effectiveStatusChangeCmd.Count -gt 0) { $effectiveStatusChangeCmd = $effectiveStatusChangeCmd[0] } else { $effectiveStatusChangeCmd = $null }
                            }
                        }
                        if (-not $effectiveStatusChangeCmd) {
                            try { $effectiveStatusChangeCmd = ${function:Invoke-QOTicketStatusChangeForItems} } catch { $effectiveStatusChangeCmd = $null }
                        }
                        if (-not $effectiveStatusChangeCmd) { throw "Status change command is unavailable." }
                        $null = & $effectiveStatusChangeCmd -Grid $grid -StatusValue $statusToApply -PreferredItems $capturedItems -GetSelectedTicketsCmd $getSelectedTicketsCmd -SetStatusCmd $setStatusCmd -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
                    } catch {
                        Write-QOTicketsUILog ("Tickets: Quick status change failed: " + $_.Exception.Message) "ERROR"
                    }
                }.GetNewClosure())
            } catch { }
            $menu.Items.Add($item) | Out-Null
        }

        $menu.PlacementTarget = $PlacementTarget
        $menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::MousePoint
        $menu.IsOpen = $true
        return $true
    }.GetNewClosure()

    $openAssigneeQuickMenu = {
        param(
            [AllowNull()][System.Windows.UIElement]$PlacementTarget,
            [AllowNull()][string]$SelectedAssignee
        )

        if (-not $PlacementTarget) { return $false }

        $selectedValue = ([string]($SelectedAssignee + "")).Trim()
        $currentValue = ""
        try { $currentValue = [string](& $getCurrentAssigneeCmd) } catch { $currentValue = "" }
        $dynamicAssignees = @(& $resolveAssigneeMenuItems)
        if ($selectedValue -and $selectedValue -ne "Unassigned" -and $dynamicAssignees -notcontains $selectedValue) {
            $dynamicAssignees = @($selectedValue) + @($dynamicAssignees)
        }

        $menu = New-Object System.Windows.Controls.ContextMenu
        if ($applyTicketsContextMenuThemeCmd) { & $applyTicketsContextMenuThemeCmd -ContextMenu $menu -Window $Window | Out-Null }
        $capturedItems = @(& $getSelectedTicketsCmd -Grid $grid -AllowContextFallback)
        $openItem = New-Object System.Windows.Controls.MenuItem
        $openItem.Header = "Open ticket"
        $openItem.IsEnabled = ($capturedItems.Count -gt 0)
        if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $openItem -Window $Window | Out-Null }
        try {
            $openItem.Add_Click([System.Windows.RoutedEventHandler]{
                param($sender, $args)
                try {
                    $openCmd = $script:TicketsOpenFromContextCmd
                    if ($openCmd) {
                        $null = & $openCmd -Items $capturedItems -Source "assignee quick menu"
                    }
                } catch {
                    Write-QOTicketsUILog ("Tickets: Quick open from assignee menu failed: " + $_.Exception.Message) "ERROR"
                }
            }.GetNewClosure())
        } catch { }
        $menu.Items.Add($openItem) | Out-Null
        $menu.Items.Add($(if ($newTicketsStyledSeparatorCmd) { & $newTicketsStyledSeparatorCmd -Window $Window } else { New-Object System.Windows.Controls.Separator })) | Out-Null
        foreach ($assignee in @($dynamicAssignees)) {
            $assigneeValue = ([string]($assignee + "")).Trim()
            if ([string]::IsNullOrWhiteSpace($assigneeValue)) { continue }

            $item = New-Object System.Windows.Controls.MenuItem
            if ($assigneeValue -eq $currentValue) {
                $item.Header = ("Me ({0})" -f $assigneeValue)
            } else {
                $item.Header = $assigneeValue
            }
            $item.Tag = $assigneeValue
            $item.IsCheckable = $true
            $item.IsChecked = ($selectedValue -and ($assigneeValue -eq $selectedValue))
            if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $item -Window $Window | Out-Null }
            $assigneeToApply = $assigneeValue
            try {
                $item.Add_Click([System.Windows.RoutedEventHandler]{
                    param($sender, $args)
                    try {
                        $effectiveAssigneeChangeCmd = $invokeTicketAssigneeChangeCmd
                        if (-not $effectiveAssigneeChangeCmd) {
                            try { $effectiveAssigneeChangeCmd = @(Get-Command Invoke-QOTicketAssigneeChangeForItems -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { $effectiveAssigneeChangeCmd = $null }
                            if ($effectiveAssigneeChangeCmd -is [System.Array]) {
                                if ($effectiveAssigneeChangeCmd.Count -gt 0) { $effectiveAssigneeChangeCmd = $effectiveAssigneeChangeCmd[0] } else { $effectiveAssigneeChangeCmd = $null }
                            }
                        }
                        if (-not $effectiveAssigneeChangeCmd) {
                            try { $effectiveAssigneeChangeCmd = ${function:Invoke-QOTicketAssigneeChangeForItems} } catch { $effectiveAssigneeChangeCmd = $null }
                        }
                        if (-not $effectiveAssigneeChangeCmd) { throw "Assignee change command is unavailable." }
                        $null = & $effectiveAssigneeChangeCmd -Grid $grid -AssigneeValue $assigneeToApply -PreferredItems $capturedItems -GetSelectedTicketsCmd $getSelectedTicketsCmd -SetAssignedToCmd $setAssignedToCmd -UpdateTicketCmd $updateTicketCmd -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
                    } catch {
                        Write-QOTicketsUILog ("Tickets: Quick assignee change failed: " + $_.Exception.Message) "ERROR"
                    }
                }.GetNewClosure())
            } catch { }
            $menu.Items.Add($item) | Out-Null
        }

        $menu.Items.Add($(if ($newTicketsStyledSeparatorCmd) { & $newTicketsStyledSeparatorCmd -Window $Window } else { New-Object System.Windows.Controls.Separator })) | Out-Null
        $customItem = New-Object System.Windows.Controls.MenuItem
        $customItem.Header = "Set assignee..."
        if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $customItem -Window $Window | Out-Null }
        try { $customItem.Add_Click($script:TicketsAssignCustomMenuItemHandler) } catch { }
        $menu.Items.Add($customItem) | Out-Null

        $menu.PlacementTarget = $PlacementTarget
        $menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::MousePoint
        $menu.IsOpen = $true
        return $true
    }.GetNewClosure()

    $openPriorityQuickMenu = {
        param(
            [AllowNull()][System.Windows.UIElement]$PlacementTarget,
            [AllowNull()][object[]]$SelectedItems
        )

        if (-not $PlacementTarget) { return $false }
        $items = @($SelectedItems | Where-Object { $null -ne $_ })
        if ($items.Count -eq 0) { return $false }

        $activePriority = ""
        if ($items.Count -eq 1) {
            try {
                if ($items[0].PSObject.Properties.Name -contains "Priority") {
                    $activePriority = ([string]($items[0].Priority + "")).Trim()
                }
            } catch { $activePriority = "" }
            if ($activePriority -eq "Normal") { $activePriority = "Medium" }
        }

        $menu = New-Object System.Windows.Controls.ContextMenu
        if ($applyTicketsContextMenuThemeCmd) { & $applyTicketsContextMenuThemeCmd -ContextMenu $menu -Window $Window | Out-Null }
        $capturedItems = @($items)
        $openItem = New-Object System.Windows.Controls.MenuItem
        $openItem.Header = "Open ticket"
        $openItem.IsEnabled = ($capturedItems.Count -gt 0)
        if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $openItem -Window $Window | Out-Null }
        try {
            $openItem.Add_Click([System.Windows.RoutedEventHandler]{
                param($sender, $args)
                try {
                    $openCmd = $script:TicketsOpenFromContextCmd
                    if ($openCmd) {
                        $null = & $openCmd -Items $capturedItems -Source "priority quick menu"
                    }
                } catch {
                    Write-QOTicketsUILog ("Tickets: Quick open from priority menu failed: " + $_.Exception.Message) "ERROR"
                }
            }.GetNewClosure())
        } catch { }
        $menu.Items.Add($openItem) | Out-Null
        $menu.Items.Add($(if ($newTicketsStyledSeparatorCmd) { & $newTicketsStyledSeparatorCmd -Window $Window } else { New-Object System.Windows.Controls.Separator })) | Out-Null
        foreach ($priority in @($priorityMenuItems)) {
            $priorityValue = ([string]($priority + "")).Trim()
            if ([string]::IsNullOrWhiteSpace($priorityValue)) { continue }

            $item = New-Object System.Windows.Controls.MenuItem
            $item.Header = $priorityValue
            $item.Tag = $priorityValue
            $item.IsCheckable = $true
            $item.IsChecked = ($activePriority -and ($priorityValue -eq $activePriority))
            if ($applyTicketsMenuItemThemeCmd) { & $applyTicketsMenuItemThemeCmd -MenuItem $item -Window $Window | Out-Null }
            $priorityToApply = $priorityValue
            try {
                $item.Add_Click([System.Windows.RoutedEventHandler]{
                    param($sender, $args)
                    try {
                        $effectivePriorityChangeCmd = $invokeTicketPriorityChangeCmd
                        if (-not $effectivePriorityChangeCmd) {
                            try { $effectivePriorityChangeCmd = @(Get-Command Invoke-QOTicketPriorityChangeForItems -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { $effectivePriorityChangeCmd = $null }
                            if ($effectivePriorityChangeCmd -is [System.Array]) {
                                if ($effectivePriorityChangeCmd.Count -gt 0) { $effectivePriorityChangeCmd = $effectivePriorityChangeCmd[0] } else { $effectivePriorityChangeCmd = $null }
                            }
                        }
                        if (-not $effectivePriorityChangeCmd) {
                            try { $effectivePriorityChangeCmd = ${function:Invoke-QOTicketPriorityChangeForItems} } catch { $effectivePriorityChangeCmd = $null }
                        }
                        if (-not $effectivePriorityChangeCmd) { throw "Priority change command unavailable." }
                        $null = & $effectivePriorityChangeCmd -Grid $grid -PreferredItems $capturedItems -PriorityValue $priorityToApply -GetSelectedTicketsCmd $getSelectedTicketsCmd -SetPriorityCmd $setPriorityCmd -UpdateTicketCmd $updateTicketCmd -GetTicketsCmd $getTicketsCmd -View $script:TicketsCurrentView
                    } catch {
                        Write-QOTicketsUILog ("Tickets: Quick priority change failed: " + $_.Exception.Message) "ERROR"
                    }
                }.GetNewClosure())
            } catch { }
            $menu.Items.Add($item) | Out-Null
        }

        $menu.PlacementTarget = $PlacementTarget
        $menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::MousePoint
        $menu.IsOpen = $true
        return $true
    }.GetNewClosure()

    $resolveMenuItem = {
        param([AllowNull()]$Candidate)

        if ($Candidate -is [System.Windows.Controls.MenuItem]) { return $Candidate }
        if ($Candidate -is [System.Array]) {
            foreach ($entry in @($Candidate)) {
                if ($entry -is [System.Windows.Controls.MenuItem]) { return $entry }
            }
        }
        return $null
    }.GetNewClosure()

    $resolveContextMenu = {
        param([AllowNull()]$Candidate)

        if ($Candidate -is [System.Windows.Controls.ContextMenu]) { return $Candidate }
        if ($Candidate -is [System.Array]) {
            foreach ($entry in @($Candidate)) {
                if ($entry -is [System.Windows.Controls.ContextMenu]) { return $entry }
            }
        }
        return $null
    }.GetNewClosure()

    & $rebuildAssignSubmenu -SelectedAssignee $null

    $resolveParentVisualLocal = {
        param(
            [AllowNull()]$Element,
            [Parameter(Mandatory)][Type]$Type
        )

        $current = $Element
        while ($current) {
            if ($Type.IsInstanceOfType($current)) { return $current }
            try {
                if ($current -is [System.Windows.Media.Visual] -or $current -is [System.Windows.Media.Media3D.Visual3D]) {
                    $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
                } elseif ($current -is [System.Windows.FrameworkContentElement]) {
                    $current = $current.Parent
                    if (-not $current) { $current = [System.Windows.LogicalTreeHelper]::GetParent($current) }
                } else {
                    $current = [System.Windows.LogicalTreeHelper]::GetParent($current)
                }
            } catch {
                $current = $null
            }
        }
        return $null
    }.GetNewClosure()

    # Right click handler must be typed MouseButtonEventHandler.
    # Use right-button-up so selection/hit test are settled before menu actions.
    $script:TicketsStatusContextMenuHandler = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $eventArgsRaw)
        try {
            $eventArgs = $null
            if ($eventArgsRaw -is [System.Windows.Input.MouseButtonEventArgs]) {
                $eventArgs = $eventArgsRaw
            } elseif ($eventArgsRaw -is [System.Array]) {
                foreach ($candidateArg in @($eventArgsRaw)) {
                    if ($candidateArg -is [System.Windows.Input.MouseButtonEventArgs]) { $eventArgs = $candidateArg; break }
                }
            }
            if ($eventArgs -isnot [System.Windows.Input.MouseButtonEventArgs]) { return }

            $hit = $null
            try { $hit = $eventArgs.OriginalSource } catch { $hit = $null }
            if (-not $hit) {
                try {
                    $point = $eventArgs.GetPosition($grid)
                    $hit = $grid.InputHitTest($point)
                } catch { $hit = $null }
            }
            if (-not $hit) { return }
            try { $row = [System.Windows.Controls.ItemsControl]::ContainerFromElement($grid, $hit) } catch { $row = $null }
            if ($row -and $row -isnot [System.Windows.Controls.DataGridRow]) {
                $row = & $resolveParentVisualLocal -Element $row -Type ([System.Windows.Controls.DataGridRow])
            }
            if (-not $row) {
                $row = & $resolveParentVisualLocal -Element $hit -Type ([System.Windows.Controls.DataGridRow])
            }
            if (-not $row -or -not $row.Item) { return }

            $cell = & $resolveParentVisualLocal -Element $hit -Type ([System.Windows.Controls.DataGridCell])
            $placementTarget = if ($cell) { $cell } else { $row }

            $clickedTextBlock = & $resolveParentVisualLocal -Element $hit -Type ([System.Windows.Controls.TextBlock])
            $clickedTitleText = $false
            $clickedStatusText = $false
            $clickedAssigneeText = $false
            $clickedPriorityIcon = $false
            $clickedTextValue = ""
            if ($clickedTextBlock) {
                $tagValue = ""
                try { $tagValue = ([string]($clickedTextBlock.Tag + "")).Trim() } catch { $tagValue = "" }
                if ($tagValue -eq "TicketTitleText") { $clickedTitleText = $true }
                if ($tagValue -eq "TicketStatusText") { $clickedStatusText = $true }
                if ($tagValue -eq "TicketAssigneeText") { $clickedAssigneeText = $true }
                if ($tagValue -eq "TicketPriorityIcon") { $clickedPriorityIcon = $true }
                try { $clickedTextValue = ([string]($clickedTextBlock.Text + "")).Trim() } catch { $clickedTextValue = "" }
            }

            $selectedItemsBefore = @()
            try { $selectedItemsBefore = @($grid.SelectedItems | Where-Object { $null -ne $_ }) } catch { $selectedItemsBefore = @() }
            $keepExistingSelection = ($selectedItemsBefore.Count -gt 1) -and ($selectedItemsBefore -contains $row.Item)

            if (-not $keepExistingSelection) {
                try { $grid.SelectedItems.Clear() } catch { }
                try { $row.IsSelected = $true } catch { }
                try { $grid.SelectedItem = $row.Item } catch { }
            }

            $selectedItems = @()
            try { $selectedItems = @($grid.SelectedItems | Where-Object { $null -ne $_ }) } catch { $selectedItems = @() }
            if ($selectedItems.Count -eq 0) {
                try { if ($grid.SelectedItem) { $selectedItems = @($grid.SelectedItem) } } catch { $selectedItems = @() }
            }
            if ($selectedItems.Count -eq 0) { $selectedItems = @($row.Item) }
            $script:TicketsContextMenuSelection = @($selectedItems)

            if (-not $clickedStatusText -and -not $clickedAssigneeText -and $clickedTextValue) {
                if ($clickedTextValue.StartsWith("@")) { $clickedAssigneeText = $true }
                if ($statusMenuItems -contains $clickedTextValue) { $clickedStatusText = $true }
            }

            if ($clickedTitleText) {
                $renameTarget = $null
                try { $renameTarget = $row.Item } catch { $renameTarget = $null }
                if (-not $renameTarget -and $selectedItems.Count -gt 0) {
                    try { $renameTarget = $selectedItems[0] } catch { $renameTarget = $null }
                }

                if ($renameTarget) {
                    try { $grid.SelectedItems.Clear() } catch { }
                    try { $grid.SelectedItem = $renameTarget } catch { }
                    try { if ($row) { $row.IsSelected = $true } } catch { }
                    $script:TicketsContextMenuSelection = @($renameTarget)

                    $renameSucceeded = $false
                    try { $renameSucceeded = [bool](& $startInlineRenameTicket -Ticket $renameTarget) } catch { $renameSucceeded = $false }
                    if ($renameSucceeded) { $eventArgs.Handled = $true; return }
                }
            }

            if ($clickedPriorityIcon -and ($selectedItems.Count -gt 0)) {
                if (& $openPriorityQuickMenu -PlacementTarget $placementTarget -SelectedItems $selectedItems) {
                    $eventArgs.Handled = $true
                    return
                }
            }

            $selectedAssignee = ""
            if ($selectedItems.Count -eq 1) {
                try {
                    if ($selectedItems[0].PSObject.Properties.Name -contains "AssignedTo") {
                        $selectedAssignee = ([string]($selectedItems[0].AssignedTo + "")).Trim()
                    }
                } catch { $selectedAssignee = "" }
            }

            $menuUndelete = & $resolveMenuItem $script:TicketsUndeleteMenuItem
            $menuOpen = & $resolveMenuItem $script:TicketsOpenMenuItem
            $menuClose = & $resolveMenuItem $script:TicketsCloseMenuItem
            $menuClaim = & $resolveMenuItem $script:TicketsClaimMenuItem
            $menuAddNote = & $resolveMenuItem $script:TicketsAddNoteMenuItem
            $menuRename = & $resolveMenuItem $script:TicketsRenameMenuItem
            $menuSetStatus = & $resolveMenuItem $script:TicketsSetStatusMenuItem
            $menuSetPriority = & $resolveMenuItem $script:TicketsSetPriorityMenuItem
            $menuSetAssigned = & $resolveMenuItem $script:TicketsSetAssignedToMenuItem
            $rowContextMenu = & $resolveContextMenu $script:TicketsRowContextMenu

            if ($menuUndelete) { $menuUndelete.IsEnabled = $false }
            if ($menuOpen) { $menuOpen.IsEnabled = ($selectedItems.Count -gt 0) }
            if ($menuClose) { $menuClose.IsEnabled = ($selectedItems.Count -gt 0) }
            if ($menuClaim) { $menuClaim.IsEnabled = ($selectedItems.Count -gt 0) }
            if ($menuAddNote) { $menuAddNote.IsEnabled = ($selectedItems.Count -gt 0) }
            if ($menuRename) { $menuRename.IsEnabled = ($selectedItems.Count -eq 1) }
            if ($menuSetStatus) { $menuSetStatus.IsEnabled = ($selectedItems.Count -gt 0) }
            if ($menuSetPriority) { $menuSetPriority.IsEnabled = ($selectedItems.Count -gt 0) }
            if ($menuSetAssigned) { $menuSetAssigned.IsEnabled = ($selectedItems.Count -gt 0) }

            & $rebuildAssignSubmenu -SelectedAssignee $selectedAssignee
            & $updateStatusMenuState -SelectedItems $selectedItems

            if ($clickedStatusText -and ($selectedItems.Count -gt 0)) {
                if (& $openStatusQuickMenu -PlacementTarget $placementTarget -SelectedItems $selectedItems) {
                    $eventArgs.Handled = $true
                    return
                }
            }

            if ($clickedAssigneeText -and ($selectedItems.Count -gt 0)) {
                if (& $openAssigneeQuickMenu -PlacementTarget $placementTarget -SelectedAssignee $selectedAssignee) {
                    $eventArgs.Handled = $true
                    return
                }
            }

            if ($rowContextMenu) {
                $rowContextMenu.PlacementTarget = $placementTarget
                $rowContextMenu.IsOpen = $true
                $eventArgs.Handled = $true
            }
        } catch {
            try { Write-QOTicketsUILog ("Tickets: Right-click status/assignee menu failed: " + $_.Exception.Message) "ERROR" } catch { }
        }
    }.GetNewClosure()

    $grid.AddHandler([System.Windows.UIElement]::PreviewMouseRightButtonUpEvent, $script:TicketsStatusContextMenuHandler, $true)

    # Shared force-back routine used by both click and preview fallback handlers.
    $invokeBackToList = {
        param([AllowNull()][string]$Source)
        try {
            if ([string]::IsNullOrWhiteSpace([string]$Source)) { $Source = "unknown" }
            try { Write-QOTicketsUILog ("Tickets: Back button clicked. Source='{0}' ActiveTicketId='{1}'." -f $Source, ([string]($script:TicketsActiveTicketId + "")).Trim()) } catch { }
            try { $script:TicketsDetailsViewClosing = $true } catch { }
            try { Stop-QOTicketQueuedDetailsRefresh -Reason ("back-" + $Source) } catch { }

            $currentTicket = $null
            try { $currentTicket = $grid.SelectedItem } catch { $currentTicket = $null }
            if (-not $currentTicket) {
                try { $currentTicket = $grid.CurrentItem } catch { $currentTicket = $null }
            }

            $currentKey = ""
            try { $currentKey = [string](& $getTicketSelectionKeySafe $currentTicket) } catch { $currentKey = "" }
            if (-not [string]::IsNullOrWhiteSpace($currentKey)) {
                $script:TicketsLastDetailsTicketKey = $currentKey
            }

            # Collapse details and keep a force-close lock so automatic reselection
            # (from refresh/filter operations) cannot immediately reopen the panel.
            $script:TicketsDetailsForceClosed = $true
            try {
                try { & $invokeDetailsUpdate $null } catch { }
            } catch {
                try {
                    if ($setTicketDetailsVisibilityCmd) {
                        & $setTicketDetailsVisibilityCmd -DetailsPanel $detailsPanel -Chevron $detailsChevron -TicketsGrid $grid -IsOpen:$false
                    } else {
                        Set-QOTicketDetailsVisibility -DetailsPanel $detailsPanel -Chevron $detailsChevron -TicketsGrid $grid -IsOpen:$false
                    }
                } catch { }
            }

            try { $grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null } catch { }
            try { $grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null } catch { }
            try { $grid.Focus() | Out-Null } catch { }
            try { $grid.UpdateLayout() | Out-Null } catch { }

            try {
                if ($invokeTicketsFilterLocal) {
                    $null = & $invokeTicketsFilterLocal -ForceRefresh -Grid $grid
                }
            } catch { }
            try {
                if ($setTicketDetailsVisibilityCmd) {
                    & $setTicketDetailsVisibilityCmd -DetailsPanel $detailsPanel -Chevron $detailsChevron -TicketsGrid $grid -IsOpen:$false
                } else {
                    Set-QOTicketDetailsVisibility -DetailsPanel $detailsPanel -Chevron $detailsChevron -TicketsGrid $grid -IsOpen:$false
                }
            } catch { }

            try {
                if ($script:TicketsListViewStateBeforeDetails) {
                    $null = Restore-QOTicketsListViewState -Grid $grid -State $script:TicketsListViewStateBeforeDetails
                }
            } catch { }
            $script:TicketsListViewStateBeforeDetails = $null

            try { Write-QOTicketsUILog ("Tickets: Back to list invoked via {0}; details panel collapsed." -f $Source) "INFO" } catch { }
            return $true
        } catch {
            try { Write-QOTicketsUILog ("Tickets: Back to list failed via {0}: {1}" -f $Source, $_.Exception.Message) "ERROR" } catch { }
            try { Write-QOTicketsUILog ("Tickets: Back to list stack via {0}: {1}" -f $Source, $_.ScriptStackTrace) "ERROR" } catch { }
            return $false
        }
    }.GetNewClosure()

    # Back-to-list click handler typed
    $script:TicketsToggleDetailsHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $collapsed = $false
            try { $collapsed = [bool]$invokeBackToList.Invoke("click") } catch { $collapsed = $false }
            if ($collapsed -and $args) { $args.Handled = $true }
        } catch { }
    }.GetNewClosure()
    $btnToggleDetails.Add_Click($script:TicketsToggleDetailsHandler)

    # Routed-event fallback for hosts where Click does not fire reliably.
    $script:TicketsToggleDetailsPreviewHandler = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $args)
        try {
            $collapsed = $false
            try { $collapsed = [bool]$invokeBackToList.Invoke("preview-mouse-up") } catch { $collapsed = $false }
            if ($collapsed -and $args) { $args.Handled = $true }
        } catch { }
    }.GetNewClosure()
    $btnToggleDetails.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent, $script:TicketsToggleDetailsPreviewHandler, $true)
    & $applyFilterSelection $false
    
    # Selection changed handler typed
    # Keep selection tracking lightweight. Details open is driven by double-click.
    $script:TicketsSelectionChangedHandler = [System.Windows.Controls.SelectionChangedEventHandler]{
        param($sender, $args)
        try {
            $selectedTicket = $null
            try {
                if ($args -and $args.AddedItems -and @($args.AddedItems).Count -gt 0) {
                    $selectedTicket = @($args.AddedItems | Where-Object { $null -ne $_ }) | Select-Object -First 1
                }
            } catch { $selectedTicket = $null }
            if (-not $selectedTicket) {
                try { $selectedTicket = $grid.SelectedItem } catch { $selectedTicket = $null }
            }
            if (-not $selectedTicket) {
                try { $selectedTicket = $grid.CurrentItem } catch { $selectedTicket = $null }
            }

            if (-not $selectedTicket) {
                $detailsIsOpen = $false
                try { $detailsIsOpen = ($detailsPanel.Visibility -eq "Visible") } catch { $detailsIsOpen = $false }
                if (-not $detailsIsOpen) {
                    try { & $invokeDetailsUpdate $null } catch { }
                    $script:TicketsLastDetailsTicketKey = ""
                }
                return
            }

            $selectedKey = ""
            try { $selectedKey = [string](& $getTicketSelectionKeySafe $selectedTicket) } catch { $selectedKey = "" }
            if (-not [string]::IsNullOrWhiteSpace($selectedKey)) {
                $script:TicketsLastDetailsTicketKey = $selectedKey
            }

            # If details are already open, keep panel in sync when changing rows.
            $detailsIsOpen = $false
            try { $detailsIsOpen = ($detailsPanel.Visibility -eq "Visible") } catch { $detailsIsOpen = $false }
            if ($detailsIsOpen -and (-not $script:TicketsDetailsForceClosed)) {
                $selectedTicketId = ""
                $activeTicketId = ""
                try { $selectedTicketId = Get-QOTicketIdValue -Ticket $selectedTicket } catch { $selectedTicketId = "" }
                try { $activeTicketId = ([string]($script:TicketsActiveTicketId + "")).Trim() } catch { $activeTicketId = "" }
                if ((-not [string]::IsNullOrWhiteSpace($selectedTicketId)) -and [string]::Equals($selectedTicketId, $activeTicketId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    try { Write-QOTicketsUILog ("Tickets: Selection refresh ignored because active detail ticket is already current. TicketId='{0}'." -f $selectedTicketId) } catch { }
                    return
                }
                try {
                    $selectedBodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $selectedTicket
                    Write-QOTicketsUILog ("Tickets: Ticket selected for details. TicketId={0}; Subject={1}; Source={2}; Property={3}; Length={4}" -f `
                        (& $getTicketSelectionKeySafe $selectedTicket), `
                        ([string]($selectedTicket.Subject + "")), `
                        $selectedBodyInfo.Source, `
                        $selectedBodyInfo.Property, `
                        $selectedBodyInfo.Length)
                } catch { }
                try { & $invokeDetailsUpdate $selectedTicket } catch { }
                $currentReader = ""
                try { $currentReader = [string](& $getCurrentAssigneeCmd) } catch { $currentReader = "" }
                try { $null = & $updateReadTrackingCmd -Ticket $selectedTicket -UpdateTicketCmd $updateTicketCmd -ReaderName $currentReader } catch { }
            }
        } catch { }
    }.GetNewClosure()
    $grid.AddHandler([System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent, $script:TicketsSelectionChangedHandler)
    try { $grid.Add_SelectionChanged($script:TicketsSelectionChangedHandler) } catch { }

    # Normalize routed mouse event args because PowerShell may pass an object[] wrapper.
    $resolveMouseArgs = {
        param(
            [AllowNull()]$Primary,
            [AllowNull()]$Secondary
        )

        $extractMouseArgs = {
            param([AllowNull()]$Value)
            if ($Value -is [System.Windows.Input.MouseButtonEventArgs]) {
                return $Value
            }
            if ($Value -is [System.Array]) {
                foreach ($candidateArg in @($Value)) {
                    if ($candidateArg -is [System.Windows.Input.MouseButtonEventArgs]) {
                        return $candidateArg
                    }
                }
            }
            return $null
        }.GetNewClosure()

        $resolved = $null
        try { $resolved = & $extractMouseArgs -Value $Primary } catch { $resolved = $null }
        if ($resolved) { return $resolved }
        try { $resolved = & $extractMouseArgs -Value $Secondary } catch { $resolved = $null }
        if ($resolved) { return $resolved }
        return $null
    }.GetNewClosure()

    $resolveTicketFromGridHitCmd = Get-Command Resolve-QOTicketFromGridHit -CommandType Function -ErrorAction Stop
    $testRenderableTicketCmd = Get-Command Test-QOTicketsRenderableListItem -CommandType Function -ErrorAction Stop
    $testScrollBarGutterPointCmd = Get-Command Test-QOTicketsScrollBarGutterPoint -CommandType Function -ErrorAction Stop
    $testScrollChromeElementCmd = Get-Command Test-QOTicketsScrollChromeElement -CommandType Function -ErrorAction Stop
    $writeTicketsLogCmd = Get-Command Write-QOTicketsUILog -CommandType Function -ErrorAction Stop
    $saveTicketsListViewStateCmd = Get-Command Save-QOTicketsListViewState -CommandType Function -ErrorAction Stop
    $showTicketsOpenPulseCmd = Get-Command Show-QOTicketsOpenPulse -CommandType Function -ErrorAction Stop

    $resolveTicketFromHit = {
        param(
            [AllowNull()]$Hit,
            [switch]$RequireRowHit
        )

        try { return (& $resolveTicketFromGridHitCmd -Grid $grid -Hit $Hit -RequireRowHit:$RequireRowHit) } catch { }
        return $null
    }.GetNewClosure()

    # Resolve ticket directly from current mouse position over the grid.
    # This is a fallback when routed event args are wrapped/unavailable.
    $resolveTicketFromMousePosition = {
        param([switch]$RequireRowHit)

        try {
            $point = $null
            $hit = $null
            try {
                $point = [System.Windows.Input.Mouse]::GetPosition($grid)
            } catch { $point = $null }
            try {
                if ($point -and (& $testScrollBarGutterPointCmd -Grid $grid -Point $point)) {
                    return $null
                }
            } catch { }
            try {
                $hit = $grid.InputHitTest($point)
            } catch { $hit = $null }

            if ($hit) {
                $resolvedTicket = $null
                try { $resolvedTicket = & $resolveTicketFromHit -Hit $hit -RequireRowHit:$RequireRowHit } catch { $resolvedTicket = $null }
                if ($resolvedTicket) { return $resolvedTicket }
            }
        } catch { }

        if ($RequireRowHit) { return $null }

        try { if ($grid.SelectedItem) { return $grid.SelectedItem } } catch { }
        try { if ($grid.CurrentItem) { return $grid.CurrentItem } } catch { }
        return $null
    }.GetNewClosure()

    $testTicketIsVisibleInGrid = {
        param([AllowNull()]$Ticket)

        if (-not (& $testRenderableTicketCmd -Ticket $Ticket)) { return $false }

        $ticketKey = ""
        try { $ticketKey = [string](& $getTicketSelectionKeySafe $Ticket) } catch { $ticketKey = "" }

        try {
            foreach ($item in @($grid.ItemsSource)) {
                if (-not (& $testRenderableTicketCmd -Ticket $item)) { continue }
                if ([object]::ReferenceEquals($item, $Ticket)) { return $true }
                if ($item -eq $Ticket) { return $true }
                if (-not [string]::IsNullOrWhiteSpace($ticketKey)) {
                    $itemKey = ""
                    try { $itemKey = [string](& $getTicketSelectionKeySafe $item) } catch { $itemKey = "" }
                    if ($itemKey -eq $ticketKey) { return $true }
                }
            }
        } catch { }

        return $false
    }.GetNewClosure()

    # Double-click a ticket row to open details + reply section in the details panel.
    $openTicketDetailsCore = {
        param(
            [AllowNull()]$Ticket,
            [AllowNull()][string]$Source = "unknown"
        )

        try {
            if (-not $Ticket) { return $false }
            if (-not (& $testRenderableTicketCmd -Ticket $Ticket)) {
                try { & $writeTicketsLogCmd ("Tickets: Ignoring open request from {0}; target was not a ticket item." -f $Source) "INFO" } catch { }
                return $false
            }
            if (-not (& $testTicketIsVisibleInGrid -Ticket $Ticket)) {
                try { & $writeTicketsLogCmd ("Tickets: Ignoring open request from {0}; ticket is not listed in the current grid view." -f $Source) "INFO" } catch { }
                return $false
            }

            $detailsAlreadyOpen = $false
            try { $detailsAlreadyOpen = ($detailsPanel.Visibility -eq "Visible") } catch { $detailsAlreadyOpen = $false }
            if (-not $detailsAlreadyOpen) {
                try {
                    $script:TicketsListViewStateBeforeDetails = & $saveTicketsListViewStateCmd -Grid $grid -AnchorTicket $Ticket
                } catch {
                    $script:TicketsListViewStateBeforeDetails = $null
                }
            }

            try { $grid.SelectedItem = $Ticket } catch { }
            try { $grid.CurrentItem = $Ticket } catch { }
            try { $grid.ScrollIntoView($Ticket) } catch { }
            try {
                $openBodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $Ticket
                & $writeTicketsLogCmd ("Tickets: Opening details. Source={0}; {1}; BodySource={2}; BodyProperty={3}; BodyLength={4}" -f `
                    $Source, `
                    (& $getTicketLogLabelSafe $Ticket), `
                    $openBodyInfo.Source, `
                    $openBodyInfo.Property, `
                    $openBodyInfo.Length) "INFO"
            } catch { }

            try {
                $grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
                $grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
            } catch { }

            $detailsOpened = $false
            try { & $invokeDetailsUpdate $Ticket } catch {
                try { & $writeTicketsLogCmd ("Tickets: Primary details render failed ({0}): {1}" -f $Source, $_.Exception.Message) "WARN" } catch { }
            }
            try {
                if ($detailsPanel) {
                    $detailsOpened = ($detailsPanel.Visibility -eq "Visible")
                }
            } catch { $detailsOpened = $false }

            if (-not $detailsOpened) {
                try {
                    if ($updateTicketDetailsViewCmd) {
                        & $updateTicketDetailsViewCmd -Ticket $Ticket -DetailsPanel $detailsPanel -BodyText $ticketBodyText -ReplySubject $ticketReplySubject -ReplyText $ticketReplyText -ReplyButton $btnSendReply -Chevron $detailsChevron
                    } else {
                        & $invokeDetailsUpdate $Ticket
                    }
                } catch {
                    try { & $writeTicketsLogCmd ("Tickets: Fallback details render failed ({0}): {1}" -f $Source, $_.Exception.Message) "WARN" } catch { }
                }
                try {
                    if ($detailsPanel) {
                        $detailsOpened = ($detailsPanel.Visibility -eq "Visible")
                    }
                } catch { $detailsOpened = $false }
            }
            if (-not $detailsOpened) {
                try { & $writeTicketsLogCmd ("Tickets: Open ticket failed ({0}) - details panel did not become visible." -f $Source) "ERROR" } catch { }
                return $false
            }

            $openedKey = ""
            try { $openedKey = [string](& $getTicketSelectionKeySafe $Ticket) } catch { $openedKey = "" }
            if (-not [string]::IsNullOrWhiteSpace($openedKey)) {
                $script:TicketsLastDetailsTicketKey = $openedKey
            }
            $script:TicketsDetailsForceClosed = $false

            try {
                $openSubject = ""
                if ($Ticket -and $Ticket.PSObject.Properties.Name -contains "Subject") {
                    $openSubject = ([string]($Ticket.Subject + "")).Trim()
                }
                if ([string]::IsNullOrWhiteSpace($openSubject) -and $Ticket -and $Ticket.PSObject.Properties.Name -contains "Title") {
                    $openSubject = ([string]($Ticket.Title + "")).Trim()
                }
                if ($openSubject.Length -gt 70) { $openSubject = $openSubject.Substring(0, 70) + "..." }
                if ([string]::IsNullOrWhiteSpace($openSubject)) { $openSubject = "ticket" }
                & $showTicketsOpenPulseCmd -StatusText $syncStatusText -Message ("Opened: {0}" -f $openSubject) -DurationMilliseconds 2200
            } catch { }

            try {
                if ($btnSendReply -and $btnSendReply.IsEnabled -and $ticketReplyText) {
                    $null = $ticketReplyText.Focus()
                }
            } catch { }

            return $true
        } catch {
            try { & $writeTicketsLogCmd ("Tickets: Core open failed ({0}): {1}" -f $Source, $_.Exception.Message) "WARN" } catch { }
            return $false
        }
    }.GetNewClosure()

    $openTicketDetailsFromDoubleClick = {
        param(
            [AllowNull()]$ArgsRaw,
            [AllowNull()]$CandidateTicket
        )

        if ($script:TicketsOpenDetailsInProgress) { return $false }
        $script:TicketsOpenDetailsInProgress = $true
        try {
            $ticket = $CandidateTicket
            $eventArgs = $null
            try { $eventArgs = & $resolveMouseArgs -Primary $ArgsRaw -Secondary $null } catch { $eventArgs = $null }

            if (-not $ticket -and $eventArgs) {
                $hit = $null
                try { $hit = $eventArgs.OriginalSource } catch { $hit = $null }
                if (-not $hit) {
                    try {
                        $point = $eventArgs.GetPosition($grid)
                        $hit = $grid.InputHitTest($point)
                    } catch { $hit = $null }
                }
                if ($hit) {
                    try { $ticket = & $resolveTicketFromHit -Hit $hit -RequireRowHit } catch { $ticket = $null }
                }
            }

            if ($eventArgs -and -not $ticket) {
                try { $script:TicketsLastPointerDownTicket = $null } catch { }
                try { $script:TicketsLastLeftClickTicketKey = "" } catch { }
                try { & $writeTicketsLogCmd "Tickets: Ignoring double-click because the pointer was not over a ticket row." "INFO" } catch { }
                return $false
            }

            if (-not $ticket) {
                try { if ($grid.CurrentCell -and $grid.CurrentCell.Item) { $ticket = $grid.CurrentCell.Item } } catch { $ticket = $null }
            }
            if (-not $ticket) {
                try { $ticket = $grid.SelectedItem } catch { $ticket = $null }
            }
            if (-not $ticket) {
                try { $ticket = $grid.CurrentItem } catch { $ticket = $null }
            }
            if (-not $ticket) {
                try {
                    if ($grid.SelectedItems -and $grid.SelectedItems.Count -gt 0) {
                        $ticket = $grid.SelectedItems[0]
                    }
                } catch { $ticket = $null }
            }
            if (-not $ticket) {
                try { $ticket = & $resolveTicketFromMousePosition } catch { $ticket = $null }
            }
            if (-not $ticket) { return $false }

            return [bool](& $openTicketDetailsCore -Ticket $ticket -Source "double click")
        } catch {
            try { & $writeTicketsLogCmd ("Tickets: Open details failed: " + $_.Exception.Message) "WARN" } catch { }
            return $false
        } finally {
            $script:TicketsOpenDetailsInProgress = $false
        }
    }.GetNewClosure()

    $openTicketDetailsFromContext = {
        param(
            [AllowNull()][object[]]$Items,
            [AllowNull()][string]$Source = "context menu"
        )
        try {
            $ticketToOpen = $null
            foreach ($entry in @($Items)) {
                if ($null -ne $entry) { $ticketToOpen = $entry; break }
            }
            if (-not $ticketToOpen) {
                try {
                    if ($script:TicketsContextMenuSelection) {
                        foreach ($entry in @($script:TicketsContextMenuSelection)) {
                            if ($null -ne $entry) { $ticketToOpen = $entry; break }
                        }
                    }
                } catch { $ticketToOpen = $null }
            }
            if (-not $ticketToOpen) {
                try { $ticketToOpen = $grid.SelectedItem } catch { $ticketToOpen = $null }
            }
            if (-not $ticketToOpen) {
                try { $ticketToOpen = $grid.CurrentItem } catch { $ticketToOpen = $null }
            }
            if (-not $ticketToOpen) {
                try {
                    $selectedItems = @(& $getSelectedTicketsCmd -Grid $grid -AllowContextFallback)
                    if ($selectedItems.Count -gt 0) { $ticketToOpen = $selectedItems[0] }
                } catch { $ticketToOpen = $null }
            }
            if (-not $ticketToOpen) {
                try { $ticketToOpen = & $resolveTicketFromMousePosition } catch { $ticketToOpen = $null }
            }

            $opened = $false
            try { $opened = [bool](& $openTicketDetailsCore -Ticket $ticketToOpen -Source $Source) } catch { $opened = $false }
            if ($opened) {
                try { & $writeTicketsLogCmd ("Tickets: Opened ticket from {0}." -f $Source) "INFO" } catch { }
            } else {
                try { & $writeTicketsLogCmd ("Tickets: Open ticket request from {0} did not resolve a ticket." -f $Source) "WARN" } catch { }
            }
            return $opened
        } catch {
            try { & $writeTicketsLogCmd ("Tickets: Open ticket from {0} failed: {1}" -f $Source, $_.Exception.Message) "ERROR" } catch { }
            return $false
        }
    }.GetNewClosure()
    $script:TicketsOpenFromContextCmd = $openTicketDetailsFromContext

    $script:TicketsOpenMenuItemHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $opened = $false
            $preferred = @()
            try { $preferred = @(& $getSelectedTicketsCmd -Grid $grid -AllowContextFallback) } catch { $preferred = @() }
            try { $opened = [bool](& $openTicketDetailsFromContext -Items $preferred -Source "row context menu") } catch { $opened = $false }
            if ($opened) {
                if ($args) { $args.Handled = $true }
            }
        } catch {
            try { & $writeTicketsLogCmd ("Tickets: Open ticket menu action failed: " + $_.Exception.Message) "ERROR" } catch { }
        }
    }.GetNewClosure()
    try {
        if ($script:TicketsOpenMenuItem -and $script:TicketsOpenMenuItemHandler) {
            $script:TicketsOpenMenuItem.Add_Click($script:TicketsOpenMenuItemHandler)
        }
    } catch { }

    $script:TicketsRowDoubleClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $args)
        try {
            $eventArgs = $null
            try { $eventArgs = & $resolveMouseArgs -Primary $args -Secondary $null } catch { $eventArgs = $null }
            if ($eventArgs) {
                if ($eventArgs.ChangedButton -ne [System.Windows.Input.MouseButton]::Left) { return }
                if ($eventArgs.ClickCount -lt 2) { return }
                try {
                    $origin = $null
                    $point = $null
                    try { $point = $eventArgs.GetPosition($grid) } catch { $point = $null }
                    if ($point -and (& $testScrollBarGutterPointCmd -Grid $grid -Point $point)) {
                        try { $script:TicketsLastPointerDownTicket = $null } catch { }
                        try { & $writeTicketsLogCmd "Tickets: Ignoring grid double-click from tickets scrollbar gutter." "INFO" } catch { }
                        return
                    }
                    try { $origin = $eventArgs.OriginalSource } catch { $origin = $null }
                    if (-not $origin) {
                        try {
                            $origin = $grid.InputHitTest($point)
                        } catch { $origin = $null }
                    }
                    if ($origin -and (& $testScrollChromeElementCmd -Element $origin)) {
                        try { $script:TicketsLastPointerDownTicket = $null } catch { }
                        try { & $writeTicketsLogCmd "Tickets: Ignoring grid double-click from scrollbar chrome." "INFO" } catch { }
                        return
                    }
                } catch { }
            }
            try { & $writeTicketsLogCmd "Tickets: Double-click event received on grid." "INFO" } catch { }

            $opened = $false
            try { $opened = [bool]$openTicketDetailsFromDoubleClick.Invoke($eventArgs, $null) } catch { $opened = $false }
            if (-not $opened) {
                try { & $writeTicketsLogCmd "Tickets: Double-click detected but ticket details could not be opened." "WARN" } catch { }
            }
            else {
                try {
                    $openedTicket = $null
                    try { $openedTicket = $grid.SelectedItem } catch { $openedTicket = $null }
                    $openedLabel = [string](& $getTicketLogLabelSafe $openedTicket)
                    & $writeTicketsLogCmd ("Tickets: Double-click opened details. {0}" -f $openedLabel) "INFO"
                } catch { }
            }
            if ($opened -and $eventArgs) { $eventArgs.Handled = $true }
        } catch {
            try { & $writeTicketsLogCmd ("Tickets double-click handler failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }.GetNewClosure()
    # Use routed events with handledEventsToo=true so double-click still works from editable cells.
    $grid.AddHandler([System.Windows.Controls.Control]::MouseDoubleClickEvent, $script:TicketsRowDoubleClickHandler, $true)
    $script:TicketsRowPreviewDoubleClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $args)
        try {
            $eventArgs = $null
            try { $eventArgs = & $resolveMouseArgs -Primary $args -Secondary $null } catch { $eventArgs = $null }
            if (-not $eventArgs) { return }
            if ($eventArgs.ChangedButton -ne [System.Windows.Input.MouseButton]::Left) { return }
            if ($eventArgs.ClickCount -lt 2) { return }

            $previewTicket = $null
            try {
                $hit = $null
                $point = $null
                try { $point = $eventArgs.GetPosition($grid) } catch { $point = $null }
                if ($point -and (& $testScrollBarGutterPointCmd -Grid $grid -Point $point)) {
                    try { $script:TicketsLastPointerDownTicket = $null } catch { }
                    return
                }
                try { $hit = $eventArgs.OriginalSource } catch { $hit = $null }
                if (-not $hit) {
                    try {
                        $hit = $grid.InputHitTest($point)
                    } catch { $hit = $null }
                }
                if ($hit) {
                    if (& $testScrollChromeElementCmd -Element $hit) {
                        try { $script:TicketsLastPointerDownTicket = $null } catch { }
                        return
                    }
                    try { $previewTicket = & $resolveTicketFromHit -Hit $hit -RequireRowHit } catch { $previewTicket = $null }
                }
            } catch { $previewTicket = $null }

            if (-not $previewTicket) {
                try {
                    $elapsedMs = ((Get-Date).ToUniversalTime() - $script:TicketsLastLeftClickUtc).TotalMilliseconds
                    if ($script:TicketsLastPointerDownTicket -and ($elapsedMs -ge 0) -and ($elapsedMs -le 1000)) {
                        $previewTicket = $script:TicketsLastPointerDownTicket
                    }
                } catch { $previewTicket = $null }
            }

            if (-not $previewTicket) { return }

            $opened = $false
            try { $opened = [bool]$openTicketDetailsFromDoubleClick.Invoke($eventArgs, $previewTicket) } catch { $opened = $false }
            if ($opened) {
                try { & $writeTicketsLogCmd "Tickets: Preview double-click opened ticket details." "INFO" } catch { }
                $eventArgs.Handled = $true
            }
        } catch {
            try { & $writeTicketsLogCmd ("Tickets: Preview double-click handler failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }.GetNewClosure()
    $grid.AddHandler([System.Windows.Controls.Control]::PreviewMouseDoubleClickEvent, $script:TicketsRowPreviewDoubleClickHandler, $true)
    # Fallback for environments where MouseDoubleClick does not bubble reliably from row templates.
    $script:TicketsRowPreviewMouseDownHandler = [System.Windows.Input.MouseButtonEventHandler]{
        param($sender, $args)
        try {
            $eventArgs = $null
            try { $eventArgs = & $resolveMouseArgs -Primary $args -Secondary $null } catch { $eventArgs = $null }
            if (-not $eventArgs) { return }
            if ($eventArgs.ChangedButton -ne [System.Windows.Input.MouseButton]::Left) { return }

            try {
                $origin = $null
                $point = $null
                try { $point = $eventArgs.GetPosition($grid) } catch { $point = $null }
                if ($point -and (& $testScrollBarGutterPointCmd -Grid $grid -Point $point)) {
                    $script:TicketsLastPointerDownTicket = $null
                    $script:TicketsLastLeftClickTicketKey = ""
                    if ($eventArgs.ClickCount -ge 2) {
                        try { & $writeTicketsLogCmd "Tickets: Ignoring preview mouse double-click from tickets scrollbar gutter." "INFO" } catch { }
                    }
                    return
                }
                try { $origin = $eventArgs.OriginalSource } catch { $origin = $null }
                if (-not $origin) {
                    try {
                        $origin = $grid.InputHitTest($point)
                    } catch { $origin = $null }
                }
                if ($origin -and (& $testScrollChromeElementCmd -Element $origin)) {
                    $script:TicketsLastPointerDownTicket = $null
                    $script:TicketsLastLeftClickTicketKey = ""
                    if ($eventArgs.ClickCount -ge 2) {
                        try { & $writeTicketsLogCmd "Tickets: Ignoring preview mouse double-click from scrollbar chrome." "INFO" } catch { }
                    }
                    return
                }
            } catch { }

            $fallbackTicket = $null
            $fallbackTicketKey = ""
            try {
                $fallbackTicket = & $resolveTicketFromMousePosition -RequireRowHit
                if ($fallbackTicket) {
                    $fallbackTicketKey = [string](& $getTicketSelectionKeySafe $fallbackTicket)
                }
            } catch {
                $fallbackTicket = $null
                $fallbackTicketKey = ""
            }

            try {
                if ($fallbackTicket) {
                    $script:TicketsLastPointerDownTicket = $fallbackTicket
                } else {
                    $script:TicketsLastPointerDownTicket = $null
                }
            } catch {
                $script:TicketsLastPointerDownTicket = $null
            }

            $shouldTreatAsDoubleClick = ($eventArgs.ClickCount -ge 2)
            if (-not $shouldTreatAsDoubleClick -and $fallbackTicket -and -not [string]::IsNullOrWhiteSpace($fallbackTicketKey)) {
                $nowUtc = (Get-Date).ToUniversalTime()
                $elapsedMs = [double]::PositiveInfinity
                try { $elapsedMs = ($nowUtc - $script:TicketsLastLeftClickUtc).TotalMilliseconds } catch { $elapsedMs = [double]::PositiveInfinity }
                if (($script:TicketsLastLeftClickTicketKey -eq $fallbackTicketKey) -and ($elapsedMs -ge 0) -and ($elapsedMs -le 650)) {
                    $shouldTreatAsDoubleClick = $true
                    try { & $writeTicketsLogCmd ("Tickets: Synthetic double-click fallback engaged ({0} ms)." -f [math]::Round($elapsedMs, 0)) "INFO" } catch { }
                }
            }

            try {
                $script:TicketsLastLeftClickUtc = (Get-Date).ToUniversalTime()
                $script:TicketsLastLeftClickTicketKey = if ($fallbackTicketKey) { $fallbackTicketKey } else { "" }
            } catch { }

            if (-not $shouldTreatAsDoubleClick) { return }

            $opened = $false
            try { $opened = [bool]$openTicketDetailsFromDoubleClick.Invoke($eventArgs, $fallbackTicket) } catch { $opened = $false }
            if ($opened) {
                try { & $writeTicketsLogCmd "Tickets: Preview mouse fallback opened ticket details." "INFO" } catch { }
                $eventArgs.Handled = $true
            } else {
                try { & $writeTicketsLogCmd "Tickets: Preview mouse fallback detected double-click but open failed." "WARN" } catch { }
            }
        } catch {
            try { & $writeTicketsLogCmd ("Tickets: Preview mouse fallback failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }.GetNewClosure()
    $grid.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, $script:TicketsRowPreviewMouseDownHandler, $true)

    # Keyboard fallback: Enter opens selected ticket details.
    $script:TicketsGridKeyDownHandler = [System.Windows.Input.KeyEventHandler]{
        param($sender, $args)
        try {
            if (-not $args) { return }
            if ($args.Key -ne [System.Windows.Input.Key]::Enter) { return }
            $selectedItems = @()
            try { $selectedItems = @(& $getSelectedTicketsCmd -Grid $grid -AllowContextFallback) } catch { $selectedItems = @() }
            $opened = $false
            try { $opened = [bool](& $openTicketDetailsFromContext -Items $selectedItems -Source "enter key") } catch { $opened = $false }
            if ($opened) {
                $args.Handled = $true
            } else {
                try { Write-QOTicketsUILog "Tickets: Enter key pressed but no ticket could be opened." "WARN" } catch { }
            }
        } catch {
            try { Write-QOTicketsUILog ("Tickets: Enter key open failed: " + $_.Exception.Message) "WARN" } catch { }
        }
    }.GetNewClosure()
    $grid.AddHandler([System.Windows.UIElement]::PreviewKeyDownEvent, $script:TicketsGridKeyDownHandler, $true)

    # Keep selection-sync timer disabled; details open is explicit via double-click.
    try {
        if ($script:TicketsSelectionSyncTimer) {
            if ($script:TicketsSelectionSyncTickHandler) {
                try { $script:TicketsSelectionSyncTimer.Remove_Tick($script:TicketsSelectionSyncTickHandler) } catch { }
            }
            try { $script:TicketsSelectionSyncTimer.Stop() } catch { }
            $script:TicketsSelectionSyncTimer = $null
            $script:TicketsSelectionSyncTickHandler = $null
        }
    } catch { }

    # Row edit handler typed
    $script:TicketsRowEditHandler = [System.EventHandler[System.Windows.Controls.DataGridRowEditEndingEventArgs]]{
        param($sender, $args)
        try {
            if ($args.EditAction -ne [System.Windows.Controls.DataGridEditAction]::Commit) { return }

            $grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
            $ticket = $args.Row.Item
            if ($null -eq $ticket) { return }
            $subjectValue = ""
            try {
                if ($ticket.PSObject.Properties.Name -contains "Subject") {
                    $subjectValue = ([string]($ticket.Subject + "")).Trim()
                }
            } catch { $subjectValue = "" }

            $idValue = ""
            try {
                if ($ticket.PSObject.Properties.Name -contains "Id") {
                    $idValue = ([string]($ticket.Id + "")).Trim()
                }
            } catch { $idValue = "" }

            if (-not [string]::IsNullOrWhiteSpace($subjectValue)) {
                try {
                    if ($ticket.PSObject.Properties.Name -contains "TicketName") { $ticket.TicketName = $subjectValue }
                } catch { }
                try {
                    if ($ticket.PSObject.Properties.Name -contains "Title") { $ticket.Title = $subjectValue }
                } catch { }
            }

            $renameCommitted = $false
            if (-not [string]::IsNullOrWhiteSpace($idValue) -and -not [string]::IsNullOrWhiteSpace($subjectValue)) {
                $effectiveRenameCmd = Resolve-QOTInvokable -Candidate $renameTicketCmd -CommandName "Rename-QOTicket"
                if ($effectiveRenameCmd) {
                    try {
                        $null = & $effectiveRenameCmd -Id $idValue -Name $subjectValue
                        $renameCommitted = $true
                    } catch {
                        Write-QOTicketsUILog ("Tickets: Inline rename commit failed: " + $_.Exception.Message) "WARN"
                    }
                }
            }

            if (-not $renameCommitted) {
                $null = & $updateTicketCmd -Ticket $ticket
            }
        } catch { }
    }.GetNewClosure()
    $grid.Add_RowEditEnding($script:TicketsRowEditHandler)

    # Compose mode toggle handlers
    $script:TicketsComposeModeInternalHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $ticket = $grid.SelectedItem
            if (-not $ticket) {
                try { Show-QOTicketsOpenPulse -StatusText $syncStatusText -Message "Open a ticket first." -DurationMilliseconds 1800 } catch { }
                return
            }
            & $setComposeMode -Mode "Note" -PreserveText -SkipFocus
            try {
                $composeTicketId = Get-QOTicketIdValue -Ticket $ticket
                if (-not [string]::IsNullOrWhiteSpace($composeTicketId)) {
                    if ($script:TicketsComposeModeByTicketId -isnot [hashtable]) { $script:TicketsComposeModeByTicketId = @{} }
                    $script:TicketsComposeModeByTicketId[$composeTicketId] = "Note"
                }
                Write-QOTicketsUILog ("Tickets: Compose mode after refresh. TicketId='{0}' Mode='Note'." -f $composeTicketId)
            } catch { }
            try { if ($btnSendReply) { $btnSendReply.IsEnabled = $true } } catch { }
            try { & $updateReplyComposeFeedback $ticket } catch { }
        } catch {
            Write-QOTicketsUILog ("Tickets: Internal note compose mode failed: " + $_.Exception.Message) "WARN"
        }
    }.GetNewClosure()
    $btnComposeInternalNote.Add_Click($script:TicketsComposeModeInternalHandler)

    $script:TicketsComposeModeReplyHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $ticket = $grid.SelectedItem
            if (-not $ticket) { return }

            $canReply = $false
            try { $canReply = [bool](& $canTicketReply $ticket) } catch { $canReply = $false }
            if (-not $canReply) {
                [System.Windows.MessageBox]::Show(
                    "This ticket needs either an Outlook source message or both a customer email address and sender mailbox before it can send email.",
                    "Reply unavailable",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                ) | Out-Null
                & $setComposeMode -Mode "Note" -PreserveText -SkipFocus
                try { if ($btnSendReply) { $btnSendReply.IsEnabled = $true } } catch { }
                return
            }

            & $setComposeMode -Mode "Reply" -PreserveText -SkipFocus
            try {
                $composeTicketId = Get-QOTicketIdValue -Ticket $ticket
                if (-not [string]::IsNullOrWhiteSpace($composeTicketId)) {
                    if ($script:TicketsComposeModeByTicketId -isnot [hashtable]) { $script:TicketsComposeModeByTicketId = @{} }
                    $script:TicketsComposeModeByTicketId[$composeTicketId] = "Reply"
                }
                Write-QOTicketsUILog ("Tickets: Compose mode after refresh. TicketId='{0}' Mode='Reply'." -f $composeTicketId)
            } catch { }
            try { if ($btnSendReply) { $btnSendReply.IsEnabled = $true } } catch { }
            try { & $updateReplyComposeFeedback $ticket } catch { }
        } catch {
            Write-QOTicketsUILog ("Tickets: Reply compose mode failed: " + $_.Exception.Message) "WARN"
        }
    }.GetNewClosure()
    $btnComposeReplyCustomer.Add_Click($script:TicketsComposeModeReplyHandler)

    # Single compose submit handler: internal note or customer reply based on compose mode.
    $replySendWriteLogCmd = Get-Command Write-QOTicketsUILog -CommandType Function -ErrorAction Stop
    $replySendOpenPulseCmd = Get-Command Show-QOTicketsOpenPulse -CommandType Function -ErrorAction Stop
    $replySendElevatedCheckCmd = Get-Command Test-QOTProcessElevated -CommandType Function -ErrorAction Stop
    $replySendResolveInvokableCmd = Get-Command Resolve-QOTInvokable -CommandType Function -ErrorAction Stop
    $replySendProcessArgsCmd = Get-Command ConvertTo-QOTProcessArgumentString -CommandType Function -ErrorAction Stop
    $replySendReadRunnerResultCmd = Get-Command Read-QOTicketsReplyRunnerResult -CommandType Function -ErrorAction Stop
    $replySendTestReplyCompletedCmd = Get-Command Test-QOTicketsReplyOperationCompleted -CommandType Function -ErrorAction Stop
    $replySendStartLimitedProcessCmd = Get-Command Start-QOTLimitedScheduledProcess -CommandType Function -ErrorAction Stop
    $replySendEnsureWorkerCmd = Get-Command Ensure-QOTTicketsWorker -ErrorAction SilentlyContinue | Select-Object -First 1
    $replySendWorkerRuntimeRootCmd = Get-Command Get-QOTTicketsWorkerRuntimeRoot -ErrorAction SilentlyContinue | Select-Object -First 1
    $replySendBuildPayloadCmd = Get-Command New-QOTTicketReplyWorkerPayload -ErrorAction SilentlyContinue | Select-Object -First 1
    $replySendCompleteCmd = Get-Command Complete-QOTTicketReplySend -ErrorAction SilentlyContinue | Select-Object -First 1
    $replyQueueToolkitRootPath = ""
    try { $replyQueueToolkitRootPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } catch { $replyQueueToolkitRootPath = "" }
    $replyQueueRunnerPath = ""
    try {
        $candidateReplyQueueRunner = Join-Path $PSScriptRoot "Tickets.Email.ReplyQueueRunner.ps1"
        if (Test-Path -LiteralPath $candidateReplyQueueRunner) {
            $replyQueueRunnerPath = $candidateReplyQueueRunner
        }
    } catch { $replyQueueRunnerPath = "" }
    $backgroundActionRunnerPath = ""
    try {
        $candidateBackgroundActionRunner = Join-Path $PSScriptRoot "Tickets.BackgroundActionRunner.ps1"
        if (Test-Path -LiteralPath $candidateBackgroundActionRunner) {
            $backgroundActionRunnerPath = $candidateBackgroundActionRunner
        }
    } catch { $backgroundActionRunnerPath = "" }
    $readBackgroundActionRunnerResultCmd = Get-Command Read-QOTicketsBackgroundActionRunnerResult -CommandType Function -ErrorAction Stop
    $cleanupBackgroundActionArtifacts = {
        param(
            [AllowNull()]$TimerRecord,
            [switch]$ForceTerminate
        )

        if (-not $TimerRecord) { return }

        try {
            if ($TimerRecord.Timer -and $TimerRecord.TickHandler) {
                try { $TimerRecord.Timer.Remove_Tick($TimerRecord.TickHandler) } catch { }
                try { $TimerRecord.Timer.Stop() } catch { }
            }
        } catch { }

        try {
            foreach ($path in @($TimerRecord.PayloadPath, $TimerRecord.ResultPath, $TimerRecord.StdOutPath, $TimerRecord.StdErrPath)) {
                $pathValue = ([string]($path + "")).Trim()
                if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
                try {
                    if (Test-Path -LiteralPath $pathValue) {
                        Remove-Item -LiteralPath $pathValue -Force -ErrorAction SilentlyContinue
                    }
                } catch { }
            }
        } catch { }

        try {
            if ($TimerRecord.Process) {
                if ($ForceTerminate) {
                    try {
                        if (-not $TimerRecord.Process.HasExited) {
                            $TimerRecord.Process.Kill()
                            $TimerRecord.Process.WaitForExit(3000) | Out-Null
                        }
                    } catch { }
                }
                try { $TimerRecord.Process.Dispose() } catch { }
            }
        } catch { }

        try {
            if ($script:TicketsBackgroundActionTimers -is [System.Collections.IList]) {
                [void]$script:TicketsBackgroundActionTimers.Remove($TimerRecord)
            }
        } catch { }
    }.GetNewClosure()
    $startBackgroundTicketAction = {
        param(
            [Parameter(Mandatory)][string]$ActionName,
            [Parameter(Mandatory)][hashtable]$Payload,
            [AllowNull()][scriptblock]$OnSuccess,
            [AllowNull()][scriptblock]$OnFailure,
            [int]$TimeoutSeconds = 60,
            [string]$LogLabel = "ticket action"
        )

        if ($TimeoutSeconds -lt 10) { $TimeoutSeconds = 10 }
        if ([string]::IsNullOrWhiteSpace($backgroundActionRunnerPath) -or -not (Test-Path -LiteralPath $backgroundActionRunnerPath)) {
            $failureResult = [pscustomobject]@{
                Success = $false
                Note    = "Background ticket action runner is unavailable."
                Action  = $ActionName
            }
            if ($OnFailure) { & $OnFailure $failureResult }
            return $null
        }

        $tempRoot = Join-Path $env:TEMP "QuinnOptimiserToolkit"
        try {
            if (-not (Test-Path -LiteralPath $tempRoot)) {
                New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            }
        } catch { $tempRoot = $env:TEMP }

        $operationId = [guid]::NewGuid().ToString("N")
        $payloadPath = Join-Path $tempRoot ("qot_ticket_action_{0}.json" -f $operationId)
        $resultPath = Join-Path $tempRoot ("qot_ticket_action_{0}.result.json" -f $operationId)
        $stdoutPath = Join-Path $tempRoot ("qot_ticket_action_{0}.stdout.log" -f $operationId)
        $stderrPath = Join-Path $tempRoot ("qot_ticket_action_{0}.stderr.log" -f $operationId)

        try {
            ($Payload | ConvertTo-Json -Depth 12 -Compress) | Set-Content -LiteralPath $payloadPath -Encoding UTF8 -Force
        } catch {
            $failureResult = [pscustomobject]@{
                Success = $false
                Note    = ("Failed to prepare background {0} payload: " -f $LogLabel) + $_.Exception.Message
                Action  = $ActionName
            }
            if ($OnFailure) { & $OnFailure $failureResult }
            return $null
        }

        $exePath = Join-Path $env:WINDIR "System32\\WindowsPowerShell\\v1.0\\powershell.exe"
        if (-not (Test-Path -LiteralPath $exePath)) { $exePath = "powershell.exe" }

        $process = $null
        try {
            $argList = @(
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-WindowStyle", "Hidden",
                "-File", $backgroundActionRunnerPath,
                "-ToolkitRoot", $replyQueueToolkitRootPath,
                "-Action", $ActionName,
                "-PayloadPath", $payloadPath,
                "-ResultPath", $resultPath
            )
            $argumentString = & $replySendProcessArgsCmd -Arguments $argList

            $workingDirectory = $replyQueueToolkitRootPath
            if ([string]::IsNullOrWhiteSpace($workingDirectory) -or -not (Test-Path -LiteralPath $workingDirectory)) {
                $workingDirectory = $env:TEMP
            }

            $process = Start-Process -FilePath $exePath -ArgumentList $argumentString -WorkingDirectory $workingDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
            try { & $replySendWriteLogCmd ("Tickets: Started background {0} runner. Action='{1}'." -f $LogLabel, $ActionName) } catch { }
        } catch {
            $failureResult = [pscustomobject]@{
                Success = $false
                Note    = ("Failed to start background {0}: " -f $LogLabel) + $_.Exception.Message
                Action  = $ActionName
            }
            try { & $replySendWriteLogCmd ("Tickets: Failed to start background {0} runner: {1}" -f $LogLabel, $_.Exception.Message) "WARN" } catch { }
            if ($OnFailure) { & $OnFailure $failureResult }
            return $null
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(250)
        $timerRecord = [pscustomobject]@{
            Timer       = $timer
            TickHandler = $null
            PayloadPath = $payloadPath
            ResultPath  = $resultPath
            StdOutPath  = $stdoutPath
            StdErrPath  = $stderrPath
            Process     = $process
        }
        try { $script:TicketsBackgroundActionTimers += $timerRecord } catch { }

        $tickHandler = {
            try {
                $isComplete = $false
                $timedOut = $false
                if (-not [string]::IsNullOrWhiteSpace([string]$timerRecord.ResultPath)) {
                    try {
                        if (Test-Path -LiteralPath $timerRecord.ResultPath) {
                            $resultInfo = Get-Item -LiteralPath $timerRecord.ResultPath -ErrorAction Stop
                            if ($resultInfo.Length -gt 0) {
                                $isComplete = $true
                            }
                        }
                    } catch { }
                }

                if (-not $isComplete -and $timerRecord.Process) {
                    try {
                        if ($timerRecord.Process.HasExited -and $stopwatch.Elapsed.TotalSeconds -ge 1) {
                            $isComplete = $true
                        }
                    } catch { }
                }

                if (-not $isComplete -and $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                    $timedOut = $true
                    $isComplete = $true
                }

                if (-not $isComplete) { return }

                try { $stopwatch.Stop() } catch { }
                & $cleanupBackgroundActionArtifacts $timerRecord -ForceTerminate:$timedOut

                $result = $null
                if ($timedOut) {
                    $result = [pscustomobject]@{
                        Success = $false
                        Note    = ("Background {0} timed out after {1} seconds." -f $LogLabel, [int]$TimeoutSeconds)
                        Action  = $ActionName
                    }
                } else {
                    $result = & $readBackgroundActionRunnerResultCmd -ResultPath $timerRecord.ResultPath -StdOutPath $timerRecord.StdOutPath -StdErrPath $timerRecord.StdErrPath
                    if (-not $result) {
                        $result = [pscustomobject]@{
                            Success = $false
                            Note    = ("Background {0} produced no result." -f $LogLabel)
                            Action  = $ActionName
                        }
                    }
                }

                $success = $false
                try { $success = [bool]$result.Success } catch { $success = $false }
                if ($success) {
                    if ($OnSuccess) { & $OnSuccess $result }
                } else {
                    if ($OnFailure) { & $OnFailure $result }
                }
            } catch {
                & $cleanupBackgroundActionArtifacts $timerRecord
                $failureResult = [pscustomobject]@{
                    Success = $false
                    Note    = ("Background {0} watcher failed: " -f $LogLabel) + $_.Exception.Message
                    Action  = $ActionName
                }
                if ($OnFailure) { & $OnFailure $failureResult }
            }
        }.GetNewClosure()

        $timerRecord.TickHandler = $tickHandler
        $timer.Add_Tick($tickHandler)
        $timer.Start()

        return $timerRecord
    }.GetNewClosure()
    $findVisiblePendingReplyMatch = {
        param(
            [Parameter(Mandatory)][string]$TicketIdValue,
            [Parameter(Mandatory)][string]$SubjectValue,
            [Parameter(Mandatory)][string]$BodyValue
        )

        $candidateKey = ""
        try {
            $candidateKey = Get-QOTicketsReplyMatchKey -Reply ([pscustomobject]@{
                Subject = $SubjectValue
                Body    = $BodyValue
            })
        } catch { $candidateKey = "" }
        if ([string]::IsNullOrWhiteSpace($candidateKey)) { return $null }

        $optimisticReplies = @()
        $queuedReplies = @()
        try { if ($getOptimisticReplyEntriesCmd) { $optimisticReplies = @(& $getOptimisticReplyEntriesCmd -TicketId $TicketIdValue) } } catch { $optimisticReplies = @() }
        try {
            if ($getQueuedReplyEntriesCmd) {
                $queuedReplies = @(& $getQueuedReplyEntriesCmd -TicketId $TicketIdValue)
            } else {
                $queuedReplies = @(Get-QOTicketsQueuedReplyEntries -TicketId $TicketIdValue)
            }
        } catch { $queuedReplies = @() }

        $visibleReplies = @()
        try {
            if ($mergeVisiblePendingRepliesCmd) {
                $visibleReplies = @(& $mergeVisiblePendingRepliesCmd -OptimisticReplies $optimisticReplies -QueuedReplies $queuedReplies)
            } else {
                $visibleReplies = @(Merge-QOTTicketVisiblePendingReplyEntries -OptimisticReplies $optimisticReplies -QueuedReplies $queuedReplies)
            }
        } catch { $visibleReplies = @() }

        return @(
            $visibleReplies |
                Where-Object {
                    if (-not $_) { return $false }
                    $stateValue = ""
                    try { if ($_.PSObject.Properties.Name -contains "SendState") { $stateValue = ([string]($_.SendState + "")).Trim() } } catch { $stateValue = "" }
                    if ($stateValue -notmatch '^(?i)(Pending|Queued|Sending)$') { return $false }

                    $replyKey = ""
                    try { $replyKey = Get-QOTicketsReplyMatchKey -Reply $_ } catch { $replyKey = "" }
                    if ([string]::IsNullOrWhiteSpace($replyKey)) { return $false }
                    return [string]::Equals($replyKey, $candidateKey, [System.StringComparison]::Ordinal)
                } |
                Select-Object -First 1
        )[0]
    }.GetNewClosure()
    $startReplyQueueWorker = {
        param([switch]$ShowFailurePulse)

        try {
            if ($initializeReplyQueueServiceCmd) {
                $serviceState = & $initializeReplyQueueServiceCmd -Reason "tickets-ui"
                $workerRunning = $false
                $activeCount = 0
                try { if ($serviceState -and ($serviceState.PSObject.Properties.Name -contains "WorkerRunning")) { $workerRunning = [bool]$serviceState.WorkerRunning } } catch { $workerRunning = $false }
                try { if ($serviceState -and ($serviceState.PSObject.Properties.Name -contains "ActiveCount")) { $activeCount = [int]$serviceState.ActiveCount } } catch { $activeCount = 0 }
                if ($workerRunning -or $activeCount -le 0) {
                    return $true
                }
            }

            if ([string]::IsNullOrWhiteSpace($replyQueueRunnerPath) -or -not (Test-Path -LiteralPath $replyQueueRunnerPath)) {
                throw "Reply queue runner script is unavailable."
            }

            $exePath = Join-Path $env:WINDIR "System32\\WindowsPowerShell\\v1.0\\powershell.exe"
            if (-not (Test-Path -LiteralPath $exePath)) { $exePath = "powershell.exe" }

            $argList = @(
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-WindowStyle", "Hidden",
                "-STA",
                "-File", $replyQueueRunnerPath,
                "-ToolkitRoot", $replyQueueToolkitRootPath
            )
            $argumentString = & $replySendProcessArgsCmd -Arguments $argList

            $workingDirectory = $replyQueueToolkitRootPath
            if ([string]::IsNullOrWhiteSpace($workingDirectory) -or -not (Test-Path -LiteralPath $workingDirectory)) {
                $workingDirectory = $env:TEMP
            }

            if ([bool](& $replySendElevatedCheckCmd)) {
                $null = & $replySendStartLimitedProcessCmd -FilePath $exePath -ArgumentString $argumentString -WorkingDirectory $workingDirectory -TaskNamePrefix "QOTReplyQueue"
                try { & $replySendWriteLogCmd "Tickets: Started detached reply queue runner via limited scheduled task." } catch { }
            } else {
                Start-Process -FilePath $exePath -ArgumentList $argList -WorkingDirectory $workingDirectory -WindowStyle Hidden | Out-Null
                try { & $replySendWriteLogCmd "Tickets: Started detached reply queue runner process." } catch { }
            }

            return $true
        } catch {
            try { & $replySendWriteLogCmd ("Tickets: Failed to start reply queue runner: " + $_.Exception.Message) "WARN" } catch { }
            if ($ShowFailurePulse) {
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply queued, but the background sender could not start." -DurationMilliseconds 2400 } catch { }
            }
            return $false
        }
    }.GetNewClosure()
    try {
        if ($script:TicketsReplyQueuedSends -isnot [System.Collections.Queue]) {
            $script:TicketsReplyQueuedSends = New-Object System.Collections.Queue
        }
    } catch {
        $script:TicketsReplyQueuedSends = New-Object System.Collections.Queue
    }
    $startNextQueuedReply = {
        try {
            if ([bool]$script:TicketsReplySendInProgress) { return }
            if ($script:TicketsReplyQueuedSends -isnot [System.Collections.Queue]) {
                $script:TicketsReplyQueuedSends = New-Object System.Collections.Queue
                return
            }
            if ($script:TicketsReplyQueuedSends.Count -le 0) { return }

            $queuedOperation = $script:TicketsReplyQueuedSends.Dequeue()
            if (-not $queuedOperation) { return }
            $queueSender = New-Object System.Windows.Controls.Button
            $queueSender.Tag = [pscustomobject]@{
                QueuedReplyOperation = $queuedOperation
            }
            if ($script:TicketsSendReplyHandler) {
                try { & $replySendWriteLogCmd "Tickets: Starting queued reply send." } catch { }
                $script:TicketsSendReplyHandler.Invoke($queueSender, [System.Windows.RoutedEventArgs]::new())
            }
        } catch {
            try { & $replySendWriteLogCmd ("Tickets: Failed to start queued reply send: " + $_.Exception.Message) "WARN" } catch { }
        }
    }.GetNewClosure()
    $script:TicketsReplyQueueDrainHandler = $startNextQueuedReply
    $script:TicketsSendReplyHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $queuedSendOperation = $null
            try {
                $sendTag = $null
                try { if ($sender) { $sendTag = $sender.Tag } } catch { $sendTag = $null }
                if ($sendTag -and ($sendTag.PSObject.Properties.Name -contains "QueuedReplyOperation")) {
                    $queuedSendOperation = $sendTag.QueuedReplyOperation
                }
            } catch { $queuedSendOperation = $null }

            $queuedTicketId = ""
            if ($queuedSendOperation) {
                try { if ($queuedSendOperation.PSObject.Properties.Name -contains "TicketId") { $queuedTicketId = ([string]($queuedSendOperation.TicketId + "")).Trim() } } catch { $queuedTicketId = "" }
            }

            $ticket = $null
            if (-not [string]::IsNullOrWhiteSpace($queuedTicketId)) {
                try {
                    $ticket = @(
                        @($grid.ItemsSource) |
                            Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $queuedTicketId) } |
                            Select-Object -First 1
                    )
                    if ($ticket -is [System.Array]) {
                        if ($ticket.Count -gt 0) { $ticket = $ticket[0] } else { $ticket = $null }
                    }
                } catch { $ticket = $null }
                if (-not $ticket) {
                    try {
                        $ticket = @(
                            @($script:AllTickets) |
                                Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $queuedTicketId) } |
                                Select-Object -First 1
                        )
                        if ($ticket -is [System.Array]) {
                            if ($ticket.Count -gt 0) { $ticket = $ticket[0] } else { $ticket = $null }
                        }
                    } catch { $ticket = $null }
                }
            }

            if (-not $ticket) {
                $ticket = $grid.SelectedItem
            }
            if (-not $ticket) {
                $activeId = ""
                try { $activeId = ([string]($script:TicketsActiveTicketId + "")).Trim() } catch { $activeId = "" }
                if (-not [string]::IsNullOrWhiteSpace($activeId)) {
                    try {
                        $ticket = @(
                            @($grid.ItemsSource) |
                                Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $activeId) } |
                                Select-Object -First 1
                        )
                        if ($ticket -is [System.Array]) {
                            if ($ticket.Count -gt 0) { $ticket = $ticket[0] } else { $ticket = $null }
                        }
                    } catch { $ticket = $null }
                    if (-not $ticket) {
                        try {
                            $ticket = @(
                                @($script:AllTickets) |
                                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $activeId) } |
                                    Select-Object -First 1
                            )
                            if ($ticket -is [System.Array]) {
                                if ($ticket.Count -gt 0) { $ticket = $ticket[0] } else { $ticket = $null }
                            }
                        } catch { $ticket = $null }
                    }
                }
            }
            if (-not $ticket) { return }

            $composeMode = ""
            try {
                if (-not $queuedSendOperation -and $sender -and ($sender -eq $btnSendReply)) {
                    $sendButtonTag = $null
                    try { $sendButtonTag = $btnSendReply.Tag } catch { $sendButtonTag = $null }
                    if ($sendButtonTag -and ($sendButtonTag.PSObject.Properties.Name -contains "ComposeAction")) {
                        $composeMode = ([string]($sendButtonTag.ComposeAction + "")).Trim()
                    }
                }
            } catch { $composeMode = "" }
            if ([string]::IsNullOrWhiteSpace($composeMode)) {
                try { $composeMode = [string]$script:TicketsComposeMode } catch { $composeMode = "" }
            }
            if ([string]::IsNullOrWhiteSpace($composeMode)) { $composeMode = "Reply" }
            if ($queuedSendOperation) { $composeMode = "Reply" }
            try { $composeMode = $(if ([string]::Equals([string]$composeMode, "Note", [System.StringComparison]::OrdinalIgnoreCase)) { "Note" } else { "Reply" }) } catch { $composeMode = "Reply" }
            try { & $replySendWriteLogCmd ("Tickets: Send action mode resolved to '{0}'." -f $composeMode) } catch { }

            $messageText = ""
            if ($queuedSendOperation) {
                try { if ($queuedSendOperation.PSObject.Properties.Name -contains "Body") { $messageText = ([string]($queuedSendOperation.Body + "")).Trim() } } catch { $messageText = "" }
            } else {
                try { $messageText = ([string]$ticketReplyText.Text).Trim() } catch { $messageText = "" }
            }
            $optimisticDraftId = ""
            $retryDraftId = ""
            if ($queuedSendOperation) {
                try { if ($queuedSendOperation.PSObject.Properties.Name -contains "DraftId") { $retryDraftId = ([string]($queuedSendOperation.DraftId + "")).Trim() } } catch { $retryDraftId = "" }
            } else {
                try { $retryDraftId = ([string]($script:TicketsReplyRetryDraftId + "")).Trim() } catch { $retryDraftId = "" }
            }

            if ([string]::Equals($composeMode, "Note", [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($queuedSendOperation) {
                    try { & $replySendWriteLogCmd "Tickets: Ignored queued send request because internal notes are local-only." "WARN" } catch { }
                    return
                }
                if ([string]::IsNullOrWhiteSpace($messageText)) {
                    [System.Windows.MessageBox]::Show(
                        "Enter an internal note before saving.",
                        "Note required",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    ) | Out-Null
                    return
                }

                $ticketId = ""
                try { if ($ticket.PSObject.Properties.Name -contains "Id") { $ticketId = [string]$ticket.Id } } catch { $ticketId = "" }
                if ([string]::IsNullOrWhiteSpace($ticketId)) {
                    & $replySendWriteLogCmd "Tickets: Cannot save internal note because ticket Id is missing." "WARN"
                    return
                }
                try { & $replySendWriteLogCmd ("Tickets: Add internal note clicked. TicketId='{0}'." -f $ticketId) } catch { }

                $author = ""
                try {
                    if ($getCurrentAssigneeCmd) {
                        $author = ([string](& $getCurrentAssigneeCmd)).Trim()
                    }
                } catch { $author = "" }
                if ([string]::IsNullOrWhiteSpace($author)) {
                    try { $author = [string]([Environment]::UserName + "") } catch { $author = "" }
                }
                if ([string]::IsNullOrWhiteSpace($author)) { $author = "User" }

                $localNoteClientId = [guid]::NewGuid().ToString("N")
                try { & $replySendWriteLogCmd ("Tickets: Internal note ID created. TicketId='{0}' NoteId='{1}'." -f $ticketId, $localNoteClientId) } catch { }
                try { $null = Add-QOTicketsLocalInternalNote -TicketId $ticketId -Note $messageText -Author $author -ClientNoteId $localNoteClientId } catch { }
                $noteCreatedText = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                try {
                    if ($ticket.PSObject.Properties.Name -contains "UpdatedAt") {
                        $ticket.UpdatedAt = $noteCreatedText
                    } else {
                        $ticket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue $noteCreatedText -Force
                    }
                } catch { }
                try { $ticketReplyText.Text = "" } catch { }
                try { Update-QOTicketDisplayFields -Tickets @($ticket) } catch { }
                try { if ($grid) { $grid.Items.Refresh() } } catch { }
                try {
                    if ($ticket) {
                        $grid.SelectedItem = $ticket
                        $grid.ScrollIntoView($ticket)
                    }
                } catch { }
                try { & $queueLightweightDetailsRefresh $ticket } catch { }
                try { & $scrollTicketDetailsToEnd } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Internal note saved locally." -DurationMilliseconds 1600 } catch { }
                $noteSaveSuccessHandler = {
                    param($result)
                    $persistedNoteId = $localNoteClientId
                    $persistedStorePath = ""
                    try { if ($result -and ($result.PSObject.Properties.Name -contains "NoteId")) { $persistedNoteId = ([string]($result.NoteId + "")).Trim() } } catch { $persistedNoteId = $localNoteClientId }
                    try { if ($result -and ($result.PSObject.Properties.Name -contains "StorePath")) { $persistedStorePath = ([string]($result.StorePath + "")).Trim() } } catch { $persistedStorePath = "" }
                    try { & $replySendWriteLogCmd ("Tickets: Background internal note persisted. TicketId='{0}' NoteId='{1}' StorePath='{2}'." -f $ticketId, $persistedNoteId, $persistedStorePath) } catch { }
                    try {
                        $savedTicket = $null
                        $getLatestTicketsCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTickets"
                        if ($getLatestTicketsCmd) {
                            $dbLatest = & $getLatestTicketsCmd -Quiet
                            if ($dbLatest -and ($dbLatest.PSObject.Properties.Name -contains "Tickets")) {
                                $savedTicket = @(
                                    @($dbLatest.Tickets) |
                                        Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $ticketId) } |
                                        Select-Object -First 1
                                )
                                if ($savedTicket -is [System.Array]) {
                                    if ($savedTicket.Count -gt 0) { $savedTicket = $savedTicket[0] } else { $savedTicket = $null }
                                }
                            }
                        }
                        if ($savedTicket) {
                            $noteCount = 0
                            $replyCount = 0
                            $pendingCount = 0
                            try { if ($savedTicket.PSObject.Properties.Name -contains "Notes") { $noteCount = @($savedTicket.Notes | Where-Object { $_ }).Count } } catch { $noteCount = 0 }
                            try { if ($savedTicket.PSObject.Properties.Name -contains "Replies") { $replyCount = @($savedTicket.Replies | Where-Object { $_ }).Count } } catch { $replyCount = 0 }
                            try { if ($savedTicket.PSObject.Properties.Name -contains "PendingReplies") { $pendingCount = @($savedTicket.PendingReplies | Where-Object { $_ }).Count } } catch { $pendingCount = 0 }
                            try { & $replySendWriteLogCmd ("Tickets: Notes found on reload. TicketId='{0}' Notes={1} Replies={2} PendingReplies={3}." -f $ticketId, $noteCount, $replyCount, $pendingCount) } catch { }
                            try { $null = Update-QOTicketObjectFromSource -Target $ticket -Source $savedTicket } catch { }
                            try {
                                foreach ($candidate in @($script:AllTickets)) {
                                    if (-not $candidate) { continue }
                                    $candidateId = ""
                                    try { $candidateId = Get-QOTicketIdValue -Ticket $candidate } catch { $candidateId = "" }
                                    if ([string]::Equals($candidateId, $ticketId, [System.StringComparison]::OrdinalIgnoreCase)) {
                                        $null = Update-QOTicketObjectFromSource -Target $candidate -Source $savedTicket
                                    }
                                }
                            } catch { }
                            try {
                                if ([bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId)) {
                                    & $queueLightweightDetailsRefresh $ticket
                                } else {
                                    & $replySendWriteLogCmd ("Tickets: Background internal note callback ignored because ticket/view is no longer active. TicketId='{0}'." -f $ticketId)
                                }
                            } catch { }
                        } else {
                            try { & $replySendWriteLogCmd ("Tickets: Internal note persisted but latest ticket reload did not return a matching ticket. TicketId='{0}' NoteId='{1}'." -f $ticketId, $persistedNoteId) "WARN" } catch { }
                            try { & $queueLightweightDetailsRefresh $ticket } catch { }
                        }
                    } catch {
                        try { & $replySendWriteLogCmd ("Tickets: Internal note persisted but reload failed. TicketId='{0}' Error='{1}'." -f $ticketId, $_.Exception.Message) "WARN" } catch { }
                        try { & $queueLightweightDetailsRefresh $ticket } catch { }
                    }
                }.GetNewClosure()
                $noteSaveFailureHandler = {
                    param($result)
                    $failureNote = ""
                    try { if ($result -and ($result.PSObject.Properties.Name -contains "Note")) { $failureNote = ([string]($result.Note + "")).Trim() } } catch { $failureNote = "" }
                    if ([string]::IsNullOrWhiteSpace($failureNote)) { $failureNote = "Internal note save failed in the background." }
                    try { & $replySendWriteLogCmd ("Tickets: Background internal note save failed. TicketId='{0}' Note='{1}'." -f $ticketId, $failureNote) "WARN" } catch { }
                    try { $null = Remove-QOTicketsLocalInternalNote -TicketId $ticketId -ClientNoteId $localNoteClientId } catch { }
                    try { & $queueLightweightDetailsRefresh $ticket } catch { }
                    try {
                        if ([bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId)) {
                            & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Internal note save failed in the background." -DurationMilliseconds 2400
                        }
                    } catch { }
                }.GetNewClosure()
                $null = & $startBackgroundTicketAction -ActionName "save-note" -Payload @{
                    TicketId = $ticketId
                    Note     = $messageText
                    Author   = $author
                    NoteId   = $localNoteClientId
                } -OnSuccess $noteSaveSuccessHandler -OnFailure $noteSaveFailureHandler -TimeoutSeconds 90 -LogLabel "internal note save"
                return
            }

            if (-not $sendReplyCmd) {
                [System.Windows.MessageBox]::Show(
                    "Reply command is unavailable.",
                    "Reply unavailable",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                return
            }

            $canReply = $false
            try { $canReply = [bool](& $canTicketReply $ticket) } catch { $canReply = $false }
            if (-not $canReply) {
                [System.Windows.MessageBox]::Show(
                    "This ticket needs either an Outlook source message or both a customer email address and sender mailbox before it can send email.",
                    "Reply unavailable",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                ) | Out-Null
                return
            }

            $replySubject = ""
            if ($queuedSendOperation) {
                try { if ($queuedSendOperation.PSObject.Properties.Name -contains "Subject") { $replySubject = ([string]($queuedSendOperation.Subject + "")).Trim() } } catch { $replySubject = "" }
            } else {
                try { $replySubject = ([string]$ticketReplySubject.Text).Trim() } catch { $replySubject = "" }
            }
            if ([string]::IsNullOrWhiteSpace($replySubject) -or [string]::IsNullOrWhiteSpace($messageText)) {
                [System.Windows.MessageBox]::Show(
                    "Enter a subject and reply before sending.",
                    "Reply required",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                ) | Out-Null
                return
            }

            $replyAlreadyInProgress = $false
            try { $replyAlreadyInProgress = [bool]$script:TicketsReplySendInProgress } catch { $replyAlreadyInProgress = $false }

            $ticketId = ""
            try { if ($ticket.PSObject.Properties.Name -contains "Id") { $ticketId = ([string]($ticket.Id + "")).Trim() } } catch { $ticketId = "" }
            if ([string]::IsNullOrWhiteSpace($ticketId)) {
                [System.Windows.MessageBox]::Show(
                    "Reply failed: ticket Id is missing.",
                    "Reply failed",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                return
            }
            $shouldUpdateVisibleReplyTicket = $true
            try {
                if ($queuedSendOperation) {
                    $shouldUpdateVisibleReplyTicket = [bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId)
                }
            } catch { $shouldUpdateVisibleReplyTicket = (-not $queuedSendOperation) }

            if (-not $queueTicketPendingReplyCmd -and -not $addTicketPendingReplyCmd) {
                [System.Windows.MessageBox]::Show(
                    "Reply queue storage is unavailable.",
                    "Reply unavailable",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                return
            }

            if ([string]::IsNullOrWhiteSpace($retryDraftId)) {
                try { $retryDraftId = [guid]::NewGuid().ToString("N") } catch { $retryDraftId = ([string](Get-Date -Format "yyyyMMddHHmmssfff")) }
            }

            $visibleDuplicateReply = $null
            try { $visibleDuplicateReply = & $findVisiblePendingReplyMatch -TicketIdValue $ticketId -SubjectValue $replySubject -BodyValue $messageText } catch { $visibleDuplicateReply = $null }
            if ($visibleDuplicateReply) {
                $duplicateDraftId = ""
                try { if ($visibleDuplicateReply.PSObject.Properties.Name -contains "DraftId") { $duplicateDraftId = ([string]($visibleDuplicateReply.DraftId + "")).Trim() } } catch { $duplicateDraftId = "" }
                try { & $replySendWriteLogCmd ("Tickets: Duplicate reply click suppressed locally for TicketId='{0}' DraftId='{1}'." -f $ticketId, $duplicateDraftId) } catch { }
                try { & $updateReplyComposeFeedback $ticket } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "This reply is already queued in the background." -DurationMilliseconds 1800 } catch { }
                return
            }
            try { & $replySendWriteLogCmd ("Tickets: Send button clicked. TicketId='{0}' Mode='Reply'." -f (Get-QOTicketIdValue -Ticket $ticket)) } catch { }

            $optimisticDraftId = $retryDraftId
            try { & $replySendWriteLogCmd ("Tickets: Reply record created. TicketId='{0}' DraftId='{1}' Source='local-optimistic'." -f $ticketId, $optimisticDraftId) } catch { }
            try {
                if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                    $matchedOptimisticReply = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState Queued -FailureNote ""
                    if (-not $matchedOptimisticReply -and $addOptimisticReplyCmd) {
                        $optimisticReply = & $addOptimisticReplyCmd -TicketId $ticketId -Subject $replySubject -Body $messageText -DraftId $optimisticDraftId
                        if ($optimisticReply -and ($optimisticReply.PSObject.Properties.Name -contains "DraftId")) {
                            $optimisticDraftId = ([string]($optimisticReply.DraftId + "")).Trim()
                            if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                                $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState Queued -FailureNote ""
                            }
                        }
                    }
                } elseif ($addOptimisticReplyCmd) {
                    $optimisticReply = & $addOptimisticReplyCmd -TicketId $ticketId -Subject $replySubject -Body $messageText -DraftId $optimisticDraftId
                    if ($optimisticReply -and ($optimisticReply.PSObject.Properties.Name -contains "DraftId")) {
                        $optimisticDraftId = ([string]($optimisticReply.DraftId + "")).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                            $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState Queued -FailureNote ""
                        }
                    }
                }
            } catch {
                try { & $replySendWriteLogCmd ("Tickets: Failed to create optimistic queued reply state: " + $_.Exception.Message) "WARN" } catch { }
            }

            try { $script:TicketsReplyRetryDraftId = "" } catch { }
            try { if (-not $queuedSendOperation -and $ticketReplyText) { $ticketReplyText.Text = "" } } catch { }
            try { Set-QOTicketsReplyUiRefreshWindow -Seconds 90 } catch { }
            if ($shouldUpdateVisibleReplyTicket) {
                try { & $queueLightweightDetailsRefresh $ticket } catch { }
                try { & $scrollTicketDetailsToEnd } catch { }
                try { & $updateReplyComposeFeedback $ticket } catch { }
                try { & $replySendWriteLogCmd ("Tickets: UI updated with pending reply item. TicketId='{0}' DraftId='{1}'." -f $ticketId, $optimisticDraftId) } catch { }
            } else {
                try { & $updateReplyComposeFeedback $ticket } catch { }
            }

            $queuePersistSuccessHandler = {
                param($result)
                $resultDraftId = $optimisticDraftId
                $duplicateSuppressed = $false
                try { if ($result -and ($result.PSObject.Properties.Name -contains "DraftId")) { $resultDraftId = ([string]($result.DraftId + "")).Trim() } } catch { $resultDraftId = $optimisticDraftId }
                try { if ($result -and ($result.PSObject.Properties.Name -contains "DuplicateSuppressed")) { $duplicateSuppressed = [bool]$result.DuplicateSuppressed } } catch { $duplicateSuppressed = $false }

                try {
                    if ($duplicateSuppressed -and $removeOptimisticReplyCmd -and -not [string]::IsNullOrWhiteSpace($optimisticDraftId)) {
                        & $removeOptimisticReplyCmd -TicketId $ticketId -DraftId $optimisticDraftId
                    } elseif ($setOptimisticReplyStateCmd -and -not [string]::IsNullOrWhiteSpace($resultDraftId)) {
                        $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $resultDraftId -SendState Queued -FailureNote ""
                    }
                } catch { }

                try {
                    if ($duplicateSuppressed) {
                        & $replySendWriteLogCmd ("Tickets: Background reply queue persistence reused an existing queued reply. TicketId='{0}' DraftId='{1}'." -f $ticketId, $resultDraftId)
                    } else {
                        & $replySendWriteLogCmd ("Tickets: Background reply queue persistence completed. TicketId='{0}' DraftId='{1}'." -f $ticketId, $resultDraftId)
                    }
                } catch { }

                try { & $refreshPendingReplyUi -TicketIdValue $ticketId -Reason $(if ($duplicateSuppressed) { "queue-duplicate" } else { "queue-persisted" }) } catch { }
                try { & $updateReplyComposeFeedback $ticket } catch { }
                if ($duplicateSuppressed) {
                    try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "This reply is already queued in the background." -DurationMilliseconds 1800 } catch { }
                }
            }.GetNewClosure()
            $queuePersistFailureHandler = {
                param($result)
                $failureText = ""
                try { if ($result -and ($result.PSObject.Properties.Name -contains "Note")) { $failureText = ([string]($result.Note + "")).Trim() } } catch { $failureText = "" }
                if ([string]::IsNullOrWhiteSpace($failureText)) { $failureText = "Reply failed before it could enter the queue." }

                try {
                    if ($setOptimisticReplyStateCmd -and -not [string]::IsNullOrWhiteSpace($optimisticDraftId)) {
                        $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState Failed -FailureNote $failureText
                    }
                } catch { }
                try { & $replySendWriteLogCmd ("Tickets: Background reply queue persistence failed. TicketId='{0}' DraftId='{1}' Note='{2}'." -f $ticketId, $optimisticDraftId, $failureText) "WARN" } catch { }
                try { & $refreshPendingReplyUi -TicketIdValue $ticketId -Reason "queue-persist-failed" } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply failed before it could enter the queue." -DurationMilliseconds 2200 } catch { }
            }.GetNewClosure()

            $queuePersistAction = & $startBackgroundTicketAction -ActionName "queue-reply" -Payload @{
                TicketId = $ticketId
                Subject  = $replySubject
                Body     = $messageText
                DraftId  = $optimisticDraftId
            } -OnSuccess $queuePersistSuccessHandler -OnFailure $queuePersistFailureHandler -TimeoutSeconds 90 -LogLabel "reply queue persistence"

            if ($queuePersistAction) {
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply queued and will send in the background..." -DurationMilliseconds 1800 } catch { }
            }
            try { & $replySendWriteLogCmd ("Tickets: UI event returned after reply queue handoff. TicketId='{0}' DraftId='{1}' QueuePersistenceStarted={2}." -f $ticketId, $optimisticDraftId, [bool]$queuePersistAction) } catch { }
            return

            $resolvedSendReplyCmd = $sendReplyCmd
            if (-not $resolvedSendReplyCmd) {
                try { $resolvedSendReplyCmd = Get-Command -Name "Send-QOTicketReply" -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $resolvedSendReplyCmd = $null }
            }
            $replyCmdName = ""
            $replyModulePath = ""
            try {
                if ($resolvedSendReplyCmd -is [System.Management.Automation.CommandInfo]) {
                    $replyCmdName = [string]$resolvedSendReplyCmd.Name
                    if ($resolvedSendReplyCmd.Module -and $resolvedSendReplyCmd.Module.Path) {
                        $replyModulePath = [string]$resolvedSendReplyCmd.Module.Path
                    }
                } elseif ($resolvedSendReplyCmd -is [string]) {
                    $replyCmdName = ([string]$resolvedSendReplyCmd).Trim()
                }
            } catch { }
            if ([string]::IsNullOrWhiteSpace($replyCmdName)) {
                [System.Windows.MessageBox]::Show(
                    "Reply command is unavailable.",
                    "Reply unavailable",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                return
            }

            $toolkitRootPath = ""
            try { $toolkitRootPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } catch { $toolkitRootPath = "" }
            $replyWorkerExePath = ""
            try {
                if ($replySendEnsureWorkerCmd) {
                    $replyWorkerExePath = [string](& $replySendEnsureWorkerCmd)
                }
            } catch {
                $replyWorkerExePath = ""
                try { & $replySendWriteLogCmd ("Tickets: Failed to prepare reply worker executable: " + $_.Exception.Message) "WARN" } catch { }
            }
            if ([string]::IsNullOrWhiteSpace($replyWorkerExePath) -or -not (Test-Path -LiteralPath $replyWorkerExePath)) {
                [System.Windows.MessageBox]::Show(
                    "Reply worker is unavailable.",
                    "Reply unavailable",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                return
            }
            $timeoutSeconds = 120
            try {
                $configuredReplyTimeout = [int]$script:TicketsReplyTimeoutSeconds
                if ($configuredReplyTimeout -lt 60) {
                    $configuredReplyTimeout = 300
                }
                $timeoutSeconds = [int][math]::Max(30, $configuredReplyTimeout)
            } catch { $timeoutSeconds = 120 }
            $replyMaxAllowedSeconds = [math]::Max(120, [int]$timeoutSeconds + 30)
            $replyViaElevatedBridge = $false
            try { $replyViaElevatedBridge = [bool](& $replySendElevatedCheckCmd) } catch { $replyViaElevatedBridge = $false }
            if ($replyViaElevatedBridge) {
                try { & $replySendWriteLogCmd "Tickets: Reply send requested while toolkit is elevated; using Outlook bridge runner." "WARN" } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Sending via Outlook bridge..." -DurationMilliseconds 2200 } catch { }
            }

            $cleanupAsyncReplyState = {
                try {
                    if ($script:TicketsReplyCompletionTimer) {
                        if ($script:TicketsReplyCompletionTickHandler) {
                            try { $script:TicketsReplyCompletionTimer.Remove_Tick($script:TicketsReplyCompletionTickHandler) } catch { }
                        }
                        try { $script:TicketsReplyCompletionTimer.Stop() } catch { }
                        $script:TicketsReplyCompletionTimer = $null
                    }
                } catch { }
                try {
                    if ($script:TicketsReplyWatchdogTimer) {
                        if ($script:TicketsReplyWatchdogTickHandler) {
                            try { $script:TicketsReplyWatchdogTimer.Remove_Tick($script:TicketsReplyWatchdogTickHandler) } catch { }
                        }
                        try { $script:TicketsReplyWatchdogTimer.Stop() } catch { }
                        $script:TicketsReplyWatchdogTimer = $null
                    }
                } catch { }
                try {
                    if ([string]::Equals([string]$script:TicketsReplyMode, "result-file", [System.StringComparison]::OrdinalIgnoreCase)) {
                        if ($script:TicketsReplyProcess) {
                            try {
                                if (-not $script:TicketsReplyProcess.HasExited) {
                                    $script:TicketsReplyProcess.Kill()
                                    $script:TicketsReplyProcess.WaitForExit(5000) | Out-Null
                                }
                            } catch { }
                        }
                        foreach ($path in @($script:TicketsReplyRunnerPayloadPath, $script:TicketsReplyRunnerStdOutPath, $script:TicketsReplyRunnerStdErrPath, $script:TicketsReplyRunnerResultPath, $script:TicketsReplyRunnerCommandPath)) {
                            if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
                            try {
                                if (Test-Path -LiteralPath $path) {
                                    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                                }
                            } catch { }
                        }
                        try { Remove-QOTLimitedScheduledProcessArtifacts -TaskName $script:TicketsReplyRunnerTaskName -CommandPath $script:TicketsReplyRunnerCommandPath } catch { }
                    } elseif ($script:TicketsReplyPowerShell) {
                        try { $script:TicketsReplyPowerShell.Stop() } catch { }
                        try { $script:TicketsReplyPowerShell.Dispose() } catch { }
                    }
                    $script:TicketsReplyPowerShell = $null
                } catch { }
                try {
                    if ($script:TicketsReplyRunspace) {
                        try { $script:TicketsReplyRunspace.Dispose() } catch { }
                    }
                    $script:TicketsReplyRunspace = $null
                } catch { }
                $script:TicketsReplyProcess = $null
                $script:TicketsReplyRunnerPayloadPath = ""
                $script:TicketsReplyRunnerStdOutPath = ""
                $script:TicketsReplyRunnerStdErrPath = ""
                $script:TicketsReplyRunnerResultPath = ""
                $script:TicketsReplyRunnerTaskName = ""
                $script:TicketsReplyRunnerCommandPath = ""
                $script:TicketsReplyMode = ""
                $script:TicketsReplyRetryDraftId = ""
                $script:TicketsReplyAsyncResult = $null
                $script:TicketsReplyCompletionTickHandler = $null
                $script:TicketsReplyWatchdogTickHandler = $null
                $script:TicketsReplySendInProgress = $false
                $script:TicketsReplyStartUtc = [datetime]::MinValue
                try {
                    if ($btnSendReply) {
                        $btnSendReply.IsEnabled = $true
                        $btnSendReply.Content = if ([string]::Equals([string]$script:TicketsComposeMode, "Note", [System.StringComparison]::OrdinalIgnoreCase)) { "Save internal note" } else { "Send reply" }
                    }
                } catch { }
            }.GetNewClosure()

            if ($replyAlreadyInProgress) {
                $canRecoverStaleReply = $false
                $staleReason = ""
                try {
                    $replyModeValue = ([string]($script:TicketsReplyMode + "")).Trim().ToLowerInvariant()
                    if ($replyModeValue -eq "result-file") {
                        if ([string]::IsNullOrWhiteSpace([string]$script:TicketsReplyRunnerResultPath) -or -not $script:TicketsReplyCompletionTimer -or -not $script:TicketsReplyCompletionTickHandler) {
                            $canRecoverStaleReply = $true
                            $staleReason = "missing result-file state handles"
                        }
                    } else {
                        if (-not $script:TicketsReplyAsyncResult -or -not $script:TicketsReplyPowerShell -or -not $script:TicketsReplyRunspace -or -not $script:TicketsReplyCompletionTimer -or -not $script:TicketsReplyCompletionTickHandler) {
                            $canRecoverStaleReply = $true
                            $staleReason = "missing async state handles"
                        } else {
                            $replyStartUtc = $script:TicketsReplyStartUtc
                            if (-not $replyStartUtc -or $replyStartUtc -eq [datetime]::MinValue) {
                                $canRecoverStaleReply = $true
                                $staleReason = "missing reply start timestamp"
                            }
                        }
                    }

                    if (-not $canRecoverStaleReply) {
                        $replyStartUtc = $script:TicketsReplyStartUtc
                        if (-not $replyStartUtc -or $replyStartUtc -eq [datetime]::MinValue) {
                            $canRecoverStaleReply = $true
                            $staleReason = "missing reply start timestamp"
                        } else {
                            $replyElapsedSeconds = ((Get-Date).ToUniversalTime() - $replyStartUtc).TotalSeconds
                            if ($replyElapsedSeconds -ge $replyMaxAllowedSeconds) {
                                $canRecoverStaleReply = $true
                                $staleReason = ("elapsed {0}s >= {1}s timeout window" -f [math]::Round($replyElapsedSeconds, 1), $replyMaxAllowedSeconds)
                            }
                        }
                    }
                } catch { }

                if ($canRecoverStaleReply) {
                    try { & $replySendWriteLogCmd ("Tickets: Recovering stale async reply send ({0})." -f $staleReason) "WARN" } catch { }
                    try { & $cleanupAsyncReplyState } catch { }
                } else {
                    try {
                        if (-not [string]::IsNullOrWhiteSpace($retryDraftId) -and $setOptimisticReplyStateCmd) {
                            $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $retryDraftId -SendState "Queued" -FailureNote ""
                            $optimisticDraftId = $retryDraftId
                        } elseif ($addOptimisticReplyCmd) {
                            $optimisticReply = & $addOptimisticReplyCmd -TicketId $ticketId -Subject $replySubject -Body $messageText
                            if ($optimisticReply -and ($optimisticReply.PSObject.Properties.Name -contains "DraftId")) {
                                $optimisticDraftId = ([string]($optimisticReply.DraftId + "")).Trim()
                                if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                                    $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Queued" -FailureNote ""
                                }
                            }
                        }
                    } catch {
                        try { & $replySendWriteLogCmd ("Tickets: Failed to queue optimistic reply state: " + $_.Exception.Message) "WARN" } catch { }
                    }
                    try { $script:TicketsReplyRetryDraftId = "" } catch { }
                    try {
                        if ($script:TicketsReplyQueuedSends -isnot [System.Collections.Queue]) {
                            $script:TicketsReplyQueuedSends = New-Object System.Collections.Queue
                        }
                        $script:TicketsReplyQueuedSends.Enqueue([pscustomobject]@{
                            TicketId = $ticketId
                            Subject  = $replySubject
                            Body     = $messageText
                            DraftId  = $optimisticDraftId
                            QueuedAt = (Get-Date).ToUniversalTime().ToString("o")
                        })
                        & $replySendWriteLogCmd ("Tickets: Reply queued behind active send. Queue length={0}." -f $script:TicketsReplyQueuedSends.Count)
                    } catch {
                        try { & $replySendWriteLogCmd ("Tickets: Failed to queue reply send: " + $_.Exception.Message) "ERROR" } catch { }
                        try {
                            if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                                $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Failed" -FailureNote ("Reply failed to queue: " + $_.Exception.Message)
                            }
                        } catch { }
                    }
                    try { if (-not $queuedSendOperation -and $ticketReplyText) { $ticketReplyText.Text = "" } } catch { }
                    if ($shouldUpdateVisibleReplyTicket) {
                        try { & $invokeDetailsUpdate $ticket } catch { }
                        try { & $scrollTicketDetailsToEnd } catch { }
                        try { & $updateReplyComposeFeedback $ticket } catch { }
                    }
                    try {
                        if ($btnSendReply) {
                            $btnSendReply.IsEnabled = $true
                            $btnSendReply.Content = if ([string]::Equals([string]$script:TicketsComposeMode, "Note", [System.StringComparison]::OrdinalIgnoreCase)) { "Save internal note" } else { "Send reply" }
                        }
                    } catch { }
                    try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply queued and will send in the background..." -DurationMilliseconds 1800 } catch { }
                    return
                }
            }

            try {
                if (-not [string]::IsNullOrWhiteSpace($retryDraftId) -and $setOptimisticReplyStateCmd) {
                    $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $retryDraftId -SendState "Sending" -FailureNote ""
                    $optimisticDraftId = $retryDraftId
                } elseif ($addOptimisticReplyCmd) {
                    $optimisticReply = & $addOptimisticReplyCmd -TicketId $ticketId -Subject $replySubject -Body $messageText
                    if ($optimisticReply -and ($optimisticReply.PSObject.Properties.Name -contains "DraftId")) {
                        $optimisticDraftId = ([string]($optimisticReply.DraftId + "")).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                            $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Sending" -FailureNote ""
                        }
                    }
                }
            } catch {
                try { & $replySendWriteLogCmd ("Tickets: Failed to create optimistic reply state: " + $_.Exception.Message) "WARN" } catch { }
            }
            try { $script:TicketsReplyRetryDraftId = "" } catch { }
            try { if (-not $queuedSendOperation -and $ticketReplyText) { $ticketReplyText.Text = "" } } catch { }
            if ($shouldUpdateVisibleReplyTicket) {
                try { & $invokeDetailsUpdate $ticket } catch { }
                try { & $scrollTicketDetailsToEnd } catch { }
                try { & $updateReplyComposeFeedback $ticket } catch { }
            }
            try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply is sending in the background..." -DurationMilliseconds 1800 } catch { }

            try {
                if ($script:TicketsReplyCompletionTimer) {
                    try { $script:TicketsReplyCompletionTimer.Stop() } catch { }
                    if ($script:TicketsReplyCompletionTickHandler) {
                        try { $script:TicketsReplyCompletionTimer.Remove_Tick($script:TicketsReplyCompletionTickHandler) } catch { }
                    }
                }
            } catch { }
            try {
                if ($script:TicketsReplyWatchdogTimer) {
                    try { $script:TicketsReplyWatchdogTimer.Stop() } catch { }
                    if ($script:TicketsReplyWatchdogTickHandler) {
                        try { $script:TicketsReplyWatchdogTimer.Remove_Tick($script:TicketsReplyWatchdogTickHandler) } catch { }
                    }
                }
            } catch { }
            try { if ($script:TicketsReplyPowerShell) { try { $script:TicketsReplyPowerShell.Stop() } catch { }; try { $script:TicketsReplyPowerShell.Dispose() } catch { } } } catch { }
            try { if ($script:TicketsReplyRunspace) { try { $script:TicketsReplyRunspace.Dispose() } catch { } } } catch { }
            $script:TicketsReplyCompletionTimer = $null
            $script:TicketsReplyCompletionTickHandler = $null
            $script:TicketsReplyWatchdogTimer = $null
            $script:TicketsReplyWatchdogTickHandler = $null
            $script:TicketsReplyProcess = $null
            $script:TicketsReplyRunnerPayloadPath = ""
            $script:TicketsReplyRunnerStdOutPath = ""
            $script:TicketsReplyRunnerStdErrPath = ""
            $script:TicketsReplyRunnerResultPath = ""
            $script:TicketsReplyRunnerTaskName = ""
            $script:TicketsReplyRunnerCommandPath = ""
            $script:TicketsReplyMode = ""
            $script:TicketsReplyPowerShell = $null
            $script:TicketsReplyRunspace = $null
            $script:TicketsReplyAsyncResult = $null
            $script:TicketsReplySendInProgress = $true
            $script:TicketsReplyStartUtc = (Get-Date).ToUniversalTime()
            try { & $replySendWriteLogCmd ("Tickets: Async reply send started for ticket '{0}'." -f $ticketId) } catch { }

            try {
                if ($btnSendReply) {
                    $btnSendReply.IsEnabled = $true
                    $btnSendReply.Content = if ([string]::Equals([string]$script:TicketsComposeMode, "Note", [System.StringComparison]::OrdinalIgnoreCase)) { "Save internal note" } else { "Send reply" }
                }
            } catch { }

            try {
                $workerRuntimeRoot = $env:TEMP
                try {
                    if ($replySendWorkerRuntimeRootCmd) {
                        $workerRuntimeRoot = [string](& $replySendWorkerRuntimeRootCmd)
                    }
                } catch { $workerRuntimeRoot = $env:TEMP }
                if ([string]::IsNullOrWhiteSpace($workerRuntimeRoot) -or -not (Test-Path -LiteralPath $workerRuntimeRoot)) {
                    $workerRuntimeRoot = $env:TEMP
                }

                $payloadPath = Join-Path $workerRuntimeRoot ("reply-payload-" + ([guid]::NewGuid().ToString("N")) + ".json")
                $resultPath = Join-Path $workerRuntimeRoot ("reply-result-" + ([guid]::NewGuid().ToString("N")) + ".json")

                $payload = $null
                if ($replySendBuildPayloadCmd) {
                    $payload = & $replySendBuildPayloadCmd -Ticket $ticket -Subject $replySubject -Body $messageText -PendingReplyDraftId $optimisticDraftId
                }
                if (-not $payload) {
                    throw "Reply payload builder is unavailable."
                }
                $payload | ConvertTo-Json -Depth 12 -Compress | Set-Content -LiteralPath $payloadPath -Encoding UTF8

                $argList = @(
                    "send-reply",
                    "--payload", $payloadPath,
                    "--result", $resultPath
                )
                $argumentString = & $replySendProcessArgsCmd -Arguments $argList

                $workingDirectory = $toolkitRootPath
                if ([string]::IsNullOrWhiteSpace($workingDirectory) -or -not (Test-Path -LiteralPath $workingDirectory)) {
                    $workingDirectory = $env:TEMP
                }

                if ($replyViaElevatedBridge) {
                    $limitedLaunch = & $replySendStartLimitedProcessCmd -FilePath $replyWorkerExePath -ArgumentString $argumentString -WorkingDirectory $workingDirectory -TaskNamePrefix "QOTReply"
                    $script:TicketsReplyProcess = $null
                    try { $script:TicketsReplyRunnerTaskName = [string]$limitedLaunch.TaskName } catch { $script:TicketsReplyRunnerTaskName = "" }
                    try { $script:TicketsReplyRunnerCommandPath = [string]$limitedLaunch.CommandPath } catch { $script:TicketsReplyRunnerCommandPath = "" }
                    try { & $replySendWriteLogCmd ("Tickets: Elevated reply worker launched as limited scheduled task. Ticket='{0}'." -f $ticketId) } catch { }
                } else {
                    $script:TicketsReplyProcess = Start-Process -FilePath $replyWorkerExePath -ArgumentList $argumentString -WorkingDirectory $workingDirectory -WindowStyle Hidden -PassThru
                    $script:TicketsReplyRunnerTaskName = ""
                    $script:TicketsReplyRunnerCommandPath = ""
                    try { & $replySendWriteLogCmd ("Tickets: Hidden reply worker launched. Ticket='{0}'." -f $ticketId) } catch { }
                }

                $script:TicketsReplyRunnerPayloadPath = $payloadPath
                $script:TicketsReplyRunnerStdOutPath = ""
                $script:TicketsReplyRunnerStdErrPath = ""
                $script:TicketsReplyRunnerResultPath = $resultPath
                $script:TicketsReplyMode = "result-file"
            } catch {
                & $cleanupAsyncReplyState
                $startFailureMessage = ("Reply failed to start: " + $_.Exception.Message)
                try { & $replySendWriteLogCmd ("Tickets: Async reply failed to start: " + $_.Exception.Message) "WARN" } catch { }
                try {
                    if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                        $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Failed" -FailureNote $startFailureMessage
                    }
                } catch { }
                if ($shouldUpdateVisibleReplyTicket) {
                    try { & $invokeDetailsUpdate $ticket } catch { }
                    try { & $scrollTicketDetailsToEnd } catch { }
                    try { & $updateReplyComposeFeedback $ticket } catch { }
                }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply failed. Ready to resend." -DurationMilliseconds 2200 } catch { }
                try { & $startNextQueuedReply } catch { }
                return
            }

            $replyStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $script:TicketsReplyCompletionTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:TicketsReplyCompletionTimer.Interval = [TimeSpan]::FromMilliseconds(150)
            $script:TicketsReplyCompletionTickHandler = {
                try {
                    $replyModeValue = ([string]($script:TicketsReplyMode + "")).Trim().ToLowerInvariant()
                    $timedOut = $false
                    $replyOperationCompleted = $false
                    try { $replyOperationCompleted = [bool](& $replySendTestReplyCompletedCmd) } catch { $replyOperationCompleted = $false }
                    if ($replyStopwatch.Elapsed.TotalSeconds -ge $timeoutSeconds -and -not $replyOperationCompleted) {
                        $timedOut = $true
                        if ($replyModeValue -ne "result-file") {
                            try { if ($script:TicketsReplyPowerShell) { $script:TicketsReplyPowerShell.Stop() } } catch { }
                        }
                        try { & $replySendWriteLogCmd ("Tickets: Async reply send timed out after {0}s." -f $timeoutSeconds) "WARN" } catch { }
                    }
                    if (-not $timedOut) {
                        if (-not $replyOperationCompleted) { return }
                    }

                    try { $replyStopwatch.Stop() } catch { }

                    $replyResult = $null
                    $completionError = $null
                    if ($timedOut) {
                        $replyResult = [pscustomobject]@{ Success = $false; Note = ("Reply timed out after {0}s." -f $timeoutSeconds) }
                    } else {
                        try {
                            if ($replyModeValue -eq "result-file") {
                                $replyResult = & $replySendReadRunnerResultCmd -ResultPath $script:TicketsReplyRunnerResultPath -StdOutPath $script:TicketsReplyRunnerStdOutPath -StdErrPath $script:TicketsReplyRunnerStdErrPath
                            } else {
                                $output = @($script:TicketsReplyPowerShell.EndInvoke($script:TicketsReplyAsyncResult))
                                if ($output.Count -gt 0) {
                                    $replyResult = $output[-1]
                                } else {
                                    $replyResult = [pscustomobject]@{ Success = $false; Note = "Reply returned no result." }
                                }
                            }
                        } catch {
                            $completionError = $_.Exception
                        }
                    }

                    & $cleanupAsyncReplyState

                    if ($completionError) {
                        try { & $replySendWriteLogCmd ("Tickets: Async reply completion failed: " + $completionError.Message) "ERROR" } catch { }
                        try {
                            if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                                $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Failed" -FailureNote ("Reply failed: " + $completionError.Message)
                            }
                        } catch { }
                        try {
                            if ([bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId)) {
                                & $invokeDetailsUpdate $ticket
                                & $scrollTicketDetailsToEnd
                                & $updateReplyComposeFeedback $ticket
                            }
                        } catch { }
                        try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply failed. Ready to resend." -DurationMilliseconds 2200 } catch { }
                        try { & $startNextQueuedReply } catch { }
                        return
                    }

                    $success = $false
                    $note = ""
                    try { $success = [bool]$replyResult.Success } catch { $success = $false }
                    try { if ($replyResult.PSObject.Properties.Name -contains "Note") { $note = [string]$replyResult.Note } } catch { $note = "" }

                    if ($success) {
                        if ($replySendCompleteCmd) {
                            try {
                                $replyResult = & $replySendCompleteCmd -Ticket $ticket -Subject $replySubject -Body $messageText -SendResult $replyResult -PendingReplyDraftId $optimisticDraftId
                            } catch {
                                $replyResult = [pscustomobject]@{
                                    Success = $true
                                    Note = $(if ([string]::IsNullOrWhiteSpace($note)) { "Reply sent." } else { $note })
                                    Persisted = $false
                                    PersistError = $_.Exception.Message
                                }
                            }
                        }
                        try {
                            if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $removeOptimisticReplyCmd) {
                                & $removeOptimisticReplyCmd -TicketId $ticketId -DraftId $optimisticDraftId
                            }
                        } catch { }
                        try { & $invokeGridRefresh } catch { }
                        $shouldRefreshCompletedTicket = $false
                        try { $shouldRefreshCompletedTicket = [bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId) } catch { $shouldRefreshCompletedTicket = $false }
                        $selectedAfterRefresh = $null
                        try {
                            if ($shouldRefreshCompletedTicket) {
                                $selectedAfterRefresh = @(
                                    @($grid.ItemsSource) |
                                        Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $ticketId) } |
                                        Select-Object -First 1
                                )
                                if ($selectedAfterRefresh -is [System.Array]) {
                                    if ($selectedAfterRefresh.Count -gt 0) { $selectedAfterRefresh = $selectedAfterRefresh[0] } else { $selectedAfterRefresh = $null }
                                }
                            }
                        } catch { $selectedAfterRefresh = $null }
                        if ($shouldRefreshCompletedTicket) {
                            if (-not $selectedAfterRefresh) { $selectedAfterRefresh = $ticket }
                            try {
                                if ($selectedAfterRefresh) {
                                    $grid.SelectedItem = $selectedAfterRefresh
                                    $grid.ScrollIntoView($selectedAfterRefresh)
                                }
                            } catch { }
                            try { & $invokeDetailsUpdate $selectedAfterRefresh } catch { }
                            try { & $scrollTicketDetailsToEnd } catch { }
                            try { & $updateReplyComposeFeedback $selectedAfterRefresh } catch { }
                        }
                        & $replySendWriteLogCmd "Ticket reply sent and details refreshed."
                        $persistedOk = $true
                        $persistError = ""
                        try { if ($replyResult.PSObject.Properties.Name -contains "Persisted") { $persistedOk = [bool]$replyResult.Persisted } } catch { $persistedOk = $true }
                        try { if ($replyResult.PSObject.Properties.Name -contains "PersistError") { $persistError = ([string]($replyResult.PersistError + "")).Trim() } } catch { $persistError = "" }
                        if ($persistedOk) {
                            try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply sent." -DurationMilliseconds 1600 } catch { }
                        } else {
                            try { & $replySendWriteLogCmd ("Tickets: Reply sent but persistence refresh reported an issue. " + $persistError) "WARN" } catch { }
                            try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply sent, but history refresh needs attention." -DurationMilliseconds 2400 } catch { }
                        }
                    } else {
                        try { & $replySendWriteLogCmd ("Tickets: Async reply returned failure: " + $note) "WARN" } catch { }
                        try {
                            if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                                $failureText = ([string]($note + "")).Trim()
                                if ([string]::IsNullOrWhiteSpace($failureText)) { $failureText = "Reply send failed." }
                                $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Failed" -FailureNote $failureText
                            }
                        } catch { }
                        try {
                            if ([bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId)) {
                                & $invokeDetailsUpdate $ticket
                                & $scrollTicketDetailsToEnd
                                & $updateReplyComposeFeedback $ticket
                            }
                        } catch { }
                        try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply failed. Ready to resend." -DurationMilliseconds 2200 } catch { }
                    }
                    try { & $startNextQueuedReply } catch { }
                } catch {
                    $unexpectedError = $_.Exception
                    try { & $replySendWriteLogCmd ("Tickets: Async reply completion timer crashed: " + $unexpectedError.Message) "ERROR" } catch { }
                    try { & $cleanupAsyncReplyState } catch { }
                    try {
                        if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                            $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Failed" -FailureNote ("Reply failed: " + $unexpectedError.Message)
                        }
                    } catch { }
                    try {
                        if ([bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId)) {
                            & $invokeDetailsUpdate $ticket
                            & $scrollTicketDetailsToEnd
                            & $updateReplyComposeFeedback $ticket
                        }
                    } catch { }
                    try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply failed. Ready to resend." -DurationMilliseconds 2200 } catch { }
                    try { & $startNextQueuedReply } catch { }
                }
            }.GetNewClosure()

            $script:TicketsReplyCompletionTimer.Add_Tick($script:TicketsReplyCompletionTickHandler)
            $script:TicketsReplyCompletionTimer.Start()

            $script:TicketsReplyWatchdogTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:TicketsReplyWatchdogTimer.Interval = [TimeSpan]::FromSeconds(2)
            $script:TicketsReplyWatchdogTickHandler = {
                try {
                    if (-not [bool]$script:TicketsReplySendInProgress) {
                        if ($script:TicketsReplyWatchdogTimer) {
                            try { $script:TicketsReplyWatchdogTimer.Stop() } catch { }
                        }
                        return
                    }

                    $elapsedSeconds = 0.0
                    $replyStartUtc = $null
                    try { $replyStartUtc = $script:TicketsReplyStartUtc } catch { $replyStartUtc = $null }
                    if ($replyStartUtc -and $replyStartUtc -ne [datetime]::MinValue) {
                        try { $elapsedSeconds = ((Get-Date).ToUniversalTime() - $replyStartUtc).TotalSeconds } catch { $elapsedSeconds = 0.0 }
                    }

                    $completionTimerReady = $false
                    try { $completionTimerReady = [bool]($script:TicketsReplyCompletionTimer -and $script:TicketsReplyCompletionTickHandler) } catch { $completionTimerReady = $false }
                    if (-not $completionTimerReady) {
                        $isReplyOperationCompleted = $false
                        try { $isReplyOperationCompleted = [bool](& $replySendTestReplyCompletedCmd) } catch { $isReplyOperationCompleted = $false }
                        if ($isReplyOperationCompleted -and $script:TicketsReplyCompletionTickHandler) {
                            try { & $replySendWriteLogCmd "Tickets: Reply watchdog forcing completion because completion timer is missing." "WARN" } catch { }
                            & $script:TicketsReplyCompletionTickHandler
                            return
                        }

                        if ($elapsedSeconds -ge $replyMaxAllowedSeconds -and -not [string]::Equals([string]$script:TicketsReplyMode, "result-file", [System.StringComparison]::OrdinalIgnoreCase)) {
                            try { if ($script:TicketsReplyPowerShell) { $script:TicketsReplyPowerShell.Stop() } } catch { }
                        }

                        try { & $replySendWriteLogCmd "Tickets: Reply watchdog recovered stale send state (completion timer missing)." "WARN" } catch { }
                        & $cleanupAsyncReplyState
                        try {
                            if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                                $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Failed" -FailureNote "Reply send reset before completion. Please resend it."
                            }
                        } catch { }
                        try {
                            if ([bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId)) {
                                & $invokeDetailsUpdate $ticket
                                & $scrollTicketDetailsToEnd
                                & $updateReplyComposeFeedback $ticket
                            }
                        } catch { }
                        try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply failed. Ready to resend." -DurationMilliseconds 2200 } catch { }
                        try { & $startNextQueuedReply } catch { }
                        return
                    }

                    $replyOperationCompleted = $false
                    try { $replyOperationCompleted = [bool](& $replySendTestReplyCompletedCmd) } catch { $replyOperationCompleted = $false }
                    if ($replyOperationCompleted) {
                        try { & $replySendWriteLogCmd "Tickets: Reply watchdog forcing completion tick for finished async send." "WARN" } catch { }
                        & $script:TicketsReplyCompletionTickHandler
                        return
                    }

                    if ($elapsedSeconds -ge $replyMaxAllowedSeconds) {
                        try { & $replySendWriteLogCmd ("Tickets: Reply watchdog forcing timeout recovery after {0}s." -f [math]::Round($elapsedSeconds, 1)) "WARN" } catch { }
                        if (-not [string]::Equals([string]$script:TicketsReplyMode, "result-file", [System.StringComparison]::OrdinalIgnoreCase)) {
                            try { if ($script:TicketsReplyPowerShell) { $script:TicketsReplyPowerShell.Stop() } } catch { }
                        }
                        if ($script:TicketsReplyCompletionTickHandler) {
                            & $script:TicketsReplyCompletionTickHandler
                            return
                        }
                        & $cleanupAsyncReplyState
                        try {
                            if (-not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                                $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Failed" -FailureNote ("Reply timed out after {0} seconds." -f [int]$timeoutSeconds)
                            }
                        } catch { }
                        try {
                            if ([bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId)) {
                                & $invokeDetailsUpdate $ticket
                                & $scrollTicketDetailsToEnd
                                & $updateReplyComposeFeedback $ticket
                            }
                        } catch { }
                        try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply failed. Ready to resend." -DurationMilliseconds 2200 } catch { }
                        try { & $startNextQueuedReply } catch { }
                    }
                } catch {
                    try { & $replySendWriteLogCmd ("Tickets: Reply watchdog crashed: " + $_.Exception.Message) "ERROR" } catch { }
                    try { & $cleanupAsyncReplyState } catch { }
                    try { & $startNextQueuedReply } catch { }
                }
            }.GetNewClosure()
            $script:TicketsReplyWatchdogTimer.Add_Tick($script:TicketsReplyWatchdogTickHandler)
            $script:TicketsReplyWatchdogTimer.Start()
            try { & $replySendWriteLogCmd "Tickets: Async reply watchdog started." } catch { }
            return
        } catch {
            $modeForError = ""
            try { $modeForError = [string]$script:TicketsComposeMode } catch { $modeForError = "" }
            if ([string]::IsNullOrWhiteSpace($modeForError)) { $modeForError = "Reply" }
            $errMessage = $_.Exception.Message
            if ([string]::Equals($modeForError, "Note", [System.StringComparison]::OrdinalIgnoreCase)) {
                & $replySendWriteLogCmd ("Ticket internal note save failed: " + $errMessage) "ERROR"
                [System.Windows.MessageBox]::Show(
                    ("Internal note save failed: " + $errMessage),
                    "Tickets",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
            } else {
                & $replySendWriteLogCmd ("Ticket reply failed: " + $errMessage) "ERROR"
                try {
                    if (-not [string]::IsNullOrWhiteSpace($ticketId) -and -not [string]::IsNullOrWhiteSpace($optimisticDraftId) -and $setOptimisticReplyStateCmd) {
                        $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $optimisticDraftId -SendState "Failed" -FailureNote ("Ticket reply failed: " + $errMessage)
                    }
                } catch { }
                try {
                    if ([string]::IsNullOrWhiteSpace($ticketId) -or [bool](& $isTicketVisibleInDetails -TicketIdValue $ticketId)) {
                        & $invokeDetailsUpdate $ticket
                        & $scrollTicketDetailsToEnd
                        & $updateReplyComposeFeedback $ticket
                    }
                } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply failed. Ready to resend." -DurationMilliseconds 2200 } catch { }
                try { & $startNextQueuedReply } catch { }
            }
        }
    }.GetNewClosure()
    $btnSendReply.Add_Click($script:TicketsSendReplyHandler)

    try {
        if ($script:TicketsReplyQueueKickTimer) {
            if ($script:TicketsReplyQueueKickTickHandler) {
                try { $script:TicketsReplyQueueKickTimer.Remove_Tick($script:TicketsReplyQueueKickTickHandler) } catch { }
            }
            try { $script:TicketsReplyQueueKickTimer.Stop() } catch { }
            $script:TicketsReplyQueueKickTimer = $null
        }
    } catch { }
    try {
        $queueWorkerKickTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $queueWorkerKickTimer.Interval = [TimeSpan]::FromMilliseconds(150)
        $queueWorkerKickTickHandler = {
            try {
                if ($script:TicketsReplyQueuedSends -isnot [System.Collections.Queue]) { return }
                if ($script:TicketsReplyQueuedSends.Count -le 0) { return }

                $replyActive = $false
                try { $replyActive = [bool]$script:TicketsReplySendInProgress } catch { $replyActive = $false }
                if (-not $replyActive) {
                    try { & $replySendWriteLogCmd "Tickets: Reply queue heartbeat starting next queued reply." } catch { }
                    try { & $startNextQueuedReply } catch { }
                    return
                }

                $replyOperationCompleted = $false
                try { $replyOperationCompleted = [bool](& $replySendTestReplyCompletedCmd) } catch { $replyOperationCompleted = $false }
                if ($replyOperationCompleted -and $script:TicketsReplyCompletionTickHandler) {
                    try { & $replySendWriteLogCmd "Tickets: Reply queue heartbeat completing finished active send before draining queue." "WARN" } catch { }
                    try { & $script:TicketsReplyCompletionTickHandler } catch { }
                    return
                }

                $hasCompletionLoop = $false
                try { $hasCompletionLoop = [bool]($script:TicketsReplyCompletionTimer -and $script:TicketsReplyCompletionTickHandler) } catch { $hasCompletionLoop = $false }
                if ($hasCompletionLoop) { return }

                $replyStartUtc = [datetime]::MinValue
                try { $replyStartUtc = [datetime]$script:TicketsReplyStartUtc } catch { $replyStartUtc = [datetime]::MinValue }
                $elapsedSeconds = 999999
                if ($replyStartUtc -and $replyStartUtc -ne [datetime]::MinValue) {
                    try { $elapsedSeconds = ((Get-Date).ToUniversalTime() - $replyStartUtc).TotalSeconds } catch { $elapsedSeconds = 999999 }
                }
                if ($elapsedSeconds -lt 10) { return }

                try { & $replySendWriteLogCmd "Tickets: Reply queue heartbeat recovering missing completion loop so queued replies can drain." "WARN" } catch { }
                try {
                    if ($script:TicketsReplyWatchdogTimer) {
                        if ($script:TicketsReplyWatchdogTickHandler) {
                            try { $script:TicketsReplyWatchdogTimer.Remove_Tick($script:TicketsReplyWatchdogTickHandler) } catch { }
                        }
                        try { $script:TicketsReplyWatchdogTimer.Stop() } catch { }
                    }
                } catch { }
                try {
                    if ($script:TicketsReplyCompletionTimer) {
                        if ($script:TicketsReplyCompletionTickHandler) {
                            try { $script:TicketsReplyCompletionTimer.Remove_Tick($script:TicketsReplyCompletionTickHandler) } catch { }
                        }
                        try { $script:TicketsReplyCompletionTimer.Stop() } catch { }
                    }
                } catch { }
                try {
                    if ($script:TicketsReplyPowerShell) {
                        try { $script:TicketsReplyPowerShell.Stop() } catch { }
                        try { $script:TicketsReplyPowerShell.Dispose() } catch { }
                    }
                } catch { }
                try {
                    if ($script:TicketsReplyRunspace) {
                        try { $script:TicketsReplyRunspace.Dispose() } catch { }
                    }
                } catch { }
                try {
                    if ([string]::Equals([string]$script:TicketsReplyMode, "result-file", [System.StringComparison]::OrdinalIgnoreCase)) {
                        try { Remove-QOTLimitedScheduledProcessArtifacts -TaskName $script:TicketsReplyRunnerTaskName -CommandPath $script:TicketsReplyRunnerCommandPath } catch { }
                    }
                } catch { }
                $script:TicketsReplyCompletionTimer = $null
                $script:TicketsReplyCompletionTickHandler = $null
                $script:TicketsReplyWatchdogTimer = $null
                $script:TicketsReplyWatchdogTickHandler = $null
                $script:TicketsReplyPowerShell = $null
                $script:TicketsReplyRunspace = $null
                $script:TicketsReplyAsyncResult = $null
                $script:TicketsReplyProcess = $null
                $script:TicketsReplyRunnerPayloadPath = ""
                $script:TicketsReplyRunnerStdOutPath = ""
                $script:TicketsReplyRunnerStdErrPath = ""
                $script:TicketsReplyRunnerResultPath = ""
                $script:TicketsReplyRunnerTaskName = ""
                $script:TicketsReplyRunnerCommandPath = ""
                $script:TicketsReplyMode = ""
                $script:TicketsReplyRetryDraftId = ""
                $script:TicketsReplySendInProgress = $false
                $script:TicketsReplyStartUtc = [datetime]::MinValue
                try {
                    if ($btnSendReply) {
                        $btnSendReply.IsEnabled = $true
                        $btnSendReply.Content = if ([string]::Equals([string]$script:TicketsComposeMode, "Note", [System.StringComparison]::OrdinalIgnoreCase)) { "Save internal note" } else { "Send reply" }
                    }
                } catch { }
                try { & $startNextQueuedReply } catch { }
            } catch {
                try { & $replySendWriteLogCmd ("Tickets: Reply queue heartbeat crashed: " + $_.Exception.Message) "ERROR" } catch { }
            }
        }.GetNewClosure()
        $script:TicketsReplyQueueKickTimer = $queueWorkerKickTimer
        $script:TicketsReplyQueueKickTickHandler = $queueWorkerKickTickHandler
        $queueWorkerKickTimer.Add_Tick($queueWorkerKickTickHandler)
        $queueWorkerKickTimer.Start()
        try { & $replySendWriteLogCmd "Tickets: Reply queue heartbeat started." } catch { }
    } catch {
        try { & $replySendWriteLogCmd ("Tickets: Failed to start reply queue heartbeat: " + $_.Exception.Message) "WARN" } catch { }
    }

    $script:TicketsRetryReplyHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $requestedRetryTicketId = ""
            $requestedRetryDraftId = ""
            try {
                $retryTag = $null
                try { if ($sender) { $retryTag = $sender.Tag } } catch { $retryTag = $null }
                if ($retryTag) {
                    try {
                        if ($retryTag.PSObject.Properties.Name -contains "PendingReplyTicketId") {
                            $requestedRetryTicketId = ([string]($retryTag.PendingReplyTicketId + "")).Trim()
                        } elseif ($retryTag.PSObject.Properties.Name -contains "TicketId") {
                            $requestedRetryTicketId = ([string]($retryTag.TicketId + "")).Trim()
                        }
                    } catch { $requestedRetryTicketId = "" }
                    try {
                        if ($retryTag.PSObject.Properties.Name -contains "PendingReplyDraftId") {
                            $requestedRetryDraftId = ([string]($retryTag.PendingReplyDraftId + "")).Trim()
                        } elseif ($retryTag.PSObject.Properties.Name -contains "DraftId") {
                            $requestedRetryDraftId = ([string]($retryTag.DraftId + "")).Trim()
                        }
                    } catch { $requestedRetryDraftId = "" }
                }
            } catch { }

            $ticket = $null
            if (-not [string]::IsNullOrWhiteSpace($requestedRetryTicketId)) {
                try { $ticket = & $resolveVisibleTicketById -TicketIdValue $requestedRetryTicketId -AllowSelectedFallback } catch { $ticket = $null }
            }

            if (-not $ticket) {
                $ticket = $grid.SelectedItem
            }
            if (-not $ticket) {
                $activeId = ""
                try { $activeId = ([string]($script:TicketsActiveTicketId + "")).Trim() } catch { $activeId = "" }
                if (-not [string]::IsNullOrWhiteSpace($activeId)) {
                    try {
                        $ticket = @(
                            @($grid.ItemsSource) |
                                Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq $activeId) } |
                                Select-Object -First 1
                        )
                        if ($ticket -is [System.Array]) {
                            if ($ticket.Count -gt 0) { $ticket = $ticket[0] } else { $ticket = $null }
                        }
                    } catch { $ticket = $null }
                }
            }

            $ticketId = ""
            try {
                if (-not [string]::IsNullOrWhiteSpace($requestedRetryTicketId)) {
                    $ticketId = $requestedRetryTicketId
                } elseif ($getTicketIdValueCmd) {
                    $ticketId = ([string](& $getTicketIdValueCmd -Ticket $ticket)).Trim()
                } elseif ($ticket.PSObject.Properties.Name -contains "Id") {
                    $ticketId = ([string]($ticket.Id + "")).Trim()
                }
            } catch { $ticketId = "" }
            if ([string]::IsNullOrWhiteSpace($ticketId)) { return }
            try { & $replySendWriteLogCmd ("Tickets: Retry clicked. TicketId='{0}' DraftId='{1}'." -f $ticketId, $requestedRetryDraftId) } catch { }

            if ([string]::IsNullOrWhiteSpace($requestedRetryDraftId)) {
                $retryCandidate = $null
                try {
                    $retryCandidate = @(
                        $(if ($getQueuedReplyEntriesCmd) { & $getQueuedReplyEntriesCmd -TicketId $ticketId } else { Get-QOTicketsQueuedReplyEntries -TicketId $ticketId }) |
                            Where-Object {
                                if (-not $_) { return $false }
                                $entryState = ""
                                try { if ($_.PSObject.Properties.Name -contains "SendState") { $entryState = ([string]($_.SendState + "")).Trim() } } catch { $entryState = "" }
                                return ($entryState -match '^(?i)(Failed|Queued|Pending)$')
                            } |
                            Sort-Object -Property @(
                                @{ Expression = {
                                    $stateValue = ""
                                    try { if ($_.PSObject.Properties.Name -contains "SendState") { $stateValue = ([string]($_.SendState + "")).Trim() } } catch { $stateValue = "" }
                                    if ([string]::Equals($stateValue, "Failed", [System.StringComparison]::OrdinalIgnoreCase)) { return 0 }
                                    return 1
                                }; Descending = $false },
                                @{ Expression = {
                                    try { if ($_.PSObject.Properties.Name -contains "QueuePosition") { return [int]$_.QueuePosition } } catch { }
                                    return 9999
                                }; Descending = $false }
                            ) |
                            Select-Object -First 1
                    )
                    if ($retryCandidate.Count -gt 0) { $retryCandidate = $retryCandidate[0] }
                } catch { $retryCandidate = $null }

                if ($retryCandidate) {
                    try { if ($retryCandidate.PSObject.Properties.Name -contains "DraftId") { $requestedRetryDraftId = ([string]($retryCandidate.DraftId + "")).Trim() } } catch { $requestedRetryDraftId = "" }
                }
            }

            if ([string]::IsNullOrWhiteSpace($requestedRetryDraftId) -or -not $retryTicketPendingReplyCmd) {
                try { & $updateReplyComposeFeedback $ticket } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "No queued reply is ready to retry." -DurationMilliseconds 1800 } catch { }
                return
            }

            try {
                if ($setOptimisticReplyStateCmd) {
                    $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $requestedRetryDraftId -SendState Queued -FailureNote ""
                }
            } catch { }
            try { & $refreshPendingReplyUi -TicketIdValue $ticketId -Reason "retry-click" } catch { }
            $retrySuccessHandler = {
                param($result)
                $newRetryDraftId = ""
                try { if ($result -and ($result.PSObject.Properties.Name -contains "DraftId")) { $newRetryDraftId = ([string]($result.DraftId + "")).Trim() } } catch { $newRetryDraftId = "" }
                if ([string]::IsNullOrWhiteSpace($newRetryDraftId)) { $newRetryDraftId = $requestedRetryDraftId }
                try { & $replySendWriteLogCmd ("Tickets: Background retry persistence completed. TicketId='{0}' OldDraftId='{1}' NewDraftId='{2}'." -f $ticketId, $requestedRetryDraftId, $newRetryDraftId) } catch { }
                try { & $replySendWriteLogCmd ("Tickets: Delete/retry persistence success. Action='retry-reply' TicketId='{0}' OldDraftId='{1}' NewDraftId='{2}'." -f $ticketId, $requestedRetryDraftId, $newRetryDraftId) } catch { }
                try {
                    Remove-QOTicketsLocalPendingReply -TicketId $ticketId -DraftId $requestedRetryDraftId -Ticket $ticket
                } catch { }
                try { & $refreshPendingReplyUi -TicketIdValue $ticketId -Reason "retry-persisted" } catch { }
            }.GetNewClosure()
            $retryFailureHandler = {
                param($result)
                $failureText = ""
                try { if ($result -and ($result.PSObject.Properties.Name -contains "Note")) { $failureText = ([string]($result.Note + "")).Trim() } } catch { $failureText = "" }
                if ([string]::IsNullOrWhiteSpace($failureText)) { $failureText = "Reply could not be requeued." }
                try {
                    if ($setOptimisticReplyStateCmd) {
                        $null = & $setOptimisticReplyStateCmd -TicketId $ticketId -DraftId $requestedRetryDraftId -SendState Failed -FailureNote $failureText
                    }
                } catch { }
                try { & $replySendWriteLogCmd ("Tickets: Background retry persistence failed. TicketId='{0}' DraftId='{1}' Note='{2}'." -f $ticketId, $requestedRetryDraftId, $failureText) "WARN" } catch { }
                try { & $replySendWriteLogCmd ("Tickets: Delete/retry persistence failure. Action='retry-reply' TicketId='{0}' DraftId='{1}' Note='{2}'." -f $ticketId, $requestedRetryDraftId, $failureText) "WARN" } catch { }
                try { & $refreshPendingReplyUi -TicketIdValue $ticketId -Reason "retry-persist-failed" } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message $failureText -DurationMilliseconds 2200 } catch { }
            }.GetNewClosure()

            $retryAction = & $startBackgroundTicketAction -ActionName "retry-reply" -Payload @{
                TicketId = $ticketId
                DraftId  = $requestedRetryDraftId
            } -OnSuccess $retrySuccessHandler -OnFailure $retryFailureHandler -TimeoutSeconds 90 -LogLabel "reply retry"

            if ($retryAction) {
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply requeued and retrying in the background..." -DurationMilliseconds 1800 } catch { }
            }
        } catch {
            try { & $replySendWriteLogCmd ("Tickets: Retry failed reply action failed: " + $_.Exception.Message) "WARN" } catch { }
            try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message ([string]$_.Exception.Message) -DurationMilliseconds 2200 } catch { }
        }
    }.GetNewClosure()
    $btnRetryFailedReply.Add_Click($script:TicketsRetryReplyHandler)

    $script:TicketsCancelReplyHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $requestedTicketId = ""
            $requestedDraftId = ""
            try {
                $cancelTag = $null
                try { if ($sender) { $cancelTag = $sender.Tag } } catch { $cancelTag = $null }
                if ($cancelTag) {
                    try {
                        if ($cancelTag.PSObject.Properties.Name -contains "PendingReplyTicketId") {
                            $requestedTicketId = ([string]($cancelTag.PendingReplyTicketId + "")).Trim()
                        } elseif ($cancelTag.PSObject.Properties.Name -contains "TicketId") {
                            $requestedTicketId = ([string]($cancelTag.TicketId + "")).Trim()
                        }
                    } catch { $requestedTicketId = "" }
                    try {
                        if ($cancelTag.PSObject.Properties.Name -contains "PendingReplyDraftId") {
                            $requestedDraftId = ([string]($cancelTag.PendingReplyDraftId + "")).Trim()
                        } elseif ($cancelTag.PSObject.Properties.Name -contains "DraftId") {
                            $requestedDraftId = ([string]($cancelTag.DraftId + "")).Trim()
                        }
                    } catch { $requestedDraftId = "" }
                }
            } catch { }

            if ([string]::IsNullOrWhiteSpace($requestedTicketId) -or [string]::IsNullOrWhiteSpace($requestedDraftId) -or -not $cancelTicketPendingReplyCmd) {
                return
            }
            try { & $replySendWriteLogCmd ("Tickets: Delete clicked. TicketId='{0}' DraftId='{1}'." -f $requestedTicketId, $requestedDraftId) } catch { }

            $ticket = $null
            try { $ticket = & $resolveVisibleTicketById -TicketIdValue $requestedTicketId -AllowSelectedFallback } catch { $ticket = $null }
            try { Add-QOTicketsSuppressedPendingReplyDraftId -TicketId $requestedTicketId -DraftId $requestedDraftId } catch { }
            try {
                Remove-QOTicketsLocalPendingReply -TicketId $requestedTicketId -DraftId $requestedDraftId -Ticket $ticket
            } catch { }
            try { & $refreshPendingReplyUi -TicketIdValue $requestedTicketId -Reason "delete-click" } catch { }
            $cancelSuccessHandler = {
                param($result)
                try {
                    Remove-QOTicketsLocalPendingReply -TicketId $requestedTicketId -DraftId $requestedDraftId -Ticket $ticket
                } catch { }
                try { Remove-QOTicketsSuppressedPendingReplyDraftId -TicketId $requestedTicketId -DraftId $requestedDraftId } catch { }
                try { & $replySendWriteLogCmd ("Tickets: Background cancel persistence completed. TicketId='{0}' DraftId='{1}'." -f $requestedTicketId, $requestedDraftId) } catch { }
                try { & $replySendWriteLogCmd ("Tickets: Delete/retry persistence success. Action='delete-reply' TicketId='{0}' DraftId='{1}'." -f $requestedTicketId, $requestedDraftId) } catch { }
                try { & $refreshPendingReplyUi -TicketIdValue $requestedTicketId -Reason "delete-persisted" } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Reply removed from the background queue." -DurationMilliseconds 2200 } catch { }
            }.GetNewClosure()
            $cancelFailureHandler = {
                param($result)
                $failureText = "Reply could not be removed from the queue."
                try { if ($result -and ($result.PSObject.Properties.Name -contains "Note")) { $failureText = ([string]($result.Note + "")).Trim() } } catch { $failureText = "Reply could not be removed from the queue." }
                try { Remove-QOTicketsSuppressedPendingReplyDraftId -TicketId $requestedTicketId -DraftId $requestedDraftId } catch { }
                try { & $replySendWriteLogCmd ("Tickets: Background cancel persistence failed. TicketId='{0}' DraftId='{1}' Note='{2}'." -f $requestedTicketId, $requestedDraftId, $failureText) "WARN" } catch { }
                try { & $replySendWriteLogCmd ("Tickets: Delete/retry persistence failure. Action='delete-reply' TicketId='{0}' DraftId='{1}' Note='{2}'." -f $requestedTicketId, $requestedDraftId, $failureText) "WARN" } catch { }
                try { & $refreshPendingReplyUi -TicketIdValue $requestedTicketId -Reason "delete-persist-failed" } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message $failureText -DurationMilliseconds 2200 } catch { }
            }.GetNewClosure()

            $cancelAction = & $startBackgroundTicketAction -ActionName "cancel-reply" -Payload @{
                TicketId = $requestedTicketId
                DraftId  = $requestedDraftId
            } -OnSuccess $cancelSuccessHandler -OnFailure $cancelFailureHandler -TimeoutSeconds 90 -LogLabel "reply delete"

            if (-not $cancelAction) {
                try { Remove-QOTicketsSuppressedPendingReplyDraftId -TicketId $requestedTicketId -DraftId $requestedDraftId } catch { }
                try { & $refreshPendingReplyUi -TicketIdValue $requestedTicketId -Reason "delete-start-failed" } catch { }
            }
        } catch {
            try { & $replySendWriteLogCmd ("Tickets: Cancel pending reply action failed: " + $_.Exception.Message) "WARN" } catch { }
            try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message ([string]$_.Exception.Message) -DurationMilliseconds 2200 } catch { }
        }
    }.GetNewClosure()

    $script:TicketsDeleteNoteHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $requestedTicketId = ""
            $requestedNoteId = ""
            try {
                $noteTag = $null
                try { if ($sender) { $noteTag = $sender.Tag } } catch { $noteTag = $null }
                if ($noteTag) {
                    try {
                        if ($noteTag.PSObject.Properties.Name -contains "TicketId") {
                            $requestedTicketId = ([string]($noteTag.TicketId + "")).Trim()
                        }
                    } catch { $requestedTicketId = "" }
                    try {
                        foreach ($noteIdProp in @("NoteId", "ClientNoteId", "Id")) {
                            if ([string]::IsNullOrWhiteSpace($requestedNoteId) -and $noteTag.PSObject.Properties.Name -contains $noteIdProp) {
                                $requestedNoteId = ([string]($noteTag.$noteIdProp + "")).Trim()
                            }
                        }
                    } catch { $requestedNoteId = "" }
                }
            } catch { }

            $ticket = $null
            if (-not [string]::IsNullOrWhiteSpace($requestedTicketId)) {
                try { $ticket = & $resolveVisibleTicketById -TicketIdValue $requestedTicketId -AllowSelectedFallback } catch { $ticket = $null }
            }
            if (-not $ticket) {
                try { $ticket = $grid.SelectedItem } catch { $ticket = $null }
            }
            if ([string]::IsNullOrWhiteSpace($requestedTicketId)) {
                try { $requestedTicketId = Get-QOTicketIdValue -Ticket $ticket } catch { $requestedTicketId = "" }
            }
            if ([string]::IsNullOrWhiteSpace($requestedTicketId)) {
                try { $requestedTicketId = ([string]($script:TicketsActiveTicketId + "")).Trim() } catch { $requestedTicketId = "" }
            }
            if ([string]::IsNullOrWhiteSpace($requestedTicketId) -or [string]::IsNullOrWhiteSpace($requestedNoteId)) { return }

            try { & $replySendWriteLogCmd ("Tickets: Delete note clicked with NoteId='{0}' TicketId='{1}'." -f $requestedNoteId, $requestedTicketId) } catch { }
            $localRemoved = 0
            try { $localRemoved = [int](Remove-QOTicketsLocalInternalNote -TicketId $requestedTicketId -NoteId $requestedNoteId -Ticket $ticket) } catch { $localRemoved = 0 }
            try { & $replySendWriteLogCmd ("Tickets: Delete note local update. TicketId='{0}' NoteId='{1}' Removed={2}." -f $requestedTicketId, $requestedNoteId, $localRemoved) } catch { }
            try {
                if ($ticket) {
                    Update-QOTicketDisplayFields -Tickets @($ticket)
                    if ($grid) { $grid.Items.Refresh() }
                }
            } catch { }
            try {
                if ($ticket -and (Test-QOTicketDetailsViewActive -TicketId $requestedTicketId)) {
                    & $queueLightweightDetailsRefresh $ticket
                }
            } catch { }

            $deleteNoteSuccessHandler = {
                param($result)
                $removed = $false
                try { if ($result -and ($result.PSObject.Properties.Name -contains "Removed")) { $removed = [bool]$result.Removed } } catch { $removed = $false }
                try { & $replySendWriteLogCmd ("Tickets: Delete/retry persistence success. Action='delete-note' TicketId='{0}' NoteId='{1}' Removed={2}." -f $requestedTicketId, $requestedNoteId, $removed) } catch { }
                try {
                    if ($ticket -and (Test-QOTicketDetailsViewActive -TicketId $requestedTicketId)) {
                        & $queueLightweightDetailsRefresh $ticket
                    }
                } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message "Internal note deleted." -DurationMilliseconds 1800 } catch { }
            }.GetNewClosure()
            $deleteNoteFailureHandler = {
                param($result)
                $failureText = "Internal note could not be deleted."
                try { if ($result -and ($result.PSObject.Properties.Name -contains "Note")) { $failureText = ([string]($result.Note + "")).Trim() } } catch { $failureText = "Internal note could not be deleted." }
                try { & $replySendWriteLogCmd ("Tickets: Delete/retry persistence failure. Action='delete-note' TicketId='{0}' NoteId='{1}' Note='{2}'." -f $requestedTicketId, $requestedNoteId, $failureText) "WARN" } catch { }
                try {
                    if ($ticket -and (Test-QOTicketDetailsViewActive -TicketId $requestedTicketId)) {
                        & $queueLightweightDetailsRefresh $ticket
                    }
                } catch { }
                try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message $failureText -DurationMilliseconds 2200 } catch { }
            }.GetNewClosure()

            $deleteNoteAction = & $startBackgroundTicketAction -ActionName "delete-note" -Payload @{
                TicketId = $requestedTicketId
                NoteId   = $requestedNoteId
            } -OnSuccess $deleteNoteSuccessHandler -OnFailure $deleteNoteFailureHandler -TimeoutSeconds 60 -LogLabel "note delete"

            if (-not $deleteNoteAction) {
                try { & $replySendWriteLogCmd ("Tickets: Delete/retry persistence failure. Action='delete-note' TicketId='{0}' NoteId='{1}' Note='Runner did not start'." -f $requestedTicketId, $requestedNoteId) "WARN" } catch { }
            }
        } catch {
            try { & $replySendWriteLogCmd ("Tickets: Delete internal note action failed: " + $_.Exception.Message) "WARN" } catch { }
            try { & $replySendOpenPulseCmd -StatusText $syncStatusText -Message ([string]$_.Exception.Message) -DurationMilliseconds 2200 } catch { }
        }
    }.GetNewClosure()

    # New ticket handler typed
    $script:TicketsNewHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $availableSenderMailboxes = @(& $getConfiguredSenderMailboxes)
            $dialog = New-Object System.Windows.Window
            $dialog.Title = "New ticket"
            $dialog.Width = 420
            $dialog.Height = 620
            $dialog.WindowStartupLocation = "CenterOwner"
            $dialog.ResizeMode = "NoResize"
            $dialog.Owner = $Window

            $stack = New-Object System.Windows.Controls.StackPanel
            $stack.Margin = "12"

            $nameLabel = New-Object System.Windows.Controls.TextBlock
            $nameLabel.Text = "Ticket title"
            $nameLabel.Margin = "0,0,0,4"
            $stack.Children.Add($nameLabel) | Out-Null

            $nameBox = New-Object System.Windows.Controls.TextBox
            $nameBox.Margin = "0,0,0,8"
            $stack.Children.Add($nameBox) | Out-Null

            $priorityLabel = New-Object System.Windows.Controls.TextBlock
            $priorityLabel.Text = "Priority"
            $priorityLabel.Margin = "0,0,0,4"
            $stack.Children.Add($priorityLabel) | Out-Null

            $priorityBox = New-Object System.Windows.Controls.ComboBox
            $priorityBox.Margin = "0,0,0,8"
            foreach ($priority in @($priorityMenuItems)) {
                $priorityBox.Items.Add($priority) | Out-Null
            }
            $priorityBox.SelectedIndex = 1
            $stack.Children.Add($priorityBox) | Out-Null

            $statusLabel = New-Object System.Windows.Controls.TextBlock
            $statusLabel.Text = "Status"
            $statusLabel.Margin = "0,0,0,4"
            $stack.Children.Add($statusLabel) | Out-Null

            $statusBox = New-Object System.Windows.Controls.ComboBox
            $statusBox.Margin = "0,0,0,8"
            foreach ($status in @($statusMenuItems)) {
                $statusBox.Items.Add($status) | Out-Null
            }
            $statusBox.SelectedIndex = 0
            $stack.Children.Add($statusBox) | Out-Null

            $assignedLabel = New-Object System.Windows.Controls.TextBlock
            $assignedLabel.Text = "Assigned to"
            $assignedLabel.Margin = "0,0,0,4"
            $stack.Children.Add($assignedLabel) | Out-Null

            $assignedBox = New-Object System.Windows.Controls.TextBox
            $assignedBox.Margin = "0,0,0,8"
            $assignedBox.Text = "Unassigned"
            $stack.Children.Add($assignedBox) | Out-Null

            $noteLabel = New-Object System.Windows.Controls.TextBlock
            $noteLabel.Text = "Initial note (optional)"
            $noteLabel.Margin = "0,0,0,4"
            $stack.Children.Add($noteLabel) | Out-Null

            $noteBox = New-Object System.Windows.Controls.TextBox
            $noteBox.Height = 90
            $noteBox.AcceptsReturn = $true
            $noteBox.TextWrapping = "Wrap"
            $noteBox.Margin = "0,0,0,12"
            $stack.Children.Add($noteBox) | Out-Null

            $emailToggle = New-Object System.Windows.Controls.CheckBox
            $emailToggle.Content = "Send email from this ticket now"
            $emailToggle.Margin = "0,0,0,8"
            $stack.Children.Add($emailToggle) | Out-Null

            $emailHint = New-Object System.Windows.Controls.TextBlock
            $emailHint.Text = "Uses the ticket title as the email subject."
            $emailHint.Margin = "0,0,0,8"
            $emailHint.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#9CA3AF")
            $emailHint.TextWrapping = "Wrap"
            $stack.Children.Add($emailHint) | Out-Null

            $customerEmailLabel = New-Object System.Windows.Controls.TextBlock
            $customerEmailLabel.Text = "Customer email"
            $customerEmailLabel.Margin = "0,0,0,4"
            $stack.Children.Add($customerEmailLabel) | Out-Null

            $customerEmailBox = New-Object System.Windows.Controls.TextBox
            $customerEmailBox.Margin = "0,0,0,8"
            $stack.Children.Add($customerEmailBox) | Out-Null

            $senderMailboxLabel = New-Object System.Windows.Controls.TextBlock
            $senderMailboxLabel.Text = "Send from mailbox"
            $senderMailboxLabel.Margin = "0,0,0,4"
            $stack.Children.Add($senderMailboxLabel) | Out-Null

            $senderMailboxBox = New-Object System.Windows.Controls.ComboBox
            $senderMailboxBox.Margin = "0,0,0,8"
            foreach ($mailbox in @($availableSenderMailboxes)) {
                $senderMailboxBox.Items.Add([string]$mailbox) | Out-Null
            }
            if ($senderMailboxBox.Items.Count -gt 0) {
                $senderMailboxBox.SelectedIndex = 0
            }
            $stack.Children.Add($senderMailboxBox) | Out-Null

            $emailBodyLabel = New-Object System.Windows.Controls.TextBlock
            $emailBodyLabel.Text = "Email message"
            $emailBodyLabel.Margin = "0,0,0,4"
            $stack.Children.Add($emailBodyLabel) | Out-Null

            $emailBodyBox = New-Object System.Windows.Controls.TextBox
            $emailBodyBox.Height = 110
            $emailBodyBox.AcceptsReturn = $true
            $emailBodyBox.TextWrapping = "Wrap"
            $emailBodyBox.Margin = "0,0,0,12"
            $stack.Children.Add($emailBodyBox) | Out-Null

            $toggleEmailFields = {
                $isEnabled = $false
                try { $isEnabled = [bool]$emailToggle.IsChecked } catch { $isEnabled = $false }
                foreach ($control in @($emailHint, $customerEmailLabel, $customerEmailBox, $senderMailboxLabel, $senderMailboxBox, $emailBodyLabel, $emailBodyBox)) {
                    if (-not $control) { continue }
                    try {
                        $control.IsEnabled = $isEnabled
                        $control.Opacity = if ($isEnabled) { 1.0 } else { 0.55 }
                    } catch { }
                }
            }.GetNewClosure()

            $emailToggle.Add_Click($toggleEmailFields)
            & $toggleEmailFields

            $buttonsPanel = New-Object System.Windows.Controls.StackPanel
            $buttonsPanel.Orientation = "Horizontal"
            $buttonsPanel.HorizontalAlignment = "Right"

            $btnCreate = New-Object System.Windows.Controls.Button
            $btnCreate.Content = "Create"
            $btnCreate.Width = 80
            $btnCreate.Margin = "0,0,8,0"
            $buttonsPanel.Children.Add($btnCreate) | Out-Null

            $btnCancel = New-Object System.Windows.Controls.Button
            $btnCancel.Content = "Cancel"
            $btnCancel.Width = 80
            $buttonsPanel.Children.Add($btnCancel) | Out-Null

            $stack.Children.Add($buttonsPanel) | Out-Null
            $dialog.Content = $stack

            $btnCancel.Add_Click({ $dialog.DialogResult = $false })
            $btnCreate.Add_Click({ $dialog.DialogResult = $true })

            $result = $dialog.ShowDialog()
            if (-not $result) { return }

            $ticketName = ([string]$nameBox.Text).Trim()
            if (-not $ticketName) {
                [System.Windows.MessageBox]::Show(
                    "Ticket title is required.",
                    "Validation",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                return
            }

            $priorityValue = "Medium"
            if ($priorityBox.SelectedItem) {
                $priorityValue = [string]$priorityBox.SelectedItem
            }

            $statusValue = "New"
            if ($statusBox.SelectedItem) {
                $statusValue = [string]$statusBox.SelectedItem
            }

            $assignedToValue = ([string]$assignedBox.Text).Trim()
            if (-not $assignedToValue) { $assignedToValue = "Unassigned" }

            $initialNote = ([string]$noteBox.Text).Trim()
            $sendEmailNow = $false
            try { $sendEmailNow = [bool]$emailToggle.IsChecked } catch { $sendEmailNow = $false }
            $customerEmail = ([string]($customerEmailBox.Text + "")).Trim()
            $senderMailbox = ""
            try {
                if ($senderMailboxBox.SelectedItem) {
                    $senderMailbox = ([string]($senderMailboxBox.SelectedItem + "")).Trim()
                }
            } catch { $senderMailbox = "" }
            $emailBody = ([string]($emailBodyBox.Text + "")).Trim()

            if ($sendEmailNow) {
                if ([string]::IsNullOrWhiteSpace($customerEmail)) {
                    [System.Windows.MessageBox]::Show(
                        "Enter the customer email address before sending.",
                        "Validation",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    ) | Out-Null
                    return
                }

                if ([string]::IsNullOrWhiteSpace($senderMailbox)) {
                    [System.Windows.MessageBox]::Show(
                        "Add at least one monitored mailbox in Settings, then choose which mailbox should send this email.",
                        "Validation",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    ) | Out-Null
                    return
                }

                if ([string]::IsNullOrWhiteSpace($emailBody)) {
                    [System.Windows.MessageBox]::Show(
                        "Enter the email message before sending.",
                        "Validation",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    ) | Out-Null
                    return
                }
            }

            $newTicketParams = @{
                Title       = $ticketName
                TicketName  = $ticketName
                Subject     = $ticketName
                Priority    = $priorityValue
                AssignedTo  = $assignedToValue
                Status      = $statusValue
                InitialNote = $initialNote
            }
            if (-not [string]::IsNullOrWhiteSpace($customerEmail)) {
                $newTicketParams.EmailTo = $customerEmail
                $newTicketParams.EmailFrom = $customerEmail
                $newTicketParams.SenderEmail = $customerEmail
            }
            if (-not [string]::IsNullOrWhiteSpace($senderMailbox)) {
                $newTicketParams.SourceMailbox = $senderMailbox
            }

            $ticket = & $newTicketCmd @newTicketParams
            $null   = & $addTicketCmd -Ticket $ticket

            & $invokeGridRefresh

            $selectedTicket = $ticket
            try {
                $selectedTicket = @(
                    @($grid.ItemsSource) |
                        Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") -and ([string]$_.Id -eq [string]$ticket.Id) } |
                        Select-Object -First 1
                )
                if ($selectedTicket -is [System.Array]) {
                    if ($selectedTicket.Count -gt 0) { $selectedTicket = $selectedTicket[0] } else { $selectedTicket = $ticket }
                }
            } catch { $selectedTicket = $ticket }

            $grid.SelectedItem = $selectedTicket
            $grid.ScrollIntoView($selectedTicket)

            if ($sendEmailNow -and $selectedTicket) {
                try { & $invokeDetailsUpdate $selectedTicket } catch { }
                try { & $setComposeMode -Mode "Reply" -PreserveText:$false -SkipFocus } catch { }
                try { if ($ticketReplySubject) { $ticketReplySubject.Text = $ticketName } } catch { }
                try { if ($ticketReplyText) { $ticketReplyText.Text = $emailBody } } catch { }
                try {
                    if ($script:TicketsSendReplyHandler) {
                        $script:TicketsSendReplyHandler.Invoke($btnSendReply, [System.Windows.RoutedEventArgs]::new())
                    }
                } catch {
                    [System.Windows.MessageBox]::Show(
                        ("Ticket created, but the email send could not start: " + $_.Exception.Message),
                        "Email send failed",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    ) | Out-Null
                }
                return
            }

            if ($grid.Columns.Count -gt 0) {
                $grid.CurrentCell = New-Object System.Windows.Controls.DataGridCellInfo($selectedTicket, $grid.Columns[0])
                $grid.BeginEdit()
            }
        }
        catch {
            Write-QOTicketsUILog ("Create ticket failed: " + $_.Exception.Message) "ERROR"
        }
    }.GetNewClosure()
    $btnNew.Add_Click($script:TicketsNewHandler)

    # Delete handler typed
    $script:TicketsDeleteHandler = [System.Windows.RoutedEventHandler]{
        param($sender, $args)
        try {
            $selectedItems = @($grid.SelectedItems)
            if ($selectedItems.Count -eq 0) { return }

            $ids = @(
                $selectedItems |
                    Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "Id") } |
                    ForEach-Object { $_.Id }
            )
            if ($ids.Count -eq 0) { return }

            $confirmText = if ($ids.Count -gt 1) {
                "Move {0} tickets to Deleted?" -f $ids.Count
            } else {
                "Move this ticket to Deleted?"
            }

            $confirm = [System.Windows.MessageBox]::Show($confirmText, "Confirm", "YesNo", "Warning")
            if ($confirm -ne "Yes") { return }

            $null = & $removeCmd -Id $ids
            & $invokeGridRefresh
        }
        catch { }
    }.GetNewClosure()
    $btnDelete.Add_Click($script:TicketsDeleteHandler)


    Write-QOTicketsUILog "Tickets: Initial grid refresh start."
    & $invokeGridRefresh
    Write-QOTicketsUILog "Tickets: Initial grid refresh end."
    Start-QOTicketsStoreAutoRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -GetStorePathCmd $getStorePathCmd -RefreshCmd $invokeGridRefreshCmd
    try {
        if ($initializeReplyQueueServiceCmd) {
            $replyQueueState = & $initializeReplyQueueServiceCmd -Reason "tickets-ui-startup"
            $activeReplyCount = 0
            try { if ($replyQueueState -and ($replyQueueState.PSObject.Properties.Name -contains "ActiveCount")) { $activeReplyCount = [int]$replyQueueState.ActiveCount } } catch { $activeReplyCount = 0 }
            if ($activeReplyCount -gt 0) {
                try { Write-QOTicketsUILog ("Tickets: Rehydrated {0} persisted pending replies into the background queue service." -f $activeReplyCount) } catch { }
            }
        }
    } catch { }

    Set-QOTicketsSyncStatus -StatusText $syncStatusText -Message "Checking Outlook for ticket sync..."
    Write-QOTicketsUILog "Tickets: Starting auto sync worker and initial sync pass."
    Start-QOTicketsAutoSyncWorker -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusText $syncStatusText
    if (-not $syncCmd) {
        Write-QOTicketsUILog "Tickets: Sync command unavailable at startup; auto-sync worker will retry command discovery." "WARN"
    }
    elseif (Test-QOTicketsHasRecentSuccessfulSync) {
        Write-QOTicketsUILog "Tickets: Skipping immediate startup sync because a successful sync just completed during intro."
        Set-QOTicketsSyncStatus -StatusText $syncStatusText -Message (Get-QOTicketsLastSuccessfulSyncLabel)
    }
    else {
        Invoke-QOTicketsEmailSyncAndRefresh -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusText $syncStatusText
    }

    # Setup clickable sync status - allow user to manually trigger sync
    try {
        if ($syncStatusText) {
            $syncStatusText.Cursor = [System.Windows.Input.Cursors]::Hand
            $syncStatusText.add_MouseLeftButtonDown({
                try {
                    if ($script:TicketsEmailSyncInProgress) {
                        Write-QOTicketsUILog "Tickets: Sync already in progress; ignoring manual sync click."
                        return
                    }
                    Write-QOTicketsUILog "Tickets: Manual email sync triggered via status text click."
                    if ($syncCmd) {
                        & $invokeEmailSyncRefreshCmd -Grid $grid -GetTicketsCmd $getTicketsCmd -SyncCmd $syncCmd -StatusText $syncStatusText
                    } else {
                        Write-QOTicketsUILog "Tickets: Sync command not available for manual sync." "WARN"
                    }
                } catch {
                    Write-QOTicketsUILog ("Tickets: Error handling sync status click: " + $_.Exception.Message) "WARN"
                }
            })
        }
    } catch {
        Write-QOTicketsUILog ("Tickets: Failed to setup clickable sync status: " + $_.Exception.Message) "WARN"
    }

    Write-QOTicketsUILog "Tickets: Initialize-QOTicketsUI completed."
}

function Resolve-QOTTicketDetailsSourceTicket {
    param(
        [AllowNull()]$Ticket
    )

    if (-not $Ticket) { return $null }

    $getTextValue = $null
    $getTextValue = {
        param(
            [AllowNull()]$Source,
            [string[]]$PropertyNames
        )

        if (-not $Source) { return "" }
        foreach ($propertyName in @($PropertyNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            try {
                if ($Source.PSObject.Properties.Name -contains $propertyName) {
                    $value = ([string]($Source.$propertyName + "")).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
                }
            } catch { }
        }
        foreach ($nestedProperty in @("Ticket", "SourceTicket", "SelectedTicket")) {
            try {
                if ($Source.PSObject.Properties.Name -contains $nestedProperty) {
                    $nestedValue = (& $getTextValue -Source $Source.$nestedProperty -PropertyNames $PropertyNames)
                    if (-not [string]::IsNullOrWhiteSpace($nestedValue)) { return $nestedValue }
                }
            } catch { }
        }
        return ""
    }.GetNewClosure()

    $getIdValue = {
        param([AllowNull()]$Source)
        return [string](& $getTextValue -Source $Source -PropertyNames @("Id", "TicketId", "SelectedTicketId"))
    }.GetNewClosure()

    $getSubjectValue = {
        param([AllowNull()]$Source)
        return [string](& $getTextValue -Source $Source -PropertyNames @("Subject", "Title", "TicketName"))
    }.GetNewClosure()

    $normalizeThreadKeyValue = {
        param([AllowNull()][string]$Subject)
        $value = ([string]($Subject + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) { return "" }
        $value = ($value -replace '[\r\n]+', ' ').Trim()
        for ($i = 0; $i -lt 6; $i++) {
            $next = ($value -replace '^(?i)\s*((RE|FW|FWD)\s*:\s*)+', '').Trim()
            if ($next -eq $value) { break }
            $value = $next
        }
        return (($value -replace '\s+', ' ').Trim().ToLowerInvariant())
    }.GetNewClosure()

    $getSortTicks = {
        param([AllowNull()]$Source)
        foreach ($dateProp in @("UpdatedAt", "CreatedAt")) {
            try {
                if ($Source -and ($Source.PSObject.Properties.Name -contains $dateProp)) {
                    $parsed = [datetime]::MinValue
                    if ([datetime]::TryParse(([string]($Source.$dateProp + "")).Trim(), [ref]$parsed)) {
                        return [int64]$parsed.Ticks
                    }
                }
            } catch { }
        }
        return 0L
    }.GetNewClosure()

    $countListItems = {
        param(
            [AllowNull()]$Source,
            [string[]]$PropertyNames
        )
        if (-not $Source) { return 0 }
        $count = 0
        foreach ($propertyName in @($PropertyNames)) {
            try {
                if ($Source.PSObject.Properties.Name -contains $propertyName) {
                    $count += @($Source.$propertyName | Where-Object { $_ }).Count
                }
            } catch { }
        }
        return $count
    }.GetNewClosure()

    $ticketId = [string](& $getIdValue -Source $Ticket)
    $inputSubject = [string](& $getSubjectValue -Source $Ticket)
    $inputThreadKey = [string](& $normalizeThreadKeyValue -Subject $inputSubject)
    $inputEmailMessageId = [string](& $getTextValue -Source $Ticket -PropertyNames @("EmailMessageId", "InternetMessageId", "MessageId"))
    $inputSourceMessageId = [string](& $getTextValue -Source $Ticket -PropertyNames @("SourceMessageId", "OutlookEntryId", "EntryId"))
    $inputBodyPath = [string](& $getTextValue -Source $Ticket -PropertyNames @("EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath", "PreviewPath"))
    $inputPreview = [string](& $getTextValue -Source $Ticket -PropertyNames @("EmailBodyPreview", "BodyPreview", "Preview"))
    $inputSender = [string](& $getTextValue -Source $Ticket -PropertyNames @("EmailFrom", "SenderEmail", "SenderName", "From", "Sender"))

    $getCandidateScore = {
        param([AllowNull()]$Candidate)

        if (-not $Candidate) { return -1 }

        $score = 0
        $candidateId = [string](& $getIdValue -Source $Candidate)
        $candidateSubject = [string](& $getSubjectValue -Source $Candidate)
        $candidateThreadKey = [string](& $normalizeThreadKeyValue -Subject $candidateSubject)
        $candidateEmailMessageId = [string](& $getTextValue -Source $Candidate -PropertyNames @("EmailMessageId", "InternetMessageId", "MessageId"))
        $candidateSourceMessageId = [string](& $getTextValue -Source $Candidate -PropertyNames @("SourceMessageId", "OutlookEntryId", "EntryId"))
        $candidateBodyPath = [string](& $getTextValue -Source $Candidate -PropertyNames @("EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath", "PreviewPath"))
        $candidatePreview = [string](& $getTextValue -Source $Candidate -PropertyNames @("EmailBodyPreview", "BodyPreview", "Preview"))
        $candidateSender = [string](& $getTextValue -Source $Candidate -PropertyNames @("EmailFrom", "SenderEmail", "SenderName", "From", "Sender"))

        if ((-not [string]::IsNullOrWhiteSpace($ticketId)) -and [string]::Equals($candidateId, $ticketId, [System.StringComparison]::OrdinalIgnoreCase)) { $score += 5000 }
        if ((-not [string]::IsNullOrWhiteSpace($inputEmailMessageId)) -and [string]::Equals($candidateEmailMessageId, $inputEmailMessageId, [System.StringComparison]::OrdinalIgnoreCase)) { $score += 4000 }
        if ((-not [string]::IsNullOrWhiteSpace($inputSourceMessageId)) -and [string]::Equals($candidateSourceMessageId, $inputSourceMessageId, [System.StringComparison]::OrdinalIgnoreCase)) { $score += 4000 }
        if ((-not [string]::IsNullOrWhiteSpace($inputBodyPath)) -and [string]::Equals($candidateBodyPath, $inputBodyPath, [System.StringComparison]::OrdinalIgnoreCase)) { $score += 3000 }
        if ((-not [string]::IsNullOrWhiteSpace($inputThreadKey)) -and [string]::Equals($candidateThreadKey, $inputThreadKey, [System.StringComparison]::OrdinalIgnoreCase)) { $score += 400 }
        if ((-not [string]::IsNullOrWhiteSpace($inputSender)) -and (-not [string]::IsNullOrWhiteSpace($candidateSender)) -and [string]::Equals($candidateSender, $inputSender, [System.StringComparison]::OrdinalIgnoreCase)) { $score += 250 }

        if ((-not [string]::IsNullOrWhiteSpace($inputPreview)) -and (-not [string]::IsNullOrWhiteSpace($candidatePreview))) {
            $prefixLength = [Math]::Min([Math]::Min($inputPreview.Length, $candidatePreview.Length), 120)
            if ($prefixLength -ge 24) {
                $inputPreviewPrefix = $inputPreview.Substring(0, $prefixLength)
                $candidatePreviewPrefix = $candidatePreview.Substring(0, $prefixLength)
                if ([string]::Equals($candidatePreviewPrefix, $inputPreviewPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $score += 1200
                }
            }
        }

        foreach ($textProp in @("SenderName", "SenderEmail", "EmailFrom", "EmailBody", "Body", "HtmlBody", "TextBody", "Preview", "EmailBodyPreview", "BodyPreview")) {
            $value = [string](& $getTextValue -Source $Candidate -PropertyNames @($textProp))
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $score += [Math]::Min($value.Length, 200)
            }
        }
        foreach ($pathProp in @("EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath", "PreviewPath")) {
            $value = [string](& $getTextValue -Source $Candidate -PropertyNames @($pathProp))
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $score += 150
            }
        }

        $score += ((& $countListItems -Source $Candidate -PropertyNames @("IncomingMessages", "Replies", "Notes", "PendingReplies", "Messages", "History", "Conversation", "SentReplies", "InternalNotes", "SystemEvents", "Events", "Timeline", "Activity", "AuditTrail")) * 25)
        return $score
    }.GetNewClosure()

    $choosePreferredTicket = {
        param(
            [AllowNull()]$Current,
            [AllowNull()]$Candidate
        )
        if (-not $Candidate) { return $Current }
        if (-not $Current) { return $Candidate }
        $currentScore = & $getCandidateScore -Candidate $Current
        $candidateScore = & $getCandidateScore -Candidate $Candidate
        if ($candidateScore -gt $currentScore) { return $Candidate }
        if ($candidateScore -lt $currentScore) { return $Current }
        if ((& $getSortTicks -Source $Candidate) -gt (& $getSortTicks -Source $Current)) { return $Candidate }
        return $Current
    }.GetNewClosure()

    $inputScore = & $getCandidateScore -Candidate $Ticket

    $logResolvedTicket = {
        param(
            [AllowNull()]$ResolvedTicket,
            [string]$Reason
        )
        if (-not $ResolvedTicket) { return }
        try {
            $bodyInfo = Get-QOTicketDisplayBodyInfo -Ticket $ResolvedTicket
            Write-QOTicketsUILog ("Tickets: Ticket load body detected. Reason={0}; TicketId={1}; Subject={2}; Source={3}; Property={4}; Length={5}; InputSubject={6}; InputMessageId={7}; InputSourceMessageId={8}" -f `
                $Reason, `
                ([string](& $getIdValue -Source $ResolvedTicket)), `
                ([string](& $getSubjectValue -Source $ResolvedTicket)), `
                $bodyInfo.Source, `
                $bodyInfo.Property, `
                $bodyInfo.Length, `
                $inputSubject, `
                $inputEmailMessageId, `
                $inputSourceMessageId)
        } catch { }
    }.GetNewClosure()

    $findBestMatchInItems = {
        param([AllowNull()][object[]]$Items)

        $exactMatch = $null
        $threadMatch = $null
        $bestOverall = $null

        foreach ($candidate in @($Items | Where-Object { $_ })) {
            $bestOverall = & $choosePreferredTicket -Current $bestOverall -Candidate $candidate

            $candidateId = [string](& $getIdValue -Source $candidate)
            $candidateEmailMessageId = [string](& $getTextValue -Source $candidate -PropertyNames @("EmailMessageId", "InternetMessageId", "MessageId"))
            $candidateSourceMessageId = [string](& $getTextValue -Source $candidate -PropertyNames @("SourceMessageId", "OutlookEntryId", "EntryId"))
            $candidateBodyPath = [string](& $getTextValue -Source $candidate -PropertyNames @("EmailBodyPath", "BodyPath", "HtmlBodyPath", "TextBodyPath", "PreviewPath"))

            $isExact = $false
            if ((-not [string]::IsNullOrWhiteSpace($ticketId)) -and [string]::Equals($candidateId, $ticketId, [System.StringComparison]::OrdinalIgnoreCase)) { $isExact = $true }
            if ((-not $isExact) -and (-not [string]::IsNullOrWhiteSpace($inputEmailMessageId)) -and [string]::Equals($candidateEmailMessageId, $inputEmailMessageId, [System.StringComparison]::OrdinalIgnoreCase)) { $isExact = $true }
            if ((-not $isExact) -and (-not [string]::IsNullOrWhiteSpace($inputSourceMessageId)) -and [string]::Equals($candidateSourceMessageId, $inputSourceMessageId, [System.StringComparison]::OrdinalIgnoreCase)) { $isExact = $true }
            if ((-not $isExact) -and (-not [string]::IsNullOrWhiteSpace($inputBodyPath)) -and [string]::Equals($candidateBodyPath, $inputBodyPath, [System.StringComparison]::OrdinalIgnoreCase)) { $isExact = $true }

            if ($isExact) {
                $exactMatch = & $choosePreferredTicket -Current $exactMatch -Candidate $candidate
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($inputThreadKey)) {
                $candidateThreadKey = [string](& $normalizeThreadKeyValue -Subject (& $getSubjectValue -Source $candidate))
                if ([string]::Equals($candidateThreadKey, $inputThreadKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $threadMatch = & $choosePreferredTicket -Current $threadMatch -Candidate $candidate
                }
            }
        }

        return [pscustomobject]@{
            ExactMatch  = $exactMatch
            ThreadMatch = $threadMatch
            BestOverall = $bestOverall
        }
    }.GetNewClosure()

    try {
        $getTicketsCmd = Resolve-QOTicketsCoreCommand -CommandName "Get-QOTickets"
        if ($getTicketsCmd) {
            $dbLatest = & $getTicketsCmd -Quiet
            if ($dbLatest) {
                $allTickets = @()
                if ($dbLatest.PSObject.Properties.Name -contains "Tickets") {
                    $allTickets = @($dbLatest.Tickets)
                } else {
                    $allTickets = @($dbLatest)
                }
                try { $script:AllTickets = @($allTickets) } catch { }

                $resolvedResults = & $findBestMatchInItems -Items $allTickets
                if ($resolvedResults -and $resolvedResults.ExactMatch) {
                    & $logResolvedTicket -ResolvedTicket $resolvedResults.ExactMatch -Reason "StoreExact"
                    return $resolvedResults.ExactMatch
                }
                if ($resolvedResults -and $resolvedResults.BestOverall -and ((& $getCandidateScore -Candidate $resolvedResults.BestOverall) -gt $inputScore)) {
                    & $logResolvedTicket -ResolvedTicket $resolvedResults.BestOverall -Reason "StoreBest"
                    return $resolvedResults.BestOverall
                }
                if ($resolvedResults -and $resolvedResults.ThreadMatch -and ((& $getCandidateScore -Candidate $resolvedResults.ThreadMatch) -gt $inputScore)) {
                    & $logResolvedTicket -ResolvedTicket $resolvedResults.ThreadMatch -Reason "StoreThread"
                    return $resolvedResults.ThreadMatch
                }
            }
        }
    } catch { }

    try {
        $visibleResults = & $findBestMatchInItems -Items @($script:AllTickets)
        if ($visibleResults -and $visibleResults.ExactMatch) {
            & $logResolvedTicket -ResolvedTicket $visibleResults.ExactMatch -Reason "VisibleExact"
            return $visibleResults.ExactMatch
        }
        if ($visibleResults -and $visibleResults.BestOverall -and ((& $getCandidateScore -Candidate $visibleResults.BestOverall) -gt $inputScore)) {
            & $logResolvedTicket -ResolvedTicket $visibleResults.BestOverall -Reason "VisibleBest"
            return $visibleResults.BestOverall
        }
        if ($visibleResults -and $visibleResults.ThreadMatch -and ((& $getCandidateScore -Candidate $visibleResults.ThreadMatch) -gt $inputScore)) {
            & $logResolvedTicket -ResolvedTicket $visibleResults.ThreadMatch -Reason "VisibleThread"
            return $visibleResults.ThreadMatch
        }
    } catch { }

    return $Ticket
}

Export-ModuleMember -Function Write-QOTicketsUILog, Initialize-QOTicketsUI, Invoke-QOTicketsFilterSafely, Invoke-QOTicketsEmailSyncAndRefresh, Start-TicketsEmailSyncAsync, Invoke-QOTicketStatusChangeForItems, Invoke-QOTicketAssigneeChangeForItems, Invoke-QOTicketPriorityChangeForItems, Set-QOTicketsSyncStatus, Resolve-QOTInvokable, Update-QOTicketDetailsView, Get-QOTTicketDetailsRenderModel, Get-QOTTicketDetailsBodyText, Resolve-QOTTicketDetailsSourceTicket, Get-QOTicketDisplayBodyInfo, Get-QOTicketPreferredSubject, Get-QOTicketPropertyTextValue, Normalize-QOTTicketThreadKey, Set-QOTicketDetailsBodyContent, Set-QOTicketContactHeader, Get-QOTicketLogLabel, Get-QOTicketIdValue

