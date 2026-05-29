$repoRoot = Split-Path -Parent $PSScriptRoot
$settingsModule = Import-Module (Join-Path $repoRoot "src\Core\Settings.psm1") -Force -PassThru -ErrorAction Stop
$ticketsUiModule = Import-Module (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Force -PassThru -ErrorAction Stop

Describe "Tickets last sync status" {
    BeforeEach {
        $global:QOTLastSyncSettingsPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-last-sync-" + [guid]::NewGuid().ToString("N") + ".json")
    }

    AfterEach {
        if (Test-Path -LiteralPath $global:QOTLastSyncSettingsPath) {
            Remove-Item -LiteralPath $global:QOTLastSyncSettingsPath -Force -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name QOTLastSyncSettingsPath -Scope Global -ErrorAction SilentlyContinue
    }

    It "prefers the last successful sync timestamp over the watermark timestamp" {
        InModuleScope $settingsModule.Name {
            $script:SettingsPath = $global:QOTLastSyncSettingsPath
            $settings = New-QODefaultSettings -NoSave
            $settings.Tickets.EmailIntegration.LastSyncUtc = "2026-03-16T02:24:45.5901955Z"
            $settings.Tickets.EmailIntegration.LastSuccessfulSyncUtc = "2026-03-24T08:40:19.0000000Z"
            Save-QOSettings -Settings $settings
        }

        InModuleScope $ticketsUiModule.Name {
            $persisted = Get-QOTicketsPersistedLastSuccessfulSyncUtc
            $persisted.ToUniversalTime().ToString("o") | Should Be "2026-03-24T08:40:19.0000000Z"
        }
    }

    It "keeps the automatic email sync cadence at five minutes" {
        InModuleScope $ticketsUiModule.Name {
            (Get-QOTicketsSyncSuccessPollSeconds) | Should Be 300
        }
    }

    It "caps reconnect retries at one minute" {
        InModuleScope $ticketsUiModule.Name {
            (Get-QOTicketsSyncBackoffSeconds -FailureCount 3) | Should Be 60
            (Get-QOTicketsSyncBackoffSeconds -FailureCount 4) | Should Be 60
        }
    }

    It "hydrates the visible last-sync label from persisted successful sync time" {
        InModuleScope $settingsModule.Name {
            $script:SettingsPath = $global:QOTLastSyncSettingsPath
            $settings = New-QODefaultSettings -NoSave
            $settings.Tickets.EmailIntegration.LastSuccessfulSyncUtc = "2026-04-10T05:30:00.0000000Z"
            Save-QOSettings -Settings $settings
        }

        InModuleScope $ticketsUiModule.Name {
            $script:TicketsLastSuccessfulSyncUtc = [datetime]"2026-04-10T05:00:00.0000000Z"
            $label = Get-QOTicketsLastSuccessfulSyncLabel
            $label | Should Match "Last successful email sync:"
            $script:TicketsLastSuccessfulSyncUtc.ToUniversalTime().ToString("o") | Should Be "2026-04-10T05:30:00.0000000Z"
        }
    }

    It "shows actionable sync status text before the first successful sync" {
        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            $statusText = [System.Windows.Controls.TextBlock]::new()
            $script:TicketsShowSyncStatus = $true
            $script:TicketsLastSuccessfulSyncUtc = $null

            Set-QOTicketsSyncStatus -StatusText $statusText -Message "Background sync every 5 minutes"

            $statusText.Text | Should Be "Background sync every 5 minutes"
            ([string]$statusText.ToolTip) | Should Match "Last successful email sync: Never"
            ([string]$statusText.ToolTip) | Should Match "Click to sync now."
        }
    }
}
