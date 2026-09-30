import QtQuick
import "../../components"
import "../../components/nothing"

// Sunrise / sunset, Nothing style.
//
// Same data as the Liquid Glass sunrise tile and no second source: GeoLocation
// resolves the coordinates (GeoClue first when the setting allows, then the
// prayer settings / Omarchy's weather location / the manual values), and the
// vendored solar engine behind PrayerTimes turns them into sunrise, sunset,
// and the position between the two. No network, no timer here - PrayerTimes
// already ticks and republishes `dayProgress`.
//
// The twin strokes a half-ellipse on a Canvas. This one is the same arc, laid
// out as a row of dots: the passed ones dim, the sun's own dot red and
// larger, the rest of the day faint.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    GeoLocation {
        id: geo
        useGeoclue: plugin.settings.useGeoclue
        fallbackLatitude: plugin.settings.latitude
        fallbackLongitude: plugin.settings.longitude
    }

    PrayerTimes {
        id: sun
        overrideLatitude: geo.latitude
        overrideLongitude: geo.longitude
    }

    readonly property string riseText: sun.sunriseText !== "" ? sun.sunriseText : "--:--"
    readonly property string setText: sun.sunsetText !== "" ? sun.sunsetText : "--:--"

    // The tile counts down to the NEXT horizon crossing: while the sun is up
    // that is sunset, and once it is down it is the morning's sunrise. The
    // header, the hero time and the footer label all follow that one choice,
    // and the footer keeps the other time on screen.
    readonly property bool day: sun.isDaylight
    readonly property string nextLabel: day ? "Sunset" : "Sunrise"
    readonly property string nextText: day ? setText : riseText
    readonly property string otherLabel: day ? "Sunrise" : "Sunset"
    readonly property string otherText: day ? riseText : setText
    readonly property string sourceText: sun.ok
        ? ((geo.label !== "" ? geo.label + " · " : "") + geo.source)
        : sun.error

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

        // ── Header ─────────────────────────────────────────────────────
        NLabel {
            id: header
            theme: nothing
            loud: true
            text: full.nextLabel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: dayBadge.visible ? dayBadge.left : parent.right
            anchors.margins: nothing.pad
            anchors.rightMargin: dayBadge.visible ? nothing.gap : nothing.pad
            elide: Text.ElideRight
        }

        NBadge {
            id: dayBadge
            theme: nothing
            active: sun.isDaylight
            label: sun.isDaylight ? "Day" : "Night"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: nothing.pad
            visible: full.width >= nothing.px(150)
        }

        // ── Stage: the rise time, and the arc it starts ────────────────
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

            Item {
                id: heroBox
                anchors.top: parent.top
                anchors.left: parent.left
                // Wide tile: the time keeps the left column and the arc gets
                // the width the horizontal tile actually adds - the same
                // split the Liquid Glass twin makes, for the same reason.
                // An explicit width in both branches, never an anchor in one
                // and a width in the other - mixing the two leaves the item
                // without a usable width.
                width: full.isWide ? Math.round(stage.width * 0.44) : stage.width
                height: full.isWide ? stage.height
                                    : Math.round(stage.height * (full.isBig ? 0.44 : 0.48))

                NMono {
                    width: parent.width
                    theme: nothing
                    text: full.nextText
                    font.pixelSize: Math.max(nothing.fBody,
                        Math.min(nothing.px(46), Math.round(heroBox.height * 0.62)))
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: nothing.fMicro
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ── The arc: a dotted parabola from horizon to horizon ──────
            Item {
                id: arcBox
                anchors.right: parent.right
                anchors.left: full.isWide ? heroBox.right : parent.left
                anchors.leftMargin: full.isWide ? nothing.pad : 0
                anchors.top: full.isWide ? parent.top : heroBox.bottom
                anchors.topMargin: full.isWide ? 0 : nothing.gap
                anchors.bottom: parent.bottom

                // An odd count so one dot lands on the apex - noon is a
                // position on this arc, not a gap between two dots.
                readonly property int dotCount: {
                    var n = Math.round(arcBox.width / nothing.px(14))
                    n = Math.max(7, Math.min(29, n))
                    return (n % 2 === 0) ? n + 1 : n
                }
                readonly property real step: arcBox.dotCount > 0
                    ? arcBox.width / arcBox.dotCount : 0
                readonly property real dotSize: Math.max(2, Math.min(
                    arcBox.step * 0.44, nothing.px(7)))
                readonly property real sunSize: arcBox.dotSize * 1.9
                readonly property real progress:
                    Math.max(0, Math.min(1, sun.dayProgress))
                readonly property int sunIndex:
                    Math.round(arcBox.progress * (arcBox.dotCount - 1))
                // Dot centres: the two ends rest just above the horizon
                // hairline, the apex leaves room for the fat sun dot.
                readonly property real baseCy:
                    arcBox.height - nothing.hair - arcBox.dotSize / 2
                readonly property real rise: Math.max(nothing.px(8),
                    arcBox.baseCy - arcBox.sunSize / 2)

                Repeater {
                    model: arcBox.dotCount

                    delegate: Rectangle {
                        id: arcDot
                        required property int index
                        readonly property real frac: arcBox.dotCount > 1
                            ? arcDot.index / (arcBox.dotCount - 1) : 0
                        readonly property bool isSun: arcDot.index === arcBox.sunIndex

                        width: arcDot.isSun ? arcBox.sunSize : arcBox.dotSize
                        height: arcDot.width
                        radius: arcDot.width / 2
                        antialiasing: true
                        // Red only while the sun is actually up: before
                        // sunrise and after sunset the marker parks at the
                        // end of the arc and goes quiet.
                        color: arcDot.isSun
                            ? (sun.isDaylight ? nothing.red : nothing.onDim)
                            : (arcDot.index < arcBox.sunIndex
                                ? nothing.onDim : nothing.onFaint)
                        x: (arcDot.index + 0.5) * arcBox.step - arcDot.width / 2
                        y: arcBox.baseCy - Math.sin(arcDot.frac * Math.PI) * arcBox.rise
                           - arcDot.height / 2

                        Behavior on color { ColorAnimation { duration: nothing.fast } }
                    }
                }

                // The horizon.
                NDivider {
                    theme: nothing
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }

        // ── Footer: sunset, and where the coordinates came from ─────────
        Column {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: nothing.pad
            spacing: nothing.gap

            Item {
                width: parent.width
                height: Math.max(setLabel.implicitHeight, setTime.implicitHeight)

                NLabel {
                    id: setLabel
                    theme: nothing
                    text: full.otherLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }
                NMono {
                    id: setTime
                    theme: nothing
                    text: full.otherText
                    font.pixelSize: nothing.fLabel
                    anchors.left: setLabel.right
                    anchors.leftMargin: nothing.gap
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: full.isWide ? Text.AlignLeft : Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            // Never silently wrong about its own position: the tile names the
            // source that won, or the engine's error if none resolved.
            NLabel {
                width: parent.width
                theme: nothing
                text: full.sourceText
                color: nothing.onQuiet
                font.pixelSize: nothing.fMicro
                elide: Text.ElideRight
                // The small square has no line to spare for provenance; it
                // shows only when the fix failed and the tile would
                // otherwise be quietly wrong.
                visible: full.isWide || full.isBig || !sun.ok
            }
        }
    }
}
