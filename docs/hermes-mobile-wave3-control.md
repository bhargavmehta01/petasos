# Petasos Wave 3: Control and trust

Everything lives in `lib/hermes_mobile/features/wave3_control/` and is reached from
Profile → **Control and trust** (plus a **Live run** bar above the composer while a
turn runs). Every feature works in demo mode (`DemoWave3Api`).

| Feature | Live source | Needs the Petasos plugin? |
|---|---|---|
| Cron studio | Dashboard `cron/jobs`, `cron/jobs/{id}`, `cron/jobs/{id}/runs`; run output from the API server's `sessions/{run}/messages` | No |
| Live run view | The chat's own SSE stream (tool progress, status, reasoning, approvals) | No |
| Memory manager (view) | Plugin, else the engine's read-only `learning/graph` facts | No (read-only without it) |
| Memory manager (edit, delete, pin, provenance, incognito) | `/api/plugins/hermes_mobile/w3/memory`, `/w3/incognito` | Yes |
| Approval rules | `/api/plugins/hermes_mobile/w3/approvals/rules` (backed by `command_allowlist`) | Yes (screen shows setup help without it) |
| Cost meter and budget alert | Dashboard `analytics/usage` (`daily` + `totals`); budget is stored on the phone | No |

## Server plugin (`server/hermes_mobile_plugin/`)

Wave 3 adds `wave3_memory.py` and `wave3_control.py`. Both follow the shared
registry contract (`register(router)` + `FEATURES`, routes under `/w3/`). Hooks need
the Hermes lifecycle side, so Wave 3 adds a fenced `register(ctx)` to `__init__.py`
(it calls each wave module's optional `register_hooks(ctx)`) and a `plugin.yaml`.

Install: copy `server/hermes_mobile_plugin` to `~/.hermes/plugins/hermes_mobile`, add `hermes_mobile` to
`plugins.enabled` in config.yaml, restart the gateway and dashboard.
Tests: `python -m pytest server/hermes_mobile_plugin/tests/test_wave3.py -q`.

- **Memory write**: edits `memories/USER.md` and `memories/MEMORY.md` through
  Hermes' own `MemoryStore` (same caps, content scan and file lock); falls back to a
  locked direct edit. Entry ids are fingerprints of target + content.
- **Pin**: pinned ids live in `plugin-data/hermes_mobile/wave3_memory.json`; a `pre_tool_call`
  hook blocks the agent's `memory` remove/replace/patch on pinned text.
- **Provenance**: a `post_tool_call` hook records which session saved an entry and
  when; edits from the phone are recorded as the user's.
- **Incognito chat**: the session id is listed in plugin state and the
  `pre_tool_call` hook blocks the `memory` tool for it. Marks expire after 30 days.
- **Approval rules**: rules are Hermes' permanent allowlist (`command_allowlist`).
  The plugin adds expiry and notes and removes expired patterns on every read and at
  `on_session_start`. Hermes re-reads hand edits to the list, so no restart is needed.
  Risk labels are a keyword heuristic, shared by the plugin and the app.

## Live run controls: what the engine exposes

Petasos chats use the Hermes API server (SSE). On that transport:

- **Stop**: native. Closing the stream interrupts the agent.
- **Pause / resume**: not exposed by any Hermes transport. Emulated: interrupt, then
  "Resume" sends a continue prompt in the same session.
- **Steer**: native only on the Desktop gateway WebSocket
  (`DesktopGatewayClient.steerPrompt` → `session.steer`), which Petasos chats do not use.
  Emulated: interrupt, then send the guidance as the next turn.
- **Take over**: emulated: interrupt, show the commands and files touched (copyable)
  and a link to the dashboard, then "Hand back" sends a note and continues.
- **Files touched / commands**: tool progress events carry only the tool name and a
  short preview, so files and commands are read from those previews (best effort).
  Full tool arguments would need the engine to include them in `hermes.tool.progress`.

Missing in the engine for a native experience: a pause/resume control on the API
server, `steer` on the API-server run path, and structured tool arguments in
progress events.
