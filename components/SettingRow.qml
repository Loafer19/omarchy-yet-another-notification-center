import QtQuick
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property string valueLabel: ""
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)
  property int rowHeight: Style.space(48)

  signal rowHovered()
  signal rowClicked()

  height: rowHeight
  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Color.accent, Color.urgent)
  bordered: false

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
    onClicked: root.rowClicked()
  }

  Column {
    anchors.left: parent.left
    anchors.leftMargin: root.edgeMargin
    anchors.right: valueLabel.left
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

  Text {
    id: valueLabel
    anchors.right: parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    text: root.valueLabel
    color: Color.accent
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }
}
