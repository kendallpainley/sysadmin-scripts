# ==============================================================================
# Description : Generates a detailed Windows/cross-platform system information
#               report including OS, hardware, memory, disk, and network info.
#               Outputs to console and optionally exports to a CSV or HTML file.
# Usage       : .\system_info.ps1 [-ExportHTML] [-ExportCSV] [-OutputPath <dir>]
# ==============================================================================

[CmdletBinding()]
param(
    [switch]$ExportHTML,
    [switch]$ExportCSV,
    [string]$OutputPath = "$env:USERPROFILE\Desktop"
)

#region ── Helpers ──────────────────────────────────────────────────────────────

function Write-Section {
    param([string]$Title)
    Write-Host "`n$('═' * 50)" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan -NoNewline
    Write-Host ""
    Write-Host "$('═' * 50)" -ForegroundColor Cyan
}

function Write-KV {
    param([string]$Key, [string]$Value, [string]$Color = "White")
    Write-Host ("  {0,-25} : " -f $Key) -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $Color
}

function Format-Bytes {
    param([long]$Bytes)
    if     ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    elseif ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    else                    { return "$Bytes B" }
}

function Get-DiskColor {
    param([double]$Pct)
    if ($Pct -ge 90) { return "Red" }
    elseif ($Pct -ge 75) { return "Yellow" }
    else { return "Green" }
}

#endregion

#region ── Gather Data ──────────────────────────────────────────────────────────

$Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$Hostname    = [System.Net.Dns]::GetHostName()
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# OS Info
$OS = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
    Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
} else { $null }

$OSCaption    = if ($OS) { $OS.Caption } else { (uname -sr) }
$OSArch       = if ($OS) { $OS.OSArchitecture } else { (uname -m) }
$LastBoot     = if ($OS) { $OS.LastBootUpTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
$Uptime       = if ($OS) { (Get-Date) - $OS.LastBootUpTime } else { $null }
$UptimeStr    = if ($Uptime) { "$($Uptime.Days)d $($Uptime.Hours)h $($Uptime.Minutes)m" } else { "N/A" }

# CPU Info
$CPU = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
    Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
} else { $null }

$CPUName    = if ($CPU) { $CPU.Name.Trim() } else { "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || cat /proc/cpuinfo 2>/dev/null | grep 'model name' | head -1 | cut -d: -f2 | xargs)" }
$CPUCores   = if ($CPU) { "$($CPU.NumberOfCores) cores / $($CPU.NumberOfLogicalProcessors) logical" } else { "$(nproc 2>/dev/null || sysctl -n hw.logicalcpu) logical" }
$CPULoad    = if ($CPU) { "$($CPU.LoadPercentage)%" } else { "N/A (use monitor tools)" }

# Memory
$TotalMem   = if ($OS) { $OS.TotalVisibleMemorySize * 1KB } else {
    if ($IsLinux) { (Get-Content /proc/meminfo | Where-Object { $_ -match "MemTotal" } | ForEach-Object { ($_ -replace '\D+','').Trim() -as [long] }) * 1KB }
    else          { [long](sysctl -n hw.memsize 2>/dev/null) }
}
$FreeMem    = if ($OS) { $OS.FreePhysicalMemory * 1KB } else { 0 }
$UsedMem    = $TotalMem - $FreeMem
$MemPct     = if ($TotalMem -gt 0) { [math]::Round(($UsedMem / $TotalMem) * 100, 1) } else { 0 }

# Disks
$Disks = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Used -ne $null }

# Network Adapters
$NetAdapters = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
    Get-NetIPAddress -ErrorAction SilentlyContinue | Where-Object { $_.AddressFamily -eq "IPv4" -and $_.IPAddress -ne "127.0.0.1" }
} else { $null }

#endregion

#region ── Console Output ───────────────────────────────────────────────────────

Write-Host "`n" -NoNewline
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "║         SYSTEM INFORMATION REPORT               ║" -ForegroundColor DarkCyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor DarkCyan

Write-KV "Hostname"        $Hostname       "Yellow"
Write-KV "Current User"    $CurrentUser    "Yellow"
Write-KV "Report Time"     $Timestamp      "Gray"

# ── OS ────────────────────────────────────────────────────────────────────────
Write-Section "Operating System"
Write-KV "OS"              $OSCaption
Write-KV "Architecture"    $OSArch
Write-KV "PowerShell"      $PSVersionTable.PSVersion.ToString()
Write-KV "Last Boot"       $LastBoot
Write-KV "Uptime"          $UptimeStr

# ── CPU ───────────────────────────────────────────────────────────────────────
Write-Section "Processor"
Write-KV "Model"           $CPUName
Write-KV "Cores"           $CPUCores
Write-KV "Current Load"    $CPULoad $(if ($CPU -and $CPU.LoadPercentage -ge 80) { "Red" } elseif ($CPU -and $CPU.LoadPercentage -ge 60) { "Yellow" } else { "Green" })

# ── Memory ────────────────────────────────────────────────────────────────────
Write-Section "Memory"
Write-KV "Total RAM"       (Format-Bytes $TotalMem)
Write-KV "Used RAM"        "$(Format-Bytes $UsedMem) ($MemPct%)" $(if ($MemPct -ge 80) { "Red" } elseif ($MemPct -ge 60) { "Yellow" } else { "Green" })
Write-KV "Free RAM"        (Format-Bytes $FreeMem)

# ── Disks ─────────────────────────────────────────────────────────────────────
Write-Section "Disk Usage"
foreach ($disk in $Disks) {
    $total = $disk.Used + $disk.Free
    if ($total -eq 0) { continue }
    $pct   = [math]::Round(($disk.Used / $total) * 100, 1)
    $color = Get-DiskColor $pct
    $label = if ($disk.Description) { "$($disk.Name) ($($disk.Description))" } else { $disk.Name }
    Write-KV $label "$(Format-Bytes ($disk.Used * 1)) used / $(Format-Bytes ($total * 1)) total — $pct%" $color
}

# ── Network ───────────────────────────────────────────────────────────────────
Write-Section "Network Interfaces"
if ($NetAdapters) {
    foreach ($adapter in $NetAdapters) {
        Write-KV $adapter.InterfaceAlias $adapter.IPAddress "Cyan"
    }
} else {
    # Cross-platform fallback
    $ifconfig = (ifconfig 2>/dev/null || ip addr 2>/dev/null)
    if ($ifconfig) {
        Write-Host "  (Use ifconfig / ip addr for full details)" -ForegroundColor Gray
    }
}

# ── Footer ────────────────────────────────────────────────────────────────────
Write-Host "`n$('═' * 50)" -ForegroundColor DarkCyan
Write-Host "  Report complete — $Timestamp" -ForegroundColor DarkCyan
Write-Host "$('═' * 50)`n" -ForegroundColor DarkCyan

#endregion

#region ── HTML Export ──────────────────────────────────────────────────────────

if ($ExportHTML) {
    $HtmlFile = Join-Path $OutputPath "system_info_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $DiskRows = ($Disks | Where-Object { ($_.Used + $_.Free) -gt 0 } | ForEach-Object {
        $total = $_.Used + $_.Free
        $pct   = [math]::Round(($_.Used / $total) * 100, 1)
        $color = if ($pct -ge 90) { "#e74c3c" } elseif ($pct -ge 75) { "#f39c12" } else { "#2ecc71" }
        "<tr><td>$($_.Name)</td><td>$(Format-Bytes ($_.Used))</td><td>$(Format-Bytes $total)</td><td style='color:$color'>$pct%</td></tr>"
    }) -join "`n"

    $Html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>System Info — $Hostname</title>
<style>
  body { font-family: 'Segoe UI', monospace; background: #1a1a2e; color: #eee; padding: 2rem; }
  h1   { color: #0f9bc0; }
  h2   { color: #0f9bc0; border-bottom: 1px solid #0f9bc0; padding-bottom: 4px; margin-top: 2rem; }
  table { width: 100%; border-collapse: collapse; margin-top: 0.5rem; }
  th   { text-align: left; color: #888; font-weight: normal; padding: 4px 8px; }
  td   { padding: 4px 8px; border-bottom: 1px solid #333; }
</style>
</head>
<body>
<h1>System Information Report</h1>
<p>Host: <b>$Hostname</b> &nbsp;|&nbsp; Generated: $Timestamp</p>
<h2>Operating System</h2>
<table><tr><th>OS</th><td>$OSCaption ($OSArch)</td></tr>
<tr><th>Uptime</th><td>$UptimeStr (since $LastBoot)</td></tr>
<tr><th>PowerShell</th><td>$($PSVersionTable.PSVersion)</td></tr></table>
<h2>Processor</h2>
<table><tr><th>Model</th><td>$CPUName</td></tr>
<tr><th>Cores</th><td>$CPUCores</td></tr></table>
<h2>Memory</h2>
<table><tr><th>Total</th><td>$(Format-Bytes $TotalMem)</td></tr>
<tr><th>Used</th><td>$(Format-Bytes $UsedMem) ($MemPct%)</td></tr></table>
<h2>Disk Usage</h2>
<table><tr><th>Drive</th><th>Used</th><th>Total</th><th>Usage</th></tr>
$DiskRows</table>
</body></html>
"@
    $Html | Out-File -FilePath $HtmlFile -Encoding UTF8
    Write-Host "HTML report saved: $HtmlFile" -ForegroundColor Green
}

#endregion

#region ── CSV Export ───────────────────────────────────────────────────────────

if ($ExportCSV) {
    $CsvFile = Join-Path $OutputPath "system_info_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    [PSCustomObject]@{
        Timestamp   = $Timestamp
        Hostname    = $Hostname
        OS          = $OSCaption
        Uptime      = $UptimeStr
        CPU         = $CPUName
        TotalRAM_GB = [math]::Round($TotalMem / 1GB, 2)
        UsedRAM_GB  = [math]::Round($UsedMem / 1GB, 2)
        MemUsedPct  = $MemPct
    } | Export-Csv -Path $CsvFile -NoTypeInformation
    Write-Host "CSV report saved: $CsvFile" -ForegroundColor Green
}

#endregion