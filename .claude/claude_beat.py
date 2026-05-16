#!/usr/bin/env python3
"""
claude_beat - OS-native heartbeat scheduler (launchd / schtasks / crontab).

Commands:
    python claude_beat.py test       Run commands once and print output
    python claude_beat.py run        Run commands once and print output
    python claude_beat.py install    Register schedule (launchd on macOS, cron on Linux)
    python claude_beat.py add        Register schedule
    python claude_beat.py uninstall  Remove schedule from OS
    python claude_beat.py remove     Remove schedule from OS
    python claude_beat.py status     Show if scheduled + last log time
"""

import os
import sys
import subprocess
import shutil
from datetime import datetime

# =============================================================================
# CONFIG
# =============================================================================

TASK_NAME = "claude_beat"
INTERVAL_MINUTES = 60  # Heartbeat interval in minutes
RUN_AT_MINUTE = 1      # Run at this minute past the hour

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(SCRIPT_DIR, "cron_claude_beat.log.txt")
GLM_SETTINGS = os.path.expanduser("~/.claude/env.glm.json")

CLAUDE_BIN = shutil.which("claude") or os.path.expanduser("~/.local/bin/claude")
BASE_CMD = [
    CLAUDE_BIN,
    "--model", "haiku",
    "--no-session-persistence",
    "-p", "Hello",
]

COMMANDS = [
    ([*BASE_CMD], "cc"),
    ([*BASE_CMD, "--settings", GLM_SETTINGS], "glm"),
]  

IS_WIN = sys.platform == "win32"
IS_MAC = sys.platform == "darwin"

PLIST_LABEL = TASK_NAME
PLIST_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{PLIST_LABEL}.plist")

if IS_WIN:
    os.environ["NODE_TLS_REJECT_UNAUTHORIZED"] = "0"


# =============================================================================
# RUN
# =============================================================================

def run_test():
    """Execute all commands once and log output."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    # Remove CLAUDECODE to avoid nested session check
    env = os.environ.copy()
    env.pop("CLAUDECODE", None)
    for cmd, label in COMMANDS:
        try:
            if not cmd[0]:
                raise RuntimeError("claude binary not found in PATH")
            kwargs = dict(capture_output=True, text=True,
                          timeout=300, env=env, stdin=subprocess.DEVNULL)
            if IS_WIN:
                kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
            result = subprocess.run(cmd, **kwargs)

            stdout = result.stdout.strip()
            stderr = result.stderr.strip()
            if stdout and stderr:
                output = f"stdout: {stdout} | stderr: {stderr}"
            else:
                output = stdout or stderr or f"(no output, return code: {result.returncode})"
            prefix = "ERROR" if result.returncode != 0 else label
            entry = f"{prefix} - {timestamp} - {label + ': ' if prefix == 'ERROR' else ''}{output}\n"
        except subprocess.TimeoutExpired:
            entry = f"ERROR - {timestamp} - {label}: (command timed out)\n"
        except Exception as e:
            entry = f"ERROR - {timestamp} - {label}: {e}\n"

        try:
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(entry)
        except OSError as e:
            print(f"ERROR - {timestamp} - log: {e}")
        print(entry, end="")


# =============================================================================
# INSTALL / UNINSTALL
# =============================================================================

def _script_cmd():
    return f'"{sys.executable}" "{os.path.abspath(__file__)}" run'


def install():
    """Register schedule using the platform's native scheduler."""
    if IS_WIN:
        subprocess.run([
            "schtasks", "/create", "/tn", TASK_NAME,
            "/sc", "hourly", "/mo", "1", "/st", f"00:{RUN_AT_MINUTE:02d}",
            "/tr", _script_cmd(),
            "/f",
        ], check=True)
    elif IS_MAC:
        launchd_install()
    else:
        crontab_add()
    print("Installed. Run 'python claude_beat.py status' to verify.")


def uninstall():
    """Remove schedule from the OS."""
    if IS_WIN:
        subprocess.run([
            "schtasks", "/delete", "/tn", TASK_NAME, "/f",
        ], check=True)
    elif IS_MAC:
        launchd_remove()
    else:
        crontab_remove()
    print("Uninstalled.")


# =============================================================================
# --- launchd helpers (macOS) ---
# =============================================================================

def _plist_content():
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{sys.executable}</string>
        <string>{os.path.abspath(__file__)}</string>
        <string>run</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Minute</key>
        <integer>{RUN_AT_MINUTE}</integer>
    </dict>
    <key>WorkingDirectory</key>
    <string>{SCRIPT_DIR}</string>
</dict>
</plist>
"""


def launchd_install():
    # Clean up old crontab entry if present
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        if _cron_tag() in result.stdout:
            crontab_remove()
            print("Removed old crontab entry.")
    except Exception:
        pass
    # Unload existing if loaded
    if os.path.exists(PLIST_PATH):
        subprocess.run(["launchctl", "unload", PLIST_PATH], capture_output=True)
    with open(PLIST_PATH, "w", encoding="utf-8") as f:
        f.write(_plist_content())
    subprocess.run(["launchctl", "load", "-w", PLIST_PATH], check=True)


def launchd_remove():
    if os.path.exists(PLIST_PATH):
        subprocess.run(["launchctl", "unload", "-w", PLIST_PATH], capture_output=True)
        os.remove(PLIST_PATH)


# =============================================================================
# --- crontab helpers (Linux) ---
# =============================================================================

def _cron_tag():
    return f"# heartbeat:{os.path.abspath(__file__)}"


def _cron_entry():
    script = os.path.abspath(__file__)
    directory = os.path.dirname(script)
    return f'{RUN_AT_MINUTE} * * * * cd "{directory}" && "{sys.executable}" "{script}" run {_cron_tag()}'


def crontab_add():
    existing = subprocess.run(
        ["crontab", "-l"], capture_output=True, text=True
    ).stdout
    tag = _cron_tag()
    # Remove old entry if present, then add new
    lines = [l for l in existing.splitlines() if tag not in l]
    lines.append(_cron_entry())
    subprocess.run(
        ["crontab", "-"], input="\n".join(lines) + "\n", text=True, check=True
    )


def crontab_remove():
    existing = subprocess.run(
        ["crontab", "-l"], capture_output=True, text=True
    ).stdout
    tag = _cron_tag()
    lines = [l for l in existing.splitlines() if tag not in l]
    subprocess.run(
        ["crontab", "-"], input="\n".join(lines) + "\n", text=True, check=True
    )


# =============================================================================
# STATUS
# =============================================================================

def status():
    """Show whether the task is scheduled, next run time, and last log."""
    # Check schedule + next run
    if IS_WIN:
        result = subprocess.run(
            ["schtasks", "/query", "/tn", TASK_NAME, "/fo", "list", "/v"],
            capture_output=True, text=True,
        )
        scheduled = result.returncode == 0
        if scheduled:
            for line in result.stdout.splitlines():
                if "Next Run Time:" in line:
                    next_run = line.split(":", 1)[1].strip()
                    break
            else:
                next_run = "(unknown)"
        else:
            next_run = None
    elif IS_MAC:
        result = subprocess.run(
            ["launchctl", "list", PLIST_LABEL],
            capture_output=True, text=True,
        )
        scheduled = result.returncode == 0
        next_run = f"hourly at :{RUN_AT_MINUTE:02d} (launchd)" if scheduled else None
    else:
        result = subprocess.run(
            ["crontab", "-l"], capture_output=True, text=True,
        )
        scheduled = _cron_tag() in result.stdout
        if scheduled:
            from datetime import timedelta
            now = datetime.now()
            minutes_past = now.minute % INTERVAL_MINUTES
            next_interval = now.replace(second=0, microsecond=0) + timedelta(minutes=INTERVAL_MINUTES - minutes_past)
            next_run = next_interval.strftime("%Y-%m-%d %H:%M:%S")
        else:
            next_run = None

    print(f"Scheduled: {'yes' if scheduled else 'no'}")
    if scheduled and next_run:
        print(f"Next run: {next_run}")

    # Last log time
    if os.path.exists(LOG_FILE):
        mtime = os.path.getmtime(LOG_FILE)
        last = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
        print(f"Last log update: {last}")
    else:
        print("No log file yet.")


# =============================================================================
# MAIN
# =============================================================================

def main():
    if len(sys.argv) < 2:
        print("""
        Usage: python claude_beat.py
        Commands:   test/run
                    install/add/setup/enable/start
                    uninstall/remove/disable/stop
                    status
        """)
        sys.exit(1)

    cmd = sys.argv[1].lower()
    if cmd in ("test", "run"):
        run_test()
    elif cmd in ("install", "add", "setup", "enable", "start"):
        install()
    elif cmd in ("uninstall", "remove", "disable", "stop"):
        uninstall()
    elif cmd == "status":
        status()
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
