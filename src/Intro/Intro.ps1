# Intro.ps1
# Startup widget for the Quinn Optimiser Toolkit
# Intro coordinates startup widget display and main window warmup sequencing.

param(
    [switch]$SkipSplash,
    [string]$LogPath,
    [switch]$Quiet,
    [switch]$EnableStartupWarmup
)

$ErrorActionPreference = "Stop"

# Console window hide/show functions
function Hide-ConsoleWindow {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ConsoleHelper {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction SilentlyContinue | Out-Null

        $consolePtr = [ConsoleHelper]::GetConsoleWindow()
        if ($consolePtr -ne [IntPtr]::Zero) {
            [ConsoleHelper]::ShowWindow($consolePtr, 0) | Out-Null  # 0 = SW_HIDE
        }
    }
    catch { }
}

function Show-ConsoleWindow {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ConsoleHelper {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction SilentlyContinue | Out-Null

        $consolePtr = [ConsoleHelper]::GetConsoleWindow()
        if ($consolePtr -ne [IntPtr]::Zero) {
            [ConsoleHelper]::ShowWindow($consolePtr, 5) | Out-Null  # 5 = SW_SHOW
        }
    }
    catch { }
}

# Keep startup noise out of interactive PowerShell; logs are written to file.
[Environment]::SetEnvironmentVariable('QOT_QUIET_CONSOLE', '1', 'Process')
[Environment]::SetEnvironmentVariable('QOT_APP_USER_MODEL_ID', 'StudioVoly.QuinnOptimiserToolkit', 'Process')

if (-not $LogPath) {
    $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $LogPath = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

$script:QOTLogPath = $LogPath

# This logger is a scriptblock, so it works reliably even when called from other scopes.
$script:QOTLog = {
    param([string]$Message, [string]$Level = "INFO")

    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"

    try { $line | Add-Content -Path $script:QOTLogPath -Encoding UTF8 } catch { }
}

$script:StartupClock = [System.Diagnostics.Stopwatch]::StartNew()
$script:StartupLast  = [TimeSpan]::Zero
$script:StartupTimers = @{}

function Write-StartupMark {
    param([string]$Label)
    $now   = $script:StartupClock.Elapsed
    $delta = $now - $script:StartupLast
    $script:StartupLast = $now
    & $script:QOTLog ("[STARTUP] {0} at {1:hh\:mm\:ss\.fff} (+{2} ms)" -f $Label, $now, [math]::Round($delta.TotalMilliseconds)) "INFO"
}

function Start-StartupChunk {
    param([string]$Name)
    $script:StartupTimers[$Name] = [System.Diagnostics.Stopwatch]::StartNew()
    & $script:QOTLog ("[STARTUP] {0} started" -f $Name) "INFO"
}

function Stop-StartupChunk {
    param(
        [string]$Name,
        [int]$WarnThresholdMs = 200
    )
    if (-not $script:StartupTimers.ContainsKey($Name)) { return }
    $sw = $script:StartupTimers[$Name]
    $sw.Stop()
    $durationMs = [math]::Round($sw.Elapsed.TotalMilliseconds)
    $level = if ($durationMs -ge $WarnThresholdMs) { "WARN" } else { "INFO" }
    & $script:QOTLog ("[STARTUP] {0} finished in {1} ms" -f $Name, $durationMs) $level
}

function Set-QOTProcessTaskbarIdentity {
    param(
        [Parameter(Mandatory = $false)]
        [string]$AppUserModelId = "StudioVoly.QuinnOptimiserToolkit"
    )

    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class QOTShellAppIdIntro {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
}
"@ -ErrorAction SilentlyContinue | Out-Null

        [void][QOTShellAppIdIntro]::SetCurrentProcessExplicitAppUserModelID($AppUserModelId)
        & $script:QOTLog ("[STARTUP] Intro set process AppUserModelID to '{0}'." -f $AppUserModelId) "INFO"
    }
    catch {
        & $script:QOTLog ("[STARTUP] Intro failed to set AppUserModelID: {0}" -f $_.Exception.Message) "WARN"
    }
}

$oldWarningPreference = $WarningPreference
$WarningPreference    = "SilentlyContinue"

# Hide the console window for clean user experience
Hide-ConsoleWindow

try {
    Set-QOTProcessTaskbarIdentity
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # Ensure a WPF Application exists before showing the widget.
    # This prevents the process from shutting down when the widget closes
    # in environments where WPF defaults to closing on last-window-close.
    $introApp = [System.Windows.Application]::Current
    if (-not $introApp) {
        $introApp = [System.Windows.Application]::new()
        & $script:QOTLog "[STARTUP] Intro created WPF Application instance before widget." "INFO"
    }
    if ($introApp.ShutdownMode -ne [System.Windows.ShutdownMode]::OnExplicitShutdown) {
        $introApp.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
        & $script:QOTLog ("[STARTUP] Intro forced Application.ShutdownMode to {0} before widget display." -f $introApp.ShutdownMode) "INFO"
    }

    $rootPath      = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
    $loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
    $engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

    # Load Startup Widget UI module
    $widgetUIModule = Join-Path $rootPath "src\Intro\StartupWidget\StartupWidget.UI.psm1"
    & $script:QOTLog ("[STARTUP] Widget module path: {0}" -f $widgetUIModule) "DEBUG"
    & $script:QOTLog ("[STARTUP] Widget module exists: {0}" -f (Test-Path $widgetUIModule)) "DEBUG"

    if (Test-Path $widgetUIModule) {
        try {
            Import-Module $widgetUIModule -Force -ErrorAction Stop
            & $script:QOTLog "[STARTUP] Widget module imported successfully" "DEBUG"
        }
        catch {
            & $script:QOTLog ("[STARTUP] Failed to import startup widget UI module: {0}" -f $_.Exception.Message) "WARN"
        }
    }

    # Create and show startup widget (replaces splash screen)
    $widget = $null
    $widgetApp = $null

    $widgetXaml = Join-Path $rootPath "src\Intro\StartupWidget\StartupWidget.xaml"
    if (Test-Path $widgetXaml) {
        try {
            # Application was already created at the top of this script with proper ShutdownMode
            # Just create and show the widget
            $widget = New-QOTStartupWidget -Path $widgetXaml
            if ($widget) {
                Show-QOTStartupWidget -Window $widget
                Write-StartupMark "Intro shown (startup widget displayed)"
                & $script:QOTLog "[STARTUP] Startup widget displayed." "INFO"
            }
        }
        catch {
            & $script:QOTLog ("[STARTUP] Failed to show startup widget: {0}" -f $_.Exception.Message) "ERROR"
            throw
        }
    }
    else {
        & $script:QOTLog "[STARTUP] Startup widget XAML not found at: $widgetXaml" "ERROR"
        throw "Startup widget XAML not found"
    }

    & $script:QOTLog "[STARTUP] Intro started" "INFO"
    Write-StartupMark "Start heavy init phase 1 (module imports)"
    if (-not $widget) {
        Write-StartupMark "Intro shown (no UI)"
    }

    function Update-StartupWidget {
        param([int]$Percent, [string]$Text)

        if (-not $widget) { return }

        if (Get-Command Update-QOTWidgetProgress -ErrorAction SilentlyContinue) {
            try {
                Update-QOTWidgetProgress -Window $widget -Value $Percent -ErrorAction Stop
            }
            catch {
                # Widget progress update failed, continue
            }
        }
    }

    Update-StartupWidget 3  "Starting Quinn Optimiser Toolkit..."
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
    Start-Sleep -Milliseconds 150

    Update-StartupWidget 8 "Loading config..."
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
    Start-StartupChunk "Load config module"
    if (Test-Path $configModule) { Import-Module $configModule -Force -ErrorAction Stop }
    Stop-StartupChunk "Load config module"

    Update-StartupWidget 15 "Loading logging..."
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
    Start-StartupChunk "Load logging module"
    if (Test-Path $loggingModule) { Import-Module $loggingModule -Force -ErrorAction Stop }
    Stop-StartupChunk "Load logging module"

    Update-StartupWidget 25 "Loading engine..."
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
    Start-StartupChunk "Load engine module"
    if (-not (Test-Path $engineModule)) { throw "Engine module not found at $engineModule" }
    Import-Module $engineModule -Force -ErrorAction Stop
    Stop-StartupChunk "Load engine module"
    Write-StartupMark "Finish module imports"

    Update-StartupWidget 35 "Scanning installed apps..."
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
    Start-StartupChunk "Prefetch installed apps cache"
    try {
        $appsModule = Join-Path $rootPath "src\Apps\InstalledApps.psm1"
        if (Test-Path $appsModule) {
            Import-Module $appsModule -Force -ErrorAction Stop
            if (Get-Command Get-QOTInstalledAppsCached -ErrorAction SilentlyContinue) {
                $Global:QOT_InstalledAppsCache = @(Get-QOTInstalledAppsCached -ForceRefresh)
                $Global:QOT_InstalledAppsCacheTimestamp = Get-Date
                & $script:QOTLog ("[STARTUP] Prefetched installed apps: {0}" -f @($Global:QOT_InstalledAppsCache).Count) "INFO"
            }
        }
    }
    catch {
        & $script:QOTLog ("[STARTUP] Installed app prefetch failed (continuing): {0}" -f $_.Exception.Message) "WARN"
    }
    Stop-StartupChunk "Prefetch installed apps cache"

    Update-StartupWidget 45 "Preparing ticket sync..."
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
    Start-StartupChunk "Prepare ticket sync"
    try {
        $ticketsCoreModule = Join-Path $rootPath "src\Core\Tickets.psm1"
        if (-not (Test-Path -LiteralPath $ticketsCoreModule)) {
            & $script:QOTLog ("[STARTUP] Ticket sync skipped: core module missing at {0}" -f $ticketsCoreModule) "WARN"
        }
        else {
            Import-Module $ticketsCoreModule -Force -ErrorAction Stop
            $syncCmd = Get-Command Sync-QOTicketsFromEmail -ErrorAction SilentlyContinue
            $getMonitoredCmd = Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction SilentlyContinue

            if (-not $syncCmd) {
                & $script:QOTLog "[STARTUP] Ticket sync skipped: Sync-QOTicketsFromEmail not available." "WARN"
            }
            else {
                $monitoredMailboxes = @()
                if ($getMonitoredCmd) {
                    try { $monitoredMailboxes = @(& $getMonitoredCmd) } catch { $monitoredMailboxes = @() }
                }

                if (@($monitoredMailboxes).Count -le 0) {
                    & $script:QOTLog "[STARTUP] Ticket sync skipped: no monitored mailbox addresses configured." "INFO"
                }
                else {
                    Update-StartupWidget 55 "Syncing tickets from Outlook..."
                    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }

                    $introSyncRunspace = $null
                    $introSyncPs = $null
                    $introSyncAsync = $null
                    $introSyncTimedOut = $false
                    $introSyncTimeoutMs = 30000
                    $introSyncStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    # Max time to wait for Stop() to actually finish before forcefully disposing
                    $introSyncStopGraceMs = 10000

                    try {
                        $introSyncRunspace = [runspacefactory]::CreateRunspace()
                        $introSyncRunspace.ApartmentState = "STA"
                        $introSyncRunspace.ThreadOptions = "ReuseThread"
                        $introSyncRunspace.Open()

                        $introSyncPs = [powershell]::Create()
                        $introSyncPs.Runspace = $introSyncRunspace
                        $null = $introSyncPs.AddScript({
                            param([string]$TicketsModulePath, [int]$MaxPerMailbox)

                            $ErrorActionPreference = "Stop"
                            Import-Module $TicketsModulePath -Force -ErrorAction Stop

                            $sync = Get-Command Sync-QOTicketsFromEmail -ErrorAction SilentlyContinue
                            if (-not $sync) {
                                return [pscustomobject]@{
                                    Success = $false
                                    Added   = 0
                                    Note    = "Sync command unavailable."
                                }
                            }

                            # Do not cold-launch Outlook during the intro phase.
                            # On fresh machines this can steal focus with first-run/setup dialogs
                            # before users clearly see Quinn's startup UI.
                            return (& $sync -MaxPerMailbox $MaxPerMailbox)
                        }).AddArgument($ticketsCoreModule).AddArgument(25)

                        $introSyncAsync = $introSyncPs.BeginInvoke()

                        while ($introSyncAsync -and (-not $introSyncAsync.IsCompleted)) {
                            if ($introSyncStopwatch.ElapsedMilliseconds -ge $introSyncTimeoutMs) {
                                $introSyncTimedOut = $true
                                break
                            }
                            if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
                            Start-Sleep -Milliseconds 120
                        }

                        if ($introSyncTimedOut) {
                            try { $introSyncPs.Stop() } catch { & $script:QOTLog ("[STARTUP] Ticket sync intro phase Stop() threw: {0}" -f $_.Exception.Message) "WARN" }
                            & $script:QOTLog ("[STARTUP] Ticket sync intro phase timed out after {0} ms; continuing startup." -f $introSyncTimeoutMs) "WARN"

                            # Wait up to $introSyncStopGraceMs for Stop() to actually take effect.
                            # If the runspace refuses to stop, we still force-dispose below in the
                            # finally block to prevent a hung background process.
                            $stopWait = [System.Diagnostics.Stopwatch]::StartNew()
                            while ($introSyncAsync -and (-not $introSyncAsync.IsCompleted) -and ($stopWait.ElapsedMilliseconds -lt $introSyncStopGraceMs)) {
                                Start-Sleep -Milliseconds 100
                            }
                            $stopWait.Stop()
                            if ($introSyncAsync -and (-not $introSyncAsync.IsCompleted)) {
                                & $script:QOTLog ("[STARTUP] Ticket sync runspace did not stop within {0} ms grace period; will force-dispose." -f $introSyncStopGraceMs) "WARN"
                            }
                        }
                        else {
                            $introSyncResult = $null
                            try {
                                $introSyncOutput = @($introSyncPs.EndInvoke($introSyncAsync))
                                if ($introSyncOutput.Count -gt 0) { $introSyncResult = $introSyncOutput[-1] }
                            }
                            catch {
                                & $script:QOTLog ("[STARTUP] Ticket sync intro phase failed while collecting results: {0}" -f $_.Exception.Message) "WARN"
                            }

                            if ($introSyncResult) {
                                $syncSuccess = $true
                                $syncAdded = 0
                                $syncNote = ""
                                try { if ($introSyncResult.PSObject.Properties.Name -contains "Success") { $syncSuccess = [bool]$introSyncResult.Success } } catch { }
                                try { if ($introSyncResult.PSObject.Properties.Name -contains "Added") { $syncAdded = [int]$introSyncResult.Added } } catch { }
                                try { if ($introSyncResult.PSObject.Properties.Name -contains "Note") { $syncNote = [string]$introSyncResult.Note } } catch { }

                                $syncLogLevel = if ($syncSuccess) { "INFO" } else { "WARN" }
                                & $script:QOTLog ("[STARTUP] Ticket sync intro phase completed. Success={0} Added={1} Note={2}" -f $syncSuccess, $syncAdded, $syncNote) $syncLogLevel
                            }
                            else {
                                & $script:QOTLog "[STARTUP] Ticket sync intro phase returned no result." "WARN"
                            }
                        }
                    }
                    finally {
                        $introSyncStopwatch.Stop()
                        # Force-stop + dispose, even if the work is still running. Stop() is safe
                        # to call multiple times. Each Dispose() is wrapped individually so one
                        # failure can't block the next cleanup step.
                        if ($introSyncPs) {
                            try { $introSyncPs.Stop() } catch { }
                            try { $introSyncPs.Dispose() } catch { & $script:QOTLog ("[STARTUP] Intro sync PowerShell Dispose() failed: {0}" -f $_.Exception.Message) "WARN" }
                            $introSyncPs = $null
                        }
                        if ($introSyncRunspace) {
                            try {
                                if ($introSyncRunspace.RunspaceStateInfo -and $introSyncRunspace.RunspaceStateInfo.State -ne 'Closed') {
                                    $introSyncRunspace.Close()
                                }
                            } catch { }
                            try { $introSyncRunspace.Dispose() } catch { & $script:QOTLog ("[STARTUP] Intro sync Runspace Dispose() failed: {0}" -f $_.Exception.Message) "WARN" }
                            $introSyncRunspace = $null
                        }
                        $introSyncAsync = $null
                    }
                }
            }
        }
    }
    catch {
        & $script:QOTLog ("[STARTUP] Ticket sync intro phase failed (continuing): {0}" -f $_.Exception.Message) "WARN"
    }
    Stop-StartupChunk "Prepare ticket sync"

    $warmupEnabled = $EnableStartupWarmup.IsPresent
    if (-not $warmupEnabled) {
        & $script:QOTLog "[STARTUP] Startup warmup skipped (default launch mode opens MainWindow only)." "INFO"
    }

    if ($warmupEnabled) {
        Update-StartupWidget 65 "Preparing startup tasks..."
        if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
        Start-StartupChunk "Startup runspace preparation"

        $startupState = [hashtable]::Synchronized(@{
            Percent   = 70
            Status    = "Preparing startup tasks..."
            Completed = $false
            Error     = $null
        })

        $startupRunspace = $null
        $startupPs = $null
        $startupAsync = $null
        $startupTimer = $null
        $startupFrame = $null

        try {
            $startupRunspace = [runspacefactory]::CreateRunspace()
            $startupRunspace.ApartmentState = "STA"
            $startupRunspace.ThreadOptions  = "ReuseThread"
            $startupRunspace.Open()

            $startupPs = [powershell]::Create()
            $startupPs.Runspace = $startupRunspace
        $null = $startupPs.AddScript({
        param(
            [string]$RootPath,
            [hashtable]$State,
            [string]$LogPath
        )

        $ErrorActionPreference = "Stop"

        function Set-IntroState {
            param([int]$Percent, [string]$Text)
            $State.Percent = $Percent
            $State.Status  = $Text
        }

        function Write-IntroLog {
            param([string]$Message, [string]$Level = "INFO")
            $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            $line = "[$ts] [$Level] $Message"
            try { $line | Add-Content -Path $LogPath -Encoding UTF8 } catch { }
        }

        function Invoke-IntroChunk {
            param(
                [string]$Name,
                [scriptblock]$Action,
                [int]$WarnThresholdMs = 200
            )

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Write-IntroLog "[STARTUP] $Name started"
            & $Action
            $sw.Stop()
            $durationMs = [math]::Round($sw.Elapsed.TotalMilliseconds)
            $level = if ($durationMs -ge $WarnThresholdMs) { "WARN" } else { "INFO" }
            Write-IntroLog ("[STARTUP] {0} finished in {1} ms [{2}]" -f $Name, $durationMs, $level) $level
        }

        try {
            Set-IntroState 72 "Loading settings..."
            Write-IntroLog "[STARTUP] Load settings JSON start"
            Invoke-IntroChunk "Load settings data" {
                $settingsModule = Join-Path $RootPath "src\Core\Settings.psm1"
                if (Test-Path $settingsModule) {
                    Import-Module $settingsModule -Force -ErrorAction Stop
                    if (Get-Command Get-QOSettings -ErrorAction SilentlyContinue) {
                        $null = Get-QOSettings
                    }
                }
            }

            Write-IntroLog "[STARTUP] Load settings JSON end"

            Set-IntroState 76 "Loading tickets..."
            Write-IntroLog "[STARTUP] Load tickets JSON start"
            Invoke-IntroChunk "Load ticket data" {
                $ticketsModule = Join-Path $RootPath "src\Core\Tickets.psm1"
                if (Test-Path $ticketsModule) {
                    Import-Module $ticketsModule -Force -ErrorAction Stop
                    if (Get-Command Get-QOTickets -ErrorAction SilentlyContinue) {
                        $null = Get-QOTickets
                    }
                }
            }

            Write-IntroLog "[STARTUP] Load tickets JSON end"

            Set-IntroState 80 "Scanning installed apps..."
            Write-IntroLog "[STARTUP] File system scan start (installed apps)"
            Invoke-IntroChunk "Scan installed apps" {
                $appsModule = Join-Path $RootPath "src\Apps\InstalledApps.psm1"
                if (Test-Path $appsModule) {
                    Import-Module $appsModule -Force -ErrorAction Stop
                    if (Get-Command Get-QOTInstalledAppsCached -ErrorAction SilentlyContinue) {
                        $null = Get-QOTInstalledAppsCached
                    }
                }
            }
            Write-IntroLog "[STARTUP] File system scan end (installed apps)"

            Set-IntroState 84 "Running startup warmup..."
            Invoke-IntroChunk "Run startup warmup" {
                $engineModule = Join-Path $RootPath "src\Core\Engine\Engine.psm1"
                if (Test-Path $engineModule) {
                    Import-Module $engineModule -Force -ErrorAction Stop
                    if (Get-Command Invoke-QOTStartupWarmup -ErrorAction SilentlyContinue) {
                        Invoke-QOTStartupWarmup -RootPath $RootPath
                    }
                }
            }

            Set-IntroState 88 "Finalising startup..."
            Start-Sleep -Milliseconds 150

            $State.Completed = $true
        }

       catch {
            $State.Error = $_.Exception.ToString()
            $State.Completed = $true
            throw
        }
        }).AddArgument($rootPath).AddArgument($startupState).AddArgument($script:QOTLogPath)

        Stop-StartupChunk "Startup runspace preparation"
        Start-StartupChunk "Startup background tasks"

        $startupAsync = $startupPs.BeginInvoke()

        $startupFrame = New-Object System.Windows.Threading.DispatcherFrame
        $startupTimer = New-Object System.Windows.Threading.DispatcherTimer
        $startupTimeoutMs = 45000
        $startupTimeoutHit = $false
        $startupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $startupTimer.Interval = [TimeSpan]::FromMilliseconds(120)
        $startupTimer.Add_Tick({
            if ($startupState.Status) {
                Update-StartupWidget $startupState.Percent $startupState.Status
            }
            if ($startupAsync.IsCompleted) {
                $startupTimer.Stop()
                $startupFrame.Continue = $false
                return
            }

            if ($startupStopwatch.ElapsedMilliseconds -ge $startupTimeoutMs) {
                $startupTimeoutHit = $true
                $startupState.Status = "Startup warmup timed out, continuing..."
                $startupTimer.Stop()
                $startupFrame.Continue = $false
            }
        })
            $startupTimer.Start()
            [System.Windows.Threading.Dispatcher]::PushFrame($startupFrame)

            try {
                if ($startupTimeoutHit) {
                    try {
                        $startupPs.Stop()
                    } catch { }
                    & $script:QOTLog ("[STARTUP] Background startup tasks timed out after {0} ms. Continuing with main window initialisation." -f $startupTimeoutMs) "WARN"
                } else {
                    $null = $startupPs.EndInvoke($startupAsync)
                }
            } finally {
                $startupStopwatch.Stop()
                if ($startupPs) {
                    try { $startupPs.Dispose() } catch { }
                }
                if ($startupRunspace) {
                    try { $startupRunspace.Dispose() } catch { }
                }
            }
        } finally {
            # Ensure timer is always stopped and disposed, even if an error occurs during runspace setup
            if ($startupTimer) {
                try { $startupTimer.Stop() } catch { }
                try { $startupTimer = $null } catch { }
            }
            if ($startupFrame) {
                try { $startupFrame = $null } catch { }
            }
        }
        Stop-StartupChunk "Startup background tasks"

        if ($startupState.Error) {
            throw $startupState.Error
        }
    }

    Update-StartupWidget 75 "Building main window..."
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
    Start-Sleep -Milliseconds 200

    # Complete progress bar to 100% before showing main window
    Update-StartupWidget 85 "Finalizing..."
    Start-Sleep -Milliseconds 150
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }

    Update-StartupWidget 92 "Ready..."
    Start-Sleep -Milliseconds 150
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }

    Update-StartupWidget 100 "Done!"
    Start-Sleep -Milliseconds 200
    if ($widget) { $widget.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }

    Start-StartupChunk "MainWindow launch"
    & $script:QOTLog "Starting main window" "INFO"
    & $script:QOTLog "[STARTUP] MainWindow launch started" "INFO"

    # MainWindow initialisation is wrapped in its own try/catch so that if every
    # fallback path (Start-QOTMain -> in-process fallback -> rescue launch) fails,
    # the user sees a friendly error dialog instead of a silent black-screen exit.
    # On fatal init failure we set $script:MainWindowInitFatal so the main loop
    # below skips the app.Run() call and the process exits cleanly.
    $script:MainWindowInitFatal = $false
    $mainWindowInitError = $null
    try {

    # Keep the startup widget open during main window initialization
    # It will fade out once the main window is visible

    # Route through Start-QOTMain without WarmupOnly so the window lifecycle
    # is owned by MainWindow.UI.psm1 (Show + app.Run) on a single code path.
    #
    # Some deployments have reported Start-QOTMain returning immediately after
    # startup logs report "Starting main window", leaving users with no visible
    # UI. If that happens in the first couple seconds, attempt a direct
    # Start-QOTMainWindow fallback path so the app can still recover.
    $shouldAttemptFallbackLaunch = $false
    $startMainThrew = $false
    $mainWindowLaunchTimer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Hand the startup widget to MainWindow so it can replace it cleanly
        # as soon as the main UI is ready to render.
        Start-QOTMain -RootPath $rootPath -SplashWindow $widget
    }
    catch {
        $startMainErrorDetail = if ($_.Exception) { $_.Exception.ToString() } else { $_.ToString() }
        & $script:QOTLog ("[STARTUP] Start-QOTMain threw; attempting direct MainWindow fallback launch.`n{0}" -f $startMainErrorDetail) "ERROR"
        $shouldAttemptFallbackLaunch = $true
        $startMainThrew = $true
    }
    finally {
        if ($mainWindowLaunchTimer) {
            $mainWindowLaunchTimer.Stop()
        }
    }
    if (-not $startMainThrew -and -not $shouldAttemptFallbackLaunch) {
        try {
            $visibleWindowCount = 0
            $visibleNonSplashWindowCount = 0
            $app = [System.Windows.Application]::Current
            if ($app) {
                $visibleWindows = @($app.Windows | Where-Object { $_ -and $_.IsVisible })
                $visibleWindowCount = $visibleWindows.Count
                $visibleNonSplashWindowCount = @(
                    $visibleWindows | Where-Object {
                        if (-not $_) { return $false }
                        if ($widget -and [object]::ReferenceEquals($_, $widget)) { return $false }
                        return $true
                    }
                ).Count
            }

            if ($visibleNonSplashWindowCount -gt 0) {
                & $script:QOTLog ("[STARTUP] Start-QOTMain returned after {0} ms and detected {1} visible WPF window(s) ({2} excluding widget); skipping fallback launch." -f [math]::Round($mainWindowLaunchTimer.Elapsed.TotalMilliseconds), $visibleWindowCount, $visibleNonSplashWindowCount) "INFO"
            }
            else {
                & $script:QOTLog ("[STARTUP] Start-QOTMain returned after {0} ms with no visible non-widget window (visible windows total: {1}); attempting direct MainWindow fallback launch." -f [math]::Round($mainWindowLaunchTimer.Elapsed.TotalMilliseconds), $visibleWindowCount) "WARN"
                $shouldAttemptFallbackLaunch = $true
            }
        }
        catch {
            & $script:QOTLog ("[STARTUP] Could not verify WPF window visibility after Start-QOTMain returned: {0}`nAttempting fallback launch as a safeguard." -f $_.Exception.Message) "WARN"
            $shouldAttemptFallbackLaunch = $true
        }
    }
    
    if ($shouldAttemptFallbackLaunch) {
        $mainWindowModulePath = Join-Path $rootPath "src\UI\MainWindow.UI.psm1"
        if (-not (Test-Path -LiteralPath $mainWindowModulePath)) {
            throw "MainWindow UI module not found for fallback launch: $mainWindowModulePath"
        }

        & $script:QOTLog "[STARTUP] Attempting in-process fallback MainWindow launch." "WARN"
        $fallbackModule = Import-Module -Name $mainWindowModulePath -Force -PassThru -ErrorAction Stop
        if (-not $fallbackModule) {
            throw "MainWindow UI module import failed during fallback launch: $mainWindowModulePath"
        }

        & $fallbackModule {
            param($SplashWindow)
            $cmd = Get-Command -Name 'Start-QOTMainWindow' -ErrorAction Stop
            $invokeArgs = @{}
            if ($cmd.Parameters.ContainsKey('SplashWindow')) { $invokeArgs['SplashWindow'] = $SplashWindow }
            if ($cmd.Parameters.ContainsKey('Issues')) {
                $requiresNonEmptyIssues = $false
                try {
                    foreach ($attr in @($cmd.Parameters['Issues'].Attributes)) {
                        if ($attr -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute]) {
                            $requiresNonEmptyIssues = $true
                            break
                        }
                    }
                }
                catch { }
                $invokeArgs['Issues'] = if ($requiresNonEmptyIssues) { @("Startup fallback launch") } else { @() }
            }

            try {
                Start-QOTMainWindow @invokeArgs
            }
            catch [System.Management.Automation.ParameterBindingException] {
                $bindingMessage = $_.Exception.Message
                $issuesBindingProblem = ($bindingMessage -match "parameter name 'Issues'") -or (($bindingMessage -match "parameter 'Issues'") -and ($bindingMessage -match "empty collection"))
                if ($issuesBindingProblem) {
                    $invokeArgs['Issues'] = @("Startup fallback launch")
                    Start-QOTMainWindow @invokeArgs
                }
                else {
                    throw
                }
            }
        } $widget
        return
    }

    # Final safeguard: if startup unexpectedly returns with no visible
    # main window, run one in-process rescue launch (no new process).
    $visibleNonWidgetAfterLaunch = 0
    try {
        $app = [System.Windows.Application]::Current
        if ($app) {
            $visibleNonWidgetAfterLaunch = @(
                $app.Windows | Where-Object {
                    if (-not $_) { return $false }
                    if (-not $_.IsVisible) { return $false }
                    if ($widget -and [object]::ReferenceEquals($_, $widget)) { return $false }
                    return $true
                }
            ).Count
        }
    }
    catch {
        & $script:QOTLog ("[STARTUP] Failed to verify post-launch window visibility: {0}" -f $_.Exception.Message) "WARN"
    }

    if ($visibleNonWidgetAfterLaunch -lt 1) {
        $mainWindowModulePath = Join-Path $rootPath "src\UI\MainWindow.UI.psm1"

        if (Test-Path -LiteralPath $mainWindowModulePath) {
            & $script:QOTLog "[STARTUP] No visible MainWindow detected after launch path; attempting in-process rescue launch." "WARN"
            $rescueModule = Import-Module -Name $mainWindowModulePath -Force -PassThru -ErrorAction Stop
            if (-not $rescueModule) {
                throw "MainWindow UI module import failed during rescue launch: $mainWindowModulePath"
            }

            & $rescueModule {
                param($SplashWindow)
                $cmd = Get-Command -Name 'Start-QOTMainWindow' -ErrorAction Stop
                $invokeArgs = @{}
                if ($cmd.Parameters.ContainsKey('SplashWindow')) { $invokeArgs['SplashWindow'] = $SplashWindow }
                if ($cmd.Parameters.ContainsKey('Issues')) {
                    $requiresNonEmptyIssues = $false
                    try {
                        foreach ($attr in @($cmd.Parameters['Issues'].Attributes)) {
                            if ($attr -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute]) {
                                $requiresNonEmptyIssues = $true
                                break
                            }
                        }
                    }
                    catch { }
                    $invokeArgs['Issues'] = if ($requiresNonEmptyIssues) { @("Startup rescue launch") } else { @() }
                }

                try {
                    Start-QOTMainWindow @invokeArgs
                }
                catch [System.Management.Automation.ParameterBindingException] {
                    $bindingMessage = $_.Exception.Message
                    $issuesBindingProblem = ($bindingMessage -match "parameter name 'Issues'") -or (($bindingMessage -match "parameter 'Issues'") -and ($bindingMessage -match "empty collection"))
                    if ($issuesBindingProblem) {
                        $invokeArgs['Issues'] = @("Startup rescue launch")
                        Start-QOTMainWindow @invokeArgs
                    }
                    else {
                        throw
                    }
                }
            } $widget
            return
        }
        else {
            & $script:QOTLog "[STARTUP] Rescue launcher skipped because MainWindow.UI.psm1 is missing." "ERROR"
        }
    }

    }  # End of MainWindow init try block
    catch {
        # Every fallback launch path has failed. Capture details, log them, and
        # show a single friendly error dialog before exiting. Do not retry - the
        # process is in a known-bad state and another attempt will fail the
        # same way.
        $mainWindowInitError = $_
        $script:MainWindowInitFatal = $true

        $initErrMsg = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
        $initErrFull = if ($_.Exception) { $_.Exception.ToString() } else { [string]$_ }
        & $script:QOTLog ("[STARTUP] MainWindow initialisation FAILED after all fallback paths exhausted: {0}" -f $initErrMsg) "ERROR"
        & $script:QOTLog ("[STARTUP] MainWindow init error detail:`n{0}" -f $initErrFull) "ERROR"

        # Close the startup widget so the error dialog isn't hidden behind it.
        if ($widget) {
            try { $widget.Close() } catch { }
        }

        $logPathHint = if ($script:QOTLogPath) { $script:QOTLogPath } else { (Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs") }
        $dialogBody = @(
            "Quinn Optimiser Toolkit could not start the main window."
            ""
            "Reason: $initErrMsg"
            ""
            "Full log: $logPathHint"
            ""
            "The application will now close. If this keeps happening, please share the log file when reporting it."
        ) -join "`r`n"

        try {
            [System.Windows.MessageBox]::Show(
                $dialogBody,
                "Quinn Optimiser Toolkit - Could not start",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
        }
        catch {
            # WPF dialog failed too - fall back to the console so the user still
            # sees something rather than a silent exit.
            try { Show-ConsoleWindow } catch { }
            Write-Host ""
            Write-Host "============================================================" -ForegroundColor Red
            Write-Host "Quinn Optimiser Toolkit - MainWindow init failed" -ForegroundColor Red
            Write-Host "============================================================" -ForegroundColor Red
            Write-Host $initErrMsg -ForegroundColor Yellow
            Write-Host ""
            Write-Host "See log: $logPathHint" -ForegroundColor Gray
        }
    }

    if ($script:MainWindowInitFatal) {
        & $script:QOTLog "[STARTUP] Skipping Application.Run() because MainWindow init was fatal." "WARN"
        Stop-StartupChunk "MainWindow launch"
        return
    }

    # Run the Application main loop to keep the window open
    try {
        $app = [System.Windows.Application]::Current
        if ($app) {
            $mainWindows = @($app.Windows | Where-Object { $_ -and $_.Title -notlike "*widget*" })

            if ($mainWindows.Count -gt 0) {
                $mainWindow = $mainWindows[0]

                # Ensure window is visible and on screen
                try {
                    $mainWindow.Visibility = [System.Windows.Visibility]::Visible
                    $mainWindow.Show()
                    # Don't activate/focus - let user continue working
                    # $mainWindow.Activate()
                    # $mainWindow.BringIntoView()
                    # $mainWindow.Focus() | Out-Null

                    # Set reasonable position if off-screen
                    if ($mainWindow.Left -lt -1000 -or $mainWindow.Top -lt -1000) {
                        $mainWindow.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
                        $mainWindow.Left = 100
                        $mainWindow.Top = 100
                    }
                }
                catch {
                    & $script:QOTLog ("[STARTUP] Warning: Could not configure window visibility: {0}" -f $_) "WARN"
                }

                # Wait a moment at 100% for user to see completion
                Write-StartupMark "Progress complete, waiting before transition"
                Start-Sleep -Milliseconds 1500

                # Fade out the startup widget now that main window is visible
                if ($widget) {
                    try {
                        $widget.Dispatcher.Invoke({
                            $fadeOutStoryboard = $widget.FindResource("FadeOutAnimation")
                            if ($fadeOutStoryboard) {
                                $fadeOutStoryboard.Add_Completed({
                                    param($sender, $args)
                                    try { $widget.Close() } catch { }
                                })
                                $fadeOutStoryboard.Begin($widget)
                            }
                            else {
                                $widget.Close()
                            }
                        }, [System.Windows.Threading.DispatcherPriority]::Normal) | Out-Null
                        & $script:QOTLog "[STARTUP] Startup widget fading out." "INFO"
                    }
                    catch {
                        & $script:QOTLog ("[STARTUP] Failed to fade out startup widget: {0}" -f $_.Exception.Message) "WARN"
                        try { $widget.Close() } catch { }
                    }
                }

                Write-StartupMark "Main window detected, running application loop"
                & $script:QOTLog "[STARTUP] Main window visible; running application main loop." "INFO"

                # Set ShutdownMode to OnLastWindowClose so the app exits when user closes the main window
                $app.ShutdownMode = [System.Windows.ShutdownMode]::OnLastWindowClose

                # Run the application main loop - this blocks until the main window is closed
                $app.Run() | Out-Null

                # Show console window again after app closes for testing/debugging
                Show-ConsoleWindow
            }
        }
    }
    catch {
        & $script:QOTLog ("[STARTUP] Error in application loop: {0}" -f $_.Exception.Message) "WARN"
        # Show console window if there was an error
        Show-ConsoleWindow
    }

    Write-StartupMark "MainWindow run loop exited"
    & $script:QOTLog "MainWindow run loop exited" "INFO"
    Stop-StartupChunk "MainWindow launch"
}
catch {
    $fatalError = $_.Exception.Message
    $fatalStack = if ($_.Exception) { $_.Exception.StackTrace } else { "" }
    & $script:QOTLog ("[STARTUP] FATAL ERROR - Application startup failed: {0}" -f $fatalError) "ERROR"
    if ($fatalStack) { & $script:QOTLog ("[STARTUP] Stack trace: {0}" -f $fatalStack) "ERROR" }

    # Attempt to show user-facing error dialog
    try {
        [System.Windows.MessageBox]::Show(
            "Quinn Optimiser Toolkit failed to start.`n`nError: $fatalError`n`nPlease check the logs in: $(if ($script:QOTLogPath) { $script:QOTLogPath } else { (Join-Path $env:ProgramData 'QuinnOptimiserToolkit\Logs') })",
            "Quinn Optimiser Toolkit - Startup Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
    catch {
        # Fallback if MessageBox fails
        Write-Host "FATAL ERROR: $fatalError" -ForegroundColor Red
        Write-Host "Check logs for details" -ForegroundColor Red
    }

    # Ensure console is visible for error messages
    Show-ConsoleWindow
}
finally {
    $WarningPreference = $oldWarningPreference
    # Ensure console is visible at the end for any final messages or errors
    Show-ConsoleWindow
}
