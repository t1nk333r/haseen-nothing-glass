import QtQuick
import "../../components"

// Filesystem use, Liquid Glass.
//
// The glass twin of widgets-nothing/storage/main.qml, and it carries the same
// set of facts: StorageData owns the only poll in the set (one short `df` per
// minute), and its `active` is bound to this widget's `visible` below, so a
// tile scrolled off a workspace stops spawning processes entirely. There is no
// timer and no second `df` in this file.
//
// StorageData is mounted with `mounts` and does the filtering as a binding on
// the parsed rows (PORTING.md item 24), so editing `storageMounts` re-filters
// on the spot rather than at the next poll - which is also why the chosen
// subset is derived here and passed in, never filtered again below.
//
// The accent carries exactly ONE meaning, as in the Nothing drawing: a
// filesystem at 90% or more. `colors.accentRed` appears in two places for that
// one fact - the FULL word in the header and the meter of the filesystem it
// applies to - and nowhere else. A large mount, a missing mount point and a
// host where every filesystem was filtered out are never red.
//
// Three layouts, one per grid preset (WidgetRegistry.sizes):
//   192x192   the mount point, its used percentage as the hero, the used and
//             total sizes, and one meter; FULL when it applies.
//   400x192   the list: one row per mount, name, sizes and a thin meter.
//   400x400   the same list, with the family's larger type and rows.
//
// Facts first, layout second: the Nothing drawing carries the same set, and a
// new figure in StorageData belongs on both.
Item {
    id: full
    anchors.fill: parent

    MacOSColors {
        id: colors
        styleMode: plugin.settings.styleMode
        appearance: plugin.settings.appearance
        systemBackground: theme.systemBackground
        themePalette: theme.palette
    }

    // Which filesystems to show, from `storageMounts`: a comma-separated list
    // of mount points, in the order they should appear. Empty = every real
    // filesystem, biggest first, which is what an unconfigured tile shows -
    // and is also how you find the exact strings to type here, since the
    // unfiltered list names them.
    readonly property var chosenMounts: {
        var raw = String(plugin.settings.storageMounts || "")
        var out = []
        var parts = raw.split(",")
        for (var i = 0; i < parts.length; i++) {
            var m = parts[i].trim()
            // A trailing slash is what a path completion leaves behind, and
            // `df` never reports one except for "/" itself.
            while (m.length > 1 && m.charAt(m.length - 1) === "/") m = m.substring(0, m.length - 1)
            if (m !== "") out.push(m)
        }
        return out
    }

    StorageData {
        id: store
        mounts: full.chosenMounts
        // An off-screen tile costs nothing - see the component's header.
        active: full.visible
    }

    // A named mount that `df` does not report - a typo, or a drive that is
    // not mounted right now - would otherwise show as a blank tile.
    readonly property bool mountMissing: store.loaded
        && store.entries.length === 0 && full.chosenMounts.length > 0

    readonly property bool ready: store.loaded && store.entries.length > 0
    readonly property int primaryPercent: full.ready ? store.primary.usedPercent : 0
    readonly property bool primaryFull: full.ready && full.primaryPercent >= 90

    readonly property int maxPercent: {
        var m = 0
        for (var i = 0; i < store.entries.length; i++)
            m = Math.max(m, store.entries[i].usedPercent)
        return m
    }

    // The family's one type and margin scale - see components/GlassScale.qml.
    // The id is `gscale` and not `scale` on purpose: `scale` is Item's own
    // transform property, and inside a Repeater delegate an unqualified outer
    // id loses to it - every delegated text then silently falls back to the
    // default pixel size.
    GlassScale {
        id: gscale
        tileWidth: full.width
        tileHeight: full.height
    }

    LiquidGlass {
        id: glass
        anchors.fill: parent
        wallpaperItem: backdrop.item
        radius: plugin.settings.cornerRadius
        roundness: plugin.settings.roundness
        refractThickness: plugin.settings.refractThickness
        refractIOR: plugin.settings.refractIOR
        refractScale: plugin.settings.refractScale
        tint: colors.glassTint
        tintAlpha: plugin.settings.tintAlpha
        chromaStrength: plugin.settings.chromaStrength
        specStrength: plugin.settings.specStrength
        blurRadius: plugin.settings.blurRadiusPx
        realtimeRefraction: plugin.settings.realtimeRefraction
        fallbackOpacity: colors.glassFallbackOpacity
        solidMode: colors.isSolid && plugin.settings.opaqueBackground
        solidColor: colors.solidBackground
    }

    // ── Layout state ─────────────────────────────────────────────────────
    readonly property bool isWide: gscale.isWide
    readonly property bool isBig: gscale.isBig
    // 192 shows one number; both 400-wide tiles have room for the list.
    readonly property bool isList: full.isWide || full.isBig

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: gscale.pad

        // ── One row of the list, sized once ────────────────────────────
        // Name line, air, meter - the same three parts the wide and large
        // presets both draw, so the row height is computed from them rather
        // than written as a literal that can drift from its own contents.
        readonly property real barH: Math.max(3, Math.round(gscale.tight * 0.36))
        readonly property real rowNameH: Math.round(gscale.body * 1.25)
        readonly property real rowAir: Math.max(2, Math.round(gscale.tight * 0.25))
        readonly property real rowH: body.rowNameH + body.rowAir + body.barH

        // ── Header ──────────────────────────────────────────────────────
        // Small tile: the mount point is the label, because the number below
        // it belongs to exactly one filesystem.
        Text {
            id: header
            text: (!full.isList && full.ready) ? store.primary.mount : "Storage"
            color: colors.foreground
            opacity: 0.75
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            font.letterSpacing: gscale.micro * 0.10
            elide: Text.ElideRight
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: badge.visible ? badge.left : parent.right
            anchors.rightMargin: badge.visible ? gscale.gap : 0
        }

        // The one red thing a tile can carry: a filesystem that is 90% or
        // more full. The list's worst meter is the same fact, drawn once more.
        Text {
            id: badge
            visible: full.ready && (full.isList ? full.maxPercent >= 90 : full.primaryFull)
            text: "FULL"
            color: colors.accentRed
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            font.letterSpacing: gscale.micro * 0.14
            font.weight: Font.DemiBold
            anchors.top: parent.top
            anchors.right: parent.right
        }

        // ── Footer ──────────────────────────────────────────────────────
        // Small: the primary filesystem's sizes over its own meter.
        // Wide/large: how many mounts are listed, and the worst of them.
        Item {
            id: footer
            visible: full.ready
            x: 0
            width: body.width
            height: full.isList
                ? summary.implicitHeight
                : (sizes.implicitHeight + gscale.gap + body.barH)
            y: Math.max(0, body.height - footer.height)

            Text {
                id: sizes
                visible: !full.isList
                text: full.ready
                    ? store.primary.usedLabel + " / " + store.primary.sizeLabel
                    : ""
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                anchors.top: parent.top
                anchors.left: parent.left
            }

            // The primary filesystem's meter: the used fraction of the whole,
            // as a track with a fill on it.
            Rectangle {
                id: primaryTrack
                visible: !full.isList
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: body.barH
                radius: height / 2
                // The channel, not a divider: a meter whose empty part cannot
                // be seen says nothing about how much room is left, and a
                // filesystem with 0% used would then draw no meter at all.
                // Foreground at 0.20 is the family's track weight
                // (now-playing's MusicSlider passes the same value as
                // `trackOpacity`), and is the glass reading of the Nothing
                // drawing's `onFaint` channel in NProgress.
                color: colors.foreground
                opacity: 0.20
            }
            Rectangle {
                visible: !full.isList
                anchors.left: primaryTrack.left
                anchors.bottom: primaryTrack.bottom
                height: primaryTrack.height
                radius: primaryTrack.radius
                width: Math.round(primaryTrack.width * full.primaryPercent / 100)
                // Full ink when the accent applies, otherwise the family's
                // meter-fill weight (now-playing's progress fill, 0.8) rather
                // than the dimmer 0.65 a share bar uses: this fill is a
                // reading, not a share.
                color: full.primaryFull ? colors.accentRed : colors.foreground
                opacity: full.primaryFull ? 1.0 : 0.8
            }

            Text {
                id: summary
                visible: full.isList
                // Never hide a filesystem silently: if the tile cannot fit
                // every row, it says how many it is showing.
                text: {
                    var total = store.entries.length
                    var shown = rows.count
                    if (shown < total)
                        return shown + " of " + total + " mounts"
                    return total + (total === 1 ? " mount" : " mounts")
                }
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                anchors.top: parent.top
                anchors.left: parent.left
            }

            Text {
                id: worst
                visible: full.isList
                text: "max " + full.maxPercent + "%"
                color: full.maxPercent >= 90 ? colors.accentRed : colors.foreground
                opacity: full.maxPercent >= 90 ? 1.0 : colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                anchors.verticalCenter: summary.verticalCenter
                anchors.right: parent.right
            }
        }

        // ── Content ─────────────────────────────────────────────────────
        Item {
            id: content
            x: 0
            y: header.implicitHeight + gscale.gap
            width: body.width
            height: Math.max(0, footer.y - gscale.gap - content.y)

            // Small: the used percentage as the hero.
            Item {
                id: hero
                visible: full.ready && !full.isList
                // The gap the mark sits in is part of the line's width, or the
                // pair is centred by the figure alone and reads 2 px left.
                readonly property real markGap: Math.round(gscale.tight * 0.3)
                width: Math.min(content.width,
                    heroAmount.implicitWidth + hero.markGap + heroMark.implicitWidth)
                height: heroAmount.implicitHeight
                anchors.centerIn: parent

                Text {
                    id: heroAmount
                    text: String(full.primaryPercent)
                    color: colors.foreground
                    font.family: colors.uiFont
                    font.pixelSize: gscale.hero
                    anchors.left: parent.left
                    anchors.top: parent.top
                }
                // The mark rides the figure's baseline rather than its top:
                // top-aligned it would read as a superscript, which is not
                // what a percentage is.
                Text {
                    id: heroMark
                    text: "%"
                    color: colors.foreground
                    opacity: 0.7
                    font.family: colors.uiFont
                    font.pixelSize: Math.round(gscale.hero * 0.46)
                    anchors.left: heroAmount.right
                    anchors.leftMargin: hero.markGap
                    anchors.baseline: heroAmount.baseline
                }
            }

            // Wide/large: one row per mount - name, sizes, thin meter.
            Column {
                id: rows
                visible: full.ready && full.isList
                width: parent.width
                // Fewer mounts than the tile can hold: the block sits in the
                // middle of the stage rather than clinging to the header with
                // dead space below it.
                anchors.verticalCenter: parent.verticalCenter

                readonly property int cap: Math.max(1, Math.floor(content.height / body.rowH))
                readonly property var list: store.entries.slice(0, rows.cap)
                readonly property int count: rows.list.length

                // Air between rows, but never enough to push the last one out
                // of the stage.
                spacing: rows.count > 1
                    ? Math.min(Math.round(gscale.gap * 0.6),
                        Math.max(0, (content.height - rows.count * body.rowH)
                            / (rows.count - 1)))
                    : 0

                Repeater {
                    model: rows.list

                    Item {
                        id: row
                        required property var modelData

                        readonly property bool tight: row.modelData.usedPercent >= 90

                        width: rows.width
                        height: body.rowH

                        Text {
                            id: rowName
                            text: row.modelData.mount
                            color: colors.foreground
                            opacity: row.tight ? 1.0 : 0.9
                            font.family: colors.uiFont
                            font.weight: row.tight ? Font.DemiBold : Font.Normal
                            font.pixelSize: gscale.body
                            height: body.rowNameH
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: rowSizes.left
                            anchors.rightMargin: gscale.gap
                        }

                        Text {
                            id: rowSizes
                            text: row.modelData.usedLabel + " / " + row.modelData.sizeLabel
                            color: colors.foreground
                            opacity: colors.textQuiet
                            font.family: colors.uiFont
                            font.pixelSize: gscale.micro
                            height: body.rowNameH
                            verticalAlignment: Text.AlignVCenter
                            anchors.top: parent.top
                            anchors.right: parent.right
                        }

                        Rectangle {
                            id: rowTrack
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: body.barH
                            radius: height / 2
                            // Same channel as the primary meter above.
                            color: colors.foreground
                            opacity: 0.20
                        }
                        Rectangle {
                            anchors.left: rowTrack.left
                            anchors.bottom: rowTrack.bottom
                            height: rowTrack.height
                            radius: rowTrack.radius
                            width: Math.round(rowTrack.width * row.modelData.usedPercent / 100)
                            color: row.tight ? colors.accentRed : colors.foreground
                            opacity: row.tight ? 1.0 : 0.8
                        }
                    }
                }
            }

            // Before the first `df` returns, and on a host where every
            // filesystem was filtered out: a named state, not a blank card
            // and not an error.
            Column {
                id: notReady
                visible: !full.ready
                width: parent.width
                spacing: gscale.gap
                anchors.centerIn: parent

                Text {
                    width: parent.width
                    text: "--"
                    color: colors.foreground
                    opacity: 0.25
                    font.family: colors.uiFont
                    font.pixelSize: Math.round(gscale.hero * 0.62)
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: !store.loaded ? "Reading df"
                        : full.mountMissing
                          ? "No such mount: " + full.chosenMounts.join(", ")
                          : (store.errorMessage !== "" ? store.errorMessage : "No filesystems")
                    color: colors.foreground
                    opacity: 0.85
                    font.family: colors.uiFont
                    font.pixelSize: gscale.body
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
