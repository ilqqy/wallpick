# Wallpick

A native Quickshell / Qt Quick wallpaper browser with a bundled backend. One Nix flake supplies the UI, wallpaper downloads, favorites, image validation, and `awww`. No Fish functions or personal NixOS scripts are required.

Designed and tested on **NixOS + Hyprland**. It requires a running Wayland session with layer-shell support; GNOME/KDE and X11 are not supported targets. Other compatible Wayland compositors may work, but Hyprland-specific monitor selection and outside-click dismissal are not guaranteed there.

## Run

From this checkout:

```sh
nix run .
nix run . -- toggle
nix run . -- close
nix run . -- status
nix run . -- stop
```

Or run a checkout from elsewhere with `nix run /path/to/wallpick`. This project does not need to be added to your system flake to try it.

The package includes all backend executables. On the first Apply or remote Random action, Wallpick reuses a running `awww-daemon`, or starts its bundled daemon and waits for it to become ready. Closing the popup leaves the wallpaper and daemon running. The daemon is not installed as an autostart service; start Wallpick again in each session when needed. Avoid running a competing wallpaper daemon on the same outputs.

Build without launching:

```sh
nix build .
./result/bin/wallpick open
```

## Install declaratively

Add this flake as an input to your own flake (use the checkout's absolute path, or its repository URL after publishing):

```nix
inputs.wallpick.url = "path:/absolute/path/to/wallpick";
```

For NixOS, include the module in your system's module list:

```nix
modules = [
  inputs.wallpick.nixosModules.default
  { programs.wallpick.enable = true; }
];
```

For Home Manager, include its module in your home configuration:

```nix
imports = [ inputs.wallpick.homeManagerModules.default ];
programs.wallpick.enable = true;
```

Use either module, or add `inputs.wallpick.packages.${pkgs.stdenv.hostPlatform.system}.default` to `environment.systemPackages` / `home.packages` directly. The modules install the package and desktop entry; they do not alter Waybar, compositor bindings, or services. Packages are exposed for x86_64-linux and aarch64-linux; runtime testing was performed on x86_64-linux.

## Browsing and Random

- Selecting an image updates the large preview. **Apply wallpaper** commits it to the desktop after its preview has loaded.
- Every category has a **Random** button. **Recent / Favorites** choose a different saved image when possible, for preview only. **Konachan / Wallhaven / Gooner** download and apply immediately.
- The tag/query field is used by remote Random buttons. Examples: `rezero emilia -chibi`, `dark forest`. Konachan resolves keywords into popular tags; negative tags are supported.
- Konachan uses the safe endpoint and rating. Wallhaven uses general, SFW, 16:9/16:10 results. Gooner is a separate questionable-rating Konachan mode; its images are excluded from Recent.
- Favorite saves the selected image, or the current wallpaper when appropriate, without applying it.
- Current-desktop tracking is updated only after a successful apply. Failed downloads do not erase it.

Sources are available even before their directories exist. The backend creates destination directories as needed.

| Collection | Default path |
| --- | --- |
| Favorites | `~/Pictures/favorite` |
| Konachan | `~/Pictures/random_konachan` |
| Wallhaven | `~/Pictures/random_wallhaven` |
| Gooner | `~/Pictures/random_gooner` |
| Current marker | `~/Pictures/.current-wallpaper` |

These paths preserve compatibility with the original workflow. Wallpick neither reads nor requires the original NixOS configuration. Existing Fish commands remain independent; the packaged UI no longer invokes them.

## Configuration

Set environment variables **before starting** the app. If it is already running, use `wallpick stop` first.

| Variable | Default | Meaning |
| --- | --- | --- |
| `WALLPICK_PICTURES_DIR` | `~/Pictures` | Root for all browsing, downloads, favorites, and current tracking |
| `WALLPICK_MIN_WIDTH` | `1920` | Minimum remote wallpaper width |
| `WALLPICK_MIN_HEIGHT` | `1080` | Minimum remote wallpaper height |
| `WALLPICK_PYWAL` | `0` | Set to `1` to generate a palette using bundled pywal after applying |
| `WALLPICK_REDUCED_MOTION` | `0` | Set to `1` to disable ambient and spring motion |

For example:

```sh
WALLPICK_PICTURES_DIR="$HOME/Pictures/Wallpick" nix run .
WALLPICK_PYWAL=1 nix run .
```

Palette generation is optional and does not restart Waybar. Applications that consume pywal colors need their own reload integration. No API keys are required for the bundled public sources; availability and rate limits are controlled by those services.

## Command line and IPC

The following commands run the bundled backend directly, wait for completion, and return a failure exit code if the operation fails:

```sh
wallpick apply /absolute/path/to/image.png
wallpick favorite
wallpick fetch anime rezero -chibi
wallpick fetch general dark forest
wallpick fetch gooner tags
```

The UI commands are asynchronous:

```sh
wallpick open
wallpick toggle
wallpick close
wallpick status
wallpick refresh
wallpick random-anime
wallpick random-wall
wallpick random-gooner
```

For development IPC:

```sh
qs -p "$PWD/src" ipc call wallpick status
qs -p "$PWD/src" ipc call wallpick operationStatus
qs -p "$PWD/src" ipc call wallpick randomSource favorites
```

Other IPC methods: `selectSource`, `selectIndex`, `selectedPath`, `applySelected`, `favoriteSelected`, `randomAnime`, `randomWall`, and `randomGooner`.

A stable [Quickshell ShellId](https://quickshell.org/docs/v0.3.0/guide/advanced/#shellid) lets the launcher find Wallpick across package paths. The launcher addresses that instance explicitly, because Quickshell's path-based duplicate check alone does not prevent duplicates across upgrades. Stop the running instance before starting a new version or switching between packaged and development code.

## Keyboard

Esc closes. Left/Right and Home/End browse. Enter applies once the preview is ready (or fetches when the tag field has focus). F favorites. R uses the selected category's Random action. Tab reaches source cards, Random buttons, gallery, input, and action controls.

## Development and tests

```sh
nix develop
./scripts/run.sh open
./scripts/run.sh foreground
python3 tests/actions_test.py
python3 tests/check.py
nix flake check
nix build .
# Stop any running Wallpick first; needs a Wayland session:
python3 tests/package_check.py
```

Backend tests use temporary directories, mocked network responses, and mocked wallpaper commands. UI tests use temporary collections and a fake action backend. Popup tests briefly open a fixture window and require a Wayland session. Tests do not apply a real wallpaper. The flake check runs the backend suite without a desktop or network connection.

The shader is compiled by the development launcher and package build. Full liquid-metal rendering needs Qt 6 GPU rendering; software rendering keeps the controls usable.

## Optional Waybar integration

After installing the package, use `wallpick toggle` as a click action, `wallpick random-anime` for random anime, and `wallpick favorite` for the current wallpaper. Invoke the installed binary rather than evaluating `nix run` on every click. This project does not modify Waybar or rebuild your system.

## Limits

- PNG and JPEG are supported.
- Remote actions need internet access and depend on the public providers.
- Wallpaper rendering requires the Wayland protocols supported by awww and Quickshell.
- No automatic system/session service is installed. The wallpaper daemon is started on demand.
# wallpick
