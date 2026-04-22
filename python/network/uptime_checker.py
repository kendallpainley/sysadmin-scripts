#!/usr/bin/env python3
"""
HTTP/HTTPS uptime monitor. Checks a list of URLs at regular intervals,
records response time and status, and sends alerts via Slack webhook or
email when a site goes down or recovers.

Usage:
    python uptime_checker.py --config sites.json [--interval 60] [--log out.csv]

Config file format (sites.json):
    [
      {"name": "My App",    "url": "https://myapp.example.com",      "timeout": 10},
      {"name": "API",       "url": "https://api.example.com/health", "timeout": 5},
      {"name": "Blog",      "url": "https://blog.example.com",       "timeout": 10}
    ]
"""

import argparse
import csv
import json
import os
import smtplib
import sys
import time
from datetime import datetime
from email.mime.text import MIMEText
from pathlib import Path
from typing import Optional

try:
    import requests
    from requests.exceptions import RequestException
except ImportError:
    sys.exit("Missing dependency: pip install requests")

# ── Config ────────────────────────────────────────────────────────────────────

DEFAULT_INTERVAL     = 60    # seconds between check rounds
DEFAULT_TIMEOUT      = 10    # per-request timeout in seconds
STATUS_DOWN_THRESHOLD = 2    # consecutive failures before alerting

# HTTP codes considered "up"
OK_CODES = {200, 201, 204, 301, 302, 304}

# ── Colors (ANSI, works in most terminals) ────────────────────────────────────
GREEN  = "\033[92m";  YELLOW = "\033[93m"
RED    = "\033[91m";  CYAN   = "\033[96m"
BOLD   = "\033[1m";   RESET  = "\033[0m"

# ── Alerting ──────────────────────────────────────────────────────────────────

def send_slack_alert(webhook_url: str, message: str) -> None:
    try:
        resp = requests.post(webhook_url, json={"text": message}, timeout=10)
        resp.raise_for_status()
    except RequestException as e:
        print(f"{RED}[ALERT] Slack notification failed: {e}{RESET}")


def send_email_alert(
    subject: str, body: str,
    to: str, smtp_host: str, smtp_port: int,
    username: str, password: str, from_addr: str
) -> None:
    try:
        msg = MIMEText(body)
        msg["Subject"] = subject
        msg["From"]    = from_addr
        msg["To"]      = to

        with smtplib.SMTP(smtp_host, smtp_port) as smtp:
            smtp.starttls()
            smtp.login(username, password)
            smtp.sendmail(from_addr, [to], msg.as_string())
    except Exception as e:
        print(f"{RED}[ALERT] Email notification failed: {e}{RESET}")


# ── Check engine ──────────────────────────────────────────────────────────────

def check_url(url: str, timeout: int = DEFAULT_TIMEOUT) -> dict:
    """Check a single URL and return a result dict."""
    result = {
        "url":           url,
        "timestamp":     datetime.now().isoformat(),
        "status_code":   None,
        "response_ms":   None,
        "up":            False,
        "error":         None,
    }
    start = time.monotonic()
    try:
        resp = requests.get(url, timeout=timeout, allow_redirects=True,
                            headers={"User-Agent": "UptimeChecker/1.0"})
        elapsed_ms = round((time.monotonic() - start) * 1000)
        result["status_code"] = resp.status_code
        result["response_ms"] = elapsed_ms
        result["up"]          = resp.status_code in OK_CODES
        if not result["up"]:
            result["error"] = f"HTTP {resp.status_code}"
    except requests.Timeout:
        result["error"] = f"Timeout after {timeout}s"
    except requests.ConnectionError as e:
        result["error"] = f"Connection error: {e}"
    except RequestException as e:
        result["error"] = str(e)

    return result


# ── Monitoring loop ───────────────────────────────────────────────────────────

class SiteState:
    """Tracks consecutive failures and current up/down state for a site."""
    def __init__(self, name: str, url: str):
        self.name      = name
        self.url       = url
        self.is_up     = True        # Assume up at start
        self.fail_streak = 0
        self.alerted   = False

    def update(self, result: dict) -> Optional[str]:
        """Returns an alert message string if state changed, else None."""
        if result["up"]:
            if not self.is_up:
                self.is_up = True
                self.fail_streak = 0
                self.alerted = False
                return f"✅ RECOVERED: {self.name} ({self.url}) is back UP."
            self.fail_streak = 0
            return None
        else:
            self.fail_streak += 1
            if self.fail_streak >= STATUS_DOWN_THRESHOLD and not self.alerted:
                self.is_up   = False
                self.alerted = True
                return (f"🚨 DOWN: {self.name} ({self.url}) — "
                        f"{result['error']} — {self.fail_streak} consecutive failures.")
            return None


def run_checks(sites: list, states: dict, config: dict, log_writer=None) -> None:
    """Run one round of checks across all sites."""
    ts  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"\n{CYAN}{BOLD}── Check Round: {ts} ──{RESET}")

    for site in sites:
        name    = site.get("name", site["url"])
        url     = site["url"]
        timeout = site.get("timeout", DEFAULT_TIMEOUT)

        result  = check_url(url, timeout)
        state   = states[url]
        alert   = state.update(result)

        # Console output
        status_str  = f"HTTP {result['status_code']}" if result["status_code"] else result["error"]
        resp_str    = f"{result['response_ms']}ms" if result["response_ms"] else "—"
        icon        = f"{GREEN}✔{RESET}" if result["up"] else f"{RED}✘{RESET}"
        streak_warn = (f"  {YELLOW}⚠ fail streak: {state.fail_streak}{RESET}"
                       if state.fail_streak > 0 else "")

        print(f"  {icon} {BOLD}{name:<25}{RESET}  {status_str:<12}  {resp_str:<10}{streak_warn}")

        # Log to CSV
        if log_writer:
            log_writer.writerow({
                "timestamp":   result["timestamp"],
                "name":        name,
                "url":         url,
                "up":          result["up"],
                "status_code": result["status_code"] or "",
                "response_ms": result["response_ms"] or "",
                "error":       result["error"] or "",
            })

        # Fire alerts
        if alert:
            print(f"\n  {BOLD}>>> {alert}{RESET}\n")
            slack_hook = config.get("slack_webhook")
            if slack_hook:
                send_slack_alert(slack_hook, alert)
            email_cfg = config.get("email")
            if email_cfg:
                send_email_alert(
                    subject   = f"[UPTIME] {alert[:60]}",
                    body      = alert,
                    to        = email_cfg["to"],
                    smtp_host = email_cfg["smtp_host"],
                    smtp_port = email_cfg.get("smtp_port", 587),
                    username  = email_cfg["username"],
                    password  = email_cfg["password"],
                    from_addr = email_cfg["from"],
                )


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="HTTP uptime monitor")
    parser.add_argument("--config",   required=True,    help="Path to sites JSON config")
    parser.add_argument("--interval", type=int,
                        default=int(os.getenv("UPTIME_INTERVAL", DEFAULT_INTERVAL)),
                        help=f"Check interval in seconds (default: {DEFAULT_INTERVAL})")
    parser.add_argument("--log",      default="",        help="CSV log output path")
    parser.add_argument("--once",     action="store_true",
                        help="Run one check round and exit")
    args = parser.parse_args()

    # Load config
    config_path = Path(args.config)
    if not config_path.exists():
        # Create a sample config if it doesn't exist
        sample = {
            "sites": [
                {"name": "Google",   "url": "https://www.google.com",  "timeout": 10},
                {"name": "GitHub",   "url": "https://github.com",       "timeout": 10},
                {"name": "Cloudflare","url":"https://1.1.1.1",          "timeout": 5},
            ]
        }
        config_path.write_text(json.dumps(sample, indent=2))
        print(f"Sample config created: {config_path}")

    raw = json.loads(config_path.read_text())

    # Support both flat list and dict with "sites" key
    sites  = raw if isinstance(raw, list) else raw.get("sites", [])
    config = raw if isinstance(raw, dict) else {}

    if not sites:
        sys.exit("No sites found in config file.")

    # Initialize state tracking
    states = {s["url"]: SiteState(s.get("name", s["url"]), s["url"]) for s in sites}

    print(f"\n{BOLD}╔══════════════════════════════════════════╗{RESET}")
    print(f"{BOLD}║         UPTIME CHECKER                  ║{RESET}")
    print(f"{BOLD}╚══════════════════════════════════════════╝{RESET}")
    print(f"  Monitoring {len(sites)} site(s)  |  Interval: {args.interval}s")
    if args.log:
        print(f"  Logging to: {args.log}")
    print(f"  Press Ctrl+C to stop.\n")

    # Open CSV log if requested
    log_file   = open(args.log, "a", newline="") if args.log else None
    log_writer = None
    if log_file:
        fieldnames = ["timestamp", "name", "url", "up", "status_code", "response_ms", "error"]
        log_writer = csv.DictWriter(log_file, fieldnames=fieldnames)
        if log_file.tell() == 0:
            log_writer.writeheader()

    try:
        if args.once:
            run_checks(sites, states, config, log_writer)
        else:
            while True:
                run_checks(sites, states, config, log_writer)
                time.sleep(args.interval)
    except KeyboardInterrupt:
        print(f"\n{BOLD}{GREEN}Uptime monitor stopped.{RESET}\n")
    finally:
        if log_file:
            log_file.close()


if __name__ == "__main__":
    main()