import QtQuick
import QtQuick.Effects

Item {
    id: root

    property string value: "0"
    property color textColor: "#ffffff"
    property string fontFamily: ""
    property real fontPixelSize: 96
    property real digitOpacity: 0.7
    property real maxBlur: 1.0
    property int duration: 520

    readonly property real _glyphHeight: fm.ascent + fm.descent
    readonly property real _p: clamp(_progress, 0, 1)
    readonly property real _speed: Math.sin(Math.PI * _p)

    // Amplitude of the spring shoot-back, as a fraction of glyph height.
    property real springAmplitude: 0.12

    // Damped spring: overshoots the rest line and settles with a small bounce.
    // _springT runs 0->1 linearly; the curve is exp-decayed cos so the digit
    // travels up, crosses past zero, and rings down smoothly to rest.
    // f(0)=1 (full pull), f(1)~=0 (settled). Multiplied by -amplitude so the
    // initial pull is downward and the shoot-back overshoots upward.
    readonly property real _springOffset:
        -Math.exp(-5.2 * _springT) * Math.cos(7.6 * _springT)
        * _glyphHeight * springAmplitude
    property string _restValue: value
    property string _fromValue: value
    property string _toValue: value
    property bool _transitioning: false
    property real _progress: 1
    property real _springT: 0
    property real _incomingScale: 1
    property real _outgoingScale: 1

    FontMetrics {
        id: fm
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
        font.weight: Font.Thin
    }

    implicitWidth: fontPixelSize * 0.72
    implicitHeight: fontPixelSize * 1.7

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }

    function startTransition(nextValue) {
        if (nextValue === _restValue && !_transitioning) {
            return
        }

        _fromValue = _transitioning ? _toValue : _restValue
        _toValue = nextValue
        _progress = 0
        _springT = 0
        _transitioning = true
        rollAnimation.restart()
    }

    onValueChanged: startTransition(value)

    Text {
        id: restDigit
        anchors.centerIn: parent
        visible: !root._transitioning
        text: root._restValue
        color: root.textColor
        opacity: root.digitOpacity
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
        font.weight: Font.Thin
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
    }

    Text {
        id: outgoingDigit
        width: root.width
        height: root._glyphHeight
        x: 0
        y: (root.height - height) / 2 + root._springOffset
        visible: root._transitioning
        text: root._fromValue
        color: root.textColor
        opacity: root.digitOpacity * (1 - root.clamp((root._p - 0.55) / 0.40, 0, 1))
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
        font.weight: Font.Thin
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
        transform: Scale {
            origin.x: outgoingDigit.width / 2
            origin.y: outgoingDigit.height
            xScale: root._outgoingScale
            yScale: root._outgoingScale
        }
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 12
            // Rescaled to reach ~1.0 at peak so the visible radius stays close
            // to the old blurMax:96 look while sampling far fewer texels.
            blur: root.maxBlur * root.clamp(Math.pow(root._p, 0.45) * 0.64 + root._speed * 0.40, 0, 1)
        }
    }

    Text {
        id: incomingDigit
        width: root.width
        height: root._glyphHeight
        x: 0
        y: (root.height - height) / 2 + root._springOffset
        visible: root._transitioning
        text: root._toValue
        color: root.textColor
        opacity: root.digitOpacity * root.clamp(root._p / 0.30, 0, 1)
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
        font.weight: Font.Thin
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
        transform: Scale {
            origin.x: incomingDigit.width / 2
            origin.y: 0
            xScale: root._incomingScale
            yScale: root._incomingScale
        }
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 12
            blur: root.maxBlur * root.clamp(Math.pow(1 - root._p, 0.45) * 0.78 + root._speed * 0.34, 0, 1)
        }
    }

    SequentialAnimation {
        id: rollAnimation
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "_progress"
                from: 0
                to: 1
                duration: root.duration
                easing.type: Easing.OutCubic
            }
            // Linear driver — the spring shape lives entirely in the
            // exp-decayed cosine of _springOffset, so easing here would
            // double-distort the ring-down. Runs the full duration plus a
            // little extra so the bounce has room to settle to rest.
            NumberAnimation {
                target: root
                property: "_springT"
                from: 0
                to: 1
                duration: Math.round(root.duration * 1.25)
                easing.type: Easing.Linear
            }
            NumberAnimation {
                target: root
                property: "_incomingScale"
                from: 0.0
                to: 1.0
                duration: root.duration
                easing.type: Easing.OutQuint
            }
            NumberAnimation {
                target: root
                property: "_outgoingScale"
                from: 1.0
                to: 0.0
                duration: root.duration
                easing.type: Easing.OutQuint
            }
        }
        onFinished: {
            root._restValue = root._toValue
            root._progress = 1
            root._springT = 0
            root._incomingScale = 1
            root._outgoingScale = 1
            root._transitioning = false
        }
    }
}
