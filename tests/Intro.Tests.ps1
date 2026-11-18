# Exercise the real intro control flow with inert module and window entry points.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$base = [IO.Path]::GetTempPath().TrimEnd('\')
$fixture = Join-Path $base ('QotIntro-' + [guid]::NewGuid())
try {
    foreach ($dir in 'src\Intro\StartupWidget','src\Core\Config','src\Core\Logging','src\Core\Engine','src\UI') {
        $null = New-Item -Type Directory -Path (Join-Path $fixture $dir) -Force
    }
    $intro = Join-Path $fixture 'src\Intro\Intro.ps1'
    Copy-Item -LiteralPath (Join-Path $repo 'src\Intro\Intro.ps1') -Destination $intro
    $env:QOT_INTRO_TRACE = Join-Path $fixture 'trace.txt'
    Set-Content (Join-Path $fixture 'src\Intro\StartupWidget\StartupWidget.UI.psm1') 'function New-QOTStartupWidget { Add-Content $env:QOT_INTRO_TRACE widget }'
    Set-Content (Join-Path $fixture 'src\Intro\StartupWidget\StartupWidget.xaml') '<Grid/>'
    foreach ($file in 'Config\Config','Logging\Logging') {
        Set-Content (Join-Path $fixture "src\Core\$file.psm1") '# inert fixture'
    }
    Set-Content (Join-Path $fixture 'src\Core\Engine\Engine.psm1') @'
function Start-QOTMain {
    param($RootPath,$SplashWindow)
    # ShowDialog returns after the user closes the window.
    Add-Content $env:QOT_INTRO_TRACE primary
    if ($env:QOT_INTRO_FAIL) { throw 'Simulated initialisation failure' }
}
'@
    Set-Content (Join-Path $fixture 'src\UI\MainWindow.UI.psm1') 'function Start-QOTMainWindow { Add-Content $env:QOT_INTRO_TRACE fallback }'
    foreach ($failure in $false,$true) {
        $env:QOT_INTRO_FAIL = if ($failure) { '1' } else { $null }
        [IO.File]::WriteAllText($env:QOT_INTRO_TRACE,'')
        & $intro -SkipSplash -Quiet -LogPath (Join-Path $fixture 'intro.log')
        $trace = (Get-Content $env:QOT_INTRO_TRACE) -join ','
        $expected = if ($failure) { 'primary,fallback' } else { 'primary' }
        if ($trace -ne $expected) { throw "Expected '$expected', got '$trace'." }
    }
    Write-Host 'PASS Closing the toolkit exits once; an initialisation error gets one recovery launch; SkipSplash skips the widget.'
} finally {
    Remove-Item Env:\QOT_INTRO_TRACE,Env:\QOT_INTRO_FAIL -ErrorAction SilentlyContinue
    if ((Split-Path $fixture -Parent) -eq $base -and (Split-Path $fixture -Leaf) -like 'QotIntro-*') { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
