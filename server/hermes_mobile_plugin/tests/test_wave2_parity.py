import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent


def _load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


w2 = _load("hermes_mobile_w2_test", "wave2_parity.py")


def test_project_instructions_round_trip(tmp_path):
    s = w2.Store(tmp_path / "hermes", user_home=tmp_path)
    assert s.project("p1")["instructions"] == ""
    s.set_instructions("p1", "  Use Flutter 3.44.  ")
    assert s.project("p1")["instructions"] == "Use Flutter 3.44."
    try:
        s.set_instructions("p1", "x" * (w2.MAX_INSTRUCTIONS + 1))
        assert False, "should reject long instructions"
    except ValueError:
        pass


def test_files_only_inside_home(tmp_path):
    proj = tmp_path / "code" / "app"
    proj.mkdir(parents=True)
    (proj / "pubspec.yaml").write_text("name: app")
    (proj / ".git").mkdir()
    (proj / "lib").mkdir()
    s = w2.Store(tmp_path / "hermes", user_home=tmp_path)
    names = [f["name"] for f in s.project("p1", str(proj))["files"]]
    assert names == ["lib/", "pubspec.yaml"]
    assert s.list_files("/etc") == []
    assert s.list_files(str(tmp_path / "missing")) == []


def test_panels_written_for_home(tmp_path):
    s = w2.Store(tmp_path / "hermes", user_home=tmp_path)
    p = s.add_panel({"title": "Backup note", "text": "B2 copy OK"})
    f = tmp_path / "hermes" / "panels" / f"{p['id']}.json"
    assert json.loads(f.read_text())["text"] == "B2 copy OK"
    assert s.panels()[0]["id"] == p["id"]
    assert s.delete_panel(p["id"]) and not f.exists()
    assert not s.delete_panel("../etc")
    try:
        s.add_panel({"title": "", "text": "x"})
        assert False
    except ValueError:
        pass


def test_profiles(tmp_path):
    home = tmp_path / "hermes"
    (home / "profiles" / "coder").mkdir(parents=True)
    s = w2.Store(home, user_home=tmp_path)
    assert [p["id"] for p in s.profiles()] == ["default", "coder"]


def test_registers_routes():
    class Router:
        def __init__(self):
            self.paths = []

        def _add(self, path):
            def deco(fn):
                self.paths.append(path)
                return fn
            return deco

        get = post = put = delete = _add

    r = Router()
    w2.register(r)
    assert "/w2/projects/{project_id}" in r.paths
    assert "/w2/panels" in r.paths
