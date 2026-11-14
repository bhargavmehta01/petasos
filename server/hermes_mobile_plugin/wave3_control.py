"""Wave 3: capability probe and always-allow approval rules for the Petasos app.

Routes (mounted under /api/plugins/hermes_mobile/):

  GET    w3/capabilities             -> what this plugin supports
  GET    w3/approvals/rules          -> {"rules": [{pattern, risk, expires_at, added_at, note}]}
  POST   w3/approvals/rules          {"pattern": str, "ttl_hours"?: num, "expires_at"?: epoch, "note"?: str}
  DELETE w3/approvals/rules?pattern=...

Rules are Hermes' own permanent approvals: the ``command_allowlist`` list in the
profile's config.yaml (what "Always allow" on an approval prompt writes). Hermes
re-reads hand edits to that list, so changes here apply without a restart.
This plugin adds expiry and notes in its own state file and removes expired
patterns from ``command_allowlist`` on every read and at session start.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Optional

HIGH = (
    "rm ", "rm -", "rmdir", "sudo", "mkfs", "dd ", "chmod", "chown", "shutdown", "reboot",
    "kill", "curl", "wget", "| sh", "|sh", "bash -c", "drop ", "truncate", "format",
    "git push --force", "reset --hard", "systemctl", "iptables", "ssh ",
)
MEDIUM = (
    "git push", "git commit", "git reset", "npm install", "pip install", "apt", "brew", "docker",
    "mv ", "cp ", "write", "send", "email", "delete", "post", "deploy", "crontab",
)


def risk_for(pattern: str) -> str:
    p = pattern.lower()
    if any(k in p for k in HIGH):
        return "high"
    if any(k in p for k in MEDIUM):
        return "medium"
    return "low"


def _home() -> Path:
    override = os.environ.get("HERMES_MOBILE_PLUGIN_HOME")
    if override:
        return Path(override)
    from hermes_constants import get_hermes_home

    return Path(get_hermes_home())


def _state_path() -> Path:
    return _home() / "plugin-data" / "hermes_mobile" / "wave3_rules.json"


def _load_state() -> dict[str, Any]:
    try:
        data = json.loads(_state_path().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _save_state(state: dict[str, Any]) -> None:
    path = _state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1, sort_keys=True), encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(path)


# Config access: Hermes' config helpers when present, plain YAML otherwise (tests).


def _read_allowlist() -> list[str]:
    if not os.environ.get("HERMES_MOBILE_PLUGIN_HOME"):
        try:
            from hermes_cli.config import load_config

            value = (load_config() or {}).get("command_allowlist") or []
            return [str(v) for v in value if isinstance(v, str)]
        except Exception:
            pass
    import yaml

    path = _home() / "config.yaml"
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except OSError:
        data = {}
    value = data.get("command_allowlist") or []
    return [str(v) for v in value if isinstance(v, str)]


def _write_allowlist(patterns: list[str]) -> None:
    if not os.environ.get("HERMES_MOBILE_PLUGIN_HOME"):
        try:
            from hermes_cli.config import load_config, save_config

            cfg = load_config() or {}
            cfg["command_allowlist"] = patterns
            save_config(cfg)
            return
        except Exception:
            pass
    import yaml

    path = _home() / "config.yaml"
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except OSError:
        data = {}
    data["command_allowlist"] = patterns
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")


class RuleError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def sweep_expired(now: Optional[float] = None) -> list[str]:
    """Remove expired patterns from command_allowlist. Returns what was removed."""
    now = now or time.time()
    state = _load_state()
    meta = state.get("rules", {})
    expired = [p for p, m in meta.items() if m.get("expires_at") and m["expires_at"] <= now]
    if not expired:
        return []
    allow = _read_allowlist()
    kept = [p for p in allow if p not in expired]
    if kept != allow:
        _write_allowlist(kept)
    for p in expired:
        meta.pop(p, None)
    state["rules"] = meta
    _save_state(state)
    return expired


def list_rules() -> list[dict[str, Any]]:
    sweep_expired()
    meta = _load_state().get("rules", {})
    out = []
    for p in _read_allowlist():
        m = meta.get(p, {})
        out.append(
            {
                "pattern": p,
                "risk": risk_for(p),
                "expires_at": m.get("expires_at"),
                "added_at": m.get("added_at"),
                "note": m.get("note"),
            }
        )
    order = {"high": 0, "medium": 1, "low": 2}
    out.sort(key=lambda r: (order[r["risk"]], r["pattern"]))
    return out


def add_rule(pattern: str, expires_at: Optional[float] = None, note: Optional[str] = None) -> dict[str, Any]:
    pattern = (pattern or "").strip()
    if not pattern or len(pattern) > 300:
        raise RuleError(400, "pattern must be 1-300 characters")
    if expires_at is not None and expires_at <= time.time():
        raise RuleError(400, "expiry must be in the future")
    allow = _read_allowlist()
    if pattern not in allow:
        _write_allowlist(allow + [pattern])
    state = _load_state()
    meta = state.setdefault("rules", {})
    meta[pattern] = {"added_at": time.time(), "expires_at": expires_at, "note": (note or None)}
    _save_state(state)
    return {"pattern": pattern, "risk": risk_for(pattern), "expires_at": expires_at}


def remove_rule(pattern: str) -> None:
    allow = _read_allowlist()
    if pattern not in allow:
        raise RuleError(404, "No such rule")
    _write_allowlist([p for p in allow if p != pattern])
    state = _load_state()
    state.get("rules", {}).pop(pattern, None)
    _save_state(state)


def capabilities() -> dict[str, Any]:
    return {
        "plugin": True,
        "version": 1,
        "memory_write": True,
        "incognito": True,
        "approval_rules": True,
        "cron_runs": True,
    }


def _on_session_start(**_: Any) -> None:
    try:
        sweep_expired()
    except Exception:
        pass


def register_hooks(ctx) -> None:
    ctx.register_hook("on_session_start", _on_session_start)


try:
    from fastapi import APIRouter, Body, HTTPException
except ImportError:
    _router = None
else:
    _router = APIRouter(prefix="/w3")

    @_router.get("/capabilities")
    def _caps():
        return capabilities()

    @_router.get("/approvals/rules")
    def _rules():
        return {"rules": list_rules()}

    @_router.post("/approvals/rules")
    def _add(body: dict = Body(...)):
        expires = body.get("expires_at")
        ttl = body.get("ttl_hours")
        if expires is None and isinstance(ttl, (int, float)) and ttl > 0:
            expires = time.time() + float(ttl) * 3600
        try:
            return add_rule(str(body.get("pattern", "")), float(expires) if expires else None, body.get("note"))
        except RuleError as e:
            raise HTTPException(e.status, e.message)

    @_router.delete("/approvals/rules")
    def _remove(pattern: str):
        try:
            remove_rule(pattern)
        except RuleError as e:
            raise HTTPException(e.status, e.message)
        return {"ok": True}


FEATURES = ["w3_capabilities", "w3_approval_rules"]


def register(router) -> None:
    """Called by registry.register_all with the plugin's root APIRouter."""
    if _router is not None:
        router.include_router(_router)
