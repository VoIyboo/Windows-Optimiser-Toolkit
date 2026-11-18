param(
    [switch]$VerboseStartup
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$introPath = Join-Path $root "src\Intro\Intro.ps1"

if (-not (Test-Path -LiteralPath $introPath)) {
    throw "Missing Intro script at: $introPath"
}

$introLog = $null
foreach ($candidate in @($env:QOT_BOOTSTRAP_LOG_DIR,
                         (Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"),
                         (Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"),
                         (Join-Path $env:TEMP "QuinnOptimiserToolkit\Logs"))) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    try {
        $null = [IO.Directory]::CreateDirectory($candidate)
        $candidateLog = Join-Path $candidate ("Intro_{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $PID)
        $stream = [IO.File]::Open($candidateLog, 'CreateNew', 'Write', 'ReadWrite')
        $stream.Dispose()
        $introLog = $candidateLog
        break
    }
    catch { continue }
}
if (!$introLog) { throw "No writable directory for the intro log." }

$psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-STA",
    "-File", ('"{0}"' -f $introPath),
    "-LogPath", ('"{0}"' -f $introLog)
)

if (-not $VerboseStartup) {
    $args += "-Quiet"
}

Write-Host ("Launching local toolkit from: {0}" -f $root)
Write-Host ("Intro log: {0}" -f $introLog)
$startedProcess = Start-Process -FilePath $psExe -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden -PassThru
if (-not $startedProcess) {
    throw "Failed to start the intro process."
}


