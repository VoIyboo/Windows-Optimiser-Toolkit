# Example-Integration.ps1
# Demonstrates how to integrate the StartupWidget into your main application bootstrap

# Set script root for example (would be different in real usage)
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WidgetPath = Split-Path -Parent $ScriptRoot

# 1. Import the StartupWidget module
Import-Module "$WidgetPath\StartupWidget\StartupWidget.UI.psm1" -Force

# 2. Create the widget instance
$xamlPath = Join-Path $WidgetPath "StartupWidget\StartupWidget.xaml"
$startupWidget = New-QOTStartupWidget -Path $xamlPath

# 3. Show the widget (positions bottom-right, starts fade-in)
Show-QOTStartupWidget -Window $startupWidget

# 4. Simulate your application initialization
# In real usage, replace this with your actual initialization code

Write-Host "Startup Widget Demo - Simulating app initialization..."

# Phase 1: Loading modules
Update-QOTWidgetStatus -Window $startupWidget -Text "Loading modules..."
Update-QOTWidgetProgress -Window $startupWidget -Value 0
Start-Sleep -Milliseconds 300

Update-QOTWidgetProgress -Window $startupWidget -Value 15
Start-Sleep -Milliseconds 300

Update-QOTWidgetProgress -Window $startupWidget -Value 30
Start-Sleep -Milliseconds 300

# Phase 2: Initializing database/storage
Update-QOTWidgetStatus -Window $startupWidget -Text "Initializing storage..."
Update-QOTWidgetProgress -Window $startupWidget -Value 40
Start-Sleep -Milliseconds 300

Update-QOTWidgetProgress -Window $startupWidget -Value 55
Start-Sleep -Milliseconds 300

# Phase 3: Building UI
Update-QOTWidgetStatus -Window $startupWidget -Text "Building UI..."
Update-QOTWidgetProgress -Window $startupWidget -Value 70
Start-Sleep -Milliseconds 300

Update-QOTWidgetProgress -Window $startupWidget -Value 85
Start-Sleep -Milliseconds 300

# Phase 4: Final setup
Update-QOTWidgetStatus -Window $startupWidget -Text "Almost ready..."
Update-QOTWidgetProgress -Window $startupWidget -Value 95
Start-Sleep -Milliseconds 300

Update-QOTWidgetProgress -Window $startupWidget -Value 100
Update-QOTWidgetStatus -Window $startupWidget -Text "Ready!"
Start-Sleep -Milliseconds 500

# 5. Close the widget (with fade-out animation)
Write-Host "Closing startup widget..."
Close-QOTStartupWidget -Window $startupWidget

Write-Host "Widget closed. Main application window would show here."

# Keep the PowerShell window open for demo purposes
Read-Host "Press Enter to exit"
