import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "yoyo.notification-center"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "yoyo.notification-center"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "\uDB80\uDC9B" : "\uDB80\uDC9A"
    dimmed: root.dnd
    active: root.badge === "Highlight" && root.unread > 0
    activeColor: Color.accent
    tooltipText: {
      if (root.dnd) return root.unread > 0 ? "Silenced · " + root.unread + " new" : "Notifications silenced"
      if (root.unread === 1) return "1 new notification"
      if (root.unread > 1) return root.unread + " new notifications"
      return "Notifications"
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (panelLoader.item && panelLoader.item.toggleDnd) panelLoader.item.toggleDnd()
        return
      }
      root.toggle()
    }
  }

  readonly property var panelItem: panelLoader.item
  readonly property bool dnd: panelItem && panelItem.dnd ? true : false
  readonly property int unread: panelItem && panelItem.unread ? panelItem.unread : 0
  readonly property string badge: panelItem && panelItem.badge ? panelItem.badge : "Dot"

  Rectangle {
    visible: root.badge === "Dot" && root.unread > 0
    anchors.right: button.right
    anchors.rightMargin: Style.space(3)
    anchors.top: button.top
    anchors.topMargin: Style.space(5)
    width: Style.space(6)
    height: width
    radius: width / 2
    color: Color.accent
  }

  Rectangle {
    visible: root.badge === "Count" && root.unread > 0
    anchors.right: button.right
    anchors.rightMargin: Style.space(1)
    anchors.top: button.top
    anchors.topMargin: Style.space(3)
    width: Math.max(countText.implicitWidth + Style.space(6), Style.space(12))
    height: Style.space(12)
    radius: height / 2
    color: Color.accent

    Text {
      id: countText
      anchors.centerIn: parent
      text: root.unread > 99 ? "99+" : String(root.unread)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Math.max(8, Style.font.caption - Style.space(3))
      font.bold: true
      color: Color.background
    }
  }
}
