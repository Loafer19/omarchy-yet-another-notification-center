import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"

// Trash's header line: the count and how long Trash keeps entries, then
// Empty trash. Emptying is permanent: the chip arms on the first click and
// commits on the second; it disarms after 4 s so a stray click later
// cannot wipe the bin (HeaderChip confirm mode).
Item {
  id: bar
  height: Style.space(28)

  property int count: 0
  property real days: 30
  property int edgeMargin: 0
  readonly property alias armed: emptyChip.armed

  signal emptyTrash()

  function disarm() { emptyChip.disarm() }
  function activate() { emptyChip.activate() }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: bar.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    text: {
      var kept = bar.days === 1 ? "1 day" : bar.days + " days"
      return bar.count === 0 ? "Empty · kept " + kept : bar.count + " in trash · " + kept
    }
    color: Theme.dim
    font.family: Theme.fontFamily
    font.pixelSize: Style.font.caption
  }

  HeaderChip {
    id: emptyChip
    anchors.right: parent.right
    anchors.rightMargin: bar.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    text: "Empty trash"
    confirm: true
    confirmText: "Confirm?"
    armMs: 4000
    danger: true
    enabled: bar.count > 0
    tooltipText: bar.count === 0
      ? "Trash is already empty"
      : (emptyChip.armed
        ? "Click again to delete forever — Esc or wait to cancel"
        : "Delete trash forever (asks for confirmation)")
    onTriggered: bar.emptyTrash()
  }
}
