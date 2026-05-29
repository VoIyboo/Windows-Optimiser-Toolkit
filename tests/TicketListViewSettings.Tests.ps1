$repoRoot = Split-Path -Parent $PSScriptRoot
$settingsModule = Import-Module (Join-Path $repoRoot "src\Core\Settings.psm1") -Force -PassThru -ErrorAction Stop
$ticketsUiModule = Import-Module (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Force -PassThru -ErrorAction Stop

Describe "Ticket list view persistence" {
    BeforeEach {
        $global:QOTTestSettingsPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-settings-" + [guid]::NewGuid().ToString("N") + ".json")
    }

    AfterEach {
        if (Test-Path -LiteralPath $global:QOTTestSettingsPath) {
            Remove-Item -LiteralPath $global:QOTTestSettingsPath -Force -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name QOTTestSettingsPath -Scope Global -ErrorAction SilentlyContinue
    }

    It "round-trips the selected filter and sort settings" {
        InModuleScope $settingsModule.Name {
            $script:SettingsPath = $global:QOTTestSettingsPath
            if (Test-Path -LiteralPath $script:SettingsPath) {
                Remove-Item -LiteralPath $script:SettingsPath -Force -ErrorAction SilentlyContinue
            }

            $saved = Set-QOTicketListViewSettings -ShowOpen $true -ShowClosed $false -ShowDeleted $true -SortMode "Oldest" -AssigneeFilter "Aaron Millar"
            $saved.ShowOpen | Should Be $true
            $saved.ShowClosed | Should Be $false
            $saved.ShowDeleted | Should Be $true
            $saved.SortMode | Should Be "Oldest"
            $saved.AssigneeFilter | Should Be "Aaron Millar"

            $loaded = Get-QOTicketListViewSettings
            $loaded.ShowOpen | Should Be $true
            $loaded.ShowClosed | Should Be $false
            $loaded.ShowDeleted | Should Be $true
            $loaded.SortMode | Should Be "Oldest"
            $loaded.AssigneeFilter | Should Be "Aaron Millar"
        }
    }

    It "loads the persisted filter and sort into the tickets runtime state" {
        InModuleScope $settingsModule.Name {
            $script:SettingsPath = $global:QOTTestSettingsPath
            if (Test-Path -LiteralPath $script:SettingsPath) {
                Remove-Item -LiteralPath $script:SettingsPath -Force -ErrorAction SilentlyContinue
            }

            Set-QOTicketListViewSettings -ShowOpen $true -ShowClosed $false -ShowDeleted $true -SortMode "Oldest" -AssigneeFilter "Aaron Millar" | Out-Null
        }

        InModuleScope $ticketsUiModule.Name {
            $script:TicketsFilterState = $null
            $state = Get-QOTicketsFilterState
            $state.ShowOpen | Should Be $true
            $state.ShowClosed | Should Be $false
            $state.ShowDeleted | Should Be $true
            $state.SortMode | Should Be "Oldest"
            $state.AssigneeFilter | Should Be "Aaron Millar"
        }
    }
}
