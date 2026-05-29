# Config.psm1
# Central configuration for Quinn Optimiser Toolkit

# Holds the current configuration
$script:QOTConfig = $null

function Initialize-QOTConfig {
    param(
        [string]$RootPath
    )

    # If not supplied, auto-detect:
    # Core\Config -> parent = Core
    # Core -> parent = src
    # src -> parent = repo root
    if (-not $RootPath) {
        $RootPath = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    }

    $srcRoot  = Join-Path $RootPath "src"
    $logsRoot = Join-Path $RootPath "Logs"

    # Persistent data root -- user-scoped, survives reboots, no admin needed.
    # Lives at %LOCALAPPDATA%\QuinnOptimiserToolkit\ and falls back to
    # %APPDATA% or %USERPROFILE% if LocalAppData is unavailable.
    $dataRoot = Resolve-QOTDataRoot

    # Ensure all directories exist
    foreach ($dir in @($logsRoot, $dataRoot)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    $script:QOTConfig = [pscustomobject]@{
        RootPath = $RootPath
        SrcRoot  = $srcRoot
        LogsRoot = $logsRoot
        DataRoot = $dataRoot
        Version  = "3.0.0"
    }

    return $script:QOTConfig
}

function Resolve-QOTDataRoot {
    # Preference order: LocalAppData -> AppData -> UserProfile -> Temp
    $candidates = @(
        $env:LOCALAPPDATA,
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),
        $env:APPDATA,
        $env:USERPROFILE,
        [System.IO.Path]::GetTempPath()
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    foreach ($base in $candidates) {
        $candidate = Join-Path ([string]$base) "QuinnOptimiserToolkit"
        try {
            if (-not (Test-Path -LiteralPath $candidate)) {
                New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
            }
            # Quick write test to confirm it's usable
            $probe = Join-Path $candidate (".qot-write-test-{0}.tmp" -f [guid]::NewGuid().ToString("N"))
            [System.IO.File]::WriteAllText($probe, "")
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            return $candidate
        } catch {
            # Try next candidate
        }
    }

    # Should never reach here, but just in case
    return Join-Path ([System.IO.Path]::GetTempPath()) "QuinnOptimiserToolkit"
}

function Get-QOTConfig {
    if (-not $script:QOTConfig) {
        throw "QOT config has not been initialised. Call Initialize-QOTConfig first."
    }
    return $script:QOTConfig
}

function Get-QOTRoot {
    (Get-QOTConfig).RootPath
}

function Get-QOTDataRoot {
    (Get-QOTConfig).DataRoot
}

function Get-QOTPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $cfg = Get-QOTConfig

    switch ($Name.ToLowerInvariant()) {
        "root"    { return $cfg.RootPath }
        "src"     { return $cfg.SrcRoot }
        "logs"    { return $cfg.LogsRoot }
        "data"    { return $cfg.DataRoot }
        "tickets" { return (Join-Path $cfg.DataRoot "Tickets") }
        default   { throw "Unknown QOT path name '$Name'. Valid values: Root, Src, Logs, Data, Tickets." }
    }
}

function Get-QOTVersion {
    (Get-QOTConfig).Version
}

Export-ModuleMember -Function `
    Initialize-QOTConfig, `
    Get-QOTConfig,         `
    Get-QOTRoot,           `
    Get-QOTDataRoot,       `
    Get-QOTPath,           `
    Get-QOTVersion
