# AdvancedTweaks.psm1
# Advanced system and app tweaks (independent from Tweaks & Cleaning)

. (Join-Path $PSScriptRoot "..\..\Core\QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Logging\Logging.psm1") -ImporterContext 'AdvancedTweaks' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Helpers.psm1")         -ImporterContext 'AdvancedTweaks' -Force

function New-QOTOperationResult {
    param(
        [Parameter(Mandatory)][ValidateSet("Success","Skipped","Failed")][string]$Status,
        [string]$Reason,
        [string]$Error
    )

    [pscustomobject]@{
        Status = $Status
        Reason = $Reason
        Error  = $Error
    }
}

function Resolve-QOTTaskResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object[]]$Operations
    )

    $failed = @($Operations | Where-Object { $_.Status -eq "Failed" })
    if ($failed.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Failed" -Reason $failed[0].Reason -Error $failed[0].Error
    }

    $success = @($Operations | Where-Object { $_.Status -eq "Success" })
    if ($success.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Success"
    }

    $skipped = @($Operations | Where-Object { $_.Status -eq "Skipped" })
    if ($skipped.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason $skipped[0].Reason
    }

    return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Not applicable"
}

function Test-QOTRegistryAdminRequired {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^(?i)HKLM:' ) { return $true }
    if ($Path -match '(?i)\\Policies\\') { return $true }
    return $false
}

function Set-QOTRegistryValueInternal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter()][ValidateSet("DWord","String","ExpandString")][string]$Type = "DWord"
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Invalid path in task definition"
    }

    if (-not (Test-QOTIsAdmin) -and (Test-QOTRegistryAdminRequired -Path $Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
    }

    if (Test-Path -LiteralPath $Path) {
        try {
            $current = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $current) {
                $currentValue = $current.$Name
                if ($currentValue -eq $Value) {
                    return New-QOTOperationResult -Status "Skipped" -Reason "Already set"
                }
            }
        }
        catch { }
    }

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-QLog ("Advanced tweak: set {0}\\{1} = {2}" -f $Path, $Name, $Value)
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        Write-QLog ("Advanced tweak failed to set {0}\\{1}: {2}" -f $Path, $Name, $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Registry update failed" -Error $_.Exception.Message
    }
}

function Invoke-QOTRegistryTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable[]]$Operations
    )

    if (-not (Test-QOTIsAdmin)) {
        foreach ($operation in $Operations) {
            if (Test-QOTRegistryAdminRequired -Path $operation.Path) {
                return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Admin required"
            }
        }
    }

    $results = foreach ($operation in $Operations) {
        $type = $operation.Type
        if ($null -ne $type -and -not [string]::IsNullOrWhiteSpace($type)) {
            Set-QOTRegistryValueInternal -Path $operation.Path -Name $operation.Name -Value $operation.Value -Type $type
        } else {
            Set-QOTRegistryValueInternal -Path $operation.Path -Name $operation.Name -Value $operation.Value
        }
    }

    return Resolve-QOTTaskResult -Name $Name -Operations $results
}

function Remove-QOTRegistryValueInternal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Invalid path in task definition"
    }

    if (-not (Test-QOTIsAdmin) -and (Test-QOTRegistryAdminRequired -Path $Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
    }

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            return New-QOTOperationResult -Status "Skipped" -Reason "Already clear"
        }

        $current = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $current -or $current.PSObject.Properties.Name -notcontains $Name) {
            return New-QOTOperationResult -Status "Skipped" -Reason "Already clear"
        }

        Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        Write-QLog ("Advanced tweak: removed {0}\{1}" -f $Path, $Name)
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        Write-QLog ("Advanced tweak failed to remove {0}\{1}: {2}" -f $Path, $Name, $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Registry restore failed" -Error $_.Exception.Message
    }
}

function Invoke-QOTRegistryClearTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable[]]$Operations
    )

    if (-not (Test-QOTIsAdmin)) {
        foreach ($operation in $Operations) {
            if (Test-QOTRegistryAdminRequired -Path $operation.Path) {
                return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Admin required"
            }
        }
    }

    $results = foreach ($operation in $Operations) {
        Remove-QOTRegistryValueInternal -Path ([string]$operation.Path) -Name ([string]$operation.Name)
    }

    return Resolve-QOTTaskResult -Name $Name -Operations $results
}

function Set-QOTRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter()][ValidateSet("DWord","String","ExpandString")][string]$Type = "DWord"
    )

    Set-QOTRegistryValueInternal -Path $Path -Name $Name -Value $Value -Type $Type
}

function Get-QOTAdvancedAdobeBlockDomains {
    return @(
        "activate.adobe.com",
        "practivate.adobe.com",
        "lm.licenses.adobe.com",
        "na1r.services.adobe.com",
        "cc-api-data.adobe.io"
    )
}

function Get-QOTAdvancedRazerBlockDomains {
    return @(
        "installer.razerzone.com",
        "drivers.razersupport.com",
        "rzr.to"
    )
}

function Get-QOTAdvancedAdobeFirewallTargets {
    return @(
        "$env:ProgramFiles\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe",
        "$env:ProgramFiles\Common Files\Adobe\Adobe Desktop Common\ADS\Adobe Desktop Service.exe",
        "$env:ProgramFiles\Common Files\Adobe\Adobe Desktop Common\CEF\Adobe CEF Helper.exe"
    )
}

function Get-QOTAdvancedHostsPath {
    return (Join-Path $env:SystemRoot "System32\drivers\etc\hosts")
}

function Add-QOTHostsEntries {
    param(
        [Parameter(Mandatory)][string[]]$Domains
    )

    if (-not (Test-QOTIsAdmin)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
    }

    $hostsPath = Get-QOTAdvancedHostsPath

    try {
        if (-not (Test-Path -LiteralPath $hostsPath)) {
            Write-QLog "Hosts file not found; cannot add entries." "ERROR"
            return New-QOTOperationResult -Status "Failed" -Reason "Hosts file not found"
        }

        $content = Get-Content -LiteralPath $hostsPath -ErrorAction Stop
        $added = $false

        foreach ($domain in $Domains) {
            if ($content -match "\b$([Regex]::Escape($domain))\b") { continue }

            Add-Content -LiteralPath $hostsPath -Value ("0.0.0.0 {0} # QOT" -f $domain)
            $added = $true
        }

        if ($added) {
            Write-QLog "Advanced tweak: hosts entries added." "INFO"
            return New-QOTOperationResult -Status "Success"
        }

        Write-QLog "Advanced tweak: hosts entries already present." "INFO"
        return New-QOTOperationResult -Status "Skipped" -Reason "Already set"
    }
    catch {
        Write-QLog ("Advanced tweak failed to update hosts file: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Hosts update failed" -Error $_.Exception.Message
    }
}

function Remove-QOTHostsEntries {
    param(
        [Parameter(Mandatory)][string[]]$Domains
    )

    if (-not (Test-QOTIsAdmin)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
    }

    $hostsPath = Get-QOTAdvancedHostsPath

    try {
        if (-not (Test-Path -LiteralPath $hostsPath)) {
            Write-QLog "Hosts file not found; cannot remove entries." "ERROR"
            return New-QOTOperationResult -Status "Failed" -Reason "Hosts file not found"
        }

        $content = @(Get-Content -LiteralPath $hostsPath -ErrorAction Stop)
        $domainPattern = (($Domains | ForEach-Object { [Regex]::Escape($_) }) -join "|")
        if ([string]::IsNullOrWhiteSpace($domainPattern)) {
            return New-QOTOperationResult -Status "Skipped" -Reason "No domains defined"
        }

        $filtered = @($content | Where-Object {
            $line = [string]$_
            -not ($line -match "(?i)#\s*QOT\b" -and $line -match "(?i)\b($domainPattern)\b")
        })

        if ($filtered.Count -eq $content.Count) {
            Write-QLog "Advanced tweak: hosts entries already clear." "INFO"
            return New-QOTOperationResult -Status "Skipped" -Reason "Already clear"
        }

        Set-Content -LiteralPath $hostsPath -Value $filtered -Encoding ASCII -ErrorAction Stop
        Write-QLog "Advanced tweak: hosts entries removed." "INFO"
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        Write-QLog ("Advanced tweak failed to restore hosts file: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Hosts restore failed" -Error $_.Exception.Message
    }
}

function Test-QOTHostsEntriesPresent {
    param(
        [Parameter(Mandatory)][string[]]$Domains
    )

    try {
        $hostsPath = Get-QOTAdvancedHostsPath
        if (-not (Test-Path -LiteralPath $hostsPath)) { return $false }
        $content = @(Get-Content -LiteralPath $hostsPath -ErrorAction Stop)
        $domainPattern = (($Domains | ForEach-Object { [Regex]::Escape($_) }) -join "|")
        if ([string]::IsNullOrWhiteSpace($domainPattern)) { return $false }

        return [bool](@($content | Where-Object {
            $line = [string]$_
            $line -match "(?i)#\s*QOT\b" -and $line -match "(?i)\b($domainPattern)\b"
        }).Count -gt 0)
    }
    catch {
        return $null
    }
}

function Add-QOTFirewallBlockRule {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$ProgramPath
    )

    if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) {
        Write-QLog "Advanced tweak: New-NetFirewallRule not available." "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Firewall cmdlets unavailable"
    }

    if (-not (Test-QOTIsAdmin)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
    }

    if (-not (Test-Path -LiteralPath $ProgramPath)) {
        Write-QLog ("Advanced tweak: program not found for firewall block: {0}" -f $ProgramPath) "WARN"
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }

    try {
        $existing = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-QLog ("Advanced tweak: firewall rule already exists: {0}" -f $DisplayName)
            return New-QOTOperationResult -Status "Skipped" -Reason "Already set"
        }

        New-NetFirewallRule -DisplayName $DisplayName -Direction Outbound -Program $ProgramPath -Action Block | Out-Null
        Write-QLog ("Advanced tweak: firewall rule created: {0}" -f $DisplayName)
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        Write-QLog ("Advanced tweak failed to create firewall rule {0}: {1}" -f $DisplayName, $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Firewall rule failed" -Error $_.Exception.Message
    }
}

function Remove-QOTFirewallBlockRules {
    param(
        [Parameter(Mandatory)][string[]]$DisplayNames
    )

    if (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) -or -not (Get-Command Remove-NetFirewallRule -ErrorAction SilentlyContinue)) {
        Write-QLog "Advanced tweak: firewall restore cmdlets unavailable." "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Firewall cmdlets unavailable"
    }

    if (-not (Test-QOTIsAdmin)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
    }

    try {
        $removed = 0
        foreach ($displayName in @($DisplayNames)) {
            if ([string]::IsNullOrWhiteSpace($displayName)) { continue }
            $rules = @(Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue)
            foreach ($rule in $rules) {
                try {
                    $rule | Remove-NetFirewallRule -ErrorAction Stop
                    $removed++
                }
                catch {
                    return New-QOTOperationResult -Status "Failed" -Reason "Firewall restore failed" -Error $_.Exception.Message
                }
            }
        }

        if ($removed -gt 0) {
            Write-QLog ("Advanced tweak: removed {0} firewall rule(s)." -f $removed)
            return New-QOTOperationResult -Status "Success"
        }

        Write-QLog "Advanced tweak: firewall block rules already clear."
        return New-QOTOperationResult -Status "Skipped" -Reason "Already clear"
    }
    catch {
        Write-QLog ("Advanced tweak failed to remove firewall rules: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Firewall restore failed" -Error $_.Exception.Message
    }
}

function Get-QOTAdobeFirewallRuleNames {
    $names = @()
    foreach ($target in Get-QOTAdvancedAdobeFirewallTargets) {
        $names += ("QOT Block Adobe: {0}" -f [System.IO.Path]::GetFileName($target))
    }
    return $names
}

function Test-QOTFirewallRulesPresent {
    param(
        [Parameter(Mandatory)][string[]]$DisplayNames
    )

    try {
        if (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)) { return $null }
        foreach ($displayName in @($DisplayNames)) {
            if ([string]::IsNullOrWhiteSpace($displayName)) { continue }
            $rule = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($rule) { return $true }
        }
        return $false
    }
    catch {
        return $null
    }
}

function Invoke-QAdvancedAdobeNetworkBlock {
    $domains = Get-QOTAdvancedAdobeBlockDomains

    $results = @()
    $results += Add-QOTHostsEntries -Domains $domains

    foreach ($target in Get-QOTAdvancedAdobeFirewallTargets) {
        $results += Add-QOTFirewallBlockRule -DisplayName ("QOT Block Adobe: {0}" -f [System.IO.Path]::GetFileName($target)) -ProgramPath $target
    }

    return Resolve-QOTTaskResult -Name "Adobe network block" -Operations $results
}

function Invoke-QAdvancedRestoreAdobeNetworkBlock {
    $results = @()
    $results += Remove-QOTHostsEntries -Domains (Get-QOTAdvancedAdobeBlockDomains)
    $results += Remove-QOTFirewallBlockRules -DisplayNames (Get-QOTAdobeFirewallRuleNames)
    return Resolve-QOTTaskResult -Name "Restore Adobe network access" -Operations $results
}

function Invoke-QAdvancedBlockRazerInstalls {
    $result = Add-QOTHostsEntries -Domains (Get-QOTAdvancedRazerBlockDomains)
    return Resolve-QOTTaskResult -Name "Block Razer installs" -Operations @($result)
}

function Invoke-QAdvancedAllowRazerInstalls {
    $result = Remove-QOTHostsEntries -Domains (Get-QOTAdvancedRazerBlockDomains)
    return Resolve-QOTTaskResult -Name "Allow Razer installs" -Operations @($result)
}

function Invoke-QAdvancedBraveDebloat {
    $path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"

    $ops = @(
        @{ Path = $path; Name = "BraveRewardsDisabled"; Value = 1 },
        @{ Path = $path; Name = "BraveWalletDisabled"; Value = 1 },
        @{ Path = $path; Name = "TorDisabled"; Value = 1 },
        @{ Path = $path; Name = "BackgroundModeEnabled"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Brave debloat" -Operations $ops
}

function Invoke-QAdvancedRestoreBraveDebloat {
    $path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"

    $ops = @(
        @{ Path = $path; Name = "BraveRewardsDisabled" },
        @{ Path = $path; Name = "BraveWalletDisabled" },
        @{ Path = $path; Name = "TorDisabled" },
        @{ Path = $path; Name = "BackgroundModeEnabled" }
    )
    return Invoke-QOTRegistryClearTask -Name "Restore Brave settings" -Operations $ops
}

function Invoke-QAdvancedEdgeDebloat {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $ops = @(
        @{ Path = $path; Name = "HideFirstRunExperience"; Value = 1 },
        @{ Path = $path; Name = "StartupBoostEnabled"; Value = 0 },
        @{ Path = $path; Name = "BackgroundModeEnabled"; Value = 0 },
        @{ Path = $path; Name = "PromotionalTabsEnabled"; Value = 0 },
        @{ Path = $path; Name = "ShowRecommendationsEnabled"; Value = 0 },
        @{ Path = $path; Name = "EdgeShoppingAssistantEnabled"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Edge debloat" -Operations $ops
}

function Invoke-QAdvancedRestoreEdgeDebloat {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $ops = @(
        @{ Path = $path; Name = "HideFirstRunExperience" },
        @{ Path = $path; Name = "StartupBoostEnabled" },
        @{ Path = $path; Name = "BackgroundModeEnabled" },
        @{ Path = $path; Name = "PromotionalTabsEnabled" },
        @{ Path = $path; Name = "ShowRecommendationsEnabled" },
        @{ Path = $path; Name = "EdgeShoppingAssistantEnabled" }
    )
    return Invoke-QOTRegistryClearTask -Name "Restore Edge debloat settings" -Operations $ops
}

function Invoke-QAdvancedDisableEdge {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $ops = @(
        @{ Path = $path; Name = "AllowMicrosoftEdgeLaunchOnStartup"; Value = 0 },
        @{ Path = $path; Name = "AllowPrelaunch"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Disable Edge" -Operations $ops
}

function Invoke-QAdvancedEnableEdge {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $ops = @(
        @{ Path = $path; Name = "AllowMicrosoftEdgeLaunchOnStartup" },
        @{ Path = $path; Name = "AllowPrelaunch" }
    )
    return Invoke-QOTRegistryClearTask -Name "Enable Edge" -Operations $ops
}

function Invoke-QAdvancedEdgeUninstallable {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $ops = @(
        @{ Path = $path; Name = "UninstallAllowed"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Edge uninstallable" -Operations $ops
}

function Invoke-QAdvancedRestoreEdgeUninstallable {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $ops = @(
        @{ Path = $path; Name = "UninstallAllowed" }
    )
    return Invoke-QOTRegistryClearTask -Name "Restore Edge uninstall setting" -Operations $ops
}

function Invoke-QAdvancedDisableBackgroundApps {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"

    $ops = @(
        @{ Path = $path; Name = "GlobalUserDisabled"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Disable background apps" -Operations $ops
}

function Invoke-QAdvancedEnableBackgroundApps {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"

    $ops = @(
        @{ Path = $path; Name = "GlobalUserDisabled"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Enable background apps" -Operations $ops
}

function Invoke-QAdvancedDisableFullscreenOptimizations {
    $path = "HKCU:\System\GameConfigStore"

    $ops = @(
        @{ Path = $path; Name = "GameDVR_FSEBehaviorMode"; Value = 2 },
        @{ Path = $path; Name = "GameDVR_HonorUserFSEBehaviorMode"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Disable fullscreen optimizations" -Operations $ops
}

function Invoke-QAdvancedEnableFullscreenOptimizations {
    $path = "HKCU:\System\GameConfigStore"

    $ops = @(
        @{ Path = $path; Name = "GameDVR_FSEBehaviorMode"; Value = 0 },
        @{ Path = $path; Name = "GameDVR_HonorUserFSEBehaviorMode"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Enable fullscreen optimizations" -Operations $ops
}

function Invoke-QAdvancedDisableIPv6 {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"

    $ops = @(
        @{ Path = $path; Name = "DisabledComponents"; Value = 255 }
    )
    return Invoke-QOTRegistryTask -Name "Disable IPv6" -Operations $ops
}

function Invoke-QAdvancedEnableIPv6 {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"

    $ops = @(
        @{ Path = $path; Name = "DisabledComponents"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Enable IPv6" -Operations $ops
}

function Invoke-QAdvancedDisableTeredo {
    if (-not (Test-QOTIsAdmin)) {
        return New-QOTTaskResult -Name "Disable Teredo" -Status "Skipped" -Reason "Admin required"
    }

    try {
        $output = @(& netsh interface teredo set state disabled 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return New-QOTTaskResult -Name "Disable Teredo" -Status "Failed" -Reason "Teredo update failed" -Error ($output -join " ")
        }
        Write-QLog "Advanced tweak: Teredo disabled."
        return New-QOTTaskResult -Name "Disable Teredo" -Status "Success"
    }
    catch {
        Write-QLog ("Advanced tweak failed to disable Teredo: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTTaskResult -Name "Disable Teredo" -Status "Failed" -Reason "Teredo update failed" -Error $_.Exception.Message
    }
}

function Invoke-QAdvancedEnableTeredo {
    if (-not (Test-QOTIsAdmin)) {
        return New-QOTTaskResult -Name "Enable Teredo" -Status "Skipped" -Reason "Admin required"
    }

    try {
        $output = @(& netsh interface teredo set state type=client 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return New-QOTTaskResult -Name "Enable Teredo" -Status "Failed" -Reason "Teredo update failed" -Error ($output -join " ")
        }
        Write-QLog "Advanced tweak: Teredo enabled."
        return New-QOTTaskResult -Name "Enable Teredo" -Status "Success"
    }
    catch {
        Write-QLog ("Advanced tweak failed to enable Teredo: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTTaskResult -Name "Enable Teredo" -Status "Failed" -Reason "Teredo update failed" -Error $_.Exception.Message
    }
}

function Invoke-QAdvancedDisableCopilot {
    $pathMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    $pathUser = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"

    $ops = @(
        @{ Path = $pathMachine; Name = "TurnOffWindowsCopilot"; Value = 1 },
        @{ Path = $pathUser; Name = "TurnOffWindowsCopilot"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Disable Copilot" -Operations $ops
}

function Invoke-QAdvancedEnableCopilot {
    $pathMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    $pathUser = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"

    $ops = @(
        @{ Path = $pathMachine; Name = "TurnOffWindowsCopilot"; Value = 0 },
        @{ Path = $pathUser; Name = "TurnOffWindowsCopilot"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Enable Copilot" -Operations $ops
}

function Invoke-QAdvancedDisableStorageSense {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"

    $ops = @(
        @{ Path = $path; Name = "01"; Value = 0 },
        @{ Path = $path; Name = "StorageSenseEnabled"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Disable Storage Sense" -Operations $ops
}

function Invoke-QAdvancedEnableStorageSense {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"

    $ops = @(
        @{ Path = $path; Name = "01"; Value = 1 },
        @{ Path = $path; Name = "StorageSenseEnabled"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Enable Storage Sense" -Operations $ops
}

function Invoke-QAdvancedDisableNotificationTray {
    $policyPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    $legacyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"

    $ops = @(
        @{ Path = $policyPath; Name = "DisableNotificationCenter"; Value = 1 },
        @{ Path = $legacyPath; Name = "DisableNotificationCenter"; Value = 1 }
    )
    return Invoke-QOTRegistryTask -Name "Disable notification tray" -Operations $ops
}

function Invoke-QAdvancedEnableNotificationTray {
    $policyPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    $legacyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"

    $ops = @(
        @{ Path = $policyPath; Name = "DisableNotificationCenter"; Value = 0 },
        @{ Path = $legacyPath; Name = "DisableNotificationCenter"; Value = 0 }
    )
    return Invoke-QOTRegistryTask -Name "Enable notification tray" -Operations $ops
}

function Invoke-QAdvancedDisplayPerformance {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"

    $ops = @(
        @{ Path = $path; Name = "VisualFXSetting"; Value = 2 }
    )
    return Invoke-QOTRegistryTask -Name "Display performance" -Operations $ops
}

function Invoke-QAdvancedRestoreDisplayPerformance {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"

    $ops = @(
        @{ Path = $path; Name = "VisualFXSetting" }
    )
    return Invoke-QOTRegistryClearTask -Name "Restore display effects setting" -Operations $ops
}

function Get-QOTAdvancedRegistryValueSnapshot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            return [pscustomobject]@{
                Exists = $false
                Value  = $null
            }
        }

        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $item -or $item.PSObject.Properties.Name -notcontains $Name) {
            return [pscustomobject]@{
                Exists = $false
                Value  = $null
            }
        }

        return [pscustomobject]@{
            Exists = $true
            Value  = $item.$Name
        }
    }
    catch {
        return [pscustomobject]@{
            Exists = $false
            Value  = $null
        }
    }
}

function Test-QOTAdvancedRegistryValueEquals {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$ExpectedValue
    )

    $snapshot = Get-QOTAdvancedRegistryValueSnapshot -Path $Path -Name $Name
    if (-not $snapshot.Exists) { return $false }
    return ($snapshot.Value -eq $ExpectedValue)
}

function Test-QOTAdvancedLiveRegistryState {
    param(
        [Parameter(Mandatory)][object[]]$Checks,
        [ValidateSet("All","Any")][string]$Mode = "All"
    )

    $results = @()
    foreach ($check in @($Checks)) {
        if (-not $check) { continue }
        $results += [bool](Test-QOTAdvancedRegistryValueEquals -Path ([string]$check.Path) -Name ([string]$check.Name) -ExpectedValue $check.Value)
    }

    if ($results.Count -eq 0) {
        return $null
    }

    switch ($Mode) {
        "Any" { return [bool]($results -contains $true) }
        default { return [bool](-not ($results -contains $false)) }
    }
}

function Test-QOTAdvancedTeredoDisabled {
    try {
        $output = @(& netsh interface teredo show state 2>&1)
        if ($LASTEXITCODE -ne 0 -and $output.Count -eq 0) { return $null }
        return [bool](($output -join "`n") -match '(?im)^\s*Type\s*:\s*disabled\s*$')
    }
    catch {
        return $null
    }
}

function Get-QOTAdvancedTelemetryTaskStates {
    $tasks = @(
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "Microsoft Compatibility Appraiser" },
        @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "ProgramDataUpdater" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "Consolidator" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "UsbCeip" },
        @{ Path = "\Microsoft\Windows\DiskDiagnostic\"; Name = "Microsoft-Windows-DiskDiagnosticDataCollector" }
    )

    $states = @()
    foreach ($task in $tasks) {
        try {
            $scheduledTask = Get-ScheduledTask -TaskPath ([string]$task.Path) -TaskName ([string]$task.Name) -ErrorAction SilentlyContinue
            if (-not $scheduledTask) { continue }
            $states += [pscustomobject]@{
                TaskPath = [string]$task.Path
                TaskName = [string]$task.Name
                State    = [string]$scheduledTask.State
                Disabled = ([string]$scheduledTask.State -eq "Disabled")
            }
        }
        catch { }
    }

    return $states
}

function Test-QOTAdvancedTelemetryTasksDisabled {
    $states = @(Get-QOTAdvancedTelemetryTaskStates)
    if ($states.Count -eq 0) { return $null }
    return [bool](@($states | Where-Object { -not [bool]$_.Disabled }).Count -eq 0)
}

function Get-QOTAdvancedLiveToggleState {
    param(
        [Parameter(Mandatory)][string]$ActionId
    )

    switch ($ActionId) {
        "Invoke-QAdvancedDisableEdge" {
            return Test-QOTAdvancedLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "AllowMicrosoftEdgeLaunchOnStartup"; Value = 0 },
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "AllowPrelaunch"; Value = 0 }
            )
        }
        "Invoke-QAdvancedAdobeNetworkBlock" {
            $hostsPresent = Test-QOTHostsEntriesPresent -Domains (Get-QOTAdvancedAdobeBlockDomains)
            $firewallPresent = Test-QOTFirewallRulesPresent -DisplayNames (Get-QOTAdobeFirewallRuleNames)
            if ($null -eq $hostsPresent -and $null -eq $firewallPresent) { return $null }
            return [bool]($hostsPresent -eq $true -or $firewallPresent -eq $true)
        }
        "Invoke-QAdvancedBlockRazerInstalls" {
            return Test-QOTHostsEntriesPresent -Domains (Get-QOTAdvancedRazerBlockDomains)
        }
        "Invoke-QAdvancedBraveDebloat" {
            return Test-QOTAdvancedLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"; Name = "BraveRewardsDisabled"; Value = 1 },
                @{ Path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"; Name = "BraveWalletDisabled"; Value = 1 },
                @{ Path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"; Name = "TorDisabled"; Value = 1 },
                @{ Path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"; Name = "BackgroundModeEnabled"; Value = 0 }
            )
        }
        "Invoke-QAdvancedEdgeDebloat" {
            return Test-QOTAdvancedLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "HideFirstRunExperience"; Value = 1 },
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "StartupBoostEnabled"; Value = 0 },
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "BackgroundModeEnabled"; Value = 0 },
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "PromotionalTabsEnabled"; Value = 0 },
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "ShowRecommendationsEnabled"; Value = 0 },
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "EdgeShoppingAssistantEnabled"; Value = 0 }
            )
        }
        "Invoke-QAdvancedEdgeUninstallable" {
            return Test-QOTAdvancedLiveRegistryState -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "UninstallAllowed"; Value = 1 }
            )
        }
        "Invoke-QAdvancedDisableBackgroundApps" {
            return Test-QOTAdvancedLiveRegistryState -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name = "GlobalUserDisabled"; Value = 1 }
            )
        }
        "Invoke-QAdvancedDisableFullscreenOptimizations" {
            return Test-QOTAdvancedLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehaviorMode"; Value = 2 },
                @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_HonorUserFSEBehaviorMode"; Value = 1 }
            )
        }
        "Invoke-QDisableTelemetryScheduledTasks" {
            return Test-QOTAdvancedTelemetryTasksDisabled
        }
        "Invoke-QAdvancedDisableIPv6" {
            return Test-QOTAdvancedLiveRegistryState -Checks @(
                @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"; Name = "DisabledComponents"; Value = 255 }
            )
        }
        "Invoke-QAdvancedDisableTeredo" {
            return Test-QOTAdvancedTeredoDisabled
        }
        "Invoke-QAdvancedDisableCopilot" {
            return Test-QOTAdvancedLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1 },
                @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1 }
            )
        }
        "Invoke-QAdvancedDisableStorageSense" {
            return Test-QOTAdvancedLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"; Name = "01"; Value = 0 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"; Name = "StorageSenseEnabled"; Value = 0 }
            )
        }
        "Invoke-QAdvancedDisableNotificationTray" {
            return Test-QOTAdvancedLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"; Name = "DisableNotificationCenter"; Value = 1 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "DisableNotificationCenter"; Value = 1 }
            )
        }
        "Invoke-QAdvancedDisplayPerformance" {
            return Test-QOTAdvancedLiveRegistryState -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"; Name = "VisualFXSetting"; Value = 2 }
            )
        }
        default {
            return $null
        }
    }
}

Export-ModuleMember -Function `
    Invoke-QAdvancedAdobeNetworkBlock, `
    Invoke-QAdvancedRestoreAdobeNetworkBlock, `
    Invoke-QAdvancedBlockRazerInstalls, `
    Invoke-QAdvancedAllowRazerInstalls, `
    Invoke-QAdvancedBraveDebloat, `
    Invoke-QAdvancedRestoreBraveDebloat, `
    Invoke-QAdvancedEdgeDebloat, `
    Invoke-QAdvancedRestoreEdgeDebloat, `
    Invoke-QAdvancedDisableEdge, `
    Invoke-QAdvancedEnableEdge, `
    Invoke-QAdvancedEdgeUninstallable, `
    Invoke-QAdvancedRestoreEdgeUninstallable, `
    Invoke-QAdvancedDisableBackgroundApps, `
    Invoke-QAdvancedEnableBackgroundApps, `
    Invoke-QAdvancedDisableFullscreenOptimizations, `
    Invoke-QAdvancedEnableFullscreenOptimizations, `
    Invoke-QAdvancedDisableIPv6, `
    Invoke-QAdvancedEnableIPv6, `
    Invoke-QAdvancedDisableTeredo, `
    Invoke-QAdvancedEnableTeredo, `
    Invoke-QAdvancedDisableCopilot, `
    Invoke-QAdvancedEnableCopilot, `
    Invoke-QAdvancedDisableStorageSense, `
    Invoke-QAdvancedEnableStorageSense, `
    Invoke-QAdvancedDisableNotificationTray, `
    Invoke-QAdvancedEnableNotificationTray, `
    Invoke-QAdvancedDisplayPerformance, `
    Invoke-QAdvancedRestoreDisplayPerformance, `
    Get-QOTAdvancedLiveToggleState
