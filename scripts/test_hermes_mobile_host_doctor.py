"""Tests for safe, repeatable host dependency initialization."""
import pathlib
import tempfile
import unittest

from scripts.hermes_mobile_host_doctor import check_sources, destination


class HermesMobileHostDoctorTest(unittest.TestCase):
    def test_locations(self):
        home = pathlib.Path("/tmp/hermes-mobile-test")
        self.assertEqual(destination(home, "mobile-push"), home / "plugins/mobile-push")
        self.assertEqual(destination(home, "hermes-mobile-platform"),
                         home / "plugins/platforms/hermes-mobile-platform")

    def test_missing_dns_dependency_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            push = root / "server/mobile-push"
            platform = root / "server/hermes-mobile-platform"
            push.mkdir(parents=True)
            platform.mkdir(parents=True)
            (platform / "plugin.yaml").write_text("name: hermes-mobile-platform\n")
            (push / "plugin.yaml").write_text(
                'name: mobile-push\npython_dependencies:\n  - "dnspython>=2.6,<3"\n'
            )
            check_sources(root)
            (push / "plugin.yaml").write_text("name: mobile-push\n")
            with self.assertRaises(RuntimeError):
                check_sources(root)


if __name__ == "__main__":
    unittest.main()


class LoadedCodeCheckTest(unittest.TestCase):
    def test_parse_etime(self):
        from scripts.hermes_mobile_host_doctor import parse_etime
        self.assertEqual(parse_etime("06:59"), 419)
        self.assertEqual(parse_etime("01:02:03"), 3723)
        self.assertEqual(parse_etime("1-00:00:05\n"), 86405)

    def test_process_older_than_code_is_stale(self):
        from scripts.hermes_mobile_host_doctor import is_stale
        self.assertTrue(is_stale(process_started=100.0, code_changed=200.0))
        self.assertFalse(is_stale(process_started=300.0, code_changed=200.0))
