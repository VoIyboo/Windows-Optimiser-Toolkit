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

    # Shorten the deadline in the temporary copy while keeping the WPF timer,
    # background runspace, cancellation and main-window handoff intact.
    $introText = [IO.File]::ReadAllText($intro).Replace('$startupTimeoutMs = 45000', '$startupTimeoutMs = 2000')
    [IO.File]::WriteAllText($intro, $introText, [Text.UTF8Encoding]::new($true))
    $env:QOT_INTRO_FAIL = $null
    Add-Content (Join-Path $fixture 'src\Core\Engine\Engine.psm1') @'
function Invoke-QOTStartupWarmup {
    param($RootPath)
    $idPath = Join-Path $RootPath 'warmup-runspace.txt'
    [IO.File]::WriteAllText($idPath, [runspace]::DefaultRunspace.InstanceId.ToString())
    try {
        Start-Sleep -Seconds 6
        Add-Content $env:QOT_INTRO_TRACE completed
    } finally {
        [IO.File]::AppendAllText($env:QOT_INTRO_TRACE, "cleanup`r`n")
    }
}
'@
    [IO.File]::WriteAllText($env:QOT_INTRO_TRACE, '')
    & $intro -EnableStartupWarmup -SkipSplash -Quiet -LogPath (Join-Path $fixture 'warmup.log')
    $trace = (Get-Content $env:QOT_INTRO_TRACE) -join ','
    if ($trace -ne 'cleanup,primary') { throw "Expected warmup cancellation before the main window opened. Got '$trace'." }
    $warmupId = [guid]([IO.File]::ReadAllText((Join-Path $fixture 'warmup-runspace.txt')))
    if (Get-Runspace | Where-Object InstanceId -eq $warmupId) { throw 'The timed-out warmup runspace was left open.' }
    Write-Host 'PASS A timed-out warmup stops, releases its runspace and opens the main window once.'
} finally {
    Remove-Item Env:\QOT_INTRO_TRACE,Env:\QOT_INTRO_FAIL -ErrorAction SilentlyContinue
    if ((Split-Path $fixture -Parent) -eq $base -and (Split-Path $fixture -Leaf) -like 'QotIntro-*') { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
