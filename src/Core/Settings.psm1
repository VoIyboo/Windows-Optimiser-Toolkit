# src\Core\Settings.psm1
# Quinn Optimiser Toolkit - Settings module
# Handles global JSON settings for the app

$ErrorActionPreference = "Stop"

# Always save to THIS path (resolved lazily)
$script:SettingsPath = $null
$script:QOAppDataRoot = $null
$script:SettingsReadVersions = [Runtime.CompilerServices.ConditionalWeakTable[psobject,hashtable]]::new()

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

function Read-QOSettingsText {
    param([string]$Path)

    $stream = [IO.File]::Open($Path, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $reader = [IO.StreamReader]::new($stream, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Invoke-QOSettingsLocked {
    param([string]$Path, [scriptblock]$Action)

    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToUpperInvariant())
        $key = [BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-', '')
    } finally { $hash.Dispose() }
    $mutex = [Threading.Mutex]::new($false, ('Global\QOTSettings_' + $key))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(10)) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (!$locked) { throw 'Timed out waiting to save toolkit settings.' }
        & $Action
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function ConvertFrom-QOSettingsJson {
    param([string]$Json)
    # Keep UTC sync markers as strings when reading in PowerShell 7.5+.
    $options = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind = 'String' }
    ConvertFrom-Json -InputObject $Json @options -ErrorAction Stop
}

function Merge-QOSettingsEdits {
    param($Original, $Edited, $Current, [string]$Prefix)

    $names = @($Original.PSObject.Properties.Name) + @($Edited.PSObject.Properties.Name)
    foreach ($name in @($names | Where-Object { $_ } | Select-Object -Unique)) {
        $originalProperty = $Original.PSObject.Properties[$name]
        $editedProperty = $Edited.PSObject.Properties[$name]
        $currentProperty = $Current.PSObject.Properties[$name]
        # An absent property produces no string; a present null produces the JSON literal null.
        $before = if ($originalProperty) { ConvertTo-Json -InputObject $originalProperty.Value -Depth 20 -Compress }
        $after = if ($editedProperty) { ConvertTo-Json -InputObject $editedProperty.Value -Depth 20 -Compress }
        if ($before -ceq $after) { continue }
        $latest = if ($currentProperty) { ConvertTo-Json -InputObject $currentProperty.Value -Depth 20 -Compress }
        if ($latest -ceq $after) { continue }
        if ($latest -cne $before) {
            if ((Test-QOSettingsIsObject $originalProperty.Value) -and (Test-QOSettingsIsObject $editedProperty.Value) -and (Test-QOSettingsIsObject $currentProperty.Value)) {
                Merge-QOSettingsEdits $originalProperty.Value $editedProperty.Value $currentProperty.Value "$Prefix$name."
                continue
            }
            throw "Another writer changed '$Prefix$name'. Reload settings before saving."
        }
        if ($editedProperty) { $Current | Add-Member -NotePropertyName $name -NotePropertyValue $editedProperty.Value -Force }
        else { $Current.PSObject.Properties.Remove($name) }
    }
}

function Write-QOSettingsFile {
    param(
        [string]$Path,
        [string]$Json,
        [switch]$IfMissing,
        [AllowEmptyString()][string]$DamagedText,
        [hashtable]$ReadVersion
    )

    $recover = $PSBoundParameters.ContainsKey('DamagedText')
    Invoke-QOSettingsLocked -Path $Path -Action {
        $dir = Split-Path -Parent $Path
        $null = [IO.Directory]::CreateDirectory($dir)
        $exists = [IO.File]::Exists($Path)
        if ($IfMissing -and $exists) { return $false }
        $backup = [System.Management.Automation.Language.NullString]::Value
        if ($recover) {
            # A writer may have replaced the settings since the original read.
            if (!$exists -or (Read-QOSettingsText $Path) -cne $DamagedText) { return $false }
            $backup = "$Path.bak_$([guid]::NewGuid().ToString('N'))"
        }
        if ($ReadVersion) {
            if (!$exists) { throw 'The settings file was removed. Reload settings before saving.' }
            $currentJson = Read-QOSettingsText $Path
            if (!$currentJson.TrimStart().StartsWith('{')) { throw 'The settings file is invalid. Reload settings before saving.' }
            $current = Complete-QOSettingsDefaults (ConvertFrom-QOSettingsJson $currentJson)
            Merge-QOSettingsEdits (ConvertFrom-QOSettingsJson $ReadVersion.Json) (ConvertFrom-QOSettingsJson $Json) $current
            $Json = ConvertTo-Json -InputObject $current -Depth 20
        }
        $temp = Join-Path $dir ('.settings-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [IO.File]::WriteAllText($temp, $Json, [Text.UTF8Encoding]::new($true))
            if ($exists) { [IO.File]::Replace($temp, $Path, $backup) }
            else { [IO.File]::Move($temp, $Path) }
        } finally { [IO.File]::Delete($temp) }
        return $true
    }
}

function Save-QOSettings {
    param([Parameter(Mandatory)]$Settings)

    $json = ConvertTo-Json -InputObject $Settings -Depth 20
    $path = Get-QOSettingsPath
    $version = $null
    if ($script:SettingsReadVersions.TryGetValue($Settings, [ref]$version) -and $version.Path -ne $path) {
        throw 'The settings location changed. Reload settings before saving.'
    }
    $null = Write-QOSettingsFile -Path $path -Json $json -ReadVersion $version
    if ($version) { $version.Json = $json }
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
    while ($true) {
        try { $json = Read-QOSettingsText $path }
        catch [IO.FileNotFoundException], [IO.DirectoryNotFoundException] {
            $defaults = New-QODefaultSettings -NoSave
            $null = Write-QOSettingsFile -Path $path -Json (ConvertTo-Json $defaults -Depth 20) -IfMissing
            continue
        }
        # Windows PowerShell unwraps a single-element JSON array. Check the root as well.
        $settings = $null
        if ($json.TrimStart().StartsWith('{')) {
            try { $settings = ConvertFrom-QOSettingsJson $json }
            catch [ArgumentException], [InvalidOperationException] { $settings = $null }
        }
        if (-not (Test-QOSettingsIsObject $settings)) {
            $defaults = New-QODefaultSettings -NoSave
            $null = Write-QOSettingsFile -Path $path -Json (ConvertTo-Json $defaults -Depth 20) -DamagedText $json
            continue
        }
        $settings = Complete-QOSettingsDefaults $settings
        $script:SettingsReadVersions.Add($settings, @{Path=$path; Json=(ConvertTo-Json -InputObject $settings -Depth 20 -Compress)})
        return $settings
    }
}

function Complete-QOSettingsDefaults {
    param($settings)
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
    $sync = $settings.Tickets.EmailIntegration
    $parsed = [datetime]::MinValue
    if ($sync.EmailSyncStartDatePinned -and ![datetime]::TryParseExact([string]$sync.EmailSyncStartDatePinned, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$parsed)) {
        $sync.EmailSyncStartDatePinned = $null
    }
    foreach ($name in 'LastSyncUtc','LastSuccessfulSyncUtc') {
        if ($sync.$name -and ![datetime]::TryParse([string]$sync.$name, [Globalization.CultureInfo]::InvariantCulture, 'RoundtripKind', [ref]$parsed)) { $sync.$name = $null }
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

    $resolvedStorePath = Resolve-QOTicketStorePath -Path $StorePath
    $resolvedBackupPath = Resolve-QOTicketBackupPath -Path $BackupPath -StorePath $resolvedStorePath
    Invoke-QOSettingsLocked -Path (Get-QOSettingsPath) -Action {
        $settings = Get-QOSettings
        $oldStore = Resolve-QOTicketStorePath -Path $settings.TicketStorePath
        if ($oldStore -ne $resolvedStorePath) {
            Update-QOEmailSyncRevision $settings.Tickets.EmailIntegration $true
        }
        $settings | Add-Member NoteProperty TicketStorePath $resolvedStorePath -Force
        $settings | Add-Member NoteProperty LocalTicketBackupPath $resolvedBackupPath -Force
        Save-QOSettings -Settings $settings
    }
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

function Update-QOEmailSyncRevision {
    param($Integration, [bool]$ResetCheckpoint)
    $Integration | Add-Member -NotePropertyName SyncRevision -NotePropertyValue ([guid]::NewGuid().ToString('N')) -Force
    if ($ResetCheckpoint) {
        $Integration.LastSyncUtc = $null
        $Integration.LastSuccessfulSyncUtc = $null
    }
}

function Set-QOMonitoredMailboxAddresses {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Addresses,
        [switch]$IfUnconfigured
    )
    $clean = @($Addresses | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    Invoke-QOSettingsLocked -Path (Get-QOSettingsPath) -Action {
        $settings = Get-QOSettings
        $integration = $settings.Tickets.EmailIntegration
        $old = @($integration.MonitoredAddresses | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        if ($IfUnconfigured -and $old.Count) { return $old }
        $added = @($clean | Where-Object { $old -notcontains $_ }).Count -gt 0
        if ($added -or $clean.Count -ne $old.Count) {
            $integration.MonitoredAddresses = $clean
            Update-QOEmailSyncRevision $integration $added
            Save-QOSettings -Settings $settings
        }
        return $clean
    }
}

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
    param([Parameter(Mandatory)][datetime]$Date)
    $pin = $Date.Date.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    Invoke-QOSettingsLocked -Path (Get-QOSettingsPath) -Action {
        $settings = Get-QOSettings
        $integration = $settings.Tickets.EmailIntegration
        $oldPin = [string]$integration.EmailSyncStartDatePinned
        if ($oldPin -ne $pin) {
            $oldDate = if ($oldPin) { [datetime]$oldPin } else { (Get-Date).Date }
            $integration.EmailSyncStartDatePinned = $pin
            Update-QOEmailSyncRevision $integration ($Date.Date -lt $oldDate)
            Save-QOSettings -Settings $settings
        }
    }
    return $Date.Date
}

function Clear-QOEmailSyncStartDatePinned {
    Invoke-QOSettingsLocked -Path (Get-QOSettingsPath) -Action {
        $settings = Get-QOSettings
        $integration = $settings.Tickets.EmailIntegration
        if ($integration.EmailSyncStartDatePinned) {
            $oldDate = [datetime]$integration.EmailSyncStartDatePinned
            $integration.EmailSyncStartDatePinned = $null
            Update-QOEmailSyncRevision $integration ((Get-Date).Date -lt $oldDate)
            Save-QOSettings -Settings $settings
        }
    }
}

function Set-QOEmailSyncCheckpoint {
    param(
        [AllowEmptyString()][string]$Revision,
        [Parameter(Mandatory)][datetime]$CompletedUtc,
        [Nullable[datetime]]$WatermarkUtc,
        [string]$StorePath
    )
    Invoke-QOSettingsLocked -Path (Get-QOSettingsPath) -Action {
        $settings = Get-QOSettings
        $integration = $settings.Tickets.EmailIntegration
        if ([string]$integration.SyncRevision -ne $Revision) { return $false }
        if ($StorePath -and (Resolve-QOTicketStorePath -Path $settings.TicketStorePath) -ne $StorePath) { return $false }
        if (!$integration.LastSuccessfulSyncUtc -or $CompletedUtc -gt ([datetime]$integration.LastSuccessfulSyncUtc).ToUniversalTime()) {
            $integration.LastSuccessfulSyncUtc = $CompletedUtc.ToUniversalTime().ToString('o')
        }
        if ($null -ne $WatermarkUtc -and (!$integration.LastSyncUtc -or $WatermarkUtc -gt ([datetime]$integration.LastSyncUtc).ToUniversalTime())) {
            $integration.LastSyncUtc = $WatermarkUtc.ToUniversalTime().ToString('o')
        }
        Save-QOSettings -Settings $settings
        return $true
    }
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
        [AllowEmptyCollection()][string[]]$Addresses,
        [switch]$IfUnconfigured
    )
    return (Set-QOMonitoredMailboxAddresses -Addresses $Addresses -IfUnconfigured:$IfUnconfigured)
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
    Set-QOEmailSyncCheckpoint, `
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
