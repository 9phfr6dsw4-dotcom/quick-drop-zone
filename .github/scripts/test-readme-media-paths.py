#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TEST_ROOT = Path(os.environ.get("RUNNER_TEMP") or os.environ.get("TMPDIR") or "")
if not TEST_ROOT.is_absolute() or not TEST_ROOT.is_dir():
    raise SystemExit("Set RUNNER_TEMP or TMPDIR to an existing scratch directory for tests")

SCRIPT_DIR = Path(__file__).parent
WORKSPACE_SCRIPT = SCRIPT_DIR / "prepare-readme-media-workspace.py"
FIXTURE_SCRIPT = SCRIPT_DIR / "prepare-quick-drop-zone-fixtures.py"
FIXTURE_NAMES = {
    "Atlas-project-brief.pdf",
    "Atlas-review-notes.md",
    "Atlas-timeline.xlsx",
    "Atlas-copy-draft.docx",
    "Team-agenda-2026-08.docx",
    "invoice-2026-08.pdf",
    "holiday-photos.zip",
    "Screenshot 2026-09-20 at 10.14.03.png",
    "meeting-notes.md",
    "brand-board.sketch",
    "Sample Studio.dmg",
    "export-final-2.csv",
}


def make_repo(parent: Path) -> Path:
    root = parent / "repo"
    images = root / "docs" / "images"
    images.mkdir(parents=True)
    (images / "quick-drop-zone-icon.png").write_bytes(b"icon")
    scripts = root / ".github" / "scripts"
    scripts.mkdir(parents=True)
    (scripts / "capture-readme-media.sh").write_text("#!/usr/bin/env bash\\n", encoding="utf-8")
    return root


def run_workspace(root: Path, runner: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(WORKSPACE_SCRIPT), str(root), str(runner), "quick-drop-zone"],
        text=True,
        capture_output=True,
        check=False,
    )


class ReadmeMediaWorkspaceTests(unittest.TestCase):
    def test_prepares_only_safe_workspace_directories(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            parent = Path(temporary)
            root = make_repo(parent)
            runner = parent / "runner"
            runner.mkdir()

            result = run_workspace(root, runner)

            self.assertEqual(result.returncode, 0, result.stderr)
            for relative in (
                "readme-media",
                "release-app",
                "release-download",
                "quick-drop-zone-demo/Downloads",
                "quick-drop-zone-demo/Applications/Sample Studio.app/Contents",
            ):
                self.assertTrue((runner / relative).is_dir(), relative)
            self.assertEqual(list((root / "docs" / "images").iterdir()), [root / "docs" / "images" / "quick-drop-zone-icon.png"])

    def test_rejects_symlinked_docs_images_before_creating_temp_paths(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            parent = Path(temporary)
            root = parent / "repo"
            docs = root / "docs"
            docs.mkdir(parents=True)
            scripts = root / ".github" / "scripts"
            scripts.mkdir(parents=True)
            (scripts / "capture-readme-media.sh").write_text("#!/usr/bin/env bash\\n", encoding="utf-8")
            outside = parent / "outside"
            outside.mkdir()
            sentinel = outside / "keep.txt"
            sentinel.write_text("keep", encoding="utf-8")
            (docs / "images").symlink_to(outside, target_is_directory=True)
            runner = parent / "runner"
            runner.mkdir()

            result = run_workspace(root, runner)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", result.stderr.lower())
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")
            self.assertFalse((runner / "release-app").exists())

    def test_rejects_symlinked_release_app_without_touching_target(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            parent = Path(temporary)
            root = make_repo(parent)
            runner = parent / "runner"
            runner.mkdir()
            outside = parent / "outside"
            outside.mkdir()
            sentinel = outside / "keep.txt"
            sentinel.write_text("keep", encoding="utf-8")
            (runner / "release-app").symlink_to(outside, target_is_directory=True)

            result = run_workspace(root, runner)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", result.stderr.lower())
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")
            self.assertFalse((runner / "release-download").exists())

    def test_rejects_symlinked_capture_output_without_touching_target(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            parent = Path(temporary)
            root = make_repo(parent)
            outside = parent / "outside.txt"
            outside.write_text("keep", encoding="utf-8")
            (root / "docs" / "images" / "quick-drop-zone-light.png").symlink_to(outside)
            runner = parent / "runner"
            runner.mkdir()

            result = run_workspace(root, runner)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", result.stderr.lower())
            self.assertEqual(outside.read_text(encoding="utf-8"), "keep")
            self.assertFalse((runner / "release-app").exists())

    def test_rejects_symlinked_runner_temp(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            parent = Path(temporary)
            root = make_repo(parent)
            real_runner = parent / "runner"
            real_runner.mkdir()
            runner_link = parent / "runner-link"
            runner_link.symlink_to(real_runner, target_is_directory=True)

            result = run_workspace(root, runner_link)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", result.stderr.lower())
            self.assertEqual(list(real_runner.iterdir()), [])

    def test_fixtures_are_created_inside_runner_temp_and_keep_expected_names(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            parent = Path(temporary)
            root = make_repo(parent)
            runner = parent / "runner"
            runner.mkdir()
            prepared = run_workspace(root, runner)
            self.assertEqual(prepared.returncode, 0, prepared.stderr)
            wallpaper = runner / "readme-wallpaper.png"
            wallpaper.write_bytes(b"synthetic wallpaper")

            result = subprocess.run(
                [sys.executable, str(FIXTURE_SCRIPT), str(runner), str(wallpaper)],
                text=True,
                capture_output=True,
                check=False,
            )

            downloads = runner / "quick-drop-zone-demo" / "Downloads"
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual({path.name for path in downloads.iterdir()}, FIXTURE_NAMES)
            self.assertEqual((downloads / "Screenshot 2026-09-20 at 10.14.03.png").read_bytes(), wallpaper.read_bytes())
            app_marker = runner / "quick-drop-zone-demo" / "Applications" / "Sample Studio.app" / "Contents" / "Info.plist"
            self.assertTrue(app_marker.is_file())
            self.assertEqual(app_marker.read_text(encoding="utf-8"), "Synthetic demo app marker.\n")

    def test_rejects_symlinked_repository_root(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            parent = Path(temporary)
            root = make_repo(parent)
            root_link = parent / "repo-link"
            root_link.symlink_to(root, target_is_directory=True)
            runner = parent / "runner"
            runner.mkdir()

            result = run_workspace(root_link, runner)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", result.stderr.lower())
            self.assertEqual(list(runner.iterdir()), [])

    def test_fixture_capture_avoids_home_and_system_install_paths(self) -> None:
        capture = (SCRIPT_DIR / "capture-readme-media.sh").read_text(encoding="utf-8")
        runtime = (SCRIPT_DIR / "readme-media-runtime.sh").read_text(encoding="utf-8")
        fixtures = (SCRIPT_DIR / "prepare-quick-drop-zone-fixtures.py").read_text(encoding="utf-8")
        self.assertNotIn("$HOME/Downloads", capture + runtime)
        self.assertNotIn("sudo", capture + runtime + fixtures)
        self.assertNotIn("/Applications/Sample Studio.app", capture + runtime + fixtures)
        self.assertIn("$FIXTURE_DOWNLOADS", capture + runtime)
        self.assertIn("quick-drop-zone-demo", fixtures)

    def test_status_item_matching_uses_exact_accessibility_description(self) -> None:
        capture = (SCRIPT_DIR / "capture-readme-media.sh").read_text(encoding="utf-8")
        self.assertEqual(capture.count("if itemDescription is statusLabel then"), 4)
        self.assertNotIn("contains appName", capture)
        self.assertNotIn("contains statusLabel", capture)

    def test_manual_workflow_is_main_gated_with_a_download_only_token(self) -> None:
        workflow = (SCRIPT_DIR.parent / "workflows" / "readme-media.yml").read_text(encoding="utf-8")
        triggers = workflow.split("permissions:", 1)[0]
        self.assertIn("workflow_dispatch:", triggers)
        self.assertNotIn("push:", triggers)
        self.assertNotIn("pull_request:", triggers)
        self.assertIn("github.ref == 'refs/heads/main'", workflow)
        download_step = workflow.split("- name: Download published release app", 1)[1].split(
            "- name: Capture the published release app", 1
        )[0]
        capture_step = workflow.split("- name: Capture the published release app", 1)[1].split(
            "- uses: actions/upload-artifact", 1
        )[0]
        self.assertIn("GH_TOKEN:", download_step)
        self.assertNotIn("GH_TOKEN", capture_step)
        macos_ci = (SCRIPT_DIR.parent / "workflows" / "macos-ci.yml").read_text(encoding="utf-8")
        self.assertNotIn("Capture the published release app", macos_ci)
        self.assertNotIn("README media", macos_ci)
        for check in (
            "bash .github/scripts/test-readme-media-runtime.sh",
            "python3 .github/scripts/test-readme-media-artifacts.py",
            "python3 .github/scripts/test-readme-media-paths.py",
            "python3 Scripts/test_checksum_sidecar.py",
        ):
            self.assertIn(check, macos_ci)

    def test_rejects_symlinked_fixture_downloads_directory(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            parent = Path(temporary)
            root = make_repo(parent)
            runner = parent / "runner"
            runner.mkdir()
            prepared = run_workspace(root, runner)
            self.assertEqual(prepared.returncode, 0, prepared.stderr)
            fixture_root = runner / "quick-drop-zone-demo"
            downloads = fixture_root / "Downloads"
            downloads.rmdir()
            outside = parent / "outside"
            outside.mkdir()
            sentinel = outside / "keep.txt"
            sentinel.write_text("keep", encoding="utf-8")
            downloads.symlink_to(outside, target_is_directory=True)
            wallpaper = runner / "readme-wallpaper.png"
            wallpaper.write_bytes(b"synthetic wallpaper")

            result = subprocess.run(
                [sys.executable, str(FIXTURE_SCRIPT), str(runner), str(wallpaper)],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", result.stderr.lower())
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")


if __name__ == "__main__":
    unittest.main(verbosity=2)
