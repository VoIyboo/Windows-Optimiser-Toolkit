$repoRoot = Split-Path -Parent $PSScriptRoot
$networkModule = Import-Module (Join-Path $repoRoot "src\Advanced\NetworkAndServices\NetworkAndServices.psm1") -Force -PassThru -ErrorAction Stop

Describe "Network reset outcome handling" {
    It "treats a clean exit code as success" {
        InModuleScope $networkModule.Name {
            $result = Resolve-QOTNetshIpResetOutcome -TaskName "Network reset" -ExitCode 0 -StdOut "" -StdErr ""

            $result.Status | Should Be "Success"
            [string]::IsNullOrWhiteSpace($result.Reason) | Should Be $true
        }
    }

    It "keeps restart-required output as success" {
        InModuleScope $networkModule.Name {
            $result = Resolve-QOTNetshIpResetOutcome -TaskName "Network reset" -ExitCode 0 -StdOut "Restart the computer to complete this action." -StdErr ""

            $result.Status | Should Be "Success"
            $result.Reason | Should Be "Restart recommended"
        }
    }

    It "treats the known protected-entry netsh result as success" {
        InModuleScope $networkModule.Name {
            $stdOut = @'
Resetting Interface, OK!
Resetting , failed.
Access is denied.

Restart the computer to complete this action.
'@
            $result = Resolve-QOTNetshIpResetOutcome -TaskName "Network reset" -ExitCode 1 -StdOut $stdOut -StdErr ""

            $result.Status | Should Be "Success"
            $result.Reason | Should Match "Restart recommended"
        }
    }

    It "preserves real failures" {
        InModuleScope $networkModule.Name {
            $result = Resolve-QOTNetshIpResetOutcome -TaskName "Network reset" -ExitCode 1 -StdOut "Something broke" -StdErr "fatal"

            $result.Status | Should Be "Failed"
            $result.Reason | Should Be "Command exited with code 1"
            $result.Error | Should Be "fatal"
        }
    }
}
