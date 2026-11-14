"""Wave 2: project instructions and files, panels from chat, profiles.

Routes (all under ``/api/plugins/hermes_mobile``):

  GET  /w2/projects/{id}?path=<host dir>   {"instructions", "files": [{name, path, size}]}
  PUT  /w2/projects/{id}/instructions      {"instructions": "..."}
  GET  /w2/panels                          panels published from chat
  POST /w2/panels                          {"title", "kind": "text", "text"} -> panel
  DELETE /w2/panels/{id}
  GET  /w2/profiles                        Hermes profiles on this host

Project instructions live in ``~/.hermes/hermes_mobile/w2_projects.json``. The app sends
them as the system message of each project chat, so no agent change is needed.
Panels are written as JSON files into ``~/.hermes/panels/`` (the folder the Home
panels publisher reads) and kept in ``~/.hermes/hermes_mobile/w2_panels.json``.
"""

from __future__ import annotations

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

FEATURES = ["w2.projects", "w2.panels", "w2.profiles"]

MAX_INSTRUCTIONS = 16000
MAX_PANEL_TEXT = 8000
MAX_FILES = 200


def hermes_home() -> Path:
    try:
        from hermes_constants import get_hermes_home  # type: ignore

        return Path(get_hermes_home())
    except Exception:
        return Path(os.environ.get("HERMES_HOME") or Path.home() / ".hermes")


def _slug(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:40] or "panel"


class Store:
    """JSON-file store for Wave 2 data. Thread-safe."""

    def __init__(self, home: Optional[Path] = None, user_home: Optional[Path] = None):
        self.home = Path(home) if home else hermes_home()
        self.user_home = Path(user_home) if user_home else Path.home()
        self._lock = threading.Lock()

    @property
    def data_dir(self) -> Path:
        d = self.home / "hermes_mobile"
        d.mkdir(parents=True, exist_ok=True)
        return d

    def _read(self, name: str) -> Dict[str, Any]:
        try:
            data = json.loads((self.data_dir / name).read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def _write(self, name: str, data: Dict[str, Any]) -> None:
        path = self.data_dir / name
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)

    # ── projects ───────────────────────────────────────────────────────
    def project(self, project_id: str, path: Optional[str] = None) -> Dict[str, Any]:
        with self._lock:
            entry = self._read("w2_projects.json").get(project_id) or {}
        return {
            "id": project_id,
            "instructions": entry.get("instructions", ""),
            "updated_at": entry.get("updated_at"),
            "files": self.list_files(path),
        }

    def set_instructions(self, project_id: str, text: Any) -> Dict[str, Any]:
        if not isinstance(text, str):
            raise ValueError("instructions must be text")
        if len(text) > MAX_INSTRUCTIONS:
            raise ValueError(f"instructions are longer than {MAX_INSTRUCTIONS} characters")
        with self._lock:
            data = self._read("w2_projects.json")
            data[project_id] = {"instructions": text.strip(), "updated_at": time.time()}
            self._write("w2_projects.json", data)
        return {"id": project_id, "instructions": text.strip()}

    def _safe_dir(self, path: Optional[str]) -> Optional[Path]:
        """Only list folders inside the user's home or HERMES_HOME."""
        if not path:
            return None
        p = Path(os.path.expanduser(path)).resolve()
        roots = [self.user_home.resolve(), self.home.resolve()]
        if not any(p == r or r in p.parents for r in roots):
            return None
        return p if p.is_dir() else None

    def list_files(self, path: Optional[str]) -> List[Dict[str, Any]]:
        d = self._safe_dir(path)
        if d is None:
            return []
        out: List[Dict[str, Any]] = []
        try:
            entries = sorted(d.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))
        except OSError:
            return []
        for e in entries:
            if e.name.startswith(".") or e.name in {"node_modules", "build", "__pycache__"}:
                continue
            try:
                out.append({
                    "name": e.name + ("/" if e.is_dir() else ""),
                    "path": str(e),
                    "size": None if e.is_dir() else e.stat().st_size,
                })
            except OSError:
                continue
            if len(out) >= MAX_FILES:
                break
        return out

    # ── panels ─────────────────────────────────────────────────────────
    @property
    def panels_dir(self) -> Path:
        d = self.home / "panels"
        d.mkdir(parents=True, exist_ok=True)
        return d

    def panels(self) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self._read("w2_panels.json").get("panels", []))

    def add_panel(self, body: Dict[str, Any]) -> Dict[str, Any]:
        title = str(body.get("title") or "").strip()
        text = str(body.get("text") or "").strip()
        if not title or not text:
            raise ValueError("title and text are required")
        panel = {
            "id": f"hermes-mobile-{_slug(title)}-{uuid.uuid4().hex[:6]}",
            "title": title[:80],
            "kind": "text",
            "text": text[:MAX_PANEL_TEXT],
            "source": "chat",
            "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        }
        with self._lock:
            data = self._read("w2_panels.json")
            data.setdefault("panels", []).insert(0, panel)
            self._write("w2_panels.json", data)
            (self.panels_dir / f"{panel['id']}.json").write_text(
                json.dumps(panel, indent=2, ensure_ascii=False), encoding="utf-8"
            )
        return panel

    def delete_panel(self, panel_id: str) -> bool:
        if not re.fullmatch(r"[a-z0-9\-]+", panel_id):
            return False
        with self._lock:
            data = self._read("w2_panels.json")
            before = len(data.get("panels", []))
            data["panels"] = [p for p in data.get("panels", []) if p.get("id") != panel_id]
            self._write("w2_panels.json", data)
            f = self.panels_dir / f"{panel_id}.json"
            if f.exists():
                f.unlink()
        return len(data["panels"]) < before

    # ── profiles ───────────────────────────────────────────────────────
    def profiles(self) -> List[Dict[str, Any]]:
        out = [{"id": "default", "label": "Default"}]
        root = self.home / "profiles"
        if root.is_dir():
            for p in sorted(root.iterdir()):
                if p.is_dir() and not p.name.startswith("."):
                    out.append({"id": p.name, "label": p.name})
        return out


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

    @router.get("/w2/projects/{project_id}")
    async def w2_project(project_id: str, path: Optional[str] = None):
        return store().project(project_id, path)

    @router.put("/w2/projects/{project_id}/instructions")
    async def w2_set_instructions(project_id: str, request: Request):
        try:
            return store().set_instructions(project_id, (await body(request)).get("instructions", ""))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    @router.get("/w2/panels")
    async def w2_panels():
        return {"panels": store().panels()}

    @router.post("/w2/panels")
    async def w2_add_panel(request: Request):
        try:
            return store().add_panel(await body(request))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    @router.delete("/w2/panels/{panel_id}")
    async def w2_delete_panel(panel_id: str):
        if not store().delete_panel(panel_id):
            raise HTTPException(status_code=404, detail="no such panel")
        return {"ok": True}

    @router.get("/w2/profiles")
    async def w2_profiles():
        return {"profiles": store().profiles()}
