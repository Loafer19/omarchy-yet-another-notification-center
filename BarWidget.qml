import QtQuick
import qs.Commons
import qs.Ui
import "vendor/yoyo-ui"

BarWidget {
  id: root
  moduleName: "yoyo.notification-center"

  // The loaded Panel.qml; var because Loader.item is typed QObject.
  readonly property var panelItem: panelLoader.item

  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function toggle() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  function injectPanel() {
    var target = root.panelItem
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

  // No IpcHandler here: the bar builds this widget once per monitor, and a
  // target may have only one handler, so Service.qml owns it.

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "\uDB80\uDC9B" : "\uDB80\uDC9A"
    dimmed: root.dnd
    active: root.badge === "Highlight" && root.unread > 0
    activeColor: Theme.accent
    tooltipText: {
      if (root.dnd) return root.unread > 0 ? "Silenced · " + root.unread + " new" : "Notifications silenced"
      if (root.unread === 1) return "1 new notification"
      if (root.unread > 1) return root.unread + " new notifications"
      return "Notifications"
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.panelItem && root.panelItem.toggleDnd) root.panelItem.toggleDnd()
        return
      }
      root.toggle()
    }
  }

  // Omarchy 4.5: where the service draws a live toast's picture to save it
  // (Service.captureHost needs an item in a shown window). 0x0 and clipped,
  // so nothing of it ever shows.
  Item { id: captureHost; width: 0; height: 0; clip: true }
  readonly property var storeRef: panelItem && panelItem.store ? panelItem.store : null
  onStoreRefChanged: if (storeRef && storeRef.captureHost !== undefined && !storeRef.captureHost) storeRef.captureHost = captureHost
  Component.onDestruction: if (storeRef && storeRef.captureHost === captureHost) storeRef.captureHost = null
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
    color: Theme.accent
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
    color: Theme.accent

    Text {
      id: countText
      anchors.centerIn: parent
      text: root.unread > 99 ? "99+" : String(root.unread)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family // qmllint disable missing-property
      font.pixelSize: Math.max(8, Theme.caption - Style.space(3))
      font.bold: true
      color: Theme.background
    }
  }
}
