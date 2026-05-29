# src\Core\Settings.psm1
# Quinn Optimiser Toolkit - Settings module
# Handles global JSON settings for the app

$ErrorActionPreference = "Stop"

# Always save to THIS path (resolved lazily)
$script:SettingsPath = $null
$script:QOAppDataRoot = $null

function Test-QOPathWritable {
    param(
        [AllowNull()][string]$Path
    )

    $candidatePath = ([string]($Path + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($candidatePath)) { return $false }

    try {
        if (-not (Test-Path -LiteralPath $candidatePath)) {
            New-Item -ItemType Directory -Path $candidatePath -Force | Out-Null
        }

        $probePath = Join-Path $candidatePath (".qot-write-test-{0}.tmp" -f [guid]::NewGuid().ToString("N"))
        [System.IO.File]::WriteAllText($probePath, "")
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

function Get-QOAppDataRoot {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:QOAppDataRoot)) {
        return [string]$script:QOAppDataRoot
    }

    $candidates = @(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),
        $env:LOCALAPPDATA,
        $env:APPDATA,
        $env:USERPROFILE
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        $probeRoot = Join-Path ([string]$candidate) "QuinnOptimiserToolkit"
        if (Test-QOPathWritable -Path $probeRoot) {
            $script:QOAppDataRoot = [string](Join-Path ([string]$candidate) "QuinnOptimiserToolkit")
            return [string]$script:QOAppDataRoot
        }
    }

    $fallbackRoot = [System.IO.Path]::GetTempPath()
    if (-not [string]::IsNullOrWhiteSpace([string]$fallbackRoot)) {
        try { $fallbackRoot = [System.IO.Path]::GetFullPath($fallbackRoot) } catch { }
        $fallbackRoot = $fallbackRoot.TrimEnd('\', '/')
        $probeRoot = Join-Path $fallbackRoot "QuinnOptimiserToolkit"
        if (Test-QOPathWritable -Path $probeRoot) {
            $script:QOAppDataRoot = [string](Join-Path $fallbackRoot "QuinnOptimiserToolkit")
            return [string]$script:QOAppDataRoot
        }
    }

    return [string](Join-Path ([System.IO.Path]::GetTempPath()) "QuinnOptimiserToolkit")
}

function Get-QOSettingsPath {
    $overridePath = ""
    try { $overridePath = [string]([Environment]::GetEnvironmentVariable("QOT_SETTINGS_PATH", "Process") + "") } catch { $overridePath = "" }
    $overridePath = $overridePath.Trim()
    if (-not [string]::IsNullOrWhiteSpace($overridePath)) {
        try { $overridePath = [System.IO.Path]::GetFullPath($overridePath) } catch { }
        $script:SettingsPath = $overridePath
        return $script:SettingsPath
    }

    if (-not $script:SettingsPath) {
        $script:SettingsPath = Join-Path (Get-QOAppDataRoot) "StudioVoly\QuinnToolkit\settings.json"
    }
    return $script:SettingsPath
}

function Save-QOSettings {
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    $path = Get-QOSettingsPath

    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Depth must be high enough for nested structures
    $json = $Settings | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function New-QODefaultSettings {
    param(
        [switch]$NoSave
    )

    $settings = [pscustomobject]@{
        SchemaVersion         = 1
        TicketStorePath       = ""
        LocalTicketBackupPath = ""
        PreferredStartTab     = "Cleaning"
        TaskTimeoutSeconds    = 1800
        InternalProtectionKey = $null
        UiState               = [pscustomobject]@{
            LastSelectedTab = "TabCleaning"
            TabVisibility   = [pscustomobject]@{
                Cleaning = $true
                Apps     = $true
                Advanced = $true
                Tickets  = $true
            }
            ToggleActions  = [pscustomobject]@{}
        }

        TicketsColumnLayout   = @()

        Tickets = [pscustomobject]@{
            EmailIntegration = [pscustomobject]@{
                MonitoredAddresses        = @()

                # If this is null or empty, UI follows today automatically.
                # When pinned, store as yyyy-MM-dd (date only, no time).
                EmailSyncStartDatePinned  = $null

                # UTC watermark for incremental email sync.
                LastSyncUtc               = $null
                # UTC timestamp for the most recent successful sync run.
                LastSuccessfulSyncUtc     = $null
            }
            StatusFilters = [pscustomobject]@{
                New             = $true
                InProgress      = $true
                WaitingOnUser   = $true
                NoLongerRequired = $true
                Completed       = $true
                IncludeDeleted  = $false
            }
            ListView = [pscustomobject]@{
                ShowOpen   = $true
                ShowClosed = $true
                ShowDeleted = $false
                SortMode   = "Priority"
                AssigneeFilter = "All"
            }
        }
    }

    if (-not $NoSave) {
        Save-QOSettings -Settings $settings
    }

    return $settings
}

function Test-QOSettingsIsObject {
    <#
    .SYNOPSIS
    Returns $true if $Value is a non-null PSObject we can safely drill into,
    $false for nulls, strings, numbers, booleans, or anything else that would
    blow up a nested property access.
    .DESCRIPTION
    PowerShell will happily let you read .PSObject.Properties on a string and
    get back the string's runtime properties - which is never what the settings
    merge wants. This guard makes "is this a structured settings sub-object"
    explicit so the merge falls back to defaults instead of corrupting state.
    #>
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return $false }
    if ($Value -is [ValueType]) { return $false }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [System.Management.Automation.PSCustomObject])) { return $false }
    try {
        return ($null -ne $Value.PSObject -and $null -ne $Value.PSObject.Properties)
    } catch {
        return $false
    }
}

function Test-QOSettingsHasProperty {
    <#
    .SYNOPSIS
    Returns $true if $Target is a structured object that has a property named $Name.
    Safe to call on $null, primitives, or anything else - never throws.
    #>
    param([AllowNull()]$Target, [Parameter(Mandatory)][string]$Name)
    if (-not (Test-QOSettingsIsObject -Value $Target)) { return $false }
    try {
        return ($null -ne $Target.PSObject.Properties[$Name])
    } catch {
        return $false
    }
}

function Confirm-QOSettingsNestedObject {
    <#
    .SYNOPSIS
    Ensures $Parent.$Name is a structured object. If it's missing or has been
    corrupted into a primitive value, replaces it with $Default.
    Returns $true if the property now holds a structured object, $false if
    $Parent itself is not even a structured object (caller cannot drill in).
    #>
    param(
        [Parameter(Mandatory)][AllowNull()]$Parent,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Default
    )

    if (-not (Test-QOSettingsIsObject -Value $Parent)) { return $false }

    $hasValid = $false
    try {
        if (Test-QOSettingsHasProperty -Target $Parent -Name $Name) {
            $hasValid = Test-QOSettingsIsObject -Value $Parent.$Name
        }
    } catch { $hasValid = $false }

    if (-not $hasValid) {
        try { $Parent | Add-Member -NotePropertyName $Name -NotePropertyValue $Default -Force } catch { return $false }
    }
    return $true
}

function Get-QOSettings {
    $path = Get-QOSettingsPath
    if (-not (Test-Path -LiteralPath $path)) {
        return New-QODefaultSettings
    }

    try {
        $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return New-QODefaultSettings
        }

        $settings = $json | ConvertFrom-Json -ErrorAction Stop

        # If the JSON root parses as something that is NOT a structured object
        # (e.g. a number, string, or array because the file is corrupt), we
        # cannot meaningfully merge into it - rebuild from defaults.
        if (-not (Test-QOSettingsIsObject -Value $settings)) {
            return New-QODefaultSettings
        }

        # Merge defaults so missing keys get added
        $defaults = New-QODefaultSettings -NoSave

        foreach ($prop in $defaults.PSObject.Properties.Name) {
            if (-not (Test-QOSettingsHasProperty -Target $settings -Name $prop)) {
                $settings | Add-Member -NotePropertyName $prop -NotePropertyValue $defaults.$prop -Force
            }
        }

        # UiState branch - guard every drill before we touch it.
        $null = Confirm-QOSettingsNestedObject -Parent $settings -Name 'UiState' -Default $defaults.UiState
        if (-not (Test-QOSettingsHasProperty -Target $settings.UiState -Name 'LastSelectedTab')) {
            $settings.UiState | Add-Member -NotePropertyName LastSelectedTab -NotePropertyValue $defaults.UiState.LastSelectedTab -Force
        }
        if ([string]::IsNullOrWhiteSpace([string]$settings.UiState.LastSelectedTab)) {
            $settings.UiState.LastSelectedTab = $defaults.UiState.LastSelectedTab
        }
        $null = Confirm-QOSettingsNestedObject -Parent $settings.UiState -Name 'TabVisibility' -Default $defaults.UiState.TabVisibility
        $null = Confirm-QOSettingsNestedObject -Parent $settings.UiState -Name 'ToggleActions' -Default ([pscustomobject]@{})

        if (Test-QOSettingsIsObject -Value $defaults.UiState.TabVisibility) {
            foreach ($prop in $defaults.UiState.TabVisibility.PSObject.Properties.Name) {
                if (-not (Test-QOSettingsHasProperty -Target $settings.UiState.TabVisibility -Name $prop)) {
                    $settings.UiState.TabVisibility | Add-Member -NotePropertyName $prop -NotePropertyValue $defaults.UiState.TabVisibility.$prop -Force
                }
                if ($null -eq $settings.UiState.TabVisibility.$prop) {
                    $settings.UiState.TabVisibility.$prop = $defaults.UiState.TabVisibility.$prop
                }
                $settings.UiState.TabVisibility.$prop = [bool]$settings.UiState.TabVisibility.$prop
            }
        }

        # Ensure nested Tickets structure exists
        $null = Confirm-QOSettingsNestedObject -Parent $settings -Name 'Tickets' -Default $defaults.Tickets
        $null = Confirm-QOSettingsNestedObject -Parent $settings.Tickets -Name 'EmailIntegration' -Default $defaults.Tickets.EmailIntegration
        $null = Confirm-QOSettingsNestedObject -Parent $settings.Tickets -Name 'StatusFilters' -Default $defaults.Tickets.StatusFilters
        $null = Confirm-QOSettingsNestedObject -Parent $settings.Tickets -Name 'ListView' -Default $defaults.Tickets.ListView


        if ($null -eq $settings.Tickets.EmailIntegration.MonitoredAddresses) {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
        }

        if ($null -eq $settings.Tickets.EmailIntegration.EmailSyncStartDatePinned) {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName EmailSyncStartDatePinned -NotePropertyValue $null -Force
        }

        if (-not (Test-QOSettingsHasProperty -Target $settings.Tickets.EmailIntegration -Name 'LastSyncUtc')) {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName LastSyncUtc -NotePropertyValue $null -Force
        }
        if (-not (Test-QOSettingsHasProperty -Target $settings.Tickets.EmailIntegration -Name 'LastSuccessfulSyncUtc')) {
            $settings.Tickets.EmailIntegration | Add-Member -NotePropertyName LastSuccessfulSyncUtc -NotePropertyValue $null -Force
        }

        if (Test-QOSettingsIsObject -Value $defaults.Tickets.StatusFilters) {
            foreach ($prop in $defaults.Tickets.StatusFilters.PSObject.Properties.Name) {
                if (-not (Test-QOSettingsHasProperty -Target $settings.Tickets.StatusFilters -Name $prop)) {
                    $settings.Tickets.StatusFilters | Add-Member -NotePropertyName $prop -NotePropertyValue $defaults.Tickets.StatusFilters.$prop -Force
                }
            }
        }

        if (Test-QOSettingsIsObject -Value $defaults.Tickets.ListView) {
            foreach ($prop in $defaults.Tickets.ListView.PSObject.Properties.Name) {
                if (-not (Test-QOSettingsHasProperty -Target $settings.Tickets.ListView -Name $prop)) {
                    $settings.Tickets.ListView | Add-Member -NotePropertyName $prop -NotePropertyValue $defaults.Tickets.ListView.$prop -Force
                }
            }
        }
        $settings.Tickets.ListView.ShowOpen = [bool]$settings.Tickets.ListView.ShowOpen
        $settings.Tickets.ListView.ShowClosed = [bool]$settings.Tickets.ListView.ShowClosed
        $settings.Tickets.ListView.ShowDeleted = [bool]$settings.Tickets.ListView.ShowDeleted
        $sortModeRaw = ""
        try { $sortModeRaw = ([string]($settings.Tickets.ListView.SortMode + "")).Trim() } catch { $sortModeRaw = "" }
        switch ($sortModeRaw.ToLowerInvariant()) {
            "newest" { $settings.Tickets.ListView.SortMode = "Newest" }
            "oldest" { $settings.Tickets.ListView.SortMode = "Oldest" }
            default { $settings.Tickets.ListView.SortMode = "Priority" }
        }
        $assigneeFilterRaw = ""
        try { $assigneeFilterRaw = ([string]($settings.Tickets.ListView.AssigneeFilter + "")).Trim() } catch { $assigneeFilterRaw = "" }
        if ([string]::IsNullOrWhiteSpace($assigneeFilterRaw)) { $assigneeFilterRaw = "All" }
        if ($assigneeFilterRaw.StartsWith("@")) { $assigneeFilterRaw = $assigneeFilterRaw.TrimStart("@") }
        switch ($assigneeFilterRaw.ToLowerInvariant()) {
            "all" { $assigneeFilterRaw = "All" }
            "unassigned" { $assigneeFilterRaw = "Unassigned" }
            "none" { $assigneeFilterRaw = "Unassigned" }
            "n/a" { $assigneeFilterRaw = "Unassigned" }
            "na" { $assigneeFilterRaw = "Unassigned" }
            "null" { $assigneeFilterRaw = "Unassigned" }
            default { }
        }
        $settings.Tickets.ListView.AssigneeFilter = $assigneeFilterRaw

        $taskTimeoutSeconds = 1800
        try {
            if ($settings.PSObject.Properties.Name -contains "TaskTimeoutSeconds") {
                $taskTimeoutSeconds = [int]$settings.TaskTimeoutSeconds
            }
        } catch { $taskTimeoutSeconds = 1800 }
        if ($taskTimeoutSeconds -lt 300) { $taskTimeoutSeconds = 300 }
        if ($taskTimeoutSeconds -gt 43200) { $taskTimeoutSeconds = 43200 }
        if ($settings.PSObject.Properties.Name -notcontains "TaskTimeoutSeconds") {
            $settings | Add-Member -NotePropertyName TaskTimeoutSeconds -NotePropertyValue $taskTimeoutSeconds -Force
        } else {
            $settings.TaskTimeoutSeconds = $taskTimeoutSeconds
        }


        return $settings
    }
    catch {
        # Backup corrupted file then recreate
        try {
            $backupName = "{0}.bak_{1}" -f $path, (Get-Date -Format "yyyyMMddHHmmss")
            Copy-Item -LiteralPath $path -Destination $backupName -ErrorAction SilentlyContinue
        } catch { }

        return New-QODefaultSettings
    }
}

function Set-QOSetting {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        $Value
    )

    $settings = Get-QOSettings

    if ($settings.PSObject.Properties.Name -notcontains $Name) {
        $settings | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    } else {
        $settings.$Name = $Value
    }

    Save-QOSettings -Settings $settings
    return $settings
}

function Get-QOTicketStorageDefaults {
    $appDataRoot = Get-QOAppDataRoot
    return [pscustomobject]@{
        StorePath  = (Join-Path $appDataRoot "StudioVoly\QuinnToolkit\Tickets\Tickets.json")
        BackupPath = (Join-Path $appDataRoot "StudioVoly\QuinnToolkit\Tickets\Backups")
    }
}

function Resolve-QOTicketStorePath {
    param([AllowNull()][string]$Path)

    $defaults = Get-QOTicketStorageDefaults
    $value = ([string]($Path + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return [string]$defaults.StorePath
    }

    $value = [Environment]::ExpandEnvironmentVariables($value)
    $looksLikeDirectory = $false
    if ($value.EndsWith("\") -or $value.EndsWith("/")) {
        $looksLikeDirectory = $true
    }
    elseif (Test-Path -LiteralPath $value -PathType Container) {
        $looksLikeDirectory = $true
    }
    elseif ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($value))) {
        $looksLikeDirectory = $true
    }

    if ($looksLikeDirectory) {
        $value = Join-Path $value "Tickets.json"
    }
    elseif ([System.IO.Path]::GetExtension($value).ToLowerInvariant() -ne ".json") {
        $value = [System.IO.Path]::ChangeExtension($value, "json")
    }

    try { return [System.IO.Path]::GetFullPath($value) } catch { return $value }
}

function Resolve-QOTicketBackupPath {
    param(
        [AllowNull()][string]$Path,
        [AllowNull()][string]$StorePath
    )

    $defaults = Get-QOTicketStorageDefaults
    $value = ([string]($Path + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return [string]$defaults.BackupPath
    }

    $value = [Environment]::ExpandEnvironmentVariables($value)

    $extension = ""
    try { $extension = [System.IO.Path]::GetExtension($value) } catch { $extension = "" }
    if (-not [string]::IsNullOrWhiteSpace($extension) -and ($extension.ToLowerInvariant() -eq ".json")) {
        $parent = ""
        try { $parent = Split-Path -Parent $value } catch { $parent = "" }
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            $value = Join-Path $parent "Backups"
        }
    }

    try { return [System.IO.Path]::GetFullPath($value) } catch { return $value }
}

function Get-QOTicketStorageSettings {
    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if ($s.PSObject.Properties.Name -notcontains "TicketStorePath") {
        $s | Add-Member -NotePropertyName TicketStorePath -NotePropertyValue "" -Force
    }
    if ($s.PSObject.Properties.Name -notcontains "LocalTicketBackupPath") {
        $s | Add-Member -NotePropertyName LocalTicketBackupPath -NotePropertyValue "" -Force
    }

    $resolvedStorePath = Resolve-QOTicketStorePath -Path ([string]$s.TicketStorePath)
    $resolvedBackupPath = Resolve-QOTicketBackupPath -Path ([string]$s.LocalTicketBackupPath) -StorePath $resolvedStorePath

    return [pscustomobject]@{
        StorePath  = $resolvedStorePath
        BackupPath = $resolvedBackupPath
    }
}

function Set-QOTicketStorageSettings {
    param(
        [AllowNull()][string]$StorePath,
        [AllowNull()][string]$BackupPath
    )

    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    $resolvedStorePath = Resolve-QOTicketStorePath -Path $StorePath
    $resolvedBackupPath = Resolve-QOTicketBackupPath -Path $BackupPath -StorePath $resolvedStorePath

    if ($s.PSObject.Properties.Name -notcontains "TicketStorePath") {
        $s | Add-Member -NotePropertyName TicketStorePath -NotePropertyValue $resolvedStorePath -Force
    } else {
        $s.TicketStorePath = $resolvedStorePath
    }

    if ($s.PSObject.Properties.Name -notcontains "LocalTicketBackupPath") {
        $s | Add-Member -NotePropertyName LocalTicketBackupPath -NotePropertyValue $resolvedBackupPath -Force
    } else {
        $s.LocalTicketBackupPath = $resolvedBackupPath
    }

    Save-QOSettings -Settings $s
    return (Get-QOTicketStorageSettings)
}

# --------------------------------------------------------------------
# Canonical API for monitored mailbox addresses
# Storage: Tickets.EmailIntegration.MonitoredAddresses
# --------------------------------------------------------------------
function Get-QOMonitoredMailboxAddresses {
    $s = Get-QOSettings
    if (-not $s) { return @() }

    $list = @()
    try { $list = @($s.Tickets.EmailIntegration.MonitoredAddresses) } catch { $list = @() }

    return @(
        $list |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique
    )
}

function Set-QOMonitoredMailboxAddresses {
    param(
        [Parameter(Mandatory)]
        [string[]]$Addresses
    )

    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $s.Tickets.EmailIntegration.MonitoredAddresses) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
    }

    $clean = @(
        $Addresses |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique
    )

    $s.Tickets.EmailIntegration.MonitoredAddresses = $clean
    Save-QOSettings -Settings $s

    return $clean
}

# --------------------------------------------------------------------
# Email sync start date pinning
# Storage: Tickets.EmailIntegration.EmailSyncStartDatePinned (yyyy-MM-dd or null)
# --------------------------------------------------------------------
function Get-QOEmailSyncStartDatePinned {
    $s = Get-QOSettings
    if (-not $s) { return $null }

    try {
        $raw = [string]$s.Tickets.EmailIntegration.EmailSyncStartDatePinned
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

        # Date only, treat as local date
        return [datetime]::ParseExact($raw, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }
}

function Set-QOEmailSyncStartDatePinned {
    param(
        [Parameter(Mandatory)]
        [datetime]$Date
    )

    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $s.Tickets.EmailIntegration.EmailSyncStartDatePinned) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName EmailSyncStartDatePinned -NotePropertyValue $null -Force
    }

    $s.Tickets.EmailIntegration.EmailSyncStartDatePinned = $Date.Date.ToString("yyyy-MM-dd")
    Save-QOSettings -Settings $s

    return (Get-QOEmailSyncStartDatePinned)
}

function Clear-QOEmailSyncStartDatePinned {
    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $s.Tickets.EmailIntegration.EmailSyncStartDatePinned) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName EmailSyncStartDatePinned -NotePropertyValue $null -Force
    }

    $s.Tickets.EmailIntegration.EmailSyncStartDatePinned = $null
    Save-QOSettings -Settings $s
    return $null
}

function Get-QOEffectiveEmailSyncStartDate {
    $pinned = Get-QOEmailSyncStartDatePinned
    if ($pinned) { return $pinned.Date }
    return (Get-Date).Date
}

function Get-QOTabVisibilitySettings {
    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.PSObject.Properties.Name.Contains("UiState")) {
        $s | Add-Member -NotePropertyName UiState -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.UiState.TabVisibility) {
        $s.UiState | Add-Member -NotePropertyName TabVisibility -NotePropertyValue ([pscustomobject]@{
            Cleaning = $true
            Apps     = $true
            Advanced = $true
            Tickets  = $true
        }) -Force
    }

    $result = [pscustomobject]@{
        Cleaning = [bool]$s.UiState.TabVisibility.Cleaning
        Apps     = [bool]$s.UiState.TabVisibility.Apps
        Advanced = [bool]$s.UiState.TabVisibility.Advanced
        Tickets  = [bool]$s.UiState.TabVisibility.Tickets
    }

    if (-not ($result.Cleaning -or $result.Apps -or $result.Advanced -or $result.Tickets)) {
        $result.Tickets = $true
    }

    return $result
}

function Get-QOToggleActionStates {
    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.PSObject.Properties.Name.Contains("UiState")) {
        $s | Add-Member -NotePropertyName UiState -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.UiState.ToggleActions) {
        $s.UiState | Add-Member -NotePropertyName ToggleActions -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $states = @{}
    foreach ($prop in @($s.UiState.ToggleActions.PSObject.Properties)) {
        if (-not $prop -or [string]::IsNullOrWhiteSpace([string]$prop.Name)) { continue }
        $states[[string]$prop.Name] = [bool]$prop.Value
    }

    return $states
}

function Get-QOToggleActionState {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [bool]$Default = $false
    )

    if ([string]::IsNullOrWhiteSpace($ActionId)) {
        return [bool]$Default
    }

    $states = Get-QOToggleActionStates
    if ($states.ContainsKey($ActionId)) {
        return [bool]$states[$ActionId]
    }

    return [bool]$Default
}

function Set-QOToggleActionState {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][bool]$IsEnabled
    )

    if ([string]::IsNullOrWhiteSpace($ActionId)) {
        throw "ActionId is required."
    }

    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.PSObject.Properties.Name.Contains("UiState")) {
        $s | Add-Member -NotePropertyName UiState -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.UiState.ToggleActions) {
        $s.UiState | Add-Member -NotePropertyName ToggleActions -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if ($s.UiState.ToggleActions.PSObject.Properties.Name -notcontains $ActionId) {
        $s.UiState.ToggleActions | Add-Member -NotePropertyName $ActionId -NotePropertyValue ([bool]$IsEnabled) -Force
    }
    else {
        $s.UiState.ToggleActions.$ActionId = [bool]$IsEnabled
    }

    Save-QOSettings -Settings $s
    return [bool]$s.UiState.ToggleActions.$ActionId
}

function Get-QOTicketListViewSettings {
    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }
    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.ListView) {
        $s.Tickets | Add-Member -NotePropertyName ListView -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if ($s.Tickets.ListView.PSObject.Properties.Name -notcontains "ShowOpen") {
        $s.Tickets.ListView | Add-Member -NotePropertyName ShowOpen -NotePropertyValue $true -Force
    }
    if ($s.Tickets.ListView.PSObject.Properties.Name -notcontains "ShowClosed") {
        $s.Tickets.ListView | Add-Member -NotePropertyName ShowClosed -NotePropertyValue $true -Force
    }
    if ($s.Tickets.ListView.PSObject.Properties.Name -notcontains "ShowDeleted") {
        $s.Tickets.ListView | Add-Member -NotePropertyName ShowDeleted -NotePropertyValue $false -Force
    }
    if ($s.Tickets.ListView.PSObject.Properties.Name -notcontains "SortMode") {
        $s.Tickets.ListView | Add-Member -NotePropertyName SortMode -NotePropertyValue "Priority" -Force
    }
    if ($s.Tickets.ListView.PSObject.Properties.Name -notcontains "AssigneeFilter") {
        $s.Tickets.ListView | Add-Member -NotePropertyName AssigneeFilter -NotePropertyValue "All" -Force
    }

    $sortMode = "Priority"
    try { $sortMode = ([string]($s.Tickets.ListView.SortMode + "")).Trim() } catch { $sortMode = "Priority" }
    switch ($sortMode.ToLowerInvariant()) {
        "newest" { $sortMode = "Newest" }
        "oldest" { $sortMode = "Oldest" }
        default { $sortMode = "Priority" }
    }
    $assigneeFilter = ""
    try { $assigneeFilter = ([string]($s.Tickets.ListView.AssigneeFilter + "")).Trim() } catch { $assigneeFilter = "" }
    if ([string]::IsNullOrWhiteSpace($assigneeFilter)) { $assigneeFilter = "All" }
    if ($assigneeFilter.StartsWith("@")) { $assigneeFilter = $assigneeFilter.TrimStart("@") }
    switch ($assigneeFilter.ToLowerInvariant()) {
        "all" { $assigneeFilter = "All" }
        "unassigned" { $assigneeFilter = "Unassigned" }
        "none" { $assigneeFilter = "Unassigned" }
        "n/a" { $assigneeFilter = "Unassigned" }
        "na" { $assigneeFilter = "Unassigned" }
        "null" { $assigneeFilter = "Unassigned" }
        default { }
    }

    $showOpen = [bool]$s.Tickets.ListView.ShowOpen
    $showClosed = [bool]$s.Tickets.ListView.ShowClosed
    $showDeleted = [bool]$s.Tickets.ListView.ShowDeleted
    if (-not ($showOpen -or $showClosed -or $showDeleted)) {
        $showOpen = $true
    }

    return [pscustomobject]@{
        ShowOpen   = $showOpen
        ShowClosed = $showClosed
        ShowDeleted = $showDeleted
        SortMode   = $sortMode
        AssigneeFilter = $assigneeFilter
    }
}

function Set-QOTicketListViewSettings {
    param(
        [Parameter(Mandatory)][bool]$ShowOpen,
        [Parameter(Mandatory)][bool]$ShowClosed,
        [Parameter(Mandatory)][bool]$ShowDeleted,
        [Parameter(Mandatory)][string]$SortMode,
        [AllowNull()][string]$AssigneeFilter = "All"
    )

    $normalizedSortMode = ([string]($SortMode + "")).Trim()
    switch ($normalizedSortMode.ToLowerInvariant()) {
        "newest" { $normalizedSortMode = "Newest" }
        "oldest" { $normalizedSortMode = "Oldest" }
        default { $normalizedSortMode = "Priority" }
    }
    $normalizedAssigneeFilter = ([string]($AssigneeFilter + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedAssigneeFilter)) { $normalizedAssigneeFilter = "All" }
    if ($normalizedAssigneeFilter.StartsWith("@")) { $normalizedAssigneeFilter = $normalizedAssigneeFilter.TrimStart("@") }
    switch ($normalizedAssigneeFilter.ToLowerInvariant()) {
        "all" { $normalizedAssigneeFilter = "All" }
        "unassigned" { $normalizedAssigneeFilter = "Unassigned" }
        "none" { $normalizedAssigneeFilter = "Unassigned" }
        "n/a" { $normalizedAssigneeFilter = "Unassigned" }
        "na" { $normalizedAssigneeFilter = "Unassigned" }
        "null" { $normalizedAssigneeFilter = "Unassigned" }
        default { }
    }

    $showOpenValue = [bool]$ShowOpen
    $showClosedValue = [bool]$ShowClosed
    $showDeletedValue = [bool]$ShowDeleted
    if (-not ($showOpenValue -or $showClosedValue -or $showDeletedValue)) {
        $showOpenValue = $true
    }

    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }
    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.ListView) {
        $s.Tickets | Add-Member -NotePropertyName ListView -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $s.Tickets.ListView.ShowOpen = $showOpenValue
    $s.Tickets.ListView.ShowClosed = $showClosedValue
    $s.Tickets.ListView.ShowDeleted = $showDeletedValue
    $s.Tickets.ListView.SortMode = $normalizedSortMode
    $s.Tickets.ListView.AssigneeFilter = $normalizedAssigneeFilter
    Save-QOSettings -Settings $s

    return (Get-QOTicketListViewSettings)
}

function Set-QOTabVisibilitySettings {
    param(
        [Parameter(Mandatory)][bool]$Cleaning,
        [Parameter(Mandatory)][bool]$Apps,
        [Parameter(Mandatory)][bool]$Advanced,
        [Parameter(Mandatory)][bool]$Tickets
    )

    $s = Get-QOSettings
    if (-not $s) { $s = New-QODefaultSettings -NoSave }

    if (-not $s.PSObject.Properties.Name.Contains("UiState")) {
        $s | Add-Member -NotePropertyName UiState -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.UiState.TabVisibility) {
        $s.UiState | Add-Member -NotePropertyName TabVisibility -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $showCleaning = [bool]$Cleaning
    $showApps = [bool]$Apps
    $showAdvanced = [bool]$Advanced
    $showTickets = [bool]$Tickets

    if (-not ($showCleaning -or $showApps -or $showAdvanced -or $showTickets)) {
        $showTickets = $true
    }

    $s.UiState.TabVisibility.Cleaning = $showCleaning
    $s.UiState.TabVisibility.Apps = $showApps
    $s.UiState.TabVisibility.Advanced = $showAdvanced
    $s.UiState.TabVisibility.Tickets = $showTickets

    Save-QOSettings -Settings $s
    return (Get-QOTabVisibilitySettings)
}

# --------------------------------------------------------------------
# Compatibility wrappers (because UI/Tickets code may call these names)
# --------------------------------------------------------------------
function Set-QOMonitoredAddresses {
    param(
        [Parameter(Mandatory)]
        [string[]]$Addresses
    )
    return (Set-QOMonitoredMailboxAddresses -Addresses $Addresses)
}

function Get-QOMonitoredAddresses {
    return (Get-QOMonitoredMailboxAddresses)
}

Export-ModuleMember -Function `
    Get-QOAppDataRoot, `
    Get-QOSettings, `
    Save-QOSettings, `
    Set-QOSetting, `
    Get-QOSettingsPath, `
    New-QODefaultSettings, `
    Get-QOMonitoredMailboxAddresses, `
    Set-QOMonitoredMailboxAddresses, `
    Get-QOMonitoredAddresses, `
    Set-QOMonitoredAddresses, `
    Get-QOEmailSyncStartDatePinned, `
    Set-QOEmailSyncStartDatePinned, `
    Clear-QOEmailSyncStartDatePinned, `
    Get-QOEffectiveEmailSyncStartDate, `
    Get-QOTicketStorageSettings, `
    Set-QOTicketStorageSettings, `
    Get-QOTicketListViewSettings, `
    Set-QOTicketListViewSettings, `
    Get-QOTabVisibilitySettings, `
    Set-QOTabVisibilitySettings, `
    Get-QOToggleActionStates, `
    Get-QOToggleActionState, `
    Set-QOToggleActionState
