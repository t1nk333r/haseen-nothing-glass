import QtQuick

Item {
    id: spectrum

    property var barValues: []
    property bool cavaAvailable: false
    property bool isPlaying: false
    property color barColor: "#ffffff"
    property real barOpacity: 0.65
    property int barCount: 18
    property real maxBarHeight: height

    property var _displayValues: []

    onBarValuesChanged: {
        if (cavaAvailable && barValues.length > 0)
            _displayValues = barValues
    }

    Timer {
        id: fakeTimer
        interval: 180
        running: !spectrum.cavaAvailable && spectrum.isPlaying
        repeat: true
        onTriggered: {
            var arr = []
            var mid = spectrum.barCount / 2.0
            for (var i = 0; i < spectrum.barCount; i++) {
                var dist = Math.abs(i - mid) / mid
                var base = (1.0 - dist * 0.6) * 0.7
                var jitter = Math.random() * 0.3
                arr.push(Math.min(1.0, base * (0.5 + jitter)))
            }
            spectrum._displayValues = arr
        }
    }

    Timer {
        id: fadeOutTimer
        interval: 180
        running: !spectrum.isPlaying && _hasNonZero()
        repeat: true
        onTriggered: {
            var arr = []
            var src = spectrum._displayValues
            for (var i = 0; i < src.length; i++)
                arr.push(Math.max(0, src[i] - 0.08))
            spectrum._displayValues = arr
        }
    }

    function _hasNonZero() {
        for (var i = 0; i < _displayValues.length; i++)
            if (_displayValues[i] > 0.01) return true
        return false
    }

    Item {
        id: barContainer
        anchors.centerIn: parent
        width: barCount * _barW + (barCount - 1) * _gap
        height: spectrum.maxBarHeight

        property real _barW: Math.max(2, Math.min(4, (spectrum.width - (barCount - 1) * 2) / barCount))
        property real _gap: barCount > 1
            ? Math.max(1, (spectrum.width - barCount * _barW) / (barCount - 1))
            : 0

        Row {
            anchors.centerIn: parent
            spacing: barContainer._gap

            Repeater {
                model: spectrum.barCount

                Item {
                    width: barContainer._barW
                    height: barContainer.height

                    Rectangle {
                        width: parent.width
                        radius: width / 2
                        color: spectrum.barColor
                        opacity: spectrum.barOpacity
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter

                        property real _val: {
                            var vals = spectrum._displayValues
                            if (index < vals.length) return vals[index]
                            return 0.05
                        }

                        height: Math.max(width, _val * barContainer.height)

                        Behavior on height {
                            NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }
        }
    }
}
