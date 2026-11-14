# Petasos Wave 1: proactive core

Everything here works in demo mode with sample data. Code lives in
`lib/hermes_mobile/features/wave1_proactive/`, tests in `test/hermes_mobile/wave1/`, the server
side in `server/hermes_mobile_plugin/wave1_proactive.py` (see `server/hermes_mobile_plugin/README.md`).

## Brief tab and proactive feed
- App-bar sun button (unread badge) opens **Brief**: *Today* shows morning and
  evening digest cards (swipe to dismiss, 👍/👎 = "more/less like this", saved
  as one entry to Hermes `USER.md` memory through the plugin) and *For you* shows
  cards with exactly one action each: **Approve**, **Snooze**, **Reply**, **Run**
  or **Open**. Pending approvals from live chats appear first as local cards.
- Home shows a compact "Your brief" row when there is a brief or unread cards.
- Live source: `GET /api/plugins/hermes_mobile/w1/feed` on the dashboard URL. Briefs are
  the newest output of cron jobs whose name contains brief/digest/recap/summary/
  morning/evening; failed cron jobs become alert cards with **Run again**.
- Without the plugin (dashboard URL set, plugin route 404): briefs come from the
  newest run of up to four brief-like cron jobs (`cron/jobs/{id}/runs` + that run
  session's last reply) and failed jobs still become alert cards; dismiss/snooze
  state is kept on the phone, and feedback/uploads/agent-pushed cards need the
  plugin. With no dashboard URL at all, the tab shows install help and approvals
  still work.

## Notifications
- Approvals that arrive while the app is backgrounded post a notification with
  **Allow / Deny / Reply** (inline text). Reply declines the request and sends the
  text as the next instruction once the run settles.
- New feed cards (polled every 15 min while the process is alive in the
  background, e.g. during a streaming turn) post with **Reply** or the card's
  action plus **Snooze**; more than one is grouped under an inbox-style digest.
- Brief → tune icon: master switch, quiet hours (default 22:00–07:00; approvals
  still arrive silently), per-source mute, test notification, and which panel the
  panel widget shows.
- Taps on the engine's turn notifications now open their chat in Petasos.

Limitation: Android lets the app post only while its process runs; there is no
push channel for proactive cards yet (the engine's UnifiedPush path is
unchanged). A cron job that should alert reliably can still deliver via
Telegram etc.

## Native agent prompts
Sudo password, secret and clarify requests render as cards above the composer
(sensitive values obscured, never stored). The engine's SSE decoder now forwards
`clarify.request` / `sudo.request` / `secret.request` events to `onStatus`,
tagged `hermes_mobile_control` (fenced `wave1` block in `connection_manager.dart`).
Answers go to `POST /v1/runs/{run_id}/{clarify|sudo|secret}` with
`{request_id, execution_generation, answer}`. Stock Hermes projects approvals and
clarify prompts on the API run stream; sudo/secret are only on the desktop
WebSocket today, so on the API path they appear only if the server emits them.
Demo: send a message containing "sudo", "secret"/"api key", or starting "which".

## Attachments
Composer **+ → File**: text/code files (≤256 KB) are inlined as fenced blocks;
images go through the existing image path; other files (PDF, docs, ≤20 MB) are
uploaded to `~/.hermes/hermes_mobile/uploads/` via `POST /w1/upload` and the message tells
the agent the host path. Without the plugin, binary files show an explanation.

## Natural-language scheduling
Sending "remind me to call the dentist tomorrow at 10am", "every weekday at 9
summarise my inbox", "every 2 hours check …", "remind me in 20 minutes …"
opens a preview card (human schedule, prompt, cron/`every`/delay/ISO schedule,
editable) instead of sending. **Schedule** creates the Hermes cron job;
**Just send it** sends the text as a normal message. Parser:
`w1_schedule.dart` (local time; ISO timestamps are naive local time).

## Quick capture
- Share sheet (existing engine intent filter): text, links, images and files open
  a sheet with prompt picks (Ask, Summarize, Remind me, Watch this, Remember).
- Quick Settings tile **Ask Hermes**, launcher shortcuts **Remind me…** and
  **Watch this…** (extra `hermes_mobile_action` on the existing QUICK_CHAT intent).

## Home-screen widgets (native, no new package)
`HermesMobileWidgets.kt`: **Hermes brief**, **Hermes panel** (pinned panel), **Needs you**
counter, **Ask Hermes** (ask + voice). Flutter writes `hermes_mobile.widget.*` keys to
SharedPreferences and calls `com.hermesagent.hermesMobile/widgets#update`.
