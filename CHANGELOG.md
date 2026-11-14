# Changelog

Petasos follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). History of the
upstream engine before Petasos: [docs/CHANGELOG-hermes-android.md](docs/CHANGELOG-hermes-android.md).

## 1.0.0 — first public release

- New app UI for Hermes Agent: Home (needs you, running now, agent panels), chats and projects,
  task cards with steps and Stop, inline approvals, skills, memory, scheduled tasks, cron studio,
  usage and cost, watchers, commitments, proactivity, appearance, demo mode.
- Encrypted scheduled-task delivery: cron jobs deliver to `hermes_mobile`; the push carries no
  content and the phone fetches the result over an authenticated session. `[SILENT]` output is
  suppressed. Server plugins in `server/`.
- Clear recovery when the server retires a device registration (turn notifications off and on).
- Optional Android control from Hermes through Mobile Next MCP over wireless ADB.
- Host tooling: read-only doctor (detects services running stale plugin code), encrypted backup,
  real-scheduler acceptance test.
- Licensed AGPL-3.0; upstream engine code from rusty4444/hermes-android stays MIT.
