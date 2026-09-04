import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  property string text: ""
  property string tooltipText: ""
  property bool on: false
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family

  signal clicked()

  readonly property color hoverFill: Style.hoverFillFor(contentForeground, Color.accent, Color.urgent)
  readonly property color idleFill: Style.normalFillFor(contentForeground, Color.accent, Color.urgent)
  readonly property color borderIdle: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.12)

  width: label.implicitWidth + Style.space(16)
  height: Style.space(24)
  radius: Style.cornerRadius
  color: {
    if (root.on) return chipMouse.containsMouse ? Qt.darker(Color.accent, 1.08) : Color.accent
    return chipMouse.containsMouse ? root.hoverFill : root.idleFill
  }
  border.width: Style.spacing.hairline
  border.color: root.on ? Color.accent : root.borderIdle

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.on ? Color.background : root.contentForeground
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && chipMouse.containsMouse
    text: root.tooltipText
    fontFamily: root.contentFontFamily
  }
}
