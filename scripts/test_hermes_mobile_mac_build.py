"""Regression tests for the self-hosted Mac Gradle identity preflight.

The tests execute the real Python preflight embedded in build_hermes_mobile_mac.sh
against a disposable checkout without requiring Flutter/Android on the CI host.
"""
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/build_hermes_mobile_mac.sh"


def preflight_source():
    source = SCRIPT.read_text()
    match = re.search(
        r'^step "Initialize Android SDK and version properties before Gradle"\n'
        r"python3 - <<'PY'\n(.*?)\nPY$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise AssertionError("Missing Mac Gradle identity preflight")
    compile(match.group(1), str(SCRIPT), "exec")
    return match.group(1)


class MacGradleIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        (self.root / "android").mkdir()
        (self.root / "sdk").mkdir()
        flutter = self.root / "flutter"
        (flutter / "packages/flutter_tools/gradle").mkdir(parents=True)
        (flutter / "bin").mkdir()
        executable = flutter / "bin/flutter"
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        self.environment = {
            **os.environ,
            "FLUTTER_ROOT": str(flutter),
            "ANDROID_HOME": str(self.root / "sdk"),
            "PATH": str(flutter / "bin") + os.pathsep + os.environ.get("PATH", ""),
        }

    def run_preflight(self, version_line):
        (self.root / "pubspec.yaml").write_text(version_line)
        return subprocess.run(
            [sys.executable, "-c", preflight_source()],
            cwd=self.root,
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_real_pubspec_version_passes_through_without_downgrading(self):
        result = self.run_preflight("name: hermes_android\nversion: 5.2.0+7200\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        props = dict(
            line.split("=", 1)
            for line in (self.root / "android/local.properties").read_text().splitlines()
        )
        self.assertEqual(props["flutter.versionName"], "5.2.0")
        self.assertEqual(props["flutter.versionCode"], "7200")
        self.assertEqual(props["flutter.buildMode"], "debug")
        # macOS canonicalizes /var/... into /private/var/...; both are the
        # same file. Compare resolved paths rather than literal spellings.
        self.assertEqual(
            pathlib.Path(props["flutter.sdk"]).resolve(),
            (self.root / "flutter").resolve(),
        )
        self.assertEqual(
            pathlib.Path(props["sdk.dir"]).resolve(),
            (self.root / "sdk").resolve(),
        )

    def test_symlinked_flutter_sdk_resolves_to_same_directory(self):
        # Reproduce macOS's /var -> /private/var alias on any platform.
        alias = self.root / "flutter-alias"
        alias.symlink_to(self.root / "flutter", target_is_directory=True)
        self.environment["FLUTTER_ROOT"] = str(alias)
        result = self.run_preflight("version: 5.2.0+7200\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        props = dict(
            line.split("=", 1)
            for line in (self.root / "android/local.properties").read_text().splitlines()
        )
        self.assertEqual(
            pathlib.Path(props["flutter.sdk"]).resolve(),
            (self.root / "flutter").resolve(),
        )

    def test_version_floor_rejects_default_gradle_code_one(self):
        result = self.run_preflight("name: hermes_android\nversion: 5.2.0+1\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("2127", result.stderr)
        self.assertFalse((self.root / "android/local.properties").exists())

    def test_missing_version_fails_before_gradle(self):
        result = self.run_preflight("name: hermes_android\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "android/local.properties").exists())

    def test_macos_builder_uses_supplied_gradle_not_a_wrapper(self):
        script = SCRIPT.read_text()
        self.assertIn("(cd android && gradle :app:testDebugUnitTest --no-daemon)", script)
        self.assertNotIn("gradle wrapper --gradle-version", script)
        self.assertNotIn("./gradlew", script)


if __name__ == "__main__":
    unittest.main()
