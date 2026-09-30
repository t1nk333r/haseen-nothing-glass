# Font licences

What every face in this directory is, where it came from, and whether this
repository may redistribute it. Read this before copying a face out of the
repo, or before shipping the plugin anywhere.

**One answer, and it now covers the whole tree.** Both faces in this directory
are **Barlow Condensed**, both are **OFL-1.1**, and both travel with the
plugin. The four **Apple** faces that used to sit beside them are gone; the
next section is the record of that, because the reason they cannot come back
is the reason they had to go.

The plugin's own code is a separate matter: GPL-3.0, `LICENSE`.

## Inventory

| File | Family (`fc-query`) | Version | Licence | Source | Redistributable here? |
|---|---|---|---|---|---|
| `barlow_medium.ttf` | Barlow Condensed — Medium | 1.408 | SIL Open Font License 1.1 | The Barlow Project Authors — <https://github.com/jpt/barlow> | **Yes**, under OFL-1.1 |
| `barlow_semibold.ttf` | Barlow Condensed — SemiBold | 1.408 | SIL Open Font License 1.1 | The Barlow Project Authors — <https://github.com/jpt/barlow> | **Yes**, under OFL-1.1 |

Nothing else states a licence for these files: there is no `OFL.txt` and no
attribution file beside them anywhere in the tree's history. What follows is
read out of the files themselves and out of each upstream project, and the
Barlow half is reproducible with `fc-query` and a `fontTools` name-table dump
— see the commands under "Barlow Condensed Medium and SemiBold".

## The Apple faces — removed 2026-09-18

Four files were removed from this directory, together with the per-widget font
directories that linked to them and every load site that named them:

| File | Family (`fc-query`) | Version | Licence | Source |
|---|---|---|---|---|
| `SF-Pro-Display-Light.otf` | SF Pro Display — Light | 16.0d18e1 | Apple San Francisco Font | Apple Inc. — <https://developer.apple.com/fonts/> |
| `sf_pro_display_regular.otf` | SF Pro Display — Regular | 16.0d18e1 | Apple San Francisco Font | Apple Inc. — <https://developer.apple.com/fonts/> |
| `sf_pro_display_thin.otf` | SF Pro Display — Thin | 16.0d18e1 | Apple San Francisco Font | Apple Inc. — <https://developer.apple.com/fonts/> |
| `sf_pro_rounded.otf` | SF Pro Rounded — Medium | 16.0d18e1 | Apple San Francisco Font | Apple Inc. — <https://developer.apple.com/fonts/> |

**Why they cannot come back.** Each file carries the **License Agreement for
the Apple San Francisco Font** in its own `name` table (ID 13, 16,596
characters, byte-identical in all four; 14,577 of those characters are the SF
Symbols per-glyph restrictions, which govern the 81 symbol-named glyphs each
face also carries).

Md5s, for recognising a copy that predates the removal — the lock plugin's
stray, a backup, an installed plugin folder old enough to hold one (2.2–2.4 MB
each, 9.2 MB together): `d2e8530d7b0f9ca7c5298263bd1a184a` (Light),
`f4245a5167ad609c4ba2d0850d553bd2` (Regular),
`5a942603c086e4c24355b64a2b160c72` (Thin),
`137ee8cda3c7f9c388e62aca25c82744` (Rounded).

Its operative grants and prohibitions, quoted verbatim:

- *"You may use the Apple Font solely for creating mock-ups of user interfaces
  to be used in software products running on Apple's iOS, iPadOS, macOS or
  tvOS operating systems, as applicable."*
- *"The grants set forth in this License do not permit you to, and you agree
  not to, install, use or run the Apple Font for the purpose of creating
  mock-ups of user interfaces to be used in software products running on any
  non-Apple operating system or to enable others to do so."*
- *"You may not embed the Apple Font in any software programs or other
  products."*
- *"You may use the Apple Font: (i) only for the purposes described in this
  License and the License Agreement for the Apple San Francisco Font; and (ii)
  only if you are a Registered Apple Developer, or as otherwise expressly
  permitted by Apple in writing."*
- There is **no grant of redistribution** anywhere in it — no right to ship
  the file onwards, in this repo, in the installed plugin, or in a release.

Apple's companion document for the surrounding assets, the *License Agreement
for Apple Design Resources* (LYL142, 06/21/2023, §2B), is blunter about the
same family, and its §1B excludes the San Francisco font from that licence and
points back at the font's own agreement — the text embedded here:

> *"You may not … make the Apple Design Resources available over a network
> where they could be run or used by multiple computers at the same time. You
> may not rent, lease, lend, trade, transfer, sell, sublicense or otherwise
> redistribute the Apple Design Resources in any unauthorized way, or enable
> others to do so."*

**Verdict: redistribution in this repository was not permitted.** The permitted
use is mock-ups of interfaces for Apple platforms; this is a Wayland desktop
shell for Arch Linux, which is the use the licence names to exclude, and the
plugin installs the files onto the user's disk. The plugin's GPL-3.0 could not
cover them, and neither the artifact nor a public clone of this repo could
carry them.

**What replaced them: the system font, not another bundled face.** The Liquid
Glass drawings now resolve their family through `MacOSColors.uiFont`, which is
the fontconfig generic alias `sans-serif` — the alias `omarchy font set`
writes, and the same value the plugin-wide `settings.systemFont` knob already
selected. Nothing was added to this directory: the operator asked for a
removal, not for a replacement face, and a metrics-close substitute is a
separate decision with its own licence. Why the alias rather than one of the
faces that are here:

- **Barlow Condensed is the wrong face for it.** It is a condensed display
  cut: it would change the genre of every glass label, and it ships only
  Medium and SemiBold, so the many call sites that ask for `Font.Light` or
  `Font.Thin` (the glass readouts' hero figures) would silently snap to
  Medium — a heavier drawing, not a substitute. Barlow stays the **Nothing**
  style's face, which is what `NTheme.sans`/`sansBold` resolve to.
- **The alias is a path that already ships.** `settings.systemFont` offered it
  in every glass widget before the removal, so the layouts were already built
  and fixed for its wider metrics (PORTING.md item 9), and `omarchy font set`
  drives it. The new default is that mode, not a new one.
- **Qt's own fallback for an unresolvable family lands on the same font**
  anyway — the app default — but only after a failed match and a diagnostic.
  Naming the alias is deterministic.

Call sites in the glass widgets name `colors.uiFont` and no longer carry a
`FontLoader` at all; the knob remains in the manifest because it still selects
between Barlow and the system font for the Nothing style. The glass clocks'
own digit face is the system font too now: it was SF Pro Rounded, and it is
one of the four files above.

**One copy is outside this repo and is not covered by this file.**
`~/.config/omarchy/plugins/t1nk33r.lock/` (a separate, hand-maintained lock
plugin) holds its own `fonts/sf_pro_display_regular.otf`, loaded by its own
`LockView.qml`, and `sync-lock-card.sh` used to mirror this
repo's copy into it. That mirror line is gone: this repo no longer has a file
to mirror. The lock plugin's copy is the operator's to settle, and it is not
part of this repository, of the installed plugin, or of a release artifact.

## Barlow Condensed Medium and SemiBold — **OFL-1.1, redistributable**

Every statement below is reproducible. `fc-query` prints the family, and the
`name` table carries the copyright, the vendor, the version and — for both
files — the licence:

```bash
cd fonts
fc-query --format='%{family}|%{style}|%{foundry}\n' *.ttf
python -c 'import sys;from fontTools.ttLib import TTFont
for f in sys.argv[1:]:
    t=TTFont(f,lazy=True)
    print("=====",f)
    print("\n".join(f"  {r.nameID}: {r.toUnicode()}" for r in t["name"].names if r.nameID in (0,4,5,8,9,13,14,16)))' *.ttf
```

Two files: `barlow_medium.ttf` (97,960 bytes, md5
`43b6c7b5a36d8a01302e1f75efe8b948`) and `barlow_semibold.ttf` (103,856 bytes,
md5 `6917d6f7470c1aedebcfa8c66b5c2a37`).

| Record | Value |
|---|---|
| `fc-query` family / style / foundry | `Barlow Condensed` / `Medium`, `SemiBold`; foundry `TRBY` |
| 0 copyright | `Copyright 2017 The Barlow Project Authors (https://github.com/jpt/barlow)` |
| 5 version | `Version 1.408` |
| 8 manufacturer / 9 designer | `Tribby Type` / `Jeremy Tribby` |
| 13 licence | `This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is available with a FAQ at: http://scripts.sil.org/OFL` |
| 14 licence URL | <http://scripts.sil.org/OFL> |

**Licence:** the SIL Open Font License 1.1, declared in the files themselves
and confirmed by the upstream project's `OFL.txt`
(<https://github.com/jpt/barlow/blob/master/OFL.txt>), whose copyright line is
the same string the fonts carry. No Reserved Font Name is declared anywhere in
it, so nothing here forces a rename of a modified copy.

**These two files are modified copies.** Upstream 1.408 (compared against
`ofl/barlowcondensed/BarlowCondensed-Medium.ttf` in the Google Fonts
catalogue, md5 `58109207d3d1ff367d2799c1574aa2bb`) has 694 glyphs and a `DSIG`
table; these have 680 and no `DSIG`, and the 14 missing glyphs are all
unencoded alternates (`a.alt`, `uni021b`, `uni0123.sc`, …). Both copies cover
the same 525 Unicode codepoints, and `Version 1.408` is unchanged, so this is
a pruning pass, not a redraw. OFL §5 keeps a modified copy under the OFL, and
§2's bundling condition is what the rest of this file exists to satisfy.

**Verdict: redistribution is permitted**, under the OFL's conditions: neither
face may be sold by itself; each copy must carry the copyright notice and this
licence; a modified copy must stay under the OFL; and the authors' names may
not be used to endorse anything. The notice half is already inside every copy
of both files — `name` IDs 0, 13 and 14 travel with the bytes, which is one of
the routes OFL §2 explicitly allows ("in the appropriate machine-readable
metadata fields"). The licence half is the appendix below, which ships beside
the faces.

## How the faces reach a user

- This directory is the source of truth **and the only copy**. The plugin ships
  exactly two font files, both here, and `omarchy plugin add` installs this
  repository as-is — there is nothing to copy, dereference or materialise, and
  no symlink anywhere in the tree. The faces reach a user because they are
  already in the plugin.
- That was not always true. Until the flattening there were three more
  directories carrying these bytes — `widgets/fonts/`, `components/nothing/fonts/`
  and a dead `widgets/tailscale/fonts` — held together with per-widget
  symlinks, and the old rsync installer materialised them into **110 font
  files carrying two faces** (118 carrying six before the four Apple files
  were removed). They are all gone; `components/nothing/NTheme.qml` and the two
  digital clocks (`widgets/clock-digital/main.qml`, `widgets/city-digital/main.qml`)
  load `Qt.resolvedUrl("../../fonts/…")` from here.
- This inventory file sits beside the faces, so the licence text travels with
  them in the repository and in every install.
- Those three sites are the only ones that load a bundled face, and all three
  load Barlow: the Nothing style's `components/nothing/NTheme.qml` registers
  both cuts with `FontLoader { source: Qt.resolvedUrl("../../fonts/…") }` and
  hands their family names to `theme.sans` / `theme.sansBold`, and the two
  digital clocks register the pair for their own digit face. No qml file under
  `widgets/` loads an Apple face or names one any more, and no glass widget
  has a `FontLoader` left: their one family is the fontconfig alias above.
- `settings.systemFont` ("Use the system font") swaps the Nothing style's
  Barlow for the desktop's own font. The Liquid Glass drawings have no second
  face to swap to and always draw in that alias; the dot-matrix displays have
  no font at all.

## Not covered by this file

This file covers `fonts/` only. Nothing in the repo states a
provenance for the following, and nothing in the files themselves does either;
if they ship, their source has to be named first:

- `icons/location.png` (388×388) and the three weather icon sets
  `icons/weather/{default,mono-dark,mono-light}/` (18 PNGs each,
  96×90). They entered this repo in `ba276ce` ("feat: icons and proper holiday
  fix", Jack Faith) at the old path `1-common/icons/weather/`, with no licence
  or attribution. Their provenance is **unestablished**; `README.md`'s claim
  that the icons come from Apple's design system is not borne out by anything
  in the files, and the two Apple design-resource documents above do not cover
  them.
- The widget-local SVGs (`widgets/now-playing/icons/*.svg`,
  `widgets/timer/widget/icons/*.svg`): plain paths, no metadata,
  no source recorded.

---

## Appendix: SIL Open Font License 1.1

*The full text, as published upstream with this font and reproduced here so the
Barlow faces ship with the licence their terms require.*

```
Copyright 2017 The Barlow Project Authors (https://github.com/jpt/barlow)

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
http://scripts.sil.org/OFL

-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```
