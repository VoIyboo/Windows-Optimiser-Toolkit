$repoRoot = Split-Path -Parent $PSScriptRoot
$tweaksModulePath = Join-Path $repoRoot "src\TweaksAndCleaning\TweaksAndPrivacy\TweaksAndPrivacy.psm1"

Describe "News and taskbar content toggle isolation" {
    $source = Get-Content -LiteralPath $tweaksModulePath -Raw

    It "does not use the Widgets taskbar button state to decide whether News is disabled" {
        $match = [regex]::Match(
            $source,
            'Invoke-QTweakNewsAndInterests"\s*\{(?<body>.*?)\n\s*\}\s*"Invoke-QTweakMeetNow"',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        $match.Success | Should Be $true
        $match.Groups["body"].Value | Should Not Match "TaskbarDa"
    }

    It "does not force Widgets on when restoring News and taskbar content" {
        $match = [regex]::Match(
            $source,
            'function Invoke-QTweakEnableNewsAndInterests\s*\{(?<body>.*?)\n\}',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        $match.Success | Should Be $true
        $match.Groups["body"].Value | Should Not Match "AllowWidgets"
        $match.Groups["body"].Value | Should Not Match "TaskbarDa"
    }
}
