#!/usr/bin/env python3
"""Regression checks with isolated folders and a fake action backend.

Run inside nix develop: python3 tests/check.py
No live wallpaper commands or user folders are changed.
"""
import json
import struct
import zlib
import importlib.util
from unittest.mock import patch
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import time

PROJECT = Path(__file__).resolve().parent.parent
BACKEND = PROJECT / "scripts/backend.py"


def wait_for(read, predicate, seconds=10):
    deadline = time.monotonic() + seconds
    last = None
    while time.monotonic() < deadline:
        try:
            last = read()
            if predicate(last):
                return last
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            pass
        time.sleep(0.1)
    raise AssertionError(f"Timed out; last state: {last}")


with tempfile.TemporaryDirectory(prefix="wallpick-test-") as directory:
    root = Path(directory)
    pictures = root / "pictures"
    pictures.mkdir()
    env = dict(os.environ, WALLPICK_PICTURES_DIR=str(pictures))

    def scan():
        return json.loads(subprocess.check_output([sys.executable, str(BACKEND), "scan"], env=env))

    assert not scan()["current"]
    assert all(not source["items"] for source in scan()["sources"].values())
    anime = pictures / "random_konachan"
    anime.mkdir()
    image = anime / "test image;literal.jpg"
    image.write_bytes(b"fixture-one")
    marker = pictures / ".current-wallpaper"
    marker.mkdir()
    current = marker / "wallpaper.jpg"
    current.write_bytes(image.read_bytes())
    before = scan()
    assert before["appliedPath"] == str(image)
    old_url = before["current"]["url"]
    os.utime(current, ns=(current.stat().st_atime_ns, current.stat().st_mtime_ns + 1_000_000))
    assert scan()["current"]["url"] != old_url

    gooner = pictures / "random_gooner"
    gooner.mkdir()
    (gooner / "separate.jpg").write_bytes(b"separate")
    current.write_bytes(b"separate")
    data = scan()
    assert data["appliedPath"] == str(gooner / "separate.jpg")
    assert all(item["source"] != "gooner" for item in data["sources"]["recent"]["items"])
    current.write_bytes(image.read_bytes())

    favorite = json.loads(subprocess.check_output(
        [sys.executable, str(BACKEND), "favorite-selected", str(image)], env=env))
    assert Path(favorite["path"]).read_bytes() == image.read_bytes()
    outside = root / "outside.jpg"
    outside.write_bytes(b"outside")
    assert subprocess.run([sys.executable, str(BACKEND), "favorite-selected", str(outside)],
                          env=env, capture_output=True).returncode != 0
    print("PASS: empty folders, current matching, image cache revision, separate source, favorite boundaries")
    module_spec = importlib.util.spec_from_file_location("wallpick_backend", BACKEND)
    backend = importlib.util.module_from_spec(module_spec)
    sys.dont_write_bytecode = True
    module_spec.loader.exec_module(backend)
    original_images = backend.images
    original_digest = backend.digest
    def interrupted_digest(path):
        if path == current:
            raise FileNotFoundError("marker replaced during scan")
        return original_digest(path)
    def disappearing_images(folder):
        return original_images(folder) + ([anime / "vanished.jpg"] if folder == anime else [])
    with patch.dict(os.environ, WALLPICK_PICTURES_DIR=str(pictures)), \
         patch.object(backend, "digest", interrupted_digest), \
         patch.object(backend, "images", disappearing_images):
        interrupted = backend.scan()
        assert not interrupted["current"]
        assert len(interrupted["sources"]["anime"]["items"]) == 1
    print("PASS: replaced current marker and disappearing gallery files preserve catalog")

    stub = root / "actions-stub.py"
    stub.write_text(f"#!{sys.executable}\n" + '''import json, os, pathlib, sys
root = pathlib.Path(os.environ['WALLPICK_TEST_ROOT'])
(root / 'argv.json').write_text(json.dumps(sys.argv[1:]))
marker = root / 'pictures/.current-wallpaper/wallpaper.jpg'
if (root / 'mode').read_text() == 'fail':
    marker.unlink(missing_ok=True)
    print('simulated network failure', file=sys.stderr)
    raise SystemExit(1)
image = root / 'pictures/random_konachan/new.jpg'
image.write_bytes(b'new-image')
marker.write_bytes(image.read_bytes())
''')
    stub.chmod(0o700)
    (root / "mode").write_text("fail")
    env.update(WALLPICK_TEST_ROOT=str(root),
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
    runtime = root / "runtime"
    shutil.copytree(PROJECT / "src", runtime / "src")
    shutil.copytree(PROJECT / "scripts", runtime / "scripts")
    shutil.copyfile(stub, runtime / "scripts/actions.py")
    shutil.copyfile(PROJECT / "tests/service.qml", runtime / "src/service-test.qml")
    config = str(runtime / "src/service-test.qml")

    def ipc(function):
        return subprocess.check_output(["qs", "-p", config, "ipc", "call", "wallpick-test", function],
                                       env=env, text=True, stderr=subprocess.DEVNULL)

    def state():
        return json.loads(ipc("state"))

    with (root / "runtime.log").open("w+") as log:
        process = subprocess.Popen(["qs", "-p", config, "--no-duplicate"], env=env,
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_for(state, lambda s: not s["scanning"] and bool(s["catalog"]["current"]))
            assert ipc("sliderRegression").strip() == "PASS"
            print("PASS: carousel large-to-small and empty collection changes")
            ipc("randomAnime")
            failed = wait_for(state, lambda s: not s["busy"] and not s["scanning"] and bool(s["error"]))
            assert failed["uncertain"] and failed["catalog"]["current"]
            time.sleep(0.3)
            assert state()["error"], "Refresh must not erase an action error"
            args = json.loads((root / "argv.json").read_text())
            assert args[-2:] == ["tag;literal", "-chibi"], args
            (root / "mode").write_text("success")
            ipc("randomAnime")
            recovered = wait_for(state, lambda s: not s["busy"] and not s["scanning"]
                                 and s["catalog"]["appliedPath"].endswith("new.jpg"))
            assert not recovered["error"] and not recovered["uncertain"]
            print("PASS: asynchronous failure, persistent error, last-known current, literal argv, recovery")
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read(), file=sys.stderr)
            raise
        finally:
            process.terminate()
            process.wait(timeout=5)

    # Exercise the actual popup's asynchronous Image state, with no live backend.
    # PanelWindow requires a Wayland backend even when testing with software rendering.
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: popup image regression requires a Wayland session")
        sys.exit(0)
    env["QT_QPA_PLATFORM"] = "wayland"
    shutil.copyfile(PROJECT / "tests/preview.qml", runtime / "src/preview-test.qml")
    config = str(runtime / "src/preview-test.qml")
    valid = root / "valid.png"
    def png_chunk(kind, data):
        return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
    valid.write_bytes(b"\x89PNG\r\n\x1a\n" +
        png_chunk(b"IHDR", struct.pack("!2I5B", 1, 1, 8, 2, 0, 0, 0)) +
        png_chunk(b"IDAT", zlib.compress(b"\x00\x80\x90\xa0")) + png_chunk(b"IEND", b""))
    broken = root / "broken.png"
    broken.write_bytes(b"not an image")

    def preview_ipc(function, *args):
        return subprocess.check_output(["qs", "-p", config, "ipc", "call",
            "wallpick-preview-test", function, *args], env=env, text=True, stderr=subprocess.DEVNULL)

    def preview_state():
        return json.loads(preview_ipc("state"))

    with (root / "preview.log").open("w+") as log:
        process = subprocess.Popen(["qs", "-p", config, "--no-duplicate"], env=env,
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_for(preview_state, lambda s: True)
            valid_url = valid.as_uri() + "?v=1"
            preview_ipc("select", valid_url)
            wait_for(preview_state, lambda s: s["displayed"] == valid_url)
            preview_ipc("select", broken.as_uri())
            wait_for(preview_state, lambda s: bool(s["error"]))
            preview_ipc("apply")
            assert preview_state()["applications"] == 0
            preview_ipc("select", valid_url)
            wait_for(preview_state, lambda s: s["selected"] == valid_url and s["ready"] and not s["error"])
            preview_ipc("apply")
            assert preview_state()["applications"] == 1
            print("PASS: image revision URL, broken preview blocks Apply, preview recovery")
            preview_ipc("localCollection")
            preview_ipc("randomSource", "favorites")
            wait_for(preview_state, lambda s: s["path"] == "two")
            assert preview_state()["applications"] == 1, "Local random must only select"
            for key, command in [("anime", "randomanime"), ("general", "randomwall"), ("gooner", "randomgooner")]:
                preview_ipc("randomSource", key)
                assert preview_state()["command"] == command
            print("PASS: category random selects local images and routes all remote commands")
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read(), file=sys.stderr)
            raise
        finally:
            process.terminate()
            process.wait(timeout=5)
