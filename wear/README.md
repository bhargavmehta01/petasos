# Hermes glance tile for Wear OS (Wave 4, documented stub)

`wear/hermes_mobile_tile` is a minimal Wear OS tile that shows the Wave 4 glance:
watcher alerts, promises due today, and what Hermes did overnight.

**Status: stub, not built by CI.** It is deliberately not listed in
`android/settings.gradle.kts`, so the phone APK and the existing CI jobs are
unchanged. Wiring it in needs a Wear emulator or watch to verify and adds the
Wear Tiles/ProtoLayout and Guava dependencies, which is more setup than Wave 4
was allowed to add.

## Data contract

The tile reads one JSON object from the Petasos server plugin:

```
GET <dashboard>/api/plugins/hermes_mobile/w4/glance
{"watchers_changed": 1, "commitments_due": 2, "overnight_actions": 4,
 "held_outbound": 0, "headline": "Sony WH-1000XM6 price: $279.99", "proactivity": "balanced"}
```

The phone computes the same shape in `Wave4Controller.glance()`
(`lib/hermes_mobile/features/wave4_novel/w4_controller.dart`).

## Build it by hand

1. Add the module to `android/settings.gradle.kts`:
   `include(":hermes_mobile_tile")` and `project(":hermes_mobile_tile").projectDir = file("../wear/hermes_mobile_tile")`.
2. `cd android && ./gradlew :hermes_mobile_tile:assembleDebug`
3. Install on a paired watch or Wear emulator: `adb -s <watch> install hermes_mobile_tile/build/outputs/apk/debug/*.apk`
4. Point it at your dashboard (until Data Layer sync exists):
   `adb shell run-as com.hermesagent.hermes_android` and write
   `shared_prefs/hermes_mobile_tile.xml` with `glance_url` (and `token` if the dashboard needs a session token).
5. Long-press the watch face, add the "Hermes glance" tile.

## Follow-ups

- Sync `glance_url` and the session token from the phone over the Wear Data Layer
  (`com.google.android.gms:play-services-wearable`), so step 4 goes away.
- Tap actions: open the phone app on Home, "Check watchers now".
- Add the module to CI once it has been verified on a watch.
