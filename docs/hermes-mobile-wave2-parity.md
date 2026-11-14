# Petasos Wave 2: parity polish

Code: `lib/hermes_mobile/features/wave2_parity/`. Tests: `test/hermes_mobile/wave2/`.
Server: `server/hermes_mobile_plugin/wave2_parity.py` (+ `tests/test_wave2_parity.py`).
Every edit to a shared file is fenced with `// --- wave2 ---`.

Everything works in demo mode (`DemoWave2Api` serves models, profiles, project
instructions/files and panels). Live mode uses the engine clients, plus the
optional Petasos plugin where noted.

## Features

| Feature | Where | Live needs |
|---|---|---|
| Message actions: copy, share text, share as image (PNG), pin, edit, regenerate, fork, read aloud, open in canvas, turn into task / reminder / Home panel | `w2_message_actions.dart`, long-press any bubble or the `…` under a reply | Panel: Petasos plugin (setup dialog otherwise). Task/reminder: dashboard cron API (already used by the app) |
| Edit-and-resend and regenerate as branches with ‹ 1/2 › arrows; nested branches move with their parent; `/undo` | `w2_branches.dart` (extension over `ChatController`, no rewrite) | — |
| Fork chat from any message (new session seeded with the transcript as history) | `W2Forking.forkChat` | — |
| Model switcher with reasoning effort, per chat | `w2_model_switcher.dart`, chip above the composer, `/model` | Engine `getModelOptions` + `setSessionModel`; effort is applied through the Desktop gateway when configured, otherwise kept on the phone |
| Profile switcher | same sheet | Live: saved connections (each can carry a Hermes profile). Demo: sample profiles |
| Slash commands and @mentions (skills, projects, chats) | `w2_composer_assist.dart`; phone-side `/new /model /voice /canvas /search /retry /undo /remind`, the rest go to Hermes | — |
| Voice mode: full-screen live conversation, barge-in (talk over the reply), tap-to-interrupt, hold-to-talk; composer button (tap = voice mode, press-and-hold = talk and send) | `w2_voice.dart` | Platform STT (`speech_to_text`) and the engine's TTS speaker (`FlutterVoiceReplySpeaker`) |
| Read aloud per message, auto-read setting | `W2ReadAloud` | — |
| Global search with filters (All, Chats, Starred, Pinned, Tasks, Panels, Memory, Skills) and recent searches | `w2_search.dart`, replaces the search button | — |
| Pinned and starred chats (device-only), pinned messages strip | `w2_chats_pane.dart`, `W2PinnedStrip` | — |
| Projects with instructions and files | `w2_projects.dart` | Instructions: kept on the phone without the plugin, on the host with it. Files: plugin (lists the project folder) |
| Canvas: full-screen editor for code, docs (with preview) and tables (add rows/columns), Send back | `w2_canvas.dart` | — |
| Material You dynamic color, accent presets, AMOLED black, text size, haptics toggle | `w2_theme.dart`, `w2_settings_screen.dart` (Profile → Colors, text, voice and haptics) | Dynamic color: Android 12+ (`W2DynamicColor.kt`) |
| Tablet / foldable two-pane (≥ 840 dp) | `W2ChatsPane` in `shell.dart` | — |

## Server plugin routes (`/api/plugins/hermes_mobile/w2/...`)

| Route | Use |
|---|---|
| `GET /w2/projects/{id}?path=` | `{instructions, files}`; files only from folders inside `$HOME` or `HERMES_HOME` |
| `PUT /w2/projects/{id}/instructions` | `{instructions}` (max 16k chars), stored in `~/.hermes/hermes_mobile/w2_projects.json` |
| `GET/POST /w2/panels`, `DELETE /w2/panels/{id}` | Panels from chat, written to `~/.hermes/panels/<id>.json` |
| `GET /w2/profiles` | Hermes profiles under `~/.hermes/profiles/` |

The app checks `GET /health` for `features` containing `w2.projects`.

## Known limits

- Edit/regenerate in place sends the truncated transcript as history. On a live
  gateway that also keeps its own session transcript, the server copy still has
  the old turn; use **Fork chat** for a clean server-side branch.
- Project instructions travel as a system message in each project chat's turn
  history (both with and without the plugin); the plugin only stores them.
- Barge-in relies on the recognizer hearing you over the phone speaker; tap the
  orb to interrupt on phones where it cannot.
- Haptics setting gates Wave 2 haptics; older calls in shared files still use
  `HapticFeedback` directly.
- `W2DynamicColor.kt` and the one-line hook in `MainActivity` were not compiled
  here (no Android build in this environment); CI's APK job builds them.
