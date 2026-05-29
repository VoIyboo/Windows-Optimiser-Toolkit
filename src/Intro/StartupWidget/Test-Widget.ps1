# Test-Widget.ps1
# Test the startup widget in STA mode

param([switch]$NoWait)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WidgetPath = $ScriptRoot

Write-Host "Loading WPF assemblies..."
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

Write-Host "Importing StartupWidget module..."
Import-Module "$WidgetPath\StartupWidget.UI.psm1" -Force

Write-Host "Creating widget..."
$xamlPath = Join-Path $WidgetPath "StartupWidget.xaml"
$widget = New-QOTStartupWidget -Path $xamlPath

Write-Host "Showing widget..."
Show-QOTStartupWidget -Window $widget

Write-Host "Testing widget updates..."
Start-Sleep -Milliseconds 500

$phases = @(
    @{ Text = "Loading modules..."; Value = 15 },
    @{ Text = "Initializing storage..."; Value = 35 },
    @{ Text = "Building UI..."; Value = 60 },
    @{ Text = "Loading settings..."; Value = 85 },
    @{ Text = "Ready!"; Value = 100 }
)

foreach ($phase in $phases) {
    Update-QOTWidgetStatus -Window $widget -Text $phase.Text
    Update-QOTWidgetProgress -Window $widget -Value $phase.Value
    Start-Sleep -Milliseconds 800
}

Write-Host "Closing widget..."
Close-QOTStartupWidget -Window $widget

Write-Host "Test complete!"

if (-not $NoWait) {
    Write-Host "Widget window should fade out and close..."
    Start-Sleep -Milliseconds 2000
}
