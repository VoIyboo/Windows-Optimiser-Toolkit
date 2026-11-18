# Validate shipped sources without invoking any toolkit actions.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sources = @(Get-ChildItem (Join-Path $root 'src') -Recurse -File -Include *.ps1,*.psm1)
$sources += Get-Item (Join-Path $root 'bootstrap.ps1'),(Join-Path $root 'run-local.ps1'),(Join-Path $root 'legacy\V2.7')
$failures = @()
foreach ($file in $sources) {
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
    foreach ($problem in $errors) { $failures += "$($file.Name) line $($problem.Extent.StartLineNumber) - $($problem.Message)" }
}
Add-Type -AssemblyName PresentationFramework
$views = @(Get-ChildItem (Join-Path $root 'src') -Recurse -Filter '*.xaml')
foreach ($view in $views) {
    $reader = [Xml.XmlReader]::Create($view.FullName)
    try { $null = [Windows.Markup.XamlReader]::Load($reader) }
    catch { $failures += "$($view.Name) - $($_.Exception.Message)" }
    finally { $reader.Close() }
}
if ($failures) { throw ($failures -join [Environment]::NewLine) }
Write-Host "PASS Parsed $($sources.Count) PowerShell sources and loaded $($views.Count) WPF resources."
