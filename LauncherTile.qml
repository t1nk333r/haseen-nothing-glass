import QtQuick
import "components/nothing"

// One tile in the launcher's grid: a live preview of the widget at its real
// proportions, its name, and what clicking it will do.
//
// The preview is the actual widget component (WidgetPreview), not a picture
// of one, so this stays truthful for free - including through a style
// change, which simply re-resolves the file behind it.
Item {
  id: tile

  required property var theme
  required property var registry
  required property var pluginSettings
  required property var injectedTheme

  PluginId { id: identity }

  property string type: ""
  property string title: ""
  property string subtitle: ""
  // The style this tile is drawn in, resolved by the launcher: the widget's
  // own choice, else its category's, else the plugin default. Passed in
  // rather than derived here so the tile, its preview and its chip cannot
  // disagree with the desktop.
  property string style: "liquid-glass"
  // "" for none, "open" while this widget's settings are showing, or any
  // other short text, shown as a dot beside the style chip.
  property string badge: ""
  property string actionLabel: "ADD"
  property var settingsOverrides: ({})

  property bool onDesktop: false
  property bool current: false

  signal primary()
  signal entered()

  implicitHeight: tile.width * 0.92
  height: implicitHeight

  NCard {
    id: card
    theme: tile.theme
    level: tile.current || area.containsMouse ? 2 : 1
    anchors.fill: parent
    border.color: tile.current ? tile.theme.red : tile.theme.outline

    // The preview area. A square tile is previewed square; the launcher does
    // not pretend to show every size at once - the size is the user's to
    // choose on the desktop, with the corner grip.
    Item {
      id: frame
      anchors { top: parent.top; left: parent.left; right: parent.right; margins: tile.theme.pad }
      height: parent.height - caption.height - tile.theme.pad * 2 - tile.theme.px(6)
      clip: true

      Rectangle {
        anchors.fill: parent
        color: tile.theme.surface
        radius: tile.theme.rChip
        border.width: tile.theme.hair
        border.color: tile.theme.outline
      }

      WidgetPreview {
        anchors.fill: parent
        anchors.margins: tile.theme.px(6)
        registry: tile.registry
        pluginSettings: tile.pluginSettings
        injectedTheme: tile.injectedTheme
        type: tile.type
        style: tile.style
        settingsOverrides: tile.settingsOverrides
        tileWidth: 192
        tileHeight: 192
      }

      // What the click does, revealed on hover over the frame rather than
      // occupying the tile permanently.
      Rectangle {
        anchors.fill: parent
        radius: tile.theme.rChip
        color: Qt.rgba(0, 0, 0, 0.62)
        opacity: area.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: tile.theme.fast } }

        NLabel {
          theme: tile.theme
          loud: true
          text: tile.actionLabel
          anchors.centerIn: parent
        }
      }

    }

    Item {
      id: caption
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: tile.theme.pad }
      height: nameText.implicitHeight + subText.implicitHeight + tile.theme.px(2)

      NText {
        id: nameText
        theme: tile.theme
        text: tile.title
        font.family: tile.theme.sansBold
        font.pixelSize: tile.theme.fLabel
        elide: Text.ElideRight
        anchors { left: parent.left; right: countText.left; rightMargin: tile.theme.px(6); top: parent.top }
      }
      // The style this widget is actually drawn in, and a dot when the badge
      // says something about it. Both live in the caption rather than over
      // the artwork: a chip on top of the widget covers exactly the corner
      // the widget itself uses.
      Row {
        id: countText
        spacing: tile.theme.px(5)
        anchors { right: parent.right; top: parent.top }

        Rectangle {
          width: tile.theme.px(6); height: tile.theme.px(6); radius: tile.theme.px(3)
          anchors.verticalCenter: parent.verticalCenter
          visible: tile.badge !== ""
          color: tile.theme.red
        }
        Rectangle {
          width: styleMark.implicitWidth + tile.theme.px(9)
          height: tile.theme.px(14)
          radius: tile.theme.px(3)
          anchors.verticalCenter: parent.verticalCenter
          color: tile.style === "nothing" ? tile.theme.red : Qt.rgba(1, 1, 1, 0.12)
          NLabel {
            id: styleMark
            theme: tile.theme
            anchors.centerIn: parent
            loud: true
            color: tile.style === "nothing" ? tile.theme.redInk : tile.theme.on
            font.pixelSize: tile.theme.fMicro
            text: identity.styleLabel(tile.style).toUpperCase()
          }
        }
      }
      NLabel {
        id: subText
        theme: tile.theme
        text: tile.subtitle
        font.pixelSize: tile.theme.fMicro
        font.capitalization: Font.MixedCase
        font.letterSpacing: 0
        elide: Text.ElideRight
        anchors { left: parent.left; right: parent.right; top: nameText.bottom }
      }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // The tile's whole read: what it is, what it is drawn at, what a click
    // does. The preview and the style chip are painted, so this is the only
    // way a reader gets any of it.
    Accessible.role: Accessible.Button
    Accessible.name: tile.title
      + (tile.subtitle !== "" ? " · " + tile.subtitle : "")
      + " · " + tile.actionLabel
    Accessible.onPressAction: tile.primary()
    onEntered: tile.entered()
    onClicked: tile.primary()
  }
}
