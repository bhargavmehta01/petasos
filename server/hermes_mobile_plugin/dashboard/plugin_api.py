"""Routes for /api/plugins/hermes_mobile/. Loaded by the Hermes dashboard plugin host.

This file stays tiny: it mounts a health route and lets every wave module in the
parent folder register its own routes through ``registry.register_all``.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from fastapi import APIRouter

_PLUGIN_DIR = Path(__file__).resolve().parent.parent


def _load_registry():
    name = "hermes_mobile_plugin_registry"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, _PLUGIN_DIR / "registry.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


router = APIRouter()
_registry = _load_registry()
FEATURES = _registry.register_all(router, _PLUGIN_DIR)


@router.get("/health")
async def health():
    return {"plugin": "hermes_mobile", "version": "0.1.0", "features": FEATURES}
