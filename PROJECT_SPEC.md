## Packaging requirement update — 2026-09-24

The user now requests one self-contained flake that anyone on the supported desktop can run without defining wallpaper scripts in their own configuration. Bundle the wallpaper backend, downloads, favorites, and required runtime dependencies. This supersedes the older requirements below to call personal Fish functions and avoid implementing downloads. Preserve the existing UI, source behavior, and folder compatibility. The external NixOS configuration and Waybar remain strictly read-only.

---

You are building a standalone wallpaper GUI project for my NixOS desktop.

==================================================
PROJECT GOAL
==================================================

Create a polished wallpaper picker / wallpaper control popup that will eventually open from the NixOS logo in my Waybar.

This is NOT a generic control center anymore.

This project is specifically a wallpaper browser / launcher / picker GUI built with:

- NixOS
- Hyprland
- Waybar
- Quickshell / QML
- Wayland only

The GUI should act as a frontend for my EXISTING wallpaper scripts and wallpaper workflow.

Do NOT reinvent the whole wallpaper backend if it already exists.
Use my existing scripts and directories as the source of truth.

==================================================
IMPORTANT CONSTRAINTS
==================================================

- Build this as a standalone project first.
- Do NOT modify my real NixOS config yet.
- Do NOT modify my Waybar config yet.
- Do NOT run nixos-rebuild.
- Do NOT run nix flake update on my main system config.
- Treat my existing NixOS config as READ-ONLY reference material.
- Do NOT install packages imperatively.
- Do NOT use React, Next.js, TSX, or a webview.
- Do NOT directly copy-paste React components from inspiration sites.
- Recreate the visual/interaction ideas natively in Quickshell/QML.

The project itself should be self-contained and clean.

==================================================
EXTERNAL REFERENCE TO INSPECT
==================================================

Inspect my existing NixOS configuration / relevant config file in READ-ONLY mode.

Path:
<REPLACE_WITH_PATH_TO_MY_NIX_CONFIG_OR_CONFIGURATION_NIX>

You should inspect it to discover:

- how the Nix logo module in Waybar currently works
- which wallpaper-related scripts / shell functions already exist
- what directories are used for wallpaper storage
- what command sets the wallpaper
- how favorites work
- whether there is already a "current wallpaper" tracking directory/file
- existing tools and conventions in my setup

Do not modify that config.
Only inspect it and reuse its logic.

==================================================
EXISTING BACKEND EXPECTATION
==================================================

Based on my config, I already have wallpaper-related commands/functions similar to these:

- wallset <path>
- fav
- wallmin
- konatag
- randomanime [tags...]
- randomwall [query...]
- randomgooner [tags...]

You must inspect the config and verify their exact behavior and paths.

Expected existing behavior:
- `wallset <path>` applies a chosen wallpaper
- `fav` saves the current wallpaper to favorites
- `randomanime` fetches a random safe anime wallpaper using tags
- `randomwall` fetches a random general wallpaper from Wallhaven using a query
- `randomgooner` exists as a separate source/mode
- there are local wallpaper directories for downloaded files
- there is likely a location tracking the current wallpaper

Do NOT reimplement external site fetching logic if my scripts already do it.
Instead, call the existing commands from the GUI.

==================================================
WHAT THE GUI SHOULD DO
==================================================

The wallpaper GUI should make my current wallpaper workflow much nicer.

Core use cases:

1. Open a popup from the Nix logo.
2. See the current wallpaper.
3. Browse wallpapers I already downloaded locally.
4. Browse categories / sources.
5. Search / enter tags for random wallpaper fetching.
6. Trigger random wallpaper commands.
7. Select a wallpaper visually.
8. Apply the selected wallpaper.
9. Favorite the current or selected wallpaper.
10. Make the whole experience feel premium and fun.

==================================================
PRIMARY UI CONCEPT
==================================================

This is an IMAGE-FIRST GUI.

It should feel like a stylish wallpaper browser, not a dashboard.

Main conceptual structure:

- Header / hero area
- Current or selected wallpaper preview
- Main wallpaper browser (Drift Slider style)
- Source/category selection
- Search / tag input
- Action buttons
- Optional recent/favorites sections
- Loading / error / empty states

The popup should feel elegant, polished, and actually useful.

==================================================
VISUAL / INTERACTION INSPIRATION
==================================================

Use https://ui.liten.design as the primary inspiration source.

IMPORTANT:
That site provides React/TSX examples.
Do NOT directly reuse React code.
Instead, study the interaction patterns and visual language, then recreate equivalent ideas natively in QML.

Use these references selectively and tastefully:

1. Ink Bleed
2. Ascii Wave
3. Liquid Metal Button
4. Folder Reveal
5. Drift Slider

==================================================
HOW TO USE EACH INSPIRATION
==================================================

1. Ink Bleed
Use this sparingly and only where appropriate.

Good uses:
- the main title, e.g. "Wallpapers" or "Wallpaper Hub"
- maybe a short featured label

Do NOT use it everywhere.
Do NOT make every heading flashy.

It should be a hero accent, not the default typography.

2. Ascii Wave
Use this as a subtle animated background layer.

Good uses:
- a faint background behind the main popup
- behind the hero/header area
- loading or empty states

It should add atmosphere, not distract from the wallpapers.
Respect reduced-motion settings.

3. Liquid Metal Button
Use this style for the PRIMARY action only.

Best use:
- Apply / Set Wallpaper

Do NOT use this style on every button.
Secondary actions should remain simpler.

4. Folder Reveal
Use this interaction style for source / folder selection.

Examples:
- Favorites
- Recent
- Konachan
- Wallhaven
- Gooner

These should feel like folder/source cards that can reveal or preview contents.

5. Drift Slider
This should be one of the CENTRAL UI elements.

Use Drift Slider as the main wallpaper browser / gallery.

It should behave like a cinematic horizontal wallpaper picker:
- selected wallpaper is dominant
- neighboring wallpapers are partially visible
- smooth drifting movement
- support mouse wheel
- support drag/swipe
- support keyboard left/right
- selected item settles clearly into place

This should be the primary way to browse wallpapers.

==================================================
VERY IMPORTANT STYLE RULE
==================================================

Do NOT overload the interface with too many flashy effects at once.

I want:
- stylish
- premium
- animated
- image-first
- cohesive

I do NOT want:
- a random collection of flashy gimmicks
- a landing page
- a web app
- an overdesigned toy UI
- visual chaos

Use the special effects selectively and with restraint.

==================================================
SELECTION VS APPLICATION
==================================================

Selecting a wallpaper and applying a wallpaper must be separate actions.

Behavior:

1. User browses wallpapers in the slider
2. User selects one
3. Large preview updates
4. User presses Apply
5. GUI calls `wallset <path>`

Do NOT apply a wallpaper instantly just because it became selected in the slider.

Selection should be safe and reversible.
Application should be explicit.

==================================================
DATA SOURCES / LOCAL DIRECTORIES
==================================================

Inspect my existing config and discover the actual wallpaper directories.

Use those real directories rather than inventing new ones if possible.

There are likely directories similar to:

- ~/Pictures/random_konachan/
- ~/Pictures/random_wallhaven/
- ~/Pictures/random_gooner/
- ~/Pictures/favorite/
- ~/Pictures/.current-wallpaper/

Inspect and confirm.

The app should be able to read wallpapers from the actual folders it finds.

If exact paths need to be configurable, centralize them in one config module.

Do not scatter hardcoded personal paths across the codebase.

==================================================
CORE FEATURES
==================================================

Implement these features for version 1:

A. OPEN/CLOSE
- popup window
- top-right placement suitable for opening under Waybar
- borderless / overlay behavior
- singleton instance
- IPC support for toggle/open/close/status

B. CURRENT WALLPAPER
- show a preview of the current wallpaper
- if there is a known current wallpaper file/path, use that
- visually indicate which wallpaper is currently applied

C. MAIN BROWSER
- main wallpaper browser uses Drift Slider style
- selected wallpaper preview
- support browsing local wallpapers from selected source/folder

D. SOURCES / CATEGORIES
Create a source/folder chooser using Folder Reveal-inspired UI.

Suggested sources:
- Favorites
- Recent
- Konachan
- Wallhaven
- Gooner

Only show sources that actually map to real underlying folders or workflows.

E. SEARCH / TAG INPUT
There should be an input box for search/tags.

Behavior:
- when source/mode is anime → input becomes tags for `randomanime`
- when source/mode is general → input becomes query for `randomwall`
- when source/mode is gooner → input becomes tags for `randomgooner`

Support examples like:
- rezero emilia -chibi
- dark forest
- cyberpunk rain

F. RANDOM ACTIONS
Provide buttons/actions for:
- Random Anime
- Random General
- Random Gooner (if appropriate and present in config)

These should call the existing scripts asynchronously.

G. APPLY
Use a Liquid-Metal-style primary Apply button.
It should apply the selected wallpaper via `wallset <path>`.

H. FAVORITE
Allow favoriting using the existing `fav` command if that corresponds to current wallpaper favorite behavior.
Also, if practical, allow favoriting directly from a selected wallpaper by applying then favoriting, or by a dedicated file-copy flow if that matches my scripts.

I. GALLERY / RECENT / FAVORITES
The app should support browsing:
- Favorites
- downloaded anime wallpapers
- downloaded general wallpapers
- downloaded gooner wallpapers
- optionally recent/current sources

J. LOADING / ERRORS
Show clear loading states when random wallpaper commands are running.
Show errors if commands fail.
Do not freeze the UI.

==================================================
WINDOW / LAYOUT
==================================================

The popup should feel like a premium media browser.

Approximate layout:

- top header with title
- main preview area
- source/folder area
- main Drift Slider gallery
- search/tags input
- action row
- optional metadata/status row

Popup should be visually balanced and not cramped.

Suggested width:
~700 to 1000 px depending on layout

Suggested height:
enough to comfortably show preview + slider + controls

This should not feel like a tiny widget anymore.
It should feel like a proper wallpaper picker.

==================================================
HEADER
==================================================

Use Ink Bleed style sparingly for the main title only, or for one short featured text element.

Examples:
- Wallpapers
- Wallpaper Hub

Add a more normal subtitle/status line if useful, such as:
- source name
- number of wallpapers
- currently selected file name
- last updated state

==================================================
BACKGROUND
==================================================

Use Ascii Wave subtly in the background.

This should:
- add atmosphere
- help the popup feel alive
- not interfere with reading image content

Keep it restrained.

==================================================
MAIN PREVIEW
==================================================

There should be a larger preview area for the currently selected wallpaper.

This area is important.

It should:
- show the selected wallpaper prominently
- clearly distinguish selected wallpaper from the rest of the gallery
- possibly show metadata like filename or source
- visually feel like the focal point of the interface

Do not make it too tiny.

==================================================
MAIN GALLERY / DRIFT SLIDER
==================================================

This is a key part of the experience.

Implement a Drift Slider-like wallpaper carousel in QML.

Requirements:
- horizontal browsing
- selected item centered or clearly emphasized
- adjacent items partially visible
- smooth motion
- support mouse drag
- support mouse wheel
- support keyboard arrows
- clear selected state
- no immediate auto-apply
- efficient enough for image thumbnails

Use real thumbnail/previews if practical.
If thumbnail caching is needed, implement it sensibly.

==================================================
FOLDER / SOURCE SELECTOR
==================================================

Use Folder Reveal style inspiration for the source/category selector.

Examples:
- Favorites
- Recent
- Konachan
- Wallhaven
- Gooner

These source cards should:
- be visually distinct
- reveal preview / count / content hints
- feel animated and tactile
- be usable by mouse and keyboard

Do not make them giant or gimmicky.
They should support the main flow.

==================================================
ACTIONS
==================================================

Action priority:

Primary:
- Apply (Liquid Metal Button)

Secondary:
- Random Anime
- Random General
- Random Gooner
- Favorite
- Open Folder (optional)
- Refresh (optional)

Secondary actions should be visually simpler than Apply.

==================================================
KEYBOARD / INPUT
==================================================

Support useful keyboard interactions:

- Esc → close popup
- Left/Right → move slider
- Enter → Apply selected wallpaper
- F → favorite
- R → random (context-sensitive or open random menu)
- Tab → move focus
- typing in search input should work naturally

Mouse interaction must also work well.

==================================================
IPC / FUTURE WAYBAR INTEGRATION
==================================================

Implement IPC commands, such as:
- open
- close
- toggle
- status
- random-anime
- random-wall
- random-gooner (if appropriate)

Future Waybar integration idea:

- Left click on Nix logo → open wallpaper GUI
- Middle click → randomanime
- Right click → fav

Do NOT modify Waybar yet.
Just make the project ready for that integration and document what will be needed later.

==================================================
PERFORMANCE / ROBUSTNESS
==================================================

- Do not block the UI thread
- run shell commands asynchronously
- handle command failures gracefully
- do not crash if a folder is missing
- do not crash if no wallpapers are present
- do not assume every external command succeeds
- do not spam expensive processes repeatedly
- image loading should be reasonably efficient

==================================================
ARCHITECTURE
==================================================

Keep the project modular and maintainable.

Suggested high-level structure:

nix-wallpaper-gui/
├── flake.nix
├── flake.lock
├── README.md
├── src/
│   ├── shell.qml
│   ├── WallpaperPopup.qml
│   ├── components/
│   │   ├── HeroHeader.qml
│   │   ├── DriftWallpaperSlider.qml
│   │   ├── FolderSourceCard.qml
│   │   ├── ApplyButton.qml
│   │   ├── SearchBar.qml
│   │   └── ...
│   ├── services/
│   │   ├── WallpaperService.qml
│   │   ├── SourceService.qml
│   │   ├── CommandService.qml
│   │   └── ...
│   ├── theme/
│   │   └── Theme.qml
│   └── config/
│       └── AppConfig.qml
└── scripts/
    └── ...

Do not create pointless abstraction layers.
Do not cram everything into one huge QML file.

==================================================
THEME / STYLING
==================================================

Centralize:
- colors
- spacing
- corner radii
- animation timings
- typography
- effect intensity

The GUI should feel:
- modern
- dark
- media-focused
- premium
- slightly futuristic
- visually coherent

Not:
- overdecorated
- noisy
- web-dashboard-like
- random

==================================================
QML IMPLEMENTATION NOTE
==================================================

You are building this in Quickshell/QML.

The visual inspiration comes from liten, but the implementation must be QML-native.

That means:
- port the visual concepts
- simplify where needed
- preserve the spirit, not the exact React source
- use QML animation systems appropriately
- respect reduced-motion where practical

==================================================
NIX / DEV ENVIRONMENT
==================================================

Make this a proper standalone Nix flake.

I want to be able to do something like:
- nix develop
- nix run

Declare dependencies in the flake.
Do not assume FHS paths.
Do not use /usr/bin hardcoded paths.

==================================================
README
==================================================

Write a README that includes:
- what the project is
- how it works
- how it uses my existing wallpaper scripts
- how to configure the path to my external NixOS config if needed
- how to configure wallpaper directories if needed
- how to run the app
- IPC command examples
- current limitations
- future Waybar integration instructions

==================================================
WORKFLOW
==================================================

Before implementing:

1. inspect this project directory
2. inspect my external NixOS config / configuration.nix in READ-ONLY mode
3. identify:
   - existing wallpaper commands
   - existing wallpaper directories
   - current wallpaper tracking mechanism
   - existing Nix logo Waybar click behavior
4. summarize what you found
5. explain the planned architecture
6. explain where each liten-inspired concept will be used:
   - Ink Bleed
   - Ascii Wave
   - Liquid Metal Button
   - Folder Reveal
   - Drift Slider
7. list the files you plan to create
8. then implement

Do not ask me questions that can be answered by inspecting the config.

If something truly cannot be determined, make it configurable in one place.

==================================================
TESTING
==================================================

After implementation:

1. validate QML syntax
2. run the application
3. fix runtime errors
4. test opening and closing
5. test the slider behavior
6. test loading wallpapers from actual folders
7. test selecting a wallpaper
8. test Apply via wallset
9. test randomanime
10. test randomwall
11. test randomgooner if available
12. test favorite behavior
13. test behavior when a source folder is empty
14. test behavior when a command fails
15. test IPC commands
16. ensure repeated toggles do not create duplicate windows/processes

Do not modify my actual system config as part of testing.

# ART DIRECTION ADDENDUM

This section is mandatory.

The main danger for this project is producing a generic AI-generated dashboard or a random collection of flashy components.

Avoid that completely.

The wallpaper picker should feel like a deliberately art-directed, premium image browser.

## CORE PRINCIPLE

The wallpapers themselves are the main visual content.

UI chrome exists to support the images, not compete with them.

Every design decision should reinforce this hierarchy:

1. selected wallpaper
2. wallpaper browsing
3. primary action
4. source/search controls
5. secondary metadata

If decorative UI becomes more visually dominant than the wallpaper itself, simplify it.

## IMAGE-FIRST DESIGN

The selected wallpaper should be the strongest visual element in the interface.

Prefer:
- large image areas
- cinematic proportions
- partial neighboring images
- subtle overlays
- controls integrated around imagery

Avoid:
- large blocks of text
- generic cards
- dashboard metrics
- unnecessary panels
- empty decorative containers

This is a media browser, not a settings application.

## LITEN DESIGN LANGUAGE

Use liten.design as the primary animation and micro-interaction reference library.

The following references are intentional parts of the art direction:

### Ink Bleed

Use only for one short hero element.

Good:
- "Wallpapers"
- a short selected source title

Bad:
- every section heading
- filenames
- metadata
- buttons
- paragraphs

Keep the effect elegant and restrained.

### Ascii Wave

Use as an ambient layer.

It should live visually behind content and have low contrast.

It must never make wallpaper thumbnails difficult to see.

The wave may become slightly more visible:
- while loading
- when no wallpaper is selected
- in an empty-state view

Do not turn the entire interface into an ASCII aesthetic.

### Drift Slider

This is the most important interaction reference.

Treat it as the centerpiece of the wallpaper browsing experience.

The slider should feel physical and fluid:
- smooth drag
- subtle inertia
- neighboring wallpaper visibility
- selected image emphasis
- elegant settling animation

Do not implement a generic horizontal ListView and call it finished.

Recreate the visual behavior and motion quality of a polished drift-style carousel.

Pay close attention to:
- scale
- opacity
- spacing
- depth
- momentum
- easing
- selected position

The movement should feel intentional rather than mechanical.

### Folder Reveal

Use Folder Reveal for navigating wallpaper collections/sources.

Potential collections:
- Favorites
- Recent
- Konachan
- Wallhaven
- Gooner

The folders should feel physical and responsive.

Hover/focus:
- reveal previews subtly

Click:
- select/open the source

If possible, use actual wallpaper thumbnails as the sheets/previews revealed from the folder rather than generic fake paper rectangles.

Do not make the folder selector dominate the interface.
It is navigation, not the main content.

### Aurora Button

Use this treatment ONLY for the primary wallpaper action:

Apply / Set Wallpaper

The button should feel special because applying the wallpaper is the final committed action.

Do not reuse the Aurora Button treatment for:
- random buttons
- favorite
- source navigation
- refresh
- close
- search actions

Those should use quieter styling.

The Aurora button should look premium rather than huge or obnoxious.

## OTHER LITEN REFERENCES

You may inspect other components and animation examples from liten.design when they solve a specific interaction problem.

Examples might include:
- Image Reveal Mask for image transitions
- Tessera Loader for fetching wallpapers
- Frost Pane for localized translucent surfaces
- Toast for success/error feedback
- subtle reveal animations for source changes

However:

DO NOT add a component simply because it looks cool.

Every borrowed idea must have a clear UX purpose.

Before adopting another liten effect, ask:

"Does this improve wallpaper browsing, selection, loading, navigation, or feedback?"

If not, do not use it.

## VISUAL RESTRAINT

Never show all special effects at maximum intensity simultaneously.

Example:

While simply browsing:
- subtle Ascii Wave
- Drift Slider active
- Sparkle title mostly calm
- Folder Reveal idle
- Liquid Metal Apply button available

When a Folder Reveal animation happens:
- do not simultaneously trigger major hero effects

When Apply is pressed:
- Liquid Metal gets temporary visual emphasis
- other ambient effects remain subdued

Think in terms of visual focus.

Only one interaction should demand attention at a time.

## COLOR

Derive the base palette from my existing desktop configuration where practical.

The UI should mostly use:
- deep neutral background
- soft foreground
- muted borders
- one main accent
- restrained secondary accent

Allow wallpaper imagery to provide most of the color.

Avoid:
- rainbow UI
- excessive neon
- overly saturated gradients
- every control using a different accent

## TRANSPARENCY / BLUR

Transparency is allowed, but use it carefully.

The wallpaper must remain readable against whatever is behind the popup.

Prefer:
- controlled dark translucent surfaces
- localized blur
- subtle border separation

Avoid:
- extremely transparent panels
- huge blur radii everywhere
- glassmorphism for its own sake

## SPACING

Use generous space around the selected wallpaper.

Use tighter spacing around secondary controls.

The UI should breathe without wasting space.

Avoid:
- giant empty regions
- compressed control clusters
- uniform spacing everywhere

Spacing should communicate hierarchy.

## TYPOGRAPHY

Use typography minimally.

Primary:
- short hero/title

Secondary:
- selected filename/source

Tertiary:
- metadata/status

Do not display unnecessary technical information by default.

For example, do not show:
- full filesystem paths
- long API URLs
- command output

unless the user explicitly opens a details/debug view.

## WALLPAPER TRANSITIONS

Changing the selected image should feel polished.

Do not simply swap image sources instantly.

Use subtle transitions inspired by liten media/reveal components.

Possible techniques:
- mask reveal
- crossfade
- slight translation
- subtle scale transition

Keep them fast enough that browsing remains responsive.

## FEEDBACK

Actions must provide clear feedback.

Examples:

Favorite:
- small animated acknowledgment
- source state updates

Random fetch:
- tasteful loader
- then reveal new wallpaper

Apply:
- Liquid Metal interaction
- success toast/status
- current wallpaper marker updates

Error:
- concise non-intrusive error state
- do not destroy the current browsing state

## FINAL QUALITY BAR

Before considering the UI finished, ask:

- Does this look like a wallpaper experience rather than a dashboard?
- Is the selected wallpaper the visual focus?
- Does every animation serve an interaction?
- Are the liten inspirations recognizable without looking copied?
- Does the UI still look coherent when all animations stop?
- Is there unnecessary decoration that can be removed?
- Does the project have a distinct visual identity?

If the answer to the last question is no, refine the art direction before adding more features.

==================================================
FINAL RESPONSE
==================================================

When done, report:

1. what you built
2. what files were created
3. how the app is structured
4. how it integrates with my existing wallpaper scripts
5. what exact directories/commands were detected from my config
6. how to run it
7. how to test IPC
8. what still needs to be changed later in Waybar/NixOS config for final integration
9. any limitations or assumptions

Again:
do not modify my actual NixOS config yet.
Build the standalone wallpaper GUI first.
