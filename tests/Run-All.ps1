# Each suite has its own runspace, module state and disposable test data.
$ErrorActionPreference = 'Stop'
$engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$suites = @(Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {
    $_.Name -like '*.Tests.ps1' -or $_.Name -like '*.Integration.ps1'
} | Sort-Object Name)
if (!$suites) { throw 'No test suites found.' }
$failed = @()
foreach ($suite in $suites) {
    Write-Host ("Running {0}" -f $suite.Name)
    & $engine -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $suite.FullName
    if ($LASTEXITCODE -ne 0) { $failed += $suite.Name }
}
if ($failed.Count) { throw ("Failed suites: {0}" -f ($failed -join ', ')) }
Write-Host ("PASS All {0} Windows PowerShell test suites." -f $suites.Count)
