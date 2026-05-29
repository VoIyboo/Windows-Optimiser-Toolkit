# Helpers.psm1
# Shared task/result helpers used across the cleaning, tweak, and network modules.
# Consolidated here so there is a single canonical copy of each function.

. (Join-Path $PSScriptRoot "QOTImportHelper.ps1")
$null = Import-QOTOptionalModule -Path (Join-Path $PSScriptRoot "Logging\Logging.psm1") -ImporterContext 'Helpers' -Force

function New-QOTTaskResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("Success","Skipped","Failed")][string]$Status,
        [string]$Reason,
        [string]$Error
    )

    [pscustomobject]@{
        Name   = $Name
        Status = $Status
        Reason = $Reason
        Error  = $Error
    }
}

function Test-QOTIsAdmin {
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

function Invoke-QOTRunNativeCommandTask {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$RequiresAdmin
    )

    if ($RequiresAdmin -and -not (Test-QOTIsAdmin)) {
        return New-QOTTaskResult -Name $TaskName -Status "Skipped" -Reason "Admin required"
    }

    $command = Get-Command -Name $FilePath -ErrorAction SilentlyContinue
    if (-not $command) {
        return New-QOTTaskResult -Name $TaskName -Status "Skipped" -Reason ("Command unavailable: {0}" -f $FilePath)
    }

    try {
        $argumentList = @($Arguments | Where-Object { $_ -ne $null })
        Write-QLog ("Task: running {0} {1}" -f $command.Source, ($argumentList -join ' '))

        $proc = Start-Process -FilePath $command.Source -ArgumentList $argumentList -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
        $exitCode = 0
        try { $exitCode = [int]$proc.ExitCode } catch { $exitCode = 0 }

        if ($exitCode -eq 0 -or $exitCode -eq 3010) {
            if ($exitCode -eq 3010) {
                return New-QOTTaskResult -Name $TaskName -Status "Success" -Reason "Restart recommended"
            }
            return New-QOTTaskResult -Name $TaskName -Status "Success"
        }

        return New-QOTTaskResult -Name $TaskName -Status "Failed" -Reason ("Command exited with code {0}" -f $exitCode)
    }
    catch {
        return New-QOTTaskResult -Name $TaskName -Status "Failed" -Reason "Command failed" -Error $_.Exception.Message
    }
}

Export-ModuleMember -Function `
    New-QOTTaskResult, `
    Test-QOTIsAdmin, `
    Invoke-QOTRunNativeCommandTask
