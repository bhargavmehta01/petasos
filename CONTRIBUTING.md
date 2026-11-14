# Contributing to Petasos

Thanks for helping. Small, focused pull requests are easiest to review.

## Before you start

- For anything bigger than a bug fix, open an issue first so we can agree on the approach.
- Check [docs/reference.md](docs/reference.md) for the architecture. The app UI lives in
  `lib/hermes_mobile/`; the engine in `lib/core/` comes from upstream
  [rusty4444/hermes-android](https://github.com/rusty4444/hermes-android). Engine fixes that are not
  Petasos-specific are best sent upstream too.

## Development

```bash
flutter pub get
flutter analyze
flutter test                      # full suite
flutter test test/hermes_mobile   # UI tests only
```

Server plugins (`server/mobile-push`, `server/hermes-mobile-platform`):

```bash
python -m pip install -e 'server/mobile-push[test]'
python -m pytest -q server/mobile-push/tests
```

Use demo mode ("Explore the demo" on the connect screen, or
`--dart-define=HERMES_MOBILE_DEMO=true`) to work on the UI without a Hermes server.

## Pull requests

- Keep the existing style; run `dart format` on changed Dart files.
- Add or update tests for behaviour changes.
- CI builds a debug-signed test APK for every pull request, so reviewers can try it.
- Never commit secrets, signing keys, device IDs, IP addresses or logs from a real host.

## Licence

By contributing you agree that your contribution is licensed under the
[AGPL-3.0](LICENSE), the licence of this project.
