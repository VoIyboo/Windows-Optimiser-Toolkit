# Cleaning.psm1
# Quinn Optimiser Toolkit â€“ Cleaning module
# Contains safe system cleaning operations (temp files, caches, logs, etc.)

# ------------------------------
# Import core modules
# ------------------------------
. (Join-Path $PSScriptRoot "..\..\Core\QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Config\Config.psm1")   -ImporterContext 'Cleaning' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Logging\Logging.psm1") -ImporterContext 'Cleaning' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Core\Helpers.psm1")         -ImporterContext 'Cleaning' -Force

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

function Write-QOTTaskOutcome {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][object]$Result
    )

    $status = "SKIPPED"
    try {
        switch ([string]$Result.Status) {
            "Success" { $status = "SUCCESS" }
            "Failed" { $status = "FAILED" }
            default { $status = "SKIPPED" }
        }
    } catch { }

    $reason = $null
    try { $reason = [string]$Result.Reason } catch { $reason = $null }
    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        Write-QLog ("Task result: {0} => {1} ({2})" -f $TaskName, $status, $reason)
    } else {
        Write-QLog ("Task result: {0} => {1}" -f $TaskName, $status)
    }
}

function Test-QOTAdminRequiredFailure {
    param([Parameter(Mandatory)][object]$ErrorRecord)

    if (-not $ErrorRecord -or -not $ErrorRecord.Exception) { return $false }
    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match "Access to the path .* is denied" -or $message -match "Access is denied") {
        return $true
    }
    return $false
}

function Invoke-QOTClearFolderContents {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    Invoke-QCleanPath -Path $Path -Label $Label
}

function Remove-QOTCacheItem {
    param([Parameter(Mandatory)]$Item)

    if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Skipped linked item: $($Item.FullName)"
    }
    if ($Item.PSIsContainer) {
        # PowerShell 5.1's recursive deletion can descend into junctions.
        # Inspect each child and remove the directory only once it is empty.
        foreach ($child in (Get-ChildItem -LiteralPath $Item.FullName -Force -ErrorAction Stop)) {
            Remove-QOTCacheItem -Item $child
        }
        [IO.Directory]::Delete($Item.FullName, $false)
    }
    else {
        Remove-Item -LiteralPath $Item.FullName -Force -ErrorAction Stop
    }
}

function Invoke-QCleanPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Label,
        [string]$Filter,
        [switch]$TempFolder
    )

    if (-not $Label) { $Label = $Path }
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop)) {
            return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
        }

        $folder = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($folder -isnot [IO.DirectoryInfo] -or -not $folder.Parent) {
            return New-QOTOperationResult -Status "Skipped" -Reason "Not a cleanup folder"
        }
        for ($parent = $folder; $null -ne $parent; $parent = $parent.Parent) {
            if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                return New-QOTOperationResult -Status "Skipped" -Reason "Linked cleanup folder"
            }
        }
        if ($TempFolder) {
            $prefix = $folder.FullName.TrimEnd('\') + '\'
            foreach ($protected in @($env:SystemRoot,$env:USERPROFILE,$env:APPDATA,$env:LOCALAPPDATA,
                    $env:ProgramData,$env:ProgramFiles,[Environment]::GetFolderPath('MyDocuments'),
                    [Environment]::GetFolderPath('DesktopDirectory'))) {
                if ($protected -and ($protected -eq $folder.FullName -or $protected.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
                    return New-QOTOperationResult -Status "Skipped" -Reason "Temp path contains a protected system or user folder"
                }
            }
        }

        $options = @{ LiteralPath = $folder.FullName; Force = $true; ErrorAction = 'Stop' }
        if ($Filter) { $options.Filter = $Filter; $options.File = $true }
        $items = @(Get-ChildItem @options)
        if ($items.Count -eq 0) {
            return New-QOTOperationResult -Status "Skipped" -Reason "Already clear"
        }

        $preserved = 0
        $failed = 0
        $firstError = $null
        foreach ($item in $items) {
            try {
                if ($TempFolder -and ($item.Name -eq 'QuinnOptimiserToolkit' -or
                        $PSScriptRoot.StartsWith(($item.FullName + '\'), [StringComparison]::OrdinalIgnoreCase))) {
                    $preserved++
                    continue
                }
                Remove-QOTCacheItem -Item $item
            }
            catch {
                $failed++
                if (-not $firstError) { $firstError = $_.Exception.Message }
            }
        }
        if ($failed) {
            return New-QOTOperationResult -Status "Failed" -Reason ("Unable to remove {0} of {1} items" -f $failed, $items.Count) -Error $firstError
        }

        if ($preserved -eq $items.Count) {
            return New-QOTOperationResult -Status "Skipped" -Reason "Only toolkit files present"
        }
        Write-QLog ("Cleaning: {0} (done)" -f $Label)
        return New-QOTOperationResult -Status "Success"
    }
    catch {
        return New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }
}

function Invoke-QCleanPathFiles {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Filter,
        [string]$Label
    )

    Invoke-QCleanPath -Path $Path -Label $Label -Filter $Filter
}

# ------------------------------
# Public: Clean Windows Update cache
# ------------------------------
function Invoke-QCleanWindowsUpdateCache {
    $taskName = "Windows Update cache"
    $serviceName = "wuauserv"
    $restartService = $false
    Write-QLog "Cleaning: Windows Update cache"

    if (-not (Test-QOTIsAdmin)) {
        return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Admin required"
    }
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        if ($service.Status -eq 'Running') {
            Stop-Service -Name $serviceName -ErrorAction Stop
            $restartService = $true
        }
        elseif ($service.Status -ne 'Stopped') {
            return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason ("Service state: {0}" -f $service.Status)
        }
        $op = Invoke-QCleanPath -Path "$env:SystemRoot\SoftwareDistribution\Download" -Label $taskName
        $result = Resolve-QOTTaskResult -Name $taskName -Operations @($op)
    }
    catch {
        $result = New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }
    finally {
        if ($restartService) {
            try { Start-Service -Name $serviceName -ErrorAction Stop }
            catch {
                $result = New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Could not restart Windows Update" -Error $_.Exception.Message
            }
        }
    }
    return $result
}

# ------------------------------
# Public: Clean Delivery Optimisation cache
# ------------------------------
function Invoke-QCleanDOCache {
    Write-QLog "Cleaning: Delivery Optimisation cache"
    $op = Invoke-QCleanPath -Path "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache" -Label "Delivery Optimisation cache"
    return Resolve-QOTTaskResult -Name "Delivery Optimisation cache" -Operations @($op)
}

# ------------------------------
# Public: Clear temp folders
# ------------------------------
function Invoke-QCleanTemp {
    $taskName = "Deep clean temporary folders"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $tempPaths = @($env:TEMP, $env:TMP, (Join-Path $env:SystemRoot 'Temp'))
    $usersRoot = Join-Path $env:SystemDrive "Users"
    if (Test-Path -LiteralPath $usersRoot -ErrorAction SilentlyContinue) {
        try {
            $profileDirs = @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue)
            foreach ($profileDir in $profileDirs) {
                if (-not $profileDir) { continue }
                $profileTemp = Join-Path $profileDir.FullName "AppData\Local\Temp"
                if (-not (Test-Path -LiteralPath $profileTemp -ErrorAction SilentlyContinue)) { continue }
                $tempPaths += $profileTemp
            }
        }
        catch {
            Write-QLog "User profile temp scan unavailable" "WARN"
        }
    }

    $ops = @(foreach ($path in ($tempPaths | Where-Object { $_ } | Sort-Object -Unique)) {
        Invoke-QCleanPath -Path $path -Label "Temporary files ($path)" -TempFolder
    })
    $result = Resolve-QOTTaskResult -Name $taskName -Operations $ops
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

# ------------------------------
# Public: Empty Recycle Bin
# ------------------------------
function Invoke-QCleanRecycleBin {
    Write-QLog "Cleaning: Recycle Bin"
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
        Write-QLog "Cleaning: Recycle Bin (done)"
        return New-QOTTaskResult -Name "Recycle Bin" -Status "Success"
    }
    catch {
        Write-QLog ("Cleaning: Recycle Bin failed: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTTaskResult -Name "Recycle Bin" -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }
}

# ------------------------------
# Public: Thumbnail cache
# ------------------------------
function Invoke-QCleanThumbnailCache {
    Write-QLog "Cleaning: Thumbnail cache"
    $thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    $ops = @(
        Invoke-QCleanPathFiles -Path $thumbPath -Filter "thumbcache*.db" -Label "Thumbnail cache"
        Invoke-QCleanPathFiles -Path $thumbPath -Filter "iconcache*.db" -Label "Icon cache"
    )
    return Resolve-QOTTaskResult -Name "Thumbnail cache" -Operations $ops
}

# ------------------------------
# Public: Error logs / crash dumps
# ------------------------------
function Invoke-QCleanErrorLogs {
    Write-QLog "Cleaning: Error logs and crash dumps"
    $ops = @(
        Invoke-QCleanPath -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -Label "Windows Error Reporting archives"
        Invoke-QCleanPath -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Label "Windows Error Reporting queue"
        Invoke-QCleanPath -Path "$env:LOCALAPPDATA\CrashDumps" -Label "User crash dumps"
    )
    return Resolve-QOTTaskResult -Name "Error logs" -Operations $ops
}

# ------------------------------
# Public: Setup / upgrade leftovers
# ------------------------------
function Invoke-QCleanSetupLeftovers {
    $taskName = "Archived Windows setup logs"
    $setupLogRoot = Join-Path $env:SystemRoot 'Panther'
    $ops = @(
        Invoke-QCleanPathFiles -Path $setupLogRoot -Filter '*.log.bak' -Label $taskName
        Invoke-QCleanPathFiles -Path $setupLogRoot -Filter '*.log.old' -Label $taskName
    )
    return Resolve-QOTTaskResult -Name $taskName -Operations $ops
}

# ------------------------------
# Public: Microsoft Store cache
# ------------------------------
function Invoke-QCleanStoreCache {
    Write-QLog "Cleaning: Microsoft Store cache"

    $resetCmd = Get-Command -Name "Reset-AppxPackage" -ErrorAction SilentlyContinue
    if (-not $resetCmd) {
        Write-QLog "Cleaning: Microsoft Store cache (skip, Reset-AppxPackage unavailable)"
        return New-QOTTaskResult -Name "Store cache" -Status "Skipped" -Reason "Not supported on this Windows build"
    }

    $storePackage = Get-AppxPackage -Name "Microsoft.WindowsStore" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $storePackage) {
        Write-QLog "Cleaning: Microsoft Store cache (skip, Microsoft Store package not found)"
        return New-QOTTaskResult -Name "Store cache" -Status "Skipped" -Reason "Microsoft Store not installed"
    }
    
    try {
        Reset-AppxPackage -Package $storePackage.PackageFullName -ErrorAction Stop
        Write-QLog "Cleaning: Microsoft Store cache (done)"
        return New-QOTTaskResult -Name "Store cache" -Status "Success"
    }
    catch {
        Write-QLog ("Cleaning: Microsoft Store cache failed: {0}" -f $_.Exception.Message) "ERROR"
        return New-QOTTaskResult -Name "Store cache" -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }
}

# ------------------------------
# Public: Edge cache cleanup (light)
# ------------------------------
function Invoke-QCleanEdgeCache {
    Write-QLog "Cleaning: Edge cache cleanup"
    $edgeBase = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    $ops = @(
        Invoke-QCleanPath -Path (Join-Path $edgeBase "Default\Cache") -Label "Edge Cache"
        Invoke-QCleanPath -Path (Join-Path $edgeBase "Default\Code Cache") -Label "Edge Code Cache"
        Invoke-QCleanPath -Path (Join-Path $edgeBase "Default\GPUCache") -Label "Edge GPU Cache"
    )
    return Resolve-QOTTaskResult -Name "Edge cache" -Operations $ops
}

# ------------------------------
# Public: Chrome/Chromium cache cleanup (light)
# ------------------------------
function Invoke-QCleanChromeCache {
    Write-QLog "Cleaning: Chrome/Chromium cache cleanup"
    $chromeBase = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    $ops = @(
        Invoke-QCleanPath -Path (Join-Path $chromeBase "Default\Cache") -Label "Chrome Cache"
        Invoke-QCleanPath -Path (Join-Path $chromeBase "Default\Code Cache") -Label "Chrome Code Cache"
        Invoke-QCleanPath -Path (Join-Path $chromeBase "Default\GPUCache") -Label "Chrome GPU Cache"
    )
    return Resolve-QOTTaskResult -Name "Chrome cache" -Operations $ops
}

function Invoke-QCleanDirectXShaderCache {
    $taskName = "Clear DirectX shader cache"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $result = Resolve-QOTTaskResult -Name $taskName -Operations @(
        Invoke-QOTClearFolderContents -Path "$env:LOCALAPPDATA\D3DSCache" -Label "DirectX shader cache"
    )
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QCleanWERQueue {
    $taskName = "Clear Windows Error Reporting queue"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $ops = @(
        Invoke-QOTClearFolderContents -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Label "WER ReportQueue"
        Invoke-QOTClearFolderContents -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -Label "WER ReportArchive"
    )
    $result = Resolve-QOTTaskResult -Name $taskName -Operations $ops
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QCleanClipboardHistory {
    $taskName = "Clear clipboard history"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $ops = @()
    try {
        if (Get-Command -Name "Set-Clipboard" -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value "" -ErrorAction Stop
            $ops += New-QOTOperationResult -Status "Success"
        } else {
            $ops += New-QOTOperationResult -Status "Skipped" -Reason "Set-Clipboard unavailable"
        }
    }
    catch {
        $ops += New-QOTOperationResult -Status "Skipped" -Reason "Clipboard unavailable" -Error $_.Exception.Message
    }

    $ops += Invoke-QOTClearFolderContents -Path "$env:LOCALAPPDATA\Microsoft\Clipboard" -Label "Clipboard history"

    $result = Resolve-QOTTaskResult -Name $taskName -Operations $ops
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QCleanExplorerRecentItems {
    $taskName = "Clear Explorer Recent items and Jump Lists"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $recentPath = "$env:APPDATA\Microsoft\Windows\Recent"
    $ops = @(
        Invoke-QOTClearFolderContents -Path $recentPath -Label "Explorer recent items"
        Invoke-QOTClearFolderContents -Path (Join-Path $recentPath "AutomaticDestinations") -Label "Jump Lists (automatic)"
        Invoke-QOTClearFolderContents -Path (Join-Path $recentPath "CustomDestinations") -Label "Jump Lists (custom)"
    )

    $result = Resolve-QOTTaskResult -Name $taskName -Operations $ops
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QCleanWindowsSearchHistory {
    $taskName = "Clear Windows Search history"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery"
    if (-not (Test-Path -LiteralPath $path)) {
        $result = New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Search history key not found"
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }

    try {
        $props = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        $propNames = @($props.PSObject.Properties | Where-Object { $_.Name -match '^\d+$|^MRUListEx$' } | ForEach-Object { $_.Name })
        if ($propNames.Count -eq 0) {
            $result = New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "No user search history entries found"
            Write-QOTTaskOutcome -TaskName $taskName -Result $result
            return $result
        }

        foreach ($name in $propNames) {
            Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop
        }

        $result = New-QOTTaskResult -Name $taskName -Status "Success"
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }
    catch {
        $reason = "Cleanup failed"
        if (Test-QOTAdminRequiredFailure -ErrorRecord $_) {
            $reason = "requires admin"
        }
        $result = New-QOTTaskResult -Name $taskName -Status "Failed" -Reason $reason -Error $_.Exception.Message
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }
}


function Invoke-QCleanPrefetchFiles {
    $taskName = "Clear Prefetch files"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $result = Resolve-QOTTaskResult -Name $taskName -Operations @(
        Invoke-QOTClearFolderContents -Path "$env:SystemRoot\Prefetch" -Label "Windows Prefetch files"
    )
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QRefreshWindowsIconCache {
    $taskName = "Refresh Windows icon cache"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    $ops = @()
    $explorerCachePath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    $ops += Invoke-QCleanPathFiles -Path $explorerCachePath -Filter "iconcache*.db" -Label "Explorer icon cache"
    $ops += Invoke-QCleanPathFiles -Path $explorerCachePath -Filter "thumbcache*.db" -Label "Explorer thumbnail cache"

    $legacyIconCacheFile = Join-Path $env:LOCALAPPDATA "IconCache.db"
    if (-not (Test-Path -LiteralPath $legacyIconCacheFile)) {
        $ops += New-QOTOperationResult -Status "Skipped" -Reason "IconCache.db not found"
    }
    else {
        try {
            Remove-Item -LiteralPath $legacyIconCacheFile -Force -ErrorAction Stop
            $ops += New-QOTOperationResult -Status "Success"
        }
        catch {
            if (Test-QOTAdminRequiredFailure -ErrorRecord $_) {
                $ops += New-QOTOperationResult -Status "Skipped" -Reason "Admin required" -Error $_.Exception.Message
            }
            else {
                $ops += New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
            }
        }
    }

    $result = Resolve-QOTTaskResult -Name $taskName -Operations $ops
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    if ($result.Status -eq "Success") {
        Write-QLog "Icon cache refreshed. Restart Windows Explorer if icons do not update immediately."
    }
    return $result
}

function Invoke-QClearWindowsEventLogs {
    $taskName = "Clear Windows Event Logs"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    if (-not (Test-QOTIsAdmin)) {
        $result = New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Admin required"
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }

    $wevtutil = Get-Command -Name "wevtutil.exe" -ErrorAction SilentlyContinue
    if (-not $wevtutil) {
        $result = New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "wevtutil unavailable"
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }

    try {
        $logs = @(& $wevtutil.Path el 2>$null)
    }
    catch {
        $result = New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Event log enumeration failed" -Error $_.Exception.Message
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }

    if ($logs.Count -eq 0) {
        $result = New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "No event logs found"
        Write-QOTTaskOutcome -TaskName $taskName -Result $result
        return $result
    }

    $cleared = 0
    $failed = 0
    foreach ($logName in $logs) {
        if ([string]::IsNullOrWhiteSpace([string]$logName)) { continue }
        try {
            & $wevtutil.Path cl "$logName" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $cleared++
            }
            else {
                $failed++
            }
        }
        catch {
            $failed++
        }
    }

    if ($cleared -gt 0) {
        $result = New-QOTTaskResult -Name $taskName -Status "Success"
    }
    elseif ($failed -gt 0) {
        $result = New-QOTTaskResult -Name $taskName -Status "Failed" -Reason "Event log cleanup failed"
    }
    else {
        $result = New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Nothing to clear"
    }

    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}

function Invoke-QCleanTeamsCache {
    $taskName = "Clear Microsoft Teams cache"
    Write-QLog ("Now doing task: {0}" -f $taskName)

    if (Get-Process -Name 'Teams','ms-teams' -ErrorAction SilentlyContinue) {
        return New-QOTTaskResult -Name $taskName -Status "Skipped" -Reason "Quit Teams before clearing its cache"
    }
    $cachePaths = @(
        (Join-Path $env:APPDATA 'Microsoft\Teams')
        (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams')
    )

    $ops = @()
    foreach ($cachePath in $cachePaths) {
        if ([string]::IsNullOrWhiteSpace($cachePath)) { continue }
        $ops += Invoke-QCleanPath -Path $cachePath -Label ("Teams cache ({0})" -f $cachePath)
    }

    $result = Resolve-QOTTaskResult -Name $taskName -Operations $ops
    Write-QOTTaskOutcome -TaskName $taskName -Result $result
    return $result
}
# ------------------------------
# Export functions
# ------------------------------
Export-ModuleMember -Function `
    Invoke-QCleanWindowsUpdateCache, `
    Invoke-QCleanDOCache, `
    Invoke-QCleanTemp, `
    Invoke-QCleanRecycleBin, `
    Invoke-QCleanThumbnailCache, `
    Invoke-QCleanErrorLogs, `
    Invoke-QCleanSetupLeftovers, `
    Invoke-QCleanStoreCache, `
    Invoke-QCleanEdgeCache, `
    Invoke-QCleanChromeCache, `
    Invoke-QCleanDirectXShaderCache, `
    Invoke-QCleanWERQueue, `
    Invoke-QCleanClipboardHistory, `
    Invoke-QCleanExplorerRecentItems, `
    Invoke-QCleanWindowsSearchHistory, `
    Invoke-QCleanPrefetchFiles, `
    Invoke-QRefreshWindowsIconCache, `
    Invoke-QClearWindowsEventLogs, `
    Invoke-QCleanTeamsCache

