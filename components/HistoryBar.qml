import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"

// History's header line: the count, then DND, Auto-hide and Clear.
Item {
  id: bar
  height: Style.space(28)

  property int count: 0
  property bool searching: false      // a search filter is applied
  property bool dnd: false
  property bool autoHide: false
  property int edgeMargin: 0

  signal dndClicked()
  signal autoHideClicked()
  signal clearClicked()

  Row {
    anchors.left: parent.left
    anchors.leftMargin: bar.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Text {
      text: bar.searching ? bar.count + " matching" : (bar.count + " in History")
      color: Theme.dim
      font.family: Theme.fontFamily
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: bar.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    HeaderChip {
      text: "DND"
      on: bar.dnd
      tooltipText: bar.dnd ? "Allow notifications" : "Silence notifications"
      onClicked: bar.dndClicked()
    }

    HeaderChip {
      text: "Auto-hide"
      on: bar.autoHide
      tooltipText: bar.autoHide
        ? "Toasts stay up — Omarchy never expires critical on its own"
        : "Hide each toast 8 s after it appears, including critical"
      onClicked: bar.autoHideClicked()
    }

    HeaderChip {
      // Stay visible when empty — disabled instead of vanishing so the
      // header layout does not jump and the action stays discoverable.
      text: "Clear"
      enabled: bar.count > 0
      tooltipText: bar.count > 0
        ? "Move everything in History to Trash"
        : "History is already empty"
      onClicked: bar.clearClicked()
    }
  }
}
