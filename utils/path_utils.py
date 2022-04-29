#!/usr/bin/env python3

from __future__ import annotations
from pathlib import Path


def norm_path(path: Path) -> Path:
    prefix_parts: list[str] = []
    parts = list(path.parts)
    if path.anchor:
        prefix_parts.append(parts.pop(0))

    norm_parts: list[str] = []
    for part in parts:
        assert part not in ("", ".")  # shouldn't happen with Path.parts
        if part == ".." and norm_parts and norm_parts[-1] != "..":
            norm_parts.pop()
        else:
            norm_parts.append(part)
    if path.root:  # remove leading ".."'s
        while norm_parts and norm_parts[0] == "..":
            norm_parts.pop(0)
    return Path(*prefix_parts, *norm_parts)


def traverse_up_until_file(
    from_path: Path,
    until_filename: str,
    stop_at: Path | None = None,
) -> Path | None:
    if stop_at is not None:
        if not stop_at.exists():
            raise ValueError(f"path {stop_at} does not exist")
        if not stop_at.is_dir():
            raise ValueError(f"path {stop_at} must be a directory")

    curr_path = from_path
    while True:
        maybe_path = curr_path / until_filename
        if maybe_path.is_file():
            return maybe_path
        if stop_at is not None and curr_path == stop_at:
            return None
        if curr_path.parent == curr_path:
            return None
        curr_path = curr_path.parent  # pragma: no cover
