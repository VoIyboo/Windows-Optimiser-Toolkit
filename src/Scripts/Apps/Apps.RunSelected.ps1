param(
    [Parameter(Mandatory)]
    [object]$Window
)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\Apps\Apps.Actions.psm1" -Force -ErrorAction Stop

function Find-QOTControlByNameDeepLocal {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Root -or [string]::IsNullOrWhiteSpace($Name)) { return $null }

    try {
        if ($Root -is [System.Windows.FrameworkElement]) {
            $direct = $Root.FindName($Name)
            if ($direct) { return $direct }
        }
    } catch { }

    $visited = New-Object 'System.Collections.Generic.HashSet[int]'
    $q = New-Object 'System.Collections.Generic.Queue[System.Object]'
    $q.Enqueue($Root) | Out-Null

    while ($q.Count -gt 0) {
        $cur = $q.Dequeue()
        if (-not $cur) { continue }

        $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
        if (-not $visited.Add($objId)) { continue }

        if ($cur -is [System.Windows.FrameworkElement]) {
            if ($cur.Name -eq $Name) { return $cur }
            try {
                $withinScope = $cur.FindName($Name)
                if ($withinScope) { return $withinScope }
            } catch { }
        }

        try {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                if ($child) { $q.Enqueue($child) | Out-Null }
            }
        } catch { }

        if ($cur -is [System.Windows.DependencyObject]) {
            try {
                $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur)
                for ($i = 0; $i -lt $count; $i++) {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                }
            } catch { }
        }
    }

    return $null
}

$appsGrid = Find-QOTControlByNameDeepLocal -Root $Window -Name "AppsGrid"
$installGrid = Find-QOTControlByNameDeepLocal -Root $Window -Name "InstallGrid"

if (-not $appsGrid -or -not $installGrid) {
    throw "Apps grids not available for Apps.RunSelected."
}

Invoke-QOTRunSelectedAppsActions -Window $Window -AppsGrid $appsGrid -InstallGrid $installGrid
