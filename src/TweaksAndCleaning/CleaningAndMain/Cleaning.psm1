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

    if (-not (Test-Path -LiteralPath $Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }

    try {
        $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
    }
    catch {
        if (Test-QOTAdminRequiredFailure -ErrorRecord $_) {
            return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
        }
        return New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }

    if ($items.Count -eq 0) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Already clear"
    }

    foreach ($item in $items) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
        }
        catch {
            if (Test-QOTAdminRequiredFailure -ErrorRecord $_) {
                return New-QOTOperationResult -Status "Skipped" -Reason "Admin required"
            }
            return New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
        }
    }

    Write-QLog ("Cleaning: {0} (done)" -f $Label)
    return New-QOTOperationResult -Status "Success"
}

function Invoke-QCleanPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Label
    )

    if ($Label -and $Label -isnot [string]) {
        $Label = [string]$Label
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Invalid path in task definition"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Label) {
            Write-QLog ("Cleaning: {0} (skip, not found)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Path not found: {0}" -f $Path)
        }
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }

    try {
        $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        $removedAny = $false
        foreach ($item in $items) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                $removedAny = $true
            } catch { }
        }
        if ($Label) {
            Write-QLog ("Cleaning: {0} (done)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Cleared {0}" -f $Path)
        }
        if ($removedAny) {
            return New-QOTOperationResult -Status "Success"
        }
        return New-QOTOperationResult -Status "Skipped" -Reason "Already done"
    }
    catch {
        if ($Label) {
            Write-QLog ("Cleaning: {0} failed: {1}" -f $Label, $_.Exception.Message) "ERROR"
        } else {
            Write-QLog ("Cleaning: {0} failed: {1}" -f $Path, $_.Exception.Message) "ERROR"
        }
        return New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }
}

function Invoke-QCleanPathFiles {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Filter,
        [string]$Label
    )

    if ($Label -and $Label -isnot [string]) {
        $Label = [string]$Label
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-QOTOperationResult -Status "Skipped" -Reason "Invalid path in task definition"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Label) {
            Write-QLog ("Cleaning: {0} (skip, not found)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Path not found: {0}" -f $Path)
        }
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }

    try {
        $items = Get-ChildItem -LiteralPath $Path -Filter $Filter -Force -ErrorAction SilentlyContinue
        $removedAny = $false
        foreach ($item in $items) {
            try {
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                $removedAny = $true
            } catch { }
        }
        if ($Label) {
            Write-QLog ("Cleaning: {0} (done)" -f $Label)
        } else {
            Write-QLog ("Cleaning: Cleared {0}\\{1}" -f $Path, $Filter)
        }
        if ($removedAny) {
            return New-QOTOperationResult -Status "Success"
        }
        return New-QOTOperationResult -Status "Skipped" -Reason "Not found"
    }
    catch {
        if ($Label) {
            Write-QLog ("Cleaning: {0} failed: {1}" -f $Label, $_.Exception.Message) "ERROR"
        } else {
            Write-QLog ("Cleaning: {0}\\{1} failed: {2}" -f $Path, $Filter, $_.Exception.Message) "ERROR"
        }
        return New-QOTOperationResult -Status "Failed" -Reason "Cleanup failed" -Error $_.Exception.Message
    }
}


# ------------------------------
# Public: Clean Windows Update cache
# (placeholder for now, real logic added later)
# ------------------------------
function Invoke-QCleanWindowsUpdateCache {
    Write-QLog "Cleaning: Windows Update cache"
    $serviceName = "wuauserv"
    try { Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue } catch { }
    $op = Invoke-QCleanPath -Path "$env:SystemRoot\SoftwareDistribution\Download" -Label "Windows Update cache"
    try { Start-Service -Name $serviceName -ErrorAction SilentlyContinue } catch { }
    return Resolve-QOTTaskResult -Name "Windows Update cache" -Operations @($op)
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

    $ops = @(
        Invoke-QCleanPath -Path $env:TEMP -Label "Current user temp files"
        Invoke-QCleanPath -Path $env:TMP -Label "Current user tmp files"
        Invoke-QCleanPath -Path "$env:SystemRoot\Temp" -Label "Windows temp files"
    )

    $usersRoot = Join-Path $env:SystemDrive "Users"
    if (Test-Path -LiteralPath $usersRoot -ErrorAction SilentlyContinue) {
        try {
            $profileDirs = @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue)
            foreach ($profileDir in $profileDirs) {
                if (-not $profileDir) { continue }
                $profileTemp = Join-Path $profileDir.FullName "AppData\Local\Temp"
                if (-not (Test-Path -LiteralPath $profileTemp -ErrorAction SilentlyContinue)) { continue }
                $ops += Invoke-QCleanPath -Path $profileTemp -Label ("User temp files ({0})" -f $profileDir.Name)
            }
        }
        catch {
            $ops += New-QOTOperationResult -Status "Skipped" -Reason "User profile temp scan unavailable"
        }
    }

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
    Write-QLog "Cleaning: Setup/upgrade leftovers"
    $ops = @(
        Invoke-QCleanPath -Path "$env:SystemDrive\Windows.old" -Label "Windows.old"
        Invoke-QCleanPath -Path "$env:SystemDrive\`$WINDOWS.~BT" -Label "Setup cache (`$WINDOWS.~BT)"
        Invoke-QCleanPath -Path "$env:SystemDrive\`$WINDOWS.~WS" -Label "Setup cache (`$WINDOWS.~WS)"
        Invoke-QCleanPath -Path "$env:SystemDrive\ESD" -Label "Windows ESD"
        Invoke-QCleanPath -Path "$env:SystemRoot\Panther" -Label "Setup log files"
    )
    return Resolve-QOTTaskResult -Name "Setup leftovers" -Operations $ops
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

    $cachePaths = @(
        "$env:APPDATA\Microsoft\Teams",
        "$env:LOCALAPPDATA\Microsoft\Teams",
        "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache",
        "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\AC\INetCache",
        "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\TempState"
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

