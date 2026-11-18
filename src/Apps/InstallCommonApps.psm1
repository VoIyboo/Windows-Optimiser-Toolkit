# src\Apps\InstallCommonApps.psm1
# Common apps catalogue + winget install logic
# Goals
# - Keep the Apps tab fast (do NOT run winget list during UI init)
# - Provide a static catalogue for the grid
# - Only check winget installed state when explicitly requested (optional)
# - Only run installs when Run selected actions is clicked

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\Core\QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\Core\Config\Config.psm1")   -ImporterContext 'InstallCommonApps' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\Core\Logging\Logging.psm1") -ImporterContext 'InstallCommonApps' -Force

# -------------------------------------------------------------------
# Winget installed cache (optional, on demand)
# -------------------------------------------------------------------
$script:QOT_WingetInstalledCache     = $null
$script:QOT_WingetInstalledCacheTime = [datetime]::MinValue

function Get-QOTWingetPath {
    try {
        $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { return $cmd.Source }
    } catch { }

    # Fallback for App Installer packaged winget
    try {
        $pkgRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
        $candidate = Join-Path $pkgRoot "winget.exe"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    } catch { }

    return $null
}

function Test-QOTWingetAvailable {
    try {
        $winget = Get-QOTWingetPath
        if (-not $winget) { return $false }

        $null = & $winget --version 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        try { Write-QLog ("winget availability check failed: {0}" -f $_.Exception.Message) "WARN" } catch { }
        return $false
    }
}

function Get-QOTWingetInstalledIdSet {
    param(
        [int]$CacheMinutes = 10,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 20,
        [switch]$ForceRefresh
    )

    if (-not $ForceRefresh) {
        if (((Get-Date) - $script:QOT_WingetInstalledCacheTime).TotalMinutes -lt $CacheMinutes) {
            return ,$script:QOT_WingetInstalledCache
        }
    }

    $set = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)

    # Unavailable is distinct from a successful inventory containing zero packages.
    $script:QOT_WingetInstalledCache = $null
    $script:QOT_WingetInstalledCacheTime = Get-Date
    $winget = Get-QOTWingetPath
    if (!$winget) { return $null }
    $exportPath = Join-Path ([IO.Path]::GetTempPath()) ("qot-winget-{0}.json" -f [guid]::NewGuid())
    $proc = [Diagnostics.Process]::new()
    try {
        $proc.StartInfo.FileName = $winget
        $proc.StartInfo.Arguments = ('export --output "{0}" --disable-interactivity' -f $exportPath)
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.CreateNoWindow = $true
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        [void]$proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()
        if (!$proc.WaitForExit($TimeoutSeconds * 1000)) {
            $proc.Kill()
            [void]$proc.WaitForExit(1000)
            throw "winget inventory timed out after $TimeoutSeconds seconds."
        }
        if ($proc.ExitCode -ne 0) { throw "winget export returned exit code $($proc.ExitCode)" }
        $inventory = Get-Content -LiteralPath $exportPath -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($null -eq $inventory.Sources) { throw "Unrecognised winget inventory format." }
        foreach ($source in $inventory.Sources) {
            foreach ($package in $source.Packages) {
                if ($package.PackageIdentifier) { [void]$set.Add($package.PackageIdentifier) }
            }
        }
    }
    catch {
        try { Write-QLog ("winget inventory unavailable: {0}" -f $_.Exception.Message) "WARN" } catch { }
        return $null
    }
    finally {
        $proc.Dispose()
        if (Test-Path -LiteralPath $exportPath) { Remove-Item -LiteralPath $exportPath -Force -ErrorAction SilentlyContinue }
    }

    $script:QOT_WingetInstalledCache     = $set
    $script:QOT_WingetInstalledCacheTime = Get-Date
    return ,$set
}

function Test-QOTWingetAppInstalled {
    param(
        [Parameter(Mandatory)]
        [string]$WingetId
    )

    $set = Get-QOTWingetInstalledIdSet
    return ($null -ne $set -and $set.Contains($WingetId))
}

# -------------------------------------------------------------------
# Catalogue (fast, static)
# -------------------------------------------------------------------
function Get-QOTCommonAppsCatalogue {
    <#
        .SYNOPSIS
            Returns a static catalogue for the Common app installs grid.

        .NOTES
            - This function does NOT call winget.
            - Keeps the UI fast.
            - The grid shows Unknown until its background scan finishes.
    #>

    $apps = @(
        # Browsers
        [pscustomobject]@{ IsSelected=$false; Name="Google Chrome";        WingetId="Google.Chrome";               Category="Browser" }
        [pscustomobject]@{ IsSelected=$false; Name="Mozilla Firefox";      WingetId="Mozilla.Firefox";             Category="Browser" }
        [pscustomobject]@{ IsSelected=$false; Name="Microsoft Edge";       WingetId="Microsoft.Edge";              Category="Browser" }
        [pscustomobject]@{ IsSelected=$false; Name="Brave Browser";        WingetId="Brave.Brave";                 Category="Browser" }

        # Utilities
        [pscustomobject]@{ IsSelected=$false; Name="7-Zip";                WingetId="7zip.7zip";                   Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="WinRAR";               WingetId="RARLab.WinRAR";               Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="Notepad++";            WingetId="Notepad++.Notepad++";         Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="Everything Search";    WingetId="voidtools.Everything";        Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="WinDirStat";           WingetId="WinDirStat.WinDirStat";       Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="PowerToys";            WingetId="Microsoft.PowerToys";         Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="Greenshot";            WingetId="Greenshot.Greenshot";         Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="ShareX";               WingetId="ShareX.ShareX";               Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="Adobe Acrobat Reader"; WingetId="Adobe.Acrobat.Reader.64-bit"; Category="Utility" }

        # Media
        [pscustomobject]@{ IsSelected=$false; Name="VLC Media Player";     WingetId="VideoLAN.VLC";                Category="Media" }
        [pscustomobject]@{ IsSelected=$false; Name="Spotify";              WingetId="Spotify.Spotify";             Category="Media" }
        [pscustomobject]@{ IsSelected=$false; Name="OBS Studio";           WingetId="OBSProject.OBSStudio";        Category="Media" }
        [pscustomobject]@{ IsSelected=$false; Name="Audacity";             WingetId="Audacity.Audacity";           Category="Media" }

        # Communication
        [pscustomobject]@{ IsSelected=$false; Name="Microsoft Teams";      WingetId="Microsoft.Teams";             Category="Communication" }
        [pscustomobject]@{ IsSelected=$false; Name="Zoom";                 WingetId="Zoom.Zoom";                   Category="Communication" }
        [pscustomobject]@{ IsSelected=$false; Name="Discord";              WingetId="Discord.Discord";             Category="Communication" }
        [pscustomobject]@{ IsSelected=$false; Name="Slack";                WingetId="SlackTechnologies.Slack";     Category="Communication" }

        # Dev / IT
        [pscustomobject]@{ IsSelected=$false; Name="Visual Studio Code";   WingetId="Microsoft.VisualStudioCode";  Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="Git";                  WingetId="Git.Git";                     Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="GitHub Desktop";       WingetId="GitHub.GitHubDesktop";        Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="Python 3.14";          WingetId="Python.Python.3.14";             Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="Node.js LTS";          WingetId="OpenJS.NodeJS.LTS";           Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="PuTTY";                WingetId="PuTTY.PuTTY";                 Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="WinSCP";               WingetId="WinSCP.WinSCP";               Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name=".NET Desktop Runtime 8"; WingetId="Microsoft.DotNet.DesktopRuntime.8"; Category="Dev" }

        # Cloud
        [pscustomobject]@{ IsSelected=$false; Name="OneDrive";             WingetId="Microsoft.OneDrive";          Category="Cloud" }
        [pscustomobject]@{ IsSelected=$false; Name="Google Drive";         WingetId="Google.GoogleDrive";                Category="Cloud" }
        [pscustomobject]@{ IsSelected=$false; Name="Dropbox";              WingetId="Dropbox.Dropbox";             Category="Cloud" }
    )

    return $apps
}

function Get-QOTCommonApps {
    <#
        .SYNOPSIS
            Returns common apps for the UI, optionally adding Installed/Available status.

        .PARAMETER IncludeStatus
            If set, will call winget list (cached) to mark items Installed/Available.
            Leave this OFF for fastest UI loads.
    #>
    param(
        [switch]$IncludeStatus
    )

    $catalogue = @(Get-QOTCommonAppsCatalogue)

    if (-not $IncludeStatus) {
        foreach ($app in $catalogue) {
            if ($null -eq $app.PSObject.Properties["Status"]) {
                $app | Add-Member -NotePropertyName Status -NotePropertyValue "Unknown" -Force
            } else {
                if ([string]::IsNullOrWhiteSpace([string]$app.Status)) { $app.Status = "Unknown" }
            }

            if ($null -eq $app.PSObject.Properties["IsInstallable"]) {
                $app | Add-Member -NotePropertyName IsInstallable -NotePropertyValue $true -Force
            }

            if ($null -eq $app.PSObject.Properties["Category"]) {
                $app | Add-Member -NotePropertyName Category -NotePropertyValue "" -Force
            }
        }

        return $catalogue
    }

    $set = Get-QOTWingetInstalledIdSet

    foreach ($app in $catalogue) {
        $installed = $false
        $status    = "Unknown"

        if ($null -ne $set) {
            $installed = $set.Contains($app.WingetId)
            $status = if ($installed) { "Installed" } else { "Available" }
        }

        $app | Add-Member -NotePropertyName Status        -NotePropertyValue $status -Force
        $app | Add-Member -NotePropertyName IsInstallable -NotePropertyValue (-not $installed) -Force
    }

    return $catalogue
}

# -------------------------------------------------------------------
# Install
# -------------------------------------------------------------------
function Install-QOTCommonApp {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$WingetId
    )

    $winget = Get-QOTWingetPath
    if (-not $winget) {
        $msg = "winget.exe not found. Install App Installer from Microsoft Store."
        try { Write-QLog $msg "ERROR" } catch { }
        throw $msg
    }

    if (-not (Test-QOTWingetAvailable)) {
        $msg = "winget is not available; cannot install $Name [$WingetId]."
        try { Write-QLog $msg "ERROR" } catch { }
        throw $msg
    }

    try { Write-QLog ("Starting install: {0} [{1}]" -f $Name, $WingetId) "INFO" } catch { }

    $args = @(
        "install",
        "--id", $WingetId,
        "-e",
        "--silent",
        "--disable-interactivity",
        "--accept-source-agreements",
        "--accept-package-agreements"
    )

    if ($WingetId -notmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]*$') { throw "Invalid winget package identifier." }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $winget
    $psi.Arguments              = ($args -join " ")
    $psi.CreateNoWindow         = $true
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        [void]$proc.Start()
        $outputRead = $proc.StandardOutput.ReadToEndAsync()
        $errorRead = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(600000)) { throw "winget is still running after 10 minutes. Check its status before retrying." }
        $stdout = $outputRead.GetAwaiter().GetResult()
        $stderr = $errorRead.GetAwaiter().GetResult()
        $exitCode = $proc.ExitCode
    }
    finally { $proc.Dispose() }
    if ($stdout) { try { Write-QLog ("winget output: {0}" -f $stdout.Trim()) "DEBUG" } catch { } }

    if ($exitCode -ne 0) {
        if ($stderr) { try { Write-QLog ("winget error: {0}" -f $stderr.Trim()) "ERROR" } catch { } }
        throw ("winget returned exit code {0} while installing {1} [{2}]." -f $exitCode, $Name, $WingetId)
    }

    try { Write-QLog ("Install succeeded: {0} [{1}]" -f $Name, $WingetId) "INFO" } catch { }

    if ($null -ne $script:QOT_WingetInstalledCache) { [void]$script:QOT_WingetInstalledCache.Add($WingetId) }
}

Export-ModuleMember -Function `
    Get-QOTCommonAppsCatalogue, `
    Get-QOTCommonApps, `
    Test-QOTWingetAvailable, `
    Get-QOTWingetInstalledIdSet, `
    Test-QOTWingetAppInstalled, `
    Install-QOTCommonApp
