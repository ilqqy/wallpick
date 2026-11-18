#!/usr/bin/env python3
"""Local wallpaper index and selected-file favorite helper for the QML UI."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import workshop


EXTENSIONS = {".jpg", ".jpeg", ".png"}
FOLDERS = {
    "favorites": "favorite",
    "anime": "random_konachan",
    "general": "random_wallhaven",
    "gooner": "random_gooner",
    # Still frames of Wallpaper Engine video wallpapers.
    "workshop": "random_workshop",
}


def pictures_dir() -> Path:
    return Path(os.environ.get("WALLPICK_PICTURES_DIR", "~/Pictures")).expanduser().resolve()


def digest(path: Path) -> str:
    hashed = hashlib.sha256()
    with path.open("rb") as image:
        for chunk in iter(lambda: image.read(1024 * 1024), b""):
            hashed.update(chunk)
    return hashed.hexdigest()


def images(folder: Path) -> list[Path]:
    if not folder.is_dir():
        return []
    try:
        files = []
        for path in folder.iterdir():
            try:
                if path.is_file() and path.suffix.lower() in EXTENSIONS:
                    files.append((path.stat().st_mtime, path))
            except OSError:
                continue
    except OSError:
        return []
    return [path for _, path in sorted(files, key=lambda entry: entry[0], reverse=True)]


def record(path: Path, source: str, applied: bool = False) -> dict:
    stat = path.stat()
    return {
        "path": str(path),
        # The current marker is overwritten in place. A revision in the URL
        # invalidates Qt's image cache without changing the command path.
        "url": path.as_uri() + f"?v={stat.st_mtime_ns}",
        "name": path.name,
        "source": source,
        "mtime": stat.st_mtime,
        "applied": applied,
    }


def scan() -> dict:
    root = pictures_dir()
    current_files = images(root / ".current-wallpaper")
    current = current_files[0] if current_files else None
    try:
        current_size = current.stat().st_size if current else None
        current_digest = digest(current) if current else None
        current_record = record(current, "current", True) if current else None
    except OSError:
        # wallset replaces the marker; a concurrent scan can catch it between files.
        current = None
        current_size = current_digest = current_record = None

    sources = {}
    all_items = []
    for key, name in FOLDERS.items():
        folder = root / name
        collection = []
        for path in images(folder):
            same = False
            try:
                if current and path.stat().st_size == current_size:
                    same = digest(path) == current_digest
                collection.append(record(path, key, same))
            except OSError:
                continue
        sources[key] = {"exists": folder.is_dir(), "path": str(folder), "items": collection}
        all_items.extend(collection)

    add_workshop_items(sources["workshop"])

    # Keep the separate questionable collection out of the default feed.
    recent = sorted((item for item in all_items if item["source"] != "gooner"),
                    key=lambda item: item["mtime"], reverse=True)[:40]
    sources["recent"] = {"exists": bool(all_items), "path": "", "items": recent}

    applied_path = next((item["path"] for item in all_items if item["applied"]), "")
    return {"pictures": str(root), "sources": sources,
            "current": current_record, "appliedPath": applied_path}


def add_workshop_items(source: dict) -> None:
    """Video and scene wallpapers Steam has downloaded but Wallpick has not
    turned into a still yet. Applying one saves its still into the Workshop folder."""
    saved = {Path(item["path"]).stem for item in source["items"]}
    pending = []
    for entry in workshop.wallpaper_items():
        stem = f"workshop_{entry['id']}"
        if stem in saved:
            continue
        preview = entry["preview"].as_uri() if entry["preview"] else ""
        pending.append({
            "key": f"workshop:{stem}",
            "id": entry["id"],
            "stem": stem,
            "source": "workshop",
            # Not an image file yet, so it is applied like a search result.
            "remote": True,
            "path": "",
            "name": entry["title"] or f"Workshop #{entry['id']}",
            "url": preview,
            "preview": preview,
            "full": "steam",
            "mtime": entry["mtime"],
            "applied": False,
        })
    if pending:
        source["exists"] = True
        source["items"] = sorted(source["items"] + pending, key=lambda item: item["mtime"], reverse=True)


def favorite_selected(raw_path: str) -> dict:
    path = Path(raw_path).expanduser().resolve(strict=True)
    root = pictures_dir().resolve()
    permitted = [root / name for name in FOLDERS.values()]
    if path.suffix.lower() not in EXTENSIONS or not any(path.is_relative_to(folder) for folder in permitted):
        raise ValueError("Selected image is outside the configured wallpaper folders")
    destination = root / FOLDERS["favorites"]
    destination.mkdir(parents=True, exist_ok=True)
    candidate = destination / f"favorite_{int(time.time())}{path.suffix.lower()}"
    counter = 1
    while candidate.exists():
        candidate = destination / f"favorite_{int(time.time())}_{counter}{path.suffix.lower()}"
        counter += 1
    shutil.copy(path, candidate)
    return {"path": str(candidate), "name": candidate.name}


def cursor_position() -> dict:
    """Optional host integration; absence of hyprctl must not prevent opening."""
    command = shutil.which("hyprctl")
    if not command or not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return {}
    try:
        output = subprocess.run([command, "cursorpos", "-j"], capture_output=True,
                                text=True, check=True, timeout=0.5)
        value = json.loads(output.stdout)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["scan", "favorite-selected", "cursor"])
    parser.add_argument("path", nargs="?")
    args = parser.parse_args()
    try:
        if args.command == "scan":
            result = scan()
        elif args.command == "cursor":
            result = cursor_position()
        else:
            if not args.path:
                parser.error("favorite-selected requires a path")
            result = favorite_selected(args.path)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
