"""Tiny route registry shared by every Petasos wave module.

A wave module (``waveN_<name>.py`` next to this file) defines
``register(router)`` and adds its routes under its own prefix, for example
``/w1/...``. ``plugin_api.py`` imports every wave module it finds and calls
``register`` once, so later waves never edit a shared file.
"""

from __future__ import annotations

import importlib.util
import logging
import sys
from pathlib import Path
from typing import Any, List

_log = logging.getLogger(__name__)
PLUGIN_DIR = Path(__file__).resolve().parent


def wave_modules(plugin_dir: Path = PLUGIN_DIR) -> List[Path]:
    """Wave module files in a stable order (wave1_*, wave2_*, ...)."""
    return sorted(p for p in plugin_dir.glob("wave[0-9]*_*.py") if p.is_file())


def load_module(path: Path) -> Any:
    name = f"hermes_mobile_plugin_{path.stem}"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def register_all(router: Any, plugin_dir: Path = PLUGIN_DIR) -> List[str]:
    """Calls ``register(router)`` on every wave module; returns their feature names."""
    features: List[str] = []
    for path in wave_modules(plugin_dir):
        try:
            module = load_module(path)
            register = getattr(module, "register", None)
            if register is None:
                continue
            register(router)
            features.extend(getattr(module, "FEATURES", [path.stem]))
        except Exception:  # one broken wave must not take the others down
            _log.exception("Petasos plugin: could not register %s", path.name)
    return features
