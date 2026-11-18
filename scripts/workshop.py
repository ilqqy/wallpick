"""Steam Workshop (Wallpaper Engine) items on disk and in Workshop listings.

Video and scene wallpapers are used, as still images: a frame of the video,
or a scene's background picture (see scenepkg.py). Web and application
wallpapers have no picture to take.
Everything here is filesystem or text parsing; network and steamcmd calls live
in actions.py.
"""

import json
import os
from pathlib import Path
import re


APP_ID = "431960"
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov", ".avi", ".m4v"}
PREVIEW_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif"}
MAX_PROJECT_BYTES = 1024 * 1024


def data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")


def steamcmd_home() -> Path:
    """steamcmd's private HOME. It must not be the user's Steam client folder
    (steamcmd rewrites ~/.steam links), and it must be under the real home
    directory: steam-run hides /tmp from the programs it starts."""
    configured = os.environ.get("WALLPICK_STEAMCMD_HOME")
    return Path(configured).expanduser() if configured else data_home() / "wallpick" / "steamcmd"


def steamcmd_root() -> Path:
    # nixpkgs' steamcmd wrapper keeps its Steam root at $HOME/.local/share/Steam.
    return steamcmd_home() / ".local" / "share" / "Steam"


def steam_roots() -> list[Path]:
    """Steam client installs: native, ~/.steam and Flatpak."""
    configured = os.environ.get("WALLPICK_STEAM_DIR")
    if configured:
        candidates = [Path(configured).expanduser()]
    else:
        home = Path.home()
        candidates = [data_home() / "Steam", home / ".steam" / "steam",
                      home / ".var" / "app" / "com.valvesoftware.Steam" / ".local" / "share" / "Steam"]
    return unique_dirs(candidates)


def unique_dirs(paths) -> list[Path]:
    seen, result = set(), []
    for path in paths:
        try:
            resolved = path.resolve()
            if resolved in seen or not resolved.is_dir():
                continue
        except OSError:
            continue
        seen.add(resolved)
        result.append(resolved)
    return result


def library_folders(root: Path) -> list[Path]:
    """The Steam root plus the extra libraries listed in libraryfolders.vdf."""
    folders = [root]
    try:
        text = (root / "steamapps" / "libraryfolders.vdf").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return folders
    for match in re.finditer(r'"path"\s+"((?:[^"\\]|\\.)*)"', text):
        folders.append(Path(match.group(1).replace("\\\\", "\\")))
    return folders


def content_dirs() -> list[Path]:
    """Every folder Steam or Wallpick's steamcmd downloads Wallpaper Engine items to."""
    libraries = [library for root in steam_roots() for library in library_folders(root)]
    libraries.append(steamcmd_root())
    return unique_dirs(library / "steamapps" / "workshop" / "content" / APP_ID for library in libraries)


def valid_id(value: object) -> bool:
    return isinstance(value, str) and value.isascii() and value.isdigit() and 0 < len(value) <= 20


def inside(path: Path, folder: Path) -> Path | None:
    """The resolved path if it stays inside folder (project.json is untrusted)."""
    try:
        resolved = (folder / path).resolve()
        return resolved if resolved.is_relative_to(folder.resolve()) and resolved.is_file() else None
    except (OSError, ValueError):
        return None


def read_project(folder: Path) -> dict | None:
    """A video or scene item's details from its project.json, or None for
    anything else. "kind" is "video" or "scene"; "video" is its file."""
    try:
        project = folder / "project.json"
        if project.stat().st_size > MAX_PROJECT_BYTES:
            return None
        data = json.loads(project.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return None
    kind = str(data.get("type", "")).lower() if isinstance(data, dict) else ""
    if kind not in ("video", "scene"):
        return None
    raw_file = data.get("file")
    video = None
    if kind == "video":
        video = inside(Path(raw_file), folder) if isinstance(raw_file, str) and raw_file else None
        if not video or video.suffix.lower() not in VIDEO_EXTENSIONS:
            return None
    elif not ((folder / "scene.pkg").is_file() or (folder / "materials").is_dir()):
        return None
    raw_preview = data.get("preview")
    preview = inside(Path(raw_preview), folder) if isinstance(raw_preview, str) and raw_preview else None
    if preview and preview.suffix.lower() not in PREVIEW_EXTENSIONS:
        preview = None
    title = data.get("title")
    return {"kind": kind, "video": video, "preview": preview,
            "title": title.strip()[:120] if isinstance(title, str) and title.strip() else ""}


def find_item(identifier: str) -> Path | None:
    if not valid_id(identifier):
        return None
    for directory in content_dirs():
        folder = directory / identifier
        if (folder / "project.json").is_file():
            return folder
    return None


def wallpaper_items() -> list[dict]:
    """Downloaded video and scene wallpapers, newest first; one per Workshop ID."""
    items = {}
    for directory in content_dirs():
        try:
            folders = [folder for folder in directory.iterdir() if valid_id(folder.name) and folder.is_dir()]
        except OSError:
            continue
        for folder in folders:
            if folder.name in items:
                continue
            info = read_project(folder)
            if not info:
                continue
            try:
                mtime = (info["video"] or folder / "project.json").stat().st_mtime
            except OSError:
                continue
            items[folder.name] = {"id": folder.name, "folder": folder, "mtime": mtime, **info}
    return sorted(items.values(), key=lambda item: item["mtime"], reverse=True)


def browse_results(html: str) -> tuple[list[dict], int] | None:
    """Results and page count embedded in a Workshop browse page, or None
    when the page no longer embeds them."""
    match = re.search(r'<script[^>]*id="valve-ssr-data"[^>]*>(.*?)</script>', html, re.S)
    if not match:
        return None
    try:
        data = json.loads(match.group(1))
    except ValueError:
        return None
    # The listing is a query result nested in JSON strings inside the page data.
    stack = [data]
    while stack:
        value = stack.pop()
        if isinstance(value, str):
            if value[:1] in "{[":
                try:
                    stack.append(json.loads(value))
                except ValueError:
                    pass
            continue
        if isinstance(value, dict):
            if isinstance(value.get("results"), list) and isinstance(value.get("total_pages"), int):
                return value["results"], value["total_pages"]
            stack.extend(value.values())
        elif isinstance(value, list):
            stack.extend(value)
    return None


def browse_ids(html: str) -> list[str]:
    """Item IDs linked from a browse page, in page order (fallback parser)."""
    seen = []
    for identifier in re.findall(r"sharedfiles/filedetails/\?id=(\d{1,20})", html):
        if identifier not in seen:
            seen.append(identifier)
    return seen


def tag_names(item: dict) -> set[str]:
    tags = item.get("tags")
    return {tag.get("tag") for tag in tags if isinstance(tag, dict) and isinstance(tag.get("tag"), str)} \
        if isinstance(tags, list) else set()


def resolution(tags: set[str]) -> tuple[int, int] | None:
    """The resolution a creator tagged, such as "3840 x 2160" or "Ultrawide 3440 x 1440"."""
    for tag in tags:
        match = re.search(r"(\d{3,5})\s*x\s*(\d{3,5})", tag)
        if match:
            return int(match.group(1)), int(match.group(2))
    return None
