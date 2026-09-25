# Agent Instructions

- Read PROJECT_SPEC.md completely before modifying anything.
- PROJECT_SPEC.md defines what the application should do.
- This file defines how you must work on the project.
- Treat the external NixOS configuration as strictly read-only.
- Do not modify Waybar or the main NixOS configuration until explicitly asked.
- Do not run nixos-rebuild.
- Do not run nix flake update on the external configuration.
- Do not install dependencies imperatively.
- Keep the implementation native to Quickshell / Qt Quick / QML.
- Test changes before claiming completion.
- Do not silently simplify major visual or functional requirements.
- When a referenced liten component has public source code, inspect that source before implementing the QML equivalent. Do not implement from memory or from the component name alone.


# LITEN FIDELITY REQUIREMENT

The referenced liten.design components are not merely loose visual inspiration.

Recreate their visual behavior and animation principles as faithfully as reasonably possible in native QML.

Do not replace them with generic approximations simply because the original implementation uses React.

Study the actual source implementation of each referenced liten component before implementing its QML counterpart.

Preserve, where applicable:

- animation timing
- easing/spring behavior
- geometry
- layering
- interaction states
- seeded/random behavior
- motion relationships
- visual hierarchy
- hover/focus/click behavior

Port algorithms and mathematical behavior where possible.

Do not copy React/TSX syntax into the project.
Translate the implementation to Qt Quick/QML primitives.

Specific requirements:

## Ink Bleed

Faithfully reproduce the original layered approach:

- metallic/chrome text layer
- blurred bloom layer
- independent four-point sparkle particles
- deterministic seeded sparkle placement
- different sparkle sizes
- independent delays and durations
- subtle breathing bloom

Do not replace this with a normal glowing Text element.

## Ascii Wave

Port the actual procedural animation concept.

Prefer QML Canvas.

Preserve:
- value-noise driven wave
- flowing rather than per-frame random glyphs
- configurable character density ramp
- cell size
- speed
- spread
- accent-to-bright-core appearance

The result should visibly behave like the liten Ascii Wave rather than generic animated ASCII noise.

## Folder Reveal

Preserve the original interaction concept:

- closed folder
- sheets fan outward on hover/focus
- staggered sheet movement
- symmetrical sheet placement
- individual sheet rotation
- vertical lift
- front pocket opening motion
- click can pin/select the folder

Where possible, use actual wallpaper thumbnails as the revealed sheets.

## Drift Slider

Treat the original Drift Slider behavior as the quality target.

Do not implement a plain horizontal ListView and call it Drift Slider.

Reproduce:
- physical-feeling drag
- neighboring items remaining visible
- depth through scale/opacity/position
- smooth settling
- momentum
- selected item emphasis
- polished spring/easing behavior

## Liquid Metal Button

This component has the highest fidelity requirement.

Do not replace it with:
- a silver gradient
- a glowing border
- a generic animated gradient

Recreate the liquid/chromatic metallic rim effect.

Use QML ShaderEffect / shaders if necessary to reproduce:
- metallic/chrome rim
- distorted liquid motion
- chromatic dispersion
- moving specular highlight
- hover interaction
- pressed interaction

A custom shader is acceptable and preferred if normal QML primitives cannot reproduce the effect accurately.

Performance must remain reasonable.

## General

When an original web primitive does not directly exist in Qt Quick:

1. understand what visual operation it performs;
2. choose the closest Qt Quick primitive;
3. use Canvas or ShaderEffect where necessary;
4. preserve the observable result rather than merely simplifying it away.

Visual fidelity to the referenced components is more important than implementation similarity.
