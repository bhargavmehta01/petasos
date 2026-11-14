"""Tests for the Wave 4 autopilot routes. Run: python -m pytest server/hermes_mobile_plugin/tests"""

import importlib.util
import sqlite3
import sys
import time
import types
from datetime import datetime
from pathlib import Path

import pytest
from fastapi import APIRouter, FastAPI
from fastapi.testclient import TestClient

PLUGIN = Path(__file__).resolve().parents[1]
PREFIX = "/api/plugins/hermes_mobile"


def _load():
    spec = importlib.util.spec_from_file_location("hermes_mobile_w4_test", PLUGIN / "wave4_autopilot.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def w4(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_MOBILE_PLUGIN_HOME", str(tmp_path))
    monkeypatch.delitem(sys.modules, "cron", raising=False)
    return _load()


@pytest.fixture
def client(w4):
    router = APIRouter()
    w4.register(router)
    app = FastAPI()
    app.include_router(router, prefix=PREFIX)
    return TestClient(app)


@pytest.fixture
def fake_cron(monkeypatch):
    calls = []
    jobs = types.ModuleType("cron.jobs")
    jobs.create_job = lambda **kw: calls.append(("create", kw)) or {"id": f"j{len(calls)}"}
    jobs.trigger_job = lambda jid: calls.append(("trigger", jid))
    jobs.pause_job = lambda jid: calls.append(("pause", jid))
    jobs.resume_job = lambda jid: calls.append(("resume", jid))
    jobs.remove_job = lambda jid: calls.append(("remove", jid)) or True
    jobs.list_jobs = lambda include_disabled=False: [
        {"id": "brief", "name": "Morning brief", "last_run_at": time.time() - 60, "last_status": "ok"},
        {"id": "old", "name": "Old", "last_run_at": time.time() - 90000, "last_status": "ok"},
        {"id": "bad", "name": "Backup", "last_run_at": time.time() - 30, "last_status": "error"},
    ]
    pkg = types.ModuleType("cron")
    pkg.jobs = jobs
    monkeypatch.setitem(sys.modules, "cron", pkg)
    monkeypatch.setitem(sys.modules, "cron.jobs", jobs)
    return calls


def test_status_and_registry_discovery(client):
    r = client.get(f"{PREFIX}/w4/status").json()
    assert r["ok"] is True
    assert "watchers" in r["features"]
    reg_spec = importlib.util.spec_from_file_location("hermes_mobile_reg_test", PLUGIN / "registry.py")
    reg = importlib.util.module_from_spec(reg_spec)
    reg_spec.loader.exec_module(reg)
    assert any(p.name == "wave4_autopilot.py" for p in reg.wave_modules(PLUGIN))


def test_watchers_lifecycle_without_cron(client):
    r = client.post(f"{PREFIX}/w4/watchers", json={"title": "XM6", "target": "bestbuy", "condition": "below $300"})
    assert r.status_code == 200
    w = r.json()["watcher"]
    assert w["status"] == "pending" and w["cron_id"] is None
    wid = w["id"]
    assert client.post(f"{PREFIX}/w4/watchers/{wid}/report",
                       json={"status": "changed", "value": "$279", "change": "Dropped $120"}).json()["watcher"]["status"] == "changed"
    listed = client.get(f"{PREFIX}/w4/watchers").json()["watchers"]
    assert listed[0]["last_value"] == "$279"
    assert listed[0]["history"] == ["$279"]
    # A change lands in the recap.
    recap = client.get(f"{PREFIX}/w4/recap", params={"since": 0}).json()["actions"]
    assert any(a["kind"] == "watcher" for a in recap)
    assert client.post(f"{PREFIX}/w4/watchers/{wid}/pause").json()["watcher"]["status"] == "paused"
    # Reports while paused do not flip the status.
    client.post(f"{PREFIX}/w4/watchers/{wid}/report", json={"status": "ok"})
    assert client.get(f"{PREFIX}/w4/watchers").json()["watchers"][0]["status"] == "paused"
    assert client.delete(f"{PREFIX}/w4/watchers/{wid}").status_code == 200
    assert client.delete(f"{PREFIX}/w4/watchers/{wid}").status_code == 404
    assert client.post(f"{PREFIX}/w4/watchers", json={"title": ""}).status_code == 400


def test_watchers_use_cron_when_available(client, fake_cron):
    w = client.post(f"{PREFIX}/w4/watchers", json={"title": "Passport", "target": "status page", "every": "Every day"}).json()["watcher"]
    kind, kw = fake_cron[0]
    assert kind == "create"
    assert kw["name"] == "Watch: Passport"
    assert kw["schedule"] == "every 1d"
    assert w["id"] in kw["prompt"] and "status page" in kw["prompt"]
    client.post(f"{PREFIX}/w4/watchers/{w['id']}/check")
    client.post(f"{PREFIX}/w4/watchers/{w['id']}/pause")
    client.delete(f"{PREFIX}/w4/watchers/{w['id']}")
    assert [c[0] for c in fake_cron] == ["create", "trigger", "pause", "remove"]


def test_recap_includes_cron_runs_and_revert_schedules_job(client, fake_cron):
    a = client.post(f"{PREFIX}/w4/actions", json={
        "summary": "Archived 23 promo emails", "kind": "message",
        "revert_prompt": "Move them back to the inbox."}).json()["action"]
    assert "revert_prompt" not in a
    since = time.time() - 3600
    actions = client.get(f"{PREFIX}/w4/recap", params={"since": since}).json()["actions"]
    by_summary = {x["summary"]: x for x in actions}
    assert by_summary["Archived 23 promo emails"]["revertible"] is True
    assert by_summary['Ran "Morning brief"']["ok"] is True
    assert by_summary['Ran "Backup"']["ok"] is False
    assert 'Ran "Old"' not in by_summary
    assert client.post(f"{PREFIX}/w4/actions/{a['id']}/revert").json()["ok"] is True
    assert client.post(f"{PREFIX}/w4/actions/{a['id']}/revert").json()["ok"] is False
    revert_job = [c for c in fake_cron if c[0] == "create"][-1][1]
    assert revert_job["repeat"] == 1 and "Move them back" in revert_job["prompt"]
    after = {x["summary"]: x for x in client.get(f"{PREFIX}/w4/recap", params={"since": since}).json()["actions"]}
    assert after["Archived 23 promo emails"]["revertible"] is False


def test_outbound_hold_and_undo(client):
    h = client.post(f"{PREFIX}/w4/outbound", json={"summary": "Email landlord", "hold_seconds": 10}).json()
    assert client.get(f"{PREFIX}/w4/outbound/{h['id']}").json()["state"] == "held"
    assert [x["id"] for x in client.get(f"{PREFIX}/w4/outbound").json()["held"]] == [h["id"]]
    assert client.post(f"{PREFIX}/w4/outbound/{h['id']}/undo").json()["ok"] is True
    assert client.get(f"{PREFIX}/w4/outbound/{h['id']}").json()["state"] == "undone"
    assert client.get(f"{PREFIX}/w4/outbound").json()["held"] == []
    # A zero hold is released at once and cannot be undone.
    z = client.post(f"{PREFIX}/w4/outbound", json={"summary": "Ping", "hold_seconds": 0}).json()
    assert client.get(f"{PREFIX}/w4/outbound/{z['id']}").json()["state"] == "released"
    assert client.post(f"{PREFIX}/w4/outbound/{z['id']}/undo").json()["ok"] is False
    assert client.get(f"{PREFIX}/w4/outbound/nope").status_code == 404


def test_proactivity_writes_one_rule(client, tmp_path):
    mem = tmp_path / "memories" / "USER.md"
    mem.parent.mkdir(parents=True)
    mem.write_text("Lives in Springfield.\n§\nProactivity: chatty. old rule")
    assert client.get(f"{PREFIX}/w4/proactivity").json()["level"] is None
    r = client.put(f"{PREFIX}/w4/proactivity", json={"level": "quiet"}).json()
    assert r["ok"] and r["rule_written"]
    entries = mem.read_text().split("\n§\n")
    assert entries[0] == "Lives in Springfield."
    assert len([e for e in entries if e.startswith("Proactivity:")]) == 1
    assert entries[-1].startswith("Proactivity: quiet.")
    assert client.get(f"{PREFIX}/w4/proactivity").json()["level"] == "quiet"
    assert client.put(f"{PREFIX}/w4/proactivity", json={"level": "loud"}).status_code == 400


def test_commitments_scan_state_db_and_overrides(client, tmp_path, w4):
    db = sqlite3.connect(tmp_path / "state.db")
    db.execute("CREATE TABLE sessions (id TEXT, title TEXT, started_at REAL)")
    db.execute("CREATE TABLE messages (id INTEGER PRIMARY KEY, session_id TEXT, role TEXT, content TEXT)")
    db.execute("INSERT INTO sessions VALUES ('s1', 'Flights', ?)", (time.time() - 100,))
    db.executemany("INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)", [
        ("s1", "user", "Remind me to call the bank tomorrow."),
        ("s1", "assistant", "I'll check the Delta fare again on Friday. Want United too?"),
        ("s1", "tool", "{}"),
    ])
    db.commit()
    db.close()
    items = client.get(f"{PREFIX}/w4/commitments").json()["commitments"]
    texts = {c["text"]: c for c in items}
    assert "Call the bank tomorrow" in texts
    agent = [c for c in items if c["owner"] == "agent"][0]
    assert "Delta fare" in agent["text"] and agent["chat_title"] == "Flights"
    # Marking a scanned one done sticks across scans.
    client.put(f"{PREFIX}/w4/commitments/{agent['id']}", json={"done": True})
    again = {c["id"]: c for c in client.get(f"{PREFIX}/w4/commitments").json()["commitments"]}
    assert again[agent["id"]]["done"] is True
    added = client.post(f"{PREFIX}/w4/commitments", json={"text": "Send the report", "owner": "agent"}).json()["commitment"]
    assert added["source"] == "server"
    assert client.post(f"{PREFIX}/w4/commitments", json={}).status_code == 400


def test_parse_due_matches_app_rules(w4):
    now = datetime(2026, 11, 3, 10)  # Tuesday
    assert w4.parse_due("by tonight", now) == datetime(2026, 11, 3, 20)
    assert w4.parse_due("on Friday", now) == datetime(2026, 11, 6, 9)
    assert w4.parse_due("Tuesday", now) == datetime(2026, 11, 10, 9)
    assert w4.parse_due("tomorrow", now) == datetime(2026, 11, 4, 9)
    assert w4.parse_due("whenever", now) is None


def test_glance_and_triggers(client):
    w = client.post(f"{PREFIX}/w4/watchers", json={"title": "XM6", "target": "bb"}).json()["watcher"]
    client.post(f"{PREFIX}/w4/watchers/{w['id']}/report", json={"status": "changed", "value": "$279"})
    client.post(f"{PREFIX}/w4/triggers/fired", json={"kind": "arrive_home", "prompt": "Home"})
    g = client.get(f"{PREFIX}/w4/glance").json()
    assert g["watchers_changed"] == 1
    assert g["headline"] == "XM6: $279"
    assert g["overnight_actions"] >= 2


def test_mounted_through_plugin_api(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_MOBILE_PLUGIN_HOME", str(tmp_path))
    for name in [n for n in sys.modules if n.startswith("hermes_mobile_plugin_")]:
        monkeypatch.delitem(sys.modules, name)
    spec = importlib.util.spec_from_file_location("hermes_mobile_api_test", PLUGIN / "dashboard" / "plugin_api.py")
    api = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(api)
    assert "watchers" in api.FEATURES
    app = FastAPI()
    app.include_router(api.router, prefix=PREFIX)
    c = TestClient(app)
    assert c.get(f"{PREFIX}/w4/status").json()["ok"] is True
    assert "watchers" in c.get(f"{PREFIX}/health").json()["features"]
