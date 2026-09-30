import QtQuick
import "../../components"
import "widget"

// Port of packages/timer/contents/ui/main.qml, per PORTING.md.
//
// Two structural notes:
//
//   * This file keeps BOTH ids from the original — `root` for the timer state
//     machine (which lived on the PlasmoidItem) and `full` for the visual tree
//     (which lived inside fullRepresentation). Collapsing them into one would
//     have meant rewriting every `root.timerState` / `full._minSide` reference
//     in 250 lines of layout for no benefit; the extra Item costs nothing and
//     keeps the diff against upstream readable.
//   * The `compactRepresentation` (panel form factor: progress ring + label)
//     is dropped, along with the `Plasmoid.formFactor` clamp on the glass
//     corner radius. A desktop widget type has no compact mode; the bar is a
//     separate entry point (see PORTING.md item 14) and plan 009 does not put
//     the timer there.
//
// `Notification` -> `Notify` (notify-send; see components/Notify.qml),
// i18n("Presets") -> "Presets", PlasmaBackdrop dropped, Layout.* dropped
// (minimum size now lives in WidgetRegistry.qml), Kirigami.Theme
// .backgroundColor -> theme.systemBackground, `Font.Regular` -> `Font.Normal`
// on the Presets title (no such enum in Qt 6; same fix in
// widget/CylinderPicker.qml), and pauseTimer() handles a pause inside the
// start delay (see its comment).
//
// The countdown is driven off an absolute `targetTime`, never a decrementing
// counter — that is what keeps it correct across dropped frames and suspend.
// Its Timer is deliberately NOT gated on Qt.application.state: this surface is
// never the focused application, so such a gate would stop the countdown.

Item {
    id: root
    anchors.fill: parent

    MacOSColors {
        id: colors
        styleMode: plugin.settings.styleMode
        appearance: plugin.settings.appearance
        systemBackground: theme.systemBackground
        themePalette: theme.palette
    }

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

    // Delay between pressing Start and the countdown actually beginning —
    // gives the RollingDigit entrance animations time to play first
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
        // this run yet, so the original computed remainingMs from a stale (or
        // zero) target and left the delay timer armed to overwrite targetTime
        // later. Keep the full duration and disarm the delay instead.
        // (Latent in the Plasma original too.)
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

    // Replaces the Plasma `Notification { componentName: "plasma_workspace" }`
    // block, which is org.kde.notification and does not exist here. Notify.qml
    // hands the same title/body to notify-send as separate argv entries.
    Notify { id: notifier }

    ListModel {
        id: presetsModel
        ListElement { label: "1 min";  mins: 1;  secs: 0; pillColor: "#4ECDC4" }
        ListElement { label: "2 min";  mins: 2;  secs: 0; pillColor: "#45B7D1" }
        ListElement { label: "3 min";  mins: 3;  secs: 0; pillColor: "#96CEB4" }
        ListElement { label: "5 min";  mins: 5;  secs: 0; pillColor: "#FF6B6B" }
        ListElement { label: "10 min"; mins: 10; secs: 0; pillColor: "#DDA0DD" }
        ListElement { label: "15 min"; mins: 15; secs: 0; pillColor: "#FFB347" }
    }

    Item {
        id: full
        anchors.fill: parent

        readonly property bool isWide: full.width >= full.height * 2
        readonly property real wideGap: Math.round(full.height * 0.04)
        readonly property real _minSide: Math.min(width, height)
        readonly property real _btnSize: _minSide * 0.22

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
            solidMode: colors.isSolid
            solidColor: colors.solidBackground
        }

        // ── Left panel: Presets (wide mode only) ──────────────────────────
        Item {
            id: leftPanel
            visible: full.isWide
            clip: true
            anchors {
                top: parent.top
                left: parent.left
                bottom: parent.bottom
                right: rightPanel.left
                rightMargin: full.wideGap
            }

            readonly property real _margin: Math.round(full.height * 0.09)
            readonly property real _cardSize: Math.max(10, Math.round(full.height * 0.052))
            readonly property real _cardSpacing: Math.round(full.height * 0.025)

            Text {
                id: presetsTitle
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: leftPanel._margin
                    leftMargin: leftPanel._margin
                }
                text: "Presets"
                color: colors.foreground
                font.family: colors.uiFont
                font.pixelSize: Math.max(10, Math.round(full.height * 0.058))
                font.weight: Font.Normal
                opacity: 0.55
                font.letterSpacing: 0.5
            }

            ListView {
                id: presetsList
                anchors {
                    top: presetsTitle.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    topMargin: leftPanel._cardSpacing
                    leftMargin: leftPanel._margin
                    rightMargin: leftPanel._margin
                    bottomMargin: leftPanel._margin
                }
                model: presetsModel
                spacing: leftPanel._cardSpacing
                clip: true

                delegate: PresetCard {
                    width: presetsList.width
                    label: model.label
                    pillColor: model.pillColor
                    textColor: colors.foreground
                    fontFamily: colors.uiFont
                    fontSize: leftPanel._cardSize
                    cardBg: colors.cardBackground
                    cardBgOpacity: colors.cardBackgroundOpacity
                    cardHoverOpacity: colors.cardHoverOpacity
                    cardPressOpacity: colors.cardPressOpacity
                    active: root.timerState === 0
                    onClicked: {
                        minPicker.setIndex(model.mins)
                        secPicker.setIndex(model.secs)
                        root.selectedMinutes = model.mins
                        root.selectedSeconds = model.secs
                        root.startTimer()
                    }
                }
            }

        }

        // ── Right panel: Timer content ────────────────────────────────────
        Item {
            id: rightPanel
            width: full.isWide ? full.height : full.width
            anchors {
                top: parent.top
                right: parent.right
                bottom: parent.bottom
            }
        }

        // ── Picker (IDLE) ─────────────────────────────────────────────────
        Item {
            id: pickerArea
            parent: rightPanel
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: buttonRow.top
            }
            visible: root.timerState === 0
            opacity: root.timerState === 0 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Row {
                anchors.centerIn: parent
                // Extra right spacing to account for the label text overflowing picker bounds
                spacing: full._minSide * 0.12

                CylinderPicker {
                    id: minPicker
                    count: 100
                    label: "min"
                    fontFamily: colors.uiFont
                    labelFontFamily: colors.uiFont
                    textColor: colors.foreground
                    separatorColor: colors.foreground
                    labelOpacity: colors.textQuiet
                    fontWeight: Font.Medium
                    fontSizeScale: 0.82
                    height: pickerArea.height * 0.86
                    width: full._minSide * 0.22
                    onCurrentIndexChanged: root.selectedMinutes = currentIndex
                }

                CylinderPicker {
                    id: secPicker
                    count: 60
                    label: "sec"
                    fontFamily: colors.uiFont
                    labelFontFamily: colors.uiFont
                    textColor: colors.foreground
                    separatorColor: colors.foreground
                    labelOpacity: colors.textQuiet
                    fontWeight: Font.Medium
                    fontSizeScale: 0.82
                    height: pickerArea.height * 0.86
                    width: full._minSide * 0.22
                    onCurrentIndexChanged: root.selectedSeconds = currentIndex
                }
            }
        }

        // ── Countdown (RUNNING / PAUSED / FINISHED) ───────────────────────
        Item {
            id: countdownArea
            parent: rightPanel
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: buttonRow.top
            }
            visible: root.timerState !== 0
            opacity: root.timerState !== 0 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 180 } }

            CountdownDisplay {
                anchors.centerIn: parent
                width: parent.width * 0.92
                height: parent.height * 0.75
                minutes: root.displayMinutes
                seconds: root.displaySeconds
                fontFamily: colors.uiFont
                textColor: colors.countdownText
                digitOpacity: 1.0
                flashing: root.timerState === 3
            }
        }

        // ── Button row ─────────────────────────────────────────────────────
        Item {
            id: buttonRow
            parent: rightPanel
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                bottomMargin: full._minSide * 0.08
            }
            height: full._btnSize

            // Cancel — left half, visible when timer is active
            TimerButton {
                id: cancelBtn
                diameter: full._btnSize
                iconSource: Qt.resolvedUrl("widget/icons/cancel.svg")
                iconColor: colors.buttonIcon
                backgroundColor: colors.cancelButtonBg
                visible: root.timerState !== 0
                opacity: root.timerState !== 0 ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width / 4 - diameter / 2
                onClicked: root.cancelTimer()
            }

            // Action button — centered when IDLE, right quarter when active
            TimerButton {
                id: actionBtn
                diameter: full._btnSize

                iconSource: {
                    if (root.timerState === 1) return Qt.resolvedUrl("widget/icons/pause.svg")
                    if (root.timerState === 3) return Qt.resolvedUrl("widget/icons/reload.svg")
                    return Qt.resolvedUrl("widget/icons/play.svg")
                }

                iconColor: colors.actionIconInk(root.timerState === 1 ? colors.actionOrange : colors.actionGreen)
                backgroundColor: root.timerState === 1 ? colors.actionOrangeBg : colors.actionGreenBg

                Behavior on iconColor { ColorAnimation { duration: 180 } }
                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                x: root.timerState === 0
                    ? (parent.width - diameter) / 2
                    : parent.width * 3 / 4 - diameter / 2

                anchors.verticalCenter: parent.verticalCenter

                enabled: root.timerState !== 0 || (root.selectedMinutes > 0 || root.selectedSeconds > 0)
                opacity: enabled ? 1.0 : 0.35
                Behavior on opacity { NumberAnimation { duration: 150 } }

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
