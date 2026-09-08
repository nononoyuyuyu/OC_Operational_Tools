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
import build_android_ci


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

    def test_release_python_changes_do_not_rebuild_apps_in_pr(self):
        self.assertEqual((False, set(), False), ci.scope([".github/scripts/publish_release.py", ".github/scripts/build_android_ci.py", ".github/scripts/oco_ci.py", "Tests/OpenCampusOrganizer/ci_release_test.py"]))

    def test_ci_only_pr_does_not_hide_application_or_native_test_changes(self):
        paths = [".github/workflows/open-campus-organizer.yml", ".github/scripts/lint_workflows.sh", "Docs/OpenCampusOrganizer/CIと自動公開.md"]
        self.assertTrue(ci.ci_only_change(paths))
        for path in [ci.VERSION_FILE, ci.APP + "lib/main.dart", "Tests/OpenCampusOrganizer/android_appearance/LauncherLifecycleTest.kt"]:
            self.assertFalse(ci.ci_only_change(paths + [path]))

    def test_only_untagged_newer_release_can_resume_after_ci_fix(self):
        self.assertTrue(ci.pending_release("0.4.4", ["v0.4.3"]))
        self.assertFalse(ci.pending_release("0.4.4", ["v0.4.3", "v0.4.4"]))
        self.assertFalse(ci.pending_release("0.4.4", ["v0.4.5"]))
        self.assertFalse(ci.pending_release("0.4.4", []))

    def test_signer_prefix_variations(self):
        for prefix in ["Signer #1", "V3 Signer:", "Signer (minSdkVersion=24, maxSdkVersion=32)"]:
            build_android_ci.verify_signers(f"{prefix} certificate SHA-256 digest: {build_android_ci.SIGNER}")

    def test_missing_or_different_signer_is_rejected(self):
        for value in ["", "certificate SHA-256 digest: " + "0" * 64,
                      f"certificate SHA-256 digest: {build_android_ci.SIGNER}\ncertificate SHA-256 digest: " + "0" * 64]:
            with self.assertRaises(ValueError):
                build_android_ci.verify_signers(value)

    def test_nested_windows_artifact_becomes_flat_release_assets(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            download = root / "download"
            names = publish_release.expected_names("0.4.4")
            for name in names:
                path = download / "0.4.4" / name if name.endswith(".exe") else download / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(name.encode())
            publish_release.collect_assets(download, root / "stage", "0.4.4")
            self.assertEqual(names, {path.name for path in (root / "stage").iterdir()})
            for name in names:
                self.assertEqual(name.encode(), (root / "stage" / name).read_bytes())
            # 同じファイル名が2階層に存在する場合は上書きで隠さず拒否する。
            duplicate = next(iter(names))
            (download / "duplicate").mkdir()
            (download / "duplicate" / duplicate).write_bytes(b"different")
            with self.assertRaises(ValueError):
                publish_release.collect_assets(download, root / "rejected", "0.4.4")

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
                with patch.dict(os.environ, {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main", "GITHUB_REPOSITORY": "example/repo", "GITHUB_SHA": "a" * 40, "RUNNER_TEMP": folder}), patch.object(publish_release, "gh") as remote:
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
