# src\Apps\InstalledApps.psm1
# Installed apps scanner for Apps tab

$ErrorActionPreference = "Stop"

function Test-QOTIsElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $identity) { return $false }
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-QOTAppIsRequiredWin32 {
    param([Parameter(Mandatory)][object]$RegistryItem)

    try {
        if ([int]$RegistryItem.SystemComponent -eq 1) { return $true }
    } catch { }

    $parentDisplay = ""
    $parentKey = ""
    $releaseType = ""
    $displayName = ""
    try { $parentDisplay = ("{0}" -f $RegistryItem.ParentDisplayName).Trim() } catch { }
    try { $parentKey = ("{0}" -f $RegistryItem.ParentKeyName).Trim() } catch { }
    try { $releaseType = ("{0}" -f $RegistryItem.ReleaseType).Trim() } catch { }
    try { $displayName = ("{0}" -f $RegistryItem.DisplayName).Trim() } catch { }

    if (-not [string]::IsNullOrWhiteSpace($parentDisplay) -or -not [string]::IsNullOrWhiteSpace($parentKey)) {
        return $true
    }

    if ($releaseType -match '(?i)update|hotfix|security|rollup') {
        return $true
    }

    if ($displayName -match '(?i)^KB\d+' -or $displayName -match '(?i)security update for|update for microsoft') {
        return $true
    }

    return $false
}

function Test-QOTAppIsRequiredStore {
    param([Parameter(Mandatory)][object]$AppxPackage)

    try {
        if ($AppxPackage.NonRemovable -eq $true) { return $true }
    } catch { }

    try {
        if ($AppxPackage.IsFramework -eq $true) { return $true }
    } catch { }

    try {
        if ($AppxPackage.IsResourcePackage -eq $true) { return $true }
    } catch { }

    $sigKind = ""
    $name = ""
    try { $sigKind = ("{0}" -f $AppxPackage.SignatureKind).Trim() } catch { }
    try { $name = ("{0}" -f $AppxPackage.Name).Trim() } catch { }

    if ($sigKind -match '(?i)^System$') {
        return $true
    }

    if ($name -match '^(?i)Microsoft\.VCLibs\.' -or
        $name -match '^(?i)Microsoft\.NET\.Native\.' -or
        $name -match '^(?i)Microsoft\.UI\.Xaml' -or
        $name -match '^(?i)Microsoft\.Services\.Store\.Engagement' -or
        $name -match '^(?i)Microsoft\.Advertising\.Xaml' -or
        $name -match '^(?i)Microsoft\.StorePurchaseApp$' -or
        $name -match '^(?i)Microsoft\.WindowsStore$' -or
        $name -match '^(?i)Microsoft\.Windows\.ShellExperienceHost$' -or
        $name -match '^(?i)MicrosoftWindows\.Client\.') {
        return $true
    }

    return $false
}

function Get-QOTAppRiskLevel {
    param(
        [string]$Name,
        [string]$Publisher,
        [string]$Source
    )

    $text = ("{0} {1} {2}" -f $Name, $Publisher, $Source).ToLowerInvariant()

    $advancedPatterns = @(
        'sentinel', 'crowdstrike', 'carbon black', 'cylance', 'sophos',
        'forticlient', 'zscaler', 'vpn', 'endpoint', 'intune', 'manageengine',
        'configuration manager', 'sccm', 'connectwise', 'screenconnect',
        'teamviewer host', 'splashtop', 'veeam', 'backup exec', 'sql server',
        'oracle', 'docker desktop', 'hyper-v', 'vmware', 'virtualbox',
        'nvidia driver', 'intel driver', 'realtek'
    )

    foreach ($pattern in $advancedPatterns) {
        if ($text -like "*$pattern*") {
            return 'Advanced'
        }
    }

    $cautionPatterns = @(
        'driver', 'runtime', 'redistributable', '.net', 'webview2',
        'java', 'jdk', 'python', 'node.js', 'git', 'powershell',
        'powertoys', 'onedrive', 'adobe acrobat'
    )

    foreach ($pattern in $cautionPatterns) {
        if ($text -like "*$pattern*") {
            return 'Caution'
        }
    }

    return 'Safe'
}

function Get-QOTWin32InstalledApps {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($path in $paths) {
        $items = @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            $name = ""
            try { $name = ("{0}" -f $item.DisplayName).Trim() } catch { $name = "" }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            if (Test-QOTAppIsRequiredWin32 -RegistryItem $item) { continue }

            $publisher = ""
            try { $publisher = ("{0}" -f $item.Publisher).Trim() } catch { $publisher = "" }

            $displayIcon = ""
            try { $displayIcon = ("{0}" -f $item.DisplayIcon).Trim() } catch { $displayIcon = "" }

            $installDate = $null
            $rawInstallDate = ""
            try { $rawInstallDate = ("{0}" -f $item.InstallDate).Trim() } catch { $rawInstallDate = "" }

            if (-not [string]::IsNullOrWhiteSpace($rawInstallDate)) {
                $parsed = [datetime]::MinValue
                try {
                    if ($rawInstallDate -match '^\d{8}$' -and
                        [datetime]::TryParseExact(
                            $rawInstallDate,
                            'yyyyMMdd',
                            [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::None,
                            [ref]$parsed
                        )
                    ) {
                        $installDate = $parsed
                    }
                    elseif ([datetime]::TryParse(
                        $rawInstallDate,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::None,
                        [ref]$parsed
                    )) {
                        $installDate = $parsed
                    }
                }
                catch {
                    try { Write-QLog ("Error parsing InstallDate '{0}' for '{1}': {2}" -f $rawInstallDate, $name, $_.Exception.Message) "WARN" } catch { }
                }
            }

            $uninstall = $null
            if (-not [string]::IsNullOrWhiteSpace($item.QuietUninstallString)) {
                $uninstall = $item.QuietUninstallString
            }
            elseif (-not [string]::IsNullOrWhiteSpace($item.UninstallString)) {
                $uninstall = $item.UninstallString
            }

            if ([string]::IsNullOrWhiteSpace($uninstall)) { continue }

            $regKeyPath = $null
            try { $regKeyPath = $item.PSPath } catch { $regKeyPath = $null }

            $risk = Get-QOTAppRiskLevel -Name $name -Publisher $publisher -Source 'Win32'

            $results.Add([pscustomobject]@{
                IsSelected      = $false
                Name            = $name
                InstallDate     = $installDate
                Source          = "Win32"
                PackageName     = $null
                RiskLevel       = $risk
                UninstallString = $uninstall
                RegistryKeyPath = $regKeyPath
                DisplayIcon     = $displayIcon
            })
        }
    }

    return $results.ToArray()
}

function Get-QOTStoreInstalledApps {
    param(
        [switch]$IncludeAllUsers
    )

    $results = New-Object System.Collections.Generic.List[object]

    $useAllUsers = $false
    if ($IncludeAllUsers -and (Test-QOTIsElevated)) {
        $useAllUsers = $true
    }

    $appxPackages = @()
    try {
        if ($useAllUsers) {
            $appxPackages = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
        }
        else {
            $appxPackages = @(Get-AppxPackage -ErrorAction Stop)
        }
    }
    catch {
        if ($useAllUsers) {
            try { Write-QLog ("Get-AppxPackage -AllUsers failed, falling back to current user: {0}" -f $_.Exception.Message) "WARN" } catch { }
            try { $appxPackages = @(Get-AppxPackage -ErrorAction SilentlyContinue) } catch { $appxPackages = @() }
        }
        else {
            throw
        }
    }

    foreach ($appx in $appxPackages) {
        if (-not $appx) { continue }
        if (Test-QOTAppIsRequiredStore -AppxPackage $appx) { continue }

        $name = ""
        try { $name = ("{0}" -f $appx.Name).Trim() } catch { $name = "" }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $publisher = ""
        try { $publisher = ("{0}" -f $appx.PublisherDisplayName).Trim() } catch { $publisher = "" }
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            try { $publisher = ("{0}" -f $appx.Publisher).Trim() } catch { $publisher = "" }
        }

        $fullName = $null
        try { $fullName = $appx.PackageFullName } catch { $fullName = $null }
        if ([string]::IsNullOrWhiteSpace($fullName)) { continue }

        $escaped = $fullName.Replace("'", "''")
        $uninstall = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"Remove-AppxPackage -Package '$escaped'`""

        $risk = Get-QOTAppRiskLevel -Name $name -Publisher $publisher -Source 'Store'

        $results.Add([pscustomobject]@{
            IsSelected      = $false
            Name            = $name
            InstallDate     = $null
            Source          = "Store"
            PackageName     = $name
            RiskLevel       = $risk
            UninstallString = $uninstall
            RegistryKeyPath = "APPX:$fullName"
            DisplayIcon     = ""
        })
    }

    return $results.ToArray()
}

function Get-QOTInstalledApps {
    [CmdletBinding()]
    param(
        [switch]$IncludeAllUsersStore
    )

    $scanErrors = New-Object System.Collections.Generic.List[string]

    try { Write-QLog "Starting installed apps scan" "INFO" } catch { }

    $win32Apps = @()
    try {
        $win32Apps = @(Get-QOTWin32InstalledApps)
    }
    catch {
        $scanErrors.Add($_.Exception.Message) | Out-Null
        try { Write-QLog ("Win32 app scan failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }

    $storeApps = @()
    try {
        $storeApps = @(Get-QOTStoreInstalledApps -IncludeAllUsers:$IncludeAllUsersStore)
    }
    catch {
        $scanErrors.Add($_.Exception.Message) | Out-Null
        try { Write-QLog ("Store app scan failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }

    $results = @($win32Apps + $storeApps | Sort-Object Name, Source -Unique | Sort-Object Name)

    try { Write-QLog ("Win32 found: {0}, Store found: {1}" -f $win32Apps.Count, $storeApps.Count) "INFO" } catch { }

    foreach ($err in $scanErrors) {
        if ([string]::IsNullOrWhiteSpace($err)) { continue }
        try { Write-QLog ("Any scan errors: {0}" -f $err) "ERROR" } catch { }
    }

    return $results
}

function Get-QOTInstalledAppsCached {
    param(
        [switch]$ForceRefresh,
        [switch]$IncludeAllUsersStore
    )

    if (-not $ForceRefresh -and $Global:QOT_InstalledAppsCache -and $Global:QOT_InstalledAppsCache.Count -gt 0) {
        return @($Global:QOT_InstalledAppsCache)
    }

    $results = @(Get-QOTInstalledApps -IncludeAllUsersStore:$IncludeAllUsersStore)
    $Global:QOT_InstalledAppsCache = $results
    $Global:QOT_InstalledAppsCacheTimestamp = Get-Date
    return $results
}

Export-ModuleMember -Function Get-QOTInstalledApps, Get-QOTInstalledAppsCached, Get-QOTWin32InstalledApps, Get-QOTStoreInstalledApps

