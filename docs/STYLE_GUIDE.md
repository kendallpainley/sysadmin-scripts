# Style Guide

Standards for writing consistent, readable, and maintainable scripts across all three languages in this repo.

---

## Universal Rules (All Languages)

- **One script, one job.** Each script should do one thing well. If it's doing three things, split it.
- **Fail loudly.** Scripts should exit with a non-zero code on failure and print a clear error message.
- **No hardcoded secrets.** Passwords, API keys, and tokens must come from environment variables or a config file — never committed to the repo.
- **Every script needs a header block.** See the templates below.
- **Use long-form flags in examples.** Write `--output` not `-o` in usage strings so intent is obvious.
- **Timestamp your logs.** Any script that writes log output should include `YYYY-MM-DD HH:mm:ss` timestamps.

---

## Bash

### Header Template
```bash
#!/usr/bin/env bash
# ==============================================================================
# script_name.sh
# Description : One or two sentence description of what this script does.
# Author      : Your Name / GitHub handle
# Usage       : ./script_name.sh [--option value]
# Platform    : macOS / Linux / Both
# ==============================================================================
```

### Safety Flags
Always include at the top of every script:
```bash
set -euo pipefail
```
- `-e` — exit on error
- `-u` — treat unset variables as errors
- `-o pipefail` — catch errors in piped commands

### Naming
- Script files: `snake_case.sh`
- Variables: `UPPER_CASE` for globals/constants, `lower_case` for locals
- Functions: `lower_case_with_underscores`

### Variables
```bash
# Good — quoted, clearly named
OUTPUT_FILE="${1:-/tmp/default.txt}"

# Bad — unquoted, cryptic
f=$1
```

### Functions
```bash
# Always declare locals inside functions
parse_args() {
  local input="$1"
  local output="$2"
  # ...
}
```

### Error handling
```bash
# Provide context in error messages
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: config file not found: $CONFIG_FILE" >&2
  exit 1
fi
```

### Output
- Use `>&2` for error messages (stderr)
- Use color sparingly — always provide a plain fallback
- Check `[[ -t 1 ]]` if you want to disable color when piped

---

## PowerShell

### Header Template
```powershell
# ==============================================================================
# script_name.ps1
# Description : One or two sentence description of what this script does.
# Author      : Your Name / GitHub handle
# Usage       : .\script_name.ps1 [-Parameter Value]
# Requires    : PowerShell 7+ (cross-platform) or Windows PowerShell 5.1+
# ==============================================================================
```

### Script Structure
Use `[CmdletBinding()]` and `param()` blocks on every script:
```powershell
[CmdletBinding()]
param(
    [string]$Target   = "localhost",
    [int]$Timeout     = 30,
    [switch]$Verbose
)
```

### Naming
- Script files: `PascalCase.ps1`
- Parameters and variables: `PascalCase`
- Internal helper functions: `Verb-Noun` (following PowerShell conventions)

### Error Handling
```powershell
# Prefer try/catch over $? checks
try {
    Start-Service -Name $ServiceName -ErrorAction Stop
} catch {
    Write-Error "Failed to start ${ServiceName}: $_"
    exit 1
}
```

Set this at the top of scripts that should halt on any error:
```powershell
$ErrorActionPreference = "Stop"
```

### Output
- Use `Write-Host` for user-facing display output
- Use `Write-Output` for pipeline-compatible data output
- Use `Write-Error` / `Write-Warning` for diagnostics
- Avoid `echo` — it's an alias and less explicit

### Compatibility
- Always test on PowerShell 7+ for cross-platform scripts
- If Windows-only, note it clearly in the header and use `#Requires -Version 5.1`

---

## Python

### Header Template
```python
#!/usr/bin/env python3
"""
script_name.py
==============
One or two sentence description of what this script does.

Usage:
    python script_name.py [--option value]

Requirements:
    pip install requests psutil
"""
```

### Naming
- Script files: `snake_case.py`
- Variables and functions: `snake_case`
- Constants: `UPPER_CASE`
- Classes: `PascalCase`

### Structure
Every script should follow this order:
1. Docstring
2. Standard library imports
3. Third-party imports (with helpful error on missing)
4. Constants / config
5. Helper functions
6. Main logic
7. `if __name__ == "__main__":` guard

### Dependency Imports
Give a clear install hint if a dependency is missing:
```python
try:
    import psutil
except ImportError:
    sys.exit("Missing dependency: pip install psutil")
```

### Argument Parsing
Use `argparse` for all CLI scripts — no positional-only argument scripts:
```python
parser = argparse.ArgumentParser(description="What this script does")
parser.add_argument("--target", required=True, help="Target hostname or IP")
parser.add_argument("--timeout", type=int, default=10, help="Timeout in seconds")
args = parser.parse_args()
```

### Error Handling
```python
# Be specific with exception types
try:
    result = requests.get(url, timeout=args.timeout)
    result.raise_for_status()
except requests.Timeout:
    sys.exit(f"Error: request to {url} timed out after {args.timeout}s")
except requests.HTTPError as e:
    sys.exit(f"Error: HTTP {e.response.status_code} from {url}")
```

### Logging
Use the `logging` module for scripts that run unattended:
```python
import logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  [%(levelname)s]  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
log = logging.getLogger(__name__)
```

### Formatting
- Follow PEP 8
- Max line length: 100 characters
- Use `black` for auto-formatting: `black script_name.py`

---

## Commit Messages

Use this format:
```
Action: short description — what and why

Action options:
  Add      → new script
  Fix      → bug fix
  Update   → improving an existing script
  Remove   → deleting something
  Docs     → documentation only
  Refactor → restructuring without behavior change
```

Examples:
```
Add: ping_sweep.sh — parallel /24 subnet scanner with DNS resolution
Fix: backup_tar.sh — handle paths with spaces in source directory
Update: system_monitor.py — add swap memory display to dashboard
Docs: SETUP.md — add PyCharm plugin recommendations
```

---

## What Not to Do

- Don't use `rm -rf` without explicit user confirmation
- Don't suppress all errors with `2>/dev/null` or `-ErrorAction SilentlyContinue` globally
- Don't write scripts that only work on your specific machine (hardcoded paths, usernames)
- Don't commit `.env` files, logs, or generated output — keep `.gitignore` up to date
- Don't use deprecated syntax (`#!/bin/sh` for bash-specific scripts, `python` instead of `python3`)