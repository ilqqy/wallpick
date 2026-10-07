#!/usr/bin/env python3
"""Standalone wallpaper actions using the existing Pictures directory layout.

This module never evaluates a shell command. The GUI starts it as a subprocess so
network, image validation, and wallpaper changes cannot block the QML thread.
"""

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import quote, urlsplit
import warnings

from PIL import Image, UnidentifiedImageError

import backend


MAX_IMAGE_BYTES = 100 * 1024 * 1024
MAX_IMAGE_PIXELS = 80_000_000
IMAGE_EXTENSION = {"PNG": "png", "JPEG": "jpg"}
MANAGED_MARKERS = ("wallpaper.png", "wallpaper.jpg", "wallpaper.jpeg")


class ActionError(Exception):
    """A recoverable action failure suitable for presentation in the UI."""


def run_process(argv: list[str], timeout: int, *, capture: bool = True) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            argv,
            check=False,
            timeout=timeout,
            stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
    except subprocess.TimeoutExpired as error:
        raise ActionError(f"Timed out while running {Path(argv[0]).name}") from error
    except OSError as error:
        raise ActionError(f"Could not start {Path(argv[0]).name}: {error}") from error


def require_command(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise ActionError(f"Required command is unavailable: {name}")
    return path


def validate_image(path: Path, *, minimum: tuple[int, int] | None = None) -> tuple[str, tuple[int, int]]:
    try:
        if not path.is_file():
            raise ActionError(f"Image does not exist: {path}")
        size = path.stat().st_size
        if size <= 0 or size > MAX_IMAGE_BYTES:
            raise ActionError("Image is empty or exceeds the 100 MiB limit")
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(path) as image:
                image_format = image.format
                dimensions = image.size
                if dimensions[0] * dimensions[1] > MAX_IMAGE_PIXELS:
                    raise ActionError("Image dimensions exceed the 80 megapixel limit")
                image.verify()
            # verify() checks metadata but a truncated JPEG can still fail to decode.
            with Image.open(path) as image:
                image.load()
    except (UnidentifiedImageError, OSError, ValueError,
            Image.DecompressionBombError, Image.DecompressionBombWarning) as error:
        raise ActionError(f"Invalid image: {path.name}: {error}") from error
    if image_format not in IMAGE_EXTENSION:
        raise ActionError("Only PNG and JPEG wallpapers are supported")
    if minimum and (dimensions[0] < minimum[0] or dimensions[1] < minimum[1]):
        raise ActionError(
            f"Wallpaper is {dimensions[0]}×{dimensions[1]}; minimum is {minimum[0]}×{minimum[1]}"
        )
    return IMAGE_EXTENSION[image_format], dimensions


def min_dimensions() -> tuple[int, int]:
    values = []
    for name, default in (("WALLPICK_MIN_WIDTH", 1920), ("WALLPICK_MIN_HEIGHT", 1080)):
        raw = os.environ.get(name, str(default))
        try:
            value = int(raw)
        except ValueError as error:
            raise ActionError(f"{name} must be a positive integer") from error
        if not 1 <= value <= 32768:
            raise ActionError(f"{name} must be between 1 and 32768")
        values.append(value)
    return values[0], values[1]


def action_lock_path() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime and Path(runtime).is_dir():
        return Path(runtime) / "wallpick-actions.lock"
    cache = Path(os.environ.get("XDG_CACHE_HOME", "~/.cache")).expanduser() / "wallpick"
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    return cache / "actions.lock"


@contextmanager
def action_lock():
    path = action_lock_path()
    fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ActionError("Another wallpaper action is already running") from error
        yield
    finally:
        os.close(fd)


def daemon_ready(awww: str) -> bool:
    result = run_process([awww, "query"], 3)
    return result.returncode == 0


def ensure_daemon(awww: str) -> None:
    if daemon_ready(awww):
        return
    daemon = require_command("awww-daemon")
    try:
        subprocess.Popen(
            [daemon],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as error:
        raise ActionError(f"Could not start awww-daemon: {error}") from error
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        time.sleep(0.15)
        if daemon_ready(awww):
            return
    raise ActionError("awww-daemon did not become ready")


def copy_current_marker(source: Path, extension: str) -> Path:
    directory = backend.pictures_dir() / ".current-wallpaper"
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / f"wallpaper.{extension}"
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".wallpick-", suffix=".tmp", dir=directory, delete=False) as output:
            temporary = Path(output.name)
            with source.open("rb") as image:
                shutil.copyfileobj(image, output, 1024 * 1024)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, target)
        temporary = None
        # Remove only the alternate names maintained by this application.
        for name in MANAGED_MARKERS:
            other = directory / name
            if other != target:
                other.unlink(missing_ok=True)
        return target
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def pywal_enabled() -> bool:
    setting = os.environ.get("WALLPICK_PYWAL", "auto")
    if setting in ("0", "1"):
        return setting == "1"
    # Follow an existing pywal setup, as the original wallset did, without
    # introducing pywal on desktops that do not already use it.
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return (cache / "wal" / "colors.json").is_file()


def optional_pywal(path: Path) -> None:
    if not pywal_enabled():
        return
    command = shutil.which("wal")
    if not command:
        print("wallpick: pywal was requested but 'wal' is unavailable", file=sys.stderr)
        return
    try:
        result = run_process([command, "-ni", str(path)], 30)
        if result.returncode:
            print("wallpick: pywal could not update the palette", file=sys.stderr)
            return
    except ActionError as error:
        print(f"wallpick: {error}", file=sys.stderr)
        return
    reload_waybar()


def reload_waybar() -> None:
    # Waybar reads the pywal CSS only when it starts. Restart it as wallset did,
    # but only when it runs as an active systemd user service.
    command = shutil.which("systemctl")
    if not command:
        return
    try:
        if run_process([command, "--user", "is-active", "--quiet", "waybar.service"], 5).returncode:
            return
        run_process([command, "--user", "--no-block", "restart", "waybar.service"], 5)
    except ActionError as error:
        print(f"wallpick: {error}", file=sys.stderr)


def apply(path: Path, *, minimum: tuple[int, int] | None = None) -> dict:
    path = path.expanduser().resolve(strict=True)
    extension, dimensions = validate_image(path, minimum=minimum)
    awww = require_command("awww")
    ensure_daemon(awww)
    result = run_process(
        [awww, "img", str(path), "--transition-type", "grow", "--transition-step", "30", "--transition-fps", "60"],
        25,
    )
    if result.returncode:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise ActionError(f"awww could not apply the wallpaper{': ' + detail if detail else ''}")
    marker = copy_current_marker(path, extension)
    optional_pywal(path)
    return {"path": str(path), "current": str(marker), "width": dimensions[0], "height": dimensions[1]}


def current_marker() -> Path:
    directory = backend.pictures_dir() / ".current-wallpaper"
    candidates = []
    for name in MANAGED_MARKERS:
        path = directory / name
        if path.is_file():
            candidates.append(path)
    if not candidates:
        raise ActionError("No current wallpaper is recorded")
    return max(candidates, key=lambda path: path.stat().st_mtime_ns)


def favorite_current() -> dict:
    source = current_marker()
    extension, _ = validate_image(source)
    directory = backend.pictures_dir() / backend.FOLDERS["favorites"]
    directory.mkdir(parents=True, exist_ok=True)
    stamp = int(time.time())
    for index in range(1000):
        suffix = f"_{index}" if index else ""
        destination = directory / f"favorite_{stamp}{suffix}.{extension}"
        try:
            with destination.open("xb") as output, source.open("rb") as image:
                shutil.copyfileobj(image, output, 1024 * 1024)
            return {"path": str(destination), "name": destination.name}
        except FileExistsError:
            continue
        except OSError:
            destination.unlink(missing_ok=True)
            raise
    raise ActionError("Could not create a unique favorite filename")


def https_url(url: str, allowed_host: str) -> str:
    if not isinstance(url, str):
        raise ActionError("Wallpaper service returned no image URL")
    try:
        parsed = urlsplit(url)
        host = (parsed.hostname or "").lower()
        port = parsed.port
    except ValueError as error:
        raise ActionError("Wallpaper service returned an invalid image URL") from error
    if parsed.scheme != "https" or parsed.username or parsed.password or port not in (None, 443):
        raise ActionError("Remote image URL must use HTTPS")
    if host != allowed_host and not host.endswith("." + allowed_host):
        raise ActionError("Remote image URL uses an unexpected host")
    return url


def curl_base() -> list[str]:
    return [
        require_command("curl"), "--fail", "--silent", "--show-error", "--location",
        "--proto", "=https", "--proto-redir", "=https", "--max-redirs", "3",
        "--connect-timeout", "8",
    ]


def fetch_json(url: str) -> object:
    result = run_process(curl_base() + ["--max-time", "25", "--max-filesize", "5242880", url], 30)
    if result.returncode:
        raise ActionError("Wallpaper search failed; check the network or query")
    try:
        return json.loads(result.stdout)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ActionError("Wallpaper service returned invalid data") from error


def resolve_konachan_tag(site: str, word: str) -> str:
    if any(symbol in word for symbol in ":*<>="):
        return word
    base = f"https://{site}/tag.json?limit=100&order=count&name="
    for pattern in (word, "*" + "*".join(word) + "*"):
        data = fetch_json(base + quote(pattern, safe=""))
        if not isinstance(data, list):
            raise ActionError("Konachan tag search returned invalid data")
        matches = [entry for entry in data if isinstance(entry, dict)
                   and isinstance(entry.get("name"), str) and isinstance(entry.get("count"), int)
                   and entry["count"] > 0]
        if matches:
            best = max(matches, key=lambda entry: entry["count"] * (5 if entry["name"] == word else 1))
            return best["name"]
    return word


def konachan_query(site: str, rating: str, words: list[str], minimum: tuple[int, int]) -> str:
    encoded = []
    for raw in words:
        normalized = raw.replace(" ", "_")
        negative = normalized.startswith("-")
        word = normalized[1:] if negative else normalized
        if not word:
            raise ActionError("A negative tag needs a name")
        resolved = resolve_konachan_tag(site, word)
        encoded.append(("-" if negative else "") + quote(resolved, safe=""))
    tags = "order:random+rating:" + rating
    if rating == "questionable":
        tags += "+-loli+-child"
    for tag in encoded:
        tags += "+" + tag
    tags += f"+width%3A%3E%3D{minimum[0]}+height%3A%3E%3D{minimum[1]}"
    return f"https://{site}/post.json?tags={tags}&limit=1"


def wallhaven_query(words: list[str], minimum: tuple[int, int]) -> str:
    query = quote(" ".join(words), safe="")
    return (
        f"https://wallhaven.cc/api/v1/search?q={query}&categories=100&purity=100"
        f"&sorting=random&atleast={minimum[0]}x{minimum[1]}&ratios=16x9,16x10"
    )


def image_url(command: str, words: list[str], minimum: tuple[int, int]) -> tuple[str, str]:
    if command == "randomwall":
        data = fetch_json(wallhaven_query(words, minimum))
        try:
            url = data["data"][0]["path"]
        except (TypeError, KeyError, IndexError) as error:
            raise ActionError("No Wallhaven wallpaper matched the query") from error
        return https_url(url, "wallhaven.cc"), "general"
    site, rating, source = (
        ("konachan.net", "safe", "anime") if command == "randomanime"
        else ("konachan.com", "questionable", "gooner")
    )
    data = fetch_json(konachan_query(site, rating, words, minimum))
    try:
        url = data[0]["file_url"]
    except (TypeError, KeyError, IndexError) as error:
        raise ActionError("No Konachan wallpaper matched the tags") from error
    return https_url(url, site), source


def download_image(url: str, source: str, minimum: tuple[int, int]) -> Path:
    directory = backend.pictures_dir() / backend.FOLDERS[source]
    directory.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".wallpick-", suffix=".part", dir=directory, delete=False) as output:
            temporary = Path(output.name)
        result = run_process(
            curl_base() + ["--max-time", "90", "--max-filesize", str(MAX_IMAGE_BYTES),
                           "--output", str(temporary), url],
            95,
        )
        if result.returncode:
            raise ActionError("Wallpaper download failed")
        extension, _ = validate_image(temporary, minimum=minimum)
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        destination = directory / f"wallpaper_{timestamp}_{secrets.token_hex(8)}.{extension}"
        os.replace(temporary, destination)
        temporary = None
        return destination
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def random_wallpaper(command: str, words: list[str]) -> dict:
    minimum = min_dimensions()
    url, source = image_url(command, words, minimum)
    path = download_image(url, source, minimum)
    applied = apply(path)
    return {**applied, "source": source}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Wallpick standalone wallpaper actions")
    parser.add_argument("command", choices=["apply", "favorite-current", "randomanime", "randomwall", "randomgooner"])
    parser.add_argument("arguments", nargs="*")
    args = parser.parse_args(argv)
    try:
        with action_lock():
            if args.command == "apply":
                if len(args.arguments) != 1:
                    raise ActionError("Apply requires one image path")
                result = apply(Path(args.arguments[0]))
            elif args.command == "favorite-current":
                if args.arguments:
                    raise ActionError("Favorite current takes no arguments")
                result = favorite_current()
            else:
                result = random_wallpaper(args.command, args.arguments)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (ActionError, OSError, ValueError) as error:
        print(f"wallpick: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
