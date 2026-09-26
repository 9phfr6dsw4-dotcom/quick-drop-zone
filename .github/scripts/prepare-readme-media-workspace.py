#!/usr/bin/env python3
"""Validate and prepare path-confined README-media workspace directories."""
from __future__ import annotations

import errno
import os
from pathlib import Path
import shutil
import stat
import sys

SLUGS = {
    "clipboard-shelf": "clipboard-shelf",
    "quick-drop-zone": "quick-drop-zone",
    "echotype": "echotype",
    "captiongrab": "captiongrab",
}
DIRECTORY_FLAGS = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)


class UnsafePath(ValueError):
    pass


def require_physical_directory(raw_path: str, label: str) -> Path:
    path = Path(raw_path)
    if not path.is_absolute():
        raise UnsafePath(f"{label} must be an absolute path")
    if path.is_symlink():
        raise UnsafePath(f"Refusing symlinked {label}: {path}")
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise UnsafePath(f"{label} is unavailable: {error}") from error
    if resolved != path:
        raise UnsafePath(f"Refusing non-physical {label} path (symlink or path alias): {path}")
    if not path.is_dir():
        raise UnsafePath(f"{label} must be a directory")
    return path


def check_directory_path(path: Path, label: str, *, required: bool) -> None:
    if path.is_symlink():
        raise UnsafePath(f"Refusing symlinked {label}: {path}")
    if not path.exists():
        if required:
            raise UnsafePath(f"Required {label} directory is missing: {path}")
        return
    if not path.is_dir():
        raise UnsafePath(f"{label} is not a directory: {path}")
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise UnsafePath(f"Could not resolve {label}: {error}") from error
    if resolved != path:
        raise UnsafePath(f"Refusing non-physical {label} path (symlink or path alias): {path}")


def check_regular_or_missing(path: Path, label: str) -> None:
    if path.is_symlink():
        raise UnsafePath(f"Refusing symlinked {label}: {path}")
    if path.exists() and not path.is_file():
        raise UnsafePath(f"{label} is not a regular file: {path}")


def validate(root_arg: str, runner_arg: str, app_key: str, *, require_prepared: bool) -> tuple[Path, Path, str]:
    if app_key not in SLUGS:
        raise UnsafePath(f"Unknown APP_KEY: {app_key}")
    root = require_physical_directory(root_arg, "repository root")
    runner = require_physical_directory(runner_arg, "RUNNER_TEMP")

    script = root / ".github" / "scripts" / "capture-readme-media.sh"
    if script.is_symlink() or not script.is_file() or script.resolve(strict=True) != script:
        raise UnsafePath("Capture script is missing or does not resolve inside the physical repository root")

    docs = root / "docs"
    images = docs / "images"
    check_directory_path(docs, "docs", required=True)
    check_directory_path(images, "docs/images", required=True)

    slug = SLUGS[app_key]
    icon = images / f"{slug}-icon.png"
    if icon.is_symlink() or not icon.is_file():
        raise UnsafePath(f"Required app icon is missing, non-regular, or symlinked: {icon}")
    for name in (f"{slug}-light.png", f"{slug}-dark.png", f"{slug}-hero.gif", "social-preview.png"):
        check_regular_or_missing(images / name, "capture output")

    for name in (
        "readme-wallpaper.png",
        "readme-capture.mov",
        f"{slug}-palette.png",
        f"{slug}-optimized.gif",
    ):
        check_regular_or_missing(runner / name, "temporary capture output")
    check_directory_path(runner / f"readme-frames-{slug}", "temporary frame directory", required=False)

    expected_directories = [
        runner / "readme-media",
        runner / "release-app",
        runner / "release-download",
    ]
    if app_key == "quick-drop-zone":
        expected_directories.extend(
            [
                runner / "quick-drop-zone-demo",
                runner / "quick-drop-zone-demo" / "Downloads",
                runner / "quick-drop-zone-demo" / "Applications",
                runner / "quick-drop-zone-demo" / "Applications" / "Sample Studio.app",
                runner / "quick-drop-zone-demo" / "Applications" / "Sample Studio.app" / "Contents",
            ]
        )
    for path in expected_directories:
        check_directory_path(path, f"temporary directory {path.name}", required=require_prepared)

    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise UnsafePath("This platform cannot safely open directories without following symlinks")
    if not shutil.rmtree.avoids_symlink_attacks:
        raise UnsafePath("This platform cannot safely clear nested temporary directories")
    return root, runner, slug


def open_child_directory(parent_fd: int, name: str, *, create: bool) -> int:
    if "/" in name or name in ("", ".", ".."):
        raise UnsafePath(f"Invalid directory component: {name!r}")
    if create:
        try:
            os.mkdir(name, mode=0o700, dir_fd=parent_fd)
        except FileExistsError:
            pass
    try:
        child_fd = os.open(name, DIRECTORY_FLAGS, dir_fd=parent_fd)
    except OSError as error:
        if error.errno in (errno.ELOOP, errno.ENOTDIR):
            raise UnsafePath(f"Refusing symlink or non-directory path component: {name}") from error
        raise
    if not stat.S_ISDIR(os.fstat(child_fd).st_mode):
        os.close(child_fd)
        raise UnsafePath(f"Path component is not a directory: {name}")
    return child_fd


def clear_directory(directory_fd: int) -> None:
    for entry in os.listdir(directory_fd):
        entry_stat = os.stat(entry, dir_fd=directory_fd, follow_symlinks=False)
        if stat.S_ISDIR(entry_stat.st_mode):
            shutil.rmtree(entry, dir_fd=directory_fd)
        else:
            os.unlink(entry, dir_fd=directory_fd)


def ensure_directory(runner_fd: int, components: tuple[str, ...], *, clear: bool = False) -> None:
    current_fd = os.dup(runner_fd)
    try:
        for component in components:
            next_fd = open_child_directory(current_fd, component, create=True)
            os.close(current_fd)
            current_fd = next_fd
        if clear:
            clear_directory(current_fd)
    finally:
        os.close(current_fd)


def prepare(runner: Path, app_key: str) -> None:
    runner_fd = os.open(runner, DIRECTORY_FLAGS)
    try:
        ensure_directory(runner_fd, ("readme-media",))
        ensure_directory(runner_fd, ("release-app",), clear=True)
        ensure_directory(runner_fd, ("release-download",), clear=True)
        if app_key == "quick-drop-zone":
            ensure_directory(runner_fd, ("quick-drop-zone-demo",), clear=True)
            ensure_directory(runner_fd, ("quick-drop-zone-demo", "Downloads"))
            ensure_directory(runner_fd, ("quick-drop-zone-demo", "Applications", "Sample Studio.app", "Contents"))
    finally:
        os.close(runner_fd)


def main() -> None:
    if len(sys.argv) not in (4, 5):
        raise SystemExit(
            "Usage: prepare-readme-media-workspace.py REPOSITORY_ROOT RUNNER_TEMP APP_KEY [--validate-only]"
        )
    root_arg, runner_arg, app_key = sys.argv[1:4]
    validate_only = len(sys.argv) == 5 and sys.argv[4] == "--validate-only"
    if len(sys.argv) == 5 and not validate_only:
        raise SystemExit("The only supported option is --validate-only")
    try:
        root, runner, _ = validate(root_arg, runner_arg, app_key, require_prepared=validate_only)
        if not validate_only:
            prepare(runner, app_key)
        print(f"{'Validated' if validate_only else 'Prepared'} path-safe README-media workspace.")
    except (OSError, UnsafePath) as error:
        raise SystemExit(f"README-media path validation failed: {error}") from error


if __name__ == "__main__":
    main()
