import QtQuick
import Quickshell.Services.Mpris
import "../../components/nothing"
import "../../components"

// Now Playing, Nothing style.
//
// `now-playing`, not `music`: the MPRIS service reports whatever player is on
// the bus, so the tile draws a podcast or a video as readily as a track. The
// old name is absorbed by Store.qml's `_legacyTypes` for instances still
// carrying it.
//
// The MPRIS half is the Liquid Glass widget's, unchanged: same player
// selection policy (`_isPlayerAllowed` + the `_activePlayer` scan), same
// `playerFilter` / `filterMode` / `artRefreshEnabled` / `autoHideEnabled` /
// `autoHideTimeout` keys, same 150 ms album-art debounce, same
// seconds -> microseconds conversion so `formatTime` and the position maths
// stay identical. A style switch must not change what a widget does.
//
// What is gone is the colour sampling: the Liquid Glass tile tints its glass
// from the cover, and Nothing has no glass to tint. Here the cover is a small
// framed square - a detail on a matte card, never the background - and the
// only colour in the file is `nothing.red`, on the playing state.
Item {
    id: root
    anchors.fill: parent

    readonly property bool _shouldShow: {
        if (!plugin.settings.autoHideEnabled) return true
        return root.isPlaying
    }

    on_ShouldShowChanged: {
        if (_shouldShow) {
            root.visible = true
            _autoHideTimer.stop()
        } else if (plugin.settings.autoHideEnabled) {
            _autoHideTimer.restart()
        }
    }

    Timer {
        id: _autoHideTimer
        interval: plugin.settings.autoHideTimeout * 1000
        repeat: false
        onTriggered: root.visible = false
    }

    // ── MPRIS ─────────────────────────────────────────────────────────────

    function _isPlayerAllowed(identity) {
        var f = (plugin.settings.playerFilter || "").toLowerCase()
        if (f === "") return true
        var list = f.split(",")
        var id = (identity || "").toLowerCase()
        var inList = false
        for (var i = 0; i < list.length; i++) {
            if (list[i].trim() === id) { inList = true; break }
        }
        return plugin.settings.filterMode === 1 ? !inList : inList
    }

    // First player the filter allows that actually has a track or an artist.
    // Kept a binding, not a one-shot read: Mpris.players is empty for the
    // first ~0.5-1 s of a shell session while D-Bus discovery runs.
    property var _activePlayer: {
        var list = (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
        for (var i = 0; i < list.length; i++) {
            var p = list[i]
            if (p && _isPlayerAllowed(p.identity) && (p.trackTitle || p.trackArtist))
                return p
        }
        return null
    }

    readonly property string identity: _activePlayer?.identity ?? ""
    readonly property string track:   _activePlayer?.trackTitle ?? ""
    readonly property string artist:  _activePlayer?.trackArtist ?? ""
    readonly property string _rawAlbumArt: _activePlayer?.trackArtUrl ?? ""

    // The player's URL, after the debounce. It is never drawn: CoverArt turns
    // it into a bounded local copy (or refuses it), and `albumArt` - the only
    // URL the cover Image is given - is what CoverArt says. No placeholder
    // image either: with no art the cover slot draws the dot matrix note
    // instead, so the "no art" state is a pattern, not a PNG.
    property string _requestedArt: ""
    CoverArt {
        id: _cover
        source: root._requestedArt
    }
    readonly property string albumArt: _cover.url
    readonly property bool hasArt: root.albumArt !== ""

    // Same debounce as the Liquid Glass twin, including the reset on "" - a
    // titled track without art must not keep the previous cover on screen,
    // and a transient "" during a track change must not flash the empty slot.
    on_RawAlbumArtChanged: _artDebounceTimer.restart()

    Timer {
        id: _artDebounceTimer
        interval: 150
        onTriggered: root._requestedArt = root._rawAlbumArt
    }

    readonly property bool isPlaying: _activePlayer?.isPlaying ?? false
    readonly property bool canGoPrevious: _activePlayer?.canGoPrevious ?? false
    readonly property bool canGoNext:     _activePlayer?.canGoNext ?? false
    readonly property bool canPlay:  _activePlayer?.canPlay ?? false
    readonly property bool canPause: _activePlayer?.canPause ?? false
    readonly property bool canSeek:  _activePlayer?.canSeek ?? false

    // UNITS. Quickshell reports position/length in SECONDS; everything below
    // works in microseconds, exactly like the twin, so formatTime() and the
    // seek arithmetic are the same code.
    readonly property real length: (_activePlayer?.lengthSupported ? (_activePlayer?.length ?? 0) : 0) * 1000000
    function _playerPositionUs() {
        return root._activePlayer ? root._activePlayer.position * 1000000 : 0
    }

    property real position: 0
    property real _lastPosTick: 0

    // The player's own position signal wins over local extrapolation: an
    // external seek or a track loop would otherwise leave the bar wrong until
    // the next state change.
    Connections {
        target: root._activePlayer
        function onPositionChanged() {
            root.position = root._playerPositionUs()
            root._lastPosTick = 0
        }
    }

    Timer {
        id: positionTimer
        interval: 250
        running: root.isPlaying && root.length > 0
        repeat: true
        onTriggered: {
            var now = Date.now()
            if (root._lastPosTick > 0)
                root.position += (now - root._lastPosTick) * 1000
            root._lastPosTick = now
        }
    }

    onTrackChanged: {
        if (track === "" || track === "Not Playing") {
            _artDebounceTimer.stop()
            _requestedArt = ""
        }
        root.position = root._playerPositionUs()
        root._lastPosTick = 0
        _scheduleArtRefresh()
    }

    onIsPlayingChanged: {
        root.position = root._playerPositionUs()
        root._lastPosTick = 0
    }

    Timer {
        id: artRefreshTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root._activePlayer && root.isPlaying) {
                root._activePlayer.pause()
                artResumeTimer.start()
            }
        }
    }

    Timer {
        id: artResumeTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (root._activePlayer) root._activePlayer.play()
        }
    }

    function _scheduleArtRefresh() {
        if (!plugin.settings.artRefreshEnabled) return
        artRefreshTimer.stop()
        artResumeTimer.stop()
        if (root.isPlaying) artRefreshTimer.start()
    }

    function togglePlaying() {
        if (!root._activePlayer) return
        root._activePlayer.togglePlaying()
    }
    function next() {
        if (!root._activePlayer) return
        root._activePlayer.next()
    }
    function previous() {
        if (!root._activePlayer) return
        root._activePlayer.previous()
    }
    // MprisPlayer.seek(offset) takes SECONDS relative to the current
    // position, and is guarded on canSeek so a player that cannot seek keeps
    // its bar inert instead of showing a position it never moved to.
    function seek(positionUs) {
        if (!root._activePlayer || !root.canSeek) return
        var currentUs = root._playerPositionUs()
        root._activePlayer.seek((positionUs - currentUs) / 1000000)
        root.position = positionUs
        root._lastPosTick = 0
    }

    function formatTime(us) {
        var totalSec = Math.floor(us / 1000000)
        var h = Math.floor(totalSec / 3600)
        var m = Math.floor((totalSec % 3600) / 60)
        var s = totalSec % 60
        var ss = s < 10 ? "0" + s : "" + s
        if (h > 0) return h + ":" + (m < 10 ? "0" + m : m) + ":" + ss
        return m + ":" + ss
    }

    // ── Presentation ──────────────────────────────────────────────────────

    // A transport glyph, drawn. The style has no icon set and does not want
    // one: a triangle and two bars are shapes, and shapes scale with the
    // tile. `theme` is passed in rather than read from scope because an
    // inline component does not inherit the enclosing file's ids.
    component Glyph: Canvas {
        id: glyph
        required property var theme
        // 0 = play, 1 = pause, 2 = next, 3 = previous
        property int kind: 0
        property color tint: glyph.theme.on

        onKindChanged: glyph.requestPaint()
        onTintChanged: glyph.requestPaint()
        onWidthChanged: glyph.requestPaint()
        onHeightChanged: glyph.requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var s = Math.min(width, height)
            if (s <= 0) return
            var cx = width / 2
            var cy = height / 2
            ctx.fillStyle = glyph.tint

            if (glyph.kind === 1) {
                var bw = s * 0.26
                var bh = s * 0.82
                ctx.fillRect(cx - bw * 1.15, cy - bh / 2, bw, bh)
                ctx.fillRect(cx + bw * 0.15, cy - bh / 2, bw, bh)
                return
            }

            // One triangle for play, two for the skips; mirrored for
            // previous by negating the x step.
            var dir = glyph.kind === 3 ? -1 : 1
            var count = glyph.kind === 0 ? 1 : 2
            var tw = s * (count === 1 ? 0.62 : 0.40)
            var th = s * (count === 1 ? 0.78 : 0.62)
            var span = count === 1 ? 0 : tw * 0.86
            var startX = cx - dir * (span / 2) - dir * (tw / 2)

            for (var i = 0; i < count; i++) {
                var x0 = startX + dir * i * span
                ctx.beginPath()
                ctx.moveTo(x0, cy - th / 2)
                ctx.lineTo(x0, cy + th / 2)
                ctx.lineTo(x0 + dir * tw, cy)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    Item {
        id: full
        anchors.fill: parent

        // The three grid presets: 192x192, 400x192, 400x400.
        readonly property bool isWide: full.width >= full.height * 1.6
        readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

        readonly property real btn: Math.max(nothing.px(22),
            Math.min(nothing.px(42), Math.min(full.width, full.height) * (full.isBig ? 0.12 : 0.17)))
        readonly property bool showTimes: full.isWide || full.isBig
        readonly property string stateLabel:
            root.track === "" ? "NOT PLAYING" : (root.isPlaying ? "NOW PLAYING" : "PAUSED")

        // Nothing is playing when no allowed player has handed over a track.
        // A PAUSED track is not idle: its card stays so the transport can
        // resume it. Idle drops the card entirely and leaves two words on the
        // wallpaper in the style's own ink (operator's call, 2026-09-08).
        readonly property bool idle: root._activePlayer === null
            || root.track === "" || root.track === "Not Playing"

        // A beamed pair of eighth notes, 7x7. Used wherever a cover would be
        // and there is none - the dot grid is the placeholder.
        readonly property var noteGlyph: [
            "0011111",
            "0010001",
            "0010001",
            "0010001",
            "0010001",
            "1110111",
            "1110111"
        ]

        NCard {
            id: card
            theme: nothing
            anchors.fill: parent
            visible: !full.idle

            // ── Header ────────────────────────────────────────────────────
            NLabel {
                id: header
                theme: nothing
                text: full.stateLabel
                loud: root.isPlaying
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: playing.left
                anchors.rightMargin: nothing.gap
                anchors.topMargin: nothing.pad
                anchors.leftMargin: nothing.pad
                elide: Text.ElideRight
            }

            NBadge {
                id: playing
                theme: nothing
                active: root.isPlaying
                label: full.isWide || full.isBig ? root.identity.toUpperCase() : ""
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: nothing.pad
                anchors.rightMargin: nothing.pad
            }

            // ── Stage: cover + track ──────────────────────────────────────
            Item {
                id: stage
                anchors.top: header.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top
                anchors.bottomMargin: nothing.gap
                anchors.leftMargin: nothing.pad
                anchors.rightMargin: nothing.pad

                // Wide: cover left, text right. Square: cover above the text,
                // as large as the leftover height allows.
                readonly property real cover: full.isWide
                    ? Math.min(stage.height, stage.width * 0.42)
                    : Math.min(stage.width * (full.isBig ? 0.72 : 0.62), stage.height * 0.58)

                Row {
                    id: wideRow
                    visible: full.isWide
                    anchors.fill: parent
                    spacing: nothing.pad

                    Item {
                        width: stage.cover
                        height: parent.height

                        Loader {
                            anchors.centerIn: parent
                            width: stage.cover
                            height: stage.cover
                            active: wideRow.visible
                            sourceComponent: coverSlot
                        }
                    }

                    Column {
                        width: parent.width - stage.cover - nothing.pad
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: nothing.px(4)

                        NText {
                            theme: nothing
                            width: parent.width
                            text: root.track !== "" ? root.track : "NOT PLAYING"
                            color: root.track !== "" ? nothing.on : nothing.onDim
                            font.family: nothing.sansBold
                            font.pixelSize: nothing.fTitle
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                        }

                        NLabel {
                            theme: nothing
                            width: parent.width
                            text: root.artist
                            visible: root.artist !== ""
                            elide: Text.ElideRight
                        }
                    }
                }

                Column {
                    id: squareCol
                    visible: !full.isWide
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: nothing.gap

                    Loader {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: stage.cover
                        height: stage.cover
                        active: squareCol.visible
                        sourceComponent: coverSlot
                    }

                    NText {
                        theme: nothing
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.track !== "" ? root.track : "NOT PLAYING"
                        color: root.track !== "" ? nothing.on : nothing.onDim
                        font.family: nothing.sansBold
                        font.pixelSize: full.isBig ? nothing.fTitle : nothing.fBody
                        maximumLineCount: full.isBig ? 2 : 1
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                    }

                    NLabel {
                        theme: nothing
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.artist
                        visible: root.artist !== ""
                        font.pixelSize: full.isBig ? nothing.fLabel : nothing.fMicro
                        elide: Text.ElideRight
                    }
                }
            }

            // The cover: a framed square, or the note matrix when the player
            // handed over no art. One definition, two mount points.
            Component {
                id: coverSlot

                Item {
                    id: slot

                    Image {
                        id: cover
                        anchors.fill: parent
                        anchors.margins: nothing.hair
                        visible: root.hasArt && cover.status === Image.Ready
                        source: root.albumArt
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        cache: true
                        sourceSize.width: Math.max(1, Math.round(slot.width * 2))
                        sourceSize.height: Math.max(1, Math.round(slot.height * 2))
                    }

                    NDotMatrix {
                        anchors.centerIn: parent
                        theme: nothing
                        pattern: full.noteGlyph
                        visible: !cover.visible
                        dot: Math.max(2, slot.height * 0.085)
                        gap: Math.max(1, slot.height * 0.045)
                        onColor: root.isPlaying ? nothing.red : nothing.onDim
                        offColor: nothing.onFaint
                    }

                    // Hairline frame, drawn over the picture so the outline
                    // reads at the same weight whatever the cover contains.
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: nothing.rDot
                        border.width: nothing.hair
                        border.color: nothing.outline
                    }
                }
            }

            // ── Footer: position, then transport ──────────────────────────
            Item {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: nothing.pad
                height: transport.height + bar.height + nothing.gap
                     + (times.visible ? times.height + nothing.px(4) : 0)

                NProgress {
                    id: bar
                    theme: nothing
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: nothing.px(5)
                    segments: Math.max(8, Math.min(48, Math.round(footer.width / nothing.px(8))))
                    accent: root.isPlaying
                    value: root.length > 0 ? Math.max(0, Math.min(1, root.position / root.length)) : 0

                    // Seeking, kept from the twin's slider: tap the bar.
                    MouseArea {
                        anchors.fill: parent
                        anchors.topMargin: -nothing.px(6)
                        anchors.bottomMargin: -nothing.px(6)
                        enabled: root.canSeek && root.length > 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: mouse => root.seek(
                            Math.max(0, Math.min(1, mouse.x / Math.max(1, width))) * root.length)
                    }
                }

                Item {
                    id: times
                    visible: full.showTimes
                    anchors.top: bar.bottom
                    anchors.topMargin: nothing.px(4)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: elapsed.implicitHeight

                    NMono {
                        id: elapsed
                        theme: nothing
                        anchors.left: parent.left
                        text: root.formatTime(root.position)
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                    }

                    NMono {
                        theme: nothing
                        anchors.right: parent.right
                        text: root.length > 0 ? root.formatTime(root.length) : "--:--"
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                    }
                }

                Row {
                    id: transport
                    anchors.bottom: parent.bottom
                    // Wide keeps the transport on the right, under the text
                    // column; the square tiles centre it. Conditional
                    // anchors would mean assigning `undefined` to an anchor
                    // line, so this is plain x.
                    x: full.isWide
                        ? Math.max(0, parent.width - transport.width)
                        : Math.max(0, (parent.width - transport.width) / 2)
                    height: full.btn
                    spacing: nothing.gap

                    NButton {
                        theme: nothing
                        width: full.btn
                        height: full.btn
                        enabled: root.canGoPrevious
                        onClicked: root.previous()

                        Glyph {
                            theme: nothing
                            anchors.centerIn: parent
                            width: parent.width * 0.5
                            height: parent.height * 0.5
                            kind: 3
                            tint: nothing.on
                        }
                    }

                    NButton {
                        theme: nothing
                        width: full.btn
                        height: full.btn
                        active: root.isPlaying
                        enabled: root.isPlaying ? root.canPause : root.canPlay
                        onClicked: root.togglePlaying()

                        Glyph {
                            theme: nothing
                            anchors.centerIn: parent
                            width: parent.width * 0.46
                            height: parent.height * 0.46
                            kind: root.isPlaying ? 1 : 0
                            tint: root.isPlaying ? nothing.redInk : nothing.on
                        }
                    }

                    NButton {
                        theme: nothing
                        width: full.btn
                        height: full.btn
                        enabled: root.canGoNext
                        onClicked: root.next()

                        Glyph {
                            theme: nothing
                            anchors.centerIn: parent
                            width: parent.width * 0.5
                            height: parent.height * 0.5
                            kind: 2
                            tint: nothing.on
                        }
                    }
                }
            }
        }

        // ── Nothing playing ───────────────────────────────────────────────
        // No card, no outline, no dot grid: the style's uppercase metadata
        // line on the bare wallpaper, sized to the tile. The tile keeps its
        // geometry, so the card returns in place the moment a player does.
        NLabel {
            anchors.centerIn: parent
            width: parent.width - nothing.pad * 2
            visible: full.idle
            loud: true
            theme: nothing
            text: "Nothing playing"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
            font.pixelSize: Math.max(nothing.fLabel,
                Math.round(Math.min(full.width, full.height) * 0.085))
        }
    }
}
