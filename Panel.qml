import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components" as Yanc

Panel {
  id: root
  moduleName: "yoyo.notification-center"
  ipcTarget: "yoyo.notification-center"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dividerColor: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.12)
  readonly property int edgeMargin: Style.space(6)

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

  readonly property var notificationService: {
    var host = bar && bar.shell ? bar.shell : null
    if (!host) return null
    var id = "omarchy.notifications"
    if (host.pluginRegistry && typeof host.pluginRegistry.resolveEnabledId === "function")
      id = host.pluginRegistry.resolveEnabledId(id)
    if (typeof host.serviceFor === "function") return host.serviceFor(id)
    if (typeof host.firstPartyServiceFor === "function") return host.firstPartyServiceFor(id)
    return null
  }
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false

  function toggleDnd() {
    if (notificationService) notificationService.setDoNotDisturb(!notificationService.doNotDisturb)
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
      root.activate(historyView[selectedIndex])
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

  Process { id: focusProc }

  function activate(row) {
    if (!row) return
    var action = String(cfg.clickAction || "Auto")
    if (action === "Nothing") return
    if (action === "Auto" && Model.isStoreImage(row.preview || row.file)) {
      var openPath = Model.storeImageUrl(row.preview || row.file).replace(/^file:\/\//, "")
      if (openPath && openPath.charAt(0) === "/" && openPath.indexOf("..") < 0)
        Quickshell.execDetached(["xdg-open", openPath])
      root.close()
      return
    }
    if (!root.omarchyPath || !Model.isSafeAppName(row.app)) return
    focusProc.command = [root.omarchyPath + "/bin/omarchy-hyprland-focus-app", row.app]
    focusProc.running = true
    root.close()
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

        Yanc.ChipRow {
          chips: root.tabs
          selectedKey: root.activeTab
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          cursorActive: root.cursorActive && root.focusSection === "tabs"
          cursorIndex: root.cursorActive && root.focusSection === "tabs" ? root.selectedIndex : -1
          onSelected: function(key) {
            root.activeTab = key
            root.setTabsCursor(root.chipIndexByKey(root.tabs, key))
          }
          onChipHovered: function(index) { root.setTabsCursor(index) }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.dividerColor }

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
              text: root.filter !== "" ? historyView.length + " matching" : (historyView.length + " kept")
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Yanc.HeaderChip {
              text: "DND"
              on: root.dnd
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              tooltipText: root.dnd ? "Allow notifications" : "Silence notifications"
              onClicked: root.toggleDnd()
            }

            Yanc.HeaderChip {
              text: "Auto-hide"
              on: root.autoHideOn
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              tooltipText: root.autoHideOn
                ? "Toasts stay up — Omarchy never expires critical on its own"
                : "Hide all toasts automatically, including critical"
              onClicked: root.toggleAutoHide()
            }

            Yanc.HeaderChip {
              visible: historyView.length > 0
              text: "Clear"
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              tooltipText: "Move everything in History to Trash"
              onClicked: if (store) store.clearAll()
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
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Yanc.HeaderChip {
            anchors.right: parent.right
            anchors.rightMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            visible: trashView.length > 0
            text: "Empty trash"
            contentForeground: root.contentForeground
            contentFontFamily: root.contentFontFamily
            tooltipText: "Delete trash forever"
            onClicked: if (store) store.emptyTrash()
          }
        }

        Yanc.ChipRow {
          visible: root.activeFilterChips.length > 0
          compact: true
          chips: root.activeFilterChips
          selectedKey: root.activeFilterKey
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
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
        anchors.bottom: parent.bottom

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
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "history" && root.selectedIndex === historyWrap.index
              onRowHovered: root.setRowCursor(historyWrap.index)
              onRowClicked: root.activate(historyWrap.modelData)
              onActionClicked: root.dismissRow(historyWrap.modelData)
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.activeTab === "history" && historyView.length === 0
          text: !root.loaded ? "Reading the archive…"
            : (root.filter !== "" || root.historyFilter !== "all") ? "Nothing matches"
            : "Nothing has come in yet"
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
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
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "trash" && root.selectedIndex === trashWrap.index
              onRowHovered: root.setRowCursor(trashWrap.index)
              onRowClicked: root.restoreRow(trashWrap.modelData)
              onActionClicked: root.restoreRow(trashWrap.modelData)
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.activeTab === "trash" && trashView.length === 0
          text: "Trash is empty"
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
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
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
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

        Text {
          anchors.centerIn: parent
          visible: root.activeTab === "settings" && root.settingsFilter === "apps" && settingsView.length === 0
          text: "No apps in the archive yet"
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
