param(
    [switch]$VerboseStartup
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$introPath = Join-Path $root "src\Intro\Intro.ps1"

if (-not (Test-Path -LiteralPath $introPath)) {
    throw "Missing Intro script at: $introPath"
}

$logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$introLog = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-STA",
    "-File", $introPath,
    "-LogPath", $introLog
)

if (-not $VerboseStartup) {
    $args += "-Quiet"
}

Write-Host ("Launching local toolkit from: {0}" -f $root)
Write-Host ("Intro log: {0}" -f $introLog)
& $psExe @args


