"""Outbound-only Petasos platform backed by paired encrypted push devices.

No inbound messages, no new device credentials, no model-callable send tool.
The Hermes cron worker enqueues an authenticated, generation-bound result into
the existing mobile-push companion's durable sender.
"""
from pathlib import Path

from .config import Profile, Rejected, identifier
from .store import Store


def _profile() -> Profile:
    from hermes_constants import get_hermes_home
    return Profile(Path(get_hermes_home()).resolve())


def check_requirements() -> bool:
    """Pure inspection; do not create a new SQLite store during status probes."""
    try:
        profile = _profile()
        return profile.policy().enabled and profile.database.is_file()
    except (OSError, ValueError):
        return False


def _auto_enable() -> dict | None:
    from gateway.platforms._shared import get_scoped_secret, seed_extra_from_env

    home = get_scoped_secret("HERMES_MOBILE_HOME_CHANNEL", "").strip()
    if not identifier(home) or not check_requirements():
        return None
    return seed_extra_from_env((), home_env="HERMES_MOBILE_HOME_CHANNEL")


async def standalone_send(
    pconfig,
    chat_id,
    message,
    *,
    thread_id=None,
    media_files=None,
    force_document=False,
):
    if thread_id or media_files or force_document:
        return {"error": "Petasos currently accepts text-only cron delivery"}
    if not isinstance(chat_id, str) or not identifier(chat_id):
        return {"error": "Petasos requires a paired device installation ID"}
    if not isinstance(message, str):
        return {"error": "Petasos requires a text message"}
    if not message.strip() or message.strip() == "[SILENT]":
        return {"success": True, "message_id": "silent"}
    try:
        profile = _profile()
        if not profile.database.is_file():
            return {"error": "The mobile-push companion is not installed"}
        event_id = Store(profile.database).record_cron(chat_id, message, profile.policy())
        return {"success": True, "message_id": event_id}
    except Rejected as exc:
        return {"error": str(exc)}
    except (OSError, ValueError):
        # Do not disclose operator filesystem paths, endpoints or registration keys.
        return {"error": "Petasos delivery unavailable; check companion status"}


def register_platform(ctx):
    # Import the host's stable, public adapter API only at platform-registration
    # time. An outbound-only adapter never registers an inbound message surface.
    from gateway.config import Platform
    from gateway.platforms.base import BasePlatformAdapter, SendResult

    class HermesMobileAdapter(BasePlatformAdapter):
        def __init__(self, config):
            super().__init__(config, Platform("hermes_mobile"))

        async def connect(self, *, is_reconnect=False):
            if not check_requirements():
                return False
            self._mark_connected()
            return True

        async def disconnect(self):
            self._mark_disconnected()

        async def get_chat_info(self, chat_id):
            # Required by BasePlatformAdapter. Expose only a generic label, never device data.
            return {"name": "Petasos device", "type": "dm"}

        async def send(self, chat_id, content, reply_to=None, metadata=None):
            result = await standalone_send(self.config, chat_id, content)
            return SendResult(
                success=result.get("success") is True,
                message_id=result.get("message_id"),
                error=result.get("error"),
            )

    ctx.register_platform(
        name="hermes_mobile",
        label="Petasos",
        adapter_factory=HermesMobileAdapter,
        check_fn=check_requirements,
        env_enablement_fn=_auto_enable,
        cron_deliver_env_var="HERMES_MOBILE_HOME_CHANNEL",
        standalone_sender_fn=standalone_send,
        max_message_length=65536,
        platform_hint="Petasos is an outbound-only, paired Android notification destination.",
    )
