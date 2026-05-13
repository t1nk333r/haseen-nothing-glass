import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.mpris as Mpris
import "components"
import "widget"

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    MacOSColors {
        id: colors
        styleMode: plasmoid.configuration.styleMode
        appearance: plasmoid.configuration.appearance
    }

    FontLoader { id: sfThin;    source: Qt.resolvedUrl("../fonts/sf_pro_display_thin.otf") }
    FontLoader { id: sfRegular; source: Qt.resolvedUrl("../fonts/sf_pro_display_regular.otf") }

    // ── MPRIS ─────────────────────────────────────────────────────────────

    Mpris.Mpris2Model { id: mpris2Model }

    readonly property string track:   mpris2Model.currentPlayer?.track ?? ""
    readonly property string artist:  mpris2Model.currentPlayer?.artist ?? ""
    readonly property string album:   mpris2Model.currentPlayer?.album ?? ""
    readonly property string albumArt: mpris2Model.currentPlayer?.artUrl ?? ""
    readonly property int playbackStatus: mpris2Model.currentPlayer?.playbackStatus ?? 0
    readonly property bool isPlaying: playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property bool canGoPrevious: mpris2Model.currentPlayer?.canGoPrevious ?? false
    readonly property bool canGoNext:     mpris2Model.currentPlayer?.canGoNext ?? false
    readonly property bool canPlay:  mpris2Model.currentPlayer?.canPlay ?? false
    readonly property bool canPause: mpris2Model.currentPlayer?.canPause ?? false
    readonly property real length: mpris2Model.currentPlayer?.length ?? 0

    property real position: 0

    Connections {
        target: mpris2Model.currentPlayer
        function onPositionChanged() {
            root.position = mpris2Model.currentPlayer?.position ?? 0
        }
    }

    Timer {
        id: positionTimer
        interval: 250
        running: root.isPlaying && root.length > 0
        repeat: true
        onTriggered: {
            if (root.position < root.length)
                root.position += interval * 1000
        }
    }

    onTrackChanged:     root.position = mpris2Model.currentPlayer?.position ?? 0
    onIsPlayingChanged: root.position = mpris2Model.currentPlayer?.position ?? 0

    function togglePlaying() {
        if (mpris2Model.currentPlayer) mpris2Model.currentPlayer.PlayPause()
    }
    function next() {
        if (mpris2Model.currentPlayer) mpris2Model.currentPlayer.Next()
    }
    function previous() {
        if (mpris2Model.currentPlayer) mpris2Model.currentPlayer.Previous()
    }
    function seek(positionUs) {
        if (mpris2Model.currentPlayer) {
            mpris2Model.currentPlayer.SetPosition(positionUs)
            root.position = positionUs
        }
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

    // ── Cava spectrum ─────────────────────────────────────────────────────
    //
    // Architecture: cava → FIFO → background "while read" relay → plain file
    // Our Timer polls the plain file with "cat". Reading a tiny file is
    // nearly instant — no FIFO blocking, no heavy per-frame process spawn.

    property bool  _cavaAvailable: false
    property var   cavaBarValues: []
    property string _cavaWidgetId: "music_" + Math.floor(Math.random() * 100000)
    property string _cavaFifo: "/tmp/cava_plasma_" + _cavaWidgetId + ".fifo"
    property string _cavaConf: "/tmp/cava_plasma_" + _cavaWidgetId + ".conf"
    property string _cavaOut:  "/tmp/cava_plasma_" + _cavaWidgetId + ".out"
    property string _cavaPidFile: "/tmp/cava_plasma_" + _cavaWidgetId + ".pid"
    property bool   _cavaStarted: false

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var stdout = data["stdout"] ?? ""

            if (source.indexOf("which cava") !== -1) {
                root._cavaAvailable = stdout.trim().length > 0
                if (root._cavaAvailable) root._startCava()
            } else if (source.indexOf("cat " + root._cavaOut) !== -1) {
                root._parseCavaFrame(stdout)
            }

            disconnectSource(source)
        }
        function exec(cmd) { connectSource(cmd) }
    }

    function _startCava() {
        if (_cavaStarted) return
        _cavaStarted = true

        var bars = plasmoid.configuration.spectrumBars
        var conf = "[general]\n"
        conf += "bars = " + bars + "\n"
        conf += "framerate = 30\n\n"
        conf += "[input]\n"
        conf += "method = pulse\n"
        conf += "source = auto\n\n"
        conf += "[output]\n"
        conf += "method = raw\n"
        conf += "raw_target = " + _cavaFifo + "\n"
        conf += "data_format = ascii\n"
        conf += "ascii_max_range = 100\n"
        conf += "bar_delimiter = 59\n"
        conf += "frame_delimiter = 10\n"
        conf += "channels = mono\n"
        conf += "mono_option = average\n"

        // Write config, create FIFO, start cava, start relay loop.
        // The relay drains the FIFO and always overwrites the .out file
        // with the latest frame — so polling "cat .out" is instant.
        var setup = "printf '%s' '" + conf.replace(/'/g, "'\\''") + "' > " + _cavaConf
        setup += " && mkfifo " + _cavaFifo + " 2>/dev/null"
        setup += " && : > " + _cavaOut
        setup += " && nohup sh -c 'cava -p " + _cavaConf + " &"
        setup += " while IFS= read -r line; do printf \"%s\" \"$line\" > " + _cavaOut + "; done < " + _cavaFifo
        setup += "' >/dev/null 2>&1 & echo $! > " + _cavaPidFile

        executable.exec(setup)
    }

    function _parseCavaFrame(stdout) {
        var line = stdout.trim()
        if (line.length === 0) return

        var parts = line.split(";")
        var vals = []
        for (var i = 0; i < parts.length; i++) {
            var v = parseFloat(parts[i])
            if (!isNaN(v)) vals.push(v / 100.0)
        }
        if (vals.length > 0) cavaBarValues = vals
    }

    property int _pollSeq: 0

    Timer {
        id: cavaPoller
        interval: 42
        running: root._cavaAvailable && root.isPlaying
        repeat: true
        onTriggered: {
            root._pollSeq++
            executable.exec("cat " + root._cavaOut + " #" + root._pollSeq)
        }
    }

    Component.onCompleted: executable.exec("which cava")

    Component.onDestruction: {
        var cleanup = "if [ -f " + _cavaPidFile + " ]; then"
        cleanup += " kill $(cat " + _cavaPidFile + ") 2>/dev/null;"
        cleanup += " fi;"
        cleanup += " pkill -f 'cava -p " + _cavaConf + "' 2>/dev/null;"
        cleanup += " rm -f " + _cavaFifo + " " + _cavaConf + " " + _cavaOut + " " + _cavaPidFile
        executable.exec(cleanup)
    }

    // ── Volume (for bar mode mute toggle) ─────────────────────────────────

    readonly property real playerVolume: mpris2Model.currentPlayer?.volume ?? -1
    property bool _muted: false
    property real _volumeBeforeMute: 1.0

    function toggleMute() {
        if (!mpris2Model.currentPlayer) return
        if (playerVolume < 0) return
        if (_muted) {
            mpris2Model.currentPlayer.volume = _volumeBeforeMute
            _muted = false
        } else {
            _volumeBeforeMute = playerVolume
            mpris2Model.currentPlayer.volume = 0
            _muted = true
        }
    }

    // ── UI ─────────────────────────────────────────────────────────────────

    fullRepresentation: Item {
        id: full
        Layout.preferredWidth: 200
        Layout.preferredHeight: 200
        Layout.minimumWidth: 80
        Layout.minimumHeight: 60

        readonly property real _ar: full.width / Math.max(1, full.height)
        readonly property string _layout:
            _ar >= 3.0  ? "bar"
          : _ar >= 1.6  ? "wide"
          : _ar <= 0.6  ? "tall"
          :               "square"

        LiquidGlass {
            id: glass
            anchors.fill: parent
            radius: plasmoid.configuration.cornerRadius
            roundness: plasmoid.configuration.roundnessX10 / 10
            refractThickness: plasmoid.configuration.refractThickness
            refractIOR: plasmoid.configuration.refractIORx100 / 100
            refractScale: plasmoid.configuration.refractScale
            tint: colors.glassTint
            tintAlpha: plasmoid.configuration.tintAlphaPct / 100
            chromaStrength: plasmoid.configuration.chromaStrengthPct / 100
            specStrength: plasmoid.configuration.specStrengthPct / 100
            blurRadius: plasmoid.configuration.blurRadiusPx
            realtimeRefraction: plasmoid.configuration.realtimeRefraction
            fallbackOpacity: colors.glassFallbackOpacity
            solidMode: colors.isSolid
            solidColor: colors.solidBackground
        }

        SquareLayout {
            anchors.fill: parent
            visible: full._layout === "square"
            colors: colors
            fontFamily: sfRegular.name
            fontFamilyThin: sfThin.name
            track: root.track
            artist: root.artist
            albumArt: root.albumArt
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

        TallLayout {
            anchors.fill: parent
            visible: full._layout === "tall"
            colors: colors
            fontFamily: sfRegular.name
            fontFamilyThin: sfThin.name
            track: root.track
            artist: root.artist
            albumArt: root.albumArt
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

        WideLayout {
            anchors.fill: parent
            visible: full._layout === "wide"
            colors: colors
            fontFamily: sfRegular.name
            fontFamilyThin: sfThin.name
            track: root.track
            artist: root.artist
            albumArt: root.albumArt
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

        BarLayout {
            anchors.fill: parent
            visible: full._layout === "bar"
            colors: colors
            fontFamily: sfRegular.name
            fontFamilyThin: sfThin.name
            track: root.track
            artist: root.artist
            albumArt: root.albumArt
            isPlaying: root.isPlaying
            canGoPrevious: root.canGoPrevious
            canGoNext: root.canGoNext
            canPlay: root.canPlay
            canPause: root.canPause
            position: root.position
            length: root.length
            cavaBarValues: root.cavaBarValues
            cavaAvailable: root._cavaAvailable
            playerVolume: root.playerVolume
            isMuted: root._muted
            onTogglePlaying: root.togglePlaying()
            onNextTrack: root.next()
            onPreviousTrack: root.previous()
            onSeek: function(pos) { root.seek(pos) }
            onToggleMute: root.toggleMute()
            formatTime: root.formatTime
        }
    }
}
