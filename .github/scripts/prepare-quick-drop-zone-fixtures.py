#!/usr/bin/env python3
"""Create synthetic Quick Drop Zone fixtures only beneath RUNNER_TEMP."""
from __future__ import annotations

import errno
import os
from pathlib import Path
import shutil
import stat
import sys

FLAGS = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
FIXTURE_TEXT = {
    "Atlas-project-brief.pdf": "Sample project brief for a fictional Atlas workspace.\n",
    "Atlas-review-notes.md": "Review notes for the fictional Atlas workspace.\n",
    "Atlas-timeline.xlsx": "Timeline data for the fictional Atlas workspace.\n",
    "Atlas-copy-draft.docx": "Draft copy for the fictional Atlas workspace.\n",
    "Team-agenda-2026-08.docx": "Sample team agenda.\n",
    "invoice-2026-08.pdf": "Receipt sample.\n",
    "holiday-photos.zip": "Archive sample.\n",
    "meeting-notes.md": "Meeting notes sample.\n",
    "brand-board.sketch": "Design draft sample.\n",
    "Sample Studio.dmg": "Installer sample.\n",
    "export-final-2.csv": "Temporary export sample.\n",
}
SCREENSHOT_NAME = "Screenshot 2026-09-20 at 10.14.03.png"


class FixtureError(ValueError):
    pass


def physical_directory(path: Path, label: str) -> Path:
    if not path.is_absolute():
        raise FixtureError(f"{label} must be an absolute path")
    if path.is_symlink():
        raise FixtureError(f"Refusing symlinked {label}: {path}")
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise FixtureError(f"{label} is unavailable: {error}") from error
    if resolved != path or not path.is_dir():
        raise FixtureError(f"Refusing non-physical or non-directory {label}: {path}")
    return path


def open_child(parent_fd: int, name: str, *, create: bool = False) -> int:
    if "/" in name or name in ("", ".", ".."):
        raise FixtureError(f"Invalid path component: {name!r}")
    if create:
        try:
            os.mkdir(name, mode=0o700, dir_fd=parent_fd)
        except FileExistsError:
            pass
    try:
        descriptor = os.open(name, FLAGS, dir_fd=parent_fd)
    except OSError as error:
        if error.errno in (errno.ELOOP, errno.ENOTDIR):
            raise FixtureError(f"Refusing symlink or non-directory path component: {name}") from error
        raise
    if not stat.S_ISDIR(os.fstat(descriptor).st_mode):
        os.close(descriptor)
        raise FixtureError(f"Expected a directory: {name}")
    return descriptor


def open_chain(root_fd: int, components: tuple[str, ...]) -> int:
    current_fd = os.dup(root_fd)
    try:
        for component in components:
            next_fd = open_child(current_fd, component)
            os.close(current_fd)
            current_fd = next_fd
        return current_fd
    except BaseException:
        os.close(current_fd)
        raise


def clear_directory(directory_fd: int) -> None:
    if not shutil.rmtree.avoids_symlink_attacks:
        raise FixtureError("This platform cannot safely clear nested fixture directories")
    for entry in os.listdir(directory_fd):
        entry_stat = os.stat(entry, dir_fd=directory_fd, follow_symlinks=False)
        if stat.S_ISDIR(entry_stat.st_mode):
            shutil.rmtree(entry, dir_fd=directory_fd)
        else:
            os.unlink(entry, dir_fd=directory_fd)


def write_file(directory_fd: int, name: str, data: bytes) -> None:
    descriptor = os.open(
        name,
        os.O_WRONLY | os.O_CREAT | os.O_TRUNC | NOFOLLOW,
        0o600,
        dir_fd=directory_fd,
    )
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise FixtureError(f"Fixture target is not a regular file: {name}")
        with os.fdopen(descriptor, "wb", closefd=False) as output:
            output.write(data)
    finally:
        os.close(descriptor)


def prepare(runner_temp: str, wallpaper_path: str) -> None:
    runner = physical_directory(Path(runner_temp), "RUNNER_TEMP")
    wallpaper = Path(wallpaper_path)
    if not wallpaper.is_absolute() or wallpaper.parent != runner or wallpaper.name != "readme-wallpaper.png":
        raise FixtureError("Wallpaper must be RUNNER_TEMP/readme-wallpaper.png")
    if wallpaper.is_symlink() or not wallpaper.is_file() or wallpaper.resolve(strict=True) != wallpaper:
        raise FixtureError("Refusing missing, non-regular, or symlinked fixture wallpaper")
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise FixtureError("This platform cannot safely open fixture directories without following symlinks")

    runner_fd = os.open(runner, FLAGS)
    downloads_fd = contents_fd = wallpaper_fd = None
    try:
        demo_fd = open_chain(runner_fd, ("quick-drop-zone-demo",))
        try:
            downloads_fd = open_child(demo_fd, "Downloads")
            app_fd = open_child(demo_fd, "Applications")
            try:
                bundle_fd = open_child(app_fd, "Sample Studio.app")
                try:
                    contents_fd = open_child(bundle_fd, "Contents")
                finally:
                    os.close(bundle_fd)
            finally:
                os.close(app_fd)
            clear_directory(downloads_fd)
            clear_directory(contents_fd)
        finally:
            os.close(demo_fd)

        wallpaper_fd = os.open("readme-wallpaper.png", os.O_RDONLY | NOFOLLOW, dir_fd=runner_fd)
        if not stat.S_ISREG(os.fstat(wallpaper_fd).st_mode):
            raise FixtureError("Fixture wallpaper is not a regular file")
        with os.fdopen(os.dup(wallpaper_fd), "rb") as source:
            wallpaper_bytes = source.read()
        if not wallpaper_bytes:
            raise FixtureError("Fixture wallpaper is empty")

        for name, content in FIXTURE_TEXT.items():
            write_file(downloads_fd, name, content.encode("utf-8"))
        write_file(downloads_fd, SCREENSHOT_NAME, wallpaper_bytes)
        write_file(contents_fd, "Info.plist", b"Synthetic demo app marker.\n")
    finally:
        if wallpaper_fd is not None:
            os.close(wallpaper_fd)
        if contents_fd is not None:
            os.close(contents_fd)
        if downloads_fd is not None:
            os.close(downloads_fd)
        os.close(runner_fd)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: prepare-quick-drop-zone-fixtures.py RUNNER_TEMP WALLPAPER")
    try:
        prepare(sys.argv[1], sys.argv[2])
    except (OSError, FixtureError) as error:
        raise SystemExit(f"Quick Drop Zone fixture preparation failed: {error}") from error
    print("Prepared synthetic Quick Drop Zone fixtures under RUNNER_TEMP.")


if __name__ == "__main__":
    main()
