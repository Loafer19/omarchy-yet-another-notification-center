import qs.Commons as Commons
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
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

  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
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
  readonly property string badge: String(setting("badge", cfg.badge || "Dot"))
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

  // Empty trash is permanent — arm on first click, commit on second.
  // Auto-disarms (4 s) so a stray click later cannot wipe the bin. The
  // two-step logic lives in the chip (HeaderChip confirm mode).
  readonly property bool emptyTrashArmed: emptyTrashChip.armed

  function disarmEmptyTrash() { emptyTrashChip.disarm() }

  function requestEmptyTrash() {
    if (!store || trashView.length === 0) {
      disarmEmptyTrash()
      return
    }
    emptyTrashChip.activate()
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
    if (store) {
      pushSchemaSettings()
      return
    }
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return
    var s = host.serviceFor("yoyo.notification-center")
    if (!s) return
    store = s
  }

  function pushSchemaSettings() {
    if (!store) return
    var keys = ["badge", "keepDays", "displayLimit", "autoHideMs", "soundEnabled"]
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      var v = settings ? settings[k] : undefined
      if (v === undefined || v === null) continue
      if (store.cfg && store.cfg[k] === v) continue
      store.setSetting(k, v)
    }
  }

  onBarChanged: bindStore()
  onSettingsChanged: pushSchemaSettings()

  Timer {
    interval: 200
    running: root.store === null
    repeat: true
    onTriggered: root.bindStore()
  }

  Connections {
    target: root.store
    function onEntryAdded(entry) {
      if (root.opened && store) store.markSeen()
    }
    // Failed store/helper calls show in the footer (it only takes space while
    // a message is up) and are already logged by the service.
    function onActionFailed(action, message) { statusFooter.flash(message, "error") }
  }

  readonly property var historyView: Model.visibleEntries(entries, filter, historyFilter)
  readonly property var trashView: Model.rowsFor(trashEntries)
  readonly property var settingsView: Model.settingRows(cfg, settingsFilter, store && store.apps ? store.apps : [])

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

  function chipIndexByKey(chips, key) {
    for (var i = 0; i < chips.length; i++) {
      if (String(chips[i].key) === String(key)) return i
    }
    return 0
  }

  function clampIndex(i, len) {
    if (len <= 0) return 0
    if (i < 0) return 0
    if (i >= len) return len - 1
    return i
  }

  function ensureCursor() {
    if (!root.cursorActive) {
      root.cursorActive = true
      if (root.activeListCount > 0) {
        root.focusSection = "rows"
        root.selectedIndex = 0
      } else if (root.activeFilterChips.length > 0) {
        root.focusSection = "filters"
        root.selectedIndex = root.chipIndexByKey(root.activeFilterChips, root.filterKeyForTab())
      } else {
        root.focusSection = "tabs"
        root.selectedIndex = root.chipIndexByKey(root.tabs, root.activeTab)
      }
      return false
    }
    return true
  }

  function setRowCursor(index) {
    root.cursorActive = true
    root.focusSection = "rows"
    root.selectedIndex = index
  }
  function setTabsCursor(index) {
    root.cursorActive = true
    root.focusSection = "tabs"
    root.selectedIndex = index
  }
  function setFiltersCursor(index) {
    root.cursorActive = true
    root.focusSection = "filters"
    root.selectedIndex = index
  }

  function cycleTab(direction) {
    var n = root.tabs.length
    var i = root.chipIndexByKey(root.tabs, root.activeTab)
    i = (i + direction) % n
    if (i < 0) i += n
    root.activeTab = root.tabs[i].key
    root.setTabsCursor(i)
  }

  function moveCursor(dx, dy) {
    if (!root.ensureCursor()) return
    if (dy !== 0) {
      if (root.focusSection === "tabs") {
        if (dy > 0) {
          if (root.activeFilterChips.length > 0) {
            root.focusSection = "filters"
            root.selectedIndex = root.chipIndexByKey(root.activeFilterChips, root.filterKeyForTab())
          } else if (root.activeListCount > 0) {
            root.focusSection = "rows"
            root.selectedIndex = 0
          }
        }
        return
      }
      if (root.focusSection === "filters") {
        if (dy > 0 && root.activeListCount > 0) {
          root.focusSection = "rows"
          root.selectedIndex = 0
        } else if (dy < 0) {
          root.focusSection = "tabs"
          root.selectedIndex = root.chipIndexByKey(root.tabs, root.activeTab)
        }
        return
      }
      if (dy > 0) root.selectedIndex = root.clampIndex(root.selectedIndex + 1, root.activeListCount)
      else if (root.selectedIndex > 0) root.selectedIndex = root.selectedIndex - 1
      else if (root.activeFilterChips.length > 0) {
        root.focusSection = "filters"
        root.selectedIndex = root.chipIndexByKey(root.activeFilterChips, root.filterKeyForTab())
      } else {
        root.focusSection = "tabs"
        root.selectedIndex = root.chipIndexByKey(root.tabs, root.activeTab)
      }
      return
    }
    if (dx === 0) return
    if (root.focusSection === "tabs") {
      root.selectedIndex = root.clampIndex(root.selectedIndex + dx, root.tabs.length)
      root.activeTab = root.tabs[root.selectedIndex].key
      return
    }
    if (root.focusSection === "filters" && root.activeFilterChips.length > 0) {
      root.selectedIndex = root.clampIndex(root.selectedIndex + dx, root.activeFilterChips.length)
      root.applyFilterKey(root.activeFilterChips[root.selectedIndex].key)
      return
    }
    if (root.focusSection === "rows" && root.activeTab === "settings")
      root.nudgeSetting(dx)
  }

  function nudgeSetting(delta) {
    if (selectedIndex < 0 || selectedIndex >= settingsView.length) return
    var row = settingsView[selectedIndex]
    if (!row || !store) return
    if (row.kind === "toggle") {
      store.setSetting(row.key, !(cfg[row.key]))
      return
    }
    if (row.kind === "step") {
      var min = Number(row.min || 1)
      var max = Number(row.max || 100)
      var step = Number(row.step || 1)
      var next = Model.clampInt(Number(cfg[row.key] || min) + delta * step, min, max, min)
      store.setSetting(row.key, next)
      return
    }
    if (row.kind === "enum" && Model.enumList(row.key).length)
      store.setSetting(row.key, Model.cycle(Model.enumList(row.key), cfg[row.key], delta))
    else if (row.kind === "enum" && (row.key === "defaultSound" || row.key === "soundLow" || row.key === "soundNormal" || row.key === "soundCritical")) {
      var soundNext = Model.cycle(Model.SOUND_IDS, cfg[row.key], delta)
      store.setSetting(row.key, soundNext)
      store.playSound(soundNext)
    } else if (row.kind === "appSound") {
      var cur = (cfg.appSounds && cfg.appSounds[row.app]) ? cfg.appSounds[row.app] : "inherit"
      store.setAppSound(row.app, Model.cycle(["inherit"].concat(Model.SOUND_IDS), cur, delta))
    }
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
      root.activateAt(historyList, selectedIndex, historyView[selectedIndex])
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

  property var pendingFocus: null

  Process {
    id: focusProc
    onExited: function(exitCode) {
      var pending = root.pendingFocus
      root.pendingFocus = null
      if (exitCode === 0) {
        root.close()
        return
      }
      if (!pending) return
      var wrap = pending.list && pending.list.itemAtIndex ? pending.list.itemAtIndex(pending.index) : null
      if (wrap && wrap.showNotice)
        wrap.showNotice("No window", root.noticeIdentity(pending.row))
    }
  }

  function noticeIdentity(row) {
    var app = String((row && row.app) || "").replace(/^\s+|\s+$/g, "")
    if (!app) app = "Notification"
    var summary = String((row && row.summary) || "").replace(/^\s+|\s+$/g, "")
    if (summary.length > 42) summary = summary.slice(0, 41) + "…"
    if (summary) return app + " · " + summary
    return app
  }

  function flashNotice(list, index, title, detail) {
    var wrap = list && list.itemAtIndex ? list.itemAtIndex(index) : null
    if (wrap && wrap.showNotice) wrap.showNotice(title, detail)
  }

  function activateAt(list, index, row) {
    if (!row) {
      root.flashNotice(list, index, "Can't open", "")
      return
    }
    var who = root.noticeIdentity(row)
    var action = String(cfg.clickAction || "Auto")
    if (action === "Nothing") {
      root.flashNotice(list, index, "Clicks are off", who)
      return
    }
    if (action === "Auto" && Model.isStoreImage(row.preview || row.file)) {
      var openPath = Model.storeImageUrl(row.preview || row.file).replace(/^file:\/\//, "")
      if (!openPath || openPath.charAt(0) !== "/" || openPath.indexOf("..") >= 0) {
        root.flashNotice(list, index, "Can't open", who)
        return
      }
      root.openPicture(list, index, who, openPath)
      return
    }
    if (!root.omarchyPath) {
      root.flashNotice(list, index, "Can't open", who)
      return
    }
    if (!Model.isSafeAppName(row.app)) {
      root.flashNotice(list, index, String(row.app || "").length ? "Can't open" : "No app to open", who)
      return
    }
    root.pendingFocus = { list: list, index: index, row: row }
    focusProc.running = false
    focusProc.command = [root.omarchyPath + "/bin/omarchy-hyprland-focus-app", row.app]
    focusProc.running = true
  }

  // xdg-open may stay up as long as the viewer does: close the panel once it
  // has run for a moment or exited cleanly; a quick non-zero exit keeps the
  // panel open and says so on the row.
  property var pendingOpen: null
  Timer {
    id: openSettle
    interval: 700
    onTriggered: if (root.pendingOpen) { root.pendingOpen.settled = true; root.close() }
  }

  function openPicture(list, index, who, path) {
    if (!store) return
    var token = { settled: false }
    root.pendingOpen = token
    openSettle.restart()
    store.run("open", ["xdg-open", path], function(res) {
      if (root.pendingOpen === token) { root.pendingOpen = null; openSettle.stop() }
      if (res.ok) {
        if (!token.settled) root.close()
        return
      }
      if (!token.settled) root.flashNotice(list, index, "Can't open", who)
    })
  }

  function copyRow(list, index, row) {
    if (!row || !store) return
    var text = Model.copyTextFor(row)
    if (!text) return
    store.run("copy", ["wl-copy", "--", text], function(res) {
      var wrap = list && list.itemAtIndex ? list.itemAtIndex(index) : null
      if (wrap && wrap.copyFinished) wrap.copyFinished(res.ok, res.error)
    })
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
            root.setTabsCursor(root.chipIndexByKey(root.tabs, key))
          }
          onChipHovered: function(index) { root.setTabsCursor(index) }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: Theme.line }

        Item {
          width: parent.width
          height: Style.space(28)
          visible: root.activeTab === "history"

          Row {
            anchors.left: parent.left
            anchors.leftMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              text: root.filter !== "" ? historyView.length + " matching" : (historyView.length + " in History")
              color: Theme.dim
              font.family: Theme.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            HeaderChip {
              text: "DND"
              on: root.dnd
              tooltipText: root.dnd ? "Allow notifications" : "Silence notifications"
              onClicked: root.toggleDnd()
            }

            HeaderChip {
              text: "Auto-hide"
              on: root.autoHideOn
              tooltipText: root.autoHideOn
                ? "Toasts stay up — Omarchy never expires critical on its own"
                : "Hide all toasts automatically, including critical"
              onClicked: root.toggleAutoHide()
            }

            HeaderChip {
              // Stay visible when empty — disabled instead of vanishing so the
              // header layout does not jump and the action stays discoverable.
              text: "Clear"
              enabled: historyView.length > 0
              tooltipText: historyView.length > 0
                ? "Move everything in History to Trash"
                : "History is already empty"
              onClicked: if (root.store) root.store.clearAll()
            }
          }
        }

        TextField {
          id: search
          width: parent.width
          visible: root.searching && root.activeTab === "history"
          placeholderText: "Search"
          onTextChanged: root.filter = text
          Keys.onEscapePressed: root.endSearch()
        }

        Item {
          width: parent.width
          height: Style.space(28)
          visible: root.activeTab === "trash"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            text: {
              var days = Number(root.cfg.trashDays || 30)
              var kept = days === 1 ? "1 day" : days + " days"
              return trashView.length === 0 ? "Empty · kept " + kept : trashView.length + " in trash · " + kept
            }
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Style.font.caption
          }

          HeaderChip {
            id: emptyTrashChip
            anchors.right: parent.right
            anchors.rightMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            text: "Empty trash"
            confirm: true
            confirmText: "Confirm?"
            armMs: 4000
            danger: true
            enabled: trashView.length > 0
            tooltipText: trashView.length === 0
              ? "Trash is already empty"
              : (emptyTrashChip.armed
                ? "Click again to delete forever — Esc or wait to cancel"
                : "Delete trash forever (asks for confirmation)")
            onTriggered: if (root.store) root.store.emptyTrash()
          }
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
            root.setFiltersCursor(root.chipIndexByKey(root.activeFilterChips, key))
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

        ListView {
          id: historyList
          anchors.fill: parent
          visible: root.activeTab === "history"
          clip: true
          spacing: Style.space(6)
          model: historyView
          delegate: Item {
            id: historyWrap
            required property int index
            required property var modelData
            width: ListView.view.width
            height: historyCard.implicitHeight
            function showNotice(title, detail) { historyCard.showNotice(title, detail) }
            function copyFinished(ok, error) { historyCard.copyFinished(ok, error) }

            Yanc.NotificationRow {
              id: historyCard
              width: parent.width
              app: historyWrap.modelData.app
              appIcon: historyWrap.modelData.appIcon
              summary: historyWrap.modelData.summary
              body: historyWrap.modelData.body
              image: historyWrap.modelData.image
              preview: historyWrap.modelData.preview
              glyph: historyWrap.modelData.glyph
              time: Model.formatTime(historyWrap.modelData.timestamp, root.now)
              urgency: historyWrap.modelData.urgency
              unread: historyWrap.modelData.timestamp > root.readMark
              showBody: !!root.cfg.showBody
              showPreview: !!root.cfg.showPreview
              actionLabel: "Trash"
              danger: true
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "history" && root.selectedIndex === historyWrap.index
              onRowHovered: root.setRowCursor(historyWrap.index)
              onRowClicked: root.activateAt(historyList, historyWrap.index, historyWrap.modelData)
              onCopyClicked: root.copyRow(historyList, historyWrap.index, historyWrap.modelData)
              onActionClicked: root.dismissRow(historyWrap.modelData)
            }
          }
        }

        EmptyState {
          anchors.centerIn: parent
          width: parent.width
          fitContent: true
          topPadding: 0
          bottomPadding: 0
          visible: root.activeTab === "history" && historyView.length === 0
          title: !root.loaded ? "Reading the archive…"
            : (root.filter !== "" || root.historyFilter !== "all") ? "Nothing matches"
            : "Nothing has come in yet"
        }

        ListView {
          id: trashList
          anchors.fill: parent
          visible: root.activeTab === "trash"
          clip: true
          spacing: Style.space(6)
          model: trashView
          delegate: Item {
            id: trashWrap
            required property int index
            required property var modelData
            width: ListView.view.width
            height: trashCard.implicitHeight
            function showNotice(title, detail) { trashCard.showNotice(title, detail) }
            function copyFinished(ok, error) { trashCard.copyFinished(ok, error) }
            Yanc.NotificationRow {
              id: trashCard
              width: parent.width
              app: trashWrap.modelData.app
              appIcon: trashWrap.modelData.appIcon
              summary: trashWrap.modelData.summary
              body: trashWrap.modelData.body
              image: trashWrap.modelData.image
              preview: trashWrap.modelData.preview
              glyph: trashWrap.modelData.glyph
              time: Model.formatTime(trashWrap.modelData.timestamp, root.now)
              urgency: trashWrap.modelData.urgency
              showBody: !!root.cfg.showBody
              showPreview: !!root.cfg.showPreview
              actionLabel: "Restore"
              danger: false
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "trash" && root.selectedIndex === trashWrap.index
              onRowHovered: root.setRowCursor(trashWrap.index)
              onRowClicked: root.restoreRow(trashWrap.modelData)
              onCopyClicked: root.copyRow(trashList, trashWrap.index, trashWrap.modelData)
              onActionClicked: root.restoreRow(trashWrap.modelData)
            }
          }
        }

        EmptyState {
          anchors.centerIn: parent
          width: parent.width
          fitContent: true
          topPadding: 0
          bottomPadding: 0
          visible: root.activeTab === "trash" && trashView.length === 0
          title: "Trash is empty"
        }

        ListView {
          id: settingsList
          anchors.fill: parent
          visible: root.activeTab === "settings"
          clip: true
          spacing: 0
          model: settingsView
          delegate: Item {
            id: settingWrap
            required property int index
            required property var modelData
            width: ListView.view.width
            height: settingCard.height
            Yanc.SettingRow {
              id: settingCard
              width: parent.width
              title: settingWrap.modelData.title
              subtitle: settingWrap.modelData.subtitle
              kind: settingWrap.modelData.kind
              checked: settingWrap.modelData.checked
              currentValue: settingWrap.modelData.currentValue
              optionSet: settingWrap.modelData.optionSet
              numericValue: settingWrap.modelData.numericValue
              numericMin: settingWrap.modelData.min
              numericMax: settingWrap.modelData.max
              numericStep: settingWrap.modelData.step
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "settings" && root.selectedIndex === settingWrap.index
              onRowHovered: root.setRowCursor(settingWrap.index)
              onRowClicked: {
                root.setRowCursor(settingWrap.index)
                root.nudgeSetting(1)
              }
              onValuePicked: function(v) {
                root.setRowCursor(settingWrap.index)
                if (settingWrap.modelData.optionSet === "sound" || settingWrap.modelData.optionSet === "appSound") {
                  if (root.store) root.store.playSound(v)
                }
                if (settingWrap.modelData.kind === "appSound") root.store.setAppSound(settingWrap.modelData.app, v)
                else root.store.setSetting(settingWrap.modelData.key, v)
              }
              onPlayClicked: {
                root.setRowCursor(settingWrap.index)
                if (root.store) root.store.playSound(settingWrap.modelData.currentValue)
              }
              onNumberPicked: function(v) {
                root.setRowCursor(settingWrap.index)
                root.store.setSetting(settingWrap.modelData.key, v)
              }
              onPopupOpenChanged: function(open) { root.settingsPopupOpen = open }
              onFieldFocusChanged: function(on) { root.settingsFieldFocus = on }
            }
          }
        }

        EmptyState {
          anchors.centerIn: parent
          width: parent.width
          fitContent: true
          topPadding: 0
          bottomPadding: 0
          visible: root.activeTab === "settings" && root.settingsFilter === "apps" && settingsView.length === 0
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
}
