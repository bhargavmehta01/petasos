"""Wave 3 plugin tests: run with `python -m pytest server/hermes_mobile_plugin/tests -q`."""

import importlib.util
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def _load(name):
    spec = importlib.util.spec_from_file_location(f"_t_{name}", ROOT / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture()
def home(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_MOBILE_PLUGIN_HOME", str(tmp_path))
    (tmp_path / "memories").mkdir()
    (tmp_path / "memories" / "USER.md").write_text("Lives in Springfield\n§\nPrefers short answers\n")
    (tmp_path / "memories" / "MEMORY.md").write_text("Backups run at 03:00\n")
    return tmp_path


def test_memory_list_add_edit_delete_pin(home):
    m = _load("wave3_memory")
    entries = m.list_entries()
    assert {e["content"] for e in entries} == {"Lives in Springfield", "Prefers short answers", "Backups run at 03:00"}
    added = m.add_entry("memory", "Panels live in ~/.hermes/panels")
    assert "Panels live" in (home / "memories" / "MEMORY.md").read_text()
    m.set_pinned(added["id"], True)
    assert m.list_entries()[0]["pinned"] is True
    edited = m.edit_entry(added["id"], "Panels live in ~/panels")
    assert edited["id"] != added["id"]
    assert any(e["pinned"] and e["id"] == edited["id"] for e in m.list_entries())
    assert m.list_entries()[0]["provenance"]["by"] == "user"
    m.delete_entry(edited["id"])
    assert "panels" not in (home / "memories" / "MEMORY.md").read_text()
    with pytest.raises(m.MemoryError_):
        m.delete_entry("nope")
    with pytest.raises(m.MemoryError_):
        m.add_entry("memory", "x" * 5000)


def test_incognito_and_pin_hooks(home):
    m = _load("wave3_memory")
    m.set_incognito("chat-1", True)
    assert m.incognito_sessions() == ["chat-1"]
    blocked = m.pre_tool_call(tool_name="memory", args={"action": "add", "content": "x"}, session_id="chat-1")
    assert blocked["action"] == "block"
    assert m.pre_tool_call(tool_name="memory", args={"action": "add"}, session_id="chat-2") is None
    assert m.pre_tool_call(tool_name="terminal", args={}, session_id="chat-1") is None
    eid = m.entry_id("user", "Lives in Springfield")
    m.set_pinned(eid, True)
    res = m.pre_tool_call(tool_name="memory", args={"action": "remove", "target": "user", "old_text": "Springfield"}, session_id="c")
    assert res["action"] == "block"
    m.post_tool_call(tool_name="memory", args={"action": "add", "target": "memory", "content": "New fact"}, session_id="s9", status="success")
    prov = m._load_state()["provenance"][m.entry_id("memory", "New fact")]
    assert prov["by"] == "agent" and prov["session_id"] == "s9"


def test_rules_add_list_expire_remove(home):
    c = _load("wave3_control")
    (home / "config.yaml").write_text("command_allowlist:\n  - ls -la\n")
    c.add_rule("git push", time.time() + 3600, "deploys")
    c.add_rule("rm -rf build", time.time() + 1)
    rules = {r["pattern"]: r for r in c.list_rules()}
    assert rules["rm -rf build"]["risk"] == "high"
    assert rules["git push"]["risk"] == "medium"
    assert rules["ls -la"]["risk"] == "low"
    assert c.sweep_expired(now=time.time() + 10) == ["rm -rf build"]
    assert "rm -rf build" not in (home / "config.yaml").read_text()
    c.remove_rule("git push")
    assert [r["pattern"] for r in c.list_rules()] == ["ls -la"]
    with pytest.raises(c.RuleError):
        c.add_rule("x", time.time() - 5)


def test_router_mounts_wave_modules(home):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    spec = importlib.util.spec_from_file_location("_t_plugin_api", ROOT / "dashboard" / "plugin_api.py")
    api = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(api)
    app = FastAPI()
    app.include_router(api.router, prefix="/api/plugins/hermes_mobile")
    client = TestClient(app)
    assert "w3_memory" in client.get("/api/plugins/hermes_mobile/health").json()["features"]
    assert client.get("/api/plugins/hermes_mobile/w3/capabilities").json()["memory_write"] is True
    r = client.post("/api/plugins/hermes_mobile/w3/memory", json={"target": "user", "content": "Has a Grand Highlander"})
    assert r.status_code == 200, r.text
    eid = r.json()["id"]
    assert client.post(f"/api/plugins/hermes_mobile/w3/memory/{eid}/pin", json={"pinned": True}).status_code == 200
    assert client.get("/api/plugins/hermes_mobile/w3/memory").json()["entries"][0]["id"] == eid
    assert client.delete("/api/plugins/hermes_mobile/w3/memory/missing").status_code == 404
    assert client.put("/api/plugins/hermes_mobile/w3/incognito/abc", json={"enabled": True}).status_code == 200
    assert client.get("/api/plugins/hermes_mobile/w3/incognito").json()["sessions"] == ["abc"]
    r = client.post("/api/plugins/hermes_mobile/w3/approvals/rules", json={"pattern": "sudo apt update", "ttl_hours": 24})
    assert r.json()["risk"] == "high"
    assert client.get("/api/plugins/hermes_mobile/w3/approvals/rules").json()["rules"][0]["pattern"] == "sudo apt update"
    assert client.delete("/api/plugins/hermes_mobile/w3/approvals/rules", params={"pattern": "sudo apt update"}).status_code == 200


def test_lifecycle_register_adds_hooks(home):
    spec = importlib.util.spec_from_file_location("_t_hermes_mobile_pkg", ROOT / "__init__.py", submodule_search_locations=[str(ROOT)])
    pkg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pkg)

    class Ctx:
        def __init__(self):
            self.hooks = []

        def register_hook(self, name, cb):
            self.hooks.append(name)

    ctx = Ctx()
    pkg.register(ctx)
    assert {"pre_tool_call", "post_tool_call", "on_session_start"} <= set(ctx.hooks)
