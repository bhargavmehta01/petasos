"""The gateway must be able to construct the Petasos adapter.

Hermes' BasePlatformAdapter is abstract (connect, disconnect, send, get_chat_info).
A missing override only surfaces at gateway start as "adapter creation failed",
so stub the host modules with the same abstract surface and build the adapter.
"""
import abc
import asyncio
import sys
import types

from mobile_push import platform


class _Platform(str):
    pass


class _SendResult:
    def __init__(self, success, message_id=None, error=None):
        self.success, self.message_id, self.error = success, message_id, error


class _Base(abc.ABC):
    def __init__(self, config, platform):
        self.config, self.platform, self.connected = config, platform, False

    def _mark_connected(self):
        self.connected = True

    def _mark_disconnected(self):
        self.connected = False

    @abc.abstractmethod
    async def connect(self, *, is_reconnect=False): ...

    @abc.abstractmethod
    async def disconnect(self): ...

    @abc.abstractmethod
    async def send(self, chat_id, content, reply_to=None, metadata=None): ...

    @abc.abstractmethod
    async def get_chat_info(self, chat_id): ...


def test_registered_adapter_is_constructible(monkeypatch):
    config_mod = types.ModuleType("gateway.config")
    config_mod.Platform = _Platform
    base_mod = types.ModuleType("gateway.platforms.base")
    base_mod.BasePlatformAdapter = _Base
    base_mod.SendResult = _SendResult
    for name, module in {
        "gateway": types.ModuleType("gateway"),
        "gateway.platforms": types.ModuleType("gateway.platforms"),
        "gateway.config": config_mod,
        "gateway.platforms.base": base_mod,
    }.items():
        monkeypatch.setitem(sys.modules, name, module)

    registered = {}

    class _Ctx:
        def register_platform(self, **kwargs):
            registered.update(kwargs)

    platform.register_platform(_Ctx())
    assert registered["name"] == "hermes_mobile"
    assert registered["cron_deliver_env_var"] == "HERMES_MOBILE_HOME_CHANNEL"

    adapter = registered["adapter_factory"](object())  # raises TypeError if abstract
    info = asyncio.run(adapter.get_chat_info("0a1b2c3d-0000-4000-8000-000000000000"))
    assert info["type"] == "dm"
    assert "0a1b2c3d" not in info["name"]  # never echo the device ID
