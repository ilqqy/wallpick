"""Isolated action tests: no live network, wallpaper daemon, or desktop writes."""

from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import actions  # noqa: E402


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
        })
        env.start()
        self.addCleanup(env.stop)

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
            return [] if "/tag.json" in url else posts

        with patch.object(actions, "fetch_json", side_effect=fake_json), \
             patch.object(actions, "run_process") as process:
            found = actions.search("anime", ["bleach"], page=2)
        process.assert_not_called()
        post_url = observed[-1]
        self.assertIn("order:score+rating:safe", post_url)
        self.assertIn(f"limit={actions.SEARCH_LIMIT}&page=2", post_url)
        self.assertTrue(found["more"])
        self.assertEqual(found["page"], 2)
        first = found["results"][0]
        self.assertEqual(first["key"], "anime:1")
        self.assertEqual(first["stem"], "konachan_1")
        self.assertEqual(first["url"], "https://konachan.net/data/preview/1.jpg")
        self.assertEqual(first["preview"], "https://konachan.net/sample/1.jpg")
        self.assertEqual(first["full"], "https://konachan.net/image/1.png")
        ids = [result["id"] for result in found["results"]]
        self.assertNotIn("2", ids)
        self.assertNotIn("../escape", ids)
        self.assertEqual(len(ids), actions.SEARCH_LIMIT - 3)

    def test_questionable_search_keeps_its_filters_and_host(self):
        with patch.object(actions, "fetch_json", side_effect=lambda url: [] if "/tag.json" in url
                          else [self.konachan_post(5, site="konachan.com")]) as fetch:
            found = actions.search("gooner", [])
        self.assertIn("konachan.com/post.json", fetch.call_args.args[0])
        self.assertIn("rating:questionable+-loli+-child", fetch.call_args.args[0])
        self.assertFalse(found["more"])
        self.assertEqual(found["results"][0]["source"], "gooner")

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


if __name__ == "__main__":
    unittest.main()
