# Wallpick handoff for Astra

## Continuation update — 2026-09-23

The pending checks below were completed during the continuation. This original handoff is retained as history; its “Next checks” list is no longer the current task list.

- Regression suite now covers carousel shrinking/empty collections, replaced/deleted files during scanning, real popup image loading/error/recovery, local Random selection, and all three remote Random command routes.
- Fixed a stale item-count QML exception during category switches, Apply/Favorite availability before a valid preview is ready, cursor-query races during rapid reopening, scan interruption by disappearing files, and launcher IPC readiness timing.
- Added a clearly labeled Random button beneath every category. Favorites/Recent select a local preview without applying. Konachan/Wallhaven/Gooner invoke the existing remote commands and apply immediately. The original fetch controls now explicitly include “Random” in their labels. R follows the selected category.
- The popup is now 910×890 to accommodate category actions.
- Final read-only subagent review found no remaining concrete blocker after these fixes.
- External NixOS config and Waybar remain untouched. The current wallpaper was verified as `~/Pictures/favorite/upscaled-ichigo.png`; the continuation used fixtures for action tests.
- New preview test: `tests/preview.qml`. `tests/check.py` runs popup tests only when a Wayland session is available.

Historical handoff follows.

This note is a continuation handoff for `/home/ilyanix/wallpick`. The user asked for a working standalone Quickshell wallpaper picker and specifically asked that the external NixOS config and Waybar remain untouched.

## Hard constraints

- `AGENTS.md` and `PROJECT_SPEC.md` were read completely.
- Treat `/home/ilyanix/nixos-config` as strictly read-only.
- Do not modify Waybar or the main NixOS configuration.
- Do not run `nixos-rebuild`, `nix flake update` in the external config, or imperative installs.
- Keep the implementation native to Quickshell / Qt Quick / QML.
- Preserve Liten fidelity. The public implementations for Sparkle Text, Ascii Wave, Drift Slider, Folder Reveal, and Liquid Metal Button were inspected before porting.
- Do not replace the existing implementation with placeholders or generic effects.

## What exists now

The application is implemented under `src/` with a Python indexing/action helper under `scripts/backend.py` and regression tests under `tests/`.

- `src/shell.qml`: singleton shell, IPC target `wallpick`, top-right `PanelWindow`, cursor-position monitor selection through `hyprctl cursorpos -j`, focused-monitor fallback, focus grab for outside-click close.
- `src/WallpaperPopup.qml`: main UI, image-first preview, current-desktop card, source/folder cards, query/tag field, random actions, carousel, Apply and Favorite actions.
- `src/services/WallpaperService.qml`: asynchronous scan and action processes, timeout wrapper, friendly errors, current-image uncertainty/last-known preservation, refresh coalescing.
- `src/components/SparkleTitle.qml`: deterministic sparkle placement, chrome text, bloom layer, breathing bloom, four-point sparkles.
- `src/components/AsciiWave.qml`: value-noise-driven Canvas glyph field with density ramp and accent-to-core treatment.
- `src/components/FolderSourceCard.qml`: folder pocket plus fan-out thumbnail sheets, staggered spring motion, hover/focus/click pinning.
- `src/components/DriftWallpaperSlider.qml`: fixed nine-card window, drag/wheel/keyboard navigation, depth transforms, spring settling and tilt.
- `src/components/LiquidMetalButton.qml` and `src/shaders/liquidmetal.frag`: custom chromatic liquid-metal rim, distortion, moving sheen, hover/press states. `src/shaders/liquidmetal.frag.qsb` is generated and ignored by the source filter.
- `src/components/QuietButton.qml`: keyboard/focus-accessible quiet control used by the UI.
- `scripts/backend.py`: safe local scan, SHA-256 current-image matching, mtime cache-busting URLs, source/favorite boundaries, selected-favorite copy.
- `scripts/run.sh`: live source launcher and IPC convenience wrapper.
- `flake.nix` / `flake.lock`: pinned nixpkgs package and dev shell; shader is compiled during package build.

## External backend facts already verified

The source of truth is `/home/ilyanix/nixos-config/configuration.nix`, Fish functions around lines 1258–1582. No edits were made there.

- `wallset`: accepts PNG/JPEG, calls `awww img` with grow transition, runs `wal -ni`, restarts `waybar.service`, updates `~/Pictures/.current-wallpaper/wallpaper.{png,jpg}`.
- `fav`: copies the current marker into `~/Pictures/favorite/favorite_<timestamp>.<ext>`.
- `randomanime`: safe Konachan source, writes `~/Pictures/random_konachan`, then calls `wallset`.
- `randomwall`: safe Wallhaven general source, writes `~/Pictures/random_wallhaven`, then calls `wallset`.
- `randomgooner`: separate questionable Konachan source, writes `~/Pictures/random_gooner`, then calls `wallset`.
- Waybar's Nix-logo left click currently calls `fish -c randomanime`; Waybar was not changed.

The picker intentionally exposes that random actions apply the downloaded wallpaper immediately because that is what the existing Fish functions do. Browsing/selecting a local image does not apply it until Apply is pressed.

## Verification already completed

Before the final preview-error handling patch, these passed:

- `nix flake check`
- `nix build .#default`
- `nix develop -c python3 tests/check.py`
- isolated UI regression: empty state, reduced motion, keyboard random failure, Escape, singleton behavior
- packaged/source runtime smoke tests with no persistent QML `ERROR:` output
- visual smoke checks at 910x858 showed the intended image-first hierarchy, sparkle title, ASCII ambient animation, folder sheets, carousel depth, and liquid-metal Apply button

The latest patch added explicit handling for a failed selected-image load: the old image is cleared on `Image.Error`, a preview error is shown, and Apply is disabled. Re-run the build/check/runtime commands below after this handoff.

## Next checks Astra should run

From `/home/ilyanix/wallpick`:

```sh
nix develop -c python3 tests/check.py
nix build .#default
nix flake check
```

Then run a clean source instance (kill only Wallpick instances, never Emilia/Persona):

```sh
qs -p src kill || true
nix develop -c ./scripts/run.sh open
qs -p src log -t wallpick
```

Check for QML errors, then test:

1. Open/close/toggle and Escape.
2. Select Recent/Favorites/Konachan/Wallhaven/Gooner.
3. Select a valid image, verify preview loads, then Apply.
4. Select a missing/broken image if available; verify the preview error appears and Apply is disabled.
5. Drag, wheel, arrows, Home/End, neighboring-card click, Tab, Enter, Space, and F.
6. Trigger random actions only if needed; remember they mutate the desktop through the existing Fish backend. Restore the current wallpaper afterward if a random action is run.
7. Confirm `wallpick status` is singleton-safe and no second instance appears.

Useful packaged commands:

```sh
./result/bin/wallpick status
./result/bin/wallpick open
./result/bin/wallpick toggle
./result/bin/wallpick close
```

## Known fixes already made during review

- Random success now switches the UI source only after the action succeeds.
- Failed random fetch preserves the last-known current image and marks it uncertain.
- Recent excludes Gooner; all source matching still considers all four source folders.
- Invalid source keys are rejected.
- `fav` output is checked for its success marker rather than trusting exit status alone.
- Selected favorites receive a fresh mtime.
- Remote Fish actions have a 180-second timeout with a 5-second kill grace period.
- Carousel is bounded to nine delegates instead of instantiating the entire catalog.
- Hidden ambient effects and slider motion are gated by the popup's active state.
- Empty slider drag and stale velocity cases are guarded.
- Keyboard activation and focus styling were added to the quiet controls.
- Cursor monitor selection follows the pointer monitor when Hyprland data is available.
- Image preview keeps the old image until the new one is ready, then handles load errors explicitly.

## Remaining risks / limitations

- The existing Fish backend still owns network behavior, downloads, `awww`, `wal`, and Waybar restart. The picker cannot make those operations safer without changing the external config, which is out of scope.
- The indexed backend is PNG/JPEG only, matching `wallset`.
- `WALLPICK_PICTURES_DIR` is useful for isolated tests, but it does not redirect the existing Fish downloader destinations.
- The shader needs Qt 6 GPU rendering for the full rim effect; the software renderer should keep the button usable but cannot render the effect fully.
- If a fresh run reports `WallpaperPopup is not a type` or `WallpaperService is not a type`, stop stale source Quickshell instances and start one clean instance; `src/qmldir` already registers the popup and the service is imported from its directory.
- The cache-busting URL uses a `?v=<mtime_ns>` query on local file URLs. Verify this on the current Quickshell build; if local-file query loading fails, preserve cache invalidation with a different source revision strategy rather than removing it blindly.

## Files intentionally not touched

- `/home/ilyanix/nixos-config/**`
- Waybar configuration
- Any system generation or external flake lock

Do not delete this handoff until Astra has completed the post-patch checks and updated the user with the final verified status.
