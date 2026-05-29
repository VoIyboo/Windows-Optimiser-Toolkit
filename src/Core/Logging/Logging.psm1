# Logging.psm1
# Simple logging utilities for Quinn Optimiser Toolkit

# Module-scoped variables
$script:QLogRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
$script:QLogFile = $null
$script:QLogMaxBytes = 32MB
$script:QLogMaxArchives = 8
$script:QLogSizeCheckIntervalSeconds = 10
$script:QLogLastSizeCheckUtc = [datetime]::MinValue
$script:QLogMaintenancePerformed = $false

function Test-QOTConsoleLoggingEnabled {
    $quietEnv = [Environment]::GetEnvironmentVariable('QOT_QUIET_CONSOLE', 'Process')
    if ([string]::IsNullOrWhiteSpace($quietEnv)) {
        return $false
    }

    $quietToken = $quietEnv.Trim().ToLowerInvariant()
    return ($quietToken -in @('0', 'false', 'no', 'off'))
}

function Ensure-QLogRoot {
    if (-not $script:QLogRoot) {
        $script:QLogRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    }

    try {
        if (-not (Test-Path -LiteralPath $script:QLogRoot)) {
            New-Item -Path $script:QLogRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        return
    } catch { }

    # Fallback for locked-down environments where ProgramData is not writable.
    try {
        $fallback = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"
        if (-not (Test-Path -LiteralPath $fallback)) {
            New-Item -Path $fallback -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $script:QLogRoot = $fallback
    } catch { }
}

function Get-QLogPolicy {
    try {
        $envMaxMb = [Environment]::GetEnvironmentVariable('QOT_LOG_MAX_MB', 'Process')
        if (-not [string]::IsNullOrWhiteSpace($envMaxMb)) {
            $parsedMaxMb = 0
            if ([int]::TryParse($envMaxMb.Trim(), [ref]$parsedMaxMb) -and $parsedMaxMb -ge 5 -and $parsedMaxMb -le 512) {
                $script:QLogMaxBytes = [int64]$parsedMaxMb * 1MB
            }
        }
    } catch { }

    try {
        $envKeep = [Environment]::GetEnvironmentVariable('QOT_LOG_KEEP_ARCHIVES', 'Process')
        if (-not [string]::IsNullOrWhiteSpace($envKeep)) {
            $parsedKeep = 0
            if ([int]::TryParse($envKeep.Trim(), [ref]$parsedKeep) -and $parsedKeep -ge 2 -and $parsedKeep -le 64) {
                $script:QLogMaxArchives = $parsedKeep
            }
        }
    } catch { }
}

function Invoke-QLogRotateIfNeeded {
    param(
        [Parameter(Mandatory)][string]$FilePath
    )

    try {
        if ([string]::IsNullOrWhiteSpace($FilePath)) { return }
        if (-not (Test-Path -LiteralPath $FilePath)) { return }

        Get-QLogPolicy

        $fileInfo = Get-Item -LiteralPath $FilePath -ErrorAction Stop
        if (-not $fileInfo) { return }
        if ($fileInfo.Length -lt [int64]$script:QLogMaxBytes) { return }

        $dir = Split-Path -Parent $FilePath
        $base = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $ext = [System.IO.Path]::GetExtension($FilePath)
        $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $archivePath = Join-Path $dir ("{0}.bak_{1}{2}" -f $base, $stamp, $ext)

        Move-Item -LiteralPath $FilePath -Destination $archivePath -Force -ErrorAction Stop

        # Trim old archives for this log file.
        try {
            $archives = @(Get-ChildItem -LiteralPath $dir -Filter ("{0}.bak_*{1}" -f $base, $ext) -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
            if ($archives.Count -gt $script:QLogMaxArchives) {
                $toDelete = $archives | Select-Object -Skip $script:QLogMaxArchives
                foreach ($old in @($toDelete)) {
                    try { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue } catch { }
                }
            }
        } catch { }

        $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -LiteralPath $FilePath -Value ("[{0}] [INFO] Log rotated automatically. Previous file: {1}" -f $ts, $archivePath) -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Never let rotation failures break runtime behavior.
    }
}

function Invoke-QLogMaintenance {
    if ($script:QLogMaintenancePerformed) { return }
    $script:QLogMaintenancePerformed = $true

    try { Get-QLogPolicy } catch { }

    $candidatePaths = @(
        (Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs\QuinnOptimiserToolkit.log"),
        (Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs\QuinnOptimiserToolkit.log")
    )

    foreach ($candidate in @($candidatePaths)) {
        try { Invoke-QLogRotateIfNeeded -FilePath $candidate } catch { }
    }
}

function Set-QLogRoot {
    param(
        [string]$Root
    )

    if (-not $Root) {
        throw "Set-QLogRoot: Root path cannot be empty."
    }

    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
    }

    $script:QLogRoot = $Root
}

function Ensure-QLogFile {
    Ensure-QLogRoot
    if (-not $script:QLogFile) {
        $script:QLogFile = Join-Path $script:QLogRoot "QuinnOptimiserToolkit.log"
    }
    try { Invoke-QLogMaintenance } catch { }
}

function Start-QLogSession {
    param(
        [string]$Prefix = "QuinnOptimiserToolkit"
    )

    Ensure-QLogRoot

    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $fileName  = "{0}_{1}.log" -f $Prefix, $timestamp
    $script:QLogFile = Join-Path $script:QLogRoot $fileName

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Log session started." |
        Out-File -FilePath $script:QLogFile -Encoding UTF8 -Force
}

function Write-QLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message

    try {
        Ensure-QLogFile
        if ($script:QLogFile) {
            $nowUtc = (Get-Date).ToUniversalTime()
            $checkRotation = $true
            try {
                $elapsedSeconds = ($nowUtc - $script:QLogLastSizeCheckUtc).TotalSeconds
                if ($elapsedSeconds -lt $script:QLogSizeCheckIntervalSeconds) {
                    $checkRotation = $false
                }
            } catch { $checkRotation = $true }
            if ($checkRotation) {
                $script:QLogLastSizeCheckUtc = $nowUtc
                try { Invoke-QLogRotateIfNeeded -FilePath $script:QLogFile } catch { }
            }
            Add-Content -LiteralPath $script:QLogFile -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        }
    } catch { }

    try {
        $fallback = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"
        if (-not (Test-Path -LiteralPath $fallback)) {
            New-Item -Path $fallback -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $fallbackFile = Join-Path $fallback "QuinnOptimiserToolkit.log"
        try { Invoke-QLogRotateIfNeeded -FilePath $fallbackFile } catch { }
        Add-Content -LiteralPath $fallbackFile -Value $line -Encoding UTF8 -ErrorAction Stop
        $script:QLogRoot = $fallback
        $script:QLogFile = $fallbackFile
    } catch {
        # Never let logging failures break runtime behavior.
    }
}

function Write-QOSettingsUILog {
    param([string]$Message)

    Ensure-QLogRoot

    try {
        $path = Join-Path $script:QLogRoot "SettingsUI.log"
        Add-Content -LiteralPath $path -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8 -ErrorAction Stop
    } catch { }

    # Optional: also echo into main log stream for dev visibility
    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog "[SettingsUI] $Message" "INFO"
        }
    } catch { }
}

function Stop-QLogSession {
    if ($script:QLogFile) {
        $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        try { Add-Content -LiteralPath $script:QLogFile -Value "[$ts] [INFO] Log session ended." -Encoding UTF8 -ErrorAction Stop } catch { }
        $script:QLogFile = $null
    }
}

Export-ModuleMember -Function `
    Set-QLogRoot, `
    Start-QLogSession, `
    Write-QLog, `
    Write-QOSettingsUILog, `
    Stop-QLogSession
