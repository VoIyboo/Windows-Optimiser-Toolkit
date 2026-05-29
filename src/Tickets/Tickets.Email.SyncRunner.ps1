param(
    [Parameter(Mandatory=$true)][string]$ToolkitRoot,
    [string]$SyncCommand = "Sync-QOTicketsFromEmail",
    [int]$MaxPerMailbox = 25,
    [switch]$AllowStartOutlook,
    [string]$ResultPath
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

function New-QOTSyncRunnerResult {
    param(
        [bool]$Success = $false,
        [int]$Added = 0,
        [int]$Updated = 0,
        [string]$Note = "",
        [object[]]$AddedTickets = @()
    )
    return [pscustomobject]@{
        Success = [bool]$Success
        Added = [int]$Added
        Updated = [int]$Updated
        AddedTickets = @($AddedTickets)
        Note = [string]$Note
    }
}

function Write-QOTSyncRunnerResult {
    param(
        [Parameter(Mandatory=$true)]$Result
    )

    $json = $Result | ConvertTo-Json -Depth 40 -Compress
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        try {
            $json | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }

    $json
}

try {
    if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
        throw "Toolkit root path is required."
    }

    if ($MaxPerMailbox -lt 1) { $MaxPerMailbox = 1 }
    if ($MaxPerMailbox -gt 500) { $MaxPerMailbox = 500 }

    $coreModulePath = Join-Path $ToolkitRoot "src\Core\Tickets.psm1"
    if (-not (Test-Path -LiteralPath $coreModulePath)) {
        throw ("Core tickets module not found: " + $coreModulePath)
    }

    Import-Module -Name $coreModulePath -Global -Force -ErrorAction Stop -WarningAction SilentlyContinue

    $syncCmd = Get-Command -Name $SyncCommand -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $syncCmd) {
        throw ("Sync command unavailable: " + $SyncCommand)
    }

    $rawResult = & $SyncCommand -MaxPerMailbox $MaxPerMailbox -AllowStartOutlook:$AllowStartOutlook
    if (-not $rawResult) {
        $rawResult = New-QOTSyncRunnerResult -Success:$false -Added 0 -Updated 0 -Note "Outlook sync returned nothing." -AddedTickets @()
    }

    $success = $true
    $added = 0
    $updated = 0
    $note = ""
    $addedTickets = @()
    try { if ($rawResult.PSObject.Properties.Name -contains "Success") { $success = [bool]$rawResult.Success } } catch { $success = $false }
    try { if ($rawResult.PSObject.Properties.Name -contains "Added") { $added = [int]$rawResult.Added } } catch { $added = 0 }
    try { if ($rawResult.PSObject.Properties.Name -contains "Updated") { $updated = [int]$rawResult.Updated } } catch { $updated = 0 }
    try { if ($rawResult.PSObject.Properties.Name -contains "Note") { $note = [string]$rawResult.Note } } catch { $note = "" }
    try { if ($rawResult.PSObject.Properties.Name -contains "AddedTickets") { $addedTickets = @($rawResult.AddedTickets) } } catch { $addedTickets = @() }

    if ($rawResult.PSObject.Properties.Name -notcontains "Success") {
        if ($note -match '(?i)\b(failed|unavailable|not loaded|not found|required)\b') {
            $success = $false
        }
    }

    Write-QOTSyncRunnerResult -Result (New-QOTSyncRunnerResult -Success:$success -Added $added -Updated $updated -Note $note -AddedTickets $addedTickets)
    exit 0
}
catch {
    $failure = New-QOTSyncRunnerResult -Success:$false -Added 0 -Updated 0 -Note ("Sync runner failed: " + $_.Exception.Message) -AddedTickets @()
    Write-QOTSyncRunnerResult -Result $failure
    exit 1
}
