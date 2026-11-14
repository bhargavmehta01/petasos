"""Hermes lifecycle entrypoint. No live work on import."""

from pathlib import Path


def register(ctx):
    from hermes_constants import get_hermes_home

    from .mobile_push.config import Profile
    from .mobile_push.service import Runtime

    profile = Profile(Path(get_hermes_home()).resolve())
    policy = profile.policy()
    # Install the lifecycle owner even if the operator policy is disabled.
    # Runtime.deliver_one() and observer callbacks re-read policy on every
    # operation and refuse to send/store when it is disabled. A later policy
    # enable must wake the existing worker without a gateway restart.
    if policy.enabled:
        policy.public_key()  # reject an invalid enabled VAPID key on load
    runtime = Runtime(profile)
    ctx.on_unload(runtime.stop)  # teardown recorded BEFORE resources or callbacks
    runtime.initialise()
    ctx.register_hook("on_session_end", runtime.session_end)
    ctx.register_hook("on_human_input_request", runtime.human_input)
    ctx.register_hook("on_human_input_resolved", runtime.human_resolved)
    runtime.start()
