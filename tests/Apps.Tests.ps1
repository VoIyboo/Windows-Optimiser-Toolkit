# Run in a new STA Windows PowerShell process: powershell -NoProfile -STA -File tests/Apps.Tests.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$root = Split-Path $PSScriptRoot -Parent
$fixtureParent = [IO.Path]::GetTempPath()
$fixture = Join-Path $fixtureParent ('QotAppsTest-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$oldEnvironment = @{}
foreach ($name in @('ProgramData', 'PATH','TEMP','QOT_TEST_APP_LOG','QOT_TEST_INVENTORY_MODE')) {
    $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$failures = [Collections.Generic.List[string]]::new()
function Check([string]$Name, [scriptblock]$Test) {
    try {
        if (-not (& $Test)) { throw 'Expectation failed' }
        Write-Host "PASS $Name"
    } catch {
        $failures.Add("$Name - $($_.Exception.Message)")
        Write-Host "FAIL $Name - $($_.Exception.Message)"
    }
}
try {
    $env:ProgramData = $fixture
    $env:TEMP = $fixture
    $env:PATH = "$fixture;$env:PATH"
    $env:QOT_TEST_APP_LOG = Join-Path $fixture 'calls.txt'
    $src = Join-Path $fixture 'src'
    $null = New-Item -ItemType Directory -Path $src,(Join-Path $src 'Scripts')
    foreach ($dir in @('Core','Apps','Scripts/Apps')) {
        Copy-Item (Join-Path $root "src/$dir") (Join-Path $src $dir) -Recurse
    }
    # The scan worker imports this stub by absolute path, so a rescan never reads host inventories.
    Set-Content (Join-Path $src 'Apps/InstalledApps.psm1') @(
        'function Get-QOTInstalledApps { [pscustomobject]@{Name="Scan fixture"; Source="Win32"} }'
        'function Get-QOTInstalledAppsCached { param([switch]$ForceRefresh) Get-QOTInstalledApps }'
    )
    $exe = Join-Path $fixture 'winget.exe'
    $source = @"
using System;
using System.IO;
class FakePackageManager {
    static int Main(string[] args) {
        File.AppendAllText(Environment.GetEnvironmentVariable("QOT_TEST_APP_LOG"), String.Join("|", args) + Environment.NewLine);
        if (args[0] == "export") {
            string mode = Environment.GetEnvironmentVariable("QOT_TEST_INVENTORY_MODE");
            if (mode == "timeout") System.Threading.Thread.Sleep(20000);
            if (mode == "failed") return 17;
            int path = Array.IndexOf(args, "--output") + 1;
            File.WriteAllText(args[path], mode == "empty" ? @"{""Sources"":[]}" : @"{""Sources"":[{""Packages"":[{""PackageIdentifier"":""Notepad++.Notepad++""}]}]}");
        }
        if (args[0] == "install" && Array.IndexOf(args,"Fixture.Fail") >= 0) return 17;
        return args[0] == "fail" ? 23 : 0;
    }
}
"@
    & (Join-Path $PSScriptRoot 'New-TestExecutable.ps1') -Path $exe -Source $source
    $actions = Import-Module (Join-Path $src 'Apps/Apps.Actions.psm1') -PassThru -DisableNameChecking
    $helpers = Import-Module (Join-Path $src 'Apps/Apps.Helpers.psm1') -PassThru -DisableNameChecking
    Import-Module (Join-Path $src 'Apps/InstallCommonApps.psm1') -DisableNameChecking
    Check 'empty and singleton selections keep exact set membership' {
        $empty = Get-QOTInstalledAppNameSet -Apps @()
        $one = Get-QOTInstalledAppNameSet -Apps @([pscustomobject]@{Name='GitHub Desktop'})
        $empty -is [Collections.Generic.HashSet[string]] -and !$empty.Contains('git') -and !$one.Contains('git')
    }
    Check 'package matching distinguishes Notepad++ from Notepad' {
        !(Test-QOTCommonAppInstalled -CommonApp ([pscustomobject]@{Name='Notepad++'}) -InstalledDataset (Get-QOTInstalledAppDataset @([pscustomobject]@{Name='Notepad'})))
    }
    Check 'MSI maintenance switch becomes uninstall and retains existing quiet option' {
        (Get-QOTSilentUninstallCommand ([pscustomobject]@{UninstallString='MsiExec.exe /I{00000000-0000-0000-0000-000000000000} /qn'})) -eq 'MsiExec.exe /X{00000000-0000-0000-0000-000000000000} /qn /norestart'
    }
    Check 'an unrelated executable with msiexec in its argument stays unchanged' {
        (Get-QOTSilentUninstallCommand ([pscustomobject]@{UninstallString='sample.exe --label msiexec'})) -eq 'sample.exe --label msiexec'
    }
    Check 'valid catalogue identifiers for Python and Google Drive' {
        $ids = (Get-QOTCommonAppsCatalogue).WingetId
        $ids -contains 'Google.GoogleDrive' -and @($ids -match '^Python\.Python\.3\.\d+$').Count -eq 1
    }
    Check 'winget exact installed IDs retain punctuation' {
        (Get-QOTWingetInstalledIdSet -ForceRefresh).Contains('Notepad++.Notepad++')
    }
    Check 'hung inventory times out and reports unavailable' {
        $env:QOT_TEST_INVENTORY_MODE = 'timeout'
        $elapsed = [Diagnostics.Stopwatch]::StartNew()
        try { $null -eq (Get-QOTWingetInstalledIdSet -ForceRefresh -TimeoutSeconds 1) -and $elapsed.Elapsed.TotalSeconds -lt 8 }
        finally { $env:QOT_TEST_INVENTORY_MODE = '' }
    }
    Check 'successful empty inventory returns an empty set' {
        $env:QOT_TEST_INVENTORY_MODE = 'empty'
        try {
            $ids = Get-QOTWingetInstalledIdSet -ForceRefresh
            $null -ne $ids -and $ids.Count -eq 0
        } finally { $env:QOT_TEST_INVENTORY_MODE = '' }
    }
    Check 'failed inventory reports unavailable' {
        $env:QOT_TEST_INVENTORY_MODE = 'failed'
        try { $null -eq (Get-QOTWingetInstalledIdSet -ForceRefresh) }
        finally { $env:QOT_TEST_INVENTORY_MODE = '' }
    }
    Check 'native uninstall preserves quoted spaces and empty arguments' {
        Start-QOTProcessFromCommand -Command ('"{0}" record "two  words" ""' -f $exe) -Wait
        (Get-Content $env:QOT_TEST_APP_LOG -Tail 1) -ceq 'record|two  words|'
    }
    Check 'unquoted icon registration with spaces and an icon index resolves' {
        $folder = New-Item -ItemType Directory (Join-Path $fixture 'Tools, with spaces')
        $icon = Join-Path $folder.FullName 'Product Logo.ico'
        [IO.File]::WriteAllBytes($icon,[byte[]]@())
        (& $helpers { param($path) Resolve-QOTPathTokenFromCommandLine -CommandLine $path } ($icon + ',0')) -eq $icon
    }
    Check 'missing executable reports a failure' {
        try { Start-QOTProcessFromCommand -Command ('"{0}/absent.exe"' -f $fixture) -Wait } catch { return $true }
        $false
    }
    Check 'nonzero uninstall exit reports a failure' {
        try { Start-QOTProcessFromCommand -Command ('"{0}" fail' -f $exe) -Wait } catch { return $true }
        $false
    }
    $window = [Windows.Markup.XamlReader]::Parse('<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Grid><DataGrid x:Name="AppsGrid"/><DataGrid x:Name="InstallGrid"/></Grid></Window>')
    $grid = $window.FindName('AppsGrid')
    $install = $window.FindName('InstallGrid')
    Import-Module (Join-Path $src 'Apps/Apps.UI.psm1') -DisableNameChecking
    Check 'failed install stays visible after a registry rescan' {
        $Global:QOT_CommonAppsCollection = @([pscustomobject]@{Name='Example';WingetId='Example.App';Status='Failed';IsSelected=$true;IsInstallable=$true})
        & $helpers { Update-QOTCommonAppsInstallStatus -InstalledApps @() }
        $Global:QOT_CommonAppsCollection[0].Status -eq 'Failed'
    }
    Check 'unavailable inventory preserves confirmed installs and marks unchecked packages unknown' {
        $confirmed = [pscustomobject]@{Name='Previously installed'; WingetId='Test.Present'; Status='Installed'; IsSelected=$false}
        $unchecked = [pscustomobject]@{Name='Unchecked package'; WingetId='Test.Other'; Status='Available'; IsSelected=$false}
        $Global:QOT_CommonAppsCollection = @($confirmed, $unchecked)
        & $helpers { Update-QOTCommonAppsInstallStatus -InstalledApps @() }
        $confirmed.Status -eq 'Installed' -and $unchecked.Status -eq 'Unknown'
    }
    $Global:QOT_CommonAppsCollection = $null
    Check 'Apps UI initialises all catalogue rows' {
        (Initialize-QOTAppsUI $window) -and $install.Items.Count -eq 32
    }
    Check 'background scan updates the live grid' {
        $frame = [Windows.Threading.DispatcherFrame]::new()
        $timer = [Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(50)
        $limit = [datetime]::UtcNow.AddSeconds(4)
        $timer.Add_Tick({ if ($grid.Items.Count -gt 0 -or [datetime]::UtcNow -gt $limit) { $frame.Continue = $false } }.GetNewClosure())
        $timer.Start()
        try { [Windows.Threading.Dispatcher]::PushFrame($frame) } finally { $timer.Stop() }
        $grid.Items.Count -eq 1 -and $grid.Items[0].Name -eq 'Scan fixture'
    }
    $entry = Join-Path $src 'Scripts/Apps/Apps.RunSelected.ps1'
    Check 'first background scan matches exact ID despite a different display name' {
        ($install.Items | Where-Object WingetId -eq 'Notepad++.Notepad++').Status -eq 'Installed'
    }
    Check 'registry rows prefetched by the intro also receive an exact-ID background check' {
        $Global:QOT_ScannedWingetIds = $null
        $Global:QOT_WingetInventoryAvailable = $false
        $row = $install.Items | Where-Object WingetId -eq 'Notepad++.Notepad++'
        $row.Status = 'Unknown'
        & $helpers { param($grid) Start-QOTInstalledAppsScanAsync -AppsGrid $grid } $grid
        $frame = [Windows.Threading.DispatcherFrame]::new()
        $timer = [Windows.Threading.DispatcherTimer]::new()
        $limit = [datetime]::UtcNow.AddSeconds(5)
        $timer.Interval = [timespan]::FromMilliseconds(50)
        $timer.Add_Tick({ if ($Global:QOT_WingetInventoryAvailable -or [datetime]::UtcNow -gt $limit) { $frame.Continue = $false } }.GetNewClosure())
        $timer.Start()
        try { [Windows.Threading.Dispatcher]::PushFrame($frame) } finally { $timer.Stop() }
        $row.Status -eq 'Installed' -and $Global:QOT_WingetInventoryAvailable
    }
    $firstScan = $Global:QOT_InstalledAppsCacheTimestamp
    $installed = [pscustomobject]@{ Name='Uninstall fixture'; IsSelected=$true; Source='Win32'; UninstallString=('"{0}" fail' -f $exe) }
    $grid.ItemsSource = @($installed)
    $install.ItemsSource = @()
    Check 'Play returns the failed uninstall outcome and preserves its selection' {
        $result = & $entry -Window $window
        $result.Status -eq 'FAILED' -and $result.Reason -match '23' -and $installed.IsSelected
    }
    $installed.IsSelected = $false
    $new = [pscustomobject]@{Name='New fixture'; WingetId='Fixture.OK'; IsSelected=$true; IsInstallable=$true; Status='Available'; StatusText=''}
    $bad = [pscustomobject]@{Name='Failed fixture'; WingetId='Fixture.Fail'; IsSelected=$true; IsInstallable=$true; Status='Available'; StatusText=''}
    $install.ItemsSource = @($new,$bad)
    Check 'mixed Play install batch records both outcomes and preserves failed selection' {
        $result = & $entry -Window $window
        $result.Status -eq 'Failed' -and $result.Reason -match '17' -and $new.Status -eq 'Installed' -and !$new.IsSelected -and $bad.Status -eq 'Failed' -and $bad.IsSelected
    }
    $new.IsSelected = $false
    $bad.IsSelected = $false
    Check 'post-install inventory refresh completes in the background' {
        $limit = [datetime]::UtcNow.AddSeconds(8)
        $frame = [Windows.Threading.DispatcherFrame]::new()
        $timer = [Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [timespan]::FromMilliseconds(50)
        $timer.Add_Tick({
            if ($Global:QOT_InstalledAppsCacheTimestamp -gt $firstScan -or [datetime]::UtcNow -gt $limit) { $frame.Continue = $false }
        }.GetNewClosure())
        $timer.Start()
        try { [Windows.Threading.Dispatcher]::PushFrame($frame) } finally { $timer.Stop() }
        $null -ne $Global:QOT_ScannedWingetIds -and $Global:QOT_ScannedWingetIds.Contains('Notepad++.Notepad++')
    }
    Check 'empty selection returns skipped' { (& $entry -Window $window).Status -eq 'Skipped' }

    $scanner = Import-Module (Join-Path $root 'src/Apps/InstalledApps.psm1') -PassThru -DisableNameChecking
    Check 'an unavailable rescan retains the last installed-app inventory' {
        & $scanner {
            $offline = $false
            function Get-QOTWin32InstalledApps {
                if ($offline) { throw 'Registry unavailable' }
                [pscustomobject]@{ Name='Cached fixture'; Source='Win32'; RegistryKeyPath='HKCU:fixture' }
            }
            function Get-QOTStoreInstalledApps { if ($offline) { throw 'Store unavailable' } }
            $previous = @(Get-QOTInstalledAppsCached -ForceRefresh)
            $offline = $true
            try {
                $null = Get-QOTInstalledAppsCached -ForceRefresh
            } catch {
                return ($previous.Count -eq 1 -and $Global:QOT_InstalledAppsCache[0].Name -eq 'Cached fixture')
            }
            return $false
        }
    }
    Check 'the all-users inventory has its own cache scope' {
        & $scanner {
            function Get-QOTWin32InstalledApps { }
            function Get-QOTStoreInstalledApps([switch]$IncludeAllUsers) {
                [pscustomobject]@{ Name=if ($IncludeAllUsers) { 'All users fixture' } else { 'Current user fixture' }; Source='Store'; RegistryKeyPath='APPX:fixture' }
            }
            $current = @(Get-QOTInstalledAppsCached -ForceRefresh)
            $all = @(Get-QOTInstalledAppsCached -IncludeAllUsersStore)
            $back = @(Get-QOTInstalledAppsCached)
            $current[0].Name -eq 'Current user fixture' -and $all[0].Name -eq 'All users fixture' -and $back[0].Name -eq 'Current user fixture'
        }
    }
    $twins = @(& $scanner {
        param($fixtureExe)
        function Get-ItemProperty($Path) {
            if ($Path -like '*WOW6432Node*') { return }
            $scope = if ($Path -like 'HKCU:*') { 'user' } else { 'machine' }
            [pscustomobject]@{
                DisplayName='Twin editor'; DisplayVersion='2.1'; Publisher='Fixture'
                PSPath=($Path.TrimEnd('*') + 'TwinEditor')
                UninstallString=('"{0}" record twin-{1}' -f $fixtureExe,$scope)
            }
        }
        function Get-AppxPackage { }
        Get-QOTInstalledApps
    } $exe)
    Check 'same-name personal and machine installations remain separately identifiable' {
        $twins.Count -eq 2 -and @($twins.DisplayName | Select-Object -Unique).Count -eq 2 -and
            @($twins.RegistryKeyPath | Select-Object -Unique).Count -eq 2
    }
    Check 'two registrations for the same uninstall command run it once per batch' {
        $grid.ItemsSource = @(foreach ($key in 'HKCU:fixture','HKLM:fixture') {
            [pscustomobject]@{Name='Shared uninstall'; RegistryKeyPath=$key; UninstallString=('"{0}" fail shared' -f $exe); IsSelected=$true; Source='Win32'}
        })
        $result = & $entry -Window $window
        $calls = @(Get-Content $env:QOT_TEST_APP_LOG | Where-Object { $_ -ceq 'fail|shared' })
        $result.Status -eq 'Failed' -and $calls.Count -eq 1 -and @($grid.ItemsSource | Where-Object IsSelected).Count -eq 2
    }
    Check 'Play uses only the selected registration for identically named apps' {
        $grid.ItemsSource = $twins
        $chosen = $twins | Where-Object RegistryKeyPath -like 'HKCU:*'
        $chosen.IsSelected = $true
        $beforePlay = $Global:QOT_InstalledAppsCacheTimestamp
        $result = & $entry -Window $window
        $frame = [Windows.Threading.DispatcherFrame]::new()
        $timer = [Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [timespan]::FromMilliseconds(50)
        $limit = [datetime]::UtcNow.AddSeconds(8)
        $timer.Add_Tick({ if ($Global:QOT_InstalledAppsCacheTimestamp -gt $beforePlay -or [datetime]::UtcNow -gt $limit) { $frame.Continue = $false } }.GetNewClosure())
        $timer.Start()
        try { [Windows.Threading.Dispatcher]::PushFrame($frame) } finally { $timer.Stop() }
        $calls = @(Get-Content $env:QOT_TEST_APP_LOG | Where-Object { $_ -like 'record|twin-*' })
        $twins.Count -eq 2 -and $result.Status -eq 'Success' -and $calls.Count -eq 1 -and $calls[0] -ceq 'record|twin-user'
    }
} finally {
    foreach ($name in $oldEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name], 'Process') }
    $target = (Resolve-Path -LiteralPath $fixture).Path
    if ((Split-Path $target -Parent) -eq $fixtureParent.TrimEnd('\') -and (Split-Path $target -Leaf) -like 'QotAppsTest-*') {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}
if ($failures.Count) { throw ("{0} app regression checks failed" -f $failures.Count) }
