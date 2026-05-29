# Quinn Startup Widget

A minimal, lightweight WPF widget that replaces the intrusive splash screen during application startup. The widget appears in the bottom-right corner and auto-closes when the main application is ready.

## Features

- **Non-intrusive positioning**: Bottom-right corner, above system tray
- **Determinate progress**: Progress bar + status text updates
- **Lightweight animations**: Fade-in/fade-out with minimal GPU overhead
- **User controls**: Minimize and close buttons
- **Draggable**: Click and drag to reposition the widget
- **Smart Z-order**: Initially `Topmost`, auto-disables after 3 seconds to not interfere with other apps
- **Non-blocking**: Doesn't steal focus from active applications

## Files

- `StartupWidget.xaml` - UI definition
- `StartupWidget.UI.psm1` - PowerShell module for widget management
- `quinn-logo.png` - Small icon (40x40px, placeholder)

## Integration

### 1. Import the Module

```powershell
Import-Module "$PSScriptRoot\StartupWidget\StartupWidget.UI.psm1"
```

### 2. Create and Show the Widget

```powershell
$xamlPath = Join-Path $PSScriptRoot "StartupWidget\StartupWidget.xaml"
$widget = New-QOTStartupWidget -Path $xamlPath
Show-QOTStartupWidget -Window $widget
```

### 3. Update Progress During Initialization

```powershell
# Update status
Update-QOTWidgetStatus -Window $widget -Text "Loading modules..."

# Update progress (0-100)
Update-QOTWidgetProgress -Window $widget -Value 25

# Simulate work
Start-Sleep -Milliseconds 500

Update-QOTWidgetStatus -Window $widget -Text "Initializing UI..."
Update-QOTWidgetProgress -Window $widget -Value 75
```

### 4. Close Widget When Ready

```powershell
# Close with fade-out animation (default)
Close-QOTStartupWidget -Window $widget

# Or close immediately (no animation)
Close-QOTStartupWidget -Window $widget -Immediate
```

## API Reference

### New-QOTStartupWidget

Creates a new startup widget instance from XAML.

```powershell
$widget = New-QOTStartupWidget -Path "path/to/StartupWidget.xaml"
```

**Parameters:**
- `Path` (string, required): Path to StartupWidget.xaml

**Returns:** WPF Window object

---

### Show-QOTStartupWidget

Shows the widget with fade-in animation and positions it in the bottom-right corner.

```powershell
Show-QOTStartupWidget -Window $widget
```

**Parameters:**
- `Window` (object, required): Widget instance from New-QOTStartupWidget

---

### Update-QOTWidgetStatus

Updates the status text displayed in the widget.

```powershell
Update-QOTWidgetStatus -Window $widget -Text "Loading modules..."
```

**Parameters:**
- `Window` (object, required): Widget instance
- `Text` (string, required): Status message to display

---

### Update-QOTWidgetProgress

Updates the progress bar value (0-100).

```powershell
Update-QOTWidgetProgress -Window $widget -Value 45
```

**Parameters:**
- `Window` (object, required): Widget instance
- `Value` (int, required): Progress value (0-100, clamped automatically)

---

### Close-QOTStartupWidget

Closes the widget with optional fade-out animation.

```powershell
Close-QOTStartupWidget -Window $widget
Close-QOTStartupWidget -Window $widget -Immediate
```

**Parameters:**
- `Window` (object, required): Widget instance
- `Immediate` (switch, optional): If set, closes immediately without fade-out animation

---

### Move-QOTStartupWidgetToBottomRight

Manually repositions the widget to the bottom-right corner (called automatically by Show-QOTStartupWidget).

```powershell
Move-QOTStartupWidgetToBottomRight -Window $widget
```

**Parameters:**
- `Window` (object, required): Widget instance

---

## Example: Full Integration

```powershell
# Import module
Import-Module "$PSScriptRoot\StartupWidget\StartupWidget.UI.psm1"

# Create widget
$xamlPath = Join-Path $PSScriptRoot "StartupWidget\StartupWidget.xaml"
$widget = New-QOTStartupWidget -Path $xamlPath
Show-QOTStartupWidget -Window $widget

# Simulate initialization phases
$phases = @(
    @{ Text = "Loading modules..."; Value = 10 },
    @{ Text = "Initializing database..."; Value = 30 },
    @{ Text = "Building UI..."; Value = 60 },
    @{ Text = "Loading settings..."; Value = 85 },
    @{ Text = "Ready!"; Value = 100 }
)

foreach ($phase in $phases) {
    Update-QOTWidgetStatus -Window $widget -Text $phase.Text
    Update-QOTWidgetProgress -Window $widget -Value $phase.Value
    Start-Sleep -Milliseconds 600
}

# Close widget when main app is ready
Close-QOTStartupWidget -Window $widget
```

## Design Details

### Window Properties

- **WindowStyle**: `None` (borderless)
- **AllowsTransparency**: `True` (for rounded corners)
- **Topmost**: `True` initially, auto-disabled after 3 seconds
- **ShowInTaskbar**: `False` (doesn't clutter taskbar)
- **ShowActivated**: `False` (doesn't steal focus)

### UI Layout

```
┌──────────────────────────────────┐
│ [Logo] Status Text               │
│ [========================>] 45%  │
│                          [−] [×] │
└──────────────────────────────────┘
```

### Animations

- **Fade-in**: 0.2s linear, opacity 0 → 1
- **Fade-out**: 0.3s linear, opacity 1 → 0
- **Dragging**: Real-time position updates

### Color Scheme

- **Background**: `#F5F5F5` (light gray)
- **Border**: `#E0E0E0` (subtle)
- **Progress**: `#0066CC` (Quinn blue)
- **Text**: `#333333` (dark gray)

---

## Notes

- Widget is **self-contained** and reusable in other projects
- **No external dependencies** beyond WPF/NET Framework
- **Thread-safe**: Uses `Dispatcher.Invoke` for cross-thread updates
- **Low overhead**: Minimal animations and effects for fast startup
- **Customizable**: Easily modify XAML for different colors, sizes, or layout
