# StartupWidget.UI.psm1
# Handles displaying and updating the startup widget window

function New-QOTStartupWidget {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "StartupWidget XAML not found at: $Path"
    }

    # Ensure WPF assemblies are loaded
    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    }
    catch {
        throw "Failed to load WPF assemblies: $_"
    }

    $xamlContent = Get-Content $Path -Raw
    $window = [Windows.Markup.XamlReader]::Parse($xamlContent)

    # Load the Studio Voly fox icon from splash image
    try {
        $logoControl = $window.FindName("QuinnLogo")
        if ($logoControl) {
            $pngPath = Join-Path $PSScriptRoot "..\StudioVolySplash.png"
            if (Test-Path $pngPath) {
                $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $bitmap.BeginInit()
                $bitmap.UriSource = New-Object System.Uri($pngPath, [System.UriKind]::Absolute)
                $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmap.EndInit()
                $bitmap.Freeze()
                $logoControl.Source = $bitmap
            }
        }
    }
    catch { }

    # Wire up button handlers
    try {
        $minimizeBtn = $window.FindName("MinimizeButton")
        if ($minimizeBtn) {
            $minimizeBtn.Add_Click({
                $window.WindowState = [System.Windows.WindowState]::Minimized
            })
        }

        $closeBtn = $window.FindName("CloseButton")
        if ($closeBtn) {
            $closeBtn.Add_Click({
                $window.Close()
            })
        }
    }
    catch {
        # Continue even if button wiring fails
    }

    # Store reference to window for dragging
    $window | Add-Member -NotePropertyName "IsDragging" -NotePropertyValue $false -Force
    $window | Add-Member -NotePropertyName "DragStartPoint" -NotePropertyValue $null -Force

    # Enable dragging on the main Border
    try {
        $border = $window.Child
        if ($border) {
            $border.Add_MouseLeftButtonDown({
                $window.IsDragging = $true
                $window.DragStartPoint = [System.Windows.Input.Mouse]::GetPosition($window)
                [System.Windows.Input.Mouse]::Capture($border)
            })

            $border.Add_MouseLeftButtonUp({
                if ($window.IsDragging) {
                    $window.IsDragging = $false
                    [System.Windows.Input.Mouse]::Capture($null)
                }
            })

            $border.Add_MouseMove({
                if ($window.IsDragging) {
                    $currentPosition = [System.Windows.Input.Mouse]::GetPosition([System.Windows.Application]::Current.MainWindow)
                    $diff = [System.Windows.Point]::new(
                        $currentPosition.X - $window.DragStartPoint.X,
                        $currentPosition.Y - $window.DragStartPoint.Y
                    )

                    $window.Left += $diff.X
                    $window.Top += $diff.Y
                }
            })
        }
    }
    catch {
        # Continue even if dragging setup fails
    }

    return $window
}

function Show-QOTStartupWidget {
    param(
        [object]$Window
    )

    if (-not $Window) { return }

    try {
        # WPF measures the auto-sized window on Show. Keep that first layout
        # transparent until the widget is at its final screen position.
        $Window.Opacity = 0
        $Window.Show()
        $Window.UpdateLayout()
        Move-QOTStartupWidgetToBottomRight -Window $Window
        $Window.Opacity = 1
        $Window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) | Out-Null

        # Auto-disable Topmost after 3 seconds
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(3)
        $timer.Add_Tick({
            param($sender, $eventArgs)
            $sender.Stop()
            $Window.Topmost = $false
        }.GetNewClosure())
        $timer.Start()
    }
    catch {
        Write-Warning "Failed to show startup widget: $_"
    }
}

function Move-QOTStartupWidgetToBottomRight {
    param(
        [object]$Window
    )

    if (-not $Window) { return }

    try {
        $workingArea = [System.Windows.SystemParameters]::WorkArea
        $left = $workingArea.Right - $Window.ActualWidth - 10
        $top = $workingArea.Bottom - $Window.ActualHeight - 10
        $Window.Left = $left
        $Window.Top = $top
    }
    catch {
        Write-Warning "Failed to position startup widget: $_"
    }
}

function Update-QOTWidgetStatus {
    param(
        [object]$Window,
        [string]$Text
    )

    if (-not $Window) { return }

    try {
        $statusText = $Window.FindName("StatusText")
        if ($statusText) {
            $Window.Dispatcher.Invoke({
                $statusText.Text = $Text
            }, [System.Windows.Threading.DispatcherPriority]::Normal)
        }
    }
    catch { }
}

function Update-QOTWidgetProgress {
    param(
        [object]$Window,
        [int]$Value
    )

    if (-not $Window) { return }

    # Clamp value between 0 and 100
    $Value = [Math]::Max(0, [Math]::Min(100, $Value))

    try {
        $progressBar = $Window.FindName("ProgressBar")
        if ($progressBar) {
            $Window.Dispatcher.Invoke({
                $progressBar.Value = $Value
            }, [System.Windows.Threading.DispatcherPriority]::Normal)
        }
    }
    catch { }
}

function Close-QOTStartupWidget {
    param(
        [object]$Window,
        [switch]$Immediate
    )

    if (-not $Window) { return }

    try {
        if ($Immediate) {
            $Window.Close()
        }
        else {
            # Fade out animation without blocking (use background dispatcher)
            try {
                $fadeOutStoryboard = $Window.FindResource("FadeOutAnimation")
                if ($fadeOutStoryboard) {
                    $storyboardCopy = $fadeOutStoryboard.Clone()
                    $storyboardCopy.Add_Completed({
                        param($sender, $args)
                        try { $Window.Close() } catch { }
                    }.GetNewClosure())
                    $storyboardCopy.Begin($Window)
                }
                else {
                    $Window.Close()
                }
            }
            catch {
                # If animation fails, close immediately
                $Window.Close()
            }
        }
    }
    catch { }
}

Export-ModuleMember -Function `
    New-QOTStartupWidget, `
    Show-QOTStartupWidget, `
    Move-QOTStartupWidgetToBottomRight, `
    Update-QOTWidgetStatus, `
    Update-QOTWidgetProgress, `
    Close-QOTStartupWidget
