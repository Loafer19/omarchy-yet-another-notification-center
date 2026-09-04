import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property string kind: "toggle"
  property bool checked: false
  property string currentValue: ""
  property string optionSet: ""
  property int numericValue: 0
  property int numericMin: 0
  property int numericMax: 100
  property int numericStep: 1
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)

  readonly property bool isEnum: kind === "enum" || kind === "appSound"
  readonly property bool isStep: kind === "step"
  readonly property bool canPreview: optionSet === "sound" || optionSet === "appSound"
  readonly property var options: Model.optionsFor(root.optionSet)

  signal rowHovered()
  signal rowClicked()
  signal valuePicked(string value)
  signal numberPicked(int value)
  signal playClicked()
  signal popupOpenChanged(bool open)
  signal fieldFocusChanged(bool on)

  implicitHeight: Math.max(Style.space(52), Math.max(infoCol.implicitHeight, controls.implicitHeight) + Style.space(14))
  height: implicitHeight
  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Color.accent, Color.urgent)
  bordered: false

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.kind === "toggle" ? Qt.PointingHandCursor : Qt.ArrowCursor
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
    onClicked: if (root.kind === "toggle") root.rowClicked()
  }

  Column {
    id: infoCol
    anchors.left: parent.left
    anchors.leftMargin: root.edgeMargin
    anchors.right: controls.left
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

  Item {
    id: controls
    anchors.right: parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    width: root.isEnum ? (root.canPreview ? Style.space(212) : Style.space(168)) : (root.isStep ? Style.space(96) : Style.space(40))
    height: root.isEnum ? dropdown.implicitHeight : (root.isStep ? numberField.implicitHeight : toggle.implicitHeight)

    ToggleSwitch {
      id: toggle
      visible: root.kind === "toggle"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: root.checked
      interactive: false
    }

    NumberField {
      id: numberField
      visible: root.isStep
      anchors.fill: parent
      label: ""
      value: root.numericValue
      from: root.numericMin
      to: root.numericMax
      stepSize: root.numericStep
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
      fieldWidth: parent.width
      hasCursor: root.hasCursor
      onModified: function(v) { root.numberPicked(v) }
      onHovered: function(on) { if (on) root.rowHovered() }
    }

    Dropdown {
      id: dropdown
      visible: root.isEnum
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - (root.canPreview ? playBtn.width + Style.space(6) : 0)
      showLabel: false
      label: ""
      value: root.currentValue
      options: root.options
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
      hasCursor: root.hasCursor
      onChanged: function(v) { root.valuePicked(v) }
      onHovered: function(on) { if (on) root.rowHovered() }
      onPopupOpenChanged: root.popupOpenChanged(popupOpen)
    }

    Button {
      id: playBtn
      visible: root.canPreview
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Play"
      bordered: true
      fontSize: Style.font.caption
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
      tooltipText: "Play this sound"
      onClicked: root.playClicked()
      onHovered: function(on) { if (on) root.rowHovered() }
    }
  }

  Connections {
    target: numberField.field
    function onActiveFocusChanged() { root.fieldFocusChanged(numberField.field.activeFocus) }
  }
}
