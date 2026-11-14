# Petasos host bootstrap and migration

Reproducible setup for a new Mac or Linux host. It addresses the original
HTTP 404 failure caused by enabling `mobile-push` before installing its
declared `dnspython` dependency in Hermes's managed Python generation.

## Before configuring a new host

1. Install Hermes from its official installer. Select the intended Hermes
   profile (the default is `~/.hermes`).
2. Restore the encrypted VAPID private key, `config.json` and pairing database
   from a verified backup **before** using a previously paired Android device.
   Do not copy credentials, VAPID keys or recovery passwords to GitHub.
3. Check out this trusted Petasos repository on the audited branch or release.
4. On a **fresh/stopped** host, run from the repo root:

   `python3 scripts/hermes_mobile_host_doctor.py --apply --install-missing`

   This installs missing Petasos plugins with `hermes plugins install` and
   `hermes plugins enable`, then runs **`hermes pm install`** to select the
   correct interpreter and install all declared Python dependencies.
   It never installs with raw `pip`, generates keys, changes the operator's
   policy, or restarts any service.

5. If plugins were already installed, run the same dependency sync without
   touching their code:

   `python3 scripts/hermes_mobile_host_doctor.py --apply`

6. Reload the **actual dashboard backend** using its supervisor. The Desktop
   Local gateway, Tailscale `hermes serve` backend, and messaging gateway can
   be different processes. On the original Mac, the dashboard service had
   launchd label `ai.hermes.serve-tailnet`; never assume that label exists
   on another machine. Do not restart active jobs blindly.

7. In a browser or Petasos Android using an existing authenticated session,
   verify `GET /api/plugins/mobile-push/capabilities` on the **actual saved**
   dashboard URL returns schema=1 and enabled=true. A naked HTTP 401 from
   the auth gate is not proof that the plugin's route exists. Inspect
   dashboard error logs for new plugin-import failures.

8. In Petasos Android open Profile → Connection → Background notifications,
   enable Automatic transport, grant permission and verify status Active.

## Diagnostics on an existing host

Run `python3 scripts/hermes_mobile_host_doctor.py` for an inspection only. To
reconcile the managed dependencies after any plugin update, migration,
or change of Hermes Python generation, run:

`python3 scripts/hermes_mobile_host_doctor.py --apply`

Run the bundled unit tests with
`python3 -m unittest scripts.test_hermes_mobile_host_doctor`.

**Constraints:** no API keys in logs; no changes to your verified dashboard
principal without an explicit owner grant; no change to running gateway
or cron state. A successful host preflight is not proof that Android received
a notification. Finish with an actual paired-device acceptance test.

## Platform plugin must be a Python package

Hermes only loads a platform plugin directory that contains `__init__.py`
(like the bundled `plugins/platforms/ntfy`). `server/hermes-mobile-platform/__init__.py`
re-exports `register` from `adapter.py`; without it `hermes plugins list` shows the plugin
as enabled while `hermes status` never lists **Petasos** and the log says
`Failed to load plugin ... No __init__.py`. After installing or updating the plugin,
restart the gateway (`hermes gateway restart`) and confirm `hermes status` lists Petasos.

## Repeatable checks (run on the Hermes Mac)

- `python3 scripts/hermes_mobile_host_doctor.py` read-only preflight.
- `bash scripts/hermes_mobile_backup.sh` encrypted local backup (Keychain passphrase), self-verifying.
- `python3 scripts/hermes_mobile_cron_acceptance.py` real-scheduler routing test: visible output is
  delivered once, `[SILENT]` creates no event. Then tap the phone notification manually.
- The same actions are available as `hermes-mobile-host-maintenance.yml` (manual dispatch).

## Restart both services after any plugin update

Two long-running processes import the plugin code and keep what they loaded at start:
the dashboard (`ai.hermes.serve-tailnet`, port 9119), which serves registration and
challenge confirmation, and the gateway, which sends pushes and delivers cron results.
If only the gateway is restarted, the phone pairs against older dashboard code and can
stay on "Pending encrypted challenge". After copying plugin files:

    hermes gateway restart
    launchctl kickstart -k gui/$(id -u)/ai.hermes.serve-tailnet

`scripts/hermes_mobile_host_doctor.py` fails with `services_running_old_plugin_code=...`
when either service predates the installed plugin files.

If a phone registration is revoked server-side (for example the push service reported its
endpoint gone; the gateway log shows `push service reported the endpoint gone`), the app
asks you to turn Background notifications off and on, which pairs a fresh installation ID.
After re-pairing, update `HERMES_MOBILE_HOME_CHANNEL` to the new device ID shown in the app
and restart the gateway.
