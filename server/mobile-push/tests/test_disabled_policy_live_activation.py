"""The lifecycle owner must wake after an operator enables an initially disabled policy."""

import importlib.util
import json
import sys
import time
from pathlib import Path
from types import SimpleNamespace

from conftest import PREFIX


class LocalSender:
    def __init__(self):
        self.kinds = []

    def send(self, registration, hint_json, policy):
        self.kinds.append(json.loads(hint_json)["kind"])
        return 201


def test_disabled_policy_starts_idle_worker_then_enabling_sends_challenge(env, monkeypatch):
    env.config["enabled"] = False
    env.save()

    monkeypatch.setitem(
        sys.modules,
        "hermes_constants",
        SimpleNamespace(get_hermes_home=lambda: str(env.profile.home)),
    )
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location(
        "_hermes_mobile_lifecycle_test_entry",
        root / "__init__.py",
        submodule_search_locations=[str(root)],
    )
    assert spec is not None and spec.loader is not None
    entry = importlib.util.module_from_spec(spec)
    monkeypatch.setitem(sys.modules, spec.name, entry)
    spec.loader.exec_module(entry)

    class Context:
        def __init__(self):
            self.on_unload_callbacks = []
            self.hooks = {}

        def on_unload(self, callback):
            self.on_unload_callbacks.append(callback)

        def register_hook(self, name, callback):
            self.hooks[name] = callback

    ctx = Context()
    entry.register(ctx)
    assert set(ctx.hooks) == {
        "on_session_end",
        "on_human_input_request",
        "on_human_input_resolved",
    }
    assert len(ctx.on_unload_callbacks) == 1
    runtime = ctx.on_unload_callbacks[0].__self__
    assert runtime.thread is not None and runtime.thread.is_alive()
    sender = LocalSender()
    runtime.sender = sender

    try:
        # With the operator policy disabled, the existing thread must not
        # deliver any event, nor grant an installation anything.
        assert runtime.deliver_one() is False
        assert sender.kinds == []

        # An operator enables the private policy *after* the gateway loaded
        # the plugin. No gateway restart or additional lifecycle registration.
        env.config["enabled"] = True
        env.save()
        response = env.client.put(
            f"{PREFIX}/registrations/phone",
            json=env.body,
        )
        assert response.status_code == 200

        deadline = time.monotonic() + 4
        while time.monotonic() < deadline and not sender.kinds:
            time.sleep(0.05)
        assert sender.kinds == ["challenge"]
        assert runtime.thread.is_alive()
    finally:
        runtime.stop()
        assert not runtime.thread.is_alive()
