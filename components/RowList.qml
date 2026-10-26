pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../Model.js" as Model

// History or Trash: one NotificationRow per entry (Model.rowsFor rows).
// itemAtIndex(i) gives a row's wrapper: showNotice(title, detail) and
// copyFinished(ok, error).
ListView {
  id: list
  clip: true
  spacing: Style.space(6)

  property double now: Date.now()
  // Rows newer than this are marked unread; 0 never marks any (Trash).
  property double readMark: 0
  property bool markUnread: false
  property bool showBody: true
  property bool showPreview: true
  property string actionLabel: "Trash"
  property bool danger: true
  property int edgeMargin: Style.space(6)
  // The keyboard cursor's row, -1 for none.
  property int cursorIndex: -1

  signal rowHovered(int index)
  signal rowClicked(int index, var row)
  signal copyClicked(int index, var row)
  signal actionClicked(var row)

  delegate: Item {
    id: wrap
    required property int index
    required property var modelData
    width: ListView.view.width
    height: card.implicitHeight
    function showNotice(title, detail) { card.showNotice(title, detail) }
    function copyFinished(ok, error) { card.copyFinished(ok, error) }

    NotificationRow {
      id: card
      width: parent.width
      app: wrap.modelData.app
      appIcon: wrap.modelData.appIcon
      summary: wrap.modelData.summary
      body: wrap.modelData.body
      image: wrap.modelData.image
      preview: wrap.modelData.preview
      glyph: wrap.modelData.glyph
      time: Model.formatTime(wrap.modelData.timestamp, list.now)
      urgency: wrap.modelData.urgency
      unread: list.markUnread && wrap.modelData.timestamp > list.readMark
      showBody: list.showBody
      showPreview: list.showPreview
      actionLabel: list.actionLabel
      danger: list.danger
      edgeMargin: list.edgeMargin
      hasCursor: list.cursorIndex === wrap.index
      onRowHovered: list.rowHovered(wrap.index)
      onRowClicked: list.rowClicked(wrap.index, wrap.modelData)
      onCopyClicked: list.copyClicked(wrap.index, wrap.modelData)
      onActionClicked: list.actionClicked(wrap.modelData)
    }
  }
}
