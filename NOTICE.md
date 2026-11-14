# Licensing and attribution

Petasos is an unofficial, community Android app for [Hermes Agent](https://hermes-agent.nousresearch.com/).
It is not affiliated with, endorsed by, or an official product of Nous Research or the
Hermes Agent project. "Hermes Agent" and "Nous Research" are used only to describe what
the app connects to.

## Licences

- **Petasos additions** (the app UI in `lib/hermes_mobile/`, the cron delivery companion and
  platform plugin under `server/`, host tooling in `scripts/`, and other changes made in this
  repository) are licensed under the **GNU Affero General Public License v3.0** — see
  [LICENSE](LICENSE). Copyright (c) 2026 Bhargav Mehta and Petasos contributors.
- **Upstream code** from [rusty4444/hermes-android](https://github.com/rusty4444/hermes-android)
  (the connection, streaming, approvals, push registration and turn-recovery engine in
  `lib/core/`, translations, and most tests) remains available under its original
  **MIT License** — see [LICENSES/MIT-hermes-android.txt](LICENSES/MIT-hermes-android.txt).
  Copyright (c) 2026 Sam Russell and contributors. Thank you, rusty4444.
- The combined work, as distributed here, is offered under AGPL-3.0. Files that come from
  upstream may still be used separately under the MIT License, as upstream permits.

## Third-party components

- The bundled Cinzel font keeps its [SIL Open Font License 1.1](assets/fonts/OFL.txt).
- The embedded FCM distributor keeps its LGPL-2.1-or-later terms; see the
  [library notice](third_party/embedded-push-notice.md),
  [verbatim licence](third_party/licenses/embedded-fcm-distributor-LGPL-2.1.txt) and
  [source/relink instructions](third_party/embedded-push-relink.md).
- Other dependencies keep their own licences and notices.

Synthetic fixture credentials in `test/` are test data only. No gateway credentials,
signing keys, device identifiers or operator logs are part of this source tree.
