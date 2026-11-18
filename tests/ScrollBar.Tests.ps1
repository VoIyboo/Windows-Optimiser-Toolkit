# Run in Windows PowerShell 5.1 with -STA.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, UIAutomationProvider

function Assert([bool]$Condition, [string]$Description) {
    if (!$Condition) { throw $Description }
    Write-Host "PASS $Description"
}

function Get-VisualChildrenOfType($Visual, [type]$Type) {
    if ($Visual -is $Type) { return $Visual }
    for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Visual); $i++) {
        Get-VisualChildrenOfType ([Windows.Media.VisualTreeHelper]::GetChild($Visual, $i)) $Type
    }
}

function Invoke-Button($Button) {
    $peer = [Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($Button)
    $invoke = $peer.GetPattern([Windows.Automation.Peers.PatternInterface]::Invoke)
    ([Windows.Automation.Provider.IInvokeProvider]$invoke).Invoke()
    $Button.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
}

$window = [Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="240" Height="240" Left="-10000" Top="-10000" WindowStartupLocation="Manual"
        ShowInTaskbar="False" ShowActivated="False" Opacity="0">
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <Border Height="1600" />
    </ScrollViewer>
</Window>
'@)
$repo = Split-Path $PSScriptRoot -Parent
$themePath = Join-Path $repo 'src/UI/Themes/SharedTheme.xaml'
$theme = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText($themePath))
$window.Resources.MergedDictionaries.Add($theme)
try {
    $window.Show()
    $window.UpdateLayout()
    $viewer = $window.Content
    $bar = $viewer.Template.FindName('PART_VerticalScrollBar', $viewer)
    Assert ($viewer.ScrollableHeight -gt 0 -and $bar.Template -eq $theme['QOTVerticalScrollBarTemplate']) 'Overflow uses the Quinn vertical scrollbar'

    $buttons = @(Get-VisualChildrenOfType $bar ([Windows.Controls.Primitives.RepeatButton]))
    $up = $buttons | Where-Object Command -eq ([Windows.Controls.Primitives.ScrollBar]::LineUpCommand)
    $down = $buttons | Where-Object Command -eq ([Windows.Controls.Primitives.ScrollBar]::LineDownCommand)
    Assert ($null -ne $up -and $null -ne $down) 'Both line arrow buttons exist'
    $track = $bar.Track
    $origin = [Windows.Point]::new(0, 0)
    $trackY = $track.TranslatePoint($origin, $bar).Y
    $upY = $up.TranslatePoint($origin, $bar).Y
    $downY = $down.TranslatePoint($origin, $bar).Y
    Assert ([math]::Abs($bar.ActualHeight - $viewer.ViewportHeight) -le 1) 'Vertical scrollbar spans the viewport'
    Assert ($upY -le 1 -and $upY + $up.ActualHeight -le $trackY) 'Up arrow sits at the top above the track'
    Assert ($downY -ge $trackY + $track.ActualHeight -and $downY + $down.ActualHeight -ge $bar.ActualHeight - 1) 'Down arrow sits at the bottom below the track'

    $viewer.ScrollToVerticalOffset(100)
    $window.UpdateLayout()
    foreach ($arrow in @($up, $down)) {
        $glyph = Get-VisualChildrenOfType $arrow ([Windows.Shapes.Path])
        Assert ($glyph.IsVisible -and $glyph.ActualWidth -gt 0 -and !$glyph.Data.IsEmpty()) "$($arrow.Command.Name) has a visible arrow glyph"
        $center = [Windows.Point]::new($arrow.ActualWidth / 2, $arrow.ActualHeight / 2)
        $hit = $viewer.InputHitTest($arrow.TranslatePoint($center, $viewer))
        Assert ($hit -eq $arrow -or $arrow.IsAncestorOf($hit)) "$($arrow.Command.Name) receives pointer hits"
    }
    $viewer.ScrollToTop()
    $window.UpdateLayout()

    Invoke-Button $down
    $line = $viewer.VerticalOffset
    Assert ($line -gt 0 -and $line -lt $viewer.ViewportHeight) 'Down arrow scrolls by less than a page'
    Invoke-Button $up
    Assert ($viewer.VerticalOffset -eq 0) 'Up arrow returns to the top'
    if ($up.IsEnabled) { Invoke-Button $up }
    Assert ($viewer.VerticalOffset -eq 0) 'Up arrow stops at the top'

    Invoke-Button $track.IncreaseRepeatButton
    Assert ($viewer.VerticalOffset -gt $line) 'Lower track scrolls down by a page'
    Invoke-Button $track.DecreaseRepeatButton
    Assert ($viewer.VerticalOffset -eq 0) 'Upper track scrolls back to the top'
    $thumb = $track.Thumb
    Assert ($thumb.ActualWidth -gt 0 -and $thumb.ActualWidth -le $bar.ActualWidth) 'Thumb fits inside the narrow scrollbar'
    $thumb.RaiseEvent([Windows.Controls.Primitives.DragStartedEventArgs]::new(0, 0))
    $thumb.RaiseEvent([Windows.Controls.Primitives.DragDeltaEventArgs]::new(0, 8))
    $thumb.RaiseEvent([Windows.Controls.Primitives.DragCompletedEventArgs]::new(0, 8, $false))
    $window.UpdateLayout()
    Assert ($thumb.ActualHeight -gt 0 -and $thumb.IsHitTestVisible -and $viewer.VerticalOffset -gt 0) 'Dragging the thumb scrolls the viewer'

    $viewer.ScrollToBottom()
    $window.UpdateLayout()
    Assert ($viewer.VerticalOffset -eq $viewer.ScrollableHeight) 'Viewer reaches the bottom'
    if ($down.IsEnabled) { Invoke-Button $down }
    Assert ($viewer.VerticalOffset -eq $viewer.ScrollableHeight) 'Down arrow stops at the bottom'
    Invoke-Button $up
    Assert ($viewer.VerticalOffset -eq $viewer.ScrollableHeight - $line) 'Up arrow scrolls one line from the bottom'
} finally {
    $window.Close()
}
