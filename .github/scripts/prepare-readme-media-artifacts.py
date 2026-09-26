#!/usr/bin/env python3
"""Safely clear the manual README-media artifact directory under RUNNER_TEMP."""
from __future__ import annotations

import errno
import os
from pathlib import Path
import shutil
import stat
import sys


def prepare(runner_temp: str, artifact_dir: str) -> None:
    runner_argument = Path(runner_temp)
    artifact_argument = Path(artifact_dir)
    if not runner_argument.is_absolute() or not artifact_argument.is_absolute():
        raise SystemExit("RUNNER_TEMP and artifact directory must be absolute paths")
    if runner_argument.is_symlink():
        raise SystemExit("Refusing a symlinked RUNNER_TEMP")

    try:
        runner_root = runner_argument.resolve(strict=True)
    except OSError as error:
        raise SystemExit(f"RUNNER_TEMP is unavailable: {error}") from error
    if not runner_root.is_dir():
        raise SystemExit("RUNNER_TEMP must be an existing directory")

    expected_artifact = runner_argument / "readme-media"
    if artifact_argument != expected_artifact:
        raise SystemExit("Refusing to clean any directory except RUNNER_TEMP/readme-media")
    if artifact_argument.parent.resolve(strict=True) != runner_root:
        raise SystemExit("Artifact directory parent escaped RUNNER_TEMP")

    required_flags = ("O_DIRECTORY", "O_NOFOLLOW")
    if any(not hasattr(os, flag) for flag in required_flags):
        raise SystemExit("This platform cannot safely open artifact directories without following symlinks")
    if not shutil.rmtree.avoids_symlink_attacks:
        raise SystemExit("This platform cannot safely remove nested artifact directories")

    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    runner_fd = artifact_fd = None
    try:
        runner_fd = os.open(runner_root, flags)
        try:
            os.mkdir("readme-media", mode=0o700, dir_fd=runner_fd)
        except FileExistsError:
            pass
        try:
            artifact_fd = os.open("readme-media", flags, dir_fd=runner_fd)
        except OSError as error:
            if error.errno in (errno.ELOOP, errno.ENOTDIR):
                raise SystemExit("Refusing a symlink or non-directory artifact path") from error
            raise

        if not stat.S_ISDIR(os.fstat(artifact_fd).st_mode):
            raise SystemExit("Artifact path is not a directory under RUNNER_TEMP")
        os.fchmod(artifact_fd, 0o700)
        for entry in os.listdir(artifact_fd):
            entry_stat = os.stat(entry, dir_fd=artifact_fd, follow_symlinks=False)
            if stat.S_ISDIR(entry_stat.st_mode):
                shutil.rmtree(entry, dir_fd=artifact_fd)
            else:
                os.unlink(entry, dir_fd=artifact_fd)
    except SystemExit:
        raise
    except OSError as error:
        raise SystemExit(f"Could not safely prepare README-media artifacts: {error}") from error
    finally:
        if artifact_fd is not None:
            os.close(artifact_fd)
        if runner_fd is not None:
            os.close(runner_fd)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: prepare-readme-media-artifacts.py RUNNER_TEMP ARTIFACT_DIR")
    prepare(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
