import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.notification
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
        running: root.timerState === 1
        onTriggered: {
            var now = Date.now()
            root.remainingMs = Math.max(0, root.targetTime - now)
            if (root.remainingMs === 0) {
                root.timerState = 3
                timerFinishedNotification.sendEvent()
            }
        }
    }

    Notification {
        id: timerFinishedNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        title: "Timer"
        text: "Time's up!"
        urgency: Notification.NormalUrgency
    }

    // ── State transitions ─────────────────────────────────────────────────
    function startTimer() {
        var ms = (selectedMinutes * 60 + selectedSeconds) * 1000
        if (ms <= 0) return
        totalMs = ms
        remainingMs = ms
        targetTime = Date.now() + ms
        timerState = 1
    }

    function pauseTimer() {
        remainingMs = Math.max(0, targetTime - Date.now())
        timerState = 2
    }

    function resumeTimer() {
        targetTime = Date.now() + remainingMs
        timerState = 1
    }

    function cancelTimer() {
        timerState = 0
        remainingMs = 0
    }

    function restartTimer() {
        remainingMs = totalMs
        targetTime = Date.now() + totalMs
        timerState = 1
    }

    // ── UI ────────────────────────────────────────────────────────────────
    fullRepresentation: Item {
        id: full
        Layout.preferredWidth: 240
        Layout.preferredHeight: 280
        Layout.minimumWidth: 200
        Layout.minimumHeight: 240

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
            realtimeRefraction: plasmoid.configuration.realtimeRefraction
            fallbackOpacity: colors.glassFallbackOpacity
            solidMode: colors.isSolid
            solidColor: colors.solidBackground
        }

        // ── Picker (IDLE) ─────────────────────────────────────────────────
        Item {
            id: pickerArea
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
                spacing: 32

                CylinderPicker {
                    id: minPicker
                    count: 100
                    currentIndex: root.selectedMinutes
                    label: "min"
                    fontFamily: sfThin.name
                    labelFontFamily: sfRegular.name
                    textColor: colors.foreground
                    separatorColor: colors.foreground
                    height: pickerArea.height * 0.82
                    width: Math.min(pickerArea.width * 0.28, 80)
                    onCurrentIndexChanged: root.selectedMinutes = currentIndex
                }

                CylinderPicker {
                    id: secPicker
                    count: 60
                    currentIndex: root.selectedSeconds
                    label: "sec"
                    fontFamily: sfThin.name
                    labelFontFamily: sfRegular.name
                    textColor: colors.foreground
                    separatorColor: colors.foreground
                    height: pickerArea.height * 0.82
                    width: Math.min(pickerArea.width * 0.28, 80)
                    onCurrentIndexChanged: root.selectedSeconds = currentIndex
                }
            }
        }

        // ── Countdown (RUNNING / PAUSED / FINISHED) ───────────────────────
        Item {
            id: countdownArea
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
                width: parent.width * 0.9
                height: parent.height * 0.7
                minutes: root.displayMinutes
                seconds: root.displaySeconds
                fontFamily: sfThin.name
                textColor: colors.foreground
                digitOpacity: colors.isGlass ? 0.72 : 0.95
                flashing: root.timerState === 3
            }
        }

        // ── Button row ─────────────────────────────────────────────────────
        Item {
            id: buttonRow
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                bottomMargin: 18
            }
            height: btnSize

            readonly property real btnSize: Math.min(full.width, full.height) * 0.26

            // Cancel button — only visible when timer is active
            TimerButton {
                id: cancelBtn
                diameter: buttonRow.btnSize
                text: "Cancel"
                fontFamily: sfRegular.name
                backgroundColor: Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.18)
                textColor: colors.foreground
                visible: root.timerState !== 0
                anchors.left: parent.left
                anchors.leftMargin: (parent.width / 2 - diameter) / 2
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.cancelTimer()
            }

            // Start / Pause / Resume button
            TimerButton {
                id: actionBtn
                diameter: buttonRow.btnSize
                fontFamily: sfRegular.name
                textColor: "#ffffff"

                text: {
                    if (root.timerState === 0) return "Start"
                    if (root.timerState === 1) return "Pause"
                    if (root.timerState === 2) return "Resume"
                    return "Start"
                }

                backgroundColor: root.timerState === 1 ? "#ff9f0a" : "#30d158"

                Behavior on backgroundColor { ColorAnimation { duration: 200 } }
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                // When IDLE: center the button; when active: right half
                x: root.timerState === 0
                    ? (parent.width - diameter) / 2
                    : parent.width / 2 + (parent.width / 2 - diameter) / 2

                anchors.verticalCenter: parent.verticalCenter

                enabled: root.timerState !== 0 || (root.selectedMinutes > 0 || root.selectedSeconds > 0)
                opacity: enabled ? 1.0 : 0.4
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
