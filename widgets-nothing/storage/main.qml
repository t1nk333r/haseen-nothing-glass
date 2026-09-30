import QtQuick
import "../../components"
import "../../components/nothing"

// Filesystem use, Nothing style.
//
// StorageData owns the only poll in the set (one short `df` per minute), and
// its `active` is bound to this widget's `visible` below: a tile scrolled
// off a workspace stops spawning processes entirely. There is no timer and
// no second `df` in this file.
//
// The accent carries exactly ONE meaning: a filesystem at 90% or more.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300
    // 192 shows one number; both 400-wide tiles have room for the list.
    readonly property bool isList: full.isWide || full.isBig

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
    readonly property bool nothingMatched: store.loaded
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

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: nothing.pad

            readonly property real headTop: Math.max(header.implicitHeight, nothing.px(18)) + nothing.gap

            // ── The list row, sized from the parts it draws ───────────
            // Name line, the air under it, then the meter - the same three
            // parts both 400-wide presets draw. The height is their sum, not a
            // literal, so it cannot drift from what the row actually draws
            // (the glass twin derives its own row the same way). It is also
            // what makes the 400x192 stage hold the list that preset exists
            // for: at a flat 32 px only three of five mounts fitted, and the
            // footer had to read "3 of 5 mounts" beside the glass half's
            // "5 mounts". `rowAir` is the one value the two presets disagree
            // on - the square keeps the roomier separation.
            readonly property real rowBarH: nothing.px(4)
            readonly property real rowAir: full.isWide ? nothing.px(3) : nothing.px(9)
            readonly property real rowNameH: Math.round(nothing.fLabel * 1.4)
            readonly property real rowH: body.rowNameH + body.rowAir + body.rowBarH

            // ── Header ────────────────────────────────────────────────
            // Small tile: the mount point is the label, because the number
            // below it belongs to exactly one filesystem.
            NLabel {
                id: header
                theme: nothing
                text: (!full.isList && full.ready) ? store.primary.mount : "Storage"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: badge.visible ? badge.left : parent.right
                anchors.rightMargin: badge.visible ? nothing.gap : 0
                elide: Text.ElideRight
            }

            NBadge {
                id: badge
                theme: nothing
                anchors.verticalCenter: header.verticalCenter
                anchors.right: parent.right
                visible: full.ready && (full.isList ? full.maxPercent >= 90 : full.primaryFull)
                active: true
                label: "Full"
            }

            // ── Footer ────────────────────────────────────────────────
            // Small: the primary filesystem's meter and its sizes.
            // Wide/large: how many mounts are listed, and the worst of them.
            Item {
                id: footer
                visible: full.ready
                x: 0
                width: body.width
                height: full.isList
                    ? summary.implicitHeight
                    : (sizes.implicitHeight + nothing.px(6) + nothing.px(5))
                y: Math.max(0, body.height - footer.height)

                NMono {
                    id: sizes
                    theme: nothing
                    visible: !full.isList
                    text: full.ready
                        ? store.primary.usedLabel + " / " + store.primary.sizeLabel
                        : ""
                    color: nothing.onDim
                    font.pixelSize: nothing.fLabel
                    anchors.top: parent.top
                    anchors.left: parent.left
                }

                NProgress {
                    theme: nothing
                    visible: !full.isList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: nothing.px(5)
                    segments: 12
                    value: full.primaryPercent / 100
                    accent: full.primaryFull
                }

                NLabel {
                    id: summary
                    theme: nothing
                    visible: full.isList
                    // Never hide a filesystem silently: if the tile cannot
                    // fit every row, it says how many it is showing.
                    text: {
                        var total = store.entries.length
                        var shown = list.rows.length
                        if (shown < total)
                            return shown + " of " + total + " mounts"
                        return total + (total === 1 ? " mount" : " mounts")
                    }
                    anchors.top: parent.top
                    anchors.left: parent.left
                }

                NMono {
                    theme: nothing
                    visible: full.isList
                    text: "max " + full.maxPercent + "%"
                    color: full.maxPercent >= 90 ? nothing.red : nothing.onDim
                    font.pixelSize: nothing.fLabel
                    anchors.verticalCenter: summary.verticalCenter
                    anchors.right: parent.right
                }
            }

            // ── Content ───────────────────────────────────────────────
            Item {
                id: content
                x: 0
                y: body.headTop
                width: body.width
                height: Math.max(0, (footer.visible ? footer.y - nothing.gap : body.height) - content.y)

                // Small: the used percentage as dot-matrix digits.
                NDotMatrix {
                    id: hero
                    theme: nothing
                    visible: full.ready && !full.isList
                    anchors.centerIn: parent
                    text: String(full.primaryPercent) + "%"
                    onColor: full.primaryFull ? nothing.red : nothing.on
                    dot: {
                        var cols = hero.colCount > 0 ? hero.colCount : 17
                        var byW = content.width / (cols + 0.34 * (cols - 1))
                        var byH = content.height / (7 + 0.34 * 6)
                        return Math.max(2, Math.min(byW, byH) * 0.92)
                    }
                    gap: Math.max(1, hero.dot * 0.34)
                }

                // Wide/large: one row per mount - name, sizes, thin meter.
                Column {
                    id: list
                    visible: full.ready && full.isList
                    width: parent.width
                    // Fewer mounts than the tile can hold: the block sits in
                    // the middle of the stage rather than clinging to the
                    // header with dead space below it.
                    anchors.verticalCenter: parent.verticalCenter

                    readonly property int cap: Math.max(1, Math.floor(content.height / body.rowH))
                    readonly property var rows: store.entries.slice(0, list.cap)

                    // Air between rows, but never enough to push the last one
                    // out of the stage.
                    spacing: list.rows.length > 1
                        ? Math.min(nothing.px(14),
                            Math.max(0, (content.height - list.rows.length * body.rowH)
                                / (list.rows.length - 1)))
                        : 0

                    Repeater {
                        model: list.rows

                        Item {
                            id: row
                            required property var modelData

                            readonly property bool tight: row.modelData.usedPercent >= 90

                            width: content.width
                            height: body.rowH

                            NLabel {
                                theme: nothing
                                text: row.modelData.mount
                                loud: row.tight
                                height: body.rowNameH
                                verticalAlignment: Text.AlignVCenter
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: rowSizes.left
                                anchors.rightMargin: nothing.gap
                                elide: Text.ElideRight
                            }

                            NMono {
                                id: rowSizes
                                theme: nothing
                                text: row.modelData.usedLabel + " / " + row.modelData.sizeLabel
                                color: nothing.onDim
                                font.pixelSize: nothing.fLabel
                                height: body.rowNameH
                                verticalAlignment: Text.AlignVCenter
                                anchors.top: parent.top
                                anchors.right: parent.right
                            }

                            NProgress {
                                theme: nothing
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: body.rowBarH
                                segments: 24
                                value: row.modelData.usedPercent / 100
                                accent: row.tight
                            }
                        }
                    }
                }

                // Before the first `df` returns, and on a host where every
                // filesystem was filtered out: a named state, not a blank
                // card and not an error.
                Column {
                    visible: !full.ready
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: nothing.gap

                    Item {
                        width: parent.width
                        height: waiting.implicitHeight

                        NDotMatrix {
                            id: waiting
                            theme: nothing
                            anchors.centerIn: parent
                            text: "--"
                            onColor: nothing.onDim
                            dot: {
                                var cols = waiting.colCount > 0 ? waiting.colCount : 11
                                var byW = content.width / (cols + 0.34 * (cols - 1))
                                var byH = content.height * 0.62 / (7 + 0.34 * 6)
                                // A placeholder, not a reading - capped so the
                                // pre-`df` state shows a dash, not blobs.
                                return Math.min(nothing.px(8),
                                    Math.max(2, Math.min(byW, byH) * 0.92))
                            }
                            gap: Math.max(1, waiting.dot * 0.34)
                        }
                    }

                    NLabel {
                        theme: nothing
                        loud: true
                        text: !store.loaded ? "Reading df"
                            : full.nothingMatched
                              ? "No such mount: " + full.chosenMounts.join(", ")
                              : (store.errorMessage !== "" ? store.errorMessage : "No filesystems")
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
