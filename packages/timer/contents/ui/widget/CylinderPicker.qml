import QtQuick

Item {
    id: root

    property int count: 60
    property int currentIndex: 0
    property string label: ""
    property string fontFamily: ""
    property color textColor: "#ffffff"
    property color separatorColor: "#ffffff"
    property string labelFontFamily: ""

    readonly property real _itemHeight: height / 5
    readonly property real _visibleRadius: height / 2
    readonly property real _maxAngle: Math.PI / 2.2

    property real _scrollY: 0

    implicitWidth: 80
    implicitHeight: 180

    clip: true

    property bool _externalSet: false

    onCurrentIndexChanged: {
        if (_externalSet) return
        var target = currentIndex * _itemHeight
        if (Math.abs(_scrollY - target) > 0.5) {
            snapAnim.stop()
            _scrollY = target
        }
    }

    function _snapToNearest() {
        var target = Math.round(_scrollY / _itemHeight) * _itemHeight
        target = Math.max(0, Math.min(target, (count - 1) * _itemHeight))
        snapAnim.to = target
        snapAnim.restart()
    }

    NumberAnimation {
        id: snapAnim
        target: root
        property: "_scrollY"
        duration: 250
        easing.type: Easing.OutCubic
        onFinished: {
            root._externalSet = true
            root.currentIndex = Math.round(root._scrollY / root._itemHeight)
            root._externalSet = false
        }
    }

    WheelHandler {
        id: wheelHandler
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            var delta = -event.angleDelta.y / 120.0
            var newY = root._scrollY + delta * root._itemHeight * 0.7
            newY = Math.max(0, Math.min(newY, (root.count - 1) * root._itemHeight))
            root._scrollY = newY
            snapTimer.restart()
        }
    }

    Timer {
        id: snapTimer
        interval: 150
        repeat: false
        onTriggered: root._snapToNearest()
    }

    DragHandler {
        id: dragHandler
        target: null
        dragThreshold: 2
        property real _startY: 0
        property real _startScrollY: 0
        onGrabChanged: function(transition, point) {
            if (transition === PointerDevice.GrabExclusive) {
                _startY = point.position.y
                _startScrollY = root._scrollY
            }
        }
        onActiveChanged: {
            if (!active) root._snapToNearest()
        }
        onCentroidChanged: {
            if (active) {
                var dy = _startY - centroid.position.y
                var newY = _startScrollY + dy
                newY = Math.max(0, Math.min(newY, (root.count - 1) * root._itemHeight))
                root._scrollY = newY
            }
        }
    }

    Repeater {
        model: root.count
        delegate: Item {
            id: delegateItem
            required property int index

            readonly property real _rawOffset: (index * root._itemHeight) - root._scrollY
            readonly property real _angle: (_rawOffset / root._visibleRadius) * root._maxAngle
            readonly property real _cosA: Math.cos(_angle)
            readonly property real _itemScale: Math.pow(Math.max(0, _cosA), 0.6)
            readonly property real _itemY: root.height / 2 + Math.sin(_angle) * root._visibleRadius - height / 2

            visible: Math.abs(_angle) < Math.PI / 2
            width: root.width * 0.75
            height: root._itemHeight
            x: 0
            y: _itemY
            opacity: Math.max(0, _cosA)

            transform: Scale {
                origin.x: delegateItem.width / 2
                origin.y: delegateItem.height / 2
                xScale: delegateItem._itemScale
                yScale: delegateItem._itemScale
            }

            Text {
                anchors.centerIn: parent
                text: index < 10 ? "0" + index : String(index)
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: root._itemHeight * 0.72
                font.weight: Font.Thin
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                renderType: Text.NativeRendering
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height / 2 - root._itemHeight / 2 - 1
        width: parent.width * 0.85
        height: 1
        color: root.separatorColor
        opacity: 0.25
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height / 2 + root._itemHeight / 2
        width: parent.width * 0.85
        height: 1
        color: root.separatorColor
        opacity: 0.25
    }

    Text {
        id: labelText
        anchors {
            left: parent.right
            leftMargin: 6
            verticalCenter: parent.verticalCenter
        }
        text: root.label
        color: root.textColor
        opacity: 0.5
        font.family: root.labelFontFamily !== "" ? root.labelFontFamily : root.fontFamily
        font.pixelSize: root._itemHeight * 0.52
        font.weight: Font.Regular
        renderType: Text.NativeRendering
    }
}
