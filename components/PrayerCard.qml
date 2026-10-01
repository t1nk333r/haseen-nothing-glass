import QtQuick

// The prayer card itself - ring, glyph, next athan time, countdown, the next
// prayer's name and the one after it.
//
// It lives here, on its own, because it is rendered in TWO places that must
// look identical: the Liquid Glass desktop widget (widgets/prayer) and this
// machine's lock screen (t1nk33r.lock/LockView.qml, which keeps a copy of
// this file next to a copy of LiquidGlass/MacOSColors). Two hand-written
// versions drifted apart within a day - different fonts, different palette -
// which is exactly what this file exists to prevent.
//
// Everything it needs is injected: it draws no background of its own, so the
// caller wraps it in whatever backdrop it has (LiquidGlass over the wallpaper
// on the desktop, LiquidGlass over the blurred lock wallpaper on the lock
// screen).
Item {
    id: card

    // A PrayerTimes instance.
    required property var prayers
    // A MacOSColors instance.
    required property var colors

    property string fontFamily: ""
    property string arabicFamily: "Noto Kufi Arabic"
    // Only the Nerd Font families carry md-mosque (`fc-list :charset=f1827`).
    property string glyphFamily: "JetBrainsMono Nerd Font"

    // md-mosque. Past U+FFFF, so it cannot be written as a \u escape.
    readonly property string mosqueGlyph: String.fromCodePoint(0xf1827)

    // Proportions are the lock card's originals, expressed against the short
    // side so the card looks the same at 150 px and at 400 px.
    readonly property real side: Math.min(width, height)
    readonly property real pad: Math.round(side * 0.11)
    readonly property real ringSize: Math.round(side * 0.32)

    function nameOf(row) {
        if (!row) return ""
        return card.prayers.isArabic ? row.ar : row.en
    }

    // Progress ring: track, then the elapsed arc from twelve o'clock.
    Canvas {
        id: ring
        x: card.pad
        y: card.pad
        width: card.ringSize
        height: card.ringSize

        onPaint: {
            var p = getContext("2d")
            p.reset()
            var stroke = card.side * 0.055
            var radius = width / 2 - stroke / 2
            if (radius <= 0) return
            p.lineWidth = stroke
            p.lineCap = "round"
            var fg = card.colors.foreground
            p.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.22)
            p.beginPath()
            p.arc(width / 2, height / 2, radius, 0, Math.PI * 2)
            p.stroke()
            if (card.prayers.progress > 0) {
                p.strokeStyle = card.colors.todayAccent
                p.beginPath()
                p.arc(width / 2, height / 2, radius, -Math.PI / 2,
                      -Math.PI / 2 + card.prayers.progress * Math.PI * 2)
                p.stroke()
            }
        }

        // Canvas does not repaint on a bound property change.
        Connections {
            target: card.prayers
            function onProgressChanged() { ring.requestPaint() }
        }
        Connections {
            target: card.colors
            function onForegroundChanged() { ring.requestPaint() }
            function onTodayAccentChanged() { ring.requestPaint() }
        }
        onWidthChanged: requestPaint()

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: card.mosqueGlyph
            color: card.colors.foreground
            font.family: card.glyphFamily
            font.pixelSize: Math.round(card.ringSize * 0.42)
        }
    }

    // Next athan time, level with the ring, with the countdown under it.
    // Width-bounded and allowed to shrink: at the lock screen's 150 px the
    // time ran straight over the ring.
    Column {
        anchors.left: ring.right
        anchors.leftMargin: Math.round(card.pad * 0.5)
        anchors.right: parent.right
        anchors.rightMargin: card.pad
        anchors.verticalCenter: ring.verticalCenter
        spacing: 0

        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: card.prayers.next ? card.prayers.next.timeText : "--:--"
            color: card.colors.foreground
            font.family: card.fontFamily
            font.pixelSize: Math.round(card.side * 0.125)
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 8
            horizontalAlignment: Text.AlignRight
        }
        Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: card.prayers.remainingText !== ""
            text: card.prayers.remainingText
            color: card.colors.todayAccent
            font.family: card.fontFamily
            font.pixelSize: Math.round(card.side * 0.085)
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 7
            horizontalAlignment: Text.AlignRight
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: card.pad
        anchors.right: parent.right
        anchors.rightMargin: card.pad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: card.pad
        spacing: Math.round(card.side * 0.01)

        // Arabic reads right-to-left, so the names hang off the right edge of
        // the card rather than the left - matching how the omaprayers panels
        // set the same strings.
        Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: card.prayers.isArabic ? Text.AlignRight : Text.AlignLeft
            text: card.nameOf(card.prayers.next)
            color: card.colors.foreground
            font.family: card.prayers.isArabic ? card.arabicFamily : card.fontFamily
            font.pixelSize: Math.round(card.side * 0.19)
        }
        Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            // Falls back to the engine's own error text rather than going
            // blank: a lock screen is the worst place to hide a dead source.
            horizontalAlignment: card.prayers.isArabic ? Text.AlignRight : Text.AlignLeft
            text: card.prayers.after
                ? card.nameOf(card.prayers.after) + "  " + card.prayers.after.timeText
                : (card.prayers.ok ? "" : card.prayers.error)
            color: card.colors.todayAccent
            opacity: card.prayers.ok ? 1.0 : 0.7
            font.family: card.prayers.isArabic ? card.arabicFamily : card.fontFamily
            font.pixelSize: Math.round(card.side * 0.10)
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 8
        }
    }
}
