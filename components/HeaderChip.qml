import qs.Commons as Commons
import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  property string text: ""
  property string tooltipText: ""
  property bool on: false
  property bool enabled: true
  // When on+danger, fill with Commons.Color.urgent (destructive confirms like Empty trash).
  property bool danger: false
  property color contentForeground: Commons.Color.foreground
  property string contentFontFamily: Style.font.family

  signal clicked()

  readonly property color activeFill: root.danger ? Commons.Color.urgent : Commons.Color.accent
  readonly property color hoverFill: Style.hoverFillFor(contentForeground, Commons.Color.accent, Commons.Color.urgent)
  readonly property color idleFill: Style.normalFillFor(contentForeground, Commons.Color.accent, Commons.Color.urgent)
  readonly property color borderIdle: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.12)

  width: label.implicitWidth + Style.space(16)
  height: Style.space(24)
  radius: Style.cornerRadius
  opacity: root.enabled ? 1 : 0.4
  color: {
    if (!root.enabled) return root.idleFill
    if (root.on) return chipMouse.containsMouse ? Qt.darker(root.activeFill, 1.08) : root.activeFill
    return chipMouse.containsMouse ? root.hoverFill : root.idleFill
  }
  border.width: Style.spacing.hairline
  border.color: root.on && root.enabled ? root.activeFill : root.borderIdle

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.on && root.enabled ? Commons.Color.background : root.contentForeground
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  MouseArea {
    id: chipMouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && chipMouse.containsMouse
    text: root.tooltipText
    fontFamily: root.contentFontFamily
  }
}
