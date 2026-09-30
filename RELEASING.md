# Releasing Nothing Glass

Short and factual: how a release is cut, what a marketplace submission needs,
where the licence and asset facts live, and what the tags mean.

The clone root is the plugin, so the thing that ships is this repository at a
tag — not a built artifact.

## How a release is cut

1. Bump `version` in `manifest.json` and add a `## <version>` section to
   `CHANGELOG.md`.
2. `bash tests/run.sh` and `omarchy plugin validate .` — both must pass on the
   exact commit being released. (CI runs the same two, plus `qmllint` and the
   widget sweep.)
3. Tag it: `git tag v<manifest.version> && git push origin v<version>`.
4. The tag-guard CI job enforces the rest: `jq -r .version manifest.json` must
   equal `${tag#v}`, and `CHANGELOG.md` must carry a `## <version>` section.
   A tag that fails either check fails the build.

Users get the release with `omarchy plugin update t1nk33r.nothing-glass`, which
fast-forwards their checkout, re-validates it and rolls back on failure. The
fast-forward is refused only where the incoming revision would overwrite a local
change — an edit it does not touch rides through — so the installed checkout
must stay read-only all the same.

## What the marketplace submission needs

Every checkbox on the submission form is answerable from a file in this repo:

| the confirmation | where the fact lives |
|---|---|
| Install and usage are documented, including **removal** | `README.md` — `## Install` carries `omarchy plugin add`, `omarchy plugin update`, and `omarchy plugin remove` (a git checkout is deleted, a plain folder is moved to a timestamped backup, a symlink is unlinked) with the disable-and-move alternative |
| Licence and attribution are accurate | `LICENSE` (GPL-3.0-only, also `license` in `manifest.json`), and `fonts/LICENSES.md`, which inventories every bundled face with its source and redistribution answer |
| External dependencies are named | `README.md`'s `## Install`: Omarchy 4.x + Quickshell 0.3.1, optionally the `tailscale` CLI and `libnotify` |
| The plugin does not overwrite user configuration | it writes only its own `~/.config/omarchy/nothing-glass.json` and `nothing-glass-options.json`, plus its own `shell.json` entry through the shell's API. The one file outside the plugin that a project script touches is `sync-lock-card.sh`, which mirrors the prayer card into a lock plugin and no-ops when none is installed (see `PORTING.md` item 19) |
| Any bundled assets are redistributable | `fonts/LICENSES.md` (two Barlow faces, OFL-1.1) and `components/prayers/LICENSE.omaprayers` (MIT, the vendored adhan-js port) |

Submission itself is a GitHub issue on the marketplace repo, from its own
`submit-plugin.yml` form: repository URL, a category and 1-3 tags, plus
maintainer notes.

## Licence and asset inventory

- **Code:** GPL-3.0-only — root `LICENSE`, `manifest.json`'s `"license"`, and
  `README.md`'s `## Credits` all say the same thing, and `## Credits` names the
  upstream this was ported from (`jaxparrow07/liquidglass-kde-widgets`, GPL-3.0).
- **Fonts:** `fonts/LICENSES.md`. Two **Barlow Condensed** faces ship, both
  **OFL-1.1** and redistributable, with the licence text beside them. Four
  Apple faces were removed on 2026-09-18 because their own licence forbade
  redistribution; that file records what they were and why they cannot return.
- **Prayer engine:** `components/prayers/LICENSE.omaprayers` — MIT, a vendored
  offline adhan-js port.
- **Uncovered:** the weather/location icon PNGs and the widget-local SVGs carry
  no recorded source. `fonts/LICENSES.md`'s "Not covered by this file" section
  is the record.

## Tags

- The **Plasma era** was tagged `1.0` and `1.1`. Those tags stay in history and
  refer to a tree this repository no longer contains.
- The **Quickshell line** starts at **`0.1.0`**, which is the current
  `manifest.json` version. A release of this line is a tag
  `v<manifest.version>` on `master`.
- So `1.1` is **not** newer than `0.1.0` — it is from a different, retired
  product line.
