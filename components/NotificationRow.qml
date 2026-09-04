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

  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Color.accent, Color.urgent)
  bordered: unread

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
    anchors.leftMargin: root.edgeMargin
    anchors.rightMargin: root.edgeMargin
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
        text: root.glyph !== "" ? root.glyph : "\uDB80\uDC9A"
        color: root.contentForeground
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
          width: parent.width - timeLabel.implicitWidth - Style.space(8)
          elide: Text.ElideRight
          text: root.app !== "" ? root.app : "Notification"
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: timeLabel
          text: root.time
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width
        visible: root.summary !== ""
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
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
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    z: 2
    width: Style.space(72)
    height: Style.space(26)
    radius: Style.cornerRadius
    opacity: root.actionEnabled ? 1.0 : 0.45
    color: actionMouse.containsMouse && root.actionEnabled
      ? (root.danger ? Util.alpha(Color.urgent, Style.hoverFillAlpha) : Style.hoverFillFor(root.contentForeground, Color.accent, Color.urgent))
      : Style.normalFillFor(root.contentForeground, Color.accent, Color.urgent)

    Text {
      anchors.centerIn: parent
      text: root.actionLabel
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
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
  }
}
