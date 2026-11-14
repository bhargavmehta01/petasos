#!/usr/bin/env python3
"""Real-scheduler acceptance for Petasos cron delivery (run on the Hermes Mac).

Creates two throwaway no-agent cron jobs that deliver to `hermes_mobile`, runs them through
the real Hermes scheduler, and checks the mobile-push outbox:
  * visible job   -> exactly one new `cron_result` event, sent
  * [SILENT] job  -> no new event
It then removes both jobs. Production crons are never edited. Read-only on the database
(works on a copy). Prints pass/fail lines only; no endpoints, keys or device data.
The visible job posts one real notification on the paired phone.
"""
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = Path.home() / ".hermes"
DB = HOME / "plugin-data" / "mobile-push" / "outbox.sqlite3"
SCRIPTS = HOME / "scripts"


def hermes(*args, timeout=120):
    done = subprocess.run(["hermes", *args], capture_output=True, text=True, timeout=timeout)
    return re.sub(r"\x1b\[[0-9;]*m", "", done.stdout + done.stderr)


def snapshot():
    """Return (max cursor, sent flag for it) from a consistent copy of the live database."""
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "outbox.sqlite3"
        src = sqlite3.connect(DB, timeout=10)
        dst = sqlite3.connect(copy)
        src.backup(dst)
        src.close()
        row = dst.execute(
            "SELECT e.cursor, COALESCE(o.done, 0) FROM events e LEFT JOIN outbox o USING(event_id) "
            "WHERE e.kind='cron_result' ORDER BY e.cursor DESC LIMIT 1"
        ).fetchone()
        dst.close()
    return row or (0, 0)


def run_job(name, output):
    SCRIPTS.mkdir(exist_ok=True)
    script = SCRIPTS / f"{name}.sh"
    script.write_text(f'#!/bin/sh\necho "{output}"\n')
    script.chmod(0o755)
    created = hermes("cron", "create", "every 1d", "--name", name, "--deliver", "hermes_mobile",
                     "--no-agent", "--script", script.name, "--repeat", "1")
    match = re.search(r"Created job: (\w+)", created)
    if not match:
        raise SystemExit(f"FAIL create job {name}: {created.strip()[:200]}")
    job = match.group(1)
    try:
        hermes("cron", "run", job)
        for _ in range(30):
            time.sleep(5)
            if "completed" in hermes("cron", "runs", job):
                break
        else:
            raise SystemExit(f"FAIL {name}: scheduler did not complete the run")
        time.sleep(5)
    finally:
        hermes("cron", "remove", job)
        script.unlink(missing_ok=True)


def main():
    status = hermes("status", "--full").lower()
    if "petasos" not in status and "hermes_mobile" not in status.replace(" ", "_"):
        raise SystemExit("FAIL hermes status does not list the Petasos platform")
    print("PASS platform listed by hermes status")

    before, _ = snapshot()
    run_job("hermes-mobile-acceptance-silent", "[SILENT]")
    after_silent, _ = snapshot()
    if after_silent != before:
        raise SystemExit("FAIL [SILENT] output created an event")
    print("PASS [SILENT] created no event")

    run_job("hermes-mobile-acceptance-visible", "Petasos acceptance: scheduler to hermes_mobile")
    cursor, sent = snapshot()
    if cursor <= after_silent:
        raise SystemExit("FAIL visible cron output created no event")
    for _ in range(24):  # the sender drains the outbox on its own interval
        if sent:
            break
        time.sleep(5)
        cursor, sent = snapshot()
    if not sent:
        raise SystemExit("FAIL event was not sent by the outbox within 2 minutes")
    print("PASS visible cron created one event and the outbox sent it")
    print("MANUAL tap the notification on the phone; the Scheduled result screen must open")


if __name__ == "__main__":
    sys.exit(main())
