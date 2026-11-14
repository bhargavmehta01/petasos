"""Wave 1: proactive cards, briefs, feedback and uploads for the Petasos app.

Routes (all under ``/api/plugins/hermes_mobile``):

  GET  /w1/feed                    cards for the Brief tab and the feed, newest first
  POST /w1/cards                   add a card (agents, cron scripts, webhooks)
  POST /w1/cards/{id}/dismiss      hide a card
  POST /w1/cards/{id}/restore      un-hide a dismissed card (phone Undo/Restore)
  POST /w1/cards/{id}/snooze       {"minutes": 60}
  POST /w1/cards/{id}/read         mark read
  POST /w1/cards/{id}/act          {"action": "approve|snooze|reply|run|open", "text": "..."}
  POST /w1/feedback                {"card_id", "signal": "more|less", "source", "kind", "title"}
  POST /w1/upload                  {"name", "data_b64", "mime"} -> {"path"}

Briefs come from Hermes cron output: the newest run of every job whose name
looks like a brief or digest becomes a morning or evening card. A cron job whose
last run failed becomes an alert card with a Run action.

More/less feedback is saved to the Hermes user memory (USER.md) as one short
entry, so the agent reads it in later sessions.
"""

from __future__ import annotations

import base64
import json
import os
import re
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

try:  # FastAPI is present inside Hermes; tests of the store run without it.
    from fastapi import HTTPException, Request
except Exception:  # pragma: no cover
    HTTPException = Request = None  # type: ignore

FEATURES = ["w1.feed", "w1.feedback", "w1.upload"]

BRIEF_NAME = re.compile(r"\b(brief|briefing|digest|recap|summary|morning|evening)\b", re.I)
MAX_BODY = 4000
MAX_UPLOAD = 20 * 1024 * 1024
BRIEF_MAX_AGE_S = 36 * 3600
ACTIONS = {"approve", "snooze", "reply", "run", "open"}
ENTRY_DELIMITER = "\n§\n"


def hermes_home() -> Path:
    try:
        from hermes_constants import get_hermes_home  # type: ignore

        return Path(get_hermes_home())
    except Exception:
        return Path(os.environ.get("HERMES_HOME") or Path.home() / ".hermes")


class Store:
    """JSON-file store for cards and their per-card state. Thread-safe."""

    def __init__(self, home: Optional[Path] = None):
        self.home = Path(home) if home else hermes_home()
        self._lock = threading.Lock()

    # ── files ───────────────────────────────────────────────────────────
    @property
    def data_dir(self) -> Path:
        d = self.home / "hermes_mobile"
        d.mkdir(parents=True, exist_ok=True)
        return d

    @property
    def cards_file(self) -> Path:
        return self.data_dir / "w1_cards.json"

    def _read(self) -> Dict[str, Any]:
        try:
            data = json.loads(self.cards_file.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                data.setdefault("cards", [])
                data.setdefault("state", {})
                return data
        except (OSError, ValueError):
            pass
        return {"cards": [], "state": {}}

    def _write(self, data: Dict[str, Any]) -> None:
        tmp = self.cards_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
        tmp.replace(self.cards_file)

    # ── cards ───────────────────────────────────────────────────────────
    def add_card(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        title = str(payload.get("title") or "").strip()
        if not title:
            raise ValueError("title is required")
        action = payload.get("action") if isinstance(payload.get("action"), dict) else None
        if action and str(action.get("kind")) not in ACTIONS:
            raise ValueError("action.kind must be one of " + ", ".join(sorted(ACTIONS)))
        card = {
            "id": str(payload.get("id") or uuid.uuid4().hex[:12]),
            "kind": str(payload.get("kind") or "suggestion"),
            "source": str(payload.get("source") or "agent"),
            "title": title[:200],
            "body": str(payload.get("body") or "")[:MAX_BODY],
            "created_at": float(payload.get("created_at") or time.time()),
            "priority": int(payload.get("priority") or 0),
            "chat_id": payload.get("chat_id"),
            "action": action,
        }
        with self._lock:
            data = self._read()
            data["cards"] = [c for c in data["cards"] if c.get("id") != card["id"]]
            data["cards"].append(card)
            data["cards"] = data["cards"][-200:]
            self._write(data)
        return card

    def set_state(self, card_id: str, **changes: Any) -> Dict[str, Any]:
        with self._lock:
            data = self._read()
            state = data["state"].setdefault(card_id, {})
            state.update(changes)
            # Keep the state map bounded.
            if len(data["state"]) > 500:
                for key in list(data["state"])[:-500]:
                    data["state"].pop(key, None)
            self._write(data)
            return state

    def feed(self, now: Optional[float] = None) -> Dict[str, Any]:
        now = now or time.time()
        data = self._read()
        cards = list(data["cards"]) + cron_cards(self.home, now)
        out = []
        for card in cards:
            st = data["state"].get(card["id"], {})
            if st.get("dismissed") or st.get("acted"):
                continue
            if float(st.get("snoozed_until") or 0) > now:
                continue
            out.append({**card, "read": bool(st.get("read"))})
        out.sort(key=lambda c: (-int(c.get("priority") or 0), -float(c.get("created_at") or 0)))
        return {"cards": out, "unread": sum(1 for c in out if not c["read"]), "generated_at": now}

    # ── feedback → memory ───────────────────────────────────────────────
    def feedback(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        signal = str(payload.get("signal") or "").lower()
        if signal not in {"more", "less"}:
            raise ValueError("signal must be more or less")
        what = str(payload.get("source") or payload.get("kind") or "this kind of card").strip()
        title = str(payload.get("title") or "").strip()
        day = time.strftime("%Y-%m-%d")
        entry = (
            f"Proactivity preference (from the Petasos app, {day}): the user wants "
            f"{signal} {what} updates"
            + (f", said on the card '{title[:80]}'" if title else "")
            + "."
        )
        mem_dir = self.home / "memories"
        mem_dir.mkdir(parents=True, exist_ok=True)
        user_md = mem_dir / "USER.md"
        with self._lock:
            existing = user_md.read_text(encoding="utf-8") if user_md.exists() else ""
            joined = entry if not existing.strip() else existing.rstrip("\n") + ENTRY_DELIMITER + entry
            user_md.write_text(joined + "\n", encoding="utf-8")
        if payload.get("card_id"):
            self.set_state(str(payload["card_id"]), feedback=signal)
        return {"saved": True, "entry": entry}

    # ── uploads ─────────────────────────────────────────────────────────
    def upload(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        name = Path(str(payload.get("name") or "file")).name
        name = re.sub(r"[^A-Za-z0-9._ -]", "_", name).strip() or "file"
        try:
            raw = base64.b64decode(str(payload.get("data_b64") or ""), validate=True)
        except Exception as exc:
            raise ValueError("data_b64 is not valid base64") from exc
        if not raw:
            raise ValueError("empty file")
        if len(raw) > MAX_UPLOAD:
            raise ValueError("file is larger than 20 MB")
        folder = self.data_dir / "uploads" / time.strftime("%Y%m%d")
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / f"{uuid.uuid4().hex[:6]}-{name}"
        target.write_bytes(raw)
        return {"path": str(target), "bytes": len(raw), "name": name}


# ── cron → cards ────────────────────────────────────────────────────────
def _load_jobs(home: Path) -> List[Dict[str, Any]]:
    try:
        data = json.loads((home / "cron" / "jobs.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    jobs = data.get("jobs") if isinstance(data, dict) else data
    return [j for j in jobs or [] if isinstance(j, dict)]


def _response_text(markdown: str) -> str:
    """The agent's answer from a cron output file (after '## Response' when present)."""
    m = re.search(r"^##\s*Response\s*$", markdown, re.M)
    text = markdown[m.end():] if m else markdown
    text = re.sub(r"^#\s*Cron Job:.*$", "", text, flags=re.M)
    return text.strip()[:MAX_BODY]


def cron_cards(home: Path, now: float) -> List[Dict[str, Any]]:
    cards: List[Dict[str, Any]] = []
    out_root = home / "cron" / "output"
    for job in _load_jobs(home):
        job_id = str(job.get("id") or job.get("job_id") or "").strip()
        if not job_id or "/" in job_id or job_id in {".", ".."}:
            continue
        name = str(job.get("name") or job.get("prompt") or "Scheduled task")[:120]
        status = str(job.get("last_status") or "").lower()
        if status in {"error", "failed", "failure"}:
            err = str(job.get("last_error") or "The last run failed.")[:400]
            cards.append({
                "id": f"cronfail:{job_id}:{job.get('last_run_at') or ''}",
                "kind": "alert",
                "source": "cron",
                "title": f"{name} failed",
                "body": err,
                "created_at": now,
                "priority": 2,
                "action": {"kind": "run", "label": "Run again", "payload": {"cron_id": job_id}},
            })
        if not BRIEF_NAME.search(name):
            continue
        folder = out_root / job_id
        try:
            files = sorted(folder.glob("*.md"), key=lambda p: p.stat().st_mtime)
        except OSError:
            continue
        if not files:
            continue
        latest = files[-1]
        mtime = latest.stat().st_mtime
        if now - mtime > BRIEF_MAX_AGE_S:
            continue
        try:
            body = _response_text(latest.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            continue
        hour = time.localtime(mtime).tm_hour
        cards.append({
            "id": f"brief:{job_id}:{latest.name}",
            "kind": "brief",
            "period": "morning" if hour < 15 else "evening",
            "source": "cron",
            "title": name,
            "body": body,
            "created_at": mtime,
            "priority": 1,
            "action": {"kind": "reply", "label": "Ask about this"},
        })
    return cards


# ── routes ──────────────────────────────────────────────────────────────
_store: Optional[Store] = None


def store() -> Store:
    global _store
    if _store is None:
        _store = Store()
    return _store


def register(router: Any) -> None:
    async def body(request: Request) -> Dict[str, Any]:
        try:
            data = await request.json()
        except Exception:
            data = {}
        return data if isinstance(data, dict) else {}

    @router.get("/w1/feed")
    async def w1_feed():
        return store().feed()

    @router.post("/w1/cards")
    async def w1_add(request: Request):
        try:
            return store().add_card(await body(request))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    @router.post("/w1/cards/{card_id}/dismiss")
    async def w1_dismiss(card_id: str):
        return store().set_state(card_id, dismissed=True)

    @router.post("/w1/cards/{card_id}/restore")
    async def w1_restore(card_id: str):
        return store().set_state(card_id, dismissed=False, acted=False, snoozed_until=0)

    @router.post("/w1/cards/{card_id}/read")
    async def w1_read(card_id: str):
        return store().set_state(card_id, read=True)

    @router.post("/w1/cards/{card_id}/snooze")
    async def w1_snooze(card_id: str, request: Request):
        minutes = max(5, min(int((await body(request)).get("minutes") or 60), 7 * 24 * 60))
        return store().set_state(card_id, snoozed_until=time.time() + minutes * 60, read=True)

    @router.post("/w1/cards/{card_id}/act")
    async def w1_act(card_id: str, request: Request):
        data = await body(request)
        action = str(data.get("action") or "")
        if action not in ACTIONS:
            raise HTTPException(status_code=400, detail="unknown action")
        return store().set_state(card_id, acted=action, acted_at=time.time(), read=True)

    @router.post("/w1/feedback")
    async def w1_feedback(request: Request):
        try:
            return store().feedback(await body(request))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    @router.post("/w1/upload")
    async def w1_upload(request: Request):
        try:
            return store().upload(await body(request))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
