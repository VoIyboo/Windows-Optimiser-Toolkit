# Uses WPF controls without opening a window. Every backend callback is a fixture.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$repo = Split-Path $PSScriptRoot -Parent
$tempBase = [IO.Path]::GetTempPath()
$fixture = Join-Path $tempBase ('qot-action-ui-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$previousData = $env:ProgramData
$previousLocal = $env:LOCALAPPDATA
$previousTestMode = $env:QOT_UI_TOGGLE_TEST_MODE
$env:ProgramData = $fixture
$env:LOCALAPPDATA = $fixture
$env:QOT_UI_TOGGLE_TEST_MODE = '1'
$failures = [Collections.Generic.List[string]]::new()
function Check($Condition, [string]$Description) {
    if (!$Condition) { $failures.Add($Description); Write-Host "FAIL $Description" }
}
try {
    $reader = [Xml.XmlReader]::Create("$repo/src/UI/MainWindow.xaml")
    try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
    Import-Module "$repo/src/Core/Actions/ActionsCatalog.psm1"
    Initialize-QOTActionCatalog
    Clear-QOTActionGroups
    $advanced = Import-Module "$repo/src/Advanced/AdvancedTweaks/AdvancedTweaks.UI.psm1" -PassThru
    $tweaks = Import-Module "$repo/src/TweaksAndCleaning/CleaningAndMain/TweaksAndCleaning.UI.psm1" -PassThru
    # Fixture state replaces both machine reads and settings persistence.
    & $advanced {
        param($window)
        function Resolve-QOTAdvancedToggleStateCommand { }
        function Get-QOTAdvancedLiveToggleState { $false }
        Initialize-QOTAdvancedTweaksUI -Window $window
    } $window
    & $tweaks {
        param($window)
        function Resolve-QOTTweaksToggleStateCommand { }
        function Get-QOTTweaksLiveToggleState { $false }
        Initialize-QOTTweaksAndCleaningUI -Window $window
    } $window
    foreach ($name in 'CbAdvRemoveOldProfiles','CbAdvAggressiveRestoreCleanup','CbAdvRepairNetworkAdapter','CbAdvServiceTuning') {
        Check (!$window.FindName($name).IsEnabled) "Unavailable control disabled: $name"
    }

    # Replace all action scripts before checking normal section events with test mode off.
    $sentinel = Join-Path $fixture 'called.txt'
    $fixtureScript = Join-Path $fixture 'action.ps1'
    @('param($Window)', 'Add-Content -LiteralPath $Window.Tag -Value called', '[pscustomobject]@{Status="Success"}') |
        Set-Content -LiteralPath $fixtureScript
    $window.Tag = $sentinel
    foreach ($definition in (Get-QOTActionDefinitions)) {
        Register-QOTActionDefinition -ActionId $definition.ActionId -Label $definition.Label -ScriptPath $fixtureScript
    }
    $env:QOT_UI_TOGGLE_TEST_MODE = '0'
    foreach ($test in @(
        @{ Header='CbSectionBrowserCleanup'; Action='CbChromeLightCleanup' }
        @{ Header='CbAdvSectionRepairRecovery'; Action='CbAdvRunSfcRepair' }
    )) {
        $header = $window.FindName($test.Header)
        $header.IsChecked = $true
        $header.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        Check ($window.FindName($test.Action).IsChecked) "Section selects its options: $($test.Header)"
        Check (!(Test-Path -LiteralPath $sentinel)) "Section waits for Play: $($test.Header)"
        $header.IsChecked = $false
        $header.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    }
    $env:QOT_UI_TOGGLE_TEST_MODE = '1'

    foreach ($test in @(
        @{ Name='CbDisableAdvertisingId'; Module=$tweaks; Group='Tweaks' }
        @{ Name='CbAdvDisableFullscreenOptimizations'; Module=$advanced; Group='Advanced' }
    )) {
        $control = $window.FindName($test.Name)
        $events = [Collections.Generic.List[bool]]::new()
        & $test.Module {
            param($group,$name,$events)
            $state = if ($group -eq 'Tweaks') { $script:QOTTweaksInstantToggleState } else { $script:QOTAdvancedInstantToggleState }
            $state.Metadata[$name].SetToggleStateCmd = { param($ActionId,$IsEnabled) $events.Add($IsEnabled) }.GetNewClosure()
        } $test.Group $test.Name $events
        # WPF raises Click for keyboard/automation activation as well as a mouse click.
        $control.IsChecked = $true
        $control.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        Check ($events.Count -eq 1 -and $events[0]) "Instant action dispatched from Click: $($test.Name)"
        Check (@(Get-QOTSelectedActions -Window $window).Count -eq 0) "Instant state is excluded from Play: $($test.Name)"
        $control.IsChecked = $false
    }
    $window.FindName('CbChromeLightCleanup').IsChecked = $true
    $selection = @(Get-QOTSelectedActionsInExecutionOrder -Window $window)
    Check ($selection.Count -eq 1 -and $selection[0].ActionId -eq 'Invoke-QCleanChromeCache') 'Single selected checkbox reaches Play'
    $window.FindName('CbChromeLightCleanup').IsChecked = $false

    $queueCount = 0
    $toggleCount = 0
    $available = @(Get-QOTActionDefinitions | Where-Object ActionId -ne 'Apps.RunSelected')
    foreach ($action in $available) {
        $queued = @(foreach ($group in (Get-QOTActionGroups)) {
            & $group.GetItems $window | Where-Object ActionId -eq $action.ActionId
        })
        $toggles = @(foreach ($uiModule in $tweaks,$advanced) {
            & $uiModule {
                param($id)
                $names = if ($script:QOTTweaksInstantToggleState) {
                    Get-QOTTweaksInstantToggleCommandNames -ActionId $id
                } else { Get-QOTAdvancedInstantToggleCommandNames -ActionId $id }
                if ($names) {
                    Get-Command -Name $names.Apply,$names.Undo -ErrorAction Stop
                }
            } $action.ActionId
        })
        if ($toggles.Count) { $toggleCount++ }
        if ($queued.Count) { $queueCount++ }
        Check (($queued.Count -eq 1 -and $toggles.Count -eq 0) -or ($queued.Count -eq 0 -and $toggles.Count -eq 2)) "One execution route for $($action.ActionId)"
    }
    Write-Host "Checked $queueCount queue actions and both commands for $toggleCount instant settings."
    if ($failures.Count) { throw "$($failures.Count) WPF regression(s): $($failures -join ', ')" }
    Write-Host 'WPF availability, section selection, instant controls and Play selection checks passed.'
} finally {
    if ($window) { $window.Close() }
    $env:ProgramData = $previousData
    $env:LOCALAPPDATA = $previousLocal
    $env:QOT_UI_TOGGLE_TEST_MODE = $previousTestMode
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($fixture)) -eq $tempBase.TrimEnd('\') -and
        [IO.Path]::GetFileName($fixture) -match '^qot-action-ui-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $fixture -Force -Recurse
    }
}
