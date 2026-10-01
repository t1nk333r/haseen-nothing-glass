import QtQuick
import Quickshell.Services.Mpris
import "../../components"
import "widget"

// Port of packages/music/contents/ui/main.qml, per PORTING.md. This is the
// only widget in the set whose data source is rewritten rather than adapted:
// Plasma's Mpris2Model becomes Quickshell's Mpris singleton.
//
// The type is `now-playing` (it was `music` until the rename): `Mpris.players`
// is every player on the bus, and the widget draws whatever it finds - a
// podcast, a video, a browser tab - not just music. Instance rows still
// carrying the old name are absorbed by Store.qml's `_legacyTypes`.
//
// What changed, and nothing else did:
//   * `Mpris.Mpris2Model` -> the `Mpris.players` object model, with the
//     player-selection policy preserved (see _activePlayer).
//   * property names remapped (track -> trackTitle, artist -> trackArtist,
//     album -> trackAlbum, artUrl -> trackArtUrl, playbackStatus enum ->
//     isPlaying), and transport methods lowercased (PlayPause -> togglePlaying,
//     Next -> next, Previous -> previous, Play/Pause -> play/pause).
//   * Seek(offset) -> seek(offsetSeconds), guarded on canSeek. (An earlier
//     revision of this port claimed seek() did not exist and wrote `position`
//     instead; it does exist, and it also works on players that report
//     positionSupported=false, so the slider is no longer disabled for them.)
//   * `album` is gone: after the lyrics removal nothing read it (it only fed
//     the LRCLIB query). No layout declares it.
//   * UNITS: Quickshell reports position/length in SECONDS, Plasma in
//     microseconds. The conversion is done once, in this file, so all 11 view
//     components keep working in microseconds unchanged.
//   * `_playerAllowed` is gone -- it was already dead code in the original
//     (nothing read it) and it was built on Plasma's currentPlayer, which has
//     no Quickshell equivalent.
//
//   * LYRICS REMOVED (operator's call, after plan 010 landed): no LRCLIB
//     fetch, no LRC parser, no SyncedLyricsView, no lyrics settings, no
//     Lyrics toggle in the wide/tall layouts. packages/music keeps all of it —
//     this is a port-side product decision, not an upstream change.
//
// Structure follows the timer port: `root` keeps the state machine that lived
// on PlasmoidItem, and a nested `full` keeps the tree that lived inside
// fullRepresentation, so neither half's references had to be rewritten.

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

    MacOSColors {
        id: colors
        styleMode: plugin.settings.styleMode
        appearance: plugin.settings.appearance
        systemBackground: theme.systemBackground
        themePalette: theme.palette
        foregroundDarkOverride: isSolid && root._hasSampledColor ? root._sampledIsDark : null
    }

    // The `colors` id above, re-exported under a name no view component has a
    // property for. The layouts below now hand their bindings to a `Loader`'s
    // Component, and inside a Component the layout's own `colors:` property
    // wins the unqualified lookup — `colors: colors` there is a
    // self-referencing binding loop that leaves the layout with a null
    // palette, where `colors: root._colors` is not.
    readonly property QtObject _colors: colors

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

    // Quickshell has no "current player" concept -- Mpris.players is the whole
    // list -- so the Plasma version's "try currentPlayer, then scan" collapses
    // into one scan with the same policy: first player that the filter allows
    // AND that actually has a track or an artist. Note the scan starts at 0:
    // Plasma started at 1 because Mpris2Model reserved row 0 for its multiplex
    // entry, and copying that verbatim here would silently ignore the only
    // player whenever exactly one is running.
    //
    // Mpris.players is empty for the first ~0.5-1s of a shell session while
    // D-Bus discovery runs (measured), so this must stay a binding, never a
    // one-shot read at Component.onCompleted.
    property var _activePlayer: {
        var list = (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
        for (var i = 0; i < list.length; i++) {
            var p = list[i]
            if (p && _isPlayerAllowed(p.identity) && (p.trackTitle || p.trackArtist))
                return p
        }
        return null
    }

    readonly property string track:   _activePlayer?.trackTitle ?? ""
    readonly property string artist:  _activePlayer?.trackArtist ?? ""
    readonly property string _rawAlbumArt: _activePlayer?.trackArtUrl ?? ""
    property string albumArt: ""

    // True only when a player actually handed over cover art. The square
    // layout paints `albumArt` full-bleed behind everything, so the background
    // must wait for art a player actually provided: an empty URL means no art.
    // (Feeding it a grey placeholder made an idle widget an opaque dark card
    // carrying a huge music note - the one tile in the set that did not look
    // like glass, with "Not Playing" sitting on top of the note.)
    readonly property bool hasRealArt: root.albumArt !== ""

    // Nothing is playing when no allowed player has handed over a track at
    // all. A PAUSED track is not idle - the card has to stay so its transport
    // can resume it; this is the "no player on this machine right now" state,
    // and the widget answers it with words on the wallpaper rather than an
    // empty card (operator's call, 2026-09-08).
    readonly property bool idle: root._activePlayer === null
        || root.track === "" || root.track === "Not Playing"

    // Deviation from the Plasma original, which returned early on "" and so
    // kept the PREVIOUS track's cover on screen when a titled track without
    // art followed one with art. An empty URL now resets to empty (after the
    // same debounce, so a transient "" during a track change does not flash
    // the fallback). Empty is a state the artwork face has to be told about,
    // not a value it may ignore - see FlipAlbumArt._processChange.
    on_RawAlbumArtChanged: _artDebounceTimer.restart()

    Timer {
        id: _artDebounceTimer
        interval: 150
        onTriggered: root.albumArt = root._rawAlbumArt
    }
    // MprisPlayer exposes isPlaying directly, so the PlaybackStatus enum
    // comparison the Plasma version needed is gone.
    readonly property bool isPlaying: _activePlayer?.isPlaying ?? false
    readonly property bool canGoPrevious: _activePlayer?.canGoPrevious ?? false
    readonly property bool canGoNext:     _activePlayer?.canGoNext ?? false
    readonly property bool canPlay:  _activePlayer?.canPlay ?? false
    readonly property bool canPause: _activePlayer?.canPause ?? false
    readonly property bool canSeek:  _activePlayer?.canSeek ?? false

    // UNITS. Plasma's MPRIS surface is microseconds; Quickshell's is seconds
    // (verified against the same Chromium player: position 1958.915 vs the
    // bus's 1958915000). Everything downstream of here -- formatTime(),
    // MusicSlider and the slider labels -- was written against microseconds, so
    // the conversion happens once, here, and no view code changes.
    readonly property real length: (_activePlayer?.lengthSupported ? (_activePlayer?.length ?? 0) : 0) * 1000000
    function _playerPositionUs() {
        return root._activePlayer ? root._activePlayer.position * 1000000 : 0
    }

    property real position: 0
    property int _flipDirection: 1

    property real _lastPosTick: 0

    // The player's own position signal wins over local extrapolation: an
    // external seek, a track loop, or a player that reports position in
    // coarse steps would otherwise leave the slider wrong until the next
    // state change. (Deleted by mistake with the lyrics code; restored.)
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
            albumArt = ""
        }
        root.position = root._playerPositionUs()
        root._lastPosTick = 0
        root._lastSampledUrl = ""
        _scheduleArtRefresh()
        _resampleTimer.restart()
    }
    Timer {
        id: _resampleTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (root.albumArt !== "" && root.albumArt !== root._lastSampledUrl)
                sampleCanvas.requestPaint()
        }
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
        root._flipDirection = -1
        root._activePlayer.next()
    }
    function previous() {
        if (!root._activePlayer) return
        root._flipDirection = 1
        root._activePlayer.previous()
    }
    // MprisPlayer.seek(offset) takes SECONDS relative to the current position
    // (Plasma's Seek() took microseconds). Guarded on canSeek so a player that
    // cannot seek keeps its slider inert instead of showing a position it
    // never moved to.
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

    // ── Album art color sampling ────────────────────────────────────────
    property color _sampledTint: "#000000"
    property color _sampledGradientTop: "#1A1B1E"
    property color _sampledGradientBottom: "#0E0F11"
    property color _sampledPrimaryColor: "#ffffff"
    property bool _hasSampledColor: false
    property bool _sampledIsDark: true

    function _hslToRgb(h, s, l) {
        var c = (1 - Math.abs(2 * l - 1)) * s
        var x = c * (1 - Math.abs((h * 6) % 2 - 1))
        var m = l - c / 2
        var r, g, b
        switch (Math.floor(h * 6) % 6) {
            case 0: r = c; g = x; b = 0; break
            case 1: r = x; g = c; b = 0; break
            case 2: r = 0; g = c; b = x; break
            case 3: r = 0; g = x; b = c; break
            case 4: r = x; g = 0; b = c; break
            case 5: r = c; g = 0; b = x; break
        }
        return Qt.rgba(r + m, g + m, b + m, 1.0)
    }

    function _rgbToHsl(r, g, b) {
        var mx = Math.max(r, g, b), mn = Math.min(r, g, b)
        var l = (mx + mn) / 2, s = 0, h = 0
        if (mx !== mn) {
            var dd = mx - mn
            s = l > 0.5 ? dd / (2 - mx - mn) : dd / (mx + mn)
            if (mx === r)      h = ((g - b) / dd + (g < b ? 6 : 0)) / 6
            else if (mx === g) h = ((b - r) / dd + 2) / 6
            else               h = ((r - g) / dd + 4) / 6
        }
        return { h: h, s: s, l: l }
    }

    property string _lastSampledUrl: ""

    onAlbumArtChanged: {
        if (albumArt !== "") {
            sampleCanvas.loadImage(albumArt)
        } else {
            _hasSampledColor = false
            _sampledTint = "#000000"
            _sampledGradientTop = "#1A1B1E"
            _sampledGradientBottom = "#0E0F11"
            _sampledPrimaryColor = "#ffffff"
            _sampledIsDark = true
            _lastSampledUrl = ""
        }
    }

    Canvas {
        id: sampleCanvas
        width: 64
        height: 64
        visible: true
        opacity: 0

        Component.onCompleted: {
            if (root.albumArt !== "") loadImage(root.albumArt)
        }

        onImageLoaded: {
            if (root.albumArt !== "" && root.albumArt !== root._lastSampledUrl) {
                root._lastSampledUrl = root.albumArt
                _resampleTimer.stop()
                requestPaint()
            }
        }

        onPaint: {
            var url = root.albumArt
            if (!url || !isImageLoaded(url)) return

            var ctx = getContext("2d")
            ctx.reset()
            ctx.drawImage(url, 0, 0, 64, 64)

            var imgData = ctx.getImageData(0, 0, 64, 64)
            var d = imgData.data
            var pixels = []
            for (var i = 0; i < d.length; i += 4) {
                if (d[i+3] < 128) continue
                pixels.push([d[i], d[i+1], d[i+2]])
            }
            if (pixels.length === 0) return

            function medianCut(px, depth) {
                if (depth === 0 || px.length === 0) {
                    var rS = 0, gS = 0, bS = 0
                    for (var j = 0; j < px.length; j++) {
                        rS += px[j][0]; gS += px[j][1]; bS += px[j][2]
                    }
                    var n = px.length || 1
                    return [{ r: rS/n/255, g: gS/n/255, b: bS/n/255, count: px.length }]
                }

                var rMin = 255, rMax = 0, gMin = 255, gMax = 0, bMin = 255, bMax = 0
                for (var j = 0; j < px.length; j++) {
                    var p = px[j]
                    if (p[0] < rMin) rMin = p[0]; if (p[0] > rMax) rMax = p[0]
                    if (p[1] < gMin) gMin = p[1]; if (p[1] > gMax) gMax = p[1]
                    if (p[2] < bMin) bMin = p[2]; if (p[2] > bMax) bMax = p[2]
                }
                var rR = rMax - rMin, gR = gMax - gMin, bR = bMax - bMin
                var ch = rR >= gR && rR >= bR ? 0 : (gR >= bR ? 1 : 2)

                px.sort(function(a, b) { return a[ch] - b[ch] })
                var mid = Math.floor(px.length / 2)

                return medianCut(px.slice(0, mid), depth - 1)
                       .concat(medianCut(px.slice(mid), depth - 1))
            }

            var buckets = medianCut(pixels, 3)

            var accentIdx = 0, maxSat = -1
            for (var i = 0; i < buckets.length; i++) {
                var hsl = root._rgbToHsl(buckets[i].r, buckets[i].g, buckets[i].b)
                buckets[i].h = hsl.h; buckets[i].s = hsl.s; buckets[i].l = hsl.l
                buckets[i].lum = 0.299 * buckets[i].r + 0.587 * buckets[i].g + 0.114 * buckets[i].b
                var score = hsl.s * (0.3 + 0.7 * (1 - Math.abs(2 * hsl.l - 1)))
                if (score > maxSat) { maxSat = score; accentIdx = i }
            }

            var sorted = buckets.slice().sort(function(a, b) { return b.count - a.count })
            var dominant = sorted[0]
            var secondary = sorted.length > 1 ? sorted[1] : sorted[0]
            var accent = buckets[accentIdx]

            var avgSat = 0
            for (var j = 0; j < buckets.length; j++)
                avgSat += buckets[j].s
            avgSat /= buckets.length
            var isMono = avgSat < 0.12

            if (isMono) {
                root._sampledTint = root._hslToRgb(0, 0, Math.min(dominant.l, 0.30))
                root._sampledGradientTop = root._hslToRgb(0, 0, 0.15 + dominant.l * 0.35)
                root._sampledGradientBottom = root._hslToRgb(0, 0, 0.06 + dominant.l * 0.20)
                root._sampledPrimaryColor = Qt.rgba(1, 1, 1, 1)
            } else {
                root._sampledTint = root._hslToRgb(accent.h,
                    Math.min(accent.s, 0.5),
                    Math.min(accent.l, 0.30))
                root._sampledGradientTop = root._hslToRgb(dominant.h,
                    Math.max(dominant.s, 0.30),
                    0.15 + dominant.l * 0.35)
                root._sampledGradientBottom = root._hslToRgb(
                    secondary.h !== dominant.h ? secondary.h : dominant.h,
                    Math.max(secondary.s, 0.25),
                    0.06 + secondary.l * 0.20)
                root._sampledPrimaryColor = root._hslToRgb(accent.h,
                    Math.max(accent.s, 0.55),
                    Math.max(accent.l, 0.75))
            }

            root._sampledIsDark = dominant.lum < 0.5
            root._hasSampledColor = true
        }
    }

    Item {
        id: full
        anchors.fill: parent

        readonly property real _ar: full.width / Math.max(1, full.height)
        readonly property string _layout:
            _ar >= 3.0  ? "bar"
          : _ar >= 1.6  ? "wide"
          : _ar <= 0.85 && full.height >= full.width * 1.55 ? "tallwide"
          :               "square"

        LiquidGlass {
            id: glass
            anchors.fill: parent
            // Idle: no card at all. See root.idle.
            visible: !root.idle
            wallpaperItem: backdrop.item
            radius: plugin.settings.cornerRadius
            roundness: plugin.settings.roundness
            refractThickness: plugin.settings.refractThickness
            refractIOR: plugin.settings.refractIOR
            refractScale: plugin.settings.refractScale
            tint: colors.isGlass && root._hasSampledColor ? root._sampledTint : colors.glassTint
            tintAlpha: colors.isGlass && root._hasSampledColor
                ? Math.max(plugin.settings.tintAlpha, 0.15)
                : plugin.settings.tintAlpha
            chromaStrength: plugin.settings.chromaStrength
            specStrength: plugin.settings.specStrength
            blurRadius: plugin.settings.blurRadiusPx
            realtimeRefraction: plugin.settings.realtimeRefraction
            fallbackOpacity: colors.glassFallbackOpacity
            solidMode: colors.isSolid
            solidColor: colors.isSolid && root._hasSampledColor ? root._sampledGradientTop : colors.solidBackground
            solidColorBottom: colors.isSolid && root._hasSampledColor ? root._sampledGradientBottom : "transparent"
        }

        // Only the layout on screen exists. This tile used to instantiate all
        // four, so the three that were not selected still built their whole
        // tree — a FlipAlbumArt (two AlbumArt images apiece), three
        // ControlButtons and two MarqueeTexts each — and an Image decodes its
        // source even under an invisible ancestor.
        //
        // Loader creates its item synchronously the moment `active` flips, so
        // a size change that swaps layouts still swaps in the frame the size
        // changed; `asynchronous: true` would put a blank frame in between,
        // which is why it is not used. `active` is a copy of the `visible:`
        // beside it — keep the two in step, or a layout exists invisibly
        // again.
        Loader {
            anchors.fill: parent
            active: full._layout === "square" && !root.idle
            visible: full._layout === "square" && !root.idle

            sourceComponent: Component {
                SquareLayout {
                    anchors.fill: parent
                    colors: root._colors
                    cornerRadius: plugin.settings.cornerRadius
                    roundness: plugin.settings.roundness
                    fontFamily: colors.uiFont
                    fontFamilyThin: colors.uiFont
                    track: root.track
                    artist: root.artist
                    albumArt: root.albumArt
                    hasRealArt: root.hasRealArt
                    isPlaying: root.isPlaying
                    canGoPrevious: root.canGoPrevious
                    canGoNext: root.canGoNext
                    canPlay: root.canPlay
                    canPause: root.canPause
                    position: root.position
                    length: root.length
                    onTogglePlaying: root.togglePlaying()
                    onNextTrack: root.next()
                    onPreviousTrack: root.previous()
                    onSeek: function(pos) { root.seek(pos) }
                    formatTime: root.formatTime
                }
            }
        }

        Loader {
            anchors.fill: parent
            active: full._layout === "tallwide" && !root.idle
            visible: full._layout === "tallwide" && !root.idle

            sourceComponent: Component {
                TallWideLayout {
                    anchors.fill: parent
                    colors: root._colors
                    accentColor: root._hasSampledColor ? root._sampledPrimaryColor : colors.foreground
                    flipDirection: root._flipDirection
                    fontFamily: colors.uiFont
                    fontFamilyThin: colors.uiFont
                    track: root.track
                    artist: root.artist
                    albumArt: root.albumArt
                    hasRealArt: root.hasRealArt
                    isPlaying: root.isPlaying
                    canGoPrevious: root.canGoPrevious
                    canGoNext: root.canGoNext
                    canPlay: root.canPlay
                    canPause: root.canPause
                    position: root.position
                    length: root.length
                    onTogglePlaying: root.togglePlaying()
                    onNextTrack: root.next()
                    onPreviousTrack: root.previous()
                    onSeek: function(pos) { root.seek(pos) }
                    formatTime: root.formatTime
                }
            }
        }

        Loader {
            anchors.fill: parent
            active: full._layout === "wide" && !root.idle
            visible: full._layout === "wide" && !root.idle

            sourceComponent: Component {
                WideLayout {
                    anchors.fill: parent
                    colors: root._colors
                    accentColor: root._hasSampledColor ? root._sampledPrimaryColor : colors.foreground
                    flipDirection: root._flipDirection
                    fontFamily: colors.uiFont
                    fontFamilyThin: colors.uiFont
                    track: root.track
                    artist: root.artist
                    albumArt: root.albumArt
                    hasRealArt: root.hasRealArt
                    isPlaying: root.isPlaying
                    canGoPrevious: root.canGoPrevious
                    canGoNext: root.canGoNext
                    canPlay: root.canPlay
                    canPause: root.canPause
                    position: root.position
                    length: root.length
                    onTogglePlaying: root.togglePlaying()
                    onNextTrack: root.next()
                    onPreviousTrack: root.previous()
                    onSeek: function(pos) { root.seek(pos) }
                    formatTime: root.formatTime
                }
            }
        }

        // ── Nothing playing ───────────────────────────────────────────────
        // No glass, no card, no album-note placeholder: two words on the
        // wallpaper, in the palette's own foreground, sized to the tile. The
        // widget stays exactly as big as it was, so the moment a player
        // appears the card materialises in place without the desktop moving.
        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            width: parent.width - Math.round(Math.min(parent.width, parent.height) * 0.16)
            visible: root.idle
            text: "Nothing playing"
            color: colors.foreground
            opacity: 0.9
            font.family: colors.uiFont
            font.pixelSize: Math.max(11, Math.round(Math.min(full.width, full.height) * 0.11))
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
            renderType: Text.NativeRendering
        }

        // Active only while its layout is the one on screen — see the note on
        // the first Loader above.
        Loader {
            anchors.fill: parent
            active: full._layout === "bar" && !root.idle
            visible: full._layout === "bar" && !root.idle

            sourceComponent: Component {
                BarLayout {
                    anchors.fill: parent
                    colors: root._colors
                    accentColor: root._hasSampledColor ? root._sampledPrimaryColor : colors.foreground
                    cornerRadius: plugin.settings.cornerRadius
                    flipDirection: root._flipDirection
                    fontFamily: colors.uiFont
                    fontFamilyThin: colors.uiFont
                    track: root.track
                    artist: root.artist
                    albumArt: root.albumArt
                    hasRealArt: root.hasRealArt
                    isPlaying: root.isPlaying
                    canGoPrevious: root.canGoPrevious
                    canGoNext: root.canGoNext
                    canPlay: root.canPlay
                    canPause: root.canPause
                    position: root.position
                    length: root.length
                    onTogglePlaying: root.togglePlaying()
                    onNextTrack: root.next()
                    onPreviousTrack: root.previous()
                    onSeek: function(pos) { root.seek(pos) }
                    formatTime: root.formatTime
                }
            }
        }
    }
}
