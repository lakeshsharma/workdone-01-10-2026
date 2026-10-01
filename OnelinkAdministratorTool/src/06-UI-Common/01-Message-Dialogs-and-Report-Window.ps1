# ----------------------------------------------------------------------------
#  UI helpers
# ----------------------------------------------------------------------------

function Show-ErrorMessage {
    param([string]$Message)
    Write-OneLinkLog $Message -Level Error
    [System.Windows.MessageBox]::Show($Message, $script:AppName, 'OK', 'Error') | Out-Null
}

function Show-InfoMessage {
    param([string]$Message)
    [System.Windows.MessageBox]::Show($Message, $script:AppName, 'OK', 'Information') | Out-Null
}

function Show-WarningMessage {
    param([string]$Message)
    Write-OneLinkLog $Message -Level Warning
    [System.Windows.MessageBox]::Show($Message, $script:AppName, 'OK', 'Warning') | Out-Null
}

# A clean, professional report window (navy title bar + monospaced, scrollable
# body so columns line up) used for status / version / certificate reports.
# A helper: a modern gradient (blue -> violet) brush matching the app header.
function New-OneLinkHeaderBrush {
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.StartPoint = New-Object System.Windows.Point(0, 0)
    $g.EndPoint = New-Object System.Windows.Point(1, 0)
    [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString('#2563EB'), 0)))
    [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString('#4F46E5'), 0.55)))
    [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString('#7C3AED'), 1)))
    $g.Freeze(); return $g
}

# Grab a style from the main window's resources (so popup buttons match the app).
function Get-OneLinkStyle { param([string]$Key) try { return $script:Window.FindResource($Key) } catch { return $null } }

function Show-OneLinkReport {
    param([string]$Title, [string]$Body)
    $win = New-Object System.Windows.Window
    $win.Title = $Title
    # Compact: size the window to the content, capped so it never gets huge.
    $lines = @($Body -split "`r?`n")
    $maxLine = ($lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    if (-not $maxLine) { $maxLine = 40 }
    $win.Width = [Math]::Min(940, [Math]::Max(420, 70 + $maxLine * 7.4))
    $win.Height = [Math]::Min(640, [Math]::Max(200, 120 + $lines.Count * 17.5))
    $win.MinWidth = 380; $win.MinHeight = 180
    $win.WindowStartupLocation = 'CenterScreen'
    $win.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F5F7FB'))
    if ($script:Window) { $win.Owner = $script:Window }

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($h in @('Auto', '*', 'Auto')) {
        $rd = New-Object System.Windows.Controls.RowDefinition
        $rd.Height = [System.Windows.GridLength]::new(1, $(if ($h -eq '*') { 'Star' } else { 'Auto' }))
        [void]$grid.RowDefinitions.Add($rd)
    }

    $hdr = New-Object System.Windows.Controls.Border
    $hdr.Background = New-OneLinkHeaderBrush
    $hdr.Padding = '16,11'
    $htxt = New-Object System.Windows.Controls.TextBlock
    $htxt.Text = $Title; $htxt.Foreground = [System.Windows.Media.Brushes]::White; $htxt.FontSize = 15; $htxt.FontWeight = 'Bold'
    $hdr.Child = $htxt
    [System.Windows.Controls.Grid]::SetRow($hdr, 0); [void]$grid.Children.Add($hdr)

    $card = New-Object System.Windows.Controls.Border
    $card.Background = [System.Windows.Media.Brushes]::White
    $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E2E8F0'))
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $card.Margin = '12,12,12,6'
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $Body; $tb.IsReadOnly = $true; $tb.AcceptsReturn = $true
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas, Courier New, monospace')
    $tb.FontSize = 13; $tb.TextWrapping = 'NoWrap'
    $tb.VerticalScrollBarVisibility = 'Auto'; $tb.HorizontalScrollBarVisibility = 'Auto'
    $tb.BorderThickness = New-Object System.Windows.Thickness(0)
    $tb.Padding = '14,12'; $tb.Background = [System.Windows.Media.Brushes]::White
    $card.Child = $tb
    [System.Windows.Controls.Grid]::SetRow($card, 1); [void]$grid.Children.Add($card)

    $bp = New-Object System.Windows.Controls.StackPanel
    $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.Margin = '12,4,12,12'
    $primaryStyle = Get-OneLinkStyle 'PrimaryButtonStyle'
    $secondaryStyle = Get-OneLinkStyle 'SecondaryButtonStyle'
    $copy = New-Object System.Windows.Controls.Button
    $copy.Content = 'Copy'; $copy.Width = 90; $copy.Height = 28; $copy.Margin = '0,0,8,0'
    if ($secondaryStyle) { $copy.Style = $secondaryStyle }
    $close = New-Object System.Windows.Controls.Button
    $close.Content = 'Close'; $close.Width = 90; $close.Height = 28; $close.IsDefault = $true; $close.IsCancel = $true
    if ($primaryStyle) { $close.Style = $primaryStyle }
    $copy.Add_Click({ try { [System.Windows.Clipboard]::SetText($Body) } catch { } }.GetNewClosure())
    $close.Add_Click({ $win.Close() }.GetNewClosure())
    [void]$bp.Children.Add($copy); [void]$bp.Children.Add($close)
    [System.Windows.Controls.Grid]::SetRow($bp, 2); [void]$grid.Children.Add($bp)

    $win.Content = $grid
    [void]$win.ShowDialog()
}

# A "loose" key for tolerant file-name matching: lower-cased with spaces and
# bracket/parenthesis characters removed. So "license (3).lic", "license(3).lic"
# and "license 3.lic" all reduce to the same key ("license3.lic"), letting the
# Find feature match a name the user half-remembers.
function ConvertTo-OneLinkLooseKey {
    param([AllowEmptyString()][string]$Value)
    return (([string]$Value).ToLowerInvariant() -replace '[\s()\[\]{}]', '')
}

