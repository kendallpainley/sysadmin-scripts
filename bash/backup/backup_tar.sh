#!/usr/bin/env bash
# ==============================================================================
# Creates a compressed, timestamped tar.gz backup of a source directory. Supports retention policy (auto-delete old backups),
# exclusion patterns, and optional checksum verification.
# Usage       : ./backup_tar.sh --src /path/to/source --dest /path/to/backups [--retain 7] [--exclude "*.log"] [--verify]
# ==============================================================================

set -euo pipefail

# ---------- Colors ------------------------------------------------------------
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ---------- Defaults ----------------------------------------------------------
SOURCE_DIR=""
DEST_DIR=""
RETAIN_DAYS=7
EXCLUDE_PATTERNS=()
VERIFY=false
LOG_FILE=""

# ---------- Usage -------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 --src <source_dir> --dest <dest_dir> [OPTIONS]

Options:
  --src      Source directory to back up (required)
  --dest     Destination directory for backups (required)
  --retain   Number of days to keep old backups (default: 7)
  --exclude  Pattern to exclude, e.g. "*.log" (can use multiple times)
  --verify   Verify archive integrity after creation
  --log      Path to log file (default: stdout only)
  -h         Show this help
EOF
  exit 1
}

# ---------- Argument parsing --------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --src)     SOURCE_DIR="$2"; shift 2 ;;
    --dest)    DEST_DIR="$2"; shift 2 ;;
    --retain)  RETAIN_DAYS="$2"; shift 2 ;;
    --exclude) EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
    --verify)  VERIFY=true; shift ;;
    --log)     LOG_FILE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$SOURCE_DIR" || -z "$DEST_DIR" ]] && { echo "Error: --src and --dest are required."; usage; }
[[ ! -d "$SOURCE_DIR" ]] && { echo "Error: Source directory does not exist: $SOURCE_DIR"; exit 1; }

# ---------- Logging -----------------------------------------------------------
log() {
  local level="$1"; shift
  local msg="$*"
  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  local colored_msg

  case "$level" in
    INFO)  colored_msg="${GREEN}[INFO]${RESET}  $msg" ;;
    WARN)  colored_msg="${YELLOW}[WARN]${RESET}  $msg" ;;
    ERROR) colored_msg="${RED}[ERROR]${RESET} $msg" ;;
    *)     colored_msg="[$level] $msg" ;;
  esac

  echo -e "  ${ts}  ${colored_msg}"
  [[ -n "$LOG_FILE" ]] && echo "  ${ts}  [${level}]  ${msg}" >> "$LOG_FILE"
}

# ---------- Setup -------------------------------------------------------------
mkdir -p "$DEST_DIR"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BASENAME=$(basename "$SOURCE_DIR")
ARCHIVE_NAME="${BASENAME}_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${DEST_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

# ---------- Header ------------------------------------------------------------
echo -e "\n${BOLD}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║         BACKUP MANAGER               ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
echo -e "  Source  : ${BOLD}${SOURCE_DIR}${RESET}"
echo -e "  Dest    : ${BOLD}${DEST_DIR}${RESET}"
echo -e "  Archive : ${ARCHIVE_NAME}"
echo -e "  Retain  : ${RETAIN_DAYS} days\n"

# ---------- Build tar exclusions ----------------------------------------------
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  EXCLUDE_ARGS+=("--exclude=${pattern}")
  log INFO "Excluding pattern: $pattern"
done

# Always exclude common junk
EXCLUDE_ARGS+=(
  "--exclude=.DS_Store"
  "--exclude=__pycache__"
  "--exclude=*.pyc"
  "--exclude=node_modules"
  "--exclude=.git"
)

# ---------- Create archive ----------------------------------------------------
log INFO "Starting backup of: $SOURCE_DIR"

if tar -czf "$ARCHIVE_PATH" "${EXCLUDE_ARGS[@]}" -C "$(dirname "$SOURCE_DIR")" "$BASENAME" 2>/dev/null; then
  ARCHIVE_SIZE=$(du -sh "$ARCHIVE_PATH" | cut -f1)
  log INFO "Archive created successfully — size: ${ARCHIVE_SIZE}"
else
  log ERROR "Failed to create archive. Check permissions and disk space."
  exit 1
fi

# ---------- Checksum ----------------------------------------------------------
log INFO "Generating SHA-256 checksum..."
if command -v sha256sum &>/dev/null; then
  sha256sum "$ARCHIVE_PATH" > "$CHECKSUM_PATH"
elif command -v shasum &>/dev/null; then
  shasum -a 256 "$ARCHIVE_PATH" > "$CHECKSUM_PATH"
else
  log WARN "No sha256sum or shasum found — skipping checksum."
fi

[[ -f "$CHECKSUM_PATH" ]] && log INFO "Checksum saved: ${CHECKSUM_PATH}"

# ---------- Verify archive ----------------------------------------------------
if $VERIFY; then
  log INFO "Verifying archive integrity..."
  if tar -tzf "$ARCHIVE_PATH" &>/dev/null; then
    FILE_COUNT=$(tar -tzf "$ARCHIVE_PATH" | wc -l | xargs)
    log INFO "Archive verified — ${FILE_COUNT} entries found."
  else
    log ERROR "Archive verification FAILED. The archive may be corrupt."
    exit 1
  fi
fi

# ---------- Retention policy --------------------------------------------------
log INFO "Applying retention policy: removing backups older than ${RETAIN_DAYS} days..."

DELETED=0
while IFS= read -r old_backup; do
  rm -f "$old_backup" "${old_backup}.sha256"
  log WARN "Deleted old backup: $(basename "$old_backup")"
  (( DELETED++ ))
done < <(find "$DEST_DIR" -name "${BASENAME}_*.tar.gz" -mtime "+${RETAIN_DAYS}" 2>/dev/null)

if (( DELETED == 0 )); then
  log INFO "No old backups to remove."
else
  log INFO "Removed ${DELETED} old backup(s)."
fi

# ---------- Summary -----------------------------------------------------------
echo ""
echo -e "${BOLD}══════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}Backup complete!${RESET}"
echo -e "  Archive : $ARCHIVE_PATH"
echo -e "  Size    : $ARCHIVE_SIZE"
echo -e "  Done    : $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BOLD}══════════════════════════════════════════${RESET}\n"