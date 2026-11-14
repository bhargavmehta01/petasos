# Petasos Wave 4: novel features

Branch `wave-4`. App code lives in `lib/hermes_mobile/features/wave4_novel/`, tests in
`test/hermes_mobile/wave4/`, the server piece in `server/hermes_mobile_plugin/wave4_autopilot.py`
(routes under `/api/plugins/hermes_mobile/w4/`). Shared files only gained small blocks
fenced with `// --- wave4 ---`.

Everything works in demo mode (`DemoWave4Api` has sample data for every feature).
On a live server the app probes `GET /api/plugins/hermes_mobile/w4/status`; when the
plugin is missing each feature falls back or explains what it needs.

| Feature | Without the plugin | With the plugin |
|---|---|---|
| Watchers (status cards, proposals on repeated asks) | Hermes cron jobs named `Watch: …` are the watchers; create, pause, run now and delete go through the cron API | Stored watchers with last value, change line and history; still backed by a `Watch: …` cron job that reports back |
| Commitments (promises → due list) | Extracted on the phone from chats it has open (or "Scan recent chats", which loads the 8 newest) | Plus a server scan of the last 7 days of `state.db`, and agent-added commitments; done state syncs |
| "While you slept" recap | Cron runs since you last looked, read-only | Everything the agent logged via `POST w4/actions`, cron runs, watcher alerts, trigger runs; Revert schedules a one-shot cron job with the action's `revert_prompt` |
| 10 s undo window | On the phone: approvals and card buttons that send, post, order or pay wait 10 s with an Undo bar (Off/5/10/30 s in Proactivity settings). Local commands are not delayed | Plus server-held sends: the agent registers a send with `POST w4/outbound`, Home shows "Going out" with a countdown and Undo, and the agent checks `GET w4/outbound/{id}` before sending |
| Proactivity dial (quiet/balanced/chatty) | Saved on the phone; "Tell Hermes" asks the agent to save the rule in memory | `PUT w4/proactivity` writes one `Proactivity: …` entry into `memories/USER.md` (replacing the old one) |
| Offline queue | Works fully on the phone: a send that fails with a network error moves to a queue (persisted), health is checked every 15 s, and the queue drains in order into the same chats | — |
| Dashboard hand-off | Chat long-press → "Continue on the dashboard" opens `<dashboard>/chat?resume=<session id>` | — |
| Context triggers (opt-in) | Native listeners (`HermesMobileContextTriggers.kt`): charging (Dart applies the 9 pm–2 am window), car Bluetooth (optional name match), arrive home (proximity alert at "lat,lng"), calendar event end (polls every minute). Each fires a new chat with its prompt; 30 min cooldown | Trigger runs are logged into the recap |
| Confidence and source chips | Under each finished reply: confidence (explicit `Confidence: high` line, hedging words, or ≥2 sources/web tools), "N sources" (tap for the list), "From memory", tools used | — |
| Wear OS tile | Documented stub in `wear/` (not built by CI) reading `GET w4/glance` | — |

## Install the server plugin

```sh
ln -s "$PWD/server/hermes_mobile_plugin" ~/.hermes/plugins/hermes_mobile   # or copy the folder
# restart the Hermes dashboard so it mounts /api/plugins/hermes_mobile/
curl -s http://<host>:9119/api/plugins/hermes_mobile/w4/status
```

Plugin tests: `python -m pytest server/hermes_mobile_plugin/tests -q` (needs fastapi, httpx, pytest).

## Agent conventions (add to a skill or SOUL.md)

- Before sending an email/message/post on the user's behalf, `POST /api/plugins/hermes_mobile/w4/outbound`
  `{"summary": "Email to …", "kind": "email"}`, wait until `release_at`, then send only if
  `GET /api/plugins/hermes_mobile/w4/outbound/{id}` says `released` (not `undone`).
- After doing something on your own (cron, overnight work), `POST /api/plugins/hermes_mobile/w4/actions`
  `{"summary": "…", "kind": "message|file|cron|purchase", "detail": "…", "revert_prompt": "how to undo it"}`.
- Watcher cron prompts already tell the agent to `POST …/w4/watchers/{id}/report`.
- End uncertain answers with `Confidence: low|medium|high` to drive the chip.

## Context triggers: limits

- Listeners run while the app process is alive (the keep-alive service helps). There is no
  background-location permission, so "arrive home" does not wake a killed app.
- Android permissions are asked only when a trigger is turned on: location (home), nearby
  devices (car Bluetooth, Android 12+), calendar (meeting end). Charging needs none.
- The native code was written without a local Android SDK; the `build-apk` workflow on
  `wave-4` is the compile check.
