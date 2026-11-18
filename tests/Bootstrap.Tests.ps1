# No network or installed app required. The only child program is a marker-writing test script.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$oldLocation = Get-Location
$tempRoot = [IO.Path]::GetTempPath().TrimEnd('\')
$fixture = Join-Path $tempRoot ('QOT bootstrap test ' + [guid]::NewGuid())
$null = New-Item -Type Directory -Path $fixture
$priorEnv = @{}
foreach ($key in 'ProgramData','APPDATA','LOCALAPPDATA','TEMP','QOT_TEST_MARKER','QOT_BOOTSTRAP_HANDOFF_SIGNAL','QOT_SETTINGS_PATH') {
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
Add-Type -Name Console -Namespace QuinnTest -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();'
@{ LogPath=$LogPath; Quiet=$Quiet.IsPresent; Console=[QuinnTest.Console]::GetConsoleWindow().ToInt64() } | ConvertTo-Json | Set-Content -LiteralPath $env:QOT_TEST_MARKER
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
        if ($child.Console -ne 0) { throw 'A console was allocated for the toolkit window' }
    }
    Test-Case 'Bootstrap can launch an older intro directly without allocating a console' {
        $legacyRoot = Join-Path $fixture 'direct intro'
        $legacyIntro = New-Item -ItemType Directory -Path (Join-Path $legacyRoot 'src\Intro') -Force
        Copy-Item -LiteralPath $intro -Destination $legacyIntro.FullName
        Remove-Item -LiteralPath $env:QOT_TEST_MARKER -ErrorAction SilentlyContinue
        Start-QOTInstalledCopy -ToolkitRoot $legacyRoot -LogDir $fixture -VerboseStartup
        $child = Get-Content -LiteralPath $env:QOT_TEST_MARKER -Raw | ConvertFrom-Json
        if ($child.Quiet -or $child.Console -ne 0) { throw 'Verbose startup opened a console or lost its arguments' }
    }
    Test-Case 'Explorer launcher opens the runner hidden from a folder with literal shell characters' {
        $guiDir = Join-Path $fixture 'helpdesk %TEMP% & support!'
        $null = [IO.Directory]::CreateDirectory($guiDir)
        $guiLauncher = Join-Path $guiDir 'Open-Quinn.vbs'
        Copy-Item -LiteralPath (Join-Path $root 'Open-Quinn.vbs') -Destination $guiLauncher
        Set-Content -LiteralPath (Join-Path $guiDir 'run-local.ps1') -Value @'
Add-Type -Name Window -Namespace QuinnTest -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hWnd);
"@
[QuinnTest.Window]::IsWindowVisible([QuinnTest.Window]::GetConsoleWindow()) | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'visible.txt')
'@
        $hostExe = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $process = Start-Process -FilePath $hostExe -ArgumentList ('//B "{0}"' -f $guiLauncher) -WorkingDirectory $fixture -WindowStyle Hidden -PassThru -Wait
        if ($process.ExitCode -ne 0 -or (Get-Content -LiteralPath (Join-Path $guiDir 'visible.txt')) -ne 'False') {
            throw 'The hidden GUI handoff failed'
        }
    }
    $env:ProgramData = $fixture
    $env:QOT_SETTINGS_PATH = Join-Path $fixture 'settings.json'
    Test-Case 'Settings desktop shortcut targets the packaged GUI launcher' {
        $settingsUi = Import-Module (Join-Path $root 'src\Core\Settings\Settings.UI.psm1') -PassThru
        $lnk = Join-Path $fixture 'Quinn Optimiser Toolkit.lnk'
        & $settingsUi { param($path, $folder) New-QOTDesktopShortcut -ShortcutPath $path -ToolkitRoot $folder } $lnk $root
        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $shell.CreateShortcut($lnk)
            if ($shortcut.TargetPath -ne (Join-Path $env:WINDIR 'System32\wscript.exe') -or
                $shortcut.Arguments -ne ('"{0}"' -f (Join-Path $root 'Open-Quinn.vbs')) -or
                $shortcut.WorkingDirectory -ne $root) { throw 'Unexpected shortcut target, arguments or working directory' }
        } finally {
            if ($shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }
    Test-Case 'Command-prompt launcher preserves console visibility, literal paths and exit status' {
        $batchDir = Join-Path $fixture 'support! desk'
        $null = [IO.Directory]::CreateDirectory($batchDir)
        Copy-Item -LiteralPath (Join-Path $root 'Launch-Quinn.bat') -Destination $batchDir
        Set-Content -LiteralPath (Join-Path $batchDir 'run-local.ps1') -Value 'Set-Content (Join-Path $PSScriptRoot "batch-result") ([Environment]::GetCommandLineArgs()); exit 17'
        $process = Start-Process -FilePath $env:ComSpec -ArgumentList '/d /c Launch-Quinn.bat' -WorkingDirectory $batchDir -WindowStyle Hidden -PassThru -Wait
        if (!(Test-Path (Join-Path $batchDir 'batch-result')) -or $process.ExitCode -ne 17) {
            throw "Incorrect batch handoff or exit status ($($process.ExitCode))"
        }
        if ('-WindowStyle' -in (Get-Content -LiteralPath (Join-Path $batchDir 'batch-result'))) { throw 'Launcher changed the caller console visibility' }
    }
    Test-Case 'Bootstrap holds the logo through local and installed handoffs and closes it on launch failure' {
        $main = $source.Substring($source.IndexOf('$logDir = Get-QOTBootstrapLogDir'))
        $state = Read-QOTInstallState $layout.StatePath
        $installedRoot = $state.InstallRoot
        $ForceRemote = $false
        $ForceRefresh = $false
        $Branch = 'main'
        $originalLocation = Get-Location
        $steps = [Collections.Generic.List[string]]::new()
        function Get-QOTInstallLayout { $layout }
        function Get-QOTBootstrapLogDir { $fixture }
        function Get-QOTLatestRemoteInfo { $remote }
        function Get-QOTBootstrapLogoPath { }
        function New-QOTBootstrapUi { $steps.Add('show'); return 'fixture logo' }
        function Update-QOTBootstrapUi { }
        function Close-QOTBootstrapUi($Ui,[switch]$Immediate) { if ($Ui) { $steps.Add("close-$Immediate") } }
        function Add-Type { throw 'Modal errors disabled in fixture' }
        function Start-QOTInstalledCopy($ToolkitRoot) {
            if ($ToolkitRoot -ne $expectedRoot) { throw "Unexpected launch root: $ToolkitRoot" }
            $steps.Add('launch')
            if ($outcome -eq 'failure') { throw 'Fixture startup failed' }
            $steps.Add($outcome)
        }
        foreach ($folder in $pkg,$fixture) {
            # Only the package directory has src\Intro, as in a direct local launch.
            $expectedRoot = if ($folder -eq $pkg) { $pkg } else { $installedRoot }
            $driver = Join-Path $folder 'bootstrap-handoff.ps1'
            Set-Content -LiteralPath $driver -Value $main
            foreach ($outcome in 'ready','timeout','failure') {
                $steps.Clear()
                try { & $driver } catch {
                    if ($outcome -ne 'failure' -or $_.Exception.Message -ne 'Fixture startup failed') { throw }
                    $steps.Add('failure reported')
                }
                $expected = if ($outcome -eq 'failure') { 'show,launch,close-True,failure reported' } else { "show,launch,$outcome,close-True" }
                if (($steps -join ',') -ne $expected) { throw "Expected $expected, saw $($steps -join ',')" }
            }
        }
    }
    Test-Case 'Archive discovery supports literal square brackets in a profile path' {
        $unpacked = Join-Path $fixture 'staff[1]'
        $content = Join-Path $unpacked 'repository-main'
        $folder = [IO.Directory]::CreateDirectory((Join-Path $content 'src\Intro'))
        [IO.File]::WriteAllText((Join-Path $folder.FullName 'Intro.ps1'), '# fixture')
        if ((Find-QOTToolkitRoot $unpacked) -ne $content) { throw 'Could not locate the unpacked release' }
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
    Test-Case 'A damaged install record can still open a downloaded release offline' {
        $main = $source.Substring($source.IndexOf('$logDir = Get-QOTBootstrapLogDir'))
        $ForceRemote = $true
        $ForceRefresh = [switch]$false
        $Branch = 'main'
        $observed = @{}
        $originalLocation = Get-Location
        [IO.File]::WriteAllText($layout.StatePath, '{truncated')
        function Get-QOTInstallLayout { $layout }
        function Get-QOTBootstrapLogDir { $fixture }
        function Get-QOTLatestRemoteInfo { throw 'Offline' }
        function Install-QOTFromGitHub { throw 'Offline download attempted' }
        function Start-QOTInstalledCopy($ToolkitRoot) { $observed.Root = $ToolkitRoot }
        function Add-Type { throw 'UI disabled in fixture' }
        & ([scriptblock]::Create($main))
        if (!$observed.Root -or !(Test-Path -LiteralPath (Join-Path $observed.Root 'src\Intro\Intro.ps1'))) { throw 'Cached release was not launched' }
    }
} finally {
    Set-Location $oldLocation
    foreach ($key in $priorEnv.Keys) { [Environment]::SetEnvironmentVariable($key,$priorEnv[$key]) }
    if ((Split-Path -Parent $fixture) -eq $tempRoot -and (Split-Path -Leaf $fixture) -like 'QOT bootstrap test *') {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
if ($failures.Count) { throw "$($failures.Count) bootstrap regression(s) failed." }
