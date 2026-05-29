$repoRoot = Split-Path -Parent $PSScriptRoot
$xamlPath = Join-Path $repoRoot "src\UI\MainWindow.xaml"
$uiModulePath = Join-Path $repoRoot "src\UI\MainWindow.UI.psm1"

Describe "Quick safe cleanup" {
    It "adds a header checkbox action" {
        $xaml = Get-Content -LiteralPath $xamlPath -Raw

        ($xaml -match 'x:Name="CbQuickSafeCleanup"') | Should Be $true
        ($xaml -match 'Content="Quick clean"') | Should Be $true
        ($xaml -match 'ToolTip="Run safe cleanup now"') | Should Be $true
    }

    It "runs a conservative cleanup list without destructive or deep-clean actions" {
        $source = Get-Content -LiteralPath $uiModulePath -Raw
        $safeActions = @(
            "Invoke-QCleanTemp",
            "Invoke-QCleanThumbnailCache",
            "Invoke-QCleanDirectXShaderCache",
            "Invoke-QCleanWERQueue",
            "Invoke-QCleanExplorerRecentItems",
            "Invoke-QCleanWindowsSearchHistory",
            "Invoke-QCleanEdgeCache",
            "Invoke-QCleanChromeCache",
            "Invoke-QCleanTeamsCache"
        )

        foreach ($actionId in $safeActions) {
            ($source -match [regex]::Escape(('"{0}"' -f $actionId))) | Should Be $true
        }

        $unsafeActions = @(
            "Invoke-QCleanRecycleBin",
            "Invoke-QCleanWindowsUpdateCache",
            "Invoke-QCleanPrefetchFiles",
            "Invoke-QCleanSetupLeftovers",
            "Invoke-QClearWindowsEventLogs"
        )

        $quickBlock = [regex]::Match($source, '(?s)\$quickSafeActionIds\s*=\s*@\((.*?)\)')
        $quickBlock.Success | Should Be $true

        foreach ($actionId in $unsafeActions) {
            ($quickBlock.Value -match [regex]::Escape($actionId)) | Should Be $false
        }
    }

    It "lets the task runner execute an explicit action list" {
        $source = Get-Content -LiteralPath $uiModulePath -Raw

        ($source -match 'function Run-QOTSelectedTasks') | Should Be $true
        ($source -match 'function Start-QOTSelectedTasksAsync') | Should Be $true
        ($source -match '\[object\[\]\]\$SelectedEntries') | Should Be $true
        ($source -match "PSBoundParameters\.ContainsKey\('SelectedEntries'\)") | Should Be $true
        ($source -match '-SelectedEntries \$quickEntries') | Should Be $true
    }
}
