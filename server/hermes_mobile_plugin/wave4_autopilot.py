"""Wave 4: autopilot routes for the Petasos app.

Routes (mounted under /api/plugins/hermes_mobile/):

  GET    w4/status                        -> {"ok": true, "features": [...]}
  GET    w4/watchers                      -> {"watchers": [...]}
  POST   w4/watchers                      {"title", "target", "every"?, "condition"?}
  DELETE w4/watchers/{id}
  POST   w4/watchers/{id}/pause | resume | check
  POST   w4/watchers/{id}/report          {"status": "ok"|"changed"|"error", "value"?, "change"?}
  GET    w4/commitments                   -> {"commitments": [...]}  (stored + scanned)
  POST   w4/commitments                   {"text", "owner"?, "due"?, "chat_id"?, "chat_title"?}
  PUT    w4/commitments/{id}              {"done"?: bool, "due"?: iso, ...}
  GET    w4/recap?since=<epoch s>         -> {"actions": [...]}
  POST   w4/actions                       {"summary", "kind"?, "detail"?, "revert_prompt"?, "chat_id"?, "ok"?}
  POST   w4/actions/{id}/revert           -> {"ok": bool}
  GET    w4/outbound                      -> {"held": [...]}
  POST   w4/outbound                      {"summary", "kind"?, "hold_seconds"?} -> {"id", "release_at"}
  GET    w4/outbound/{id}                 -> {"state": "held"|"released"|"undone"}
  POST   w4/outbound/{id}/undo            -> {"ok": bool}
  GET    w4/proactivity                   -> {"level": "quiet"|"balanced"|"chatty"|null}
  PUT    w4/proactivity                   {"level"} -> writes a standing rule to memories/USER.md
  POST   w4/triggers/fired                {"kind", "prompt"?}
  GET    w4/glance                        -> counts for the Wear tile and widgets

State lives in ``$HERMES_HOME/hermes_mobile/wave4.json`` (one small JSON file, locked on
write). Watchers are backed by Hermes cron jobs named ``Watch: <title>`` when the
cron module is importable, so they really run; the agent (or the cron prompt)
reports results through ``/report``. Reverting an action schedules a one-shot cron
job with the action's ``revert_prompt``. The undo window for outbound actions is
cooperative: the agent registers a send with ``POST w4/outbound``, waits out the
hold, and checks ``GET w4/outbound/{id}`` before it really sends.
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import sqlite3
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

FEATURES = [
    "watchers",
    "commitments",
    "recap",
    "outbound_undo",
    "proactivity",
    "context_triggers",
    "glance",
]
VERSION = "0.4.0"
DEFAULT_HOLD_SECONDS = 10
MAX_ITEMS = 500
LEVELS = ("quiet", "balanced", "chatty")
RULES = {
    "quiet": "Proactivity: quiet. Only reach out for approvals, failures and alerts "
    "the user set up. No suggestions or unrequested summaries.",
    "balanced": "Proactivity: balanced. Reach out for approvals, failures and alerts, "
    "one short daily recap, and a suggestion only when clearly useful.",
    "chatty": "Proactivity: chatty. Proactive suggestions, watcher ideas and context "
    "nudges are welcome, still batched and never more than hourly.",
}
MEMORY_DELIMITER = "\n§\n"


# ── paths and state ────────────────────────────────────────────────────


def _home() -> Path:
    override = os.environ.get("HERMES_MOBILE_PLUGIN_HOME")  # tests
    if override:
        return Path(override)
    from hermes_constants import get_hermes_home

    return Path(get_hermes_home())


def _state_file() -> Path:
    return _home() / "hermes_mobile" / "wave4.json"


@contextlib.contextmanager
def _locked():
    path = _state_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.with_suffix(".lock")
    with open(lock, "a+") as fd:
        try:
            import fcntl

            fcntl.flock(fd, fcntl.LOCK_EX)
        except Exception:  # non-POSIX: best effort
            pass
        state = _read()
        yield state
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(state, indent=1, sort_keys=True))
        os.replace(tmp, path)


def _read() -> Dict[str, Any]:
    path = _state_file()
    try:
        data = json.loads(path.read_text())
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}


def _now() -> float:
    return time.time()


def _iso(ts: Optional[float]) -> Optional[str]:
    if ts is None:
        return None
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()


def _new_id(prefix: str) -> str:
    return f"{prefix}{uuid.uuid4().hex[:10]}"


def _trim(items: List[Any]) -> List[Any]:
    return items[-MAX_ITEMS:]


# ── cron bridge (optional) ─────────────────────────────────────────────


def _cron():
    try:
        from cron import jobs  # type: ignore

        return jobs
    except Exception:
        return None


def _cron_schedule(every: str) -> str:
    m = re.search(r"every (\d+) (minute|hour|day)", every or "", re.I)
    if not m:
        return "every 1d" if "day" in (every or "").lower() else "every 6h"
    unit = {"minute": "m", "hour": "h", "day": "d"}[m.group(2).lower()]
    return f"every {m.group(1)}{unit}"


def watcher_prompt(watcher_id: str, target: str, condition: Optional[str]) -> str:
    alert = (
        f"Alert me only when: {condition}."
        if condition
        else "Tell me only if something important changed since the last check."
    )
    return (
        f"Watcher check ({watcher_id}). Look at: {target}. {alert} "
        "Start your reply with one status word: OK, CHANGED or ERROR, then one short "
        "line with the current value. Then report it with "
        f"POST /api/plugins/hermes_mobile/w4/watchers/{watcher_id}/report "
        '{"status": "ok|changed|error", "value": "...", "change": "..."}.'
    )


# ── watchers ───────────────────────────────────────────────────────────


def list_watchers() -> List[Dict[str, Any]]:
    return list(_read().get("watchers", []))


def create_watcher(title: str, target: str, every: str = "Every 6 hours",
                   condition: Optional[str] = None) -> Dict[str, Any]:
    if not title.strip() or not target.strip():
        raise ValueError("title and target are required")
    wid = _new_id("w")
    watcher = {
        "id": wid,
        "title": title.strip()[:120],
        "target": target.strip()[:500],
        "every": every,
        "condition": (condition or "").strip()[:200] or None,
        "status": "pending",
        "created_at": _iso(_now()),
        "history": [],
        "cron_id": None,
    }
    cron = _cron()
    if cron is not None:
        try:
            job = cron.create_job(
                prompt=watcher_prompt(wid, watcher["target"], watcher["condition"]),
                schedule=_cron_schedule(every),
                name=f"Watch: {watcher['title']}",
            )
            watcher["cron_id"] = job.get("id") if isinstance(job, dict) else None
        except Exception:
            watcher["cron_id"] = None
    with _locked() as state:
        state.setdefault("watchers", []).insert(0, watcher)
        state["watchers"] = state["watchers"][:MAX_ITEMS]
    return watcher


def _update_watcher(wid: str, **changes: Any) -> Optional[Dict[str, Any]]:
    with _locked() as state:
        for w in state.get("watchers", []):
            if w.get("id") == wid:
                w.update(changes)
                return dict(w)
    return None


def set_watcher_paused(wid: str, paused: bool) -> Optional[Dict[str, Any]]:
    w = _update_watcher(wid, status="paused" if paused else "pending")
    cron = _cron()
    if w and w.get("cron_id") and cron is not None:
        with contextlib.suppress(Exception):
            (cron.pause_job if paused else cron.resume_job)(w["cron_id"])
    return w


def check_watcher(wid: str) -> Optional[Dict[str, Any]]:
    w = _update_watcher(wid, check_requested_at=_iso(_now()))
    cron = _cron()
    if w and w.get("cron_id") and cron is not None:
        with contextlib.suppress(Exception):
            cron.trigger_job(w["cron_id"])
    return w


def delete_watcher(wid: str) -> bool:
    removed = None
    with _locked() as state:
        keep = []
        for w in state.get("watchers", []):
            if w.get("id") == wid:
                removed = w
            else:
                keep.append(w)
        state["watchers"] = keep
    cron = _cron()
    if removed and removed.get("cron_id") and cron is not None:
        with contextlib.suppress(Exception):
            cron.remove_job(removed["cron_id"])
    return removed is not None


def report_watcher(wid: str, status: str, value: Optional[str] = None,
                   change: Optional[str] = None) -> Optional[Dict[str, Any]]:
    status = status.lower() if status else "ok"
    if status not in ("ok", "changed", "error"):
        status = "ok"
    with _locked() as state:
        for w in state.get("watchers", []):
            if w.get("id") != wid:
                continue
            if w.get("status") == "paused":
                return dict(w)
            w["status"] = status
            w["last_checked"] = _iso(_now())
            if value:
                w["last_value"] = str(value)[:120]
                hist = w.setdefault("history", [])
                if not hist or hist[-1] != w["last_value"]:
                    hist.append(w["last_value"])
                    w["history"] = hist[-20:]
            if change:
                w["last_change"] = str(change)[:200]
            if status in ("changed", "error"):
                state.setdefault("actions", []).append({
                    "id": _new_id("a"),
                    "summary": f"{w['title']}: {value or status}",
                    "detail": change,
                    "kind": "watcher",
                    "at": _now(),
                    "ok": status != "error",
                })
                state["actions"] = _trim(state["actions"])
            return dict(w)
    return None


# ── commitments ────────────────────────────────────────────────────────

_AGENT_PROMISE = re.compile(
    r"\b(I'll|I will|I'm going to|I am going to|I'll remind you|I'll check|"
    r"I'll follow up|I'll get back|I'll keep an eye|let me check back)\b[^.!?\n]{3,160}[.!?]?",
    re.I,
)
_USER_PROMISE = re.compile(
    r"\b(remind me to|remind me about|don't let me forget to|I need to|I have to|"
    r"I promised to)\b[^.!?\n]{3,160}[.!?]?",
    re.I,
)
_WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def parse_due(text: str, now: datetime) -> Optional[datetime]:
    """Same rules as the app's ``parseDue``."""
    t = text.lower()

    def at(d: datetime, hour: int) -> datetime:
        return d.replace(hour=hour, minute=0, second=0, microsecond=0)

    m = re.search(r"\bin (\d{1,2}) (minute|hour|day|week)s?\b", t)
    if m:
        n = int(m.group(1))
        delta = {"minute": timedelta(minutes=n), "hour": timedelta(hours=n),
                 "week": timedelta(days=7 * n)}.get(m.group(2), timedelta(days=n))
        return now + delta
    if re.search(r"\btonight\b", t):
        return at(now, 20)
    if re.search(r"\b(end of (the )?day|eod|today|this afternoon)\b", t):
        return at(now, 17)
    if re.search(r"\btomorrow\b", t):
        return at(now + timedelta(days=1), 9)
    if re.search(r"\bnext week\b", t):
        return at(now + timedelta(days=7 - now.weekday()), 9)
    for i, day in enumerate(_WEEKDAYS):
        if re.search(rf"\b{day}\b", t):
            delta = i - now.weekday()
            if delta <= 0:
                delta += 7
            return at(now + timedelta(days=delta), 9)
    return None


def _stable_id(chat_id: str, text: str) -> str:
    h = 0
    for ch in f"{chat_id}|{text}":
        h = (h * 31 + ord(ch)) & 0x7FFFFFFF
    return f"c{h}"


def extract_commitments(messages: List[Dict[str, Any]], chat_id: str,
                        chat_title: Optional[str] = None,
                        now: Optional[datetime] = None) -> List[Dict[str, Any]]:
    """Promises in a transcript (rows with ``role`` and ``content``)."""
    now = now or datetime.now().astimezone()
    out, seen = [], set()
    for m in messages:
        role = m.get("role")
        if role not in ("user", "assistant"):
            continue
        content = m.get("content")
        if not isinstance(content, str):
            continue
        text = re.sub(r"```[\s\S]*?```", " ", content)
        pattern = _USER_PROMISE if role == "user" else _AGENT_PROMISE
        for match in pattern.finditer(text):
            raw = match.group(0)
            sentence = re.sub(r"[*_`>#]", "", raw)
            sentence = re.sub(r"\s+", " ", sentence).strip().rstrip(".!")
            lower = sentence.lower()
            if len(sentence) < 8 or "if you" in lower or "would you" in lower or raw.strip().endswith("?"):
                continue
            if lower in seen:
                continue
            seen.add(lower)
            body = sentence
            if role == "user":
                body = re.sub(r"^(remind me to|remind me about|don't let me forget to)\s*", "", body, flags=re.I)
            body = (body[:1].upper() + body[1:]) if body else sentence
            due = parse_due(sentence, now)
            out.append({
                "id": _stable_id(chat_id, lower),
                "text": body,
                "owner": "user" if role == "user" else "agent",
                "due": due.isoformat() if due else None,
                "chat_id": chat_id,
                "chat_title": chat_title,
                "done": False,
                "source": "server",
                "quote": sentence,
            })
    return out


def _scan_state_db(days: int = 7, limit_sessions: int = 40) -> List[Dict[str, Any]]:
    """Reads recent sessions from Hermes' ``state.db`` read-only. Best effort:
    the schema is upstream's and may change, so any error yields nothing."""
    db = _home() / "state.db"
    if not db.exists():
        return []
    since = _now() - days * 86400
    found: List[Dict[str, Any]] = []
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=2)
        try:
            con.row_factory = sqlite3.Row
            sessions = con.execute(
                "SELECT id, title FROM sessions WHERE started_at >= ? "
                "ORDER BY started_at DESC LIMIT ?",
                (since, limit_sessions),
            ).fetchall()
            for s in sessions:
                rows = con.execute(
                    "SELECT role, content FROM messages WHERE session_id = ? "
                    "ORDER BY id DESC LIMIT 60",
                    (s["id"],),
                ).fetchall()
                msgs = [{"role": r["role"], "content": r["content"]} for r in reversed(rows)]
                found.extend(extract_commitments(msgs, s["id"], s["title"]))
        finally:
            con.close()
    except Exception:
        return []
    return found


def list_commitments(scan: bool = True) -> List[Dict[str, Any]]:
    state = _read()
    stored = {c["id"]: c for c in state.get("commitments", []) if isinstance(c, dict)}
    overrides = state.get("commitment_overrides", {})
    if scan:
        for c in _scan_state_db():
            stored.setdefault(c["id"], c)
    out = []
    for cid, c in stored.items():
        c = dict(c)
        c.update(overrides.get(cid, {}))
        out.append(c)
    out.sort(key=lambda c: (bool(c.get("done")), c.get("due") or "9999"))
    return out


def add_commitment(body: Dict[str, Any]) -> Dict[str, Any]:
    text = str(body.get("text") or "").strip()
    if not text:
        raise ValueError("text is required")
    c = {
        "id": _new_id("k"),
        "text": text[:300],
        "owner": "user" if body.get("owner") == "user" else "agent",
        "due": body.get("due"),
        "chat_id": body.get("chat_id"),
        "chat_title": body.get("chat_title"),
        "done": False,
        "source": "server",
    }
    with _locked() as state:
        state.setdefault("commitments", []).append(c)
        state["commitments"] = _trim(state["commitments"])
    return c


def update_commitment(cid: str, body: Dict[str, Any]) -> Dict[str, Any]:
    allowed = {k: body[k] for k in ("done", "due", "text") if k in body}
    with _locked() as state:
        for c in state.get("commitments", []):
            if c.get("id") == cid:
                c.update(allowed)
                return dict(c)
        # A scanned commitment: remember the change as an override.
        state.setdefault("commitment_overrides", {}).setdefault(cid, {}).update(allowed)
        return {"id": cid, **allowed}


# ── recap, actions and revert ──────────────────────────────────────────


def record_action(summary: str, kind: str = "task", detail: Optional[str] = None,
                  revert_prompt: Optional[str] = None, chat_id: Optional[str] = None,
                  ok: bool = True) -> Dict[str, Any]:
    """Logs something the agent did on its own. Other plugin code can call this."""
    a = {
        "id": _new_id("a"),
        "summary": summary[:200],
        "kind": kind,
        "detail": (detail or None) and detail[:500],
        "revert_prompt": revert_prompt,
        "chat_id": chat_id,
        "at": _now(),
        "ok": bool(ok),
        "reverted": False,
    }
    with _locked() as state:
        state.setdefault("actions", []).append(a)
        state["actions"] = _trim(state["actions"])
    return a


def _cron_runs_since(since: float) -> List[Dict[str, Any]]:
    cron = _cron()
    if cron is None:
        return []
    out = []
    try:
        for j in cron.list_jobs(include_disabled=True):
            last = j.get("last_run_at")
            ts = None
            if isinstance(last, (int, float)):
                ts = float(last)
            elif isinstance(last, str):
                with contextlib.suppress(Exception):
                    ts = datetime.fromisoformat(last.replace("Z", "+00:00")).timestamp()
            if ts is None or ts < since:
                continue
            status = str(j.get("last_status") or "")
            out.append({
                "id": f"cron:{j.get('id')}",
                "summary": f"Ran \"{j.get('name') or 'task'}\"",
                "detail": j.get("last_error") or None,
                "kind": "cron",
                "at": ts,
                "ok": not any(x in status.lower() for x in ("error", "fail")),
                "revertible": False,
            })
    except Exception:
        return []
    return out


def recap(since: float) -> List[Dict[str, Any]]:
    actions = []
    for a in _read().get("actions", []):
        if float(a.get("at", 0)) < since:
            continue
        item = {k: v for k, v in a.items() if k != "revert_prompt"}
        item["revertible"] = bool(a.get("revert_prompt")) and not a.get("reverted")
        item["at"] = _iso(float(a["at"]))
        actions.append(item)
    for r in _cron_runs_since(since):
        r["at"] = _iso(r["at"])
        actions.append(r)
    actions.sort(key=lambda a: a["at"], reverse=True)
    return actions[:100]


def revert_action(aid: str) -> bool:
    target = None
    with _locked() as state:
        for a in state.get("actions", []):
            if a.get("id") == aid and a.get("revert_prompt") and not a.get("reverted"):
                a["reverted"] = True
                target = dict(a)
                break
    if target is None:
        return False
    cron = _cron()
    if cron is None:
        return True  # marked; the agent picks it up from the log
    try:
        run_at = datetime.now(timezone.utc) + timedelta(minutes=1)
        cron.create_job(
            prompt=f"Revert this earlier action the user asked to undo: {target['summary']}. "
            f"{target['revert_prompt']}",
            schedule=run_at.isoformat(),
            name=f"Revert: {target['summary'][:60]}",
            repeat=1,
        )
    except Exception:
        return True
    return True


# ── outbound undo window ───────────────────────────────────────────────


def hold_outbound(summary: str, kind: str = "message",
                  hold_seconds: int = DEFAULT_HOLD_SECONDS) -> Dict[str, Any]:
    hold = max(0, min(int(hold_seconds), 120))
    h = {
        "id": _new_id("h"),
        "summary": summary[:200],
        "kind": kind,
        "created_at": _now(),
        "release_at": _now() + hold,
        "undone": False,
    }
    with _locked() as state:
        state.setdefault("outbound", []).append(h)
        state["outbound"] = _trim(state["outbound"])
    return {"id": h["id"], "release_at": _iso(h["release_at"])}


def outbound_state(hid: str) -> Optional[str]:
    for h in _read().get("outbound", []):
        if h.get("id") == hid:
            if h.get("undone"):
                return "undone"
            return "released" if _now() >= float(h["release_at"]) else "held"
    return None


def held_outbound() -> List[Dict[str, Any]]:
    now = _now()
    return [
        {"id": h["id"], "summary": h["summary"], "kind": h.get("kind", "message"),
         "release_at": _iso(float(h["release_at"]))}
        for h in _read().get("outbound", [])
        if not h.get("undone") and float(h["release_at"]) > now
    ]


def undo_outbound(hid: str) -> bool:
    with _locked() as state:
        for h in state.get("outbound", []):
            if h.get("id") == hid and not h.get("undone") and _now() < float(h["release_at"]):
                h["undone"] = True
                return True
    return False


# ── proactivity dial ───────────────────────────────────────────────────


def get_level() -> Optional[str]:
    return _read().get("proactivity")


def set_level(level: str) -> bool:
    if level not in LEVELS:
        raise ValueError("level must be quiet, balanced or chatty")
    with _locked() as state:
        state["proactivity"] = level
    return _write_rule(RULES[level])


def _write_rule(rule: str) -> bool:
    """Replaces the one ``Proactivity:`` entry in memories/USER.md (entries are
    separated by ``\\n§\\n``, the format of Hermes' memory tool)."""
    path = _home() / "memories" / "USER.md"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        text = path.read_text() if path.exists() else ""
        entries = [e for e in text.split(MEMORY_DELIMITER) if e.strip()] if text.strip() else []
        entries = [e for e in entries if not e.strip().startswith("Proactivity:")]
        entries.append(rule)
        tmp = path.with_suffix(".hermesMobile.tmp")
        tmp.write_text(MEMORY_DELIMITER.join(entries))
        os.replace(tmp, path)
        return True
    except Exception:
        return False


# ── glance ─────────────────────────────────────────────────────────────


def glance() -> Dict[str, Any]:
    state = _read()
    watchers = state.get("watchers", [])
    changed = [w for w in watchers if w.get("status") in ("changed", "error")]
    horizon = (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()
    due = [c for c in list_commitments(scan=False)
           if not c.get("done") and c.get("due") and str(c["due"]) <= horizon]
    since = _now() - 12 * 3600
    overnight = [a for a in state.get("actions", []) if float(a.get("at", 0)) >= since]
    headline = None
    if changed:
        w = changed[0]
        headline = f"{w['title']}: {w.get('last_value') or w.get('status')}"
    elif due:
        headline = f"{len(due)} due today"
    return {
        "watchers_changed": len(changed),
        "commitments_due": len(due),
        "overnight_actions": len(overnight),
        "held_outbound": len(held_outbound()),
        "headline": headline,
        "proactivity": state.get("proactivity"),
    }


# ── routes ─────────────────────────────────────────────────────────────


def register(router) -> None:
    from fastapi import Body, HTTPException

    def _404(item: Any) -> Any:
        if item is None:
            raise HTTPException(404, "Not found")
        return item

    @router.get("/w4/status")
    async def w4_status():
        return {"ok": True, "version": VERSION, "features": FEATURES}

    @router.get("/w4/watchers")
    async def w4_watchers():
        return {"watchers": list_watchers()}

    @router.post("/w4/watchers")
    async def w4_create_watcher(body: Dict[str, Any] = Body(...)):
        try:
            w = create_watcher(
                str(body.get("title") or ""),
                str(body.get("target") or ""),
                str(body.get("every") or "Every 6 hours"),
                body.get("condition"),
            )
        except ValueError as e:
            raise HTTPException(400, str(e))
        return {"watcher": w}

    @router.delete("/w4/watchers/{wid}")
    async def w4_delete_watcher(wid: str):
        _404(True if delete_watcher(wid) else None)
        return {"ok": True}

    @router.post("/w4/watchers/{wid}/pause")
    async def w4_pause(wid: str):
        return {"watcher": _404(set_watcher_paused(wid, True))}

    @router.post("/w4/watchers/{wid}/resume")
    async def w4_resume(wid: str):
        return {"watcher": _404(set_watcher_paused(wid, False))}

    @router.post("/w4/watchers/{wid}/check")
    async def w4_check(wid: str):
        return {"watcher": _404(check_watcher(wid))}

    @router.post("/w4/watchers/{wid}/report")
    async def w4_report(wid: str, body: Dict[str, Any] = Body(...)):
        return {"watcher": _404(report_watcher(
            wid, str(body.get("status") or "ok"), body.get("value"), body.get("change")))}

    @router.get("/w4/commitments")
    async def w4_commitments():
        return {"commitments": list_commitments()}

    @router.post("/w4/commitments")
    async def w4_add_commitment(body: Dict[str, Any] = Body(...)):
        try:
            return {"commitment": add_commitment(body)}
        except ValueError as e:
            raise HTTPException(400, str(e))

    @router.put("/w4/commitments/{cid}")
    async def w4_update_commitment(cid: str, body: Dict[str, Any] = Body(...)):
        return {"commitment": update_commitment(cid, body), "ok": True}

    @router.get("/w4/recap")
    async def w4_recap(since: Optional[float] = None):
        start = since if since is not None else _now() - 12 * 3600
        return {"actions": recap(start)}

    @router.post("/w4/actions")
    async def w4_record(body: Dict[str, Any] = Body(...)):
        summary = str(body.get("summary") or "").strip()
        if not summary:
            raise HTTPException(400, "summary is required")
        a = record_action(summary, str(body.get("kind") or "task"), body.get("detail"),
                          body.get("revert_prompt"), body.get("chat_id"), body.get("ok", True) is not False)
        return {"action": {k: v for k, v in a.items() if k != "revert_prompt"}}

    @router.post("/w4/actions/{aid}/revert")
    async def w4_revert(aid: str):
        return {"ok": revert_action(aid)}

    @router.get("/w4/outbound")
    async def w4_held():
        return {"held": held_outbound()}

    @router.post("/w4/outbound")
    async def w4_hold(body: Dict[str, Any] = Body(...)):
        summary = str(body.get("summary") or "").strip()
        if not summary:
            raise HTTPException(400, "summary is required")
        return hold_outbound(summary, str(body.get("kind") or "message"),
                             int(body.get("hold_seconds", DEFAULT_HOLD_SECONDS) or 0))

    @router.get("/w4/outbound/{hid}")
    async def w4_outbound_state(hid: str):
        return {"state": _404(outbound_state(hid))}

    @router.post("/w4/outbound/{hid}/undo")
    async def w4_undo(hid: str):
        return {"ok": undo_outbound(hid)}

    @router.get("/w4/proactivity")
    async def w4_level():
        return {"level": get_level()}

    @router.put("/w4/proactivity")
    async def w4_set_level(body: Dict[str, Any] = Body(...)):
        try:
            written = set_level(str(body.get("level") or ""))
        except ValueError as e:
            raise HTTPException(400, str(e))
        return {"ok": True, "rule_written": written}

    @router.post("/w4/triggers/fired")
    async def w4_trigger(body: Dict[str, Any] = Body(...)):
        kind = str(body.get("kind") or "trigger")
        record_action(f"Context trigger: {kind.replace('_', ' ')}", "trigger",
                      body.get("prompt"))
        return {"ok": True}

    @router.get("/w4/glance")
    async def w4_glance():
        return glance()
