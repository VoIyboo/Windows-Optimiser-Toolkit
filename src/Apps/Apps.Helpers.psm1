# src\Apps\Apps.Helpers.psm1
# Shared helpers for Apps UI and actions

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\Core\QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\Core\Logging\Logging.psm1") -ImporterContext 'Apps.Helpers' -Force

$script:QOT_InstalledAppsScanRunspace = $null
$script:QOT_InstalledAppsScanPowerShell = $null
$script:QOT_InstalledAppsScanAsyncResult = $null
$script:QOT_InstalledAppsScanTimer = $null
$script:QOT_AppIconCache = @{}

function Commit-QOTGridEdits {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid
    )

    try {
        $Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
        $Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true) | Out-Null
    } catch { }
}

function Get-QOTNormalizedAppName {
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
    $normalized = $Name.ToLowerInvariant()
    $normalized = $normalized -replace "[^\p{L}\p{Nd}+#]", ""
    return $normalized
}

function Get-QOTInstalledAppNameSet {
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Apps = @()
    )

    $set = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($app in $Apps) {
        if (-not $app) { continue }
        $key = Get-QOTNormalizedAppName -Name $app.Name
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            [void]$set.Add($key)
        }
    }

    return ,$set
}

function Get-QOTInstalledAppDataset {
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Apps = @()
    )

    $win32NameSet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    $storeNameSet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($app in $Apps) {
        if (-not $app) { continue }

        $name = $null
        try { $name = $app.Name } catch { $name = $null }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $source = "Win32"
        try {
            if (-not [string]::IsNullOrWhiteSpace($app.Source)) {
                $source = [string]$app.Source
            }
        } catch { }

        if ($source -ieq "Store") {
            [void]$storeNameSet.Add($name)
        }
        else {
            [void]$win32NameSet.Add($name)
        }
    }

    return [pscustomobject]@{
        AllNames    = Get-QOTInstalledAppNameSet -Apps $Apps
        Win32Names  = $win32NameSet
        StoreNames  = $storeNameSet
    }
}

function Test-QOTCommonAppInstalled {
    param(
        [Parameter(Mandatory)][object]$CommonApp,
        [Parameter(Mandatory)][object]$InstalledDataset
    )

    $name = $null
    try { $name = [string]$CommonApp.Name } catch { $name = $null }
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }

    $normalizedName = Get-QOTNormalizedAppName -Name $name

    if ($InstalledDataset.AllNames.Contains($normalizedName)) {
        return $true
    }

    $storePackageName = $null
    try { $storePackageName = [string]$CommonApp.PackageName } catch { $storePackageName = $null }
    if (-not [string]::IsNullOrWhiteSpace($storePackageName) -and $InstalledDataset.StoreNames.Contains($storePackageName)) {
        return $true
    }

    $wingetId = $null
    try { $wingetId = [string]$CommonApp.WingetId } catch { $wingetId = $null }

    if (-not [string]::IsNullOrWhiteSpace($wingetId) -and $InstalledDataset.StoreNames.Contains($wingetId)) {
        return $true
    }

    return $false
}


function Update-QOTCommonAppsInstallStatus {
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$InstalledApps = @()
    )

    $commonApps = @($Global:QOT_CommonAppsCollection)
    if (-not $commonApps -or $commonApps.Count -eq 0) { return }

    $dataset = Get-QOTInstalledAppDataset -Apps $InstalledApps

    foreach ($item in $commonApps) {
        if (-not $item) { continue }
        $installed = Test-QOTCommonAppInstalled -CommonApp $item -InstalledDataset $dataset
        if (-not $installed -and $null -ne $Global:QOT_ScannedWingetIds -and $item.WingetId) {
            $installed = $Global:QOT_ScannedWingetIds.Contains([string]$item.WingetId)
        }
        if (-not $Global:QOT_WingetInventoryAvailable -and $item.Status -eq "Installed") { $installed = $true }

        if ($null -eq $item.PSObject.Properties["Status"]) {
            $item | Add-Member -NotePropertyName Status -NotePropertyValue "" -Force
        }
        if ($null -eq $item.PSObject.Properties["IsInstallable"]) {
            $item | Add-Member -NotePropertyName IsInstallable -NotePropertyValue $true -Force
        }
        if ($null -eq $item.PSObject.Properties["StatusText"]) {
            $item | Add-Member -NotePropertyName StatusText -NotePropertyValue "" -Force
        }

        if ($installed) {
            $item.Status = "Installed"
            $item.IsSelected = $false
        }
        elseif ($item.Status -ne "Failed") {
            $item.Status = if ($Global:QOT_WingetInventoryAvailable) { "Available" } else { "Unknown" }
        }
        $item.IsInstallable = -not $installed
        $item.StatusText = ("Status: {0}" -f $item.Status)
    }
}

function Resolve-QOTPathTokenFromCommandLine {
    param(
        [string]$CommandLine
    )

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }

    $candidate = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($candidate.StartsWith("@")) {
        $candidate = $candidate.Substring(1).Trim()
    }

    if ($candidate -match '^"([^"]+)"') {
        $candidate = $Matches[1]
    }
    elseif ($candidate -match '^(.+?\.(?:exe|ico|png|jpg|jpeg|bmp))(?=\s|,\s*-?\d+\s*$|$)') {
        $candidate = $Matches[1]
    }
    else { return $null }

    $candidate = $candidate.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
    if (-not (Test-Path -LiteralPath $candidate)) { return $null }
    return $candidate
}

function Get-QOTAppGlyphForItem {
    param(
        [Parameter(Mandatory)][object]$App
    )

    $name = ""
    try { $name = [string]$App.Name } catch { $name = "" }
    $name = $name.ToLowerInvariant()

    if ($name -match 'chrome|chromium|edge|firefox|brave|opera|browser') { return [string][char]0xE774 }
    if ($name -match 'teams|zoom|discord|slack|skype') { return [string][char]0xE8BD }
    if ($name -match 'visual studio|vscode|git|node|python|terminal|putty|winscp|developer') { return [string][char]0xE943 }
    if ($name -match 'onedrive|dropbox|drive|cloud') { return [string][char]0xE753 }
    if ($name -match 'vlc|spotify|obs|audacity|media') { return [string][char]0xE8B2 }
    if ($name -match '7-zip|winrar|powertoys|everything|utility|reader') { return [string][char]0xE9F9 }

    $source = ""
    try { $source = [string]$App.Source } catch { $source = "" }
    if ($source -ieq "Store") { return [string][char]0xE719 }

    return [string][char]0xE71D
}

function Resolve-QOTAppIconPath {
    param(
        [Parameter(Mandatory)][object]$App
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $displayIcon = [string]$App.DisplayIcon
        if (-not [string]::IsNullOrWhiteSpace($displayIcon)) {
            $candidates.Add($displayIcon) | Out-Null
        }
    } catch { }

    try {
        $uninstall = [string]$App.UninstallString
        if (-not [string]::IsNullOrWhiteSpace($uninstall)) {
            $candidates.Add($uninstall) | Out-Null
        }
    } catch { }

    foreach ($candidate in $candidates) {
        $path = Resolve-QOTPathTokenFromCommandLine -CommandLine $candidate
        if ([string]::IsNullOrWhiteSpace($path)) { continue }

        $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
        if ($ext -in @(".exe", ".ico", ".png", ".jpg", ".jpeg", ".bmp")) {
            return $path
        }
    }

    return $null
}

function ConvertTo-QOTAppIconImageSource {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    if ($script:QOT_AppIconCache.ContainsKey($Path)) {
        return $script:QOT_AppIconCache[$Path]
    }

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $iconSource = $null

    try {
        if ($ext -in @(".png", ".jpg", ".jpeg", ".bmp", ".ico")) {
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.UriSource = New-Object System.Uri($Path)
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.DecodePixelWidth = 20
            $bitmap.EndInit()
            $bitmap.Freeze()
            $iconSource = $bitmap
        }
        elseif ($ext -eq '.exe') {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
            if ($ico) {
                try {
                    $bmp = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                        $ico.Handle,
                        [System.Windows.Int32Rect]::Empty,
                        [System.Windows.Media.Imaging.BitmapSizeOptions]::FromWidthAndHeight(20, 20)
                    )
                    if ($bmp) {
                        $bmp.Freeze()
                        $iconSource = $bmp
                    }
                } finally { $ico.Dispose() }
            }
        }
    }
    catch { }

    $script:QOT_AppIconCache[$Path] = $iconSource
    return $iconSource
}

function Ensure-QOTInstalledAppForGrid {
    param(
        [Parameter(Mandatory)][object]$App
    )

    if ($null -eq $App.PSObject.Properties["IsSelected"]) {
        $App | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
    }
    if ($null -eq $App.PSObject.Properties["Publisher"]) {
        $App | Add-Member -NotePropertyName Publisher -NotePropertyValue "" -Force
    }
    if ($null -eq $App.PSObject.Properties["Version"]) {
        $App | Add-Member -NotePropertyName Version -NotePropertyValue "" -Force
    }
    if ($null -eq $App.PSObject.Properties["Source"]) {
        $App | Add-Member -NotePropertyName Source -NotePropertyValue "Win32" -Force
    }
    if ($null -eq $App.PSObject.Properties["InstallDate"]) {
        $App | Add-Member -NotePropertyName InstallDate -NotePropertyValue $null -Force
    }
    if ($null -eq $App.PSObject.Properties["RiskLevel"]) {
        $App | Add-Member -NotePropertyName RiskLevel -NotePropertyValue "Safe" -Force
    }
    if ($null -eq $App.PSObject.Properties["UninstallString"]) {
        $App | Add-Member -NotePropertyName UninstallString -NotePropertyValue "" -Force
    }
    if ($null -eq $App.PSObject.Properties["ActionId"]) {
        $App | Add-Member -NotePropertyName ActionId -NotePropertyValue "Apps.Uninstall" -Force
    }
    if ($null -eq $App.PSObject.Properties["DisplayIcon"]) {
        $App | Add-Member -NotePropertyName DisplayIcon -NotePropertyValue "" -Force
    }
    if ($null -eq $App.PSObject.Properties["AppIcon"]) {
        $App | Add-Member -NotePropertyName AppIcon -NotePropertyValue $null -Force
    }
    if ($null -eq $App.PSObject.Properties["AppGlyph"]) {
        $App | Add-Member -NotePropertyName AppGlyph -NotePropertyValue (Get-QOTAppGlyphForItem -App $App) -Force
    }
    if ($null -eq $App.PSObject.Properties["InstallDateText"]) {
        $App | Add-Member -NotePropertyName InstallDateText -NotePropertyValue "Installed date unavailable" -Force
    }

    if ($App.InstallDate -is [datetime]) {
        $App.InstallDateText = ("Installed {0:yyyy-MM-dd}" -f [datetime]$App.InstallDate)
    }
    else {
        $App.InstallDateText = "Installed date unavailable"
    }

    if (-not $App.AppIcon) {
        $iconPath = Resolve-QOTAppIconPath -App $App
        if (-not [string]::IsNullOrWhiteSpace($iconPath)) {
            $App.AppIcon = ConvertTo-QOTAppIconImageSource -Path $iconPath
        }
    }
}

function Ensure-QOTCommonAppForGrid {
    param(
        [Parameter(Mandatory)][object]$App
    )

    if ($null -eq $App.PSObject.Properties["IsSelected"]) {
        $App | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
    }
    if ($null -eq $App.PSObject.Properties["ActionId"]) {
        $App | Add-Member -NotePropertyName ActionId -NotePropertyValue "Apps.Install" -Force
    }
    if ($null -eq $App.PSObject.Properties["Status"]) {
        $App | Add-Member -NotePropertyName Status -NotePropertyValue "Unknown" -Force
    }
    if ($null -eq $App.PSObject.Properties["StatusText"]) {
        $App | Add-Member -NotePropertyName StatusText -NotePropertyValue "Install state unknown" -Force
    }
    if ($null -eq $App.PSObject.Properties["RiskLevel"]) {
        $App | Add-Member -NotePropertyName RiskLevel -NotePropertyValue "Safe" -Force
    }
    if ($null -eq $App.PSObject.Properties["AppIcon"]) {
        $App | Add-Member -NotePropertyName AppIcon -NotePropertyValue $null -Force
    }
    if ($null -eq $App.PSObject.Properties["AppGlyph"]) {
        $App | Add-Member -NotePropertyName AppGlyph -NotePropertyValue (Get-QOTAppGlyphForItem -App $App) -Force
    }

    $status = ""
    try { $status = [string]$App.Status } catch { $status = "" }
    if ([string]::IsNullOrWhiteSpace($status)) {
        $App.StatusText = "Install state unknown"
    }
    else {
        $App.StatusText = ("Status: {0}" -f $status)
    }
}

function Write-QOTAppsCollectionDiagnostics {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [object[]]$SourceItems
    )

    $count = @($Items).Count
    if ($count -gt 0) { return }

    $datasetItems = if ($PSBoundParameters.ContainsKey("SourceItems") -and $null -ne $SourceItems) { @($SourceItems) } else { @($Items) }
    $datasetCount = $datasetItems.Count

    $samples = @($datasetItems | ForEach-Object {
        if ($null -eq $_) { return $null }
        try { [string]$_.Name } catch { $null }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 5)

    $sampleText = if ($samples.Count -gt 0) { $samples -join ", " } else { "<none>" }
    try { Write-QLog ("{0} ItemsSource count is 0. Dataset count: {1}. Sample names: {2}" -f $Label, $datasetCount, $sampleText) "WARN" } catch { }
}

function Start-QOTInstalledAppsScanAsync {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [switch]$ForceScan,
        [int]$StaleAfterMinutes = 30
    )

    try {
        if (-not (Get-Command Get-QOTInstalledApps -ErrorAction SilentlyContinue)) {
            $null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "InstalledApps.psm1") -ImporterContext 'Apps.Helpers.ScanAsync' -Force
        }
        if (-not (Get-Command Get-QOTInstalledApps -ErrorAction SilentlyContinue)) {
            try { Write-QLog "Get-QOTInstalledApps not found. Check Apps\InstalledApps.psm1 was imported." "ERROR" } catch { }
            return
        }

        $dispatcher = $AppsGrid.Dispatcher

        $isCacheFresh = $false
        if ($Global:QOT_InstalledAppsCacheTimestamp) {
            try {
                $cacheAge = (New-TimeSpan -Start $Global:QOT_InstalledAppsCacheTimestamp -End (Get-Date)).TotalMinutes
                $isCacheFresh = ($cacheAge -lt $StaleAfterMinutes)
            } catch { $isCacheFresh = $false }
        }

        $cachedResults = $null
        if (-not $ForceScan -and $Global:QOT_InstalledAppsCache -and $Global:QOT_InstalledAppsCache.Count -gt 0 -and $isCacheFresh) {
            $cachedResults = @($Global:QOT_InstalledAppsCache)
            $dispatcher.Invoke([action]{
                $Global:QOT_InstalledAppsCollection.Clear()
                foreach ($app in $cachedResults) {
                    Ensure-QOTInstalledAppForGrid -App $app
                    $Global:QOT_InstalledAppsCollection.Add($app)
                }
            })

            Update-QOTCommonAppsInstallStatus -InstalledApps $cachedResults
            try { Write-QLog ("Installed Apps grid populated: {0} rows" -f @($Global:QOT_InstalledAppsCollection).Count) "INFO" } catch { }
            Write-QOTAppsCollectionDiagnostics -Label "Installed Apps" -Items @($Global:QOT_InstalledAppsCollection) -SourceItems $cachedResults

            try { Write-QLog ("Installed apps loaded from cache ({0} items)." -f $cachedResults.Count) "DEBUG" } catch { }
            # Intro prefetches Win32/Store rows without winget. Fill in its missing
            # inventory off the UI thread while the cached rows are already visible.
            if ($Global:QOT_WingetInventoryAvailable) { return }
        }

        if ($script:QOT_InstalledAppsScanTimer) {
            if ($ForceScan) { $script:QOT_InstalledAppsScanTimer.Tag.Rescan = $true }
            return
        }

        $installedAppsModulePath = Join-Path $PSScriptRoot "InstalledApps.psm1"
        $installModulePath = Join-Path $PSScriptRoot "InstallCommonApps.psm1"
        $script:QOT_InstalledAppsScanRunspace = [runspacefactory]::CreateRunspace()
        $script:QOT_InstalledAppsScanRunspace.Open()

        $script:QOT_InstalledAppsScanPowerShell = [powershell]::Create()
        $script:QOT_InstalledAppsScanPowerShell.Runspace = $script:QOT_InstalledAppsScanRunspace
        $null = $script:QOT_InstalledAppsScanPowerShell.AddScript({
            param(
                [string]$InstalledAppsModulePath,
                [string]$InstallModulePath,
                [object[]]$Prefetched,
                [bool]$ForceRefresh
            )

            $ErrorActionPreference = "Stop"
            if (Test-Path -LiteralPath $InstalledAppsModulePath) {
                Import-Module -Name $InstalledAppsModulePath -Force -ErrorAction Stop
            }

            $apps = $Prefetched
            if ($null -eq $apps) { $apps = @(Get-QOTInstalledAppsCached -ForceRefresh:$ForceRefresh) }
            Import-Module $InstallModulePath -ErrorAction Stop
            [pscustomobject]@{
                Apps = $apps
                WingetIds = Get-QOTWingetInstalledIdSet
            }
        }).AddArgument($installedAppsModulePath).AddArgument($installModulePath).AddArgument($cachedResults).AddArgument([bool]$ForceScan.IsPresent)

        $script:QOT_InstalledAppsScanAsyncResult = $script:QOT_InstalledAppsScanPowerShell.BeginInvoke()

        $scanTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $scanTimer.Interval = [TimeSpan]::FromMilliseconds(150)
        $scanTimer.Tag = @{ Grid = $AppsGrid; Rescan = $false }
        $scanTimer.Add_Tick({
            param($sender, $eventArgs)
            if (-not $script:QOT_InstalledAppsScanAsyncResult) {
                $sender.Stop()
                return
            }

            if (-not $script:QOT_InstalledAppsScanAsyncResult.IsCompleted) {
                return
            }

            $sender.Stop()

            $results = @()
            $scanError = $null

            try {
                $scan = $script:QOT_InstalledAppsScanPowerShell.EndInvoke($script:QOT_InstalledAppsScanAsyncResult)[0]
                $results = $scan.Apps
                $Global:QOT_WingetInventoryAvailable = $null -ne $scan.WingetIds
                if ($Global:QOT_WingetInventoryAvailable) { $Global:QOT_ScannedWingetIds = $scan.WingetIds }
            }
            catch {
                $scanError = $_.Exception
            }
            finally {
                try { $script:QOT_InstalledAppsScanPowerShell.Dispose() } catch { }
                try { $script:QOT_InstalledAppsScanRunspace.Dispose() } catch { }
                $script:QOT_InstalledAppsScanPowerShell = $null
                $script:QOT_InstalledAppsScanRunspace = $null
                $script:QOT_InstalledAppsScanAsyncResult = $null
                $script:QOT_InstalledAppsScanTimer = $null
            }

            if ($scanError) {
                try { Write-QLog ("Installed apps scan failed: {0}" -f $scanError.Message) "ERROR" } catch { }
                return
            }

            try {
                $selectedKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($old in $Global:QOT_InstalledAppsCollection) {
                    if ($old.IsSelected -and $old.RegistryKeyPath) { [void]$selectedKeys.Add($old.RegistryKeyPath) }
                }
                $Global:QOT_InstalledAppsCache = $results
                $Global:QOT_InstalledAppsCacheTimestamp = Get-Date

                $Global:QOT_InstalledAppsCollection.Clear()
                foreach ($app in $results) {
                    Ensure-QOTInstalledAppForGrid -App $app
                    if ($app.RegistryKeyPath -and $selectedKeys.Contains($app.RegistryKeyPath)) { $app.IsSelected = $true }
                    $Global:QOT_InstalledAppsCollection.Add($app)
                }
                Update-QOTCommonAppsInstallStatus -InstalledApps $results
                if ($Global:QOT_CommonAppsCollection) { [Windows.Data.CollectionViewSource]::GetDefaultView($Global:QOT_CommonAppsCollection).Refresh() }
                $installedRows = @($Global:QOT_InstalledAppsCollection).Count
                try { Write-QLog ("Installed Apps grid populated: {0} rows" -f $installedRows) "INFO" } catch { }
                Write-QOTAppsCollectionDiagnostics -Label "Installed Apps" -Items @($Global:QOT_InstalledAppsCollection) -SourceItems $results
                Write-QOTAppsCollectionDiagnostics -Label "Common App installs" -Items @($Global:QOT_CommonAppsCollection)
                try { Write-QLog ("Installed apps scan complete. Loaded {0} items." -f $results.Count) "DEBUG" } catch { }
            }
            catch {
                try { Write-QLog ("Installed apps scan completion handler failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
            }
            if ($sender.Tag.Rescan) { Start-QOTInstalledAppsScanAsync -AppsGrid $sender.Tag.Grid -ForceScan }
        })

        $script:QOT_InstalledAppsScanTimer = $scanTimer
        try { Write-QLog "Starting installed apps scan" "INFO" } catch { }
        $script:QOT_InstalledAppsScanTimer.Start()
    }
    catch {
        try { Write-QLog ("Start-QOTInstalledAppsScanAsync error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

Export-ModuleMember -Function Commit-QOTGridEdits, Get-QOTNormalizedAppName, Get-QOTInstalledAppNameSet, Get-QOTInstalledAppDataset, Test-QOTCommonAppInstalled, Update-QOTCommonAppsInstallStatus, Ensure-QOTInstalledAppForGrid, Ensure-QOTCommonAppForGrid, Write-QOTAppsCollectionDiagnostics, Start-QOTInstalledAppsScanAsync




