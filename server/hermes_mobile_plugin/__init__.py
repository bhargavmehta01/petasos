"""Petasos companion plugin for Hermes (server side of the Petasos Android app).

Install by copying or symlinking this folder to ``~/.hermes/plugins/hermes_mobile``. The
dashboard discovers ``dashboard/manifest.json`` and mounts the routes from
``dashboard/plugin_api.py`` under ``/api/plugins/hermes_mobile/``. Each app wave adds its
own ``waveN_*.py`` module next to this file; the registry finds them by name.
"""

PLUGIN_NAME = "hermes_mobile"


# --- wave3 ---
def register(ctx):
    """Hermes lifecycle entrypoint: wave modules may add hooks via ``register_hooks(ctx)``."""
    import importlib.util
    import sys
    from pathlib import Path

    here = Path(__file__).resolve().parent
    name = "hermes_mobile_plugin_registry"
    registry = sys.modules.get(name)
    if registry is None:
        spec = importlib.util.spec_from_file_location(name, here / "registry.py")
        registry = importlib.util.module_from_spec(spec)
        sys.modules[name] = registry
        spec.loader.exec_module(registry)
    for path in registry.wave_modules(here):
        try:
            hook = getattr(registry.load_module(path), "register_hooks", None)
            if callable(hook):
                hook(ctx)
        except Exception:  # one broken wave must not take the others down
            import logging

            logging.getLogger(__name__).exception("Petasos plugin: hooks failed for %s", path.name)
# --- end wave3 ---
