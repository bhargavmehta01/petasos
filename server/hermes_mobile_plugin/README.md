# Petasos server plugin for Hermes

Server-side companion for the Petasos Android app. It runs inside the Hermes
dashboard (`hermes dashboard` / the web server) as a dashboard plugin and serves
JSON routes under `/api/plugins/hermes_mobile/`. It has no dashboard tab of its own.

The app works without it: features that need it hide themselves or show setup
help, and demo mode has sample data for everything.

## Install

```bash
# on the Hermes host
mkdir -p ~/.hermes/plugins
cp -r server/hermes_mobile_plugin ~/.hermes/plugins/hermes_mobile      # or: ln -s "$PWD/server/hermes_mobile_plugin" ~/.hermes/plugins/hermes_mobile
# restart the dashboard so it discovers the plugin
systemctl --user restart hermes-dashboard 2>/dev/null || true   # or stop/start `hermes dashboard`
curl -s -H "Authorization: Bearer $HERMES_DASHBOARD_TOKEN" http://127.0.0.1:9119/api/plugins/hermes_mobile/health
```

The health route answers `{"plugin": "hermes_mobile", "features": [...]}`. In the app,
the dashboard URL must be set under Profile → Connection (the same one Panels
and Projects use).

## Layout

| File | What it is |
|---|---|
| `dashboard/manifest.json` | Plugin manifest the dashboard discovers (hidden tab, `api: plugin_api.py`). |
| `dashboard/plugin_api.py` | Mounts `/health` and loads every wave module through the registry. |
| `registry.py` | Finds `waveN_*.py` files next to it and calls `register(router)` on each. |
| `waveN_*.py` | One file per app wave. Each defines `FEATURES` and `register(router)` and keeps its routes under `/wN/...`. |
| `tests/` | `python3 -m pytest server/hermes_mobile_plugin/tests` |

Rules for a wave module: import FastAPI names (`Request`, `HTTPException`) at
module top level, not inside `register`, because FastAPI resolves string
annotations against module globals. Keep state under `~/.hermes/hermes_mobile/`.

## Wave 1 routes (`wave1_proactive.py`)

| Route | Use |
|---|---|
| `GET /w1/feed` | Cards for the Brief tab and feed: `{cards, unread}`. |
| `POST /w1/cards` | Add a card: `{title, body, kind, source, priority, chat_id, action: {kind: approve\|snooze\|reply\|run\|open, label, payload}}`. |
| `POST /w1/cards/{id}/dismiss` · `/restore` · `/read` · `/snooze {minutes}` · `/act {action}` | Card state. |
| `POST /w1/feedback` | `{card_id, signal: more\|less, source, title}`; appends one entry to `~/.hermes/memories/USER.md`. |
| `POST /w1/upload` | `{name, data_b64}` (max 20 MB); saves to `~/.hermes/hermes_mobile/uploads/` and returns the host path the agent can read. |

Briefs: the newest output (last 36 h) of any cron job whose name contains brief,
digest, recap, summary, morning or evening becomes a morning or evening card. A
cron job whose last run failed becomes an alert card with a "Run again" action.

Pushing a card from a cron script or skill:

```bash
curl -s -X POST -H "Authorization: Bearer $HERMES_DASHBOARD_TOKEN" -H 'content-type: application/json' \
  http://127.0.0.1:9119/api/plugins/hermes_mobile/w1/cards \
  -d '{"title":"Costco cart ready","body":"3 items, $26.95","kind":"approval","source":"shopping","action":{"kind":"approve","label":"Approve"}}'
```
