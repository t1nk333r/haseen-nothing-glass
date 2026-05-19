# macos-widgets

macOS Tahoe / iOS 18 style widgets for KDE Plasma 6.

## Status

Phase 1: scaffolding + liquid-glass background component. One test widget (`test-glass`).

## Requirements

- KDE Plasma 6.x
- Qt 6.x with `qsb` (from `qt6-base-dev-tools`) — only needed if you rebuild shaders
- `jq`, `zip`, `kpackagetool6`

## Install

```
./install.sh test-glass          # single widget (test-* names work too)
./install.sh -a                  # all non-test widgets in packages/
./install.sh -t                  # only test-* widgets
./install.sh -a -t               # everything
```

Then add the "macOS Glass Test" widget to the desktop.

## Package

```
./build-shaders.sh               # rebuild .qsb files (commit the outputs)
./package.sh test-glass          # -> 2-packaged/test-glass-0.1.plasmoid
./package.sh -a                  # all non-test widgets
./package.sh -t                  # only test-* widgets
./package.sh -a -t               # everything
```

## Layout

- `1-common/` — shared QML components, shaders, fonts
- `packages/` — individual widget sources; each symlinks into `1-common/`
- `2-packaged/` — `.plasmoid` build outputs
- `0-images/` — screenshots per widget

## Liquid glass

`1-common/components/LiquidGlass.qml` samples `Plasmoid.containment.wallpaperGraphicsObject`, blurs it with `MultiEffect`, and runs a custom GLSL shader for edge refraction, tint, and specular. Works on desktop containments only — falls back to a flat translucent rect elsewhere (including `plasmoidviewer`).
