# No network or installed app required. The only child program is a marker-writing test script.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$oldLocation = Get-Location
$tempRoot = [IO.Path]::GetTempPath().TrimEnd('\')
$fixture = Join-Path $tempRoot ('QOT bootstrap test ' + [guid]::NewGuid())
$null = New-Item -Type Directory -Path $fixture
$priorEnv = @{}
foreach ($key in 'ProgramData','APPDATA','LOCALAPPDATA','TEMP','QOT_TEST_MARKER','QOT_BOOTSTRAP_HANDOFF_SIGNAL') {
    $priorEnv[$key] = [Environment]::GetEnvironmentVariable($key)
}
$env:QOT_TEST_MARKER = Join-Path $fixture 'child.json'
$failures = @()
function Test-Case($name, [scriptblock]$body) {
    try { & $body; Write-Host "PASS $name" }
    catch { $script:failures += $name; Write-Host "FAIL $name - $($_.Exception.Message)" }
}
try {
    # Load the bootstrap functions without starting a download or displaying the splash.
    $source = Get-Content -LiteralPath (Join-Path $root 'bootstrap.ps1') -Raw
    $ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
    foreach ($fn in $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] }) {
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $env:LOCALAPPDATA = $fixture
    try { $layout = Get-QOTInstallLayout }
    finally { $env:LOCALAPPDATA = $priorEnv.LOCALAPPDATA }
    $remote = [pscustomobject]@{Owner='VoIyboo';CommitSha=('a'*40);CommitDate='2026-01-01'}
    $pkg = Join-Path $fixture 'package'
    $introDir = New-Item -Type Directory -Path (Join-Path $pkg 'src\Intro') -Force
    $intro = Join-Path $introDir.FullName 'Intro.ps1'
    Set-Content -LiteralPath $intro -Value @'
param([string]$LogPath, [switch]$Quiet)
@{ LogPath=$LogPath; Quiet=$Quiet.IsPresent } | ConvertTo-Json | Set-Content -LiteralPath $env:QOT_TEST_MARKER
if ($env:QOT_BOOTSTRAP_HANDOFF_SIGNAL) { Set-Content -LiteralPath $env:QOT_BOOTSTRAP_HANDOFF_SIGNAL -Value 'ready' }
'@
    Copy-Item -LiteralPath (Join-Path $root 'run-local.ps1') -Destination $pkg
    $archive = Join-Path $fixture 'fixture.zip'
    Compress-Archive -LiteralPath $pkg -DestinationPath $archive
    function Invoke-QOTDownloadRepoZip($Urls, $OutFile) {
        $script:urlsSeen = @($Urls)
        Copy-Item -LiteralPath $archive -Destination $OutFile
    }
    $installArgs = @{ Layout=$layout; Owners=@('VoIyboo'); RepoName='Windows-Optimiser-Toolkit'; Branch='main'; RemoteInfo=$remote }
    Test-Case 'Installed release matches the exact revision recorded in state' {
        $state = Install-QOTFromGitHub @installArgs
        if (($urlsSeen -join ',') -notmatch $remote.CommitSha -or ($urlsSeen -join ',') -match 'refs/heads') { throw "Archive URLs use a moving branch" }
        if ((Read-QOTInstallState $layout.StatePath).CommitSha -ne $remote.CommitSha) { throw 'Install state missing' }
    }
    Test-Case 'Refreshing the same revision keeps the active release usable' {
        $first = Read-QOTInstallState $layout.StatePath
        $second = Install-QOTFromGitHub @installArgs
        if ($first.InstallRoot -eq $second.InstallRoot -or !(Test-Path (Join-Path $first.InstallRoot 'src\Intro\Intro.ps1'))) {
            throw 'Refresh replaced an in-use release'
        }
        if ((Read-QOTInstallState $layout.StatePath).InstallRoot -ne $second.InstallRoot) { throw 'State was not switched' }
    }
    Test-Case 'Bootstrap and local runner launch under a profile path containing spaces' {
        $state = Read-QOTInstallState $layout.StatePath
        # Windows Shell uses the real profile for its own caches. Redirect toolkit logs only.
        Start-QOTInstalledCopy -ToolkitRoot $state.InstallRoot -LogDir $fixture
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (!(Test-Path $env:QOT_TEST_MARKER) -and $timer.Elapsed.TotalSeconds -lt 3) { Start-Sleep -Milliseconds 50 }
        $child = Get-Content -LiteralPath $env:QOT_TEST_MARKER -Raw | ConvertFrom-Json
        if (!$child.Quiet -or $child.LogPath -notlike "$fixture\*") { throw 'Child received incorrect parameters' }
    }
    Test-Case 'Batch launcher supports exclamation marks and returns the runner exit code' {
        $batchDir = Join-Path $fixture 'support! desk'
        $null = [IO.Directory]::CreateDirectory($batchDir)
        Copy-Item -LiteralPath (Join-Path $root 'Launch-Quinn.bat') -Destination $batchDir
        Set-Content -LiteralPath (Join-Path $batchDir 'run-local.ps1') -Value 'Set-Content (Join-Path $PSScriptRoot "batch-result") launched; exit 17'
        $process = Start-Process -FilePath $env:ComSpec -ArgumentList '/d /c Launch-Quinn.bat' -WorkingDirectory $batchDir -WindowStyle Hidden -PassThru -Wait
        if (!(Test-Path (Join-Path $batchDir 'batch-result')) -or $process.ExitCode -ne 17) {
            throw "Incorrect batch handoff or exit status ($($process.ExitCode))"
        }
    }
    Test-Case 'A failed update launches the last working installation' {
        # Exercise the normal remote control flow with a previously installed release.
        # Strip only declarations, retaining the bootstrap entry point and its error handling.
        $main = $source.Substring($source.IndexOf('$logDir = Get-QOTBootstrapLogDir'))
        $oldState = Read-QOTInstallState $layout.StatePath
        $ForceRemote = $true
        $ForceRefresh = [switch]$true
        $Branch = 'main'
        $originalLocation = Get-Location
        $VerboseStartup = $false
        $observed = @{}
        function Get-QOTInstallLayout { $layout }
        function Get-QOTBootstrapLogDir { $fixture }
        function Get-QOTLatestRemoteInfo { $remote }
        function Install-QOTFromGitHub { throw 'Fixture download interrupted' }
        function Start-QOTInstalledCopy($ToolkitRoot) { $observed.Root = $ToolkitRoot }
        # The failure handler must never show a modal dialog in this unattended test.
        function Add-Type { throw 'UI disabled in fixture' }
        & ([scriptblock]::Create($main))
        if ($observed.Root -ne $oldState.InstallRoot) { throw 'Usable installation was not launched' }
    }
} finally {
    Set-Location $oldLocation
    foreach ($key in $priorEnv.Keys) { [Environment]::SetEnvironmentVariable($key,$priorEnv[$key]) }
    if ((Split-Path -Parent $fixture) -eq $tempRoot -and (Split-Path -Leaf $fixture) -like 'QOT bootstrap test *') {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
if ($failures.Count) { throw "$($failures.Count) bootstrap regression(s) failed." }
