# SysAdmin Scripts Repository

> A collection of **PowerShell**, **Bash**, and **Python** scripts for system administration and automation.

---

## Repository Structure

```
sysadmin-scripts/
├── bash/
│   ├── system/          # OS health, disk, CPU, memory monitoring
│   ├── network/         # Connectivity checks, port scanning, DNS tools
│   ├── users/           # User account management & auditing
│   └── backup/          # File backup and archiving scripts
├── powershell/
│   ├── system/          # Windows system info, services, event logs
│   ├── network/         # Network adapters, firewall, ping sweeps
│   ├── users/           # Active Directory, local user management
│   └── backup/          # VSS snapshots, robocopy wrappers
├── python/
│   ├── system/          # Cross-platform monitoring & reporting
│   ├── network/         # Socket tools, API checks, uptime monitors
│   ├── users/           # LDAP/AD queries, CSV user provisioning
│   └── backup/          # Scheduled backups with logging
└── docs/
    ├── STYLE_GUIDE.md
    └── SETUP.md
```

---

### Clone the Repo
```bash
git clone https://github.com/YOUR_USERNAME/sysadmin-scripts.git
cd sysadmin-scripts
```

### Running Bash Scripts
```bash
chmod +x bash/system/health_check.sh
./bash/system/health_check.sh
```

### Running PowerShell Scripts
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
./powershell/system/system_info.ps1
```

### Running Python Scripts
```bash
pip install -r python/requirements.txt
python python/system/monitor.py
```

---

## Script Index

### Bash

| Script | Category | Description |
|--------|----------|-------------|
| `health_check.sh` | system | Full system health report (CPU, RAM, Disk) |
| `disk_alert.sh` | system | Emails alert when disk usage exceeds threshold |
| `port_scan.sh` | network | Lightweight local network port scanner |
| `ping_sweep.sh` | network | Pings a subnet range and reports live hosts |
| `add_user.sh` | users | Creates users with home dirs and SSH keys |
| `audit_logins.sh` | users | Reports last logins and failed attempts |
| `backup_tar.sh` | backup | Compressed tar backup with date stamping |
| `rotate_logs.sh` | backup | Rotates and archives logs older than N days |

### PowerShell

| Script | Category | Description |
|--------|----------|-------------|
| `system_info.ps1` | system | Detailed Windows system info report |
| `service_monitor.ps1` | system | Checks and restarts stopped critical services |
| `firewall_audit.ps1` | network | Lists all active firewall rules |
| `ping_sweep.ps1` | network | Pings IP range, outputs CSV of live hosts |
| `new_local_user.ps1` | users | Creates local user with group assignment |
| `inactive_users.ps1` | users | Finds AD/local accounts inactive for 90+ days |
| `vss_backup.ps1` | backup | Creates VSS snapshot backup |
| `robocopy_sync.ps1` | backup | Mirror sync two directories with logging |

### Python

| Script | Category | Description |
|--------|----------|-------------|
| `system_monitor.py` | system | Live CPU/RAM/Disk dashboard (cross-platform) |
| `process_killer.py` | system | Find and kill processes by name or PID |
| `uptime_checker.py` | network | HTTP uptime monitor with Slack/email alerts |
| `port_scanner.py` | network | Multi-threaded TCP port scanner |
| `user_provisioner.py` | users | Bulk user creation from CSV input |
| `login_auditor.py` | users | Parses auth logs for suspicious activity |
| `backup_manager.py` | backup | Scheduled backups with retention policies |
| `s3_uploader.py` | backup | Uploads backups to AWS S3 with versioning |


---

## License

MIT License — free to use, modify, and distribute with attribution.

---

