import QtQuick
import Quickshell
import "Model.js" as Model
import "service"

Item {
  id: root
  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property string omarchyPath: ""

  property alias cfg: settingsSync.cfg
  property var entries: []
  property var trashEntries: []
  property var apps: []
  property double lastSeen: 0
  property bool loaded: false
  property bool doNotDisturb: false

  // Which Omarchy notification engine is running (Model.engineOf): "legacy"
  // (4.0.x, popupModel), "omapager" (4.5, liveEntries/historyEntries), or
  // "auto" when no service turned up (the backend then goes by the files).
  // "" until known; the watcher starts once it is.
  property string engine: ""
  property var engineService: null

  readonly property alias dndSettingsPath: dndFile.path
  readonly property int unread: Model.unreadCount(entries, lastSeen)

  // --- Omarchy 4.5: pictures and actions of live toasts (LiveToasts) --------
  property Item captureHost: null
  readonly property string storeDir: {
    var custom = Quickshell.env("YANC_STORE")
    if (custom) return custom
    var state = Quickshell.env("XDG_STATE_HOME")
    return (state ? state : Quickshell.env("HOME") + "/.local/state") + "/omarchy/yoyo.notification-center"
  }
  // Bumped when a live row's sender actions may have changed.
  readonly property int liveRevision: root.engineService && root.engineService.refsRevision !== undefined
    ? Number(root.engineService.refsRevision) : 0

  // The sender's actions while its toast is up ([] after): { id, text }.
  // revision (liveRevision) only makes bindings re-evaluate.
  function liveActions(key, revision) { return Model.liveActions(liveToasts.liveRef(key)) }
  // Run one (Omapager then closes the toast); false when it is gone.
  function invokeLive(key, id) { return liveToasts.invoke(key, id) }

  function fileCapture(key) {
    root.run("capture", root.storeCommand(["capture", key]), function(res) {
      if (!res.ok || !res.data || res.data.key !== key) return
      var next = Model.patchLine(root.entries, JSON.stringify(res.data))
      if (next) { root.entries = next; root.entriesReset() }
    })
  }

  LiveToasts {
    id: liveToasts
    engineService: root.engineService
    active: root.engine === "omapager"
    pictures: (root.cfg || {}).showPreview !== false
    host: root.captureHost
    storeDir: root.storeDir
    onFiled: function(key) { root.fileCapture(key) }
  }

  readonly property string script:
    Qt.resolvedUrl("scripts/backend.sh").toString().replace(/^file:\/\//, "")

  signal entryAdded(var entry)
  signal entriesReset()
  signal trashReset()
  signal settingsChanged()
  // A store/helper call failed. message is user-facing ("Couldn't …: why").
  signal actionFailed(string action, string message)
  readonly property alias lastError: runner.lastError
  property string loadError: ""

  // Run one checked command (ActionRunner): failures are logged and raised
  // through actionFailed; done(res) always runs with { ok, error, data }.
  function run(action, command, done) { runner.run(action, command, done) }
  function reportFailure(action, error) { runner.reportFailure(action, error) }

  ActionRunner {
    id: runner
    onFailed: function(action, message) { root.actionFailed(action, message) }
  }

  // A list read that does not return an array is an error, not "empty".
  // Reported once per distinct message so the 15 s poll does not spam.
  function noteLoad(text) {
    var data = null
    try { data = JSON.parse(text) } catch (e) {}
    if (Array.isArray(data)) {
      root.loadError = ""
      return data
    }
    var why = data && data.error ? String(data.error) : (Model.lastLine(text) || "no output")
    if (root.loadError !== why) {
      root.loadError = why
      root.reportFailure("load", why)
    }
    return null
  }

  function storeCommand(args) {
    return ["bash", root.script].concat(args)
  }

  function notificationService() {
    if (!shell) return null
    var n = null
    if (typeof shell.firstPartyServiceFor === "function")
      n = shell.firstPartyServiceFor("omarchy.notifications")
    if (!n && typeof shell.serviceFor === "function")
      n = shell.serviceFor("omarchy.notifications")
    return n
  }

  function refreshEngine() {
    var n = root.notificationService()
    var found = Model.engineOf(n)
    if (found === "omapager") {
      if (root.engineService !== n) root.engineService = n
      if (n.doNotDisturb !== undefined && root.doNotDisturb !== (n.doNotDisturb === true))
        root.doNotDisturb = n.doNotDisturb === true
    }
    if (!found || found === root.engine || root.engine === "omapager") return
    root.engine = found
    root.startWatch()
  }

  readonly property var watchArgs: root.engine === "legacy" || root.engine === ""
    ? ["watch"] : ["watch", root.engine]

  // (Re)start the backend watcher for the current engine.
  function startWatch() { watcher.restart() }

  Watcher {
    id: watcher
    command: root.storeCommand(root.watchArgs)
    ready: root.engine !== ""
    onLine: function(text) { root.absorb(text) }
  }

  // Do Not Disturb: Omarchy's file (DndFile), and on 4.5 also the service's
  // doNotDisturb property.
  DndFile {
    id: dndFile
    engine: root.engine
    onStored: function(on) { root.doNotDisturb = on }
  }

  function setDnd(on) {
    var want = on === true
    if (root.doNotDisturb === want) return
    root.doNotDisturb = want
    var n = root.notificationService()
    if (n && typeof n.setDoNotDisturb === "function") {
      n.setDoNotDisturb(want)
      return
    }
    root.run("dnd", ["omarchy-shell", "notifications", "setDnd", want ? "on" : "off"], function(res) {
      // Roll back; the FileView re-syncs from notifications.json anyway.
      if (!res.ok) dndFile.read()
      if (!res.ok && root.doNotDisturb === want) root.doNotDisturb = !want
    })
  }

  function toggleDnd() {
    root.setDnd(!root.doNotDisturb)
  }

  function load() {
    root.startList()
    root.startTrash()
    root.startApps()
  }

  function startList() {
    listProc.start(root.storeCommand(["list", String(Model.clampNamed("displayLimit", root.cfg.displayLimit))]))
  }

  function startTrash() { trashProc.start(root.storeCommand(["trash-list", "200"])) }
  function startApps() { appsProc.start(root.storeCommand(["apps"])) }

  function loadSettings() { settingsSync.load() }
  function setSetting(key, value) { settingsSync.set(key, value) }
  function setAppSound(app, sound) { settingsSync.setAppSound(app, sound) }

  SettingsSync {
    id: settingsSync
    command: root.storeCommand
    run: root.run
    onChanged: root.settingsChanged()
    onAutoHideChanged: root.scheduleAutoHide()
    onLimitsSaved: root.run("prune", root.storeCommand(["prune"]), function() { root.load() })
  }
  function readSeen() { seenProc.start(root.storeCommand(["seen"])) }

  function markSeen() {
    var stamp = Date.now()
    root.lastSeen = stamp
    root.run("seen", root.storeCommand(["seen", String(stamp)]))
  }

  function dismiss(key) {
    if (!Model.isSafeKey(key)) return
    var next = []
    for (var i = 0; i < entries.length; i++)
      if (entries[i].key !== key) next.push(entries[i])
    entries = next
    entriesReset()
    // Reload either way: on failure that brings the row back.
    root.run("dismiss", root.storeCommand(["dismiss", String(key)]), function() { root.load() })
  }

  function restore(key) {
    if (!Model.isSafeKey(key)) return
    root.run("restore", root.storeCommand(["restore", String(key)]), function() { root.load() })
  }

  function purge(key) {
    if (!Model.isSafeKey(key)) return
    root.run("purge", root.storeCommand(["purge", String(key)]), function() { root.load() })
  }

  function clearAll() {
    // Optimistic clear of History; backend moves rows into Trash, so the
    // follow-up reload refreshes both lists (and undoes the optimistic clear
    // if the store refused).
    entries = []
    entriesReset()
    root.run("clear", root.storeCommand(["clear"]), function() { root.load() })
  }

  function emptyTrash() {
    trashEntries = []
    trashReset()
    root.run("empty-trash", root.storeCommand(["empty-trash"]), function() { root.load() })
  }

  function playSound(id) {
    var sound = Model.canonicalSound(id)
    if (!sound || sound === "mute" || sound === "inherit") return
    root.run("play-sound", root.storeCommand(["play-sound", sound]))
  }

  function absorb(line) {
    var res = Model.absorbLine(entries, line, root.cfg.displayLimit)
    if (!res) return
    entries = res.entries
    entryAdded(res.entry)
    maybePlay(res.entry)
    root.scheduleAutoHide()
  }

  function maybePlay(entry) {
    var cfg = root.cfg || {}
    if (cfg.soundEnabled === false) return
    if (cfg.muteSoundWhenDnd !== false && root.doNotDisturb) return
    root.playSound(Model.soundFor(entry, cfg))
  }

  function hideAllToasts() { autoHide.hideAll() }
  function scheduleAutoHide() { autoHide.schedule() }
  function noteToasts() { autoHide.note() }

  AutoHide {
    id: autoHide
    engine: root.engine
    autoHideMs: Number(root.cfg.autoHideMs || 0)
    lookup: root.notificationService
    onDismissAll: root.run("dismiss-toasts", ["omarchy-shell", "notifications", "dismissAll"])
  }

  Connections {
    target: root.engineService
    ignoreUnknownSignals: true
    function onLiveEntriesChanged() { Qt.callLater(root.noteToasts); Qt.callLater(liveToasts.fileShots) }
    function onHistoryEntriesChanged() { Qt.callLater(liveToasts.fileShots) }
    // Synchronous on purpose: a silenced toast is let go right after.
    function onRefsRevisionChanged() { liveToasts.captureLive() }
    function onDoNotDisturbChanged() {
      if (root.engineService) root.doNotDisturb = root.engineService.doNotDisturb === true
    }
  }

  // No notification service after 3 s: let the backend pick by the files.
  Timer {
    id: engineFallback
    interval: 3000
    onTriggered: if (!root.engine) { root.engine = "auto"; root.startWatch() }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.load()
  }

  Timer {
    interval: 400
    running: true
    repeat: true
    onTriggered: {
      root.refreshEngine()
      root.noteToasts()
      if (liveToasts.hasShots()) liveToasts.fileShots()
    }
  }

  ListReader {
    id: listProc
    onRerun: root.startList()
    onOutput: function(text) {
      var data = root.noteLoad(text)
      if (!data) return
      root.loaded = true
      root.entries = data
      root.entriesReset()
    }
  }

  ListReader {
    id: trashProc
    onRerun: root.startTrash()
    onOutput: function(text) {
      var data = root.noteLoad(text)
      if (!data) return
      root.trashEntries = data
      root.trashReset()
    }
  }

  ListReader {
    id: appsProc
    onRerun: root.startApps()
    onOutput: function(text) {
      var data
      try { data = JSON.parse(text) } catch (e) { return }
      if (Array.isArray(data)) root.apps = data
    }
  }

  ListReader {
    id: seenProc
    queue: false
    onOutput: function(text) {
      try {
        var data = JSON.parse(text)
        if (data.ok === true) root.lastSeen = Number(data.seen) || 0
      } catch (e) {}
    }
  }

  Component.onCompleted: {
    root.refreshEngine()
    if (!root.engine) engineFallback.start()
    dndFile.read()
    loadSettings()
    readSeen()
    load()
  }
}
