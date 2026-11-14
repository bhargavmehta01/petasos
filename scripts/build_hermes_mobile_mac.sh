#!/usr/bin/env bash
# Build and test Petasos Android on Apple Silicon.
# Run directly from Terminal or from the manually triggered Mac GitHub runner.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { printf 'Petasos Mac build: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || fail "This builder requires macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "Use an Apple Silicon (ARM64) Mac."
for program in flutter java python3; do
  command -v "$program" >/dev/null 2>&1 || fail "Missing $program."
done
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
[[ -d "$sdk/build-tools" ]] || fail "Android SDK Build-Tools missing at $sdk."
[[ -d "$sdk/platforms/android-36" ]] || fail "Android SDK Platform 36 missing at $sdk."
export ANDROID_HOME="$sdk"
export ANDROID_SDK_ROOT="$sdk"

temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
work="$(mktemp -d "$temp_root/hermes-mobile-mac-build.XXXXXX")"
cleanup() {
  if [[ "${created_key_properties:-false}" == "true" ]]; then rm -f key.properties; fi
  rm -rf "$work"
}
trap cleanup EXIT

step "Validate the toolchain"
flutter --version
java -version
flutter config --android-sdk "$sdk" >/dev/null
flutter doctor -v

step "Install Flutter dependencies"
flutter pub get

# This repository intentionally omits gradlew/gradle-wrapper.jar. Native
# Gradle tasks still configure :app and validate versionCode *before* Flutter
# can initialise local.properties on its own. Mirror native-server.yml and
# populate the real pubspec version/Flutter SDK/Android SDK properties first.
step "Initialize Android SDK and version properties before Gradle"
python3 - <<'PY'
import os
import pathlib
import re
import shutil

root = pathlib.Path.cwd()
match = re.search(
    r"^version:\s*([^\s+]+)\+(\d+)\s*$",
    (root / "pubspec.yaml").read_text(),
    re.MULTILINE,
)
if not match:
    raise SystemExit("pubspec.yaml must define versionName+versionCode")
version_name, version_code = match.groups()
if int(version_code) <= 2127:
    raise SystemExit("versionCode must exceed the minimum installed version 2127")

flutter_bin = shutil.which("flutter")
if not flutter_bin:
    raise SystemExit("Flutter executable not found")
flutter_root = pathlib.Path(
    os.environ.get("FLUTTER_ROOT") or pathlib.Path(flutter_bin).resolve().parent.parent
).resolve()
if not (flutter_root / "packages/flutter_tools/gradle").is_dir():
    raise SystemExit("Unable to locate Flutter SDK from flutter executable")

sdk = pathlib.Path(os.environ["ANDROID_HOME"]).resolve()
# java.util.Properties treats backslashes and colons as escapes; preserve paths.
def property_path(value):
    return str(value).replace("\\", "\\\\").replace(":", "\\:")

properties = root / "android/local.properties"
properties.write_text(
    f"flutter.sdk={property_path(flutter_root)}\n"
    f"sdk.dir={property_path(sdk)}\n"
    f"flutter.versionName={version_name}\n"
    f"flutter.versionCode={version_code}\n"
    "flutter.buildMode=debug\n"
)
print(f"Configured native Gradle with versionName={version_name}, versionCode={version_code}")
PY
command -v gradle >/dev/null 2>&1 || fail "Gradle 9.1.0 missing; install Gradle or run via GitHub Actions"

step "Analyze Dart"
flutter analyze --no-pub
step "Run all Flutter tests"
flutter test --no-pub

step "Run Python mobile push server tests"
python3 -m venv "$work/python"
"$work/python/bin/python" -m pip install --disable-pip-version-check -e 'server/mobile-push[test]'
"$work/python/bin/python" -m pytest -q \
  server/mobile-push/tests --ignore=server/mobile-push/tests/test_dart_contract_smoke.py

step "Run native Android unit tests"
(cd android && gradle :app:testDebugUnitTest --no-daemon)

# If Actions release-signing secrets exist, let Gradle sign with that key.
# Otherwise the APK is signed below with a local keystore kept OUTSIDE the repo
# (~/.config/hermes-mobile/release.p12, passphrase in the macOS Keychain service
# "hermes-mobile-signing"), or with a throwaway debug key for contributor builds.
if [[ ! -f key.properties && -n "${HERMES_MOBILE_KEYSTORE_BASE64:-}" ]]; then
  [[ -n "${HERMES_MOBILE_KEYSTORE_PASSWORD:-}" && -n "${HERMES_MOBILE_KEY_ALIAS:-}" && -n "${HERMES_MOBILE_KEY_PASSWORD:-}" ]] || \
    fail "Release signing vars must be configured together."
  printf '%s' "$HERMES_MOBILE_KEYSTORE_BASE64" | base64 -D > "$work/release.keystore"
  chmod 600 "$work/release.keystore"
  {
    printf 'storePassword=%s\n' "$HERMES_MOBILE_KEYSTORE_PASSWORD"
    printf 'keyPassword=%s\n' "$HERMES_MOBILE_KEY_PASSWORD"
    printf 'keyAlias=%s\n' "$HERMES_MOBILE_KEY_ALIAS"
    printf 'storeFile=%s\n' "$work/release.keystore"
  } > key.properties
  chmod 600 key.properties
  created_key_properties=true
fi

step "Build release ARM64 APK"
flutter build apk --release --target-platform android-arm64 \
  --split-per-abi --split-debug-info=build/symbols
apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
[[ -f "$apk" ]] || fail "Flutter did not create $apk."

build_tools="$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
[[ -x "$build_tools/zipalign" && -x "$build_tools/apksigner" ]] || fail \
  "zipalign or apksigner missing from $build_tools"
if [[ ! -f key.properties ]]; then
  local_ks="${HERMES_MOBILE_LOCAL_KEYSTORE:-$HOME/.config/hermes-mobile/release.p12}"
  alias_name="${HERMES_MOBILE_LOCAL_KEY_ALIAS:-hermes-mobile}"
  if [[ -f "$local_ks" ]] && ks_pass="$(security find-generic-password -a "$USER" -s hermes-mobile-signing -w 2>/dev/null)"; then
    step "Sign APK with the local Petasos release key"
    ks_args=(--ks "$local_ks" --ks-type PKCS12 --ks-key-alias "$alias_name")
  else
    echo "WARNING: no release key configured; signing with a throwaway debug key (not for distribution)." >&2
    ks_pass="android"
    keytool -genkeypair -keystore "$work/debug.p12" -storetype PKCS12 -alias debug \
      -keyalg RSA -keysize 2048 -validity 3650 -storepass "$ks_pass" -keypass "$ks_pass" \
      -dname "CN=Petasos Debug" >/dev/null 2>&1
    ks_args=(--ks "$work/debug.p12" --ks-type PKCS12 --ks-key-alias debug)
  fi
  "$build_tools/zipalign" -f -p 4 "$apk" "$work/aligned.apk"
  "$build_tools/apksigner" sign "${ks_args[@]}" \
    --ks-pass "pass:$ks_pass" --key-pass "pass:$ks_pass" \
    --out "$work/signed.apk" "$work/aligned.apk"
  unset ks_pass
  cp "$work/signed.apk" "$apk"
fi
step "Validate APK signature"
"$build_tools/apksigner" verify --verbose --print-certs "$apk"
step "Publish local artifact"
mkdir -p dist
version="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+)\+.*/\1/p' pubspec.yaml | head -n 1)"
[[ -n "$version" ]] || fail "pubspec.yaml version missing."
target="dist/hermes-mobile-${version}-arm64.apk"
cp "$apk" "$target"
(cd dist && shasum -a 256 "$(basename "$target")" > SHA256SUMS.txt)
printf '\nSUCCESS: %s\n' "$target"
printf 'SHA256: '
shasum -a 256 "$target" | awk '{print $1}'
