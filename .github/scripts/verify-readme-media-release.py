#!/usr/bin/env python3
"""Verify the pinned Quick Drop Zone release ZIP and published checksum sidecar."""
from __future__ import annotations

import errno
import hashlib
import os
from pathlib import Path
import re
import stat
import sys

EXPECTED_RELEASE_TAG = "v1.2.1"
EXPECTED_TAG_COMMIT = "0bc41de7eb753d3531ac2450da10ee87db87d8f1"
EXPECTED_ZIP_NAME = "Quick-Drop-Zone-1.2.1.zip"
EXPECTED_SIDECAR_NAME = "Quick-Drop-Zone-1.2.1.zip.sha256"
EXPECTED_ZIP_SHA256 = "9ee5652e61c7f886e66b193944da3013439effda3e2005e469ac04ce14837785"
EXPECTED_SIDECAR_SHA256 = "f4214d7e20cb3220f9b9cced32df0f875d9b4894a3796ed01a918d946116f156"


class ReleaseVerificationError(ValueError):
    """Raised when the downloaded release assets are not the pinned pair."""


def _open_regular_file(directory_fd: int, name: str) -> int:
    try:
        descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory_fd)
    except OSError as error:
        if error.errno in (errno.ELOOP, errno.ENOTDIR):
            raise ReleaseVerificationError(f"Refusing symlinked release asset: {name}") from error
        if error.errno == errno.ENOENT:
            raise ReleaseVerificationError(f"Missing release asset: {name}") from error
        raise
    if not stat.S_ISREG(os.fstat(descriptor).st_mode):
        os.close(descriptor)
        raise ReleaseVerificationError(f"Release asset is not a regular file: {name}")
    return descriptor


def _sha256_file(descriptor: int) -> str:
    with os.fdopen(os.dup(descriptor), "rb") as asset:
        return hashlib.file_digest(asset, "sha256").hexdigest()


def _sidecar_bytes(descriptor: int) -> bytes:
    if os.fstat(descriptor).st_size > 512:
        raise ReleaseVerificationError("Checksum sidecar is unexpectedly large")
    content = os.pread(descriptor, 513, 0)
    if not content or len(content) > 512:
        raise ReleaseVerificationError("Checksum sidecar is empty or unexpectedly large")
    return content


def verify_release_assets(
    download_directory: str | Path,
    *,
    expected_zip_sha256: str = EXPECTED_ZIP_SHA256,
    expected_sidecar_sha256: str = EXPECTED_SIDECAR_SHA256,
) -> Path:
    directory = Path(download_directory)
    if not directory.is_absolute():
        raise ReleaseVerificationError("Release download directory must be absolute")
    if directory.is_symlink():
        raise ReleaseVerificationError("Refusing symlinked release download directory")
    try:
        resolved_directory = directory.resolve(strict=True)
    except OSError as error:
        raise ReleaseVerificationError(f"Release download directory is unavailable: {error}") from error
    if resolved_directory != directory or not directory.is_dir():
        raise ReleaseVerificationError("Release download directory is not a physical directory")

    for label, digest in (
        ("ZIP", expected_zip_sha256),
        ("sidecar", expected_sidecar_sha256),
    ):
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ReleaseVerificationError(f"Invalid pinned {label} SHA-256")

    if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
        raise ReleaseVerificationError("This platform cannot safely open release paths without following symlinks")
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        directory_fd = os.open(directory, directory_flags)
    except OSError as error:
        raise ReleaseVerificationError(f"Could not safely open release download directory: {error}") from error

    zip_fd = sidecar_fd = None
    try:
        actual_names = set(os.listdir(directory_fd))
        expected_names = {EXPECTED_ZIP_NAME, EXPECTED_SIDECAR_NAME}
        unexpected = sorted(actual_names - expected_names)
        if unexpected:
            raise ReleaseVerificationError(f"Refusing unexpected files in release download directory: {unexpected}")
        missing = sorted(expected_names - actual_names)
        if missing:
            raise ReleaseVerificationError(f"Missing pinned release assets: {missing}")

        zip_fd = _open_regular_file(directory_fd, EXPECTED_ZIP_NAME)
        sidecar_fd = _open_regular_file(directory_fd, EXPECTED_SIDECAR_NAME)
        sidecar_digest = _sha256_file(sidecar_fd)
        if sidecar_digest != expected_sidecar_sha256:
            raise ReleaseVerificationError(
                f"Checksum sidecar SHA-256 mismatch: expected {expected_sidecar_sha256}, got {sidecar_digest}"
            )

        zip_digest = _sha256_file(zip_fd)
        if zip_digest != expected_zip_sha256:
            raise ReleaseVerificationError(
                f"Release ZIP SHA-256 mismatch: expected {expected_zip_sha256}, got {zip_digest}"
            )

        expected_sidecar = f"{expected_zip_sha256}  dist/{EXPECTED_ZIP_NAME}\n".encode("ascii")
        if _sidecar_bytes(sidecar_fd) != expected_sidecar:
            raise ReleaseVerificationError("Published checksum sidecar contents do not match the pinned ZIP name and digest")
        return directory / EXPECTED_ZIP_NAME
    finally:
        if sidecar_fd is not None:
            os.close(sidecar_fd)
        if zip_fd is not None:
            os.close(zip_fd)
        os.close(directory_fd)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify-readme-media-release.py RELEASE_DOWNLOAD_DIRECTORY")
    try:
        path = verify_release_assets(sys.argv[1])
    except (OSError, ReleaseVerificationError) as error:
        raise SystemExit(f"Published release verification failed: {error}") from error
    print(f"Verified {EXPECTED_RELEASE_TAG} {EXPECTED_ZIP_NAME} SHA-256 {EXPECTED_ZIP_SHA256}")
    print(f"Verified checksum sidecar {EXPECTED_SIDECAR_NAME} SHA-256 {EXPECTED_SIDECAR_SHA256}")
    print(f"Verified release archive: {path}")


if __name__ == "__main__":
    main()
