"""Cron mobile delivery: paired-device authorization, confidentiality and recovery."""
import asyncio
import json

import pytest

from conftest import PREFIX, activate
from test_outbox import RecordingSender
from mobile_push.config import Rejected
from mobile_push import platform


def owner(env):
    env.config["principals"][0]["owner_all_sessions"] = True
    env.save()


def paired(env, installation="phone", kinds=None):
    body = dict(env.body)
    body.pop("session_ids")
    body["session_scope"] = "authorized"
    body["event_kinds"] = kinds or [
        "turn_done", "turn_error", "input", "input_resolved", "cron_result"
    ]
    body["registration_nonce"] = "nonce_0123456789abcdef_" + installation
    answer = env.client.put(f"{PREFIX}/registrations/{installation}", json=body)
    assert answer.status_code == 200, answer.text
    generation = answer.json()["generation"]
    with env.runtime.store.connection() as db:
        row = db.execute(
            "SELECT payload FROM outbox WHERE installation=? AND done=0",
            (installation,),
        ).fetchone()
    challenge = json.loads(row[0])["challenge"]
    answer = env.client.post(
        f"{PREFIX}/registrations/{installation}/confirm",
        json={"generation": generation, "challenge": challenge},
    )
    assert answer.status_code == 200, answer.text
    return generation


def bound(env, generation, installation="phone"):
    return env.client.get(
        f"{PREFIX}/events",
        params={"installation_id": installation, "generation": generation},
    )


def test_cron_result_goes_only_to_paired_device_and_never_to_hint(env):
    owner(env)
    generation = paired(env)
    paired(env, "other-device")
    message = "Action before noon: confirm the appointment."
    event_id = env.runtime.store.record_cron("phone", message, env.profile.policy())
    events = bound(env, generation).json()["events"]
    assert [(e["event_id"], e["kind"]) for e in events] == [(event_id, "cron_result")]
    assert "session_id" not in events[0]
    assert bound(env, 1, "other-device").json()["events"] == []
    assert all(e["kind"] != "cron_result" for e in env.client.get(f"{PREFIX}/events").json()["events"])
    response = env.client.get(
        f"{PREFIX}/cron-results/{event_id}",
        params={"installation_id": "phone", "generation": generation},
    )
    assert response.status_code == 200
    assert response.json() == {"event_id": event_id, "message": message}
    assert env.client.get(
        f"{PREFIX}/cron-results/{event_id}",
        params={"installation_id": "other-device", "generation": 1},
    ).status_code == 404

    sender = RecordingSender()
    env.runtime.sender = sender
    assert env.runtime.deliver_one()
    assert sender.hints[0]["kind"] == "cron_result"
    assert message not in json.dumps(sender.hints[0])
    assert "session_id" not in sender.hints[0]
    assert not env.runtime.deliver_one()


def test_mobile_destination_requires_owner_approved_authorized_scope(env):
    # A signed-in account allowed to read a single chat cannot receive
    # arbitrary cron output, even when it registered a genuine push endpoint.
    generation = paired(env)
    with pytest.raises(Rejected, match="not consented"):
        env.runtime.store.record_cron("phone", "private cron output", env.profile.policy())
    assert bound(env, generation).json()["events"] == []
    owner(env)
    assert env.runtime.store.record_cron("phone", "allowed now", env.profile.policy())


def test_explicit_scope_and_legacy_kinds_cannot_receive_cron(env):
    owner(env)
    activate(env)
    with pytest.raises(Rejected):
        env.runtime.store.record_cron("phone", "not opted in", env.profile.policy())


def test_result_revocation_and_owner_acl_changes_fail_closed(env):
    owner(env)
    generation = paired(env)
    event_id = env.runtime.store.record_cron("phone", "secret", env.profile.policy())
    env.config["principals"][0].pop("owner_all_sessions")
    env.save()
    result = env.client.get(
        f"{PREFIX}/cron-results/{event_id}",
        params={"installation_id": "phone", "generation": generation},
    )
    assert result.status_code == 403
    env.config["principals"][0]["owner_all_sessions"] = True
    env.save()
    env.runtime.store.revoke(("fixture", "alice"), "phone")
    result = env.client.get(
        f"{PREFIX}/cron-results/{event_id}",
        params={"installation_id": "phone", "generation": generation},
    )
    assert result.status_code == 409
    sender = RecordingSender()
    env.runtime.sender = sender
    assert not env.runtime.deliver_one()
    assert sender.hints == []


def test_silent_output_does_not_create_events(env):
    owner(env)
    paired(env)
    for message in ("", "  ", "[SILENT]", "  [SILENT]  "):
        assert env.runtime.store.record_cron("phone", message, env.profile.policy()) == "silent"
    with env.runtime.store.connection() as db:
        assert db.execute("SELECT count(*) FROM cron_results").fetchone()[0] == 0


def test_standalone_sender_returns_failure_not_false_success(env, monkeypatch):
    owner(env)
    paired(env)
    monkeypatch.setattr(platform, "_profile", lambda: env.profile)
    async def send(destination, message):
        return await platform.standalone_send(None, destination, message)
    successful = asyncio.run(send("phone", "Ready for tomorrow"))
    assert successful["success"] is True and successful["message_id"] != "silent"
    missing = asyncio.run(send("unpaired-device", "Private"))
    assert "error" in missing and "success" not in missing
    silent = asyncio.run(send("phone", "[SILENT]"))
    assert silent == {"success": True, "message_id": "silent"}
    invalid = asyncio.run(
        platform.standalone_send(None, "phone", "test", media_files=["private.pdf"])
    )
    assert "error" in invalid


def test_generic_turn_hook_does_not_notify_silent_cron_session(env):
    import sqlite3
    owner(env)
    paired(env)
    with sqlite3.connect(env.profile.home / "state.db") as db:
        db.execute("ALTER TABLE sessions ADD COLUMN source TEXT DEFAULT ''")
        db.execute("UPDATE sessions SET source='cron' WHERE id='session-a'")
    env.runtime.session_end(
        session_id="session-a", turn_id="scheduled-turn",
        completed=True, failed=False, interrupted=False,
        turn_exit_reason="stop",
    )
    assert all(
        item["kind"] != "turn_done"
        for item in bound(env, 1).json()["events"]
    )
    assert env.runtime.store.record_cron("phone", "[SILENT]", env.profile.policy()) == "silent"


def test_cron_result_bound_generation_is_required(env):
    owner(env)
    generation = paired(env)
    event_id = env.runtime.store.record_cron("phone", "private", env.profile.policy())
    assert env.client.get(f"{PREFIX}/cron-results/{event_id}").status_code == 422
    assert env.client.get(
        f"{PREFIX}/cron-results/{event_id}",
        params={"installation_id": "phone", "generation": generation + 1},
    ).status_code == 409
    env.identity[0] = None
    assert env.client.get(
        f"{PREFIX}/cron-results/{event_id}",
        params={"installation_id": "phone", "generation": generation},
    ).status_code == 401
