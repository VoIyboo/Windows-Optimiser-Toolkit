# TweaksAndPrivacy.psm1
# Quinn Optimiser Toolkit â€“ Tweaks & Privacy module
# Handles UI / privacy / telemetry / UX tweaks.

# ------------------------------
# Import core modules
# ------------------------------
. (Join-Path $PSScriptRoot "..\..\Core\QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Config\Config.psm1")   -ImporterContext 'TweaksAndPrivacy' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Logging\Logging.psm1") -ImporterContext 'TweaksAndPrivacy' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Helpers.psm1")         -ImporterContext 'TweaksAndPrivacy' -Force

function Test-QOTRegistryAdminRequired {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^(?i)HKLM:' ) { return $true }
    if ($Path -match '(?i)\\Policies\\') { return $true }
    return $false
}

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

function Set-QOTRegistryValueInternal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter()][ValidateSet("DWord","String","ExpandString")][string]$Type = "DWord",
        [switch]$DefaultValue
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Invalid path in task definition"
    }

    if (-not (Test-QOTIsAdmin) -and (Test-QOTRegistryAdminRequired -Path $Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
    }
    try {
        if (Test-Path -LiteralPath $Path) {
            try {
                $current = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
                if ($null -ne $current) {
                    $currentValue = $current.$Name
                    if ($currentValue -eq $Value) {
                        return New-QOTOperationResult -Status "Skipped" -Reason "Already set"
                    }
                }
            } catch { }
        }
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        if ($DefaultValue) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force | Out-Null
        } else {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        }
        Write-QLog ("Tweaks: set {0}\\{1} = {2}" -f $Path, $Name, $Value)
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        Write-QLog ("Tweaks: failed to set {0}\\{1}: {2}" -f $Path, $Name, $_.Exception.Message) "ERROR"
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
        $path = $operation.Path
        $value = $operation.Value
        $type = $operation.Type
        if ($operation.DefaultValue) {
            Set-QOTRegistryValueInternal -Path $path -Name "(default)" -Value $value -DefaultValue
        } else {
            if ($null -ne $type -and -not [string]::IsNullOrWhiteSpace($type)) {
                Set-QOTRegistryValueInternal -Path $path -Name $operation.Name -Value $value -Type $type
            } else {
                Set-QOTRegistryValueInternal -Path $path -Name $operation.Name -Value $value
            }
        }
    }
    $failed = @($results | Where-Object { $_.Status -eq "Failed" })
    if ($failed.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Failed" -Reason $failed[0].Reason -Error $failed[0].Error
    }

    $success = @($results | Where-Object { $_.Status -eq "Success" })
    if ($success.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Success"
    }

    $skipped = @($results | Where-Object { $_.Status -eq "Skipped" })
    if ($skipped.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason $skipped[0].Reason
    }

    return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Not applicable"
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

function Set-QOTRegistryDefaultValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    Set-QOTRegistryValueInternal -Path $Path -Name "(default)" -Value $Value -DefaultValue
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
        if ($null -eq $current) {
            return New-QOTOperationResult -Status "Skipped" -Reason "Already clear"
        }

        Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        Write-QLog ("Tweaks: removed {0}\\{1}" -f $Path, $Name)
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        Write-QLog ("Tweaks: failed to remove {0}\\{1}: {2}" -f $Path, $Name, $_.Exception.Message) "ERROR"
        return New-QOTOperationResult -Status "Failed" -Reason "Registry update failed" -Error $_.Exception.Message
    }
}

function Invoke-QOTRegistryRemovalTask {
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
        Remove-QOTRegistryValueInternal -Path $operation.Path -Name $operation.Name
    }

    $failed = @($results | Where-Object { $_.Status -eq "Failed" })
    if ($failed.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Failed" -Reason $failed[0].Reason -Error $failed[0].Error
    }

    $success = @($results | Where-Object { $_.Status -eq "Success" })
    if ($success.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Success"
    }

    $skipped = @($results | Where-Object { $_.Status -eq "Skipped" })
    if ($skipped.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason $skipped[0].Reason
    }

    return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Not applicable"
}

function Resolve-QOTTweakTaskResults {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object[]]$Results
    )

    $failed = @($Results | Where-Object { $_.Status -eq "Failed" })
    if ($failed.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Failed" -Reason $failed[0].Reason -Error $failed[0].Error
    }

    $success = @($Results | Where-Object { $_.Status -eq "Success" })
    if ($success.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Success"
    }

    $skipped = @($Results | Where-Object { $_.Status -eq "Skipped" })
    if ($skipped.Count -gt 0) {
        return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason $skipped[0].Reason
    }

    return New-QOTTaskResult -Name $Name -Status "Skipped" -Reason "Not applicable"
}
# ------------------------------
# Start menu / recommendations
# ------------------------------

function Write-QOTTaskOutcome {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][object]$Result
    )

    $status = "SKIPPED"
    switch ([string]$Result.Status) {
        "Success" { $status = "SUCCESS" }
        "Failed" { $status = "FAILED" }
        default { $status = "SKIPPED" }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Result.Reason)) {
        Write-QLog ("Task result: {0} => {1} ({2})" -f $TaskName, $status, [string]$Result.Reason)
    } else {
        Write-QLog ("Task result: {0} => {1}" -f $TaskName, $status)
    }
}

function Invoke-QOTLoggedRegistryTask {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][hashtable[]]$Operations
    )

    Write-QLog ("Now doing task: {0}" -f $TaskName)
    $result = Invoke-QOTRegistryTask -Name $TaskName -Operations $Operations
    Write-QOTTaskOutcome -TaskName $TaskName -Result $result
    return $result
}

function Invoke-QTweakStartMenuRecommendations {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Value = 1 },
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Value = 1 }
    )
    Write-QLog "Tweaks: Start menu recommendations disabled."
    return Invoke-QOTRegistryTask -Name "Start menu recommendations" -Operations $ops
}

function Invoke-QTweakEnableStartMenuRecommendations {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Value = 0 }
    )
    Write-QLog "Tweaks: Start menu recommendations enabled."
    return Invoke-QOTRegistryTask -Name "Enable start menu recommendations" -Operations $ops
}

function Invoke-QTweakSuggestedApps {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338388Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-338389Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353698Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353694Enabled"; Value = 0 },
        @{ Path = $path; Name = "SilentInstalledAppsEnabled"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1 }
    )
    Write-QLog "Tweaks: Suggested apps and promotions disabled."
    return Invoke-QOTRegistryTask -Name "Suggested apps and promotions" -Operations $ops
}

function Invoke-QTweakEnableSuggestedApps {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338388Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-338389Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-353698Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-353694Enabled"; Value = 1 },
        @{ Path = $path; Name = "SilentInstalledAppsEnabled"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 0 }
    )
    Write-QLog "Tweaks: Suggested apps and promotions enabled."
    return Invoke-QOTRegistryTask -Name "Enable suggested apps and promotions" -Operations $ops
}

function Invoke-QTweakTipsInStart {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338389Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-338393Enabled"; Value = 0 },
        @{ Path = $path; Name = "SystemPaneSuggestionsEnabled"; Value = 0 }
    )
    Write-QLog "Tweaks: Tips and suggestions in Start disabled."
    return Invoke-QOTRegistryTask -Name "Tips in Start" -Operations $ops
}

function Invoke-QTweakEnableTipsInStart {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338389Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-338393Enabled"; Value = 1 },
        @{ Path = $path; Name = "SystemPaneSuggestionsEnabled"; Value = 1 }
    )
    Write-QLog "Tweaks: Tips and suggestions in Start enabled."
    return Invoke-QOTRegistryTask -Name "Enable tips in Start" -Operations $ops
}

function Invoke-QTweakBingSearch {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Value = 0 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "CortanaConsent"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Value = 1 },
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Value = 1 }
    )
    Write-QLog "Tweaks: Bing/web results in Start search disabled."
    return Invoke-QOTRegistryTask -Name "Bing search" -Operations $ops
}

function Invoke-QTweakEnableBingSearch {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Value = 1 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "CortanaConsent"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Value = 0 }
    )
    Write-QLog "Tweaks: Bing/web results in Start search enabled."
    return Invoke-QOTRegistryTask -Name "Enable Bing search" -Operations $ops
}

function Invoke-QTweakClassicContextMenu {
    $path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    $ops = @(
        @{ Path = $path; Value = ""; DefaultValue = $true }
    )
    Write-QLog "Tweaks: Classic context menu enabled (restart Explorer for effect)."
    return Invoke-QOTRegistryTask -Name "Classic context menu" -Operations $ops
}

function Invoke-QTweakEnableModernContextMenu {
    $path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    Write-QLog "Now doing task: Enable modern context menu"

    try {
        if (-not (Test-Path -LiteralPath $path)) {
            $result = New-QOTTaskResult -Name "Enable modern context menu" -Status "Skipped" -Reason "Already set"
            Write-QOTTaskOutcome -TaskName "Enable modern context menu" -Result $result
            return $result
        }

        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        $result = New-QOTTaskResult -Name "Enable modern context menu" -Status "Success"
        Write-QOTTaskOutcome -TaskName "Enable modern context menu" -Result $result
        return $result
    }
    catch {
        Write-QLog ("Tweaks: failed to enable modern context menu: {0}" -f $_.Exception.Message) "ERROR"
        $result = New-QOTTaskResult -Name "Enable modern context menu" -Status "Failed" -Reason "Registry update failed" -Error $_.Exception.Message
        Write-QOTTaskOutcome -TaskName "Enable modern context menu" -Result $result
        return $result
    }
}

# ------------------------------
# Widgets / News & Interests
# ------------------------------
function Invoke-QTweakWidgets {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowWidgets"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0 }
    )
    Write-QLog "Tweaks: Widgets disabled."
    return Invoke-QOTRegistryTask -Name "Widgets" -Operations $ops
}

function Invoke-QTweakEnableWidgets {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowWidgets"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 1 }
    )
    $removeOps = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarDa" }
    )
    Write-QLog "Tweaks: Widgets enabled."
    $results = @(
        Invoke-QOTRegistryTask -Name "Enable widgets policies" -Operations $ops
        Invoke-QOTRegistryRemovalTask -Name "Restore widgets taskbar default" -Operations $removeOps
    )
    return Resolve-QOTTweakTaskResults -Name "Enable widgets" -Results $results
}

function Invoke-QTweakNewsAndInterests {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"; Name = "EnableFeeds"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name = "ShellFeedsTaskbarViewMode"; Value = 2 }
    )
    Write-QLog "Tweaks: News/taskbar content disabled."
    return Invoke-QOTRegistryTask -Name "News and interests" -Operations $ops
}

function Invoke-QTweakEnableNewsAndInterests {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"; Name = "EnableFeeds"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 1 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name = "ShellFeedsTaskbarViewMode"; Value = 0 }
    )
    Write-QLog "Tweaks: News/taskbar content enabled."
    return Invoke-QOTRegistryTask -Name "Enable news and interests" -Operations $ops
}

# ------------------------------
# Background apps / animations
# ------------------------------
function Invoke-QTweakBackgroundApps {
    Write-QLog "Tweaks: Limit or disable background apps (placeholder)"
}

function Invoke-QTweakAnimations {
    Write-QLog "Tweaks: Reduce / disable animations (placeholder)"
}

# ------------------------------
# Tips / advertising / feedback
# ------------------------------
function Invoke-QTweakOnlineTips {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338393Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353694Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353696Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353698Enabled"; Value = 0 }
    )
    Write-QLog "Tweaks: Online tips and suggestions disabled."
    return Invoke-QOTRegistryTask -Name "Online tips" -Operations $ops
}

function Invoke-QTweakEnableOnlineTips {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338393Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-353694Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-353696Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-353698Enabled"; Value = 1 }
    )
    Write-QLog "Tweaks: Online tips and suggestions enabled."
    return Invoke-QOTRegistryTask -Name "Enable online tips" -Operations $ops
}

function Invoke-QTweakAdvertisingId {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"; Name = "DisabledByGroupPolicy"; Value = 1 }
    )
    Write-QLog "Tweaks: Advertising ID disabled."
    return Invoke-QOTRegistryTask -Name "Advertising ID" -Operations $ops
}

function Invoke-QTweakEnableAdvertisingId {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"; Name = "DisabledByGroupPolicy"; Value = 0 }
    )
    Write-QLog "Tweaks: Advertising ID enabled."
    return Invoke-QOTRegistryTask -Name "Enable advertising ID" -Operations $ops
}

function Invoke-QTweakFeedbackHub {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Siuf\Rules"; Name = "NumberOfSIUFInPeriod"; Value = 0 },
        @{ Path = "HKCU:\Software\Microsoft\Siuf\Rules"; Name = "PeriodInNanoSeconds"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "DoNotShowFeedbackNotifications"; Value = 1 }
    )
    Write-QLog "Tweaks: Feedback and survey prompts reduced."
    return Invoke-QOTRegistryTask -Name "Feedback hub" -Operations $ops
}

function Invoke-QTweakEnableFeedbackHub {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Siuf\Rules"; Name = "NumberOfSIUFInPeriod"; Value = 1 },
        @{ Path = "HKCU:\Software\Microsoft\Siuf\Rules"; Name = "PeriodInNanoSeconds"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "DoNotShowFeedbackNotifications"; Value = 0 }
    )
    Write-QLog "Tweaks: Feedback and survey prompts enabled."
    return Invoke-QOTRegistryTask -Name "Enable feedback hub" -Operations $ops
}

function Invoke-QTweakTelemetrySafe {
    Write-QLog "Tweaks: Set telemetry to safe/minimal level (placeholder)"
}

# ------------------------------
# Meet Now / Cortana / stock apps
# ------------------------------
function Invoke-QTweakMeetNow {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideSCAMeetNow"; Value = 1 }
    )
    Write-QLog "Tweaks: Meet Now hidden."
    return Invoke-QOTRegistryTask -Name "Meet now" -Operations $ops
}

function Invoke-QTweakEnableMeetNow {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideSCAMeetNow"; Value = 0 }
    )
    Write-QLog "Tweaks: Meet Now shown."
    return Invoke-QOTRegistryTask -Name "Enable Meet now" -Operations $ops
}

function Invoke-QTweakCortanaLeftovers {
    Write-QLog "Tweaks: Turn off Cortana leftovers (placeholder)"
}

function Invoke-QRemoveStockApps {
    Write-QLog "Tweaks: Remove unused stock apps (placeholder)"
}

# ------------------------------
# Startup / Snap / mouse / explorer
# ------------------------------
function Invoke-QTweakStartupSound {
    Write-QLog "Tweaks: Turn off startup sound (placeholder)"
}

function Invoke-QTweakSnapAssist {
    Write-QLog "Tweaks: Adjust Snap Assist (placeholder)"
}

function Invoke-QTweakMouseAcceleration {
    Write-QLog "Tweaks: Disable mouse acceleration (placeholder)"
}

function Invoke-QShowHiddenFiles {
    Write-QLog "Tweaks: Show hidden files and file extensions (placeholder)"
}

function Invoke-QEnableVerboseLogon {
    Write-QLog "Tweaks: Enable verbose logon messages (placeholder)"
}

function Invoke-QDisableGameDVR {
    Write-QLog "Tweaks: Disable GameDVR (placeholder)"
}

function Invoke-QDisableAppReinstall {
    Write-QLog "Tweaks: Disable auto reinstall of apps (placeholder)"
}

function Invoke-QTweakDisableLockScreenTips {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338387Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-338388Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-338389Enabled"; Value = 0 },
        @{ Path = $path; Name = "RotatingLockScreenEnabled"; Value = 0 },
        @{ Path = $path; Name = "RotatingLockScreenOverlayEnabled"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Disable lock screen tips, suggestions, and spotlight extras" -Operations $ops
}

function Invoke-QTweakEnableLockScreenTips {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338387Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-338388Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-338389Enabled"; Value = 1 },
        @{ Path = $path; Name = "RotatingLockScreenEnabled"; Value = 1 },
        @{ Path = $path; Name = "RotatingLockScreenOverlayEnabled"; Value = 1 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Enable lock screen tips, suggestions, and spotlight extras" -Operations $ops
}

function Invoke-QTweakDisableSettingsSuggestedContent {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338393Enabled"; Value = 0 },
        @{ Path = $path; Name = "SubscribedContent-353694Enabled"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Disable Suggested content in Settings" -Operations $ops
}

function Invoke-QTweakEnableSettingsSuggestedContent {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $ops = @(
        @{ Path = $path; Name = "SubscribedContent-338393Enabled"; Value = 1 },
        @{ Path = $path; Name = "SubscribedContent-353694Enabled"; Value = 1 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Enable Suggested content in Settings" -Operations $ops
}

function Invoke-QTweakDisableTransparencyEffects {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    $ops = @(
        @{ Path = $path; Name = "EnableTransparency"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Turn off transparency effects" -Operations $ops
}

function Invoke-QTweakEnableTransparencyEffects {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    $ops = @(
        @{ Path = $path; Name = "EnableTransparency"; Value = 1 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Turn on transparency effects" -Operations $ops
}

function Invoke-QTweakDisableStartupDelay {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
    $ops = @(
        @{ Path = $path; Name = "StartupDelayInMSec"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Disable startup delay for startup apps" -Operations $ops
}

function Invoke-QTweakEnableStartupDelay {
    $ops = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"; Name = "StartupDelayInMSec" }
    )
    Write-QLog "Now doing task: Enable startup delay for startup apps"
    $result = Invoke-QOTRegistryRemovalTask -Name "Enable startup delay for startup apps" -Operations $ops
    Write-QOTTaskOutcome -TaskName "Enable startup delay for startup apps" -Result $result
    return $result
}


function Test-QOTRecallSupported {
    try {
        $cv = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
        $build = 0
        try { $build = [int]$cv.CurrentBuildNumber } catch { $build = 0 }
        return ($build -ge 26100)
    }
    catch {
        return $false
    }
}

function Invoke-QTweakDisableGameDVR {
    $ops = @(
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Value = 0 },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehaviorMode"; Value = 2 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"; Name = "AppCaptureEnabled"; Value = 0 },
        @{ Path = "HKCU:\Software\Microsoft\GameBar"; Name = "AllowAutoGameMode"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Disable Game DVR" -Operations $ops
}

function Invoke-QTweakEnableGameDVR {
    $ops = @(
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Value = 1 },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehaviorMode"; Value = 0 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"; Name = "AppCaptureEnabled"; Value = 1 },
        @{ Path = "HKCU:\Software\Microsoft\GameBar"; Name = "AllowAutoGameMode"; Value = 1 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Enable Game DVR" -Operations $ops
}

function Invoke-QTweakDisableWindowsConsumerFeatures {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SilentInstalledAppsEnabled"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Disable Windows consumer features" -Operations $ops
}

function Invoke-QTweakEnableWindowsConsumerFeatures {
    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 0 },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SilentInstalledAppsEnabled"; Value = 1 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Enable Windows consumer features" -Operations $ops
}

function Invoke-QTweakDisableWindowsRecall {
    if (-not (Test-QOTRecallSupported)) {
        $result = New-QOTTaskResult -Name "Disable Windows Recall" -Status "Skipped" -Reason "Not supported on this Windows build"
        Write-QOTTaskOutcome -TaskName "Disable Windows Recall" -Result $result
        return $result
    }

    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 1 },
        @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 1 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Disable Windows Recall" -Operations $ops
}

function Invoke-QTweakEnableWindowsRecall {
    if (-not (Test-QOTRecallSupported)) {
        $result = New-QOTTaskResult -Name "Enable Windows Recall" -Status "Skipped" -Reason "Not supported on this Windows build"
        Write-QOTTaskOutcome -TaskName "Enable Windows Recall" -Result $result
        return $result
    }

    $ops = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 0 },
        @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 0 }
    )
    return Invoke-QOTLoggedRegistryTask -TaskName "Enable Windows Recall" -Operations $ops
}

function Get-QOTRegistryValueSnapshot {
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

function Test-QOTRegistryValueEquals {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$ExpectedValue
    )

    $snapshot = Get-QOTRegistryValueSnapshot -Path $Path -Name $Name
    if (-not $snapshot.Exists) { return $false }
    return ($snapshot.Value -eq $ExpectedValue)
}

function Test-QOTRegistryPathExists {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    try {
        return [bool](Test-Path -LiteralPath $Path)
    }
    catch {
        return $false
    }
}

function Test-QOTTweaksLiveRegistryState {
    param(
        [Parameter(Mandatory)][object[]]$Checks,
        [ValidateSet("All","Any")][string]$Mode = "All"
    )

    $results = @()
    foreach ($check in @($Checks)) {
        if (-not $check) { continue }

        $matched = $false
        if ($check.ContainsKey("Exists")) {
            $matched = (Test-QOTRegistryPathExists -Path ([string]$check.Path)) -eq [bool]$check.Exists
        }
        else {
            $matched = Test-QOTRegistryValueEquals -Path ([string]$check.Path) -Name ([string]$check.Name) -ExpectedValue $check.Value
        }

        $results += [bool]$matched
    }

    if ($results.Count -eq 0) {
        return $null
    }

    switch ($Mode) {
        "Any" { return [bool]($results -contains $true) }
        default { return [bool](-not ($results -contains $false)) }
    }
}

function Get-QOTTweaksLiveToggleState {
    param(
        [Parameter(Mandatory)][string]$ActionId
    )

    switch ($ActionId) {
        "Invoke-QTweakStartMenuRecommendations" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Value = 1 },
                @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Value = 1 }
            )
        }
        "Invoke-QTweakSuggestedApps" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SilentInstalledAppsEnabled"; Value = 0 }
            )
        }
        "Invoke-QTweakTipsInStart" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SystemPaneSuggestionsEnabled"; Value = 0 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338393Enabled"; Value = 0 }
            )
        }
        "Invoke-QTweakBingSearch" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Value = 1 },
                @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Value = 1 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Value = 0 }
            )
        }
        "Invoke-QTweakClassicContextMenu" {
            return Test-QOTTweaksLiveRegistryState -Checks @(
                @{ Path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; Exists = $true }
            )
        }
        "Invoke-QTweakWidgets" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowWidgets"; Value = 0 },
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarDa"; Value = 0 }
            )
        }
        "Invoke-QTweakNewsAndInterests" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"; Name = "EnableFeeds"; Value = 0 },
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name = "ShellFeedsTaskbarViewMode"; Value = 2 }
            )
        }
        "Invoke-QTweakMeetNow" {
            return Test-QOTTweaksLiveRegistryState -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideSCAMeetNow"; Value = 1 }
            )
        }
        "Invoke-QTweakAdvertisingId" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Value = 0 },
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"; Name = "DisabledByGroupPolicy"; Value = 1 }
            )
        }
        "Invoke-QTweakFeedbackHub" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "DoNotShowFeedbackNotifications"; Value = 1 },
                @{ Path = "HKCU:\Software\Microsoft\Siuf\Rules"; Name = "NumberOfSIUFInPeriod"; Value = 0 }
            )
        }
        "Invoke-QTweakOnlineTips" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338393Enabled"; Value = 0 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-353696Enabled"; Value = 0 }
            )
        }
        "Invoke-QTweakDisableLockScreenTips" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "RotatingLockScreenEnabled"; Value = 0 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "RotatingLockScreenOverlayEnabled"; Value = 0 }
            )
        }
        "Invoke-QTweakDisableSettingsSuggestedContent" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338393Enabled"; Value = 0 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-353694Enabled"; Value = 0 }
            )
        }
        "Invoke-QTweakDisableTransparencyEffects" {
            return Test-QOTTweaksLiveRegistryState -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"; Name = "EnableTransparency"; Value = 0 }
            )
        }
        "Invoke-QTweakDisableStartupDelay" {
            return Test-QOTTweaksLiveRegistryState -Checks @(
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"; Name = "StartupDelayInMSec"; Value = 0 }
            )
        }
        "Invoke-QTweakDisableGameDVR" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Value = 0 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"; Name = "AppCaptureEnabled"; Value = 0 }
            )
        }
        "Invoke-QTweakDisableWindowsConsumerFeatures" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1 },
                @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SilentInstalledAppsEnabled"; Value = 0 }
            )
        }
        "Invoke-QTweakDisableWindowsRecall" {
            return Test-QOTTweaksLiveRegistryState -Mode "Any" -Checks @(
                @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 1 },
                @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 1 }
            )
        }
        default {
            return $null
        }
    }
}
# ------------------------------
# Exported functions
# ------------------------------
Export-ModuleMember -Function `
    Invoke-QTweakStartMenuRecommendations, `
    Invoke-QTweakEnableStartMenuRecommendations, `
    Invoke-QTweakSuggestedApps, `
    Invoke-QTweakEnableSuggestedApps, `
    Invoke-QTweakTipsInStart, `
    Invoke-QTweakEnableTipsInStart, `
    Invoke-QTweakBingSearch, `
    Invoke-QTweakEnableBingSearch, `
    Invoke-QTweakClassicContextMenu, `
    Invoke-QTweakEnableModernContextMenu, `
    Invoke-QTweakWidgets, `
    Invoke-QTweakEnableWidgets, `
    Invoke-QTweakNewsAndInterests, `
    Invoke-QTweakEnableNewsAndInterests, `
    Invoke-QTweakBackgroundApps, `
    Invoke-QTweakAnimations, `
    Invoke-QTweakOnlineTips, `
    Invoke-QTweakEnableOnlineTips, `
    Invoke-QTweakAdvertisingId, `
    Invoke-QTweakEnableAdvertisingId, `
    Invoke-QTweakFeedbackHub, `
    Invoke-QTweakEnableFeedbackHub, `
    Invoke-QTweakTelemetrySafe, `
    Invoke-QTweakMeetNow, `
    Invoke-QTweakEnableMeetNow, `
    Invoke-QTweakCortanaLeftovers, `
    Invoke-QRemoveStockApps, `
    Invoke-QTweakStartupSound, `
    Invoke-QTweakSnapAssist, `
    Invoke-QTweakMouseAcceleration, `
    Invoke-QShowHiddenFiles, `
    Invoke-QEnableVerboseLogon, `
    Invoke-QDisableGameDVR, `
    Invoke-QDisableAppReinstall, `
    Invoke-QTweakDisableLockScreenTips, `
    Invoke-QTweakEnableLockScreenTips, `
    Invoke-QTweakDisableSettingsSuggestedContent, `
    Invoke-QTweakEnableSettingsSuggestedContent, `
    Invoke-QTweakDisableTransparencyEffects, `
    Invoke-QTweakEnableTransparencyEffects, `
    Invoke-QTweakDisableStartupDelay, `
    Invoke-QTweakEnableStartupDelay, `
    Invoke-QTweakDisableGameDVR, `
    Invoke-QTweakEnableGameDVR, `
    Invoke-QTweakDisableWindowsConsumerFeatures, `
    Invoke-QTweakEnableWindowsConsumerFeatures, `
    Invoke-QTweakDisableWindowsRecall, `
    Invoke-QTweakEnableWindowsRecall, `
    Get-QOTTweaksLiveToggleState

