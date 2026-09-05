import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property string preview: ""
  property string glyph: ""
  property string time: ""
  property int urgency: 1
  property bool unread: false
  property bool showBody: true
  property bool showPreview: true
  property string actionLabel: "Trash"
  property bool actionEnabled: true
  property bool danger: true
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)

  signal actionClicked()
  signal rowClicked()
  signal rowHovered()

  readonly property int urgencyLevel: urgency >= 2 ? 2 : (urgency <= 0 ? 0 : 1)
  readonly property color urgencyColor: urgencyLevel === 2
    ? Color.urgent
    : (urgencyLevel === 0 ? Qt.darker(contentForeground, 1.8) : Color.accent)
  readonly property string urgencyLabel: urgencyLevel === 2 ? "Critical" : (urgencyLevel === 0 ? "Low" : "")

  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Color.accent, Color.urgent)
  bordered: unread || urgencyLevel === 2

  readonly property string previewSource: {
    if (!showPreview) return ""
    if (preview) return preview.indexOf("file://") === 0 ? preview : (preview.charAt(0) === "/" ? "file://" + preview : "")
    if (image && image.indexOf("file://") === 0) return image
    return ""
  }
  readonly property string smallIcon: {
    if (!appIcon) return ""
    if (appIcon.indexOf("file://") === 0 || appIcon.indexOf("image://") === 0) return appIcon
    if (appIcon.charAt(0) === "/") return "file://" + appIcon
    return Quickshell.iconPath(appIcon, true)
  }

  implicitHeight: Math.max(Style.space(56), contentCol.implicitHeight + Style.space(16))

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(3)
    radius: 1
    color: root.urgencyColor
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.actionClicked()
      else root.rowClicked()
    }
  }

  Row {
    id: row
    anchors.left: parent.left
    anchors.right: actionBtn.left
    anchors.leftMargin: root.edgeMargin + Style.space(4)
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    Item {
      width: Style.space(36)
      height: Style.space(36)
      anchors.verticalCenter: parent.verticalCenter

      Image {
        anchors.fill: parent
        visible: root.previewSource !== ""
        source: root.previewSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
      }

      Image {
        anchors.fill: parent
        visible: root.previewSource === "" && root.smallIcon !== ""
        source: root.smallIcon
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }

      Text {
        anchors.centerIn: parent
        visible: root.previewSource === "" && root.smallIcon === ""
        textFormat: Text.PlainText
        text: root.glyph !== "" ? root.glyph : "\uDB80\uDC9A"
        color: root.urgencyColor
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.icon
      }
    }

    Column {
      id: contentCol
      width: parent.width - Style.space(46)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width - metaLabel.implicitWidth - Style.space(8)
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: root.app !== "" ? root.app : "Notification"
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: metaLabel
          textFormat: Text.PlainText
          text: (root.urgencyLabel !== "" ? root.urgencyLabel + " · " : "") + root.time
          color: root.urgencyLevel === 2 ? Color.urgent : Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.bold: root.urgencyLevel === 2
        }
      }

      Text {
        width: parent.width
        visible: root.summary !== ""
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.summary
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        width: parent.width
        visible: root.showBody && root.body !== ""
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: root.body
        textFormat: Text.PlainText
        color: Qt.darker(root.contentForeground, 1.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Rectangle {
    id: actionBtn
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    z: 2
    width: Style.space(40)
    opacity: root.actionEnabled ? 1.0 : 0.45
    color: actionMouse.containsMouse && root.actionEnabled
      ? (root.danger ? Util.alpha(Color.urgent, Style.hoverFillAlpha) : Style.hoverFillFor(root.contentForeground, Color.accent, Color.urgent))
      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)

    Text {
      anchors.centerIn: parent
      text: root.danger ? "\uDB80\uDDB4" : "\uDB80\uDC6F"
      color: actionMouse.containsMouse && root.danger ? Color.urgent : root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.icon
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      enabled: root.actionEnabled
      hoverEnabled: true
      cursorShape: root.actionEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) root.rowHovered()
      onClicked: root.actionClicked()
    }

    PanelToolTip {
      visible: actionMouse.containsMouse && root.actionEnabled
      text: root.actionLabel
      fontFamily: root.contentFontFamily
    }
  }
}
