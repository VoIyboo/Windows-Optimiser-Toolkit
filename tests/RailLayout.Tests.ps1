$repoRoot = Split-Path -Parent $PSScriptRoot
$xamlPath = Join-Path $repoRoot "src\UI\MainWindow.xaml"
$uiModule = Import-Module (Join-Path $repoRoot "src\UI\MainWindow.UI.psm1") -Force -PassThru -ErrorAction Stop
$enginePath = Join-Path $repoRoot "src\Core\Engine\Engine.psm1"

Describe "Rail icon layout" {
    It "defines a single movable rail host in the main window" {
        $xaml = Get-Content -LiteralPath $xamlPath -Raw

        ($xaml -match 'x:Name="RailIconHost"') | Should Be $true
        ($xaml -match 'x:Name="TicketsRailSubmenu"') | Should Be $true
        ($xaml -match 'AllowDrop="True"') | Should Be $true
        ($xaml -match 'x:Name="BtnNavCleaning"') | Should Be $true
        ($xaml -match 'x:Name="BtnSettings"') | Should Be $true
    }

    It "reorders rail children and appends missing defaults" {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop

        InModuleScope $uiModule.Name {
            $host = [System.Windows.Controls.StackPanel]::new()
            foreach ($name in @("BtnNavCleaning","BtnNavApps","BtnNavAdvanced","BtnNavTickets")) {
                $button = [System.Windows.Controls.Button]::new()
                $button.Name = $name
                [void]$host.Children.Add($button)
            }

            $finalOrder = @(Apply-QOTRailIconOrder -Host $host -Order @("BtnNavTickets","BtnNavApps"))
            $currentOrder = @(Get-QOTRailIconCurrentOrder -Host $host)

            ($finalOrder -join ",") | Should Be "BtnNavTickets,BtnNavApps,BtnNavCleaning,BtnNavAdvanced"
            ($currentOrder -join ",") | Should Be "BtnNavTickets,BtnNavApps,BtnNavCleaning,BtnNavAdvanced"
        }
    }

    It "resolves wrapped rail items and drag targets using wrapper tags" {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop

        InModuleScope $uiModule.Name {
            $window = $null
            try {
                $host = [System.Windows.Controls.StackPanel]::new()
                foreach ($name in @("BtnNavCleaning","BtnNavApps","BtnNavAdvanced","BtnNavTickets")) {
                    $wrapper = [System.Windows.Controls.Border]::new()
                    $wrapper.Tag = $name
                    $wrapper.Width = 48
                    $wrapper.Height = 48
                    $wrapper.Margin = [System.Windows.Thickness]::new(0,0,0,6)
                    $button = [System.Windows.Controls.Button]::new()
                    $button.Name = $name
                    $button.Width = 48
                    $button.Height = 48
                    $wrapper.Child = $button
                    [void]$host.Children.Add($wrapper)
                }

                $window = [System.Windows.Window]::new()
                $window.Width = 80
                $window.Height = 280
                $window.WindowStyle = [System.Windows.WindowStyle]::None
                $window.ShowInTaskbar = $false
                $window.Content = $host
                $window.Show()
                $window.UpdateLayout()

                $resolvedChild = Resolve-QOTRailIconHostChild -Host $host -Element $host.Children[2].Child
                $dragTarget = Get-QOTRailDragTargetAtPoint -Host $host -SourceName "BtnNavTickets" -Point ([System.Windows.Point]::new(10, 5))

                $resolvedChild | Should Not Be $null
                ([string]$resolvedChild.Tag) | Should Be "BtnNavAdvanced"
                $dragTarget | Should Not Be $null
                ([string]$dragTarget.TargetName) | Should Be "BtnNavCleaning"
                ([string]$dragTarget.Placement) | Should Be "Before"
            }
            finally {
                if ($window) {
                    try { $window.Close() } catch { }
                }
            }
        }
    }

    It "moves rail items before, after, and to the end" {
        InModuleScope $uiModule.Name {
            $baseOrder = @("BtnNavCleaning","BtnNavApps","BtnNavAdvanced","BtnNavTickets")

            $beforeOrder = @(Move-QOTRailIconOrder -Order $baseOrder -SourceName "BtnNavTickets" -TargetName "BtnNavApps" -Placement "Before")
            $afterOrder = @(Move-QOTRailIconOrder -Order $baseOrder -SourceName "BtnNavCleaning" -TargetName "BtnNavAdvanced" -Placement "After")
            $endOrder = @(Move-QOTRailIconOrder -Order $baseOrder -SourceName "BtnNavApps" -Placement "End")

            ($beforeOrder -join ",") | Should Be "BtnNavCleaning,BtnNavTickets,BtnNavApps,BtnNavAdvanced"
            ($afterOrder -join ",") | Should Be "BtnNavApps,BtnNavAdvanced,BtnNavCleaning,BtnNavTickets"
            ($endOrder -join ",") | Should Be "BtnNavCleaning,BtnNavAdvanced,BtnNavTickets,BtnNavApps"
        }
    }

    It "can move the Tickets icon to the top and then to the bottom" {
        InModuleScope $uiModule.Name {
            $baseOrder = @("BtnNavCleaning","BtnNavApps","BtnNavAdvanced","BtnNavTickets","BtnPlay")

            $ticketsTop = @(Move-QOTRailIconOrder -Order $baseOrder -SourceName "BtnNavTickets" -TargetName "BtnNavCleaning" -Placement "Before")
            $ticketsBottom = @(Move-QOTRailIconOrder -Order $ticketsTop -SourceName "BtnNavTickets" -Placement "End")

            ($ticketsTop -join ",") | Should Be "BtnNavTickets,BtnNavCleaning,BtnNavApps,BtnNavAdvanced,BtnPlay"
            ($ticketsBottom -join ",") | Should Be "BtnNavCleaning,BtnNavApps,BtnNavAdvanced,BtnPlay,BtnNavTickets"
        }
    }

    It "persists and restores saved rail order in UiState" {
        InModuleScope $uiModule.Name {
            $script:TestRailSettings = [pscustomobject]@{
                UiState = [pscustomobject]@{}
            }

            function Get-QOSettings { return $script:TestRailSettings }
            function Save-QOSettings { param($Settings) $script:TestRailSettings = $Settings }

            try {
                Save-QOTRailIconOrder -Order @("BtnHelp","BtnSettings","BtnPlay")
                $savedOrder = @(Get-QOTSavedRailIconOrder)

                ($savedOrder[0..2] -join ",") | Should Be "BtnHelp,BtnSettings,BtnPlay"
                ($savedOrder -contains "BtnNavCleaning") | Should Be $true
                ($savedOrder -contains "CbQuickSafeCleanup") | Should Be $true
            }
            finally {
                Remove-Item Function:\Get-QOSettings -ErrorAction SilentlyContinue
                Remove-Item Function:\Save-QOSettings -ErrorAction SilentlyContinue
                Remove-Variable -Name TestRailSettings -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }

    It "keeps the Tickets submenu open for ticket actions and closes it only when leaving Tickets" {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop

        $window = $null
        try {
            Import-Module $enginePath -Force -ErrorAction Stop | Out-Null
            $window = Start-QOTMain -RootPath $repoRoot -WarmupOnly -PassThru
            if (-not $window) { throw "Start-QOTMain did not return a window." }

            $window.Show()
            $window.UpdateLayout()

            $tabs = $window.FindName("MainTabControl")
            if (-not $tabs) { throw "MainTabControl was not found." }

            $cases = @(
                @{ Button = "BtnNavCleaning"; ExpectedTab = "TabCleaning" },
                @{ Button = "BtnNavApps"; ExpectedTab = "TabApps" },
                @{ Button = "BtnNavAdvanced"; ExpectedTab = "TabAdvanced" },
                @{ Button = "BtnNavTickets"; ExpectedTab = "TabTickets" }
            )

            foreach ($case in $cases) {
                $button = $window.FindName($case.Button)
                $button | Should Not Be $null

                $button.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $window.UpdateLayout()

                $tabs.SelectedItem.Name | Should Be $case.ExpectedTab
            }

            $ticketsButton = $window.FindName("BtnNavTickets")
            $appsButton = $window.FindName("BtnNavApps")
            $submenu = $window.FindName("TicketsRailSubmenu")
            $backProxy = $window.FindName("BtnRailTicketBack")
            $newProxy = $window.FindName("BtnRailTicketNew")
            $deleteProxy = $window.FindName("BtnRailTicketDelete")
            $filterProxy = $window.FindName("BtnRailTicketFilter")
            $legacyFilterButton = $window.FindName("BtnTicketsFilterMenu")

            $ticketsButton | Should Not Be $null
            $appsButton | Should Not Be $null
            $submenu | Should Not Be $null
            $backProxy | Should Not Be $null
            $newProxy | Should Not Be $null
            $deleteProxy | Should Not Be $null
            $filterProxy | Should Not Be $null
            $legacyFilterButton | Should Not Be $null

            $appsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $window.UpdateLayout()
            $submenu.Visibility.ToString() | Should Be "Collapsed"

            $ticketsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $window.UpdateLayout()
            $submenu.Visibility.ToString() | Should Be "Visible"

            foreach ($proxyButtonName in @("BtnRailTicketBack","BtnRailTicketNew","BtnRailTicketDelete")) {
                $proxyButton = $window.FindName($proxyButtonName)
                $proxyButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $window.UpdateLayout()
                $tabs.SelectedItem.Name | Should Be "TabTickets"
                $submenu.Visibility.ToString() | Should Be "Visible"
            }

            $filterProxy.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $window.UpdateLayout()
            $tabs.SelectedItem.Name | Should Be "TabTickets"
            $submenu.Visibility.ToString() | Should Be "Visible"
            $legacyFilterButton.ContextMenu | Should Not Be $null
            [bool]$legacyFilterButton.ContextMenu.IsOpen | Should Be $true
            $legacyFilterButton.ContextMenu.PlacementTarget.Name | Should Be "BtnRailTicketFilter"

            $appsButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $window.UpdateLayout()
            $submenu.Visibility.ToString() | Should Be "Collapsed"
        }
        finally {
            if ($window) {
                try { $window.Close() } catch { }
            }
        }
    }

    It "does not define the old rail reorder popup" {
        $xaml = Get-Content -LiteralPath $xamlPath -Raw

        ($xaml -match 'x:Name="RailReorderPopup"') | Should Be $false
    }
}
