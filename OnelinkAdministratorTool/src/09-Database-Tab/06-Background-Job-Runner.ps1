# ---------------------------------------------------------------------------
#  Background job infrastructure for long DB backup/restore (keeps the UI
#  responsive and lets the user Stop a running operation).
# ---------------------------------------------------------------------------
# The single in-flight backup/restore context, held INSIDE a hashtable. This is
# deliberate: the completion runs in a DispatcherTimer tick built with
# .GetNewClosure(), and inside such a closure `$script:X = ...` writes to the
# closure's own module scope - it does NOT clear the real script variable. So a
# plain `$script:BgJob = $null` in the tick never cleared the flag ("a
# backup/restore is already running" on the 2nd export). Mutating a CAPTURED
# hashtable's member does reach the real object, so we clear via $state.Job.
$script:BgState = @{ Job = $null }

# Run a SELF-CONTAINED scriptblock in a background runspace. It receives $sync
# (a synchronized state bag) plus every entry of $Vars as a variable.
function Start-OneLinkBgJob {
    param([scriptblock]$Script, [hashtable]$Vars)
    $sync = [hashtable]::Synchronized(@{ Cancel = $false; Status = 'Starting...'; Done = $false; Ok = $false; Message = ''; Client = $null; StopInfo = $null })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    foreach ($k in $Vars.Keys) { $rs.SessionStateProxy.SetVariable($k, $Vars[$k]) }
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Script)
    $handle = $ps.BeginInvoke()
    return [pscustomobject]@{ Sync = $sync; PS = $ps; Runspace = $rs; Handle = $handle }
}

# Poll a background job on the UI thread; update status, and report on completion.
function Watch-OneLinkBgJob {
    param($Ctx, $StatusCtrl, $RunButton, $StopButton, [string]$OpName, [string]$TargetHost)
    $RunButton.IsEnabled = $false
    $StopButton.IsEnabled = $true
    $state = $script:BgState   # local reference to the shared hashtable; GetNewClosure captures it
    $state.Job = $Ctx
    $startTime = Get-Date
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $tick = {
        $StatusCtrl.Text = [string]$Ctx.Sync.Status
        # Finish when the worker signals Done OR when the runspace pipeline has
        # actually completed. The second check is the safety net: a hard Stop
        # (BeginStop) or a worker crash can abort the thread BEFORE its
        # finally{ $sync.Done = $true } runs, which used to leave $script:BgJob
        # stuck non-null forever ("a backup/restore is already running" with
        # nothing running). Handle.IsCompleted flips true even in that case.
        if ($Ctx.Sync.Done -or $Ctx.Handle.IsCompleted) {
            $timer.Stop()
            # Clear the guard and reset buttons FIRST, before any call that could
            # throw, so the tool can never wedge in the "busy" state. $state is the
            # captured shared hashtable - mutating .Job here DOES reach the real
            # $script:BgState (unlike `$script:BgJob = $null`, which a GetNewClosure
            # would write to its own module scope).
            $state.Job = $null
            $RunButton.IsEnabled = $true
            $StopButton.IsEnabled = $false
            try { $Ctx.PS.EndInvoke($Ctx.Handle) } catch { }
            try { $Ctx.PS.Dispose() } catch { }
            try { $Ctx.Runspace.Dispose() } catch { }
            # If the pipeline ended without the worker setting Done, it was killed
            # before it could record a result - treat that as stopped/failed.
            if (-not $Ctx.Sync.Done) {
                $Ctx.Sync.Ok = $false
                if ([string]::IsNullOrWhiteSpace([string]$Ctx.Sync.Message)) { $Ctx.Sync.Message = 'Stopped.' }
            }
            Complete-OneLinkActivity -Name $OpName -Target $TargetHost -Outcome ($(if ($Ctx.Sync.Ok) { 'Success' } else { 'Failed' })) -OperationSeconds (((Get-Date) - $startTime).TotalSeconds)
            if ($Ctx.Sync.Ok) {
                $StatusCtrl.Text = "Done. " + [string]$Ctx.Sync.Message
                Write-OneLinkLog "[$TargetHost] $OpName : $($Ctx.Sync.Message)" -Level Success
                Write-OneLinkEfficiency -Operation $OpName -Target $TargetHost -Outcome 'Success' -Start $startTime -End (Get-Date)
                Show-InfoMessage "$OpName completed.`n`n$($Ctx.Sync.Message)"
            }
            else {
                $StatusCtrl.Text = "Stopped/failed. " + [string]$Ctx.Sync.Message
                Write-OneLinkLog "[$TargetHost] $OpName : $($Ctx.Sync.Message)" -Level Error
                Write-OneLinkEfficiency -Operation $OpName -Target $TargetHost -Outcome 'Failed' -Start $startTime -End (Get-Date)
                Show-WarningMessage "$OpName did not complete.`n`n$($Ctx.Sync.Message)"
            }
        }
    }.GetNewClosure()
    $timer.Add_Tick($tick)
    $timer.Start()
}

# Stop a running job: flag cancel, kill the server-side dump/restore, drop the
# worker's SSH client, and stop the runspace pipeline.
function Stop-OneLinkBgJob {
    param($Ctx)
    if ($null -eq $Ctx) { return }
    $Ctx.Sync.Cancel = $true
    $Ctx.Sync.Status = 'Stopping (killing server-side job and aborting transfer)...'
    $si = $Ctx.Sync.StopInfo
    if ($si) {
        try {
            Import-OneLinkPoshSsh
            $sec = ConvertTo-SecureString $si.Pass -AsPlainText -Force
            $cr = [pscredential]::new($si.User, $sec)
            $s2 = New-SSHSession -ComputerName $si.Host -Port $si.Port -Credential $cr -AcceptKey -ConnectionTimeout 15 -ErrorAction Stop
            if ($si.JobId -notmatch '^[a-f0-9]{32}$') { throw 'Invalid database job identity.' }
            $stopScript = @'
d=__DIR__
if [ -r "$d/pid" ]; then
    read -r pid < "$d/pid"
    case "$pid" in ''|*[!0-9]*) exit 1;; esac
    if [ -r "/proc/$pid/cmdline" ] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -F -- "$d" >/dev/null; then
        if [ "$(id -u)" = 0 ]; then kill -TERM -- "-$pid"; else sudo -n kill -TERM -- "-$pid"; fi
    fi
fi
'@
            $stopScript = $stopScript.Replace('__DIR__', (ConvertTo-OneLinkBashArg ('/tmp/onelink-db-' + $si.JobId)))
            Invoke-SSHCommand -SSHSession $s2 -Command (ConvertTo-OneLinkDatabaseCommand $stopScript) -TimeOut 25 | Out-Null
            Remove-SSHSession -SSHSession $s2 -ErrorAction SilentlyContinue | Out-Null
        }
        catch { }
    }
    try { if ($Ctx.Sync.Client) { $Ctx.Sync.Client.Disconnect() } } catch { }
    try { [void]$Ctx.PS.BeginStop($null, $null) } catch { }
}

