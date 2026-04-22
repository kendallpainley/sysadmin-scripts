#!/usr/bin/env bash
# ==============================================================================
# Pings every host in a /24 subnet and reports which IPs are live.
# Uses parallel pinging for speed. Optionally resolves hostnames.
# Usage       : ./ping_sweep.sh <subnet_base> [--resolve] [--output results.txt]
# ==============================================================================

set -euo pipefail

# ---------- Colors ------------------------------------------------------------
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'

# ---------- Defaults ----------------------------------------------------------
RESOLVE_NAMES=false
OUTPUT_FILE=""
MAX_PARALLEL=50        # concurrent ping jobs
PING_TIMEOUT=1         # seconds per ping

# ---------- Usage -------------------------------------------------------------
usage() {
  echo "Usage: $0 <subnet_base> [--resolve] [--output file.txt]"
  echo "  subnet_base  : First 3 octets, e.g. 192.168.1"
  echo "  --resolve    : Attempt reverse DNS lookup for live hosts"
  echo "  --output     : Save results to file"
  exit 1
}

[[ $# -lt 1 ]] && usage

SUBNET_BASE="$1"; shift

while [[ $# -gt 0 ]]; do
  case $1 in
    --resolve) RESOLVE_NAMES=true; shift ;;
    --output)  OUTPUT_FILE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Validate subnet format
if ! [[ "$SUBNET_BASE" =~ ^([0-9]{1,3}\.){2}[0-9]{1,3}$ ]]; then
  echo "Error: subnet_base must be in format X.X.X (e.g. 192.168.1)"
  exit 1
fi

# ---------- OS detection for ping flags ---------------------------------------
OS=$(uname -s)
if [[ "$OS" == "Darwin" ]]; then
  PING_CMD="ping -c 1 -W ${PING_TIMEOUT}000"   # macOS uses milliseconds for -W
else
  PING_CMD="ping -c 1 -W $PING_TIMEOUT"
fi

# ---------- Scan function -----------------------------------------------------
LIVE_HOSTS=()
TMPDIR_RESULTS=$(mktemp -d)

scan_host() {
  local ip="$1"
  if $PING_CMD "$ip" &>/dev/null; then
    echo "$ip" > "${TMPDIR_RESULTS}/${ip//./_}"
  fi
}

export -f scan_host
export PING_CMD TMPDIR_RESULTS

# ---------- Header ------------------------------------------------------------
echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║         PING SWEEP SCANNER           ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
echo -e "  Target Subnet : ${BOLD}${SUBNET_BASE}.0/24${RESET}"
echo -e "  Resolve DNS   : $RESOLVE_NAMES"
echo -e "  Started       : $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Scanning 254 hosts...\n"

# ---------- Parallel scan -----------------------------------------------------
JOB_COUNT=0
for i in $(seq 1 254); do
  IP="${SUBNET_BASE}.${i}"
  scan_host "$IP" &
  (( JOB_COUNT++ ))
  if (( JOB_COUNT >= MAX_PARALLEL )); then
    wait
    JOB_COUNT=0
  fi
done
wait  # Wait for remaining jobs

# ---------- Collect results ---------------------------------------------------
RESULTS=()
for result_file in "$TMPDIR_RESULTS"/*; do
  [[ -f "$result_file" ]] || continue
  IP=$(cat "$result_file")
  RESULTS+=("$IP")
done

# Sort IPs numerically
IFS=$'\n' SORTED=($(printf '%s\n' "${RESULTS[@]}" | sort -t. -k4 -n)); unset IFS

# ---------- Output results ----------------------------------------------------
LIVE_COUNT=0
OUTPUT_LINES=()

for IP in "${SORTED[@]}"; do
  HOSTNAME_STR=""
  if $RESOLVE_NAMES; then
    HOSTNAME_STR=$(host "$IP" 2>/dev/null | awk '/domain name pointer/ {print $5}' | sed 's/\.$//')
    [[ -z "$HOSTNAME_STR" ]] && HOSTNAME_STR="(no PTR record)"
  fi

  LINE="  ${IP}"
  [[ -n "$HOSTNAME_STR" ]] && LINE="${LINE}  →  ${HOSTNAME_STR}"
  echo -e "${GREEN}✔${RESET} ${LINE}"
  OUTPUT_LINES+=("✔ ${LINE}")
  (( LIVE_COUNT++ ))
done

# Cleanup temp dir
rm -rf "$TMPDIR_RESULTS"

# ---------- Summary -----------------------------------------------------------
echo ""
echo -e "${BOLD}══════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}Live hosts found : ${LIVE_COUNT}${RESET}"
echo -e "  Scan completed   : $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BOLD}══════════════════════════════════════════${RESET}"

# ---------- Optional file output ----------------------------------------------
if [[ -n "$OUTPUT_FILE" ]]; then
  {
    echo "Ping Sweep Results — ${SUBNET_BASE}.0/24"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "----------------------------------------"
    printf '%s\n' "${OUTPUT_LINES[@]}"
    echo "----------------------------------------"
    echo "Live hosts: $LIVE_COUNT"
  } > "$OUTPUT_FILE"
  echo -e "\n  Results saved to: $OUTPUT_FILE"
fi