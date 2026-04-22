#!/usr/bin/env bash
# ==============================================================================
# health_check.sh
# Full system health report — CPU, RAM, Disk, and top processes.
# Outputs a timestamped report to stdout and optionally to a file.
# Usage       : ./health_check.sh [--output /path/to/report.txt]
# ==============================================================================

set -euo pipefail

# ---------- Colors ------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ---------- Config ------------------------------------------------------------
DISK_WARN_THRESHOLD=80      # % usage that triggers a WARNING
DISK_CRIT_THRESHOLD=90      # % usage that triggers a CRITICAL
MEM_WARN_THRESHOLD=80
OUTPUT_FILE=""

# ---------- Argument parsing --------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--output /path/to/report.txt]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ---------- Helper functions --------------------------------------------------
section() { echo -e "\n${CYAN}${BOLD}══ $1 ══${RESET}"; }
ok()      { echo -e "  ${GREEN}✔${RESET}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
crit()    { echo -e "  ${RED}✘${RESET}  $1"; }

# Detect OS
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

OS=$(detect_os)

# ---------- Report header -----------------------------------------------------
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)

echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       SYSTEM HEALTH REPORT           ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
echo -e "  Host      : ${BOLD}${HOSTNAME}${RESET}"
echo -e "  Generated : ${TIMESTAMP}"
echo -e "  OS        : $(uname -srm)"

# ---------- CPU ---------------------------------------------------------------
section "CPU"

if [[ "$OS" == "macos" ]]; then
  CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  CPU_CORES=$(sysctl -n hw.logicalcpu)
  # macOS: get CPU usage via top snapshot
  CPU_IDLE=$(top -l 1 -n 0 | awk '/CPU usage/ {gsub(/%/,""); print $7}')
  CPU_USAGE=$(echo "100 - $CPU_IDLE" | bc 2>/dev/null || echo "N/A")
else
  CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
  CPU_CORES=$(nproc)
  CPU_USAGE=$(top -bn1 | awk '/Cpu\(s\)/ {print 100 - $8}')
fi

echo "  Model  : $CPU_MODEL"
echo "  Cores  : $CPU_CORES"
echo "  Usage  : ${CPU_USAGE}%"

# Load average (works on both macOS and Linux)
LOAD=$(uptime | awk -F'load average[s:]?' '{print $2}' | xargs)
echo "  Load   : $LOAD (1m, 5m, 15m)"

# ---------- Memory ------------------------------------------------------------
section "Memory"

if [[ "$OS" == "macos" ]]; then
  TOTAL_MEM_BYTES=$(sysctl -n hw.memsize)
  TOTAL_MEM_GB=$(echo "scale=1; $TOTAL_MEM_BYTES / 1073741824" | bc)

  # Parse vm_stat for page usage
  PAGE_SIZE=$(vm_stat | awk '/page size/ {print $8}')
  PAGES_FREE=$(vm_stat | awk '/Pages free/ {gsub(/\./,""); print $3}')
  PAGES_ACTIVE=$(vm_stat | awk '/Pages active/ {gsub(/\./,""); print $3}')
  PAGES_INACTIVE=$(vm_stat | awk '/Pages inactive/ {gsub(/\./,""); print $3}')
  PAGES_WIRED=$(vm_stat | awk '/Pages wired/ {gsub(/\./,""); print $4}')

  USED_PAGES=$((PAGES_ACTIVE + PAGES_WIRED))
  FREE_PAGES=$((PAGES_FREE + PAGES_INACTIVE))
  USED_GB=$(echo "scale=1; $USED_PAGES * $PAGE_SIZE / 1073741824" | bc)
  FREE_GB=$(echo "scale=1; $FREE_PAGES * $PAGE_SIZE / 1073741824" | bc)
  MEM_PCT=$(echo "scale=0; $USED_PAGES * 100 / ($USED_PAGES + $FREE_PAGES)" | bc)
else
  read TOTAL_MEM USED_MEM FREE_MEM <<< $(free -m | awk '/^Mem/ {print $2, $3, $4}')
  TOTAL_MEM_GB=$(echo "scale=1; $TOTAL_MEM / 1024" | bc)
  USED_GB=$(echo "scale=1; $USED_MEM / 1024" | bc)
  FREE_GB=$(echo "scale=1; $FREE_MEM / 1024" | bc)
  MEM_PCT=$(echo "scale=0; $USED_MEM * 100 / $TOTAL_MEM" | bc)
fi

echo "  Total  : ${TOTAL_MEM_GB} GB"
echo "  Used   : ${USED_GB} GB (${MEM_PCT}%)"
echo "  Free   : ${FREE_GB} GB"

if (( MEM_PCT >= MEM_WARN_THRESHOLD )); then
  warn "Memory usage is at ${MEM_PCT}% — consider investigating high-memory processes."
else
  ok "Memory usage is healthy at ${MEM_PCT}%."
fi

# ---------- Disk --------------------------------------------------------------
section "Disk Usage"

if [[ "$OS" == "macos" ]]; then
  DF_CMD="df -H"
  EXCLUDE_PATTERN="devfs|map|Filesystem"
else
  DF_CMD="df -h --output=source,size,used,avail,pcent,target"
  EXCLUDE_PATTERN="tmpfs|devtmpfs|Filesystem"
fi

$DF_CMD | grep -vE "$EXCLUDE_PATTERN" | while read -r line; do
  PCT=$(echo "$line" | awk '{print $(NF-1)}' | tr -d '%')
  MOUNT=$(echo "$line" | awk '{print $NF}')
  SIZE=$(echo "$line" | awk '{print $2}')
  USED=$(echo "$line" | awk '{print $3}')

  [[ -z "$PCT" || ! "$PCT" =~ ^[0-9]+$ ]] && continue

  DISPLAY="  $MOUNT — ${USED} used of ${SIZE} (${PCT}%)"
  if (( PCT >= DISK_CRIT_THRESHOLD )); then
    crit "$DISPLAY  [CRITICAL]"
  elif (( PCT >= DISK_WARN_THRESHOLD )); then
    warn "$DISPLAY  [WARNING]"
  else
    ok "$DISPLAY"
  fi
done

# ---------- Top Processes by CPU ----------------------------------------------
section "Top 5 Processes (CPU)"
if [[ "$OS" == "macos" ]]; then
  ps -eo pid,pcpu,pmem,comm | sort -k2 -rn | head -6 | tail -5 | \
    awk '{printf "  PID %-8s  CPU %-6s  MEM %-6s  %s\n", $1, $2"%", $3"%", $4}'
else
  ps -eo pid,pcpu,pmem,comm --sort=-%cpu | head -6 | tail -5 | \
    awk '{printf "  PID %-8s  CPU %-6s  MEM %-6s  %s\n", $1, $2"%", $3"%", $4}'
fi

# ---------- Uptime ------------------------------------------------------------
section "Uptime"
uptime | awk '{
  for(i=1;i<=NF;i++) if($i=="up") {
    print "  " $(i+1) " " $(i+2)
    break
  }
}'

# ---------- Footer ------------------------------------------------------------
echo -e "\n${BOLD}══════════════════════════════════════════${RESET}"
echo -e "  Report complete — ${TIMESTAMP}"
echo -e "${BOLD}══════════════════════════════════════════${RESET}\n"

# ---------- Optional file output ----------------------------------------------
if [[ -n "$OUTPUT_FILE" ]]; then
  # Re-run without color codes for the file
  script_path="$(realpath "$0")"
  bash "$script_path" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$OUTPUT_FILE"
  echo "Report saved to: $OUTPUT_FILE"
fi