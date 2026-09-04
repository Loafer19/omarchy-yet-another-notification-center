import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  property string text: ""
  property bool on: false
  property bool danger: false
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family

  signal clicked()

  readonly property color hoverFill: danger
    ? Util.alpha(Color.urgent, Style.hoverFillAlpha)
    : Style.hoverFillFor(contentForeground, Color.accent, Color.urgent)
  readonly property color idleFill: Style.normalFillFor(contentForeground, Color.accent, Color.urgent)

  width: label.implicitWidth + Style.space(16)
  height: Style.space(24)
  radius: Style.cornerRadius
  color: root.on ? Color.accent
    : (chipMouse.containsMouse ? root.hoverFill : root.idleFill)

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.on ? Color.background : root.contentForeground
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.caption
    font.bold: root.on
  }

  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
