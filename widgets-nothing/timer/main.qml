import QtQuick
import "../../components"
import "../../components/nothing"

// Timer, Nothing style.
//
// The state machine is the Liquid Glass widget's, line for line: the four
// states (0 IDLE, 1 RUNNING, 2 PAUSED, 3 FINISHED), the absolute `targetTime`
// the countdown is derived from (never a decrementing counter, so it stays
// correct across dropped frames and suspend), the 1 s start delay and its
// pause-inside-the-delay fix, and the same notify-send on completion. The
// preset durations are the same six.
//
// The timer type declares no per-instance settings (WidgetFields.forType
// returns nothing for it) and the twin's only `plugin.settings` reads
// are glass knobs, so this file reads no configuration at all - the correct
// way to keep the two styles' settings identical here is to read none.
//
// Presentation: the remaining time as dot-matrix digits, which is the widget
// the matrix was drawn for; elapsed fraction as a segmented bar (or a ring on
// the large tile); red only while the clock is actually running.
Item {
    id: root
    anchors.fill: parent

    // ── State ─────────────────────────────────────────────────────────────
    // 0 = IDLE, 1 = RUNNING, 2 = PAUSED, 3 = FINISHED
    property int  timerState: 0
    property int  selectedMinutes: 0
    property int  selectedSeconds: 0
    property real remainingMs: 0
    property real targetTime: 0
    property real totalMs: 0

    readonly property int displayMinutes: Math.floor(remainingMs / 60000)
    readonly property int displaySeconds: Math.floor((remainingMs % 60000) / 1000)

    // ── Countdown tick ────────────────────────────────────────────────────
    Timer {
        id: countdownTick
        interval: 100
        repeat: true
        running: root.timerState === 1 && !startDelayTimer.running
        onTriggered: {
            var now = Date.now()
            root.remainingMs = Math.max(0, root.targetTime - now)
            if (root.remainingMs === 0) {
                root.timerState = 3
                notifier.send("Timer", "Time's up!", "normal")
            }
        }
    }

    // Delay between pressing Start and the countdown actually beginning -
    // here it is what the digits' reveal animation plays over.
    Timer {
        id: startDelayTimer
        interval: 1000
        repeat: false
        onTriggered: root.targetTime = Date.now() + root.remainingMs
    }

    // ── State transitions ─────────────────────────────────────────────────
    function startTimer() {
        var ms = (selectedMinutes * 60 + selectedSeconds) * 1000
        if (ms <= 0) return
        totalMs = ms
        remainingMs = ms
        timerState = 1
        startDelayTimer.restart()
    }

    function pauseTimer() {
        // Pause inside the 1 s start delay: targetTime has not been set for
        // this run yet, so keep the full duration and disarm the delay.
        if (startDelayTimer.running) {
            startDelayTimer.stop()
            timerState = 2
            return
        }
        remainingMs = Math.max(0, targetTime - Date.now())
        timerState = 2
    }

    function resumeTimer() {
        targetTime = Date.now() + remainingMs
        timerState = 1
    }

    function cancelTimer() {
        startDelayTimer.stop()
        timerState = 0
        remainingMs = 0
    }

    // Same presets as the twin's ListModel, minus its per-preset pill colour:
    // this style has exactly one accent and a six-colour palette is not it.
    readonly property var presets: [
        { label: "1",  mins: 1,  secs: 0 },
        { label: "2",  mins: 2,  secs: 0 },
        { label: "3",  mins: 3,  secs: 0 },
        { label: "5",  mins: 5,  secs: 0 },
        { label: "10", mins: 10, secs: 0 },
        { label: "15", mins: 15, secs: 0 }
    ]

    // Picking a preset starts the run, exactly as it does on the Liquid Glass
    // tile; after a cancel the selection is retained, so the action button
    // restarts the last duration without another trip to the chips.
    function pick(mins, secs) {
        if (root.timerState !== 0) return
        root.selectedMinutes = mins
        root.selectedSeconds = secs
        root.startTimer()
    }

    Notify { id: notifier }

    Item {
        id: full
        anchors.fill: parent

        // The three grid presets: 192x192, 400x192, 400x400.
        readonly property bool isWide: full.width >= full.height * 1.6
        readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

        readonly property real elapsed: root.totalMs > 0
            ? Math.max(0, Math.min(1, 1 - root.remainingMs / root.totalMs)) : 0
        readonly property bool active: root.timerState !== 0
        readonly property bool running: root.timerState === 1
        readonly property bool finished: root.timerState === 3

        readonly property string clockText: {
            var m = root.timerState === 0
                ? root.selectedMinutes : root.displayMinutes
            var s = root.timerState === 0
                ? root.selectedSeconds : root.displaySeconds
            var mm = m < 10 ? "0" + m : "" + Math.min(99, m)
            var ss = s < 10 ? "0" + s : "" + s
            return mm + ":" + ss
        }

        readonly property string stateLabel: {
            if (root.timerState === 1) return startDelayTimer.running ? "STARTING" : "RUNNING"
            if (root.timerState === 2) return "PAUSED"
            if (root.timerState === 3) return "TIME'S UP"
            return "TIMER"
        }

        readonly property real btn: Math.max(nothing.px(24),
            Math.min(nothing.px(44), Math.min(full.width, full.height) * (full.isBig ? 0.13 : 0.17)))
        readonly property real chip: Math.max(nothing.px(20),
            Math.min(nothing.px(30), full.height * 0.11))

        NCard {
            id: card
            theme: nothing
            anchors.fill: parent

            NDotField {
                theme: nothing
                anchors.fill: parent
                anchors.margins: nothing.pad
                intensity: 0.4
                visible: full.isBig
            }

            // ── Header ────────────────────────────────────────────────────
            NLabel {
                id: header
                theme: nothing
                text: full.stateLabel
                loud: full.running || full.finished
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: mark.left
                anchors.rightMargin: nothing.gap
                anchors.topMargin: nothing.pad
                anchors.leftMargin: nothing.pad
                elide: Text.ElideRight
            }

            NBadge {
                id: mark
                theme: nothing
                active: full.running || full.finished
                label: full.isWide || full.isBig
                    ? (root.totalMs > 0 ? Math.round(root.totalMs / 60000) + " MIN" : "SET")
                    : ""
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: nothing.pad
                anchors.rightMargin: nothing.pad

                // A tick of the accent while the clock runs: the badge is the
                // one thing on the card that moves on its own.
                SequentialAnimation on opacity {
                    running: full.running
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.55; duration: 500; easing.type: nothing.ease }
                    NumberAnimation { to: 1.0;  duration: 500; easing.type: nothing.ease }
                    onStopped: mark.opacity = 1.0
                }
            }

            // ── Wide only: the presets as a side list ─────────────────────
            Item {
                id: sidePresets
                visible: full.isWide
                width: full.isWide ? Math.round(full.width * 0.30) : 0
                anchors.left: parent.left
                anchors.leftMargin: nothing.pad
                anchors.top: header.bottom
                anchors.topMargin: nothing.gap
                anchors.bottom: parent.bottom
                anchors.bottomMargin: nothing.pad

                Column {
                    anchors.fill: parent
                    spacing: Math.max(nothing.px(2),
                        (parent.height - root.presets.length * full.chip) / (root.presets.length - 1))

                    Repeater {
                        model: root.presets

                        NButton {
                            required property var modelData
                            theme: nothing
                            width: sidePresets.width
                            height: full.chip
                            label: modelData.label + " MIN"
                            enabled: !full.active
                            active: !full.active
                                && root.selectedMinutes === modelData.mins
                                && root.selectedSeconds === modelData.secs
                            onClicked: root.pick(modelData.mins, modelData.secs)
                        }
                    }
                }
            }

            NDivider {
                id: sideRule
                theme: nothing
                vertical: true
                visible: full.isWide
                anchors.left: sidePresets.right
                anchors.leftMargin: nothing.pad
                anchors.top: sidePresets.top
                anchors.bottom: sidePresets.bottom
            }

            // ── Stage: the remaining time ─────────────────────────────────
            Item {
                id: stage
                anchors.top: header.bottom
                anchors.topMargin: nothing.gap
                anchors.left: full.isWide ? sideRule.right : parent.left
                anchors.leftMargin: nothing.pad
                anchors.right: parent.right
                anchors.rightMargin: nothing.pad
                anchors.bottom: footer.top
                anchors.bottomMargin: nothing.gap

                // Dot size from the space, never a constant: the same five
                // glyphs have to read inside a 192 px tile and fill a 400 px
                // one. "MM:SS" is 27 dot columns wide (5 + 5 + 3 + 5 + 5,
                // plus a column between glyphs) and 7 rows tall, so the tile
                // with 372 px of stage gets a 10 px dot and the one with
                // 164 px gets a 3.5 px dot - same glyph, no clipping either
                // way. An elapsed RING was tried here and lost: fitting 27
                // columns inside a circle costs more than half the digit
                // size, and on this widget the digits are the point. The
                // elapsed fraction stays on the segmented bar in the footer.
                readonly property real dotSize: {
                    var cols = 27
                    var rows = 7
                    var byW = (stage.width - (cols - 1) * 2) / cols
                    var byH = (stage.height - (rows - 1) * 2) / rows
                    // 0.80, not 1.0: the gap between dots is 0.34 of a dot,
                    // so the naive fit runs the glyph into the padding.
                    return Math.max(2, Math.min(byW, byH) * 0.80)
                }

                NDotMatrix {
                    id: digits
                    theme: nothing
                    anchors.centerIn: parent
                    text: full.clockText
                    dot: stage.dotSize
                    gap: Math.max(1, stage.dotSize * 0.34)
                    onColor: full.finished ? nothing.red
                        : full.active ? nothing.on : nothing.onDim
                    offColor: nothing.onFaint

                    // The reveal the start delay exists for: the digits come
                    // up dot by dot in the second before the count begins.
                    NumberAnimation on reveal {
                        id: revealIn
                        running: false
                        from: 0
                        to: 1
                        duration: 900
                        easing.type: nothing.ease
                    }

                    // FINISHED blinks - the one moment the card shouts.
                    SequentialAnimation on opacity {
                        running: full.finished
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 320 }
                        NumberAnimation { to: 1.0;  duration: 320 }
                        onStopped: digits.opacity = 1.0
                    }
                }

                Connections {
                    target: root
                    function onTimerStateChanged() {
                        if (root.timerState === 1 && startDelayTimer.running) {
                            digits.reveal = 0
                            revealIn.restart()
                        } else if (root.timerState === 0) {
                            revealIn.stop()
                            digits.reveal = 1
                        }
                    }
                }
            }

            // ── Footer: elapsed bar, presets (square tiles), transport ────
            Item {
                id: footer
                anchors.left: full.isWide ? sideRule.right : parent.left
                anchors.leftMargin: nothing.pad
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: nothing.pad
                anchors.bottomMargin: nothing.pad
                height: progress.height + nothing.gap + buttons.height + nothing.gap
                     + (chips.visible ? chips.height + nothing.gap : 0)

                NProgress {
                    id: progress
                    theme: nothing
                    // The elapsed fraction, on every tile size.
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: nothing.px(5)
                    segments: Math.max(8, Math.min(40, Math.round(footer.width / nothing.px(9))))
                    accent: full.running || full.finished
                    value: full.elapsed
                }

                // Small and large squares carry their presets here, as a row
                // of chips: three on the 192 tile, all six on the 400 one.
                Row {
                    id: chips
                    visible: !full.isWide
                    anchors.top: progress.bottom
                    anchors.topMargin: nothing.gap
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: full.chip
                    spacing: nothing.px(4)

                    readonly property int shown: full.isBig ? 6 : 3
                    // 1 / 5 / 10 on the small tile - the three a desktop
                    // timer is actually set to - and every preset on the big.
                    readonly property var picks: full.isBig
                        ? [0, 1, 2, 3, 4, 5] : [0, 3, 4]

                    Repeater {
                        model: chips.shown

                        NButton {
                            required property int index
                            readonly property var preset: root.presets[chips.picks[index]]
                            theme: nothing
                            width: (chips.width - (chips.shown - 1) * nothing.px(4)) / chips.shown
                            height: full.chip
                            label: preset.label
                            enabled: !full.active
                            active: !full.active
                                && root.selectedMinutes === preset.mins
                                && root.selectedSeconds === preset.secs
                            onClicked: root.pick(preset.mins, preset.secs)
                        }
                    }
                }

                // ── Transport ─────────────────────────────────────────────
                Row {
                    id: buttons
                    anchors.bottom: parent.bottom
                    x: Math.max(0, (parent.width - buttons.width) / 2)
                    height: full.btn
                    spacing: nothing.gap

                    NButton {
                        theme: nothing
                        width: full.btn * 2.2
                        height: full.btn
                        visible: full.active
                        label: "CANCEL"
                        onClicked: root.cancelTimer()
                    }

                    NButton {
                        theme: nothing
                        width: full.btn * 2.2
                        height: full.btn
                        active: full.running
                        enabled: full.active
                            || root.selectedMinutes > 0 || root.selectedSeconds > 0
                        label: root.timerState === 1 ? "PAUSE"
                            : root.timerState === 2 ? "RESUME"
                            : root.timerState === 3 ? "RESET" : "START"
                        onClicked: {
                            if (root.timerState === 0) root.startTimer()
                            else if (root.timerState === 1) root.pauseTimer()
                            else if (root.timerState === 2) root.resumeTimer()
                            else root.cancelTimer()
                        }
                    }
                }
            }
        }
    }
}
