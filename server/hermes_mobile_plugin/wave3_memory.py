"""Wave 3: memory manager write API and incognito chats for the Petasos app.

Routes (mounted under /api/plugins/hermes_mobile/):

  GET    w3/memory                  -> {"entries": [...], "limits": {...}}
  POST   w3/memory                  {"target": "user"|"memory", "content": str}
  PUT    w3/memory/{entry_id}       {"content": str}
  DELETE w3/memory/{entry_id}
  POST   w3/memory/{entry_id}/pin   {"pinned": bool}
  GET    w3/incognito               -> {"sessions": [session_id, ...]}
  PUT    w3/incognito/{session_id}  {"enabled": bool}

Entries live in the profile's ``memories/USER.md`` and ``memories/MEMORY.md``
(entries split by ``\\n§\\n``), the same files the built-in ``memory`` tool writes.
Writes go through Hermes' own ``MemoryStore`` when it is importable (same caps,
content scan and file lock); otherwise a locked direct edit is used.

Hooks (registered from the plugin's ``register(ctx)``):

- ``pre_tool_call`` blocks the ``memory`` tool in incognito sessions, and blocks
  ``remove``/``replace`` of an entry the user pinned.
- ``post_tool_call`` records provenance (which chat saved an entry, and when).

Entry ids are a fingerprint of target + content, so an edit gives a new id.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import time
from pathlib import Path
from typing import Any, Optional

DELIMITER = "\n§\n"
TARGETS = {"user": "USER.md", "memory": "MEMORY.md"}
DEFAULT_LIMITS = {"memory": 2200, "user": 1375}
INCOGNITO_BLOCK = (
    "Incognito chat: the user turned memory off for this conversation. "
    "Do not save anything; answer normally."
)
PINNED_BLOCK = "That memory entry is pinned by the user and cannot be changed or removed by the agent."


# ── paths and state ────────────────────────────────────────────────────


def _home() -> Path:
    override = os.environ.get("HERMES_MOBILE_PLUGIN_HOME")  # tests
    if override:
        return Path(override)
    from hermes_constants import get_hermes_home

    return Path(get_hermes_home())


def _memory_dir() -> Path:
    return _home() / "memories"


def _state_path() -> Path:
    return _home() / "plugin-data" / "hermes_mobile" / "wave3_memory.json"


def _load_state() -> dict[str, Any]:
    try:
        data = json.loads(_state_path().read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        pass
    return {}


def _save_state(state: dict[str, Any]) -> None:
    path = _state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1, sort_keys=True), encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(path)


def entry_id(target: str, content: str) -> str:
    return hashlib.sha256(f"{target}:{content.strip()}".encode()).hexdigest()[:16]


def _read_entries(target: str) -> list[str]:
    path = _memory_dir() / TARGETS[target]
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError:
        return []
    return [e.strip() for e in raw.split(DELIMITER) if e.strip()]


@contextlib.contextmanager
def _locked(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.with_suffix(path.suffix + ".lock")
    fd = os.open(lock, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        try:
            import fcntl

            fcntl.flock(fd, fcntl.LOCK_EX)
        except ImportError:  # pragma: no cover - non-POSIX
            pass
        yield
    finally:
        os.close(fd)


def _write_entries(target: str, entries: list[str]) -> None:
    path = _memory_dir() / TARGETS[target]
    tmp = path.with_suffix(".tmp")
    tmp.write_text(DELIMITER.join(entries) + ("\n" if entries else ""), encoding="utf-8")
    tmp.replace(path)


def _store():
    """Hermes' MemoryStore when running inside Hermes, else None."""
    if os.environ.get("HERMES_MOBILE_PLUGIN_HOME"):
        return None
    try:
        from tools.memory_tool import load_on_disk_store

        return load_on_disk_store()
    except Exception:
        return None


def _limits() -> dict[str, int]:
    try:
        from hermes_cli.config import load_config
        from tools.memory_tool import get_builtin_memory_config

        cfg = get_builtin_memory_config(load_config() or {})
        return {
            "memory": int(cfg.get("memory_char_limit", DEFAULT_LIMITS["memory"])),
            "user": int(cfg.get("user_char_limit", DEFAULT_LIMITS["user"])),
        }
    except Exception:
        return dict(DEFAULT_LIMITS)


class MemoryError_(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def _check_store_result(result: Any) -> None:
    if isinstance(result, dict) and result.get("success") is False:
        raise MemoryError_(422, str(result.get("error") or result.get("message") or "Memory write refused"))


# ── operations (plain functions, so tests need no HTTP) ────────────────


def list_entries() -> list[dict[str, Any]]:
    state = _load_state()
    pins = set(state.get("pins", []))
    prov = state.get("provenance", {})
    out = []
    for target in TARGETS:
        for content in _read_entries(target):
            eid = entry_id(target, content)
            out.append(
                {
                    "id": eid,
                    "target": target,
                    "file": TARGETS[target],
                    "content": content,
                    "pinned": eid in pins,
                    "provenance": prov.get(eid),
                }
            )
    out.sort(key=lambda e: (not e["pinned"]))
    return out


def _find(eid: str) -> tuple[str, str]:
    for target in TARGETS:
        for content in _read_entries(target):
            if entry_id(target, content) == eid:
                return target, content
    raise MemoryError_(404, "No memory entry with that id")


def _record(eid: str, by: str, session_id: Optional[str] = None, title: Optional[str] = None) -> None:
    state = _load_state()
    prov = state.setdefault("provenance", {})
    prov[eid] = {"by": by, "saved_at": time.time(), "session_id": session_id, "session_title": title}
    # Keep the provenance map bounded.
    if len(prov) > 2000:
        for k in sorted(prov, key=lambda k: prov[k].get("saved_at") or 0)[: len(prov) - 2000]:
            prov.pop(k, None)
    _save_state(state)


def add_entry(target: str, content: str) -> dict[str, Any]:
    if target not in TARGETS:
        raise MemoryError_(400, "target must be 'user' or 'memory'")
    content = (content or "").strip()
    if not content:
        raise MemoryError_(400, "content is empty")
    if DELIMITER.strip() in content:
        raise MemoryError_(400, "content may not contain the § separator")
    store = _store()
    if store is not None:
        _check_store_result(store.add(target, content))
    else:
        path = _memory_dir() / TARGETS[target]
        with _locked(path):
            entries = _read_entries(target)
            if content in entries:
                raise MemoryError_(409, "That entry already exists")
            limit = _limits()[target]
            if len(DELIMITER.join(entries + [content])) > limit:
                raise MemoryError_(422, f"{TARGETS[target]} would exceed its {limit} character limit")
            _write_entries(target, entries + [content])
    eid = entry_id(target, content)
    _record(eid, "user")
    return {"id": eid, "target": target, "content": content}


def edit_entry(eid: str, content: str) -> dict[str, Any]:
    target, old = _find(eid)
    content = (content or "").strip()
    if not content:
        raise MemoryError_(400, "content is empty")
    if DELIMITER.strip() in content:
        raise MemoryError_(400, "content may not contain the § separator")
    store = _store()
    if store is not None:
        _check_store_result(store.replace(target, old, content))
    else:
        path = _memory_dir() / TARGETS[target]
        with _locked(path):
            entries = _read_entries(target)
            entries = [content if e == old else e for e in entries]
            limit = _limits()[target]
            if len(DELIMITER.join(entries)) > limit:
                raise MemoryError_(422, f"{TARGETS[target]} would exceed its {limit} character limit")
            _write_entries(target, entries)
    new_id = entry_id(target, content)
    state = _load_state()
    pins = state.get("pins", [])
    if eid in pins:
        state["pins"] = [new_id if p == eid else p for p in pins]
        _save_state(state)
    _record(new_id, "user")
    return {"id": new_id, "target": target, "content": content}


def delete_entry(eid: str) -> None:
    target, old = _find(eid)
    store = _store()
    if store is not None:
        _check_store_result(store.remove(target, old))
    else:
        path = _memory_dir() / TARGETS[target]
        with _locked(path):
            _write_entries(target, [e for e in _read_entries(target) if e != old])
    state = _load_state()
    state["pins"] = [p for p in state.get("pins", []) if p != eid]
    state.get("provenance", {}).pop(eid, None)
    _save_state(state)


def set_pinned(eid: str, pinned: bool) -> None:
    _find(eid)
    state = _load_state()
    pins = [p for p in state.get("pins", []) if p != eid]
    if pinned:
        pins.append(eid)
    state["pins"] = pins
    _save_state(state)


def incognito_sessions() -> list[str]:
    return sorted(_load_state().get("incognito", {}))


def set_incognito(session_id: str, enabled: bool) -> None:
    if not session_id or len(session_id) > 200:
        raise MemoryError_(400, "bad session id")
    state = _load_state()
    inc = state.setdefault("incognito", {})
    if enabled:
        inc[session_id] = time.time()
    else:
        inc.pop(session_id, None)
    # Forget incognito marks after 30 days.
    cutoff = time.time() - 30 * 86400
    state["incognito"] = {k: v for k, v in inc.items() if (v or 0) > cutoff}
    _save_state(state)


# ── hooks ──────────────────────────────────────────────────────────────


def _pinned_contents() -> list[str]:
    pins = set(_load_state().get("pins", []))
    if not pins:
        return []
    return [e["content"] for e in list_entries() if e["id"] in pins]


def pre_tool_call(tool_name: str = "", args: Optional[dict] = None, session_id: str = "", **_: Any):
    if tool_name != "memory":
        return None
    try:
        if session_id and session_id in _load_state().get("incognito", {}):
            return {"action": "block", "message": INCOGNITO_BLOCK}
        args = args or {}
        ops = args.get("operations") if isinstance(args.get("operations"), list) else [args]
        pinned = _pinned_contents()
        if not pinned:
            return None
        for op in ops:
            if not isinstance(op, dict):
                continue
            if str(op.get("action", "")).lower() in ("remove", "replace", "patch"):
                old = str(op.get("old_text") or "")
                if old and any(old in p for p in pinned):
                    return {"action": "block", "message": PINNED_BLOCK}
    except Exception:
        return None  # fail open: never break the agent over bookkeeping
    return None


def post_tool_call(tool_name: str = "", args: Optional[dict] = None, session_id: str = "", **kw: Any):
    if tool_name != "memory":
        return None
    status = kw.get("status")
    if status and str(status).lower() not in ("success", "ok"):
        return None
    try:
        args = args or {}
        ops = args.get("operations") if isinstance(args.get("operations"), list) else [args]
        for op in ops:
            if not isinstance(op, dict):
                continue
            action = str(op.get("action", "")).lower()
            target = str(op.get("target") or "memory").lower()
            content = op.get("content") or op.get("new_text")
            if action in ("add", "replace") and target in TARGETS and isinstance(content, str):
                _record(entry_id(target, content), "agent", session_id or None)
    except Exception:
        pass
    return None


def register_hooks(ctx) -> None:
    ctx.register_hook("pre_tool_call", pre_tool_call)
    ctx.register_hook("post_tool_call", post_tool_call)


# ── routes ─────────────────────────────────────────────────────────────

try:
    from fastapi import APIRouter, Body, HTTPException
except ImportError:  # agent process without the web extra: hooks still work
    _router = None
else:
    _router = APIRouter(prefix="/w3")

    def _http(fn, *a):
        try:
            return fn(*a)
        except MemoryError_ as e:
            raise HTTPException(e.status, e.message)

    @_router.get("/memory")
    def _list():
        return {"entries": list_entries(), "limits": _limits()}

    @_router.post("/memory")
    def _add(body: dict = Body(...)):
        return _http(add_entry, str(body.get("target", "memory")), str(body.get("content", "")))

    @_router.put("/memory/{eid}")
    def _edit(eid: str, body: dict = Body(...)):
        return _http(edit_entry, eid, str(body.get("content", "")))

    @_router.delete("/memory/{eid}")
    def _delete(eid: str):
        _http(delete_entry, eid)
        return {"ok": True}

    @_router.post("/memory/{eid}/pin")
    def _pin(eid: str, body: dict = Body(...)):
        _http(set_pinned, eid, bool(body.get("pinned", True)))
        return {"ok": True}

    @_router.get("/incognito")
    def _inc_list():
        return {"sessions": incognito_sessions()}

    @_router.put("/incognito/{session_id}")
    def _inc_set(session_id: str, body: dict = Body(...)):
        _http(set_incognito, session_id, bool(body.get("enabled", True)))
        return {"ok": True, "session_id": session_id, "enabled": bool(body.get("enabled", True))}


FEATURES = ["w3_memory", "w3_incognito"]


def register(router) -> None:
    """Called by registry.register_all with the plugin's root APIRouter."""
    if _router is not None:
        router.include_router(_router)
