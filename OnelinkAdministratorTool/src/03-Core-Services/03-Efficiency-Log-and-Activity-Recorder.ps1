# ----------------------------------------------------------------------------
#  Efficiency log: a separate CSV-style log recording each operation's target,
#  start time, end time, duration and outcome. No secrets are written (only the
#  operation name and target host). Used to see how long installs/uploads/etc.
#  take.
# ----------------------------------------------------------------------------
$script:EfficiencyLogFile = $null

function Initialize-OneLinkEfficiencyLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }
    $script:EfficiencyLogFile = Join-Path $Directory ("OneLinkAdminTool_efficiency_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    if (-not (Test-Path -LiteralPath $script:EfficiencyLogFile)) {
        Add-Content -LiteralPath $script:EfficiencyLogFile -Value 'Operation,Target,Outcome,StartTime,EndTime,DurationSeconds' -Encoding UTF8
    }
    return $script:EfficiencyLogFile
}

# Records one operation's timing. $Target is a host or 'all'; never a secret.
function Write-OneLinkEfficiency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Outcome,
        [Parameter(Mandatory)][datetime]$Start,
        [Parameter(Mandatory)][datetime]$End
    )

    $duration = [math]::Round(($End - $Start).TotalSeconds, 2)
    $csvField = {
        param($v)
        $s = [string]$v
        if ($s -match '[",\r\n]') { '"' + ($s -replace '"', '""') + '"' } else { $s }
    }
    $line = @(
        (& $csvField (Protect-LogText -Message $Operation)),
        (& $csvField $Target),
        (& $csvField $Outcome),
        (& $csvField ($Start.ToString('yyyy-MM-dd HH:mm:ss'))),
        (& $csvField ($End.ToString('yyyy-MM-dd HH:mm:ss'))),
        $duration
    ) -join ','

    if ($script:EfficiencyLogFile) {
        Add-Content -LiteralPath $script:EfficiencyLogFile -Value $line -Encoding UTF8
    }
    Write-OneLinkLog ("[timing] {0} on {1}: {2} in {3}s" -f $Operation, $Target, $Outcome, $duration) -Level Debug
}

# ----------------------------------------------------------------------------
#  Activity metrics: how many CLICKS + distinct FIELDS a user task took, and how
#  long (wall-clock) from the previous completed activity to this one. Captured
#  automatically; shown live in the footer and in the Activity Metrics tab.
# ----------------------------------------------------------------------------
$script:ActClicks = 0                 # running window click count (PreviewMouseDown)
$script:ActBoundaryClicks = 0         # click count when the current activity segment began
$script:ActBoundaryTime = Get-Date    # when the current activity segment began
$script:ActTouchedFields = New-Object 'System.Collections.Generic.HashSet[string]'  # distinct fields edited this segment
$script:ActivityMetrics = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$script:MetricsLogFile = $null
$script:ActCaptureEnabled = $false    # toggled by the "Record efficiency metrics" checkbox
# Active-time tracking: only count time while the user is actually working. Any
# gap longer than the idle threshold between interactions is treated as idle and
# is NOT added to the activity's time.
$script:ActActiveSeconds = 0.0
$script:ActLastInteraction = Get-Date
$script:ActIdleThresholdSeconds = 30

# Accumulate active time between interactions (excluding idle gaps). Called on
# every click and field edit while capture is on.
function Register-OneLinkInteraction {
    if (-not $script:ActCaptureEnabled) { return }
    $now = Get-Date
    $gap = ($now - $script:ActLastInteraction).TotalSeconds
    if ($gap -ge 0 -and $gap -le $script:ActIdleThresholdSeconds) { $script:ActActiveSeconds += $gap }
    $script:ActLastInteraction = $now
}

function Initialize-OneLinkMetricsLog {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory)) { New-Item -Path $Directory -ItemType Directory -Force | Out-Null }
    $script:MetricsLogFile = Join-Path $Directory ("OneLinkAdminTool_activity_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    if (-not (Test-Path -LiteralPath $script:MetricsLogFile)) {
        Add-Content -LiteralPath $script:MetricsLogFile -Value 'Time,Activity,Target,Outcome,Clicks,InputsEdited,ActivitySeconds,OperationSeconds' -Encoding UTF8
    }
    return $script:MetricsLogFile
}

# Reset the activity segment (called after each completed activity, so the next
# activity's clicks/fields/time start fresh).
function Reset-OneLinkActivitySegment {
    $script:ActBoundaryClicks = $script:ActClicks
    $script:ActBoundaryTime = Get-Date
    $script:ActTouchedFields.Clear()
    $script:ActActiveSeconds = 0.0
    $script:ActLastInteraction = Get-Date
}

# Record one completed activity: clicks + distinct fields + wall-clock time since
# the previous activity, then reset the segment. Safe to call on the UI thread.
function Complete-OneLinkActivity {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Target = '',
        [string]$Outcome = 'Success',
        [double]$OperationSeconds = 0,
        [hashtable]$Context = $null
    )
    # Only record when the user has switched capture on.
    if (-not $script:ActCaptureEnabled) { return }
    $now = Get-Date
    $clicks = [math]::Max(0, $script:ActClicks - $script:ActBoundaryClicks)
    $inputs = $script:ActTouchedFields.Count
    if ($Context) {
        if ($Context.ContainsKey('Frozen') -and $Context.Frozen -and $Context.Generation -ne $script:ActCaptureGeneration) { return }
        if ($Context.Generation -ne $script:ActCaptureGeneration) { Reset-OneLinkRecorderContext $Context }
        $clicks = $Context.Clicks
        $inputs = $Context.Fields.Count
    }
    # Active (hands-on) time only: form-filling active gaps (idle excluded) plus
    # the operation's own run time. Idle time between activities is NOT counted.
    $actSecs = [math]::Round($script:ActActiveSeconds + $OperationSeconds, 2)
    if ($Context) { $actSecs = [math]::Round($Context.ActiveSeconds + $OperationSeconds, 2) }

    $m = [OlActivityMetric]::new()
    $m.Time = $now.ToString('HH:mm:ss')
    $m.Activity = $Name
    $m.Target = $Target
    $m.Outcome = $Outcome
    $m.Clicks = $clicks
    $m.Inputs = $inputs
    $m.ActivitySeconds = $actSecs
    $m.OperationSeconds = [math]::Round($OperationSeconds, 2)
    $script:ActivityMetrics.Insert(0, $m)   # newest first

    if ($script:MetricsLogFile) {
        $q = { param($v) $s = [string]$v; if ($s -match '[",\r\n]') { '"' + ($s -replace '"', '""') + '"' } else { $s } }
        $line = @((& $q $now.ToString('yyyy-MM-dd HH:mm:ss')), (& $q (Protect-LogText -Message $Name)), (& $q $Target), (& $q $Outcome), $clicks, $inputs, $actSecs, $m.OperationSeconds) -join ','
        Add-Content -LiteralPath $script:MetricsLogFile -Value $line -Encoding UTF8
    }

    Update-OneLinkActivitySummary
    if ($Context) { Reset-OneLinkRecorderContext $Context } else { Reset-OneLinkActivitySegment }
}

# Separate counters for each auxiliary window. Only field identities are stored,
# never typed values, passwords, file contents or command text.
$script:ActCaptureGeneration = 0
function Set-OneLinkRecorderCapture {
    param([bool]$Enabled)
    if ($Enabled -and -not $script:ActCaptureEnabled) { $script:ActCaptureGeneration++; Reset-OneLinkActivitySegment }
    $script:ActCaptureEnabled = $Enabled
}

function Test-OneLinkRecorderCapture { return $script:ActCaptureEnabled }

function Reset-OneLinkRecorderContext {
    param([hashtable]$Context)
    $Context.Clicks = 0
    $Context.Fields = New-Object 'System.Collections.Generic.HashSet[string]'
    $Context.ActiveSeconds = 0.0
    $Context.Last = Get-Date
    $Context.Generation = $script:ActCaptureGeneration
}

function Register-OneLinkRecorderEvent {
    param([hashtable]$Context, [switch]$Click, [string]$Field = '')
    if (-not $script:ActCaptureEnabled) { return }
    if ($Context.Generation -ne $script:ActCaptureGeneration) { Reset-OneLinkRecorderContext $Context }
    $now = Get-Date
    $gap = ($now - $Context.Last).TotalSeconds
    if ($gap -ge 0 -and $gap -le $script:ActIdleThresholdSeconds) { $Context.ActiveSeconds += $gap }
    $Context.Last = $now
    if ($Click) { $Context.Clicks++ }
    if ($Field) { [void]$Context.Fields.Add($Field) }
}

function Start-OneLinkRecordedOperation {
    param([hashtable]$Context)
    if ($Context.Generation -ne $script:ActCaptureGeneration) { Reset-OneLinkRecorderContext $Context }
    $snapshot = @{
        Clicks = $Context.Clicks; Fields = $Context.Fields; ActiveSeconds = $Context.ActiveSeconds
        Generation = $Context.Generation; Frozen = $true; Started = Get-Date
    }
    Reset-OneLinkRecorderContext $Context
    return $snapshot
}

function Enable-OneLinkWindowRecorder {
    param($Window)
    $context = @{}
    Reset-OneLinkRecorderContext $context
    if ($script:ActCaptureEnabled) {
        $context.Clicks = [math]::Max(0, $script:ActClicks - $script:ActBoundaryClicks)
        $context.ActiveSeconds = $script:ActActiveSeconds
        foreach ($field in $script:ActTouchedFields) { [void]$context.Fields.Add($field) }
        Reset-OneLinkActivitySegment
    }
    $Window.Add_PreviewMouseDown({ Register-OneLinkRecorderEvent -Context $context -Click }.GetNewClosure())
    $Window.Add_PreviewKeyDown({ Register-OneLinkRecorderEvent -Context $context }.GetNewClosure())
    $touch = {
        param($sender, $eventArgs)
        $control = $eventArgs.OriginalSource
        if ($control -and $control.IsKeyboardFocusWithin) {
            Register-OneLinkRecorderEvent -Context $context -Field ([string]$control.GetHashCode())
        }
    }.GetNewClosure()
    $Window.AddHandler([System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent, [System.Windows.Controls.TextChangedEventHandler]$touch)
    $Window.AddHandler([System.Windows.Controls.PasswordBox]::PasswordChangedEvent, [System.Windows.RoutedEventHandler]$touch)
    $Window.AddHandler([System.Windows.Controls.Primitives.Selector]::SelectionChangedEvent, [System.Windows.Controls.SelectionChangedEventHandler]$touch)
    $Window.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent, [System.Windows.RoutedEventHandler]$touch)
    $Window.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, [System.Windows.RoutedEventHandler]$touch)
    return $context
}

function Update-OneLinkConsoleRecording {
    param([hashtable]$State, [string]$Chunk = '', [switch]$Closing)
    $State.Buffer += $Chunk
    foreach ($pending in @($State.Pending.ToArray())) {
        $match = [regex]::Match($State.Buffer, ([regex]::Escape($pending.Token) + ':(\d+)\r?\n'))
        if ($match.Success -or $Closing -or ((Get-Date) - $pending.Context.Started).TotalSeconds -ge $State.Timeout) {
            $outcome = if ($match.Success) { if ([int]$match.Groups[1].Value -eq 0) { 'Success' } else { 'Failed' } } else { 'Unknown' }
            Complete-OneLinkActivity -Name 'SSH Command' -Target $pending.Host -Outcome $outcome -OperationSeconds (((Get-Date) - $pending.Context.Started).TotalSeconds) -Context $pending.Context
            [void]$State.Pending.Remove($pending)
        }
    }
    # Hide the instrumentation's echoed printf line and completion marker.
    $State.Buffer = $State.Buffer -replace '(?m)^.*printf.*OLK_METRIC_[a-f0-9]+.*\r?\n', ''
    $State.Buffer = $State.Buffer -replace 'OLK_METRIC_[a-f0-9]+:\d+\r?\n', ''
    $end = $State.Buffer.LastIndexOf("`n") + 1
    if ($State.Pending.Count -eq 0) { $end = $State.Buffer.Length }
    if ($end -gt 0) {
        $display = $State.Buffer.Substring(0, $end)
        $State.Buffer = $State.Buffer.Substring($end)
        return $display
    }
}

# Refresh the Activity Metrics summary line (totals + averages).
function Update-OneLinkActivitySummary {
    if (-not $script:TxtActivitySummary) { return }
    $n = $script:ActivityMetrics.Count
    if ($n -eq 0) { $script:TxtActivitySummary.Text = 'No activities recorded yet.'; return }
    $totClicks = ($script:ActivityMetrics | Measure-Object -Property Clicks -Sum).Sum
    $totInputs = ($script:ActivityMetrics | Measure-Object -Property Inputs -Sum).Sum
    $totSecs = ($script:ActivityMetrics | Measure-Object -Property ActivitySeconds -Sum).Sum
    $avgActions = [math]::Round(($totClicks + $totInputs) / $n, 1)
    $mins = [math]::Floor($totSecs / 60); $secs = [int]($totSecs % 60)
    $script:TxtActivitySummary.Text = ("Activities: {0}   |   Total time: {1}m {2}s   |   Clicks: {3}   |   Fields: {4}   |   Avg actions/activity: {5}" -f `
        $n, $mins, $secs, $totClicks, $totInputs, $avgActions)
}

# Efficiency panel (opened from the footer diamond - no sign-in). Start/stop
# capturing, open the Metrics tab, and export the report. Capturing counts only
# ACTIVE work; idle time (no interaction for over the threshold) is not counted.
function Show-OneLinkCaptureDialog {
    $win = New-Object System.Windows.Window
    $win.Title = 'Efficiency metrics'
    $win.SizeToContent = 'WidthAndHeight'; $win.WindowStartupLocation = 'CenterScreen'; $win.ResizeMode = 'NoResize'; $win.MinWidth = 380
    $win.WindowStyle = 'SingleBorderWindow'
    if ($script:Window) { $win.Owner = $script:Window }
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '16'
    $status = New-Object System.Windows.Controls.TextBlock; $status.TextWrapping = 'Wrap'; $status.Margin = '0,0,0,14'; $status.MaxWidth = 360
    $status.Text = if ($script:ActCaptureEnabled) {
        "Capturing is ON. Each completed action records its clicks, fields and ACTIVE time (idle time is not counted). Results appear on the Metrics tab."
    } else {
        "Capturing is OFF. Start it to record each action's clicks, fields and ACTIVE time. Idle time (no interaction for over $($script:ActIdleThresholdSeconds)s) is not counted."
    }
    $mk = {
        param($text)
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $text; $b.Height = 30; $b.Margin = '0,0,0,8'; $b.HorizontalContentAlignment = 'Center'
        return $b
    }
    $toggleText = 'Start capturing'; if ($script:ActCaptureEnabled) { $toggleText = 'Stop capturing' }
    $toggle = & $mk $toggleText
    $openTab = & $mk 'Open Metrics tab'
    $export = & $mk 'Export report (CSV)'
    $close = New-Object System.Windows.Controls.Button; $close.Content = 'Close'; $close.Height = 30; $close.HorizontalAlignment = 'Right'; $close.Width = 90; $close.IsCancel = $true

    $revealTab = { $TabMetrics.Visibility = [System.Windows.Visibility]::Visible; $TabMetrics.IsSelected = $true }

    $toggle.Add_Click({
        if (Test-OneLinkRecorderCapture) {
            Set-OneLinkRecorderCapture $false
            $ChkCaptureMetrics.IsChecked = $false
            Write-OneLinkLog "Efficiency capture stopped." -Level Info
        }
        else {
            Set-OneLinkRecorderCapture $true
            $ChkCaptureMetrics.IsChecked = $true
            Reset-OneLinkActivitySegment
            & $revealTab
            Write-OneLinkLog "Efficiency capture STARTED (active time only)." -Level Success
        }
        $win.Close()
    }.GetNewClosure())
    $openTab.Add_Click({ & $revealTab; $win.Close() }.GetNewClosure())
    $export.Add_Click({ Export-OneLinkActivityMetrics }.GetNewClosure())
    $close.Add_Click({ $win.Close() }.GetNewClosure())

    foreach ($el in @($status, $toggle, $openTab, $export, $close)) { [void]$sp.Children.Add($el) }
    $win.Content = $sp; [void]$win.ShowDialog()
}

