# Run in a fresh Windows PowerShell process. All action targets below are fixtures.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$tempBase = [IO.Path]::GetTempPath()
$fixture = Join-Path $tempBase ('qot-action-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$previousData = $env:ProgramData
$previousLocal = $env:LOCALAPPDATA
$env:ProgramData = $fixture
$env:LOCALAPPDATA = $fixture
$failures = [Collections.Generic.List[string]]::new()
function Check($Condition, [string]$Description) {
    if (!$Condition) { $failures.Add($Description); Write-Host "FAIL $Description" }
}

try {
    Import-Module "$repo/src/Core/Actions/ActionsCatalog.psm1" -Force
    Initialize-QOTActionCatalog
    $catalog = @(Get-QOTActionDefinitions)
    $backends = @{}
    foreach ($action in $catalog) {
        Check (Test-Path -LiteralPath $action.ScriptPath -PathType Leaf) "Script exists for $($action.ActionId)"
        if ($action.ActionId -eq 'Apps.RunSelected') { continue }
        $body = Get-Content -Raw -LiteralPath $action.ScriptPath
        if ($body -notmatch 'Import-Module "\$PSScriptRoot(?<module>[^"]+)"') { throw "Unexpected wrapper $($action.ActionId)" }
        $module = [IO.Path]::GetFullPath((Split-Path $action.ScriptPath -Parent) + $matches['module'])
        if (!$backends.ContainsKey($module)) { $backends[$module] = Import-Module $module -PassThru }
        Check ($backends[$module].ExportedCommands.ContainsKey($action.ActionId)) "Backend exports $($action.ActionId)"
        Check (($body.Trim() -split '\r?\n')[-1].Trim() -eq $action.ActionId) "Wrapper calls $($action.ActionId)"
    }
    Write-Host "Checked $($catalog.Count) catalogue entries and $($backends.Count) backend modules"

    $actionScript = Join-Path $fixture 'test-action.ps1'
    @(
        'param($Window)'
        '$Window.Calls++'
        '"ordinary output"'
        '[pscustomobject]@{ Status=$Window.Status; Reason="fixture reason" }'
    ) | Set-Content -LiteralPath $actionScript
    $window = [pscustomobject]@{ Calls=0; Status='Failed' }
    Register-QOTActionDefinition -ActionId 'fixture' -Label 'Fixture' -ScriptPath $actionScript
    Clear-QOTActionGroups
    Check (!(Test-QOTAnyActionsSelected -Window $window)) 'Empty selection'
    Register-QOTActionGroup -Name 'Apps' -GetItems { @{ Id='fixture'; IsSelected=$true } }
    Check (Test-QOTAnyActionsSelected -Window $window) 'One checked action counts as selected'
    $result = Invoke-QOTRegisteredActions -Window $window
    Check (!$result.Success -and $result.Executed -eq 0 -and $result.FailedActionId -eq 'fixture') 'Structured failure stops the run'
    $window.Status = 'Success'
    $result = Invoke-QOTActionById -ActionId fixture -Window $window
    Check ($result -is [bool] -and $result) 'Action output does not leak into its boolean return'
    $window.Status = 'Skipped'
    $result = Invoke-QOTActionById -ActionId fixture -Window $window
    Check ($result -is [bool] -and $result) 'Skipped action permits the queue to continue'
    Register-QOTActionGroup -Name 'Advanced' -GetItems { @{Id='advanced';IsSelected=$true} }
    Register-QOTActionGroup -Name 'Tweaks & Cleaning' -GetItems { @{Id='clean';IsSelected={ param($w) $w.Calls -gt 0 }} }
    $ordered = @(Get-QOTSelectedActionsInExecutionOrder -Window $window)
    Check (($ordered.ActionId -join ',') -eq 'clean,fixture,advanced') 'Selection execution order'

    $clean = Import-Module "$repo/src/TweaksAndCleaning/CleaningAndMain/Cleaning.psm1" -PassThru
    $cache = Join-Path $fixture 'cache'
    $null = New-Item -ItemType Directory -Path $cache
    $locked = [IO.File]::Open((Join-Path $cache 'locked.db'), 'CreateNew', 'ReadWrite', 'None')
    try {
        foreach ($filtered in $true,$false) {
            $result = & $clean {
                param($p,$filtered)
                if ($filtered) { Invoke-QCleanPathFiles -Path $p -Filter '*.db' } else { Invoke-QCleanPath -Path $p }
            } $cache $filtered
            Check ($result.Status -eq 'Failed' -and $result.Error) "Locked cache file reports its error (filtered=$filtered)"
        }
    } finally { $locked.Dispose() }

    # Synthetic drive, profile and cache trees. Every system location used by these actions is redirected.
    $names = 'SystemDrive','SystemRoot','TEMP','TMP','APPDATA','LOCALAPPDATA'
    $originalPaths = @{}
    foreach ($name in $names) { $originalPaths[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
    try {
        $env:SystemDrive = Join-Path $fixture 'drive'
        $env:SystemRoot = Join-Path $env:SystemDrive 'Windows'
        $env:TEMP = Join-Path $fixture 'Temp'
        $env:TMP = $env:TEMP
        $env:APPDATA = Join-Path $fixture 'roaming'
        $env:LOCALAPPDATA = Join-Path $fixture 'local'
        $preserve = @(
            "$env:SystemDrive\Windows.old\Users\fixture\document.txt"
            "$env:SystemDrive\ESD\Recovery\install.esd"
            "$env:SystemRoot\Panther\setupact.log"
            "$env:LOCALAPPDATA\Microsoft\Teams\current\Teams.exe"
            "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\other\data"
            "$env:TEMP\QuinnOptimiserToolkit\App\Current\toolkit.ps1"
        )
        $disposable = @(
            "$env:SystemRoot\Panther\setupact.log.bak"
            "$env:APPDATA\Microsoft\Teams\Cache\data"
            "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\data"
            "$env:TEMP\ordinary\nested\data"
        )
        foreach ($path in $preserve + $disposable) {
            $null = New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force
            [IO.File]::WriteAllText($path,'fixture')
        }
        $null = Invoke-QCleanSetupLeftovers
        $null = & $clean {
            function Get-Process { }
            Invoke-QCleanTeamsCache
        }
        $null = Invoke-QCleanTemp
        foreach ($path in $preserve) { Check (Test-Path -LiteralPath $path) "Preserve $($path.Substring($fixture.Length))" }
        foreach ($path in $disposable) { Check (!(Test-Path -LiteralPath $path)) "Remove $($path.Substring($fixture.Length))" }

        $visited = [Collections.Generic.List[string]]::new()
        $null = & $clean {
            param($cache,$visited)
            function Get-ChildItem {
                # A simulated link has no real filesystem target.
                [pscustomobject]@{ FullName=(Join-Path $cache 'fixture-link'); PSIsContainer=$true; Attributes=[IO.FileAttributes]::ReparsePoint }
            }
            function Remove-Item { param($LiteralPath) $visited.Add($LiteralPath) }
            Invoke-QCleanPath -Path $cache
        } $cache $visited
        Check ($visited.Count -eq 0) 'Directory links are excluded from cleanup'
    }
    finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,$originalPaths[$name],'Process') }
    }

    foreach ($status in 'Running','Stopped','StopFails','CleanupFails','StartFails') {
        $calls = [Collections.Generic.List[string]]::new()
        $result = & $clean {
            param($status,$calls)
            function Test-QOTIsAdmin { $true }
            function Get-Service { [pscustomobject]@{ Status = if ($status -eq 'Stopped') {'Stopped'} else {'Running'} } }
            function Stop-Service { $calls.Add('stop'); if ($status -eq 'StopFails') { throw 'fixture stop error' } }
            function Start-Service { $calls.Add('start'); if ($status -eq 'StartFails') { throw 'fixture start error' } }
            function Invoke-QCleanPath {
                $calls.Add('clean')
                if ($status -eq 'CleanupFails') { throw 'fixture cleanup error' }
                New-QOTOperationResult -Status Success
            }
            try { Invoke-QCleanWindowsUpdateCache } catch { [pscustomobject]@{Status='uncaught'} }
        } $status $calls
        $expected = switch ($status) { 'Stopped' {'clean'} 'StopFails' {'stop'} default {'stop,clean,start'} }
        $outcome = if ($status -like '*Fails') {'Failed'} else {'Success'}
        Check (($calls -join ',') -eq $expected -and $result.Status -eq $outcome) "Windows Update cache preserves service state ($status), got $calls / $($result.Status)"
    }

    $network = Import-Module "$repo/src/Advanced/NetworkAndServices/NetworkAndServices.psm1" -PassThru
    $result = & $network {
        function Test-QOTIsAdmin { $true }
        function Add-Type { throw 'No confirmation UI in fixture' }
        function Invoke-QOTRunNativeCommandTask { [pscustomobject]@{Status='Unexpected reset'} }
        Invoke-QResetWindowsFirewall
    }
    Check ($result.Status -eq 'Skipped') 'Firewall reset requires an affirmative answer'

    $networkFixture = Join-Path $fixture 'network-fixture.exe'
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
class NetworkFixture {
    static int Main() {
        string folder = Path.GetDirectoryName(typeof(NetworkFixture).Assembly.Location);
        File.WriteAllText(Path.Combine(folder, "network.pid"), Process.GetCurrentProcess().Id.ToString());
        using (var watchdog = new Timer(_ => Environment.Exit(74), null, 4000, Timeout.Infinite)) {
            if (File.Exists(Path.Combine(folder, "wait.txt"))) Thread.Sleep(6000);
            Console.Error.Write(new string('x', 262144));
            Console.Out.Write("finished");
            return 0;
        }
    }
}
'@ -OutputAssembly $networkFixture -OutputType ConsoleApplication
    $runNetworkFixture = {
        param($file,$seconds)
        function Test-QOTIsAdmin { $true }
        function Get-Command { [pscustomobject]@{ Source=$file } }
        function Write-QLog { }
        Invoke-QNetworkReset -TimeoutSeconds $seconds
    }
    $result = & $network $runNetworkFixture $networkFixture 6
    Check ($result.Status -eq 'Success') 'Network process drains stdout and stderr concurrently'
    $null = New-Item -ItemType File -Path (Join-Path $fixture 'wait.txt')
    $result = & $network $runNetworkFixture $networkFixture 1
    $childId = [int](Get-Content (Join-Path $fixture 'network.pid'))
    Check ($result.Status -eq 'Failed' -and $result.Reason -match 'timed out' -and
        !(Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Network process timeout reports failure after the owned child exits'

    foreach ($failure in 'Stop','Start') {
        $result = & $network {
            param($failure)
            $probe = @{ Count=0 }
            function Get-Process {
                $probe.Count++
                if ($probe.Count -eq 1) { [pscustomobject]@{ Id=1; SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId } }
            }
            function Stop-Process { if ($failure -eq 'Stop') { throw 'fixture stop failed' } }
            function Start-Sleep { }
            function Start-Process {
                [CmdletBinding()]param($FilePath)
                if ($failure -eq 'Start') { Write-Error 'fixture launch failed' }
            }
            Invoke-QRestartWindowsExplorer
        } $failure
        Check ($result.Status -eq 'Failed') "Explorer restart reports $failure errors"
    }

    $driverModule = Import-Module "$repo/src/Advanced/AdvancedCleaning/AdvancedCleaning.psm1" -PassThru
    $driverFixture = Join-Path $fixture 'driver-fixture.cmd'
    foreach ($exitCode in 0,1) {
        @('@echo off', 'echo Publizierter Name: oem12.inf', 'echo Original Name: oem12.inf', "exit /b $exitCode") | Set-Content -LiteralPath $driverFixture -Encoding ASCII
        $result = & $driverModule {
            param($driverFixture)
            function Get-Command { [pscustomobject]@{ Source=$driverFixture } }
            Invoke-QScanUnusedDeviceDrivers
        } $driverFixture
        $ok = if ($exitCode) { $result.Status -eq 'Failed' } else { $result.Status -eq 'Success' -and $result.Reason -match '\b1\b' }
        Check $ok "Localized driver inventory and exit code $exitCode"
    }

    if ($failures.Count) { throw "$($failures.Count) action regression(s): $($failures -join ', ')" }
    Write-Host 'Action catalogue, selection, queue, cleanup and confirmation checks passed.'
} finally {
    $env:ProgramData = $previousData
    $env:LOCALAPPDATA = $previousLocal
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($fixture)) -eq $tempBase.TrimEnd('\') -and
        [IO.Path]::GetFileName($fixture) -match '^qot-action-tests-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $fixture -Force -Recurse
    }
}
