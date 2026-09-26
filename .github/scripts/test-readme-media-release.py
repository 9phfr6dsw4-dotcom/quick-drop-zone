#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from typing import Any

SCRIPT_DIR = Path(__file__).parent
VERIFIER_PATH = SCRIPT_DIR / "verify-readme-media-release.py"
TEST_ROOT = Path(os.environ.get("RUNNER_TEMP") or os.environ.get("TMPDIR") or "")
if not TEST_ROOT.is_absolute() or not TEST_ROOT.is_dir():
    raise SystemExit("Set RUNNER_TEMP or TMPDIR to an existing scratch directory for tests")

verifier: Any = None
if VERIFIER_PATH.is_file():
    spec = importlib.util.spec_from_file_location("readme_media_release_verifier", VERIFIER_PATH)
    if spec is None or spec.loader is None:
        raise SystemExit("Could not load the release verifier for tests")
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)


def make_assets(directory: Path, archive: bytes = b"synthetic release archive") -> tuple[str, str]:
    zip_name = "Quick-Drop-Zone-1.2.1.zip"
    sidecar_name = f"{zip_name}.sha256"
    zip_digest = hashlib.sha256(archive).hexdigest()
    sidecar = f"{zip_digest}  dist/{zip_name}\n".encode("ascii")
    (directory / zip_name).write_bytes(archive)
    (directory / sidecar_name).write_bytes(sidecar)
    return zip_digest, hashlib.sha256(sidecar).hexdigest()


class PublishedReleaseVerificationTests(unittest.TestCase):
    def require_verifier(self):
        self.assertIsNotNone(verifier, "pinned release verifier is not implemented")
        return verifier

    def test_accepts_exact_archive_and_matching_checksum_sidecar(self) -> None:
        subject = self.require_verifier()
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            directory = Path(temporary)
            zip_digest, sidecar_digest = make_assets(directory)
            verified = subject.verify_release_assets(
                directory,
                expected_zip_sha256=zip_digest,
                expected_sidecar_sha256=sidecar_digest,
            )
            self.assertEqual(verified.name, "Quick-Drop-Zone-1.2.1.zip")

    def test_rejects_archive_that_does_not_match_the_expected_digest(self) -> None:
        subject = self.require_verifier()
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            directory = Path(temporary)
            zip_digest, sidecar_digest = make_assets(directory)
            with self.assertRaisesRegex(subject.ReleaseVerificationError, "ZIP SHA-256"):
                subject.verify_release_assets(
                    directory,
                    expected_zip_sha256="0" * 64,
                    expected_sidecar_sha256=sidecar_digest,
                )

    def test_rejects_sidecar_that_does_not_match_its_pinned_digest(self) -> None:
        subject = self.require_verifier()
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            directory = Path(temporary)
            zip_digest, _ = make_assets(directory)
            with self.assertRaisesRegex(subject.ReleaseVerificationError, "sidecar SHA-256"):
                subject.verify_release_assets(
                    directory,
                    expected_zip_sha256=zip_digest,
                    expected_sidecar_sha256="0" * 64,
                )

    def test_rejects_sidecar_for_a_different_asset_name(self) -> None:
        subject = self.require_verifier()
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            directory = Path(temporary)
            zip_digest, _ = make_assets(directory)
            sidecar = directory / "Quick-Drop-Zone-1.2.1.zip.sha256"
            bad_sidecar = ("0" * 64 + "  dist/other.zip\n").encode("ascii")
            sidecar.write_bytes(bad_sidecar)
            bad_sidecar_digest = hashlib.sha256(bad_sidecar).hexdigest()
            with self.assertRaisesRegex(subject.ReleaseVerificationError, "sidecar contents"):
                subject.verify_release_assets(
                    directory,
                    expected_zip_sha256=zip_digest,
                    expected_sidecar_sha256=bad_sidecar_digest,
                )

    def test_rejects_unexpected_extra_archive(self) -> None:
        subject = self.require_verifier()
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            directory = Path(temporary)
            make_assets(directory)
            (directory / "unexpected.zip").write_bytes(b"not pinned")
            with self.assertRaisesRegex(subject.ReleaseVerificationError, "unexpected files"):
                subject.verify_release_assets(directory)

    def test_rejects_symlinked_archive(self) -> None:
        subject = self.require_verifier()
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            root = Path(temporary)
            directory = root / "download"
            directory.mkdir()
            zip_digest, sidecar_digest = make_assets(directory)
            outside = root / "outside.zip"
            outside.write_bytes((directory / "Quick-Drop-Zone-1.2.1.zip").read_bytes())
            (directory / "Quick-Drop-Zone-1.2.1.zip").unlink()
            (directory / "Quick-Drop-Zone-1.2.1.zip").symlink_to(outside)
            with self.assertRaisesRegex(subject.ReleaseVerificationError, "symlink"):
                subject.verify_release_assets(
                    directory,
                    expected_zip_sha256=zip_digest,
                    expected_sidecar_sha256=sidecar_digest,
                )

    def test_release_pins_match_published_v1_2_1_assets(self) -> None:
        subject = self.require_verifier()
        self.assertEqual(subject.EXPECTED_RELEASE_TAG, "v1.2.1")
        self.assertEqual(subject.EXPECTED_ZIP_NAME, "Quick-Drop-Zone-1.2.1.zip")
        self.assertEqual(subject.EXPECTED_SIDECAR_NAME, "Quick-Drop-Zone-1.2.1.zip.sha256")
        self.assertEqual(subject.EXPECTED_ZIP_SHA256, "9ee5652e61c7f886e66b193944da3013439effda3e2005e469ac04ce14837785")
        self.assertEqual(subject.EXPECTED_SIDECAR_SHA256, "f4214d7e20cb3220f9b9cced32df0f875d9b4894a3796ed01a918d946116f156")
        self.assertEqual(subject.EXPECTED_TAG_COMMIT, "0bc41de7eb753d3531ac2450da10ee87db87d8f1")

    def test_capture_verifies_release_before_extract_quarantine_removal_and_launch(self) -> None:
        capture = (SCRIPT_DIR / "capture-readme-media.sh").read_text(encoding="utf-8")
        verify = capture.index("verify-readme-media-release.py")
        extract = capture.index("ditto -x -k")
        unquarantine = capture.index("xattr -dr com.apple.quarantine")
        launch = capture.index('open "$APP"')
        self.assertLess(verify, extract)
        self.assertLess(extract, unquarantine)
        self.assertLess(unquarantine, launch)
        self.assertIn("Quick-Drop-Zone-1.2.1.zip", capture)

    def test_manual_workflow_downloads_pinned_pair_and_keeps_capture_out_of_routine_ci(self) -> None:
        workflow = (SCRIPT_DIR.parent / "workflows" / "readme-media.yml").read_text(encoding="utf-8")
        self.assertIn("github.repository == '9phfr6dsw4-dotcom/quick-drop-zone'", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("gh release download v1.2.1", workflow)
        self.assertIn("Quick-Drop-Zone-1.2.1.zip", workflow)
        self.assertIn("Quick-Drop-Zone-1.2.1.zip.sha256", workflow)
        self.assertIn("0bc41de7eb753d3531ac2450da10ee87db87d8f1", workflow)
        self.assertIn("gh api repos/9phfr6dsw4-dotcom/quick-drop-zone/git/ref/tags/v1.2.1", workflow)
        self.assertIn("verify-readme-media-release.py", workflow)
        macos_ci = (SCRIPT_DIR.parent / "workflows" / "macos-ci.yml").read_text(encoding="utf-8")
        self.assertNotIn("Capture the published release app", macos_ci)
        self.assertIn("test-readme-media-release.py", macos_ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
