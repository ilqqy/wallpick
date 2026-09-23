"""Live package smoke test with a clean HOME, empty PATH, and temporary pictures.

Run after nix build, from nix develop. Opens a fixture popup; never applies an image.
Stop other Wallpick instances first so this check does not reuse a personal profile.
"""
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib

project = Path(__file__).resolve().parents[1]
package = (project / "result").resolve()
binary = str(package / "bin/wallpick")
qs, bash = shutil.which("qs"), shutil.which("bash")
assert qs and bash and os.environ.get("WAYLAND_DISPLAY"), "Run in nix develop inside a Wayland session"
instances = json.loads(subprocess.check_output([qs, "list", "--all", "--json"], text=True))
assert not any(i["shell_id"] == "wallpick" for i in instances), "Stop Wallpick before the package test"

with tempfile.TemporaryDirectory(prefix="wallpick-package-") as directory:
    root = Path(directory)
    env = {k: v for k, v in os.environ.items() if k in [
        "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "HYPRLAND_INSTANCE_SIGNATURE"]}
    env.update(HOME=directory, PATH="", XDG_CONFIG_HOME=str(root / "config"),
               XDG_CACHE_HOME=str(root / "cache"), WALLPICK_PICTURES_DIR=str(root / "Pictures"))
    marker = root / "Pictures/.current-wallpaper/wallpaper.png"
    marker.parent.mkdir(parents=True)

    def chunk(kind, data):
        return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))

    marker.write_bytes(b"\x89PNG\r\n\x1a\n" +
        chunk(b"IHDR", struct.pack("!2I5B", 1, 1, 8, 2, 0, 0, 0)) +
        chunk(b"IDAT", zlib.compress(b"\0\x20\x30\x40")) + chunk(b"IEND", b""))
    saved = json.loads(subprocess.check_output([binary, "favorite"], env=env, text=True))
    assert Path(saved["path"]).read_bytes() == marker.read_bytes()
    assert subprocess.run([binary, "apply", str(root / "missing.png")], env=env,
                          capture_output=True).returncode == 1
    print("PASS: packaged backend with empty PATH and clean HOME")
    try:
        subprocess.run([binary, "open"], env=env, check=True)
        time.sleep(0.9)
        assert subprocess.check_output([binary, "status"], env=env, text=True).strip() == "open"
        copy = root / "alternate-package-path"
        shutil.copytree(package / "share/wallpick", copy)
        second_env = dict(env, WALLPICK_APP_DIR=str(copy), WALLPICK_PACKAGED="1",
                          WALLPICK_QS=qs, WALLPICK_PYTHON=sys.executable)
        subprocess.run([bash, str(copy / "scripts/run.sh"), "open"], env=second_env, check=True)
        instances = json.loads(subprocess.check_output([qs, "list", "--all", "--json"], env=env, text=True))
        ours = [i for i in instances if i["shell_id"] == "wallpick"]
        assert len(ours) == 1, ours
        log = subprocess.check_output([qs, "log", "-i", ours[0]["id"], "-t", "100"], env=env, text=True)
        assert "ERROR" not in log and "WARN" not in log, log
        print("PASS: clean-profile UI, optional hyprctl fallback, cross-path singleton, clean QML log")
    finally:
        subprocess.run([binary, "stop"], env=env, check=False)
