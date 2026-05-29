# src\Core\QOTImportHelper.ps1
# Shared helper for safely importing PowerShell modules with clear diagnostics.
#
# Dot-source this script at the top of any module that has optional or
# best-effort imports, then call Import-QOTOptionalModule instead of
# `Import-Module ... -ErrorAction SilentlyContinue`. Failed imports get
# logged to the standard log directory AND surfaced via Write-Warning so
# the failure mode is never silent.

if (-not (Get-Variable -Name 'QOTImportHelperLoaded' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:QOTImportHelperLoaded = $true

    function Get-QOTImportLogPath {
        # We log to ProgramData rather than relying on Logging.psm1, because
        # the whole point of this helper is to survive a failed Logging.psm1
        # import. Falls back to the user temp directory if ProgramData isn't
        # writable for some reason.
        $programData = [string]$env:ProgramData
        if ([string]::IsNullOrWhiteSpace($programData)) { $programData = $env:TEMP }
        if ([string]::IsNullOrWhiteSpace($programData)) { return $null }

        $dir = Join-Path $programData 'QuinnOptimiserToolkit\Logs'
        try {
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
            }
        }
        catch { return $null }
        return (Join-Path $dir 'ModuleImports.log')
    }

    function Write-QOTImportDiagnostic {
        param(
            [Parameter(Mandatory)][string]$Message,
            [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'WARN'
        )

        # File log first - this is the survivable channel.
        $logPath = Get-QOTImportLogPath
        if ($logPath) {
            try {
                $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Add-Content -LiteralPath $logPath -Value ("[$stamp] [$Level] $Message") -Encoding UTF8 -ErrorAction SilentlyContinue
            }
            catch { }
        }

        # Then surface via Write-Warning so an interactive PowerShell host
        # sees the failure live. Wrapped because Write-Warning may be
        # suppressed by a $WarningPreference in some hosts; we always have
        # the file log as a backstop.
        try { Write-Warning $Message } catch { }
    }

    function Import-QOTOptionalModule {
        <#
        .SYNOPSIS
        Imports a PowerShell module and logs a clear warning if the import
        fails, rather than silently swallowing the error.
        .DESCRIPTION
        Use this in place of `Import-Module ... -ErrorAction SilentlyContinue`.
        If the module path does not exist, the file cannot be loaded, or the
        module itself throws during load, this function writes a diagnostic
        line to ProgramData\QuinnOptimiserToolkit\Logs\ModuleImports.log
        AND emits a Write-Warning so the failure is visible to anyone
        running the tool interactively.

        Returns $true on success, $false on failure.

        Pass -Critical to indicate that downstream functionality will not
        work without this module - the warning is logged at ERROR severity
        and the function still returns $false (callers decide what to do).
        .EXAMPLE
        Import-QOTOptionalModule -Path "$PSScriptRoot\..\Core\Logging\Logging.psm1" -ImporterContext 'Apps.Actions'
        #>
        param(
            [Parameter(Mandatory)][string]$Path,
            [string]$ImporterContext = '',
            [switch]$Global,
            [switch]$Force,
            [switch]$Critical
        )

        $ctx = if ([string]::IsNullOrWhiteSpace($ImporterContext)) { '' } else { "[$ImporterContext] " }

        if ([string]::IsNullOrWhiteSpace($Path)) {
            $sev = if ($Critical) { 'ERROR' } else { 'WARN' }
            Write-QOTImportDiagnostic -Message ("{0}Import-QOTOptionalModule called with empty path." -f $ctx) -Level $sev
            return $false
        }

        if (-not (Test-Path -LiteralPath $Path)) {
            $sev = if ($Critical) { 'ERROR' } else { 'WARN' }
            Write-QOTImportDiagnostic -Message ("{0}Module file not found: '{1}'." -f $ctx, $Path) -Level $sev
            return $false
        }

        $params = @{ Name = $Path; ErrorAction = 'Stop' }
        if ($Global) { $params['Global'] = $true }
        if ($Force)  { $params['Force']  = $true }

        try {
            Import-Module @params -WarningAction SilentlyContinue
            return $true
        }
        catch {
            $sev = if ($Critical) { 'ERROR' } else { 'WARN' }
            $msg = if ($Critical) {
                "{0}CRITICAL: Failed to import required module '{1}'. Downstream features will not work. Error: {2}" -f $ctx, $Path, $_.Exception.Message
            } else {
                "{0}Failed to import optional module '{1}'. Error: {2}" -f $ctx, $Path, $_.Exception.Message
            }
            Write-QOTImportDiagnostic -Message $msg -Level $sev
            return $false
        }
    }
}
