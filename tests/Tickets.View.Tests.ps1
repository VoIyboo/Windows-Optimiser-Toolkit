# Exercise the shipped ticket view and filter/refresh code against a disposable store.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$base = [IO.Path]::GetTempPath().TrimEnd('\')
$fixture = Join-Path $base ('QotTicketView-' + [guid]::NewGuid().ToString('N'))
$repo = Split-Path $PSScriptRoot -Parent
$failures = [Collections.Generic.List[string]]::new()
function Check([bool]$Passed, [string]$Label) {
    if ($Passed) { Write-Host "PASS $Label" } else { Write-Host "FAIL $Label"; $failures.Add($Label) }
}
function Find-TicketTitle($Element) {
    if ($Element -is [Windows.Controls.TextBlock] -and $Element.Tag -eq 'TicketTitleText') { return $Element }
    for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Element); $i++) {
        $title = Find-TicketTitle ([Windows.Media.VisualTreeHelper]::GetChild($Element, $i))
        if ($title) { return $title }
    }
}
try {
    $core = [IO.Directory]::CreateDirectory((Join-Path $fixture 'src/Core')).FullName
    $tickets = [IO.Directory]::CreateDirectory((Join-Path $fixture 'src/Tickets')).FullName
    $null = [IO.Directory]::CreateDirectory((Join-Path $core 'Logging'))
    Copy-Item -LiteralPath (Join-Path $repo 'src/Tickets/Tickets.UI.psm1') -Destination $tickets
    Copy-Item -LiteralPath (Join-Path $repo 'src/Core/QOTImportHelper.ps1') -Destination $core
    Set-Content (Join-Path $core 'Settings.psm1') '# Settings are unnecessary for this view.'
    Set-Content (Join-Path $core 'Logging/Logging.psm1') 'function Write-QLog { param($Message,$Level) }'
    Set-Content (Join-Path $core 'Tickets.psm1') @'
function Get-QOTicketsStorePath { Join-Path $PSScriptRoot 'rows.json' }
function Get-QOTickets {
    $path = Get-QOTicketsStorePath
    $snapshot = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (Test-Path -LiteralPath ($path + '.incoming')) {
        [IO.File]::Copy(($path + '.incoming'),$path,$true)
        [IO.File]::Delete($path + '.incoming')
    }
    $snapshot
}
'@
    $ui = Import-Module (Join-Path $tickets 'Tickets.UI.psm1') -PassThru -DisableNameChecking
    $window = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $repo 'src/UI/MainWindow.xaml')))
    $window.Width = 1000
    $window.Height = 650
    $window.WindowStartupLocation = 'Manual'
    $window.Top = $window.Left = -32000
    $window.ShowActivated = $window.ShowInTaskbar = $false
    $window.FindName('MainTabControl').SelectedItem = $window.FindName('TabTickets')
    $grid = $window.FindName('TicketsGrid')
    $empty = $window.FindName('TicketsEmptyText')
    $details = $window.FindName('TicketDetailsPanel')
    & $ui {
        param($window,$grid,$details)
        $script:TicketsWindow = $window
        $script:TicketsGrid = $grid
        $script:TicketsDetailsPanel = $details
    } $window $grid $details
    $window.Show()
    $clock = [datetime]::UtcNow
    function Refresh-Store([object[]]$Rows) {
        $file = Get-QOTicketsStorePath
        [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject @{ Tickets = $Rows }))
        $script:clock = $script:clock.AddSeconds(1)
        [IO.File]::SetLastWriteTimeUtc($file, $script:clock)
        & $ui { param($g) $null = Invoke-QOTicketsGridRefresh -Grid $g -GetTicketsCmd (Get-Command Get-QOTickets) } $grid
        $window.UpdateLayout()
    }
    Refresh-Store @()
    Check ($grid.IsVisible -and $empty -and $empty.IsVisible -and $empty.Text -match 'New ticket') 'Empty queue explains how to create a ticket'
    $common = @{ Subject='Laptop request'; CreatedAt='2026-03-01T10:00:00'; IsDeleted=$false }
    $first = [pscustomobject]($common + @{ Id='first'; Priority='High'; Status='New'; AssignedTo='' })
    $second = [pscustomobject]($common + @{ Id='second'; Priority='Low'; Status='New'; AssignedTo='Kim' })
    Refresh-Store @($first,$second)
    $row = $grid.ItemContainerGenerator.ContainerFromIndex(0)
    $title = if ($row) { Find-TicketTitle $row }
    Check ($grid.Items.Count -eq 2 -and $title.Text -eq $first.Subject -and $title.ActualWidth -gt 0 -and !$empty.IsVisible) 'Ticket cards show the subject at 1000 by 650'
    [IO.File]::WriteAllText((Get-QOTicketsStorePath), '{')
    & $ui { $null = Invoke-QOTicketsGridRefresh -Grid $script:TicketsGrid -GetTicketsCmd (Get-Command Get-QOTickets) }
    $window.UpdateLayout()
    $errorPanel = $window.FindName('TicketsStartupErrorPanel')
    Check ($errorPanel.IsVisible -and $grid.Items.Count -eq 2 -and !$empty.IsVisible) 'A store read failure shows an inline error and retains the last loaded rows'
    Refresh-Store @($first,$second)
    Check (!$errorPanel.IsVisible -and $grid.Items.Count -eq 2) 'A successful reload clears the store error'

    $grid.SelectedItems.Add($grid.Items[0]) | Out-Null
    $grid.SelectedItems.Add($grid.Items[1]) | Out-Null
    Refresh-Store @($first,$second)
    Check ($grid.SelectedItems.Count -eq 2) 'Background refresh preserves the complete multi-selection'
    $grid.SelectedItems.Clear()
    & $ui { $script:TicketsAssigneeFilter = 'Missing'; Apply-TicketsFilter }
    $window.UpdateLayout()
    Check ($grid.Items.Count -eq 0 -and $empty.IsVisible -and $empty.Text -match 'filter') 'A filtered-out queue identifies the active filters'
    & $ui { $script:TicketsAssigneeFilter = 'Unassigned'; Apply-TicketsFilter }
    Check ($grid.Items.Count -eq 1 -and $grid.Items[0].Id -eq 'first') 'Unassigned filter includes legacy tickets with a blank assignee'
    & $ui {
        param($row)
        $null = Merge-QOTicketsIntoGridCollection -Grid $script:TicketsGrid -IncomingTickets @($row) -SkipFilterRefresh
    } ([pscustomobject]($common + @{ Id='streamed'; Priority='Low'; Status='New'; AssignedTo='Kim' }))
    Check ($grid.Items.Count -eq 1) 'Incoming tickets respect the assignee filter before the next refresh'
    & $ui { $script:TicketsAssigneeFilter = 'All'; Apply-TicketsFilter }
    $grid.SelectedItem = $grid.Items[0]
    $grid.CurrentItem = $grid.SelectedItem
    & $ui { $script:TicketsActiveTicketId='first'; Set-QOTicketDetailsVisibility -DetailsPanel $script:TicketsDetailsPanel -IsOpen:$true }
    Refresh-Store @($second)
    Check ($null -eq $grid.SelectedItem -and $grid.IsVisible -and !$details.IsVisible) 'Removing the open ticket closes details without selecting a same-subject ticket'
    Refresh-Store @()
    Check ($grid.Items.Count -eq 0 -and $empty.IsVisible -and $empty.Text -match 'New ticket') 'Refreshing after the last removal clears old rows'
    $incoming = (Get-QOTicketsStorePath) + '.incoming'
    [IO.File]::WriteAllText($incoming, (ConvertTo-Json -InputObject @{ Tickets = @($second) }))
    [IO.File]::SetLastWriteTimeUtc($incoming, $clock.AddMinutes(1))
    Refresh-Store @($first)
    & $ui { $null = Invoke-QOTicketsGridRefresh -Grid $script:TicketsGrid -GetTicketsCmd (Get-Command Get-QOTickets) }
    Check ($grid.Items.Count -eq 1 -and $grid.Items[0].Id -eq 'second') 'A concurrent store change between reading and rendering is picked up on the next refresh'
    if ($failures.Count) { throw ($failures -join [Environment]::NewLine) }
} finally {
    if ($window) { $window.Close() }
    if (Test-Path -LiteralPath $fixture) {
        $exact = (Resolve-Path -LiteralPath $fixture).Path
        if ((Split-Path $exact -Parent) -eq $base -and (Split-Path $exact -Leaf) -match '^QotTicketView-[a-f0-9]{32}$') {
            Remove-Item -LiteralPath $exact -Force -Recurse
        }
    }
}
