# Changelog

Releases of this plugin are tags `v<manifest.version>` on `master`. The
**Quickshell line starts at `0.1.0`** — the two older tags, `1.0` and `1.1`,
belong to the retired KDE Plasma applet tree and are **not** newer than
anything below; they are history, not a version to compare against.

## 0.1.0

The first release of the Quickshell line: a single Omarchy plugin,
`t1nk33r.nothing-glass`, drawing desktop widgets on the Hyprland desktop in two
styles from one runtime — Liquid Glass, whose material refracts the real
wallpaper through a shader, and Nothing OS, the monochrome dot-matrix drawing
of the same widgets.

- 24 widget types (clocks, world clocks, weather, calendar, timer, now
  playing, prayer times, sunrise, Tailscale, performance, media servers, usage
  tiles, battery, network, storage, photos) plus three dev tiles.
- Per-instance placement, sizing and settings, a right-click settings sheet,
  a bar control panel and a widget browser launcher — all also reachable over
  the plugin's IPC surface.
- Plugin-wide appearance knobs (corner radius, refraction, blur, tint,
  dispersion, specular), per-category styles, and Omarchy theme following.
- The clone root is the plugin: install with `omarchy plugin add
  https://github.com/t1nk333r/t1nk33r.nothing-glass.git`, update with
  `omarchy plugin update t1nk33r.nothing-glass`.
- Private by default: the sunrise tile's GeoClue lookup is an opt-in, off
  unless *Ask GeoClue for the location* is turned on, and turning it off
  takes effect even mid-lookup; the calendar's empty state never draws a path
  containing the account name; the README's *Network and privacy* section
  documents the tiles' network activity, including the remote cover art a
  player can point Now Playing at.
- `add <type> ""` places the widget on the focused monitor, as documented.
