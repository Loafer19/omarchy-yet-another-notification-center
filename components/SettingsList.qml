pragma ComponentBehavior: Bound
import QtQuick

// The Settings tab: one SettingRow per Model.settingRows row.
ListView {
  id: list
  clip: true
  spacing: 0

  property int edgeMargin: 0
  // The keyboard cursor's row, -1 for none.
  property int cursorIndex: -1

  signal rowHovered(int index)
  signal rowClicked(int index)
  // A value picked from a row's popup; play when it is a sound.
  signal valuePicked(int index, var row, var value)
  signal playClicked(int index, var row)
  signal numberPicked(int index, var row, var value)
  signal popupOpenChanged(bool open)
  signal fieldFocusChanged(bool on)

  delegate: Item {
    id: wrap
    required property int index
    required property var modelData
    width: ListView.view.width
    height: card.height

    SettingRow {
      id: card
      width: parent.width
      title: wrap.modelData.title
      subtitle: wrap.modelData.subtitle
      kind: wrap.modelData.kind
      checked: wrap.modelData.checked
      currentValue: wrap.modelData.currentValue
      optionSet: wrap.modelData.optionSet
      numericValue: wrap.modelData.numericValue
      numericMin: wrap.modelData.min
      numericMax: wrap.modelData.max
      numericStep: wrap.modelData.step
      edgeMargin: list.edgeMargin
      hasCursor: list.cursorIndex === wrap.index
      onRowHovered: list.rowHovered(wrap.index)
      onRowClicked: list.rowClicked(wrap.index)
      onValuePicked: function(v) { list.valuePicked(wrap.index, wrap.modelData, v) }
      onPlayClicked: list.playClicked(wrap.index, wrap.modelData)
      onNumberPicked: function(v) { list.numberPicked(wrap.index, wrap.modelData, v) }
      onPopupOpenChanged: function(open) { list.popupOpenChanged(open) }
      onFieldFocusChanged: function(on) { list.fieldFocusChanged(on) }
    }
  }
}
