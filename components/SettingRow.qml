import QtQuick
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property string valueLabel: ""
  property string kind: "toggle"
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)
  property int rowHeight: Style.space(48)

  readonly property bool hasStepper: kind === "step" || kind === "enum" || kind === "appSound"

  signal rowHovered()
  signal rowClicked()
  signal decrementClicked()
  signal incrementClicked()

  height: rowHeight
  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Color.accent, Color.urgent)
  bordered: false

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
    onClicked: function(mouse) {
      if (root.hasStepper) {
        if (mouse.button === Qt.RightButton) root.decrementClicked()
        else root.incrementClicked()
        return
      }
      root.rowClicked()
    }
  }

  Column {
    anchors.left: parent.left
    anchors.leftMargin: root.edgeMargin
    anchors.right: controls.left
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      elide: Text.ElideRight
      visible: root.title !== ""
      text: root.title
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      visible: root.subtitle !== ""
      text: root.subtitle
      color: Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    id: controls
    anchors.right: parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Rectangle {
      visible: root.hasStepper
      width: Style.space(22)
      height: Style.space(22)
      radius: Style.cornerRadius
      color: minusMouse.containsMouse
        ? Style.hoverFillFor(root.contentForeground, Color.accent, Color.urgent)
        : Style.normalFillFor(root.contentForeground, Color.accent, Color.urgent)

      Text {
        anchors.centerIn: parent
        text: "−"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      MouseArea {
        id: minusMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) root.rowHovered()
        onClicked: root.decrementClicked()
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.valueLabel
      color: Color.accent
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Rectangle {
      visible: root.hasStepper
      width: Style.space(22)
      height: Style.space(22)
      radius: Style.cornerRadius
      color: plusMouse.containsMouse
        ? Style.hoverFillFor(root.contentForeground, Color.accent, Color.urgent)
        : Style.normalFillFor(root.contentForeground, Color.accent, Color.urgent)

      Text {
        anchors.centerIn: parent
        text: "+"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      MouseArea {
        id: plusMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) root.rowHovered()
        onClicked: root.incrementClicked()
      }
    }
  }
}
