# Petasos: Deliver Hermes cron results directly to Android

For repeatable installation on new Macs or Linux hosts, run the
[Petasos host bootstrap and dependency preflight](hermes-mobile-host-bootstrap.md)
before starting the Hermes dashboard. It synchronizes declared plugin
dependencies through Hermes PM, including dnspython.

This feature extends the existing opt-in encrypted mobile-push companion. It does
**not** install itself onto a running Hermes host or enroll an Android device.

## Prerequisites

- Hermes build with plugin platform registration and standalone cron sender support.
- The paired `server/mobile-push` companion in this repository, with its operator-owned
  policy, VAPID key, and verified dashboard login already configured according to
  [the full server runbook](mobile-push-server.md).
- **Launch/default profile in trusted in-process mode**, as documented in the
  mobile-push runbook. Secondary-profile impersonation and bearer/header identity
  fallbacks are intentionally unsupported.
- Android app APK containing the `cron_result` event-kind support, running on a
  phone with working Web Push / UnifiedPush.

## Build and install the Android APK on your own Mac

Official APKs come from [Releases](https://github.com/bhargavmehta01/petasos/releases).
To build your own, run the reusable [scripts/build_hermes_mobile_mac.sh](../scripts/build_hermes_mobile_mac.sh)
on a Mac:

```bash
git clone https://github.com/bhargavmehta01/petasos.git
cd petasos
bash scripts/build_hermes_mobile_mac.sh
```

It runs Flutter analysis, the full Flutter tests, the push-server Python tests, native
Android unit tests, the release build, APK signature verification and SHA-256
generation, and it publishes nothing if any step fails. Install Flutter 3.44.0,
Java 17, Android SDK Platform 36 + Build-Tools, Python 3.11+ and Gradle 9.1.0 first.
The output is `dist/hermes-mobile-<version>-arm64.apk` with `dist/SHA256SUMS.txt`.

Without a release key configured, the script signs with a throwaway debug key.
Android only updates an installed app in place when the new APK has the same
package ID (`io.github.bhargavmehta01.hermesmobile`) and the same signing key, so a
self-built APK installs as an update only over another self-built one.

Pull requests are built by GitHub-hosted CI ([build-apk.yml](../.github/workflows/build-apk.yml)),
which uploads a debug-signed test APK for each change.

### Important separation

A successfully compiled APK is **not** proof that scheduled notifications work.
The corresponding Hermes host-side plugins must still be installed and a
real cron delivery accepted on the phone as described below.

## Step 1 — Deploy the plugin on the Hermes host

Back up an existing `$HERMES_HOME/plugins/mobile-push` directory and the private
`$HERMES_HOME/plugin-data/mobile-push` state before upgrading. Copy the checked
`server/mobile-push` directory from the release into that plugin location.
Also install the separate **platform plugin** by copying
`server/hermes-mobile-platform` into the same profile at
`$HERMES_HOME/plugins/platforms/hermes-mobile-platform`. This second plugin
contains `kind: platform` metadata and the adapter entrypoint Hermes needs
to discover `hermes_mobile` as a cron target.
**Do not overwrite a live plugin or mix old gateway processes with new database
writers.** Drain running turns, coordinate a stopped/restart upgrade of dashboard,
gateway/turn workers, and cron workers, then use the Hermes plugin manager's
supported admission/enable workflow. Its declared Python dependencies must be
prepared through Hermes package management, not unmanaged pip writes.

For a personal server, the selected profile's private operator policy must
explicitly authorize the **verified** dashboard principal as an owner:

```json
{
  "provider": "your-verified-auth-provider",
  "user_id": "your-verified-user-id",
  "owner_all_sessions": true
}
```

This is an entry inside `principals` in the existing private
`plugin-data/mobile-push/config.json`, **not** a replacement for that whole
configuration. Restrict file ownership and permissions as the server runbook
requires. Never copy credentials, notification endpoints, or private keys into
the Android repository.

## Step 2 — Update the Android app and pair again

1. Install the version of your Petasos APK built from this change.
2. Go to **Profile → Connection → Background notifications**.
3. If push was already active on an older APK, **Disable and revoke** it once
   before re-enrolling in the upgraded client. A previous registration does not
   contain the new `cron_result` event kind. **Do not repeatedly revoke a
   pending registration**: that discards its installation ID and starts over.
4. Wait for **Status: Active**, then copy **Petasos cron destination
   (device ID)** immediately below the status. **The UI intentionally hides this
   field while the status says `Pending encrypted challenge`**. That status
   means the silent encrypted push proof has not yet been confirmed. Tap
   **Refresh / retry**, check Google Play Services/notification permission and
   the server push worker, and reopen/retry after the five-minute local waiting
   ceiling for automatic handshake renewal. Do not infer a device ID from the
   saved connection or Tailscale address.
5. Keep background notifications enabled and grant the Android notification permission.

The Android UI uses the existing encrypted registration handshake and receives
minimal metadata only. The result text remains in a private server-side SQLite
companion database and is read by the app only after authentication. The push
notification itself never contains the prompt, response, credentials or content.

## Step 3 — Configure the cron home channel

In the same Hermes profile which runs the plugin and cron worker, set the
profile-scoped configuration environment variable to the *exact paired device ID*:

```dotenv
HERMES_MOBILE_HOME_CHANNEL=00000000-0000-0000-0000-000000000000
```

Use your actual installation ID, not the zeros. Reload/restart the relevant
gateway, dashboard, and cron runtimes through the supported Hermes controls;
confirm `hermes status` recognizes the **Petasos** plugin platform.

The platform is outbound-only: it will not create a second chat bot, receive
arbitrary phone commands, or register an agent-callable send tool.

## Step 4 — Enable delivery on the existing scheduled task

In the Desktop **Edit cron job → Deliver to** selector, choose **Petasos**
after Hermes recognizes the registered and configured platform. Retain **This
desktop** and **WhatsApp** if desired. If your Hermes Desktop version does not
discover plugin platforms, edit the cron target using the supported CLI with
`deliver=hermes_mobile` and check the persisted target in `hermes cron list`
and the run history. Do not assume a checkbox was added merely by building the
Android APK.

For a direct sending smoke test, use the Hermes host CLI and its documented
`hermes send --to hermes_mobile:<installation-id> ...` syntax *where supported*,
or trigger a narrowly scoped test cron that targets `hermes_mobile`. A successful
push-send receipt establishes queue acceptance; final delivery requires checking
the Android notification and authenticated result screen.

## Privacy and delivery behavior

- A cron output consisting only of `[SILENT]` or whitespace queues **no event**.
- The sender rejects unpaired, revoked, restricted-scope and unenrolled devices.
- A completed event has a stable server event ID, active registration generation,
  TTL and best-effort Web Push retry.
- On Android, tapping the notification securely opens **Scheduled result** and
  offers a link to **Cron studio**.
- Revoked/expired/foreign events cannot be resolved, and the app fails closed.
- Android force-stop, battery restrictions, distributor downtime, unavailable
  gateway processes and network failures can still delay or prevent delivery.
  There is no guarantee of instant notification or an exactly-once phone display.

## Acceptance checklist

- [ ] Plugin is enabled, authenticated, and running in all relevant host processes.
- [ ] Petasos is present among connected platform names in Hermes status/UI.
- [ ] Android **Background notifications** shows **Active** with a device ID.
- [ ] A non-silent test cron appears on the phone; tap opens the correct result.
- [ ] The same job with `[SILENT]` produces no phone notification.
- [ ] Repeated/retried sends do not duplicate a single queued event.
- [ ] Disabled/revoked device no longer receives results.
- [ ] WhatsApp and desktop destinations still receive the outputs they request.

Until these checks are done against the actual Mac and Android device, the
feature is **implemented but not verified operational**.
