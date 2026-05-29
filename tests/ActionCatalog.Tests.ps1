$repoRoot = Split-Path -Parent $PSScriptRoot
$actionRegistryPath = Join-Path $repoRoot "src\Core\Actions\ActionRegistry.psm1"
$actionCatalogPath = Join-Path $repoRoot "src\Core\Actions\ActionsCatalog.psm1"

Import-Module $actionRegistryPath -Force -ErrorAction Stop | Out-Null
Import-Module $actionCatalogPath -Force -ErrorAction Stop | Out-Null

Describe "Action catalog coverage" {
    BeforeEach {
        Clear-QOTActionDefinitions
        Initialize-QOTActionCatalog
    }

    It "keeps unavailable advanced no-op actions out of the registered catalog" {
        foreach ($actionId in @(
                "Invoke-QRemoveOldProfiles",
                "Invoke-QAggressiveRestoreCleanup",
                "Invoke-QRepairAdapter",
                "Invoke-QServiceTune")) {
            (Get-QOTActionDefinition -ActionId $actionId) | Should Be $null
        }
    }

    It "keeps the unused driver action clearly labeled as report only" {
        $definition = Get-QOTActionDefinition -ActionId "Invoke-QScanUnusedDeviceDrivers"
        $definition | Should Not Be $null
        $definition.Label | Should Be "Scan unused device drivers (report only)"
        (Test-Path -LiteralPath $definition.ScriptPath) | Should Be $true
    }
}
