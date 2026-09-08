"""不要なビルドの省略と不正な配布番号の拒否を検証する。"""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

script = Path(__file__).resolve().parents[2] / ".github/scripts/oco_ci.py"
spec = importlib.util.spec_from_file_location("oco_ci", script)
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)
sys.path.insert(0, str(script.parent))
import publish_release
import audit_payload


class ReleasePlanTest(unittest.TestCase):
    def test_source_requires_both_numbers_to_increase(self):
        for current in [("0.4.3", 12), ("0.4.3", 13), ("0.4.4", 12), ("0.4.2", 14)]:
            with self.subTest(current=current), self.assertRaises(ValueError):
                ci.validate_version(current, ("0.4.3", 12), True, [])
        self.assertTrue(ci.validate_version(("0.4.4", 13), ("0.4.3", 12), True, []))

    def test_duplicate_tag_rejected(self):
        with self.assertRaises(ValueError):
            ci.validate_version(("0.4.4", 13), ("0.4.3", 12), True, ["v0.4.4"])

    def test_numeric_version_comparison(self):
        self.assertTrue(ci.validate_version(("0.10.0", 14), ("0.9.9", 13), True, []))

    def test_invalid_versions(self):
        for text in ["version: 0.4.4", "version: 0.4.4+0", "version: 01.2.3+1", "version: 0.4.4-beta+13", "version: 0.4.4+2100000001"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                ci.parse_version(text)

    def test_docs_do_not_build_or_release(self):
        self.assertEqual((False, set(), False), ci.scope(["README.md", "Docs/OpenCampusOrganizer/設計.md"]))
        self.assertFalse(ci.validate_version(("0.4.4", 13), ("0.4.4", 13), False, ["v0.4.4"]))

    def test_native_changes_build_only_their_platform(self):
        self.assertEqual((True, {"Android"}, True), ci.scope([ci.APP + "android/app/src/main/AndroidManifest.xml"]))
        self.assertEqual((True, {"Windows"}, False), ci.scope([ci.APP + "windows/runner/main.cpp"]))
        self.assertEqual((True, {"iOS"}, False), ci.scope([ci.APP + "ios/Runner/AppDelegate.swift"]))

    def test_common_code_and_workflow_build_all_platforms(self):
        for path in [ci.APP + "lib/main.dart", ci.APP + "pubspec.yaml", ".github/workflows/open-campus-organizer.yml"]:
            self.assertEqual(set(ci.TARGETS), ci.scope([path])[1])

    def test_release_is_forbidden_from_pr_and_non_main(self):
        for event, ref in [("pull_request", "refs/heads/main"), ("push", "refs/heads/codex/example")]:
            with patch.dict(os.environ, {"GITHUB_EVENT_NAME": event, "GITHUB_REF": ref}), patch.object(publish_release, "gh") as remote:
                with self.assertRaises(ValueError):
                    publish_release.main()
                remote.assert_not_called()

    def test_download_requires_exact_asset_set_and_hashes(self):
        def fake_download(*args):
            folder = Path(args[-1])
            (folder / "artifact.apk").write_bytes(b"changed")
        with patch.object(publish_release, "gh", side_effect=fake_download), self.assertRaises(ValueError):
            publish_release.verify_download("v0.4.4", {"artifact.apk": "0" * 64})

    def test_missing_assets_are_rejected_before_github(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / ci.VERSION_FILE).parent.mkdir(parents=True)
            (root / ci.VERSION_FILE).write_text("version: 0.4.4+13\n")
            (root / "dist").mkdir()
            old = Path.cwd()
            try:
                os.chdir(root)
                with patch.dict(os.environ, {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main", "GITHUB_REPOSITORY": "example/repo", "GITHUB_SHA": "a" * 40}), patch.object(publish_release, "gh") as remote:
                    with self.assertRaises(ValueError):
                        publish_release.main()
                    remote.assert_not_called()
            finally:
                os.chdir(old)

    def test_private_paths_are_rejected_without_printing_values(self):
        candidate = "C:/Users/fixture-owner/cache/plugin.dart"
        for value in [candidate.encode(), candidate.encode("utf-16-le")]:
            with self.assertRaises(ValueError) as error:
                audit_payload.inspect(value, "payload.bin")
            self.assertNotIn("fixture-owner", str(error.exception))
        audit_payload.inspect(b"C:/Users/runneradmin/cache/plugin.dart", "payload.bin")

    def test_signing_files_cannot_be_assets(self):
        with self.assertRaises(ValueError):
            audit_payload.inspect(b"fixture", "android-release.jks")


if __name__ == "__main__":
    unittest.main()
