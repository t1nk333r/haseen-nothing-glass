import QtQuick

// Drag/resize for one widget instance. Deliberately minimal. `host` (this item's parent, an Item from WidgetHost.qml) is what
// actually moves/resizes; this component only reads/writes its x/y/width/
// height and commits the result to the store on release.
//
// MOVE is a RIGHT-button drag anywhere on the widget. RESIZE is a plain
// left-button drag on the bottom-right grip. No modifiers, on purpose — two
// things found by driving a real pointer in the lab (plan 005's gates,
// finally exercised):
//
//   1. Modifier keys never reach this surface. It has
//      WlrLayershell.keyboardFocus: None, and Wayland delivers
//      wl_keyboard.modifiers only to the keyboard-focused surface, so every
//      mouse event here arrives with `modifiers == 0`. A SUPER- or ALT-gated
//      press was rejected every single time; the original design could not
//      have worked. (SUPER is additionally consumed by the compositor:
//      Omarchy binds `SUPER + mouse:272/273` in
//      /usr/share/omarchy/default/hypr/bindings/tiling.lua:70-71.)
//   2. Right-button is free: no Omarchy mouse bind uses it bare, and every
//      ported widget's own MouseAreas accept LeftButton only, so a
//      right-press never competes with a control underneath.
//
// Left clicks are NOT intercepted by anything this component installs except
// the resize grip: moveArea accepts only RightButton, so the now-playing and
// timer buttons keep working with no accepted=false dance. The grip's own hit
// area is exactly the 18 px box it is drawn in, so a left click reaches the
// widget underneath everywhere else.
//
// A small dead zone (dragThreshold) keeps a right-click that wobbles by a
// pixel from committing a move.
Item {
  id: placement

  required property var entry     // the store row this instance represents (for its id)
  required property Store store   // committed to on release only, not per-frame
  required property WidgetRegistry registry
  required property real screenWidth
  required property real screenHeight

  // The screen's reserved edges (the bar). Widgets stay out of them: the
  // surface itself ignores exclusive zones so that a widget CAN be placed
  // edge to edge, which also means nothing else stops a drag from parking
  // one behind the bar.
  property int insetLeft: 0
  property int insetTop: 0
  property int insetRight: 0
  property int insetBottom: 0

  readonly property Item host: placement.parent
  readonly property int gripSize: 18
  readonly property int dragThreshold: 6

  // Emitted on a right-CLICK (a press that never crossed the dead zone).
  // GlassSurface turns it into the settings sheet; nothing here knows what
  // the sheet is.
  signal settingsRequested(var entry, real screenX, real screenY)

  property bool dragging: false
  property bool resizing: false
  property bool _moved: false
  property real _pressX: 0
  property real _pressY: 0
  property real _startX: 0
  property real _startY: 0
  property real _startW: 0
  property real _startH: 0

  // Tile origins land on the registry's lattice (gap + n*pitch), so a moved
  // widget lines up with its neighbours instead of on an arbitrary 8 px
  // multiple. The typed Position fields in the control panel stay exact -
  // this is the gesture's snap, not a store-level constraint.
  function _snapX(v) {
    return placement.registry ? placement.registry.snapCoord(v, placement.insetLeft) : Math.round(v)
  }

  function _snapY(v) {
    return placement.registry ? placement.registry.snapCoord(v, placement.insetTop) : Math.round(v)
  }

  function _clampX(x, w) {
    var maxX = Math.max(placement.insetLeft, placement.screenWidth - placement.insetRight - w)
    return Math.min(Math.max(placement.insetLeft, x), maxX)
  }

  function _clampY(y, h) {
    var maxY = Math.max(placement.insetTop, placement.screenHeight - placement.insetBottom - h)
    return Math.min(Math.max(placement.insetTop, y), maxY)
  }

  // --- move ---------------------------------------------------------

  MouseArea {
    id: moveArea
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    z: 0

    onPressed: function (mouse) {
      if (!placement.host) {
        mouse.accepted = false
        return
      }
      var g = moveArea.mapToItem(null, mouse.x, mouse.y)
      placement._pressX = g.x
      placement._pressY = g.y
      placement._startX = placement.host.x
      placement._startY = placement.host.y
      placement.dragging = true
      mouse.accepted = true
    }

    onPositionChanged: function (mouse) {
      if (!placement.dragging || !placement.host) return
      var g = moveArea.mapToItem(null, mouse.x, mouse.y)
      var dx = g.x - placement._pressX
      var dy = g.y - placement._pressY
      if (Math.abs(dx) < placement.dragThreshold && Math.abs(dy) < placement.dragThreshold) return
      // Past the dead zone this is a move, not a click - remembered so the
      // release below can tell the two apart.
      placement._moved = true
      var nx = placement._clampX(placement._snapX(placement._startX + dx), placement.host.width)
      var ny = placement._clampY(placement._snapY(placement._startY + dy), placement.host.height)
      placement.host.x = nx
      placement.host.y = ny
    }

    // A right-press that never left the dead zone is a right-CLICK, and that
    // opens the widget's settings sheet. Same button as the move on purpose:
    // there is no other one left (left is the widgets' own controls, and
    // modifiers never arrive - see this file's header), and "drag to move,
    // click for settings" is the desktop convention anyway.
    onReleased: function (mouse) {
      if (!placement.dragging) {
        mouse.accepted = false
        return
      }
      placement.dragging = false

      if (!placement._moved) {
        var g = moveArea.mapToItem(null, mouse.x, mouse.y)
        placement.settingsRequested(placement.entry, g.x, g.y)
        return
      }

      placement._moved = false
      if (placement.store && placement.entry) {
        placement.store.move(placement.entry.id, placement.host.x, placement.host.y)
      }
    }
  }

  // --- resize (bottom-right grip) ------------------------------------
  //
  // Invisible until the pointer is over the widget. It used to be a
  // permanently visible white square, which is a UI chrome artefact sitting
  // on top of a widget whose whole point is that it looks like glass.
  //
  // Hover comes from a HoverHandler, NOT a hoverEnabled MouseArea: this item
  // is stacked ABOVE the widget's own content (see WidgetHost.qml's child
  // order), and a hovering MouseArea would swallow hover from every control
  // underneath it - the now-playing buttons and the timer's cards would stop
  // highlighting. HoverHandler is non-blocking (`blocking: false` default),
  // so both this and the widget's own hover states see the pointer.
  HoverHandler {
    id: widgetHover
  }

  // How far the widget's silhouette cuts in from the box corner at 45°.
  // WidgetHost.maskRadius is `cornerRadius` rescaled so that a CIRCLE of that
  // radius has the same diagonal cut as the drawn superellipse, so the cut
  // itself is the circle's: r - r/√2. Anchoring the grip flush to the box
  // corner left the strokes hanging outside the glass; using maskRadius
  // directly buried them 3.4× too deep.
  readonly property real cornerInset: {
    var r = placement.host && !isNaN(placement.host.maskRadius) ? placement.host.maskRadius : 20
    return Math.round(r * (1 - Math.SQRT1_2)) + 2
  }

  Item {
    id: resizeGrip
    width: placement.gripSize
    height: placement.gripSize
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Math.max(1, placement.cornerInset)
    anchors.bottomMargin: Math.max(1, placement.cornerInset)
    z: 1

    // Still draggable while invisible (a pointer already inside the corner
    // has hovered it by definition), so the fade is decoration only.
    opacity: widgetHover.hovered || placement.resizing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // Two short diagonal strokes in the corner - the platform idiom for a
    // resize affordance, and far less loud than a filled square.
    Repeater {
      model: 2

      Rectangle {
        id: stroke
        required property int index
        readonly property real inset: 4 + stroke.index * 5
        width: placement.gripSize - stroke.inset - 3
        height: 2
        radius: 1
        color: Qt.rgba(1, 1, 1, 0.85)
        antialiasing: true
        transformOrigin: Item.Center
        rotation: -45
        x: resizeGrip.width - stroke.inset - stroke.width / 2 - stroke.height / 2
        y: resizeGrip.height - stroke.inset - stroke.height / 2

        // A dark companion stroke keeps the affordance visible on a pale
        // wallpaper without a background plate.
        Rectangle {
          anchors.fill: parent
          anchors.margins: -1
          z: -1
          radius: 2
          color: Qt.rgba(0, 0, 0, 0.30)
        }
      }
    }

    // The input surface is the drawn affordance and nothing else: the 18 px
    // box the two strokes live in. It used to reach back out to the widget's
    // box corner, sized by cornerInset - a value derived from the mask - so
    // (gripSize + cornerInset)^2 px of every widget swallowed left clicks,
    // and grew with an unrelated number. Reveal-gating is not an alternative:
    // widgetHover is on the whole widget, so the grip is already revealed
    // whenever a click could land.
    //
    // Opacity 0 does not disable input, so this works whether or not the
    // affordance has faded in.
    MouseArea {
      id: resizeArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      propagateComposedEvents: true

      onPressed: function (mouse) {
        if (!placement.host) {
          mouse.accepted = false
          return
        }
        var g = resizeArea.mapToItem(null, mouse.x, mouse.y)
        placement._pressX = g.x
        placement._pressY = g.y
        placement._startW = placement.host.width
        placement._startH = placement.host.height
        placement.resizing = true
        mouse.accepted = true
      }

      // Not a free transform: the pointer chooses among the type's three
      // grid sizes and the tile jumps between them. The pointer's own
      // position never becomes the size, so a drag can only ever produce a
      // legal tile - which is what makes two widgets line up without the
      // user aiming at pixels.
      onPositionChanged: function (mouse) {
        if (!placement.resizing || !placement.host || !placement.registry) return
        var g = resizeArea.mapToItem(null, mouse.x, mouse.y)
        var dx = g.x - placement._pressX
        var dy = g.y - placement._pressY
        var type = placement.entry ? placement.entry.type : ""
        var pick = placement.registry.nearestSize(
          type,
          placement._startW + dx,
          placement._startH + dy,
          placement.screenWidth - placement.insetRight - placement.host.x,
          placement.screenHeight - placement.insetBottom - placement.host.y)
        if (!pick) return
        placement.host.width = pick.width
        placement.host.height = pick.height
      }

      onReleased: function (mouse) {
        if (!placement.resizing) {
          mouse.accepted = false
          return
        }
        placement.resizing = false
        if (placement.store && placement.entry) {
          placement.store.resize(placement.entry.id, placement.host.width, placement.host.height)
        }
      }
    }
  }
}
