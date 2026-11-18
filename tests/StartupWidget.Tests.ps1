$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Intro/StartupWidget/StartupWidget.UI.psm1') -DisableNameChecking
# A window stand-in supplies WPF measurements without activating the user's desktop.
$widget = [pscustomobject]@{Width=300;Height=[double]::NaN;ActualWidth=300;ActualHeight=202;Top=0;Left=0;Opacity=0;Topmost=$true;TookFocus=$false;OpacityAtShow=-1;Dispatcher=[Windows.Threading.Dispatcher]::CurrentDispatcher}
$widget | Add-Member ScriptMethod Show { $this.OpacityAtShow = $this.Opacity }
$widget | Add-Member ScriptMethod UpdateLayout { }
foreach ($method in 'Activate','Focus') { Add-Member -InputObject $widget -MemberType ScriptMethod -Name $method -Value { $this.TookFocus = $true } }
Show-QOTStartupWidget -Window $widget
if ($widget.OpacityAtShow -ne 0 -or $widget.Opacity -ne 1) { throw 'Widget appeared before it was positioned at its measured coordinates.' }
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Intro/StartupWidget/StartupWidget.xaml'
$view = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText($source))
if ($widget.TookFocus -or $view.ShowActivated) { throw 'Widget requested keyboard focus during startup.' }
$view.Close()
$expected=[Windows.SystemParameters]::WorkArea.Bottom - $widget.ActualHeight - 10
$clock=[Diagnostics.Stopwatch]::StartNew()
while ($widget.Topmost -and $clock.Elapsed.TotalSeconds -lt 4) {
    $frame = New-Object Windows.Threading.DispatcherFrame
    $null=$widget.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[action]{ $frame.Continue=$false })
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    Start-Sleep -Milliseconds 20
}
if ($widget.Top -ne $expected -or $widget.Topmost) {throw 'Widget positioning or timer failed'}

Write-Host "PASS Startup widget uses its measured size and releases topmost on the UI thread."
