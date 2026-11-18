"""Isolated action tests: no live network, wallpaper daemon, or desktop writes."""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import lz4.block
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import actions  # noqa: E402
import backend  # noqa: E402
import scenepkg  # noqa: E402


class ActionsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        env = patch.dict(os.environ, {
            "WALLPICK_PICTURES_DIR": str(self.root / "Pictures"),
            "XDG_RUNTIME_DIR": str(self.root),
            "WALLPICK_MIN_WIDTH": "100",
            "WALLPICK_MIN_HEIGHT": "80",
            "WALLPICK_PYWAL": "0",
            "XDG_CACHE_HOME": str(self.root / "cache"),
            # Keep the user's real Steam folders and steamcmd login out of tests.
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "WALLPICK_STEAM_DIR": str(self.root / "steam"),
            "WALLPICK_STEAM_USER": "",
        })
        env.start()
        self.addCleanup(env.stop)
        actions.tag_lookup.cache_clear()
        self.addCleanup(actions.tag_lookup.cache_clear)

    def image(self, path: Path, size=(150, 120), image_format="PNG") -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", size, (25, 38, 51)).save(path, format=image_format)
        return path

    def completed(self, argv, returncode=0, stdout=b"", stderr=b""):
        return subprocess.CompletedProcess(argv, returncode, stdout, stderr)

    def test_pywal_follows_an_existing_palette_unless_overridden(self):
        cache = self.root / "cache"
        with patch.dict(os.environ, {"WALLPICK_PYWAL": "auto", "XDG_CACHE_HOME": str(cache)}):
            self.assertFalse(actions.pywal_enabled())
            (cache / "wal").mkdir(parents=True)
            (cache / "wal" / "colors.json").write_text("{}")
            self.assertTrue(actions.pywal_enabled())
            with patch.dict(os.environ, {"WALLPICK_PYWAL": "0"}):
                self.assertFalse(actions.pywal_enabled())
        with patch.dict(os.environ, {"WALLPICK_PYWAL": "1", "XDG_CACHE_HOME": str(self.root / "empty")}):
            self.assertTrue(actions.pywal_enabled())

    def test_new_palette_restarts_only_an_active_waybar_service(self):
        calls = []
        def process(argv, timeout, active=0, wal=0):
            calls.append(argv)
            code = wal if argv[0] == "wal" else active if "is-active" in argv else 0
            return self.completed(argv, code)
        with patch.dict(os.environ, {"WALLPICK_PYWAL": "1"}), \
             patch.object(actions.shutil, "which", side_effect=lambda name: name):
            with patch.object(actions, "run_process", side_effect=process):
                actions.optional_pywal(Path("wall.png"))
            self.assertEqual(calls[0], ["wal", "-ni", "wall.png"])
            self.assertEqual(calls[-1], ["systemctl", "--user", "--no-block", "restart", "waybar.service"])
            calls.clear()
            with patch.object(actions, "run_process", side_effect=lambda argv, timeout: process(argv, timeout, active=3)):
                actions.optional_pywal(Path("wall.png"))
            self.assertNotIn("restart", calls[-1])
            calls.clear()
            with patch.object(actions, "run_process", side_effect=lambda argv, timeout: process(argv, timeout, wal=1)):
                actions.optional_pywal(Path("wall.png"))
            self.assertEqual(calls, [["wal", "-ni", "wall.png"]])

    def test_apply_reuses_daemon_and_replaces_managed_marker_only_after_success(self):
        source = self.image(self.root / "Pictures" / "random_konachan" / "selected.png")
        current = self.root / "Pictures" / ".current-wallpaper"
        old = self.image(current / "wallpaper.jpg", image_format="JPEG")
        unrelated = self.image(current / "unrelated.png")
        old_contents = old.read_bytes()
        with patch.object(actions, "require_command", side_effect=lambda name: name), \
             patch.object(actions, "daemon_ready", return_value=True), \
             patch.object(actions, "run_process", side_effect=lambda argv, timeout: self.completed(argv)) as process:
            result = actions.apply(source)
        self.assertEqual(result["path"], str(source))
        self.assertEqual((current / "wallpaper.png").read_bytes(), source.read_bytes())
        self.assertFalse(old.exists())
        self.assertTrue(unrelated.exists())
        self.assertNotEqual(old_contents, source.read_bytes())
        arguments = process.call_args.args[0]
        self.assertEqual(arguments[:3], ["awww", "img", str(source)])
        self.assertIn("--transition-type", arguments)
        self.assertIn("grow", arguments)
        self.assertEqual(arguments[-2:], ["--transition-fps", "60"])

    def test_failed_apply_preserves_old_marker(self):
        source = self.image(self.root / "Pictures" / "random_konachan" / "selected.png")
        old = self.image(self.root / "Pictures" / ".current-wallpaper" / "wallpaper.jpg", image_format="JPEG")
        old_contents = old.read_bytes()
        with patch.object(actions, "require_command", return_value="awww"), \
             patch.object(actions, "ensure_daemon"), \
             patch.object(actions, "run_process", side_effect=lambda argv, timeout: self.completed(argv, 1, stderr=b"offline")):
            with self.assertRaisesRegex(actions.ActionError, "offline"):
                actions.apply(source)
        self.assertEqual(old.read_bytes(), old_contents)
        self.assertFalse((old.parent / "wallpaper.png").exists())

    def test_invalid_image_and_minimum_do_not_invoke_awww(self):
        bad = self.root / "invalid.jpg"
        bad.write_bytes(b"not an image")
        small = self.image(self.root / "small.png", size=(10, 10))
        with patch.object(actions, "require_command") as command:
            with self.assertRaises(actions.ActionError):
                actions.apply(bad)
            with self.assertRaises(actions.ActionError):
                actions.apply(small, minimum=(100, 80))
            command.assert_not_called()

    def test_truncated_jpeg_is_rejected_before_wallpaper_change(self):
        jpeg = self.image(self.root / "truncated.jpg", size=(500, 400), image_format="JPEG")
        jpeg.write_bytes(jpeg.read_bytes()[:-80])
        with patch.object(actions, "require_command") as command:
            with self.assertRaises(actions.ActionError):
                actions.apply(jpeg)
            command.assert_not_called()

    def test_favorite_current_copies_marker_and_is_newest(self):
        marker = self.image(self.root / "Pictures" / ".current-wallpaper" / "wallpaper.png")
        older = self.image(self.root / "Pictures" / "favorite" / "older.png")
        os.utime(older, (1, 1))
        first = actions.favorite_current()
        second = actions.favorite_current()
        self.assertNotEqual(first["path"], second["path"])
        self.assertEqual(Path(first["path"]).read_bytes(), marker.read_bytes())
        self.assertGreater(Path(first["path"]).stat().st_mtime, older.stat().st_mtime)

    def test_favorite_current_rejects_missing_marker(self):
        with self.assertRaisesRegex(actions.ActionError, "No current wallpaper"):
            actions.favorite_current()

    def test_konachan_query_resolves_weighted_tag_and_negative_tag(self):
        calls = []

        def fake_json(url):
            calls.append(url)
            if "name=rezero" in url:
                return [{"name": "re:zero_kara_hajimeru_isekai_seikatsu", "count": 1000},
                        {"name": "rezero", "count": 250}]
            return [{"name": "chibi", "count": 12}]

        with patch.object(actions, "fetch_json", side_effect=fake_json):
            url = actions.konachan_query("konachan.net", "safe", ["rezero", "-chibi"], (1920, 1080))
        self.assertIn("rating:safe+rezero+-chibi", url)
        self.assertIn("width%3A%3E%3D1920+height%3A%3E%3D1080", url)
        self.assertEqual(len(calls), 2)

    def test_konachan_fuzzy_fallback_and_questionable_filters(self):
        calls = []

        def fake_json(url):
            calls.append(url)
            return [] if len(calls) == 1 else [{"name": "hatsune_miku", "count": 450}]

        with patch.object(actions, "fetch_json", side_effect=fake_json):
            url = actions.konachan_query("konachan.com", "questionable", ["miku"], (100, 80))
        self.assertIn("rating:questionable+-loli+-child+hatsune_miku", url)
        self.assertIn("%2A", calls[1])

    def test_wallhaven_query_matches_original_filters(self):
        url = actions.wallhaven_query(["dark", "forest", "-moon"], (2560, 1440))
        self.assertIn("q=dark%20forest%20-moon", url)
        self.assertIn("categories=100&purity=100&sorting=random", url)
        self.assertIn("atleast=2560x1440&ratios=16x9,16x10", url)

    def test_remote_url_must_be_https_and_source_host(self):
        self.assertEqual(actions.https_url("https://w.wallhaven.cc/full/a.png", "wallhaven.cc"),
                         "https://w.wallhaven.cc/full/a.png")
        for url in ("http://w.wallhaven.cc/a.png", "https://evil.example/a.png",
                    "https://wallhaven.cc.evil.example/a.png", None,
                    "https://wallhaven.cc:invalid/a.png"):
            with self.assertRaises(actions.ActionError):
                actions.https_url(url, "wallhaven.cc")

    def test_each_random_source_uses_the_matching_endpoint(self):
        observed = []

        def fake_json(url):
            observed.append(url)
            if "/tag.json" in url:
                return []
            if "wallhaven.cc" in url:
                return {"data": [{"path": "https://w.wallhaven.cc/full/a.png"}]}
            return [{"file_url": "https://" + urlsplit_host(url) + "/image/a.png"}]

        def urlsplit_host(url):
            return url.split("/")[2]

        with patch.object(actions, "fetch_json", side_effect=fake_json):
            anime, anime_source = actions.image_url("randomanime", ["emilia"], (100, 80))
            wall, wall_source = actions.image_url("randomwall", ["forest"], (100, 80))
            gooner, gooner_source = actions.image_url("randomgooner", ["miku"], (100, 80))
        self.assertEqual((anime_source, wall_source, gooner_source), ("anime", "general", "gooner"))
        self.assertIn("konachan.net", anime)
        self.assertIn("wallhaven.cc", wall)
        self.assertIn("konachan.com", gooner)
        self.assertTrue(any("rating:safe" in url for url in observed))
        self.assertTrue(any("rating:questionable+-loli+-child" in url for url in observed))

    def test_no_remote_result_keeps_desktop_unmodified(self):
        old = self.image(self.root / "Pictures" / ".current-wallpaper" / "wallpaper.png")
        old_contents = old.read_bytes()
        for command, empty_result in (("randomanime", []), ("randomgooner", []),
                                      ("randomwall", {"data": []})):
            with self.subTest(command=command), \
                 patch.object(actions, "fetch_json", return_value=empty_result), \
                 patch.object(actions, "require_command") as command_lookup:
                with self.assertRaises(actions.ActionError):
                    actions.random_wallpaper(command, [])
                command_lookup.assert_not_called()
                self.assertEqual(old.read_bytes(), old_contents)

    def test_random_download_validates_then_auto_applies(self):
        source = self.image(self.root / "fixture.png")

        def fake_process(argv, timeout):
            if "--output" in argv:
                Path(argv[argv.index("--output") + 1]).write_bytes(source.read_bytes())
            return self.completed(argv)

        with patch.object(actions, "fetch_json", return_value={"data": [{"path": "https://w.wallhaven.cc/full/abc.png"}]}), \
             patch.object(actions, "require_command", side_effect=lambda name: name), \
             patch.object(actions, "ensure_daemon"), \
             patch.object(actions, "run_process", side_effect=fake_process):
            result = actions.random_wallpaper("randomwall", ["dark", "forest"])
        saved = Path(result["path"])
        self.assertEqual(result["source"], "general")
        self.assertTrue(saved.is_file())
        self.assertEqual(saved.read_bytes(), source.read_bytes())
        self.assertEqual(Path(result["current"]).read_bytes(), source.read_bytes())

    def test_failed_download_preserves_current_and_removes_partial_file(self):
        old = self.image(self.root / "Pictures" / ".current-wallpaper" / "wallpaper.png")
        old_contents = old.read_bytes()
        with patch.object(actions, "require_command", return_value="curl"), \
             patch.object(actions, "run_process", side_effect=lambda argv, timeout: self.completed(argv, 22)):
            with self.assertRaisesRegex(actions.ActionError, "download failed"):
                actions.download_image("https://konachan.net/data/a.png", "anime", (100, 80))
        self.assertEqual(old.read_bytes(), old_contents)
        self.assertEqual(list((self.root / "Pictures" / "random_konachan").iterdir()), [])

    def test_daemon_start_is_bounded_and_reuses_existing(self):
        with patch.object(actions, "daemon_ready", return_value=True), \
             patch.object(actions.subprocess, "Popen") as popen:
            actions.ensure_daemon("awww")
            popen.assert_not_called()
        with patch.object(actions, "daemon_ready", side_effect=[False, False, True]), \
             patch.object(actions, "require_command", return_value="awww-daemon"), \
             patch.object(actions.subprocess, "Popen") as popen, \
             patch.object(actions.time, "sleep"):
            actions.ensure_daemon("awww")
            popen.assert_called_once()

    def test_lock_rejects_concurrent_action(self):
        with actions.action_lock():
            with self.assertRaisesRegex(actions.ActionError, "already running"):
                with actions.action_lock():
                    pass

    def konachan_post(self, identifier, site="konachan.net", **overrides):
        post = {
            "id": identifier, "width": 1920, "height": 1080,
            "preview_url": f"https://{site}/data/preview/{identifier}.jpg",
            "sample_url": f"https://{site}/sample/{identifier}.jpg",
            "file_url": f"https://{site}/image/{identifier}.png",
        }
        post.update(overrides)
        return post

    def test_konachan_search_lists_results_without_downloading(self):
        observed = []
        posts = [self.konachan_post(1), self.konachan_post(2, file_url="https://evil.example/a.png"),
                 "not a post", self.konachan_post("../escape")]
        posts += [self.konachan_post(10 + i) for i in range(actions.SEARCH_LIMIT - len(posts))]

        def fake_json(url):
            observed.append(url)
            if "tag" in url.split("?")[0]:
                return []
            return posts if "konachan.net/post.json" in url else []

        with patch.object(actions, "fetch_json", side_effect=fake_json), \
             patch.object(actions, "run_process") as process:
            found = actions.search("anime", ["bleach"], page=2)
        process.assert_not_called()
        post_url = next(url for url in observed if "konachan.net/post.json" in url)
        self.assertIn("order:score+rating:safe", post_url)
        self.assertIn(f"limit={actions.SEARCH_LIMIT}&page=2", post_url)
        self.assertTrue(found["more"])
        self.assertEqual(found["page"], 2)
        first = found["results"][0]
        self.assertEqual(first["key"], "anime:konachan_1")
        self.assertEqual(first["stem"], "konachan_1")
        self.assertEqual(first["name"], "Konachan #1")
        self.assertEqual(first["url"], "https://konachan.net/data/preview/1.jpg")
        self.assertEqual(first["preview"], "https://konachan.net/sample/1.jpg")
        self.assertEqual(first["full"], "https://konachan.net/image/1.png")
        ids = [result["id"] for result in found["results"]]
        self.assertNotIn("2", ids)
        self.assertNotIn("../escape", ids)
        self.assertEqual(len(ids), actions.SEARCH_LIMIT - 3)

    def danbooru_post(self, identifier, width=3840, height=2160, tags="jujutsu_kaisen", **overrides):
        digest = f"{identifier:032x}"
        post = {
            "id": identifier, "image_width": width, "image_height": height, "file_ext": "png",
            "file_url": f"https://cdn.donmai.us/original/{digest}.png",
            "large_file_url": f"https://cdn.donmai.us/sample/sample-{digest}.jpg",
            "preview_file_url": f"https://cdn.donmai.us/180x180/{digest}.jpg",
            "tag_string": tags,
            "media_asset": {"variants": [
                {"type": "180x180", "url": f"https://cdn.donmai.us/180x180/{digest}.jpg", "file_ext": "jpg"},
                {"type": "360x360", "url": f"https://cdn.donmai.us/360x360/{digest}.jpg", "file_ext": "jpg"},
                {"type": "720x720", "url": f"https://cdn.donmai.us/720x720/{digest}.webp", "file_ext": "webp"},
            ]},
        }
        post.update(overrides)
        return post

    def test_anime_search_mixes_boards_and_survives_one_failing(self):
        observed = []
        yandere = [self.konachan_post(5, site="files.yande.re", preview_url="https://assets.yande.re/p/5.jpg",
                                      width=3000, height=1500),
                   self.konachan_post(6, site="files.yande.re", width=1500, height=3000)]
        danbooru = [self.danbooru_post(7), self.danbooru_post(8, file_ext="gif"),
                    self.danbooru_post(9, file_url="https://evil.example/a.png")]

        def fake_json(url):
            observed.append(url)
            if "tag" in url.split("?")[0]:
                return []
            if "konachan.net" in url:
                raise actions.ActionError("Wallpaper search failed; check the network or query")
            return yandere if "yande.re" in url else danbooru

        def fake_process(argv, timeout):
            for index, value in enumerate(argv):
                if value == "--output":
                    observed.append(argv[index + 2])
                    Path(argv[index + 1]).write_bytes(b"jpeg")
            return self.completed(argv)

        with patch.object(actions, "fetch_json", side_effect=fake_json), \
             patch.object(actions, "require_command", side_effect=lambda name: name), \
             patch.object(actions, "run_process", side_effect=fake_process), \
             redirect_stderr(io.StringIO()) as errors:
            found = actions.search("anime", ["bleach"])
        self.assertIn("Konachan:", errors.getvalue())
        self.assertEqual([result["key"] for result in found["results"]], ["anime:yandere_5", "anime:danbooru_7"])
        self.assertFalse(found["more"])
        yande, dan = found["results"]
        self.assertEqual((yande["name"], yande["url"]), ("yande.re #5", "https://assets.yande.re/p/5.jpg"))
        self.assertEqual(dan["name"], "Danbooru #7")
        self.assertTrue(dan["url"].startswith("file://") and dan["url"].endswith("/danbooru_7-thumb.jpg"))
        self.assertTrue(any("/360x360/" in url for url in observed))
        self.assertIn("/sample/", dan["preview"])
        self.assertIn("/original/", dan["full"])
        danbooru_url = next(url for url in observed if "danbooru.donmai.us/posts.json" in url)
        for part in ("order%3Ascore", "rating%3Ag", "ratio%3A%3E%3D1.3", "bleach"):
            self.assertIn(part, danbooru_url)

    def test_danbooru_previews_are_served_from_a_local_cache(self):
        cache = Path(os.environ["XDG_CACHE_HOME"])
        posts = [self.danbooru_post(7), self.danbooru_post(9)]
        downloads = []

        def fake_process(argv, timeout):
            # Danbooru's CDN rejects Qt, so curl fetches the card thumbnails;
            # #9's download fails and its card falls back to no thumbnail.
            pairs = [(argv[i + 1], argv[i + 2]) for i, value in enumerate(argv) if value == "--output"]
            for path, url in pairs:
                downloads.append(url)
                if "/360x360/" in url and f"{9:032x}" not in url:
                    Path(path).write_bytes(b"jpeg")
            return self.completed(argv, 0 if len(pairs) == 1 else 22)

        def fake_json(url):
            if "tag" in url.split("?")[0]:
                return []
            return posts if "danbooru" in url else []

        with patch.object(actions, "require_command", side_effect=lambda name: name), \
             patch.object(actions, "fetch_json", side_effect=fake_json), \
             patch.object(actions, "run_process", side_effect=fake_process):
            found = actions.search("anime", ["bleach"])
            first, second = found["results"]
            thumb = cache / "wallpick" / "previews" / "danbooru_7-thumb.jpg"
            self.assertEqual(first["url"], thumb.as_uri())
            self.assertTrue(first["previewFetch"])
            self.assertEqual(second["url"], "")
            self.assertTrue(first["preview"].startswith("https://cdn.donmai.us/sample/"))
            self.assertEqual(len(downloads), 2)
            # A second search reuses the cached thumbnail.
            actions.search("anime", ["bleach"])
            self.assertEqual(len(downloads), 3)

            preview = actions.fetch_preview("anime", "7", "https://cdn.donmai.us/360x360/" + f"{7:032x}.jpg")
            self.assertEqual(preview["url"], (cache / "wallpick" / "previews" / "danbooru_7-preview.jpg").as_uri())
            with self.assertRaises(actions.ActionError):
                actions.fetch_preview("anime", "7", "https://evil.example/a.jpg")
            with self.assertRaisesRegex(actions.ActionError, "could not be downloaded"):
                actions.fetch_preview("anime", "8", "https://cdn.donmai.us/sample/missing.jpg")

    def test_search_fails_only_when_every_board_fails(self):
        def fake_json(url):
            raise actions.ActionError("Wallpaper search failed; check the network or query")

        with patch.object(actions, "fetch_json", side_effect=fake_json), redirect_stderr(io.StringIO()):
            with self.assertRaises(actions.ActionError):
                actions.search("anime", ["bleach"])

    def test_multi_word_query_is_one_tag_not_two(self):
        # Konachan's real answers: "kaisen" alone would favour the artist kaisen_chuui.
        tags = {
            "jujutsu_kaisen": [{"name": "jujutsu_kaisen", "count": 15, "type": 3}],
            "kaisen": [{"name": "kaisen_chuui", "count": 21, "type": 1},
                       {"name": "jujutsu_kaisen", "count": 15, "type": 3}],
        }
        calls = []

        def fake_json(url):
            calls.append(url)
            return tags.get(url.rsplit("name=", 1)[1], [])

        with patch.object(actions, "fetch_json", side_effect=fake_json):
            self.assertEqual(actions.resolve_tags("konachan.net", ["jujutsu", "kaisen"]), ["jujutsu_kaisen"])
            self.assertEqual(len(calls), 1)
            self.assertEqual(actions.resolve_tags("konachan.net", ["kaisen"]), ["jujutsu_kaisen"])

    def test_words_must_start_tag_parts(self):
        tags = {
            "emilia": [{"name": "remilia_scarlet", "count": 2081, "type": 4},
                       {"name": "emilia_(re:zero)", "count": 294, "type": 4}],
            "dark_forest": [], "%2Adark%2Aforest%2A": [{"name": "dark_elven_forest_ranger", "count": 10, "type": 4}],
            "dark": [{"name": "dark", "count": 900, "type": 0}],
            "forest": [{"name": "forest", "count": 5000, "type": 0}],
            "gojo_satoru": [], "%2Agojo%2Asatoru%2A": [{"name": "gojou_satoru", "count": 40, "type": 4}],
        }
        with patch.object(actions, "fetch_json", side_effect=lambda url: tags.get(url.rsplit("name=", 1)[1], [])):
            self.assertEqual(actions.resolve_tags("konachan.net", ["emilia", "-chibi"]), ["emilia_(re:zero)", "-chibi"])
            self.assertEqual(actions.resolve_tags("konachan.net", ["dark", "forest"]), ["dark", "forest"])
            self.assertEqual(actions.resolve_tags("konachan.net", ["gojo", "satoru"]), ["gojou_satoru"])

    def test_danbooru_sends_rarest_tag_and_filters_the_rest(self):
        def fake_json(url):
            if "tags.json" in url:
                if "jujutsu" in url:
                    return [{"name": "jujutsu_kaisen", "post_count": 25000, "category": 3}]
                if "gojo" in url:
                    return [{"name": "gojo_satoru", "post_count": 6000, "category": 4}]
                return [{"name": "chibi", "post_count": 390000, "category": 0}]
            if "posts.json" in url:
                return [self.danbooru_post(1, tags="jujutsu_kaisen gojo_satoru"),
                        self.danbooru_post(2, tags="jujutsu_kaisen gojo_satoru chibi"),
                        self.danbooru_post(3, tags="gojo_satoru")]
            return []

        with patch.object(actions, "fetch_json", side_effect=fake_json):
            url, rest = actions.danbooru_query("g", ["jujutsu_kaisen", "gojo_satoru", "-chibi"], (1920, 1080), limit=24)
            self.assertIn("+gojo_satoru&", url)
            self.assertNotIn("jujutsu", url)
            self.assertEqual(rest, ["jujutsu_kaisen", "-chibi"])
            results, _ = actions.booru_page(actions.DANBOORU, "g", "anime", ["jujutsu_kaisen", "gojo_satoru", "-chibi"],
                                            (1920, 1080), 1)
        self.assertEqual([result["id"] for result in results], ["1"])
        with patch.object(actions, "fetch_json", return_value=[]):
            url, _ = actions.danbooru_query("g", [], (1920, 1080), limit=24)
        self.assertIn("order%3Arank", url)

    def test_questionable_search_keeps_its_filters_and_host(self):
        with patch.object(actions, "fetch_json", side_effect=lambda url: [] if "/tag.json" in url
                          else [self.konachan_post(5, site="konachan.com")]) as fetch:
            found = actions.search("gooner", [])
        self.assertIn("konachan.com/post.json", fetch.call_args.args[0])
        self.assertIn("rating:questionable+-loli+-child", fetch.call_args.args[0])
        self.assertFalse(found["more"])
        self.assertEqual(found["results"][0]["source"], "gooner")
        self.assertEqual(found["results"][0]["stem"], "konachan_5")

    def test_wallhaven_search_uses_relevance_and_reports_more_pages(self):
        post = {"id": "abc123", "file_type": "image/jpeg", "dimension_x": 3840, "dimension_y": 2160,
                "path": "https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg",
                "thumbs": {"large": "https://th.wallhaven.cc/lg/ab/abc123.jpg"}}
        gif = dict(post, id="gif1", file_type="image/gif")
        data = {"data": [post, gif], "meta": {"current_page": 1, "last_page": 3}}
        with patch.object(actions, "fetch_json", return_value=data) as fetch:
            found = actions.search("general", ["dark", "forest"])
            self.assertIn("sorting=relevance", fetch.call_args.args[0])
            self.assertTrue(found["more"])
            self.assertEqual([result["id"] for result in found["results"]], ["abc123"])
            self.assertEqual(found["results"][0]["url"], "https://th.wallhaven.cc/lg/ab/abc123.jpg")
            self.assertEqual(found["results"][0]["stem"], "wallhaven_abc123")
            found = actions.search("general", [], page=3)
            self.assertIn("sorting=toplist", fetch.call_args.args[0])
            self.assertIn("&page=3", fetch.call_args.args[0])
            self.assertFalse(found["more"])

    def test_search_rejects_unknown_source(self):
        with self.assertRaisesRegex(actions.ActionError, "Unknown search source"):
            actions.search("favorites", [])

    def test_result_download_validates_source_host_and_id(self):
        with patch.object(actions, "run_process") as process:
            with self.assertRaises(actions.ActionError):
                actions.download_result("anime", "1", "https://wallhaven.cc/full/a.png")
            with self.assertRaises(actions.ActionError):
                actions.download_result("gooner", "1", "https://cdn.donmai.us/original/a.png")
            with self.assertRaises(actions.ActionError):
                actions.download_result("anime", "../../x", "https://konachan.net/image/a.png")
            process.assert_not_called()

    def test_apply_result_downloads_under_stable_name_then_reuses_it(self):
        source = self.image(self.root / "fixture.png")
        downloads = []

        def fake_process(argv, timeout):
            if "--output" in argv:
                downloads.append(argv[-1])
                Path(argv[argv.index("--output") + 1]).write_bytes(source.read_bytes())
            return self.completed(argv)

        with patch.object(actions, "require_command", side_effect=lambda name: name), \
             patch.object(actions, "ensure_daemon"), \
             patch.object(actions, "run_process", side_effect=fake_process):
            first = actions.apply_result("anime", "42", "https://konachan.net/image/a.png")
            second = actions.apply_result("anime", "42", "https://konachan.net/image/a.png")
        saved = self.root / "Pictures" / "random_konachan" / "konachan_42.png"
        self.assertEqual(first["path"], str(saved))
        self.assertEqual(second["path"], str(saved))
        self.assertEqual(downloads, ["https://konachan.net/image/a.png"])
        self.assertEqual(Path(first["current"]).read_bytes(), source.read_bytes())

    def test_each_board_saves_under_its_own_name(self):
        source = self.image(self.root / "fixture.png")

        def fake_process(argv, timeout):
            if "--output" in argv:
                Path(argv[argv.index("--output") + 1]).write_bytes(source.read_bytes())
            return self.completed(argv)

        with patch.object(actions, "require_command", side_effect=lambda name: name), \
             patch.object(actions, "run_process", side_effect=fake_process):
            yandere = actions.download_result("anime", "42", "https://files.yande.re/image/abc/a.png")
            danbooru = actions.download_result("anime", "42", "https://cdn.donmai.us/original/ab/a.png")
        self.assertEqual((yandere.name, danbooru.name), ("yandere_42.png", "danbooru_42.png"))

    def test_failed_result_download_keeps_desktop_and_folder_clean(self):
        old = self.image(self.root / "Pictures" / ".current-wallpaper" / "wallpaper.png")
        old_contents = old.read_bytes()
        with patch.object(actions, "require_command", return_value="curl"), \
             patch.object(actions, "run_process", side_effect=lambda argv, timeout: self.completed(argv, 22)):
            with self.assertRaisesRegex(actions.ActionError, "download failed"):
                actions.apply_result("general", "abc123", "https://w.wallhaven.cc/full/ab/a.jpg")
        self.assertEqual(old.read_bytes(), old_contents)
        self.assertEqual(list((self.root / "Pictures" / "random_wallhaven").iterdir()), [])

    def test_favorite_result_saves_a_copy_in_favorites(self):
        saved = self.image(self.root / "Pictures" / "random_konachan" / "konachan_7.png")
        with patch.object(actions, "run_process") as process:
            favorite = actions.favorite_result("anime", "7", "https://konachan.net/image/a.png")
        process.assert_not_called()
        self.assertEqual(Path(favorite["path"]).parent, self.root / "Pictures" / "favorite")
        self.assertEqual(Path(favorite["path"]).read_bytes(), saved.read_bytes())

    def test_cli_search_does_not_wait_for_the_action_lock(self):
        output = io.StringIO()
        with patch.object(actions, "search", return_value={"results": []}) as search, \
             redirect_stdout(output), actions.action_lock():
            status = actions.main(["search", "--", "anime", "2", "bleach", "-chibi"])
        self.assertEqual(status, 0)
        search.assert_called_once_with("anime", ["bleach", "-chibi"], 2)

    def test_cli_passes_negative_tags_as_data(self):
        output = io.StringIO()
        with patch.object(actions, "random_wallpaper", return_value={"path": "/tmp/example.png"}) as random_action, \
             redirect_stdout(output):
            status = actions.main(["randomanime", "--", "rezero", "-chibi"])
        self.assertEqual(status, 0)
        random_action.assert_called_once_with("randomanime", ["rezero", "-chibi"])
        self.assertEqual(json.loads(output.getvalue()), {"path": "/tmp/example.png"})

    # --- Steam Workshop -------------------------------------------------

    def workshop_item(self, identifier, tags=("Video", "Everyone", "1920 x 1080"), **overrides):
        item = {
            "publishedfileid": str(identifier), "consumer_appid": 431960, "title": f"Loop {identifier}",
            "preview_url": f"https://images.steamusercontent.com/ugc/{identifier}/ABC/",
            "tags": [{"tag": tag, "display_name": tag} for tag in tags],
        }
        item.update(overrides)
        return item

    def browse_page(self, results, total_pages=3):
        # Steam nests the listing as a JSON string inside the page's SSR data.
        state = json.dumps({"queries": [{"state": {"data": {"current_page": 1, "total_pages": total_pages,
                                                             "results": results}}}]})
        data = json.dumps({"route": "/workshop/browse", "renderContext": state})
        return f'<html><script type="application/json" id="valve-ssr-data" nonce="x">{data}</script></html>'

    def test_workshop_search_lists_only_safe_landscape_videos_and_scenes(self):
        observed = []
        results = [self.workshop_item(1), self.workshop_item(2, tags=("Scene", "Everyone")),
                   self.workshop_item(10, tags=("Web", "Everyone")),
                   self.workshop_item(3, tags=("Video", "Mature")), self.workshop_item(4, tags=("Video", "Everyone", "1080 x 1920")),
                   self.workshop_item(5, tags=("Video", "Everyone", "1280 x 720")), self.workshop_item(6, tags=("Video", "Everyone")),
                   self.workshop_item(7, consumer_appid=4000), self.workshop_item("../8"),
                   self.workshop_item(9, preview_url="https://evil.example/a.gif")]

        def fake_text(url, data=None):
            observed.append(url)
            return self.browse_page(results)

        with patch.dict(os.environ, {"WALLPICK_MIN_WIDTH": "1920", "WALLPICK_MIN_HEIGHT": "1080"}), \
             patch.object(actions, "fetch_text", side_effect=fake_text):
            found = actions.search("workshop", ["rem", "&x"], 2)
        url = observed[0]
        self.assertTrue(url.startswith("https://steamcommunity.com/workshop/browse/?appid=431960&"))
        for part in ("requiredtags%5B%5D=Everyone", "p=2", "searchtext=rem%20%26x", "browsesort=textsearch"):
            self.assertIn(part, url)
        # The type filter takes one type, so it is left out and applied here.
        self.assertNotIn("requiredtags%5B%5D=Video", url)
        self.assertEqual([result["id"] for result in found["results"]], ["1", "2", "6"])
        self.assertTrue(found["more"])
        first = found["results"][0]
        self.assertEqual((first["key"], first["stem"], first["name"]), ("workshop:workshop_1", "workshop_1", "Loop 1"))
        self.assertTrue(first["url"].startswith("https://images.steamusercontent.com/ugc/1/ABC/?imw=512"))
        self.assertEqual((first["width"], first["height"]), (1920, 1080))
        self.assertEqual(found["results"][2]["width"], 0)

    def test_workshop_without_words_lists_the_most_popular(self):
        with patch.object(actions, "fetch_text", return_value=self.browse_page([], total_pages=1)) as fetch:
            found = actions.search("workshop", [], 1)
        self.assertIn("browsesort=trend&days=-1", fetch.call_args.args[0])
        self.assertNotIn("searchtext", fetch.call_args.args[0])
        self.assertFalse(found["more"])

    def test_workshop_falls_back_to_the_public_details_api(self):
        html = '<a href="https://steamcommunity.com/sharedfiles/filedetails/?id=11">x</a>' \
               '<a href="https://steamcommunity.com/sharedfiles/filedetails/?id=11">y</a>' \
               '<a href="https://steamcommunity.com/sharedfiles/filedetails/?id=12">z</a>'
        details = {"response": {"publishedfiledetails": [
            {**self.workshop_item(11), "consumer_app_id": 431960, "result": 1},
            {**self.workshop_item(12), "consumer_app_id": 431960, "result": 1, "banned": 1}]}}
        calls = []

        def fake_text(url, data=None):
            calls.append((url, data))
            return html if data is None else json.dumps(details)

        with patch.object(actions, "fetch_text", side_effect=fake_text):
            found = actions.search("workshop", ["x"], 1)
        self.assertEqual([result["id"] for result in found["results"]], ["11"])
        self.assertEqual(calls[1][1], "itemcount=2&publishedfileids%5B0%5D=11&publishedfileids%5B1%5D=12")

    def steam_item(self, base, identifier, project=None, video="loop.mp4"):
        folder = base / "steamapps" / "workshop" / "content" / "431960" / str(identifier)
        folder.mkdir(parents=True)
        (folder / video).write_bytes(b"video")
        self.image(folder / "preview.png", (64, 64))
        (folder / "project.json").write_text(json.dumps(project or {
            "type": "Video", "file": video, "preview": "preview.png", "title": f"Local {identifier}"}))
        return folder

    def fake_ffmpeg(self, calls):
        def process(argv, timeout):
            calls.append(argv)
            if argv[0] == "ffprobe":
                return self.completed(argv, stdout=b"10.0\n")
            self.image(Path(argv[-1]), (160, 90))
            return self.completed(argv)
        return process

    def test_local_subscription_becomes_a_still_without_steamcmd(self):
        folder = self.steam_item(self.root / "steam", 21)
        calls = []
        with patch.object(actions, "require_command", side_effect=lambda name: name), \
             patch.object(actions.shutil, "which", side_effect=lambda name: name), \
             patch.object(actions.subprocess, "run") as steamcmd, \
             patch.object(actions, "run_process", side_effect=self.fake_ffmpeg(calls)):
            still = actions.download_result("workshop", "21", "steam")
            again = actions.download_result("workshop", "21", "steam")
        steamcmd.assert_not_called()
        self.assertEqual(still, self.root / "Pictures" / "random_workshop" / "workshop_21.jpg")
        self.assertEqual(again, still)
        self.assertEqual(actions.validate_image(still), ("jpg", (160, 90)))
        ffmpeg = [argv for argv in calls if argv[0] == "ffmpeg"]
        self.assertEqual(len(ffmpeg), 1, "the saved still is reused")
        self.assertEqual(ffmpeg[0][ffmpeg[0].index("-ss") + 1], "1.5")
        self.assertIn(str(folder / "loop.mp4"), ffmpeg[0])
        self.assertTrue(folder.is_dir(), "Steam's own download is left alone")
        self.assertEqual([path.name for path in still.parent.iterdir()], ["workshop_21.jpg"])

    def test_unreadable_video_leaves_no_partial_files(self):
        self.steam_item(self.root / "steam", 22)
        with patch.object(actions, "require_command", side_effect=lambda name: name), \
             patch.object(actions.shutil, "which", return_value=None), \
             patch.object(actions, "run_process", side_effect=lambda argv, timeout: self.completed(argv, 1)):
            with self.assertRaisesRegex(actions.ActionError, "frame"):
                actions.download_result("workshop", "22", "steam")
        self.assertEqual(list((self.root / "Pictures" / "random_workshop").iterdir()), [])

    def test_project_json_cannot_point_outside_its_item(self):
        outside = self.root / "steam" / "secret.mp4"
        outside.parent.mkdir(parents=True)
        outside.write_bytes(b"x")
        self.steam_item(self.root / "steam", 23, {"type": "video", "file": "../../../../../secret.mp4"})
        self.steam_item(self.root / "steam", 24, {"type": "scene", "file": "scene.pkg"})
        import workshop
        self.assertIsNone(workshop.read_project(workshop.find_item("23")))
        self.assertIsNone(workshop.read_project(workshop.find_item("24")))
        self.assertEqual(workshop.wallpaper_items(), [])

    def test_workshop_download_requires_a_steam_login(self):
        with patch.object(actions.shutil, "which", side_effect=lambda name: name), \
             patch.object(actions.subprocess, "run") as steamcmd, redirect_stderr(io.StringIO()) as errors:
            status = actions.main(["apply-result", "--", "workshop", "31", "steam"])
        self.assertEqual(status, 3)
        self.assertIn("wallpick steam-login", errors.getvalue())
        steamcmd.assert_not_called()

    def test_steamcmd_downloads_privately_then_keeps_only_the_still(self):
        calls = []
        steam_root = self.root / "data" / "wallpick" / "steamcmd" / ".local" / "share" / "Steam"

        def fake_run(argv, **options):
            calls.append((argv, options))
            # The nixpkgs wrapper creates "Steamapps"; steamcmd reports where it saved.
            self.steam_item(steam_root, 41)
            (steam_root / "steamapps").rename(steam_root / "Steamapps")
            moved = steam_root / "Steamapps" / "workshop" / "content" / "431960" / "41"
            return self.completed(argv, stdout=b'\x1b[0mSuccess. Downloaded item 41 to "%s" (5 bytes)' % bytes(moved))

        with patch.dict(os.environ, {"WALLPICK_STEAM_USER": "someone_1"}), \
             patch.object(actions, "require_command", side_effect=lambda name: name), \
             patch.object(actions.shutil, "which", side_effect=lambda name: name), \
             patch.object(actions.subprocess, "run", side_effect=fake_run), \
             patch.object(actions, "run_process", side_effect=self.fake_ffmpeg([])):
            still = actions.download_result("workshop", "41", "https://steamcommunity.com/sharedfiles/filedetails/?id=41")
        argv, options = calls[0]
        self.assertEqual(argv, ["steamcmd", "+login", "someone_1", "+workshop_download_item", "431960", "41", "+quit"])
        home = self.root / "data" / "wallpick" / "steamcmd"
        self.assertEqual((options["env"]["HOME"], options["cwd"]), (str(home), home))
        self.assertEqual(options["stdin"], subprocess.DEVNULL)
        self.assertTrue(still.is_file())
        self.assertFalse((steam_root / "Steamapps" / "workshop" / "content" / "431960" / "41").exists())

    def test_steamcmd_report_outside_its_root_is_not_trusted(self):
        elsewhere = self.steam_item(self.root / "elsewhere", 42)
        output = b'Success. Downloaded item 42 to "%s"' % bytes(elsewhere)
        with patch.dict(os.environ, {"WALLPICK_STEAM_USER": "a"}), \
             patch.object(actions.shutil, "which", side_effect=lambda name: name), \
             patch.object(actions.subprocess, "run", return_value=self.completed([], 0, stdout=output)), \
             redirect_stderr(io.StringIO()):
            with self.assertRaisesRegex(actions.ActionError, "could not download"):
                actions.steamcmd_download("42")
        self.assertTrue(elsewhere.is_dir())

    def test_steamcmd_failures_say_what_to_do(self):
        cases = [(b"Cached credentials not found.\npassword: \nLogging in user 'a' to Steam Public...ERROR (Invalid Password)",
                  "sign-in has expired"),
                 (b"Downloading item 51 ...\nERROR! Download item 51 failed (Failure).", "must own Wallpaper Engine"),
                 (b"Rate Limit Exceeded", "limiting")]
        for output, message in cases:
            with self.subTest(message=message), patch.dict(os.environ, {"WALLPICK_STEAM_USER": "a"}), \
                 patch.object(actions.shutil, "which", side_effect=lambda name: name), \
                 patch.object(actions.subprocess, "run", return_value=self.completed([], 5, stdout=output)), \
                 redirect_stderr(io.StringIO()):
                with self.assertRaisesRegex(actions.NoticeError, message):
                    actions.workshop_still("51")
        with patch.dict(os.environ, {"WALLPICK_STEAM_USER": "a +quit"}):
            with self.assertRaisesRegex(actions.NoticeError, "invalid"):
                actions.steam_user()

    def test_scan_lists_downloaded_videos_until_they_have_a_still(self):
        self.steam_item(self.root / "steam", 61)
        flatpak = self.root / "library"
        (self.root / "steam" / "steamapps" / "libraryfolders.vdf").write_text(
            '"libraryfolders"\n{\n "1"\n {\n  "path"\t\t"%s"\n }\n}\n' % flatpak)
        self.steam_item(flatpak, 62)
        data = backend.scan()
        items = data["sources"]["workshop"]["items"]
        self.assertEqual(sorted(item["id"] for item in items), ["61", "62"])
        pending = next(item for item in items if item["id"] == "61")
        self.assertTrue(pending["remote"])
        self.assertEqual(pending["name"], "Local 61")
        self.assertTrue(pending["url"].startswith("file://") and pending["url"].endswith("preview.png"))
        self.assertFalse(any(item["source"] == "workshop" and item.get("remote")
                             for item in data["sources"]["recent"]["items"]))
        self.image(self.root / "Pictures" / "random_workshop" / "workshop_61.jpg", image_format="JPEG")
        items = backend.scan()["sources"]["workshop"]["items"]
        self.assertEqual(sorted((item.get("id") or item["name"]) for item in items), ["62", "workshop_61.jpg"])

    def test_random_workshop_applies_a_listed_video(self):
        pages = []

        def fake_page(words, page):
            pages.append(page)
            return [{"id": "71"}], 1

        with patch.object(actions, "workshop_page", side_effect=fake_page), \
             patch.object(actions, "workshop_still", return_value=Path("/w/workshop_71.jpg")) as still, \
             patch.object(actions, "apply", return_value={"path": "/w/workshop_71.jpg"}):
            result = actions.random_wallpaper("randomworkshop", ["rain"])
        still.assert_called_once_with("71")
        self.assertEqual(pages, [1])
        self.assertEqual(result["source"], "workshop")

    # --- Scene packages ---------------------------------------------------

    def tex(self, size, payload, *, tex_format=0, flags=0, texture=None, container="TEXB0003",
            image_format=-1, mipmap=None, compress=False):
        """A .tex texture laid out as RePKG's TexWriter writes one."""
        texture = texture or size
        mipmap = mipmap or texture
        version = int(container[4:])
        data = b"TEXV0005\0TEXI0001\0" + struct.pack("<7i", tex_format, flags, *texture, *size, 0)
        data += container.encode() + b"\0" + struct.pack("<i", 1)
        if version >= 3:
            data += struct.pack("<i", image_format)
        if version == 4:
            data += struct.pack("<i", 0)
        data += struct.pack("<i", 1) + struct.pack("<2i", *mipmap)
        stored = lz4.block.compress(payload, store_size=False) if compress else payload
        if version >= 2:
            data += struct.pack("<2i", 1 if compress else 0, len(payload))
        return data + struct.pack("<i", len(stored)) + stored

    def pkg(self, entries):
        """A scene.pkg laid out as RePKG's PackageWriter writes one."""
        header, body = b"", b""
        for name, data in entries.items():
            encoded = name.encode()
            header += struct.pack("<i", len(encoded)) + encoded + struct.pack("<2i", len(body), len(data))
            body += data
        return struct.pack("<i", 8) + b"PKGV0001" + struct.pack("<i", len(entries)) + header + body

    def jpeg_bytes(self, size, color):
        buffer = io.BytesIO()
        Image.new("RGB", size, color).save(buffer, format="JPEG", quality=95)
        return buffer.getvalue()

    def scene_folder(self, identifier, entries, base=None, title="Scene"):
        folder = (base or self.root / "steam") / "steamapps" / "workshop" / "content" / "431960" / str(identifier)
        folder.mkdir(parents=True)
        (folder / "scene.pkg").write_bytes(self.pkg(entries))
        (folder / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json", "title": title}))
        return folder

    def test_scene_uses_its_largest_landscape_picture(self):
        background = self.jpeg_bytes((320, 180), (200, 40, 40))
        folder = self.scene_folder(81, {
            "scene.json": b"{}",
            "materials/small.tex": self.tex((160, 90), self.jpeg_bytes((160, 90), (0, 0, 255)), image_format=2),
            # Bigger, but square: an effect atlas, not the background.
            "materials/atlas.tex": self.tex((512, 512), b"\0" * 512 * 512 * 4),
            "materials/anim.tex": self.tex((640, 360), b"\0" * 640 * 360 * 4, flags=scenepkg.FLAG_GIF),
            "materials/background.tex": self.tex((320, 180), background, image_format=2),
        })
        picture = scenepkg.main_picture(folder)
        self.assertEqual(picture.size, (320, 180))
        red, green, blue = picture.convert("RGB").getpixel((10, 10))
        self.assertGreater(red, 180)
        self.assertLess(green + blue, 120)

    def test_raw_lz4_texture_is_cropped_to_its_picture(self):
        texture = Image.new("RGBA", (256, 256), (0, 0, 0, 255))
        texture.paste(Image.new("RGBA", (200, 150), (10, 200, 30, 255)))
        folder = self.scene_folder(82, {"materials/bg.tex": self.tex(
            (200, 150), texture.tobytes(), texture=(256, 256), container="TEXB0002", compress=True)})
        picture = scenepkg.main_picture(folder)
        self.assertEqual(picture.size, (200, 150))
        self.assertEqual(picture.getpixel((199, 149)), (10, 200, 30, 255))

    def test_dxt_textures_decode(self):
        # One 4x4 block per format, every pixel colour 0 (pure red in RGB565).
        red = 0xF800
        dxt1 = struct.pack("<HHI", red, red, 0)
        dxt5 = bytes([255, 255, 0, 0, 0, 0, 0, 0]) + dxt1
        for tex_format, block in ((scenepkg.TEX_DXT1, dxt1), (scenepkg.TEX_DXT5, dxt5)):
            with self.subTest(tex_format=tex_format):
                folder = self.scene_folder(83 + tex_format, {"materials/bg.tex": self.tex(
                    (8, 4), block * 2, tex_format=tex_format)})
                picture = scenepkg.main_picture(folder)
                self.assertEqual(picture.size, (8, 4))
                self.assertEqual(picture.getpixel((7, 3))[:3], (255, 0, 0))

    def test_loose_materials_are_read_when_there_is_no_package(self):
        folder = self.root / "steam" / "steamapps" / "workshop" / "content" / "431960" / "91"
        (folder / "materials").mkdir(parents=True)
        (folder / "materials" / "bg.tex").write_bytes(
            self.tex((320, 180), self.jpeg_bytes((320, 180), (0, 90, 0)), image_format=2))
        self.assertEqual(scenepkg.main_picture(folder).size, (320, 180))

    def test_malformed_packages_are_rejected(self):
        good = self.tex((320, 180), self.jpeg_bytes((320, 180), (1, 2, 3)), image_format=2)
        truncated = self.pkg({"materials/bg.tex": good})[:-50]
        outside = bytearray(self.pkg({"materials/bg.tex": good}))
        offset = 4 + 8 + 4 + 4 + len("materials/bg.tex")
        outside[offset:offset + 4] = struct.pack("<i", 10_000_000)
        lying = self.tex((320, 180), b"\0" * 64, container="TEXB0002", compress=True)
        lying = lying.replace(struct.pack("<2i", 1, 64), struct.pack("<2i", 1, 64_000_000), 1)
        for name, data in (("truncated", truncated), ("outside", bytes(outside)), ("not a package", b"garbage!"),
                           ("bad lz4", self.pkg({"materials/bg.tex": lying}))):
            with self.subTest(name=name):
                folder = self.root / name
                folder.mkdir()
                (folder / "scene.pkg").write_bytes(data)
                with self.assertRaises(scenepkg.SceneError):
                    scenepkg.main_picture(folder)

    def test_scene_subscription_becomes_a_still(self):
        self.scene_folder(92, {"materials/bg.tex": self.tex(
            (320, 180), self.jpeg_bytes((320, 180), (90, 60, 30)), image_format=2)}, title="Quiet room")
        self.scene_folder(93, {"materials/bg.tex": self.tex(
            (64, 36), self.jpeg_bytes((64, 36), (90, 60, 30)), image_format=2)})
        items = {item["id"]: item for item in backend.scan()["sources"]["workshop"]["items"]}
        self.assertEqual(items["92"]["name"], "Quiet room")
        with patch.object(actions.subprocess, "run") as steamcmd:
            still = actions.download_result("workshop", "92", "steam")
            with self.assertRaisesRegex(actions.NoticeError, "only 64×36"):
                actions.download_result("workshop", "93", "steam")
        steamcmd.assert_not_called()
        self.assertEqual(still.name, "workshop_92.jpg")
        self.assertEqual(actions.validate_image(still), ("jpg", (320, 180)))
        self.assertEqual(sorted(path.name for path in still.parent.iterdir()), ["workshop_92.jpg"])


if __name__ == "__main__":
    unittest.main()
