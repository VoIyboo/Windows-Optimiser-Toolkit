# src\UI\HelpWindow.UI.psm1
# Help window UI for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

$script:QOTHelp_AssembliesLoaded = $false

function Initialize-QOTHelpUIAssemblies {
    if ($script:QOTHelp_AssembliesLoaded) { return }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    $script:QOTHelp_AssembliesLoaded = $true
}

function Convert-HelpWindowToHostableRoot {
    param([Parameter(Mandatory)][xml]$Doc)

    $win = $Doc.DocumentElement
    if (-not $win -or $win.LocalName -ne "Window") {
        throw "HelpWindow.xaml root must be <Window>."
    }

    $ns = $win.NamespaceURI
    $grid = $Doc.CreateElement("Grid", $ns)

    $removeAttrs = @(
        "Title", "Height", "Width", "Topmost", "WindowStartupLocation",
        "ResizeMode", "SizeToContent", "ShowInTaskbar", "WindowStyle", "AllowsTransparency"
    )

    foreach ($a in @($win.Attributes)) {
        if ($removeAttrs -contains $a.Name) { continue }
        $null = $grid.Attributes.Append($a.Clone())
    }

    foreach ($child in @($win.ChildNodes)) {
        if ($child.NodeType -ne "Element") { continue }

        if ($child.LocalName -eq "Window.Resources") {
            $newRes = $Doc.CreateElement("Grid.Resources", $ns)
            foreach ($rChild in @($child.ChildNodes)) {
                $null = $newRes.AppendChild($rChild.Clone())
            }
            $null = $grid.AppendChild($newRes)
        }
        else {
            $null = $grid.AppendChild($child.Clone())
        }
    }

    $null = $Doc.RemoveChild($win)
    $null = $Doc.AppendChild($grid)

    return $Doc
}

function Get-QOTHelpSections {
    return @(
        [pscustomobject]@{
            Title = "Welcome to Quinn Optimiser Toolkit"
            Body  = "This tool is designed to help you work quickly without guesswork. Pick what you need, run it once, and review outcomes in Logs. If something does not look right, stop and review before continuing."
        }
        [pscustomobject]@{
            Title = "How to run tasks safely"
            Body  = "Choose actions in Tweaks & Cleaning, Apps, or Advanced, then press Play once. Play runs selected tasks in the background so the app stays responsive. Use Stop if you need to pause new work."
        }
        [pscustomobject]@{
            Title = "Risk colours at a glance"
            Body  = "Green means safe change, Orange means some technical skill needed, and Red means admin-level change with higher impact. Review orange/red items before running in production."
        }
        [pscustomobject]@{
            Title = "Logs and results"
            Body  = "Open Logs after a run to see Worked, Skipped, and Failed actions in plain language. This is the best place to confirm what happened and what needs follow-up."
        }
        [pscustomobject]@{
            Title = "Ticket workflow basics"
            Body  = "Use Tickets to manage email-based work. Open a ticket, read the thread, add an internal note, or reply to the customer. Keep status and assignee current so everyone knows what is in progress."
        }
        [pscustomobject]@{
            Title = "Internal notes vs customer replies"
            Body  = "Use Add internal note for team-only updates. Use Reply to customer for outbound email. Notes and replies are appended to the ticket timeline to keep full context in one place."
        }
        [pscustomobject]@{
            Title = "Right-click actions in Tickets"
            Body  = "Right-click a ticket to change Status, Assignee, Priority, or Title. You can also apply updates to multiple selected tickets to speed up bulk triage."
        }
        [pscustomobject]@{
            Title = "Filtering and sorting tickets"
            Body  = "Use the filter menu to show Open, Closed, or Deleted tickets and sort by Priority, Newest, or Oldest. Your selected view is saved so it opens the same way next time."
        }
        [pscustomobject]@{
            Title = "Outlook sync and reply requirements"
            Body  = "Ticket sync uses Classic Outlook desktop COM (not New Outlook). If sync or reply fails, open Classic Outlook first and retry. Keep toolkit and Outlook at the same permission level (both normal user is best)."
        }
        [pscustomobject]@{
            Title = "Settings that apply immediately"
            Body  = "Visible tabs update live while the app is running. Settings also controls monitored mailbox addresses, email sync start date, and shared ticket storage paths for team collaboration."
        }
        [pscustomobject]@{
            Title = "Dates, time, and desktop shortcut"
            Body  = "Ticket timestamps follow your Windows regional date/time format. You can install a desktop shortcut from Settings to launch Quinn quickly without running a manual PowerShell command each time."
        }
        [pscustomobject]@{
            Title = "If something fails"
            Body  = "You are not stuck. Check Logs first, then retry the specific action. If needed, capture the exact error message and share it with your team so the issue can be fixed quickly."
        }
    )
}

function New-QOTHelpView {
    Initialize-QOTHelpUIAssemblies

    $xamlPath = Join-Path $PSScriptRoot "HelpWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "HelpWindow.xaml not found at $xamlPath"
    }

    [xml]$doc = Get-Content -LiteralPath $xamlPath -Raw
    $doc = Convert-HelpWindowToHostableRoot -Doc $doc

    $reader = New-Object System.Xml.XmlNodeReader($doc)
    $root = [System.Windows.Markup.XamlReader]::Load($reader)
    if (-not $root) { throw "Failed to load HelpWindow.xaml" }

    $themePath = Join-Path $PSScriptRoot "Themes\SharedTheme.xaml"
    if (Test-Path -LiteralPath $themePath) {
        [xml]$themeDoc = Get-Content -LiteralPath $themePath -Raw
        $themeReader = New-Object System.Xml.XmlNodeReader($themeDoc)
        $themeDictionary = [System.Windows.Markup.XamlReader]::Load($themeReader)
        if ($themeDictionary) {
            [void]$root.Resources.MergedDictionaries.Add($themeDictionary)
        }
    }

    $sectionsControl = $root.FindName("HelpSections")
    if ($sectionsControl) {
        $sectionsControl.ItemsSource = (Get-QOTHelpSections)
    }

    return $root
}

Export-ModuleMember -Function New-QOTHelpView
