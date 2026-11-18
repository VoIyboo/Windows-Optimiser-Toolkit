# Run the real startup error handler without showing its modal dialog.
$ErrorActionPreference = 'Stop'
class QOTIntroTestDialog {
    static [int] $Calls
    static [bool] $Fail
    static [string] $Message

    static [void] Show([string]$message, [string]$title, [object]$buttons, [object]$icon) {
        [QOTIntroTestDialog]::Calls++
        [QOTIntroTestDialog]::Message = $message
        if ([QOTIntroTestDialog]::Fail) { throw 'Dialog unavailable' }
    }
}

$repo = Split-Path $PSScriptRoot -Parent
$temp = [IO.Path]::GetTempPath().TrimEnd('\')
$fixture = Join-Path $temp ('QotIntroFatal-' + [guid]::NewGuid().ToString('N'))
try {
    $dir = [IO.Directory]::CreateDirectory((Join-Path $fixture 'src\Intro'))
    $intro = Join-Path $dir.FullName 'Intro.ps1'
    $text = [IO.File]::ReadAllText((Join-Path $repo 'src\Intro\Intro.ps1'))
    $dialog = '[System.Windows.MessageBox]::Show('
    if (!$text.Contains($dialog)) { throw 'Could not intercept the startup error dialog.' }
    [IO.File]::WriteAllText($intro, $text.Replace($dialog, '[QOTIntroTestDialog]::Show('), [Text.UTF8Encoding]::new($true))

    $log = Join-Path $fixture 'intro.log'
    $expected = 'Engine module not found at ' + (Join-Path $fixture 'src\Core\Engine\Engine.psm1')
    foreach ($failDialog in $false,$true) {
        [QOTIntroTestDialog]::Calls = 0
        [QOTIntroTestDialog]::Fail = $failDialog
        $caught = $null
        try { & $intro -SkipSplash -Quiet -LogPath $log 6>$null }
        catch { $caught = $_ }
        if (!$caught -or $caught.Exception.Message -ne $expected) {
            throw "Expected the caller to receive the original missing-engine error when dialog failure was $failDialog. Got '$caught'."
        }
        if ([QOTIntroTestDialog]::Calls -ne 1 -or ![QOTIntroTestDialog]::Message.Contains($expected)) {
            throw 'Expected one error dialog containing the original startup failure.'
        }
    }
    Write-Host 'PASS Fatal startup errors reach the caller even when the error dialog fails.'
} finally {
    if (Test-Path -LiteralPath $fixture) {
        $target = (Resolve-Path -LiteralPath $fixture).Path
        if ((Split-Path $target -Parent) -eq $temp -and (Split-Path $target -Leaf) -match '^QotIntroFatal-[a-f0-9]{32}$') {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
}
