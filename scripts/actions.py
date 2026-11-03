#!/usr/bin/env python3
"""Standalone wallpaper actions using the existing Pictures directory layout.

This module never evaluates a shell command. The GUI starts it as a subprocess so
network, image validation, and wallpaper changes cannot block the QML thread.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import fcntl
from functools import lru_cache
from itertools import chain, zip_longest
import json
import os
import re
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
SEARCH_LIMIT = 24
DANBOORU = "danbooru.donmai.us"
# Image boards a search can draw from. "files" is the host family that serves
# their images; "prefix" names saved results, so a result that was already
# downloaded is reused and the UI can recognise it in the local catalog.
# "landscape" drops portrait art, which most boards other than Konachan are
# full of and which makes a poor desktop wallpaper.
BOORUS = {
    "konachan.net": {"kind": "moebooru", "label": "Konachan", "prefix": "konachan", "files": "konachan.net"},
    "konachan.com": {"kind": "moebooru", "label": "Konachan", "prefix": "konachan", "files": "konachan.com"},
    "yande.re": {"kind": "moebooru", "label": "yande.re", "prefix": "yandere", "files": "yande.re",
                 "landscape": True},
    DANBOORU: {"kind": "danbooru", "label": "Danbooru", "prefix": "danbooru", "files": "donmai.us",
               "landscape": True},
}
# The boards each searchable source lists, with that board's rating filter.
SEARCH_BOORUS = {
    "anime": (("konachan.net", "safe"), ("yande.re", "safe"), (DANBOORU, "g")),
    "gooner": (("konachan.com", "questionable"),),
}
SEARCH_SOURCES = ("anime", "general", "gooner")
LANDSCAPE_RATIO = 1.3
# Consecutive words are tried as one tag first ("jujutsu kaisen"), up to this many.
MAX_PHRASE_WORDS = 3
# order:score uses one of the two tags an anonymous search may have.
DANBOORU_FREE_TAGS = 1


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


@lru_cache(maxsize=None)
def tag_lookup(site: str, pattern: str) -> tuple[tuple[str, int, bool], ...]:
    """Tags on the board matching the pattern as (name, post count, is an
    artist), most used first."""
    danbooru = BOORUS[site]["kind"] == "danbooru"
    if danbooru:
        # Brackets are percent-encoded so curl does not treat them as a glob.
        url = (f"https://{site}/tags.json?limit=100&only=name,post_count,category&search%5Border%5D=count"
               f"&search%5Bname_or_alias_matches%5D={quote(pattern, safe='')}")
    else:
        url = f"https://{site}/tag.json?limit=100&order=count&name={quote(pattern, safe='')}"
    data = fetch_json(url)
    if not isinstance(data, list):
        raise ActionError(f"{BOORUS[site]['label']} tag search returned invalid data")
    count, kind = ("post_count", "category") if danbooru else ("count", "type")
    return tuple((entry["name"], entry[count], entry.get(kind) == 1) for entry in data
                 if isinstance(entry, dict) and isinstance(entry.get("name"), str)
                 and isinstance(entry.get(count), int) and entry[count] > 0)


def contains_pattern(site: str, text: str) -> str:
    # Moebooru matches a plain name anywhere in a tag; Danbooru needs wildcards.
    return f"*{text}*" if BOORUS[site]["kind"] == "danbooru" else text


def word_shape(words: list[str]) -> re.Pattern:
    # Each word must begin one of the tag's consecutive parts, so "emilia" is
    # not "remilia_scarlet" and "dark forest" is not "dark_elven_forest_ranger".
    return re.compile(r"(?:^|_|\()" + "_".join(re.escape(word) + "[^_]*" for word in words))


def best_tag(matches, exact: str, shape: re.Pattern | None) -> tuple[str, int] | None:
    # Artist names are only taken when typed exactly: a search for "kaisen"
    # means Jujutsu Kaisen, not the artist kaisen_chuui.
    usable = [(name, count) for name, count, artist in matches
              if name == exact or (not artist and (shape is None or shape.search(name)))]
    if not usable:
        return None
    return max(usable, key=lambda match: match[1] * (5 if match[0] == exact else 1))


def resolve_tag(site: str, word: str) -> tuple[str, int] | None:
    """The board's tag for one typed word, or None when nothing fits."""
    found = best_tag(tag_lookup(site, contains_pattern(site, word)), word, word_shape([word]))
    if not found and BOORUS[site]["kind"] == "moebooru":
        # A letter-by-letter wildcard forgives typos ("rezero"). On Danbooru it
        # matches almost any popular tag, so Danbooru borrows Konachan's
        # answer instead.
        found = best_tag(tag_lookup(site, "*" + "*".join(word) + "*"), word, None)
    return found


def resolve_phrase(site: str, words: list[str]) -> tuple[str, int] | None:
    """One tag spelled by consecutive words, such as "jujutsu kaisen" or "gojo satoru"."""
    joined = "_".join(words)
    shape = word_shape(words)
    for pattern in (contains_pattern(site, joined), "*" + "*".join(words) + "*"):
        found = best_tag(tag_lookup(site, pattern), joined, shape)
        if found:
            return found
    return None


def plain_word(word: str) -> bool:
    return not any(symbol in word for symbol in ":*<>=")


def resolve_counted(site: str, words: list[str]) -> list[tuple[str, int | None]]:
    """Typed words as the board's tags with their post counts (None if
    unknown); negative tags keep their "-"."""
    items = []
    for raw in words:
        normalized = raw.replace(" ", "_")
        negative = normalized.startswith("-")
        word = normalized[1:] if negative else normalized
        if not word:
            raise ActionError("A negative tag needs a name")
        items.append((negative, word))
    # Danbooru has no forgiving fallback of its own; Konachan shares most of
    # its tag names and Danbooru resolves the remaining ones as aliases.
    fallback = "konachan.net" if BOORUS[site]["kind"] == "danbooru" else None
    tags = []
    index = 0
    while index < len(items):
        negative, word = items[index]
        # Typing a multi-word tag is far more common than meaning each word
        # separately, so the longest phrase that names a real tag wins.
        end = index
        while (end < len(items) and end - index < MAX_PHRASE_WORDS
               and not items[end][0] and plain_word(items[end][1])):
            end += 1
        while end - index >= 2:
            parts = [word for _, word in items[index:end]]
            found = resolve_phrase(site, parts) or (fallback and resolve_phrase(fallback, parts))
            if found:
                tags.append(found)
                break
            end -= 1
        if end - index >= 2:
            index = end
            continue
        found = None
        if plain_word(word):
            found = resolve_tag(site, word) or (fallback and resolve_tag(fallback, word))
        name, count = found or (word, None)
        tags.append((("-" if negative else "") + name, count))
        index += 1
    unique = {}
    for name, count in tags:
        unique.setdefault(name, count)
    return list(unique.items())


def resolve_tags(site: str, words: list[str]) -> list[str]:
    """Map typed words to the board's tag names; negative tags keep their "-"."""
    return [name for name, _ in resolve_counted(site, words)]


def konachan_query(site: str, rating: str, words: list[str], minimum: tuple[int, int],
                   *, order: str = "random", limit: int = 1, page: int = 1) -> str:
    """A Moebooru post search (Konachan, yande.re)."""
    tags = f"order:{order}+rating:" + rating
    if rating == "questionable":
        tags += "+-loli+-child"
    for tag in resolve_tags(site, words):
        tags += "+" + quote(tag, safe="")
    tags += f"+width%3A%3E%3D{minimum[0]}+height%3A%3E%3D{minimum[1]}"
    return f"https://{site}/post.json?tags={tags}&limit={limit}" + (f"&page={page}" if page > 1 else "")


DANBOORU_FIELDS = "id,image_width,image_height,file_ext,file_url,large_file_url,preview_file_url,tag_string,media_asset"


def danbooru_query(rating: str, words: list[str], minimum: tuple[int, int],
                   *, limit: int, page: int = 1) -> tuple[str, list[str]]:
    """The post search URL and the tags left for the caller to filter by.

    Anonymous Danbooru searches allow two tags besides rating and size
    metatags, and order:score takes one of them. The rarest tag is sent so the
    best-rated page is as relevant as possible; each post's tag list is
    checked for the rest.
    """
    resolved = resolve_counted(DANBOORU, words)
    positive = sorted((tag for tag in resolved if not tag[0].startswith("-")),
                      key=lambda tag: float("inf") if tag[1] is None else tag[1])
    negative = [tag for tag in resolved if tag[0].startswith("-")]
    sent = [name for name, _ in (positive + negative)[:DANBOORU_FREE_TAGS]]
    rest = [name for name, _ in resolved if name not in sent]
    # Sorting the whole board by score times out without a tag to narrow it;
    # "rank" lists recent popular posts instead.
    order = "order:score" if positive else "order:rank"
    tags = [order, f"rating:{rating}", f"width:>={minimum[0]}", f"height:>={minimum[1]}",
            f"ratio:>={LANDSCAPE_RATIO}"] + sent
    url = (f"https://{DANBOORU}/posts.json?tags={'+'.join(quote(tag, safe='') for tag in tags)}"
           f"&limit={limit}&only={DANBOORU_FIELDS}" + (f"&page={page}" if page > 1 else ""))
    return url, rest


def wallhaven_query(words: list[str], minimum: tuple[int, int],
                    *, sorting: str = "random", page: int = 1) -> str:
    query = quote(" ".join(words), safe="")
    return (
        f"https://wallhaven.cc/api/v1/search?q={query}&categories=100&purity=100"
        f"&sorting={sorting}&atleast={minimum[0]}x{minimum[1]}&ratios=16x9,16x10"
        + (f"&page={page}" if page > 1 else "")
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


def download_image(url: str, source: str, minimum: tuple[int, int], stem: str | None = None) -> Path:
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
        if not stem:
            stem = f"wallpaper_{time.strftime('%Y%m%d_%H%M%S')}_{secrets.token_hex(8)}"
        destination = directory / f"{stem}.{extension}"
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


def search_source(raw: str) -> str:
    if raw not in SEARCH_SOURCES:
        raise ActionError(f"Unknown search source: {raw}")
    return raw


def result_id(raw: object) -> str:
    value = str(raw)
    # The identifier becomes part of a filename, so only plain IDs are allowed.
    if not value.isascii() or not value.isalnum() or len(value) > 32:
        raise ActionError("Wallpaper service returned an invalid wallpaper ID")
    return value


def booru_result(site: str, source: str, raw_id: object, *, thumb: object, preview: object,
                 full: object, width: object, height: object, extension: object = None) -> dict:
    board = BOORUS[site]
    identifier = result_id(raw_id)
    if extension is not None and str(extension).lower() not in ("jpg", "jpeg", "png"):
        raise ActionError("Only PNG and JPEG wallpapers are supported")
    if not isinstance(width, int) or not isinstance(height, int) or height <= 0:
        raise ActionError(f"{board['label']} post has no dimensions")
    if board.get("landscape") and width < height * LANDSCAPE_RATIO:
        raise ActionError(f"{board['label']} post is not a landscape image")
    files = board["files"]
    stem = f"{board['prefix']}_{identifier}"
    return {
        "id": identifier,
        "key": f"{source}:{stem}",
        "stem": stem,
        "source": source,
        "name": f"{board['label']} #{identifier}",
        "url": https_url(thumb, files),
        "preview": https_url(preview or full, files),
        "full": https_url(full, files),
        "width": width,
        "height": height,
    }


def konachan_result(post: object, source: str, site: str) -> dict:
    """A Moebooru post (Konachan, yande.re)."""
    if not isinstance(post, dict):
        raise ActionError(f"{BOORUS[site]['label']} returned an invalid post")
    # The 300 px preview suits gallery cards; the 1500 px sample the hero.
    return booru_result(site, source, post.get("id"), thumb=post.get("preview_url"),
                        preview=post.get("sample_url"), full=post.get("file_url"),
                        width=post.get("width"), height=post.get("height"), extension=post.get("file_ext"))


def danbooru_result(post: object, source: str) -> dict:
    if not isinstance(post, dict):
        raise ActionError("Danbooru returned an invalid post")
    # The 360 px JPEG variant is the closest match to the other boards' card
    # previews; 720 px is WebP, which Qt may not decode.
    thumb = post.get("preview_file_url")
    asset = post.get("media_asset")
    variants = asset.get("variants") if isinstance(asset, dict) else None
    for variant in variants if isinstance(variants, list) else []:
        if (isinstance(variant, dict) and variant.get("type") == "360x360"
                and variant.get("file_ext") in ("jpg", "png")):
            thumb = variant.get("url")
    return booru_result(DANBOORU, source, post.get("id"), thumb=thumb, preview=post.get("large_file_url"),
                        full=post.get("file_url"), width=post.get("image_width"),
                        height=post.get("image_height"), extension=post.get("file_ext"))


def has_tags(post: object, tags: list[str]) -> bool:
    present = set(post.get("tag_string", "").split()) if isinstance(post, dict) else set()
    return all((tag[1:] not in present) if tag.startswith("-") else (tag in present) for tag in tags)


def convert_posts(posts: list, convert) -> list[dict]:
    results = []
    for post in posts:
        try:
            results.append(convert(post))
        except ActionError:
            # One unusable post must not hide the rest of the page.
            continue
    return results


def booru_page(site: str, rating: str, source: str, words: list[str],
               minimum: tuple[int, int], page: int) -> tuple[list[dict], bool]:
    label = BOORUS[site]["label"]
    try:
        if BOORUS[site]["kind"] == "danbooru":
            url, rest = danbooru_query(rating, words, minimum, limit=SEARCH_LIMIT, page=page)
            convert = lambda post: danbooru_result(post, source)  # noqa: E731
        else:
            url, rest = konachan_query(site, rating, words, minimum, order="score",
                                       limit=SEARCH_LIMIT, page=page), []
            convert = lambda post: konachan_result(post, source, site)  # noqa: E731
        posts = fetch_json(url)
    except ActionError as error:
        raise ActionError(f"{label}: {error}") from error
    if not isinstance(posts, list):
        raise ActionError(f"{label} search returned invalid data")
    more = len(posts) >= SEARCH_LIMIT
    return convert_posts([post for post in posts if has_tags(post, rest)], convert), more


def wallhaven_result(post: object) -> dict:
    if not isinstance(post, dict) or not isinstance(post.get("thumbs"), dict):
        raise ActionError("Wallhaven returned an invalid wallpaper")
    if post.get("file_type") not in ("image/png", "image/jpeg"):
        raise ActionError("Only PNG and JPEG wallpapers are supported")
    identifier = result_id(post.get("id"))
    full = https_url(post.get("path"), "wallhaven.cc")
    width, height = post.get("dimension_x"), post.get("dimension_y")
    if not isinstance(width, int) or not isinstance(height, int):
        raise ActionError("Wallhaven wallpaper has no dimensions")
    return {
        "id": identifier,
        "key": f"general:{identifier}",
        "stem": f"wallhaven_{identifier}",
        "source": "general",
        "name": f"Wallhaven {identifier}",
        "url": https_url(post["thumbs"].get("large") or post["thumbs"].get("small"), "wallhaven.cc"),
        # Wallhaven has no mid-size rendition; the hero shows the original.
        "preview": full,
        "full": full,
        "width": width,
        "height": height,
    }


def search(source: str, words: list[str], page: int = 1) -> dict:
    """List matching wallpapers without downloading or applying any of them."""
    source = search_source(source)
    if not 1 <= page <= 1000:
        raise ActionError("Search page is out of range")
    minimum = min_dimensions()
    if source == "general":
        # Relevance needs a query; an empty search shows the most popular.
        data = fetch_json(wallhaven_query(words, minimum, sorting="relevance" if words else "toplist", page=page))
        posts = data.get("data") if isinstance(data, dict) else None
        if not isinstance(posts, list):
            raise ActionError("Wallhaven search returned invalid data")
        meta = data.get("meta") if isinstance(data.get("meta"), dict) else {}
        last = meta.get("last_page")
        more = isinstance(last, int) and page < last
        return {"source": source, "page": page, "more": more, "results": convert_posts(posts, wallhaven_result)}
    boards = SEARCH_BOORUS[source]
    # The boards are queried side by side; one that is down or rejects the
    # query only loses its own share of the results.
    with ThreadPoolExecutor(max_workers=len(boards)) as pool:
        futures = [pool.submit(booru_page, site, rating, source, words, minimum, page) for site, rating in boards]
    pages, errors = [], []
    for future in futures:
        try:
            pages.append(future.result())
        except ActionError as error:
            errors.append(error)
            print(f"wallpick: {error}", file=sys.stderr)
    if not pages:
        raise errors[0]
    # Alternate between boards so each one's best-rated posts lead the list.
    mixed = [result for result in chain.from_iterable(zip_longest(*(results for results, _ in pages)))
             if result is not None]
    return {"source": source, "page": page, "more": any(more for _, more in pages), "results": mixed}


def result_board(source: str, url: str) -> tuple[str, str]:
    """The saved-name prefix and image host family for a result's image URL."""
    if source == "general":
        return "wallhaven", "wallhaven.cc"
    try:
        host = (urlsplit(url).hostname or "").lower() if isinstance(url, str) else ""
    except ValueError:
        host = ""
    for site, _ in SEARCH_BOORUS[source]:
        files = BOORUS[site]["files"]
        if host == files or host.endswith("." + files):
            return BOORUS[site]["prefix"], files
    raise ActionError("Remote image URL uses an unexpected host")


def download_result(source: str, identifier: str, url: str) -> Path:
    source = search_source(source)
    identifier = result_id(identifier)
    prefix, files = result_board(source, url)
    url = https_url(url, files)
    stem = f"{prefix}_{identifier}"
    directory = backend.pictures_dir() / backend.FOLDERS[source]
    for extension in ("png", "jpg"):
        existing = directory / f"{stem}.{extension}"
        if existing.is_file():
            try:
                validate_image(existing)
                return existing
            except ActionError:
                existing.unlink(missing_ok=True)
    return download_image(url, source, min_dimensions(), stem)


def apply_result(source: str, identifier: str, url: str) -> dict:
    path = download_result(source, identifier, url)
    return {**apply(path), "source": source}


def favorite_result(source: str, identifier: str, url: str) -> dict:
    path = download_result(source, identifier, url)
    return backend.favorite_selected(str(path))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Wallpick standalone wallpaper actions")
    parser.add_argument("command", choices=["apply", "favorite-current", "randomanime", "randomwall", "randomgooner",
                                            "search", "apply-result", "favorite-result"])
    parser.add_argument("arguments", nargs="*")
    args = parser.parse_args(argv)
    try:
        if args.command == "search":
            # Read-only, so it neither takes nor waits for the action lock.
            if len(args.arguments) < 2 or not args.arguments[1].isdigit():
                raise ActionError("Search requires a source, a page number and optional tags")
            print(json.dumps(search(args.arguments[0], args.arguments[2:], int(args.arguments[1])), ensure_ascii=False))
            return 0
        with action_lock():
            if args.command == "apply":
                if len(args.arguments) != 1:
                    raise ActionError("Apply requires one image path")
                result = apply(Path(args.arguments[0]))
            elif args.command == "favorite-current":
                if args.arguments:
                    raise ActionError("Favorite current takes no arguments")
                result = favorite_current()
            elif args.command in ("apply-result", "favorite-result"):
                if len(args.arguments) != 3:
                    raise ActionError("A search result needs a source, an ID and an image URL")
                action = apply_result if args.command == "apply-result" else favorite_result
                result = action(*args.arguments)
            else:
                result = random_wallpaper(args.command, args.arguments)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (ActionError, OSError, ValueError) as error:
        print(f"wallpick: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
