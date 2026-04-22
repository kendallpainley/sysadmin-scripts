# ==============================================================================
# Description : Monitors a list of critical Windows services. If any are stopped,
#               it attempts to restart them and logs the event. Optionally sends
#               an email alert and writes to the Windows Event Log.
# Usage       : .\service_monitor.ps1 [-Services "svc1","svc2"] [-AlertEmail addr]
#               Can be scheduled via Task Scheduler for continuous monitoring.
# ==============================================================================

[CmdletBinding()]
param(
    # Services to monitor — defaults to common critical Windows services
    [string[]]$Services = @(
        "wuauserv",        # Windows Update
        "Spooler",         # Print Spooler
        "W32Time",         # Windows Time
        "WinDefend",       # Windows Defender
        "EventLog"         # Windows Event Log
    ),

    [string]$AlertEmail   = "",            # Send alert to this address if non-empty
    [string]$SmtpServer   = "smtp.example.com",
    [int]$SmtpPort        = 587,
    [string]$FromAddress  = "alerts@example.com",
    [string]$LogPath      = "$env:TEMP\service_monitor.log",
    [switch]$NoRestart,                    # Only alert, don't try to restart
    [int]$RestartWaitSec  = 10             # Seconds to wait before checking if restart succeeded
)

#region ── Helpers ──────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue

    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $line -ForegroundColor $color
}

function Send-Alert {
    param([string]$Subject, [string]$Body)
    if (-not $AlertEmail) { return }
    try {
        $mailParams = @{
            SmtpServer = $SmtpServer
            Port       = $SmtpPort
            UseSsl     = $true
            From       = $FromAddress
            To         = $AlertEmail
            Subject    = $Subject
            Body       = $Body
            BodyAsHtml = $false
        }
        Send-MailMessage @mailParams -ErrorAction Stop
        Write-Log "INFO" "Alert email sent to $AlertEmail"
    } catch {
        Write-Log "ERROR" "Failed to send email alert: $_"
    }
}

#endregion

#region ── Main ─────────────────────────────────────────────────────────────────

# Ensure log directory exists
$LogDir = Split-Path $LogPath
if ($LogDir -and -not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "║         SERVICE MONITOR                         ║" -ForegroundColor DarkCyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""

Write-Log "INFO" "Service monitor started on $env:COMPUTERNAME"
Write-Log "INFO" "Monitoring $($Services.Count) service(s)"

$Results = @()
$RestartAttempts = 0
$Failures = @()

foreach ($ServiceName in $Services) {
    # Get service object
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if (-not $svc) {
        Write-Log "WARN" "Service not found: $ServiceName"
        $Results += [PSCustomObject]@{
            Service = $ServiceName
            Status  = "Not Found"
            Action  = "None"
        }
        continue
    }

    $DisplayName = $svc.DisplayName
    $Status      = $svc.Status

    Write-Host ("  {0,-30} → {1}" -f $DisplayName, $Status) -ForegroundColor $(
        if ($Status -eq "Running") { "Green" } else { "Red" }
    )

    if ($Status -eq "Running") {
        Write-Log "INFO" "OK: $DisplayName [$ServiceName] is Running"
        $Results += [PSCustomObject]@{
            Service = $ServiceName
            Status  = "Running"
            Action  = "None needed"
        }
        continue
    }

    # ── Service is NOT running ─────────────────────────────────────────────────
    Write-Log "WARN" "ALERT: $DisplayName [$ServiceName] is $Status"
    $Failures += $ServiceName

    if ($NoRestart) {
        Write-Log "WARN" "-NoRestart specified; skipping restart attempt for $ServiceName"
        $Results += [PSCustomObject]@{
            Service = $ServiceName
            Status  = $Status
            Action  = "No restart (flag set)"
        }
        continue
    }

    # Attempt restart
    Write-Log "INFO" "Attempting to start $DisplayName [$ServiceName]..."
    try {
        Start-Service -Name $ServiceName -ErrorAction Stop
        Start-Sleep -Seconds $RestartWaitSec

        $svcPost = Get-Service -Name $ServiceName
        if ($svcPost.Status -eq "Running") {
            Write-Log "SUCCESS" "$DisplayName [$ServiceName] restarted successfully."
            $Results += [PSCustomObject]@{
                Service = $ServiceName
                Status  = "Restarted"
                Action  = "Restart succeeded"
            }
            $RestartAttempts++
        } else {
            Write-Log "ERROR" "$DisplayName [$ServiceName] did not start (status: $($svcPost.Status))"
            $Results += [PSCustomObject]@{
                Service = $ServiceName
                Status  = $svcPost.Status
                Action  = "Restart FAILED"
            }
        }
    } catch {
        Write-Log "ERROR" "Exception restarting $ServiceName`: $_"
        $Results += [PSCustomObject]@{
            Service = $ServiceName
            Status  = "Error"
            Action  = "Restart exception: $_"
        }
    }
}

#endregion

#region ── Summary & Alert ──────────────────────────────────────────────────────

Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkCyan
$RunningCount = ($Results | Where-Object { $_.Status -in "Running","Restarted" }).Count
Write-Log "INFO" "Monitor complete — $RunningCount/$($Services.Count) services healthy"
if ($RestartAttempts -gt 0) {
    Write-Log "INFO" "$RestartAttempts service(s) were restarted."
}

# Send alert email if any service was not running
if ($Failures.Count -gt 0) {
    $Subject = "[ALERT] $env:COMPUTERNAME — $($Failures.Count) service(s) not running"
    $Body = "Service Monitor Alert`n"
    $Body += "Host     : $env:COMPUTERNAME`n"
    $Body += "Time     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
    $Body += "Log      : $LogPath`n`n"
    $Body += "Problem Services:`n"
    foreach ($f in $Failures) { $Body += "  - $f`n" }
    $Body += "`nResult Summary:`n"
    foreach ($r in $Results) { $Body += "  $($r.Service) : $($r.Status) — $($r.Action)`n" }
    Send-Alert -Subject $Subject -Body $Body
}

# Display table
$Results | Format-Table Service, Status, Action -AutoSize

Write-Host ("═" * 50) -ForegroundColor DarkCyan
Write-Host ""

#endregion