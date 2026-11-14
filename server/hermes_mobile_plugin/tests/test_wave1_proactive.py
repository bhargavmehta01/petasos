import base64
import importlib.util
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent


def _load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


w1 = _load("hermes_mobile_w1_test", "wave1_proactive.py")
registry = _load("hermes_mobile_registry_test", "registry.py")


def test_add_dismiss_snooze_and_unread(tmp_path):
    s = w1.Store(tmp_path)
    a = s.add_card({"title": "Approve the Costco cart", "kind": "approval",
                    "action": {"kind": "approve", "label": "Approve"}})
    s.add_card({"title": "Price drop", "source": "watch"})
    feed = s.feed()
    assert feed["unread"] == 2 and len(feed["cards"]) == 2
    s.set_state(a["id"], read=True)
    assert s.feed()["unread"] == 1
    s.set_state(a["id"], snoozed_until=time.time() + 60)
    assert [c["title"] for c in s.feed()["cards"]] == ["Price drop"]
    s.set_state(a["id"], snoozed_until=0, dismissed=True)
    assert len(s.feed()["cards"]) == 1


def test_rejects_bad_action(tmp_path):
    s = w1.Store(tmp_path)
    try:
        s.add_card({"title": "x", "action": {"kind": "explode"}})
    except ValueError:
        return
    raise AssertionError("expected ValueError")


def test_cron_brief_and_failure_cards(tmp_path):
    cron = tmp_path / "cron"
    (cron / "output" / "j1").mkdir(parents=True)
    (cron / "jobs.json").write_text(json.dumps({"jobs": [
        {"id": "j1", "name": "Morning brief", "last_status": "ok"},
        {"id": "j2", "name": "Backup check", "last_status": "error", "last_error": "jq missing"},
    ]}))
    (cron / "output" / "j1" / "2026-11-03_07-00.md").write_text(
        "# Cron Job: Morning brief\n\n## Prompt\nx\n\n## Response\n\nThree meetings today.\n")
    cards = {c["kind"]: c for c in w1.Store(tmp_path).feed()["cards"]}
    assert cards["brief"]["body"] == "Three meetings today."
    assert cards["brief"]["period"] in {"morning", "evening"}
    assert cards["alert"]["action"]["payload"] == {"cron_id": "j2"}


def test_feedback_appends_to_user_memory(tmp_path):
    s = w1.Store(tmp_path)
    (tmp_path / "memories").mkdir()
    (tmp_path / "memories" / "USER.md").write_text("Lives in Springfield.\n")
    out = s.feedback({"signal": "less", "source": "price watch", "title": "Price drop"})
    text = (tmp_path / "memories" / "USER.md").read_text()
    assert out["saved"] and "\n§\n" in text and "less price watch" in text


def test_upload_saves_file(tmp_path):
    s = w1.Store(tmp_path)
    out = s.upload({"name": "../../evil notes.pdf", "data_b64": base64.b64encode(b"%PDF").decode()})
    p = Path(out["path"])
    assert p.read_bytes() == b"%PDF" and p.parent.parent.name == "uploads"
    assert "evil notes.pdf" in p.name and ".." not in p.name


def test_registry_finds_wave_modules():
    names = [p.name for p in registry.wave_modules(HERE)]
    assert "wave1_proactive.py" in names
