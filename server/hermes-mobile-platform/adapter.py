"""Hermes platform plugin: outbound Petasos cron transport.

The encrypted mobile-push companion remains a separate general plugin.
Only trusted server-side code is imported from its installed plugin directory.
No inbound channel, model-callable send tool, or remote registration bypass.
"""
from __future__ import annotations

import hashlib
import importlib
import importlib.util
import sys
from pathlib import Path


def register(ctx):
    from hermes_constants import get_hermes_home

    home = Path(get_hermes_home()).resolve()
    source = home / "plugins" / "mobile-push" / "mobile_push"
    init = source / "__init__.py"
    if not init.is_file():
        raise RuntimeError(
            "Petasos requires the separately installed mobile-push companion"
        )
    # An isolated package namespace preserves relative imports and prevents
    # accidentally importing another profile's installed companion code.
    name = "_hermes_mobile_companion_" + hashlib.sha256(str(source).encode()).hexdigest()[:16]
    if name not in sys.modules:
        spec = importlib.util.spec_from_file_location(
            name, init, submodule_search_locations=[str(source)]
        )
        if spec is None or spec.loader is None:
            raise RuntimeError("Petasos companion is unavailable")
        package = importlib.util.module_from_spec(spec)
        sys.modules[name] = package
        try:
            spec.loader.exec_module(package)
        except Exception:
            sys.modules.pop(name, None)
            raise
    platform = importlib.import_module(name + ".platform")
    platform.register_platform(ctx)
