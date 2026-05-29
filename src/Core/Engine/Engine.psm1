# Engine.psm1
# Coordinates major operations by calling the feature modules
# Splash is NOT handled here. Intro.ps1 owns creating the splash.
# MainWindow.UI.psm1 handles "Ready", wait 2s, fade, close when SplashWindow is passed.

$ErrorActionPreference = "Stop"

# Use the diagnostic helper for optional imports so failures get logged
# instead of silently swallowed. The helper is dot-sourced (not imported)
# so it works before any module is loaded.
. (Join-Path $PSScriptRoot "..\QOTImportHelper.ps1")

$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\Config\Config.psm1")   -ImporterContext 'Engine' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\Logging\Logging.psm1") -ImporterContext 'Engine' -Force

# Import feature modules (best effort - failures are now logged, not silenced)
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\TweaksAndCleaning\CleaningAndMain\Cleaning.psm1")           -ImporterContext 'Engine' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\TweaksAndCleaning\TweaksAndPrivacy\TweaksAndPrivacy.psm1") -ImporterContext 'Engine' -Force

# Apps
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Apps\InstalledApps.psm1")     -ImporterContext 'Engine' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Apps\InstallCommonApps.psm1") -ImporterContext 'Engine' -Force

# Advanced
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Advanced\AdvancedCleaning\AdvancedCleaning.psm1")     -ImporterContext 'Engine' -Force
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "..\..\Advanced\NetworkAndServices\NetworkAndServices.psm1") -ImporterContext 'Engine' -Force

function Set-QOTStatus {
    param([string]$Text)

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog "STATUS: $Text"
        }
    } catch { }

    if (Get-Command Set-QOTSummary -ErrorAction SilentlyContinue) {
        Set-QOTSummary -Text $Text
    }
}

function Set-QOTProgress {
    param([int]$Percent)

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog "Progress: $Percent%"
        }
    } catch { }
}

function Invoke-QOTRun {
    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog "Starting full run"
        }
    } catch { }

    Set-QOTStatus "Running..."
    Set-QOTProgress 0

    try {
        if (Get-Command Start-QOTCleaning -ErrorAction SilentlyContinue) { Start-QOTCleaning }
        Set-QOTProgress 33

        if (Get-Command Start-QOTTweaks -ErrorAction SilentlyContinue) { Start-QOTTweaks }
        Set-QOTProgress 66

        try {
            if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                Write-QLog "Run completed"
            }
        } catch { }

        Set-QOTProgress 100
        Set-QOTStatus "Completed"
    }
    catch {
        try {
            if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                Write-QLog "Error during run: $($_.Exception.Message)" "ERROR"
            }
        } catch { }

        Set-QOTStatus "Error occurred"
    }
}

function Invoke-QOTAdvancedRun {
    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog "Starting Advanced run"
        }
    } catch { }

    Set-QOTStatus "Running Advanced Tasks..."

    try {
        if (Get-Command Start-QOTAdvancedCleaning -ErrorAction SilentlyContinue) { Start-QOTAdvancedCleaning }
        if (Get-Command Start-QOTNetworkFix -ErrorAction SilentlyContinue) { Start-QOTNetworkFix }

        try {
            if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                Write-QLog "Advanced run completed"
            }
        } catch { }

        Set-QOTStatus "Advanced Completed"
    }
    catch {
        try {
            if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                Write-QLog "Error in advanced run: $($_.Exception.Message)" "ERROR"
            }
        } catch { }

        Set-QOTStatus "Advanced Error"
    }
}

function Invoke-QOTStartupWarmup {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog "Startup warmup: begin"
        }
    } catch { }

    try { if (Get-Command Test-QOTWingetAvailable -ErrorAction SilentlyContinue) { $null = Test-QOTWingetAvailable } } catch { }
    try { if (Get-Command Get-QOTCommonAppsCatalogue -ErrorAction SilentlyContinue) { $null = Get-QOTCommonAppsCatalogue } } catch { }

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog "Startup warmup: end"
        }
    } catch { }
}

function Start-QOTMain {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory = $false)]
        [System.Windows.Window]$SplashWindow,

        [switch]$WarmupOnly,
        [switch]$PassThru
    )

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog "Start-QOTMain called. Root = $RootPath"
        }
    } catch { }

    try {
        # Ensure Settings UI logging + view builder are available globally before UI loads
        $settingsUIModule = Join-Path $PSScriptRoot "..\Settings\Settings.UI.psm1"
        $settingsUIModule = [System.IO.Path]::GetFullPath($settingsUIModule)

        if (Test-Path -LiteralPath $settingsUIModule) {
            Import-Module $settingsUIModule -Force -Global -ErrorAction Stop
            if (Get-Command Write-QOSettingsUILog -ErrorAction SilentlyContinue) {
                Write-QOSettingsUILog "Engine confirmed Settings UI logger is available"
            }
        } else {
            try {
                if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                    Write-QLog "Settings UI module missing: $settingsUIModule" "WARN"
                }
            } catch { }
        }

        $uiModule = Join-Path $PSScriptRoot "..\..\UI\MainWindow.UI.psm1"
        $uiModule = [System.IO.Path]::GetFullPath($uiModule)

        if (-not (Test-Path -LiteralPath $uiModule)) {
            throw "UI module file missing: $uiModule"
        }

        $mainWindowModule = Import-Module $uiModule -Force -PassThru -ErrorAction Stop
        if (-not $mainWindowModule) {
            throw "UI module import failed: $uiModule"
        }
        # Invoke in module scope to avoid conflicting Start-QOTMainWindow definitions in-session.
        if ($WarmupOnly) {
            return & $mainWindowModule {
                param($SplashWindow, $PassThru)
                $cmd = Get-Command -Name 'Start-QOTMainWindow' -ErrorAction Stop
                $invokeArgs = @{ SplashWindow = $SplashWindow; WarmupOnly = $true }
                if ($PassThru) { $invokeArgs["PassThru"] = $true }
                if ($cmd.Parameters.ContainsKey('Issues')) {
                    $requiresNonEmptyIssues = $false
                    try {
                        foreach ($attr in @($cmd.Parameters['Issues'].Attributes)) {
                            if ($attr -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute]) {
                                $requiresNonEmptyIssues = $true
                                break
                            }
                        }
                    } catch { }
                    $invokeArgs["Issues"] = if ($requiresNonEmptyIssues) { @("Startup warmup launch") } else { @() }
                }
                try {
                    Start-QOTMainWindow @invokeArgs
                }
                catch [System.Management.Automation.ParameterBindingException] {
                    $bindingMessage = $_.Exception.Message
                    $issuesBindingProblem = ($bindingMessage -match "parameter name 'Issues'") -or (($bindingMessage -match "parameter 'Issues'") -and ($bindingMessage -match "empty collection"))
                    if ($issuesBindingProblem) {
                        $invokeArgs["Issues"] = @("Startup warmup launch")
                        Start-QOTMainWindow @invokeArgs
                    }
                    else { throw }
                }
            } $SplashWindow $PassThru
        }

        & $mainWindowModule {
            param($SplashWindow)
            $cmd = Get-Command -Name 'Start-QOTMainWindow' -ErrorAction Stop
            $invokeArgs = @{ SplashWindow = $SplashWindow }
            if ($cmd.Parameters.ContainsKey('Issues')) {
                $requiresNonEmptyIssues = $false
                try {
                    foreach ($attr in @($cmd.Parameters['Issues'].Attributes)) {
                        if ($attr -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute]) {
                            $requiresNonEmptyIssues = $true
                            break
                        }
                    }
                } catch { }
                $invokeArgs["Issues"] = if ($requiresNonEmptyIssues) { @("Startup launch") } else { @() }
            }
            try {
                Start-QOTMainWindow @invokeArgs
            }
            catch [System.Management.Automation.ParameterBindingException] {
                $bindingMessage = $_.Exception.Message
                $issuesBindingProblem = ($bindingMessage -match "parameter name 'Issues'") -or (($bindingMessage -match "parameter 'Issues'") -and ($bindingMessage -match "empty collection"))
                if ($issuesBindingProblem) {
                    $invokeArgs["Issues"] = @("Startup launch")
                    Start-QOTMainWindow @invokeArgs
                }
                else { throw }
            }
        } $SplashWindow
        
    }
        
    catch {
        $exception = $_.Exception
        $detailLines = New-Object System.Collections.Generic.List[string]
        $depth = 0
        while ($exception) {
            $detailLines.Add(("Exception[{0}] Type: {1}" -f $depth, $exception.GetType().FullName))
            $detailLines.Add(("Exception[{0}] Message: {1}" -f $depth, $exception.Message))
            if (-not [string]::IsNullOrWhiteSpace($exception.StackTrace)) {
                $detailLines.Add(("Exception[{0}] StackTrace:`n{1}" -f $depth, $exception.StackTrace))
            }
            $exception = $exception.InnerException
            $depth++
        }

        $details = $detailLines -join [Environment]::NewLine
        try {
            if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                Write-QLog ("Start-QOTMain failed.`n{0}" -f $details) "ERROR"
            }
        } catch { }

        try {
            if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                Write-QLog "Start-QOTMain failed. Full error details captured in log." "ERROR"
            }
        } catch { }

        throw
    }
}

Export-ModuleMember -Function `
    Start-QOTMain, `
    Invoke-QOTRun, `
    Invoke-QOTAdvancedRun, `
    Invoke-QOTStartupWarmup, `
    Set-QOTStatus, `
    Set-QOTProgress
