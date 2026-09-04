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
  readonly property var entries: store ? store.entries : []
  readonly property var trashEntries: store ? store.trashEntries : []
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
    rebuild()
    rebuildTrash()
    rebuildSettings()
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
      rebuild()
    }
    function onEntriesReset() { root.rebuild() }
    function onTrashReset() { root.rebuildTrash() }
    function onSettingsChanged() { root.rebuildSettings() }
  }

  ListModel { id: historyRows }
  ListModel { id: trashRows }
  ListModel { id: settingRows }

  function rebuild() {
    historyRows.clear()
    var list = entries || []
    for (var i = 0; i < list.length; i++) {
      if (Model.matches(list[i], filter) && Model.matchesUrgency(list[i], root.historyFilter))
        historyRows.append(Model.rowFor(list[i], now))
    }
  }

  function rebuildTrash() {
    trashRows.clear()
    var list = trashEntries || []
    for (var i = 0; i < list.length; i++)
      trashRows.append(Model.rowFor(list[i], now))
  }

  function boolLabel(v) { return v ? "On" : "Off" }

  function rebuildSettings() {
    settingRows.clear()
    var c = cfg
    if (settingsFilter === "sound") {
      settingRows.append({ key: "soundEnabled", kind: "toggle", title: "Play a sound", subtitle: "Omarchy's daemon is silent — this plays one when a notification arrives", valueLabel: boolLabel(!!c.soundEnabled) })
      settingRows.append({ key: "soundCritical", kind: "enum", title: "Critical", subtitle: "Omarchy -u critical — never auto-expires on its own", valueLabel: Model.soundLabel(c.soundCritical || "warning") })
      settingRows.append({ key: "soundNormal", kind: "enum", title: "Normal", subtitle: "The usual desktop notification", valueLabel: Model.soundLabel(c.soundNormal || c.defaultSound || "message") })
      settingRows.append({ key: "soundLow", kind: "enum", title: "Low", subtitle: "Omarchy -u low — quiet toasts", valueLabel: Model.soundLabel(c.soundLow || "complete") })
      settingRows.append({ key: "muteSoundWhenDnd", kind: "toggle", title: "Mute while Do Not Disturb", subtitle: "Still archives the notification", valueLabel: boolLabel(!!c.muteSoundWhenDnd) })
      return
    }
    if (settingsFilter === "apps") {
      var apps = store && store.apps ? store.apps : []
      for (var i = 0; i < apps.length; i++) {
        var app = apps[i].app
        var current = (c.appSounds && c.appSounds[app]) ? c.appSounds[app] : "inherit"
        settingRows.append({
          key: "app:" + app,
          kind: "appSound",
          title: app,
          subtitle: (apps[i].count || 1) + " in archive · − / + to pick a sound",
          valueLabel: Model.soundLabel(current),
          app: app
        })
      }
      return
    }
    settingRows.append({ key: "displayLimit", kind: "step", title: "Show at most", subtitle: "Cards on the History tab · − / +", valueLabel: String(c.displayLimit || 50), min: 10, max: 500, step: 10 })
    settingRows.append({ key: "keepDays", kind: "step", title: "Keep history for", subtitle: "Days. Older entries are deleted", valueLabel: String(c.keepDays || 30) + " days", min: 1, max: 365, step: 1 })
    settingRows.append({ key: "maxItems", kind: "step", title: "Keep at most", subtitle: "Archive ceiling, regardless of age", valueLabel: String(c.maxItems || 1000), min: 50, max: 10000, step: 50 })
    settingRows.append({ key: "clickAction", kind: "enum", title: "Clicking a notification", subtitle: "Never runs the sender's command", valueLabel: String(c.clickAction || "Auto") })
    settingRows.append({ key: "showBody", kind: "toggle", title: "Show the message text", subtitle: "Off leaves the sender and subject", valueLabel: boolLabel(!!c.showBody) })
    settingRows.append({ key: "showPreview", kind: "toggle", title: "Show pictures", subtitle: "Off stops keeping copies of new ones", valueLabel: boolLabel(!!c.showPreview) })
    settingRows.append({ key: "badge", kind: "enum", title: "Unread mark", subtitle: "Dot, Highlight, Count, or None", valueLabel: String(c.badge || "Dot") })
  }

  property bool cursorActive: false
  property string focusSection: "rows"
  property int selectedIndex: 0

  readonly property var activeFilterChips: {
    if (root.activeTab === "history") return root.historyChips
    if (root.activeTab === "settings") return root.settingsChips
    return []
  }
  readonly property int activeListCount: {
    if (root.activeTab === "history") return historyRows.count
    if (root.activeTab === "trash") return trashRows.count
    if (root.activeTab === "settings") return settingRows.count
    return 0
  }

  function filterKeyForTab() {
    if (root.activeTab === "history") return root.historyFilter
    if (root.activeTab === "settings") return root.settingsFilter
    return ""
  }

  function applyFilterKey(key) {
    if (root.activeTab === "history") {
      root.historyFilter = key
      root.rebuild()
      if (root.focusSection === "rows") root.selectedIndex = 0
      return
    }
    if (root.activeTab === "settings") {
      root.settingsFilter = key
      root.rebuildSettings()
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
    if (selectedIndex < 0 || selectedIndex >= settingRows.count) return
    var row = settingRows.get(selectedIndex)
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
    if (row.kind === "enum" && row.key === "clickAction")
      store.setSetting("clickAction", Model.cycle(["Auto", "Focus the app", "Nothing"], cfg.clickAction, delta))
    else if (row.kind === "enum" && row.key === "badge")
      store.setSetting("badge", Model.cycle(["Dot", "Highlight", "Count", "None"], cfg.badge, delta))
    else if (row.kind === "enum" && (row.key === "defaultSound" || row.key === "soundLow" || row.key === "soundNormal" || row.key === "soundCritical"))
      store.setSetting(row.key, Model.cycle(Model.SOUND_IDS, cfg[row.key], delta))
    else if (row.kind === "appSound") {
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
    if (root.activeTab === "history" && selectedIndex >= 0 && selectedIndex < historyRows.count)
      root.activate(historyRows.get(selectedIndex))
    else if (root.activeTab === "trash" && selectedIndex >= 0 && selectedIndex < trashRows.count)
      root.restoreRow(trashRows.get(selectedIndex))
    else if (root.activeTab === "settings")
      root.nudgeSetting(1)
  }

  function deleteSelected() {
    if (root.activeTab === "history" && selectedIndex >= 0 && selectedIndex < historyRows.count)
      root.dismissRow(historyRows.get(selectedIndex))
    else if (root.activeTab === "trash" && selectedIndex >= 0 && selectedIndex < trashRows.count)
      root.purgeRow(trashRows.get(selectedIndex))
  }

  Process { id: focusProc }

  function activate(row) {
    if (!row) return
    var action = String(cfg.clickAction || "Auto")
    if (action === "Nothing") return
    if (action === "Auto" && Model.isImagePath(row.file)) {
      Quickshell.execDetached(["xdg-open", String(row.file)])
      root.close()
      return
    }
    if (!Model.isSafeAppName(row.app)) return
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
  onSettingsFilterChanged: rebuildSettings()
  onHistoryFilterChanged: rebuild()
  onFilterChanged: rebuild()

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
      blocked: root.searching
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
              text: root.filter !== "" ? historyRows.count + " matching" : (historyRows.count + " kept")
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
              text: root.dnd ? "DND" : "DND off"
              on: root.dnd
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              onClicked: root.toggleDnd()
            }

            Yanc.HeaderChip {
              text: root.autoHideOn ? "Auto-hide" : "Auto-hide off"
              on: root.autoHideOn
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              onClicked: root.toggleAutoHide()
            }

            Yanc.HeaderChip {
              visible: historyRows.count > 0
              text: "Clear"
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
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
            text: trashRows.count === 0 ? "Empty · kept 30 days" : trashRows.count + " in trash · 30 days"
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Yanc.HeaderChip {
            anchors.right: parent.right
            anchors.rightMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            visible: trashRows.count > 0
            text: "Empty trash"
            danger: true
            contentForeground: root.contentForeground
            contentFontFamily: root.contentFontFamily
            onClicked: if (store) store.emptyTrash()
          }
        }

        Yanc.ChipRow {
          visible: root.activeTab === "history"
          compact: true
          chips: root.historyChips
          selectedKey: root.historyFilter
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          cursorActive: root.cursorActive && root.focusSection === "filters" && root.activeTab === "history"
          cursorIndex: root.cursorActive && root.focusSection === "filters" && root.activeTab === "history" ? root.selectedIndex : -1
          onSelected: function(key) {
            root.historyFilter = key
            root.setFiltersCursor(root.chipIndexByKey(root.historyChips, key))
          }
          onChipHovered: function(index) { root.setFiltersCursor(index) }
        }

        Yanc.ChipRow {
          visible: root.activeTab === "settings"
          compact: true
          chips: root.settingsChips
          selectedKey: root.settingsFilter
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          cursorActive: root.cursorActive && root.focusSection === "filters" && root.activeTab === "settings"
          cursorIndex: root.cursorActive && root.focusSection === "filters" && root.activeTab === "settings" ? root.selectedIndex : -1
          onSelected: function(key) {
            root.settingsFilter = key
            root.setFiltersCursor(root.chipIndexByKey(root.settingsChips, key))
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
          model: historyRows
          section.property: "day"
          section.criteria: ViewSection.FullString
          section.delegate: Item {
            required property string section
            width: ListView.view.width
            height: dayLabel.implicitHeight + Style.space(10)
            Text {
              id: dayLabel
              anchors.left: parent.left
              anchors.leftMargin: root.edgeMargin
              anchors.bottom: parent.bottom
              text: parent.section.toUpperCase()
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
          delegate: Item {
            id: historyWrap
            required property int index
            required property string key
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property string preview
            required property string file
            required property string glyph
            required property string time
            required property double timestamp
            required property int urgency
            width: ListView.view.width
            height: historyCard.implicitHeight
            Yanc.NotificationRow {
              id: historyCard
              width: parent.width
              app: historyWrap.app
              appIcon: historyWrap.appIcon
              summary: historyWrap.summary
              body: historyWrap.body
              image: historyWrap.image
              preview: historyWrap.preview
              glyph: historyWrap.glyph
              time: historyWrap.time
              urgency: historyWrap.urgency
              unread: historyWrap.timestamp > root.readMark
              showBody: !!root.cfg.showBody
              showPreview: !!root.cfg.showPreview
              actionLabel: "Trash"
              danger: true
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "history" && root.selectedIndex === historyWrap.index
              onRowHovered: root.setRowCursor(historyWrap.index)
              onRowClicked: root.activate({ key: historyWrap.key, app: historyWrap.app, file: historyWrap.file })
              onActionClicked: root.dismissRow({ key: historyWrap.key })
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.activeTab === "history" && historyRows.count === 0
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
          model: trashRows
          delegate: Item {
            id: trashWrap
            required property int index
            required property string key
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property string preview
            required property string glyph
            required property string time
            required property int urgency
            width: ListView.view.width
            height: trashCard.implicitHeight
            Yanc.NotificationRow {
              id: trashCard
              width: parent.width
              app: trashWrap.app
              appIcon: trashWrap.appIcon
              summary: trashWrap.summary
              body: trashWrap.body
              image: trashWrap.image
              preview: trashWrap.preview
              glyph: trashWrap.glyph
              time: trashWrap.time
              urgency: trashWrap.urgency
              showBody: !!root.cfg.showBody
              showPreview: !!root.cfg.showPreview
              actionLabel: "Restore"
              danger: false
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "trash" && root.selectedIndex === trashWrap.index
              onRowHovered: root.setRowCursor(trashWrap.index)
              onRowClicked: root.restoreRow({ key: trashWrap.key })
              onActionClicked: root.restoreRow({ key: trashWrap.key })
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.activeTab === "trash" && trashRows.count === 0
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
          model: settingRows
          delegate: Item {
            id: settingWrap
            required property int index
            required property string title
            required property string subtitle
            required property string valueLabel
            required property string kind
            width: ListView.view.width
            height: settingCard.height
            Yanc.SettingRow {
              id: settingCard
              width: parent.width
              title: settingWrap.title
              subtitle: settingWrap.subtitle
              valueLabel: settingWrap.valueLabel
              kind: settingWrap.kind
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "settings" && root.selectedIndex === settingWrap.index
              onRowHovered: root.setRowCursor(settingWrap.index)
              onRowClicked: {
                root.setRowCursor(settingWrap.index)
                root.nudgeSetting(1)
              }
              onDecrementClicked: {
                root.setRowCursor(settingWrap.index)
                root.nudgeSetting(-1)
              }
              onIncrementClicked: {
                root.setRowCursor(settingWrap.index)
                root.nudgeSetting(1)
              }
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.activeTab === "settings" && root.settingsFilter === "apps" && settingRows.count === 0
          text: "No apps in the archive yet"
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
