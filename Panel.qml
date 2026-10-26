import qs.Commons as Commons
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Nav.js" as Nav
import "components" as Yanc
import "vendor/yoyo-ui"

Panel {
  id: root
  moduleName: "yoyo.notification-center"
  ipcTarget: "yoyo.notification-center"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // The host types bar and Style.font as plain QObject, so qmllint cannot
  // see their members; the disables below are for that alone.
  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground // qmllint disable missing-property
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family // qmllint disable missing-property
  readonly property int edgeMargin: Style.space(6)

  // Shared yoyo-ui Theme follows the bar this panel opens from.
  Binding { target: Theme; property: "foreground"; value: root.contentForeground }
  Binding { target: Theme; property: "fontFamily"; value: root.contentFontFamily }

  property string activeTab: "history"
  property string historyFilter: "all"
  property string settingsFilter: "general"
  property string filter: ""
  property bool searching: false
  property bool settingsPopupOpen: false
  property bool settingsFieldFocus: false
  property double now: Date.now()
  property double readMark: 0
  property var store: null

  readonly property var tabs: [
    { key: "history", label: "History" },
    { key: "trash", label: "Trash" },
    { key: "settings", label: "Settings" }
  ]
  readonly property var historyChips: [
    { key: "all", label: "All" },
    { key: "critical", label: "Critical" },
    { key: "normal", label: "Normal" },
    { key: "low", label: "Low" }
  ]
  readonly property var settingsChips: [
    { key: "general", label: "General" },
    { key: "sound", label: "Sound" },
    { key: "apps", label: "Apps" }
  ]

  readonly property var cfg: store && store.cfg ? store.cfg : Model.DEFAULTS
  // Settings live in the store only (settings.json via backend settings-get/
  // set); see README "Settings". Omarchy's per-widget settings are not read.
  readonly property string badge: String(cfg.badge || "Dot")
  readonly property var emptyList: []
  readonly property var entries: store ? store.entries : emptyList
  readonly property var trashEntries: store ? store.trashEntries : emptyList
  readonly property int unread: store ? store.unread : 0
  readonly property double lastSeen: store ? store.lastSeen : 0
  readonly property bool loaded: store ? store.loaded : false
  readonly property bool autoHideOn: Number(cfg.autoHideMs || 0) > 0

  // Bind the toggle to the plugin store only. Mixing first-party
  // doNotDisturb with FileView/CLI made the control flicker when those
  // sources briefly disagreed during a write.
  readonly property bool dnd: store ? store.doNotDisturb === true : false

  function toggleDnd() {
    if (store && store.toggleDnd) store.toggleDnd()
  }

  // Empty trash is permanent: the Trash bar's chip arms on the first click
  // and commits on the second (see components/TrashBar.qml).
  readonly property bool emptyTrashArmed: trashBar.armed

  function disarmEmptyTrash() { trashBar.disarm() }

  function requestEmptyTrash() {
    if (!store || trashView.length === 0) {
      disarmEmptyTrash()
      return
    }
    trashBar.activate()
  }

  onTrashViewChanged: if (trashView.length === 0) disarmEmptyTrash()

  Keys.onEscapePressed: function(event) {
    if (root.emptyTrashArmed) {
      root.disarmEmptyTrash()
      event.accepted = true
    }
  }

  function toggleAutoHide() {
    if (!store) return
    store.setSetting("autoHideMs", autoHideOn ? 0 : 8000)
  }

  function bindStore() {
    if (store) return
    var host = bar && bar.shell ? bar.shell : null // qmllint disable missing-property
    if (!host || typeof host.serviceFor !== "function") return
    var s = host.serviceFor("yoyo.notification-center")
    if (!s) return
    store = s
  }

  onBarChanged: bindStore()

  Timer {
    interval: 200
    running: root.store === null
    repeat: true
    onTriggered: root.bindStore()
  }

  Connections {
    target: root.store
    function onEntryAdded(entry) {
      if (root.opened && root.store) root.store.markSeen()
    }
    // Failed store/helper calls show in the footer (it only takes space while
    // a message is up) and are already logged by the service.
    function onActionFailed(action, message) { statusFooter.flash(message, "error") }
  }

  readonly property var historyView: Model.visibleEntries(entries, filter, historyFilter)
  readonly property var trashView: Model.rowsFor(trashEntries)
  readonly property var settingsView: Model.settingRows(cfg, settingsFilter, store && store.apps ? store.apps : [], store ? store.engine : "")

  property bool cursorActive: false
  property string focusSection: "rows"
  property int selectedIndex: 0

  readonly property var activeFilterChips: {
    if (root.activeTab === "history") return root.historyChips
    if (root.activeTab === "settings") return root.settingsChips
    return []
  }
  readonly property int activeListCount: {
    if (root.activeTab === "history") return historyView.length
    if (root.activeTab === "trash") return trashView.length
    if (root.activeTab === "settings") return settingsView.length
    return 0
  }

  readonly property string activeFilterKey: {
    if (root.activeTab === "history") return root.historyFilter
    if (root.activeTab === "settings") return root.settingsFilter
    return ""
  }

  function filterKeyForTab() { return root.activeFilterKey }

  function applyFilterKey(key) {
    if (root.activeTab === "history") {
      root.historyFilter = key
      if (root.focusSection === "rows") root.selectedIndex = 0
      return
    }
    if (root.activeTab === "settings") {
      root.settingsFilter = key
    }
  }

  // --- keyboard cursor (Nav.js) ----------------------------------------------
  function navContext() {
    return { tabs: root.tabs, activeTab: root.activeTab, chips: root.activeFilterChips,
             filterKey: root.activeFilterKey, count: root.activeListCount }
  }

  function rowCursor(tab) {
    return root.cursorActive && root.focusSection === "rows" && root.activeTab === tab ? root.selectedIndex : -1
  }

  // The first key press only shows the cursor (false); later ones move it.
  function ensureCursor() {
    if (root.cursorActive) return true
    root.cursorActive = true
    var at = Nav.start(root.navContext())
    root.focusSection = at.section
    root.selectedIndex = at.index
    return false
  }

  function setCursor(section, index) {
    root.cursorActive = true
    root.focusSection = section
    root.selectedIndex = index
  }
  function setRowCursor(index) { root.setCursor("rows", index) }
  function setTabsCursor(index) { root.setCursor("tabs", index) }
  function setFiltersCursor(index) { root.setCursor("filters", index) }

  function cycleTab(direction) {
    var to = Nav.cycleTab(root.navContext(), direction)
    root.activeTab = to.tab
    root.setTabsCursor(to.index)
  }

  function moveCursor(dx, dy) {
    if (!root.ensureCursor()) return
    var to = Nav.move({ section: root.focusSection, index: root.selectedIndex }, dx, dy, root.navContext())
    root.focusSection = to.section
    root.selectedIndex = to.index
    if (to.tab !== undefined) root.activeTab = to.tab
    if (to.filter !== undefined) root.applyFilterKey(to.filter)
    if (to.nudge) root.nudgeSetting(to.nudge)
  }

  function nudgeSetting(delta) {
    if (selectedIndex < 0 || selectedIndex >= settingsView.length || !store) return
    var change = Model.settingNudge(settingsView[selectedIndex], cfg, delta)
    if (!change) return
    if (change.app !== undefined) {
      store.setAppSound(change.app, change.value)
      return
    }
    store.setSetting(change.key, change.value)
    if (change.play) store.playSound(change.value)
  }

  function activateCursor() {
    if (!root.ensureCursor()) return
    if (root.focusSection === "tabs") {
      root.activeTab = root.tabs[root.selectedIndex].key
      return
    }
    if (root.focusSection === "filters") {
      root.applyFilterKey(root.activeFilterChips[root.selectedIndex].key)
      return
    }
    if (root.activeTab === "history" && selectedIndex >= 0 && selectedIndex < historyView.length)
      opener.activateAt(historyList, selectedIndex, historyView[selectedIndex])
    else if (root.activeTab === "trash" && selectedIndex >= 0 && selectedIndex < trashView.length)
      root.restoreRow(trashView[selectedIndex])
    else if (root.activeTab === "settings")
      root.nudgeSetting(1)
  }

  function deleteSelected() {
    if (root.activeTab === "history" && selectedIndex >= 0 && selectedIndex < historyView.length)
      root.dismissRow(historyView[selectedIndex])
    else if (root.activeTab === "trash" && selectedIndex >= 0 && selectedIndex < trashView.length)
      root.purgeRow(trashView[selectedIndex])
  }

  Yanc.RowOpener {
    id: opener
    store: root.store
    cfg: root.cfg
    omarchyPath: root.omarchyPath
    onCloseRequested: root.close()
  }

  function dismissRow(row) { if (store && row) store.dismiss(row.key) }
  function restoreRow(row) { if (store && row) store.restore(row.key) }
  function purgeRow(row) { if (store && row) store.purge(row.key) }

  function startSearch() {
    searching = true
    Qt.callLater(function() { if (root.searching) search.forceActiveFocus() })
  }
  function endSearch() {
    searching = false
    filter = ""
    search.text = ""
  }

  onActiveTabChanged: {
    root.disarmEmptyTrash()
    root.selectedIndex = 0
    root.focusSection = root.activeFilterChips.length > 0 ? "filters" : "rows"
  }

  onOpenedChanged: {
    if (!opened) {
      searching = false
      filter = ""
      search.text = ""
      return
    }
    now = Date.now()
    if (store) store.load()
    readMark = lastSeen
    if (store) store.markSeen()
    root.cursorActive = false
    root.focusSection = "rows"
    root.selectedIndex = 0
  }

  Component.onCompleted: bindStore()

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.searching || root.settingsPopupOpen || root.settingsFieldFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.cycleTab(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.deleteSelected()
      onTextKey: function(text) { if (text === "/") root.startSearch() }

      Column {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(8)

        ChipRow {
          chips: root.tabs
          selectedKey: root.activeTab
          cursorActive: root.cursorActive && root.focusSection === "tabs"
          cursorIndex: root.cursorActive && root.focusSection === "tabs" ? root.selectedIndex : -1
          onSelected: function(key) {
            root.activeTab = key
            root.setTabsCursor(Nav.indexOfKey(root.tabs, key))
          }
          onChipHovered: function(index) { root.setTabsCursor(index) }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: Theme.line } // qmllint disable missing-property

        Yanc.HistoryBar {
          width: parent.width
          visible: root.activeTab === "history"
          count: root.historyView.length
          searching: root.filter !== ""
          dnd: root.dnd
          autoHide: root.autoHideOn
          onDndClicked: root.toggleDnd()
          onAutoHideClicked: root.toggleAutoHide()
          onClearClicked: if (root.store) root.store.clearAll()
        }

        TextField {
          id: search
          width: parent.width
          visible: root.searching && root.activeTab === "history"
          placeholderText: "Search"
          onTextChanged: root.filter = text
          Keys.onEscapePressed: root.endSearch()
        }

        Yanc.TrashBar {
          id: trashBar
          width: parent.width
          visible: root.activeTab === "trash"
          count: root.trashView.length
          days: Number(root.cfg.trashDays || 30)
          onEmptyTrash: if (root.store) root.store.emptyTrash()
        }

        ChipRow {
          visible: root.activeFilterChips.length > 0
          compact: true
          chips: root.activeFilterChips
          selectedKey: root.activeFilterKey
          cursorActive: root.cursorActive && root.focusSection === "filters"
          cursorIndex: root.cursorActive && root.focusSection === "filters" ? root.selectedIndex : -1
          onSelected: function(key) {
            root.applyFilterKey(key)
            root.setFiltersCursor(Nav.indexOfKey(root.activeFilterChips, key))
          }
          onChipHovered: function(index) { root.setFiltersCursor(index) }
        }
      }

      Item {
        id: body
        anchors.top: header.bottom
        anchors.topMargin: root.edgeMargin
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusFooter.top

        Yanc.RowList {
          id: historyList
          anchors.fill: parent
          visible: root.activeTab === "history"
          model: root.historyView
          now: root.now
          readMark: root.readMark
          markUnread: true
          showBody: !!root.cfg.showBody
          showPreview: !!root.cfg.showPreview
          actionLabel: "Trash"
          danger: true
          edgeMargin: root.edgeMargin
          cursorIndex: root.rowCursor("history")
          onRowHovered: function(index) { root.setRowCursor(index) }
          onRowClicked: function(index, row) { opener.activateAt(historyList, index, row) }
          onCopyClicked: function(index, row) { opener.copyRow(historyList, index, row) }
          onActionClicked: function(row) { root.dismissRow(row) }
        }

        BodyEmpty {
          visible: root.activeTab === "history" && root.historyView.length === 0
          title: !root.loaded ? "Reading the archive…"
            : (root.filter !== "" || root.historyFilter !== "all") ? "Nothing matches"
            : "Nothing has come in yet"
        }

        Yanc.RowList {
          id: trashList
          anchors.fill: parent
          visible: root.activeTab === "trash"
          model: root.trashView
          now: root.now
          showBody: !!root.cfg.showBody
          showPreview: !!root.cfg.showPreview
          actionLabel: "Restore"
          danger: false
          edgeMargin: root.edgeMargin
          cursorIndex: root.rowCursor("trash")
          onRowHovered: function(index) { root.setRowCursor(index) }
          onRowClicked: function(index, row) { root.restoreRow(row) }
          onCopyClicked: function(index, row) { opener.copyRow(trashList, index, row) }
          onActionClicked: function(row) { root.restoreRow(row) }
        }

        BodyEmpty {
          visible: root.activeTab === "trash" && root.trashView.length === 0
          title: "Trash is empty"
        }

        Yanc.SettingsList {
          anchors.fill: parent
          visible: root.activeTab === "settings"
          model: root.settingsView
          edgeMargin: root.edgeMargin
          cursorIndex: root.rowCursor("settings")
          onRowHovered: function(index) { root.setRowCursor(index) }
          onRowClicked: function(index) {
            root.setRowCursor(index)
            root.nudgeSetting(1)
          }
          onValuePicked: function(index, row, v) {
            root.setRowCursor(index)
            if (row.optionSet === "sound" || row.optionSet === "appSound") {
              if (root.store) root.store.playSound(v)
            }
            if (row.kind === "appSound") root.store.setAppSound(row.app, v)
            else root.store.setSetting(row.key, v)
          }
          onPlayClicked: function(index, row) {
            root.setRowCursor(index)
            if (root.store) root.store.playSound(row.currentValue)
          }
          onNumberPicked: function(index, row, v) {
            root.setRowCursor(index)
            root.store.setSetting(row.key, v)
          }
          onPopupOpenChanged: function(open) { root.settingsPopupOpen = open }
          onFieldFocusChanged: function(on) { root.settingsFieldFocus = on }
        }

        BodyEmpty {
          visible: root.activeTab === "settings" && root.settingsFilter === "apps" && root.settingsView.length === 0
          title: "No apps in the archive yet"
        }
      }

      // Takes no space unless a failure is being shown (clears after 6 s).
      StatusFooter {
        id: statusFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: statusText !== ""
        height: visible ? implicitHeight : 0
      }
    }
  }

  // The empty-list message, centred in the body.
  component BodyEmpty: EmptyState {
    anchors.centerIn: parent
    width: parent.width
    fitContent: true
    topPadding: 0
    bottomPadding: 0
  }
}
