#!/usr/bin/env python3
"""Hermes/Petasos mobile-push host preflight; read-only unless --apply is given."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

PLUGINS = (
    ("mobile-push", Path("server/mobile-push")),
    ("hermes-mobile-platform", Path("server/hermes-mobile-platform")),
)


def destination(home: Path, name: str) -> Path:
    return (home / "plugins/platforms/hermes-mobile-platform"
            if name == "hermes-mobile-platform" else home / "plugins/mobile-push")


def check_sources(repo: Path) -> None:
    for name, relative in PLUGINS:
        manifest = repo / relative / "plugin.yaml"
        if not manifest.is_file() or manifest.is_symlink():
            raise RuntimeError("Missing or unsafe source manifest: " + name)
        text = manifest.read_text()
        if not re.search(r"^name:\s*" + re.escape(name) + r"\s*$", text, re.M):
            raise RuntimeError("Plugin source name does not match: " + name)
        if name == "mobile-push" and '"dnspython>=2.6,<3"' not in text:
            raise RuntimeError("Required dnspython dependency was omitted")


def hermes(cli: str, args: list[str], timeout: int) -> subprocess.CompletedProcess:
    # Capture ALL subprocess output, since it may contain credential or URL
    # material. Report only the command's exit status.
    result = subprocess.run([cli, *args], capture_output=True, text=True, timeout=timeout)
    print("command=" + " ".join(args[:2]) + " exit=" + str(result.returncode))
    if result.returncode:
        raise RuntimeError("Managed Hermes command failed")
    return result


# Processes that import the plugin code: dashboard (registration/confirm API) and
# gateway (sender, cron adapter). Each keeps the code it loaded at start.
SERVICE_PORTS = (("dashboard", 9119), ("gateway", 8642))


def parse_etime(text: str) -> int:
    """Seconds from ps etime: [[dd-]hh:]mm:ss."""
    text = text.strip()
    days, _, rest = text.rpartition("-")
    parts = [int(p) for p in rest.split(":")]
    while len(parts) < 3:
        parts.insert(0, 0)
    hours, minutes, seconds = parts
    return (int(days) if days else 0) * 86400 + hours * 3600 + minutes * 60 + seconds


def newest_plugin_mtime(home: Path) -> float:
    newest = 0.0
    for name, _ in PLUGINS:
        for path in destination(home, name).rglob("*.py"):
            if "__pycache__" not in path.parts:
                newest = max(newest, path.stat().st_mtime)
    return newest


def is_stale(process_started: float, code_changed: float) -> bool:
    """A process started before the newest plugin file still runs older code."""
    return process_started < code_changed


def check_loaded_code(home: Path, now: float) -> list[str]:
    """Names of running services that predate the installed plugin code."""
    changed = newest_plugin_mtime(home)
    stale = []
    for label, port in SERVICE_PORTS:
        found = subprocess.run(["lsof", "-nP", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"],
                               capture_output=True, text=True, timeout=10).stdout.split()
        for pid in found[:1]:
            etime = subprocess.run(["ps", "-o", "etime=", "-p", pid],
                                   capture_output=True, text=True, timeout=10).stdout
            if etime.strip() and is_stale(now - parse_etime(etime), changed):
                stale.append(label)
    print("services_running_old_plugin_code=" + (",".join(stale) or "none"))
    return stale


def run_preflight(repo: Path, home: Path, cli: str,
                  apply: bool, install_missing: bool) -> None:
    check_sources(repo)
    if not home.is_dir() or home.is_symlink():
        raise RuntimeError("Hermes home missing or unsafe")
    missing = [(name, relative) for name, relative in PLUGINS
               if not (destination(home, name) / "plugin.yaml").is_file()]
    print("missing_plugins=" + (",".join(name for name, _ in missing) or "none"))
    if missing and not (apply and install_missing):
        raise RuntimeError("Install the missing plugins first")
    if missing:
        service = subprocess.run([cli, "status"], capture_output=True, text=True, timeout=30)
        running = any("gateway:" in l.lower() and "running" in l.lower()
                      and "not running" not in l.lower()
                      for l in service.stdout.splitlines())
        if running:
            raise RuntimeError("Refusing to modify plugin files with a running gateway")
        for name, relative in missing:
            hermes(cli, ["plugins", "install", str((repo / relative).resolve())], 180)
            hermes(cli, ["plugins", "enable", name], 90)
    if apply:
        hermes(cli, ["pm", "install"], 600)
    hermes(cli, ["pm", "status"], 90)
    import time
    if check_loaded_code(home, time.time()):
        # Pairing breaks when the dashboard serves older code than the gateway sends with.
        raise RuntimeError(
            "Restart services after a plugin update: 'hermes gateway restart' and "
            "'launchctl kickstart -k gui/$(id -u)/ai.hermes.serve-tailnet'"
        )
    print("managed_dependency_sync=" + ("complete" if apply else "not_modified"))
    print("secrets_modified=false")
    print("gateway_restarted=false")
    print("dashboard_restarted=false")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--home", type=Path, default=Path(os.environ.get("HERMES_HOME", "~/.hermes")))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--install-missing", action="store_true")
    options = parser.parse_args()
    if options.install_missing and not options.apply:
        parser.error("--install-missing requires --apply")
    cli = shutil.which("hermes") or str(Path.home() / ".local/bin/hermes")
    if not Path(cli).is_file():
        print("Hermes CLI not found", file=sys.stderr)
        return 1
    try:
        run_preflight(options.repo.resolve(), options.home.expanduser().resolve(),
                      cli, options.apply, options.install_missing)
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print("preflight_failed=" + type(error).__name__, file=sys.stderr)
        return 1
    print("preflight=passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
