import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

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

  property var cfg: ({})
  property var entries: []
  property var trashEntries: []
  property var apps: []
  property double lastSeen: 0
  property bool loaded: false
  property bool doNotDisturb: false

  readonly property string dndSettingsPath: {
    var state = Quickshell.env("XDG_STATE_HOME")
    var home = Quickshell.env("HOME")
    var rootDir = state ? state : (home + "/.local/state")
    return rootDir + "/omarchy/notifications.json"
  }

  readonly property int unread: {
    var count = 0
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].timestamp > lastSeen) count++
      else break
    }
    return count
  }

  readonly property string script:
    Qt.resolvedUrl("scripts/backend.sh").toString().replace(/^file:\/\//, "")

  signal entryAdded(var entry)
  signal entriesReset()
  signal trashReset()
  signal settingsChanged()
  // A store/helper call failed. message is user-facing ("Couldn't …: why").
  signal actionFailed(string action, string message)
  property string lastError: ""
  property string loadError: ""
  property int settingsSeq: 0

  // Run one command and check it: exit code and {"ok":false} both count as
  // failure. Failures are logged and raised through actionFailed; done(res)
  // always runs with { ok, error, data } so callers can roll back.
  function run(action, command, done) {
    var p = actionProcess.createObject(root, { action: action, done: done || null })
    if (!p) {
      root.reportFailure(action, "could not start")
      if (typeof done === "function") done({ ok: false, error: "could not start", data: null })
      return
    }
    p.command = command
    p.running = true
  }

  function finishAction(p, exitCode, stdout, stderr) {
    var res = Model.actionResult(exitCode, stdout, stderr)
    if (!res.ok) root.reportFailure(p.action, res.error)
    if (typeof p.done === "function") {
      try { p.done(res) } catch (e) { console.warn("yoyo.notification-center: " + p.action + " callback: " + e) }
    }
    p.destroy()
  }

  function reportFailure(action, error) {
    var msg = Model.actionMessage(action, error)
    root.lastError = msg
    console.warn("yoyo.notification-center: " + msg)
    root.actionFailed(action, msg)
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

  // Single source of truth: notifications.json via FileView.
  // Polling `dndState` raced the file (CLI lagged behind JSON) and made the
  // bell/toggle flicker — that is why the old local setDnd/hydrate existed.
  function readDnd(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      if (data && typeof data.dnd === "boolean")
        root.doNotDisturb = data.dnd
    } catch (e) {}
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
      if (!res.ok) root.readDnd(dndFile.text())
      if (!res.ok && root.doNotDisturb === want) root.doNotDisturb = !want
    })
  }

  function toggleDnd() {
    root.setDnd(!root.doNotDisturb)
  }

  // A read that is already running may have started before the last write;
  // queue one more so the lists never settle on pre-action data.
  property bool listAgain: false
  property bool trashAgain: false
  property bool appsAgain: false

  function load() {
    root.startList()
    root.startTrash()
    root.startApps()
  }

  function startList() {
    if (listProc.running) { root.listAgain = true; return }
    listProc.command = root.storeCommand(["list", String(Model.clampNamed("displayLimit", root.cfg.displayLimit))])
    listProc.running = true
  }

  function startTrash() {
    if (trashProc.running) { root.trashAgain = true; return }
    trashProc.command = root.storeCommand(["trash-list", "200"])
    trashProc.running = true
  }

  function startApps() {
    if (appsProc.running) { root.appsAgain = true; return }
    appsProc.command = root.storeCommand(["apps"])
    appsProc.running = true
  }

  function loadSettings() {
    if (settingsProc.running) return
    settingsProc.command = root.storeCommand(["settings-get"])
    settingsProc.running = true
  }

  function readSeen() {
    if (seenProc.running) return
    seenProc.command = root.storeCommand(["seen"])
    seenProc.running = true
  }

  function markSeen() {
    var stamp = Date.now()
    root.lastSeen = stamp
    root.run("seen", root.storeCommand(["seen", String(stamp)]))
  }

  function setSetting(key, value) {
    if (Model.DEFAULTS[key] === undefined) return
    var patch = {}
    patch[key] = value
    var next = {}
    for (var k in root.cfg) next[k] = root.cfg[k]
    next[key] = value
    root.cfg = next
    root.settingsChanged()
    if (key === "autoHideMs") Qt.callLater(root.scheduleAutoHide)
    var limits = key === "keepDays" || key === "maxItems" || key === "displayLimit" || key === "trashDays"
    var seq = ++root.settingsSeq
    root.run("settings-set", root.storeCommand(["settings-set", JSON.stringify(patch)]), function(res) {
      if (seq !== root.settingsSeq) return   // a newer change is in flight
      if (!res.ok) {
        // Not saved: show what the store really has.
        root.loadSettings()
        return
      }
      // The store clamps and validates; adopt what it saved.
      if (res.data && typeof res.data === "object" && !Array.isArray(res.data)) {
        root.cfg = Model.mergeSettings(res.data)
        root.settingsChanged()
        if (key === "autoHideMs") root.scheduleAutoHide()
      }
      // displayLimit trims History into Trash — prune after the new limit is
      // saved, then reload, so the list matches the new ceiling.
      if (limits) root.run("prune", root.storeCommand(["prune"]), function() { root.load() })
    })
  }

  function setAppSound(app, sound) {
    if (!Model.isSafeAppName(app)) return
    var sounds = {}
    var current = root.cfg.appSounds || {}
    for (var k in current) sounds[k] = current[k]
    if (!sound || sound === "inherit") delete sounds[app]
    else sounds[app] = sound
    root.setSetting("appSounds", sounds)
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
    var entry
    try { entry = JSON.parse(line) } catch (e) { return }
    if (!entry || !Model.isSafeKey(entry.key)) return
    for (var i = 0; i < entries.length; i++)
      if (entries[i].key === entry.key) return
    var next = [entry].concat(entries)
    var limit = Number(root.cfg.displayLimit || 50)
    if (next.length > limit) next = next.slice(0, limit)
    entries = next
    entryAdded(entry)
    maybePlay(entry)
  }

  function maybePlay(entry) {
    var cfg = root.cfg || {}
    if (cfg.soundEnabled === false) return
    if (cfg.muteSoundWhenDnd !== false && root.doNotDisturb) return
    root.playSound(Model.soundFor(entry, cfg))
    root.scheduleAutoHide()
  }

  function hideAllToasts() {
    var n = root.notificationService()
    if (n && typeof n.clearPopups === "function") {
      n.clearPopups()
      return
    }
    if (n && n.popupModel && typeof n.dismissPopup === "function") {
      var guard = 0
      while (n.popupModel.count > 0 && guard < 32) {
        n.dismissPopup(0)
        guard++
      }
      if (guard > 0) return
    }
    root.run("dismiss-toasts", ["omarchy-shell", "notifications", "dismissAll"])
  }

  function scheduleAutoHide() {
    var ms = Number(root.cfg.autoHideMs || 0)
    if (ms <= 0) {
      hideTimer.stop()
      return
    }
    hideTimer.interval = ms
    hideTimer.restart()
  }

  property int lastPopupCount: 0

  function noteToasts() {
    var n = root.notificationService()
    var hasModel = !!(n && n.popupModel)
    var count = hasModel ? n.popupModel.count : 0
    var ms = Number(root.cfg.autoHideMs || 0)
    if (ms <= 0) {
      hideTimer.stop()
      root.lastPopupCount = count
      return
    }
    if (!hasModel) return
    if (count === 0) {
      hideTimer.stop()
    } else if (count > root.lastPopupCount) {
      hideTimer.interval = ms
      hideTimer.restart()
    } else if (!hideTimer.running) {
      hideTimer.interval = ms
      hideTimer.start()
    }
    root.lastPopupCount = count
  }

  FileView {
    id: dndFile
    path: root.dndSettingsPath
    watchChanges: true
    printErrors: false
    preload: true
    onLoaded: root.readDnd(text())
    onFileChanged: reload()
  }

  Process {
    id: watchProc
    command: root.storeCommand(["watch"])
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.absorb(line) }
    }
    onExited: restartWatch.restart()
  }

  Timer {
    id: restartWatch
    interval: 5000
    onTriggered: if (!watchProc.running) watchProc.running = true
  }

  // One checked call (see run()). Finishes once the process has exited and
  // both streams are drained; a process that never starts is finished by the
  // grace timer so callers are never left waiting.
  Component {
    id: actionProcess
    Process {
      id: proc
      property string action: ""
      property var done: null
      property bool exited: false
      property int code: -1
      property bool outDone: false
      property bool errDone: false
      property bool finished: false
      function maybeFinish(force) {
        if (proc.finished) return
        if (!force && !(proc.exited && proc.outDone && proc.errDone)) return
        proc.finished = true
        root.finishAction(proc, proc.exited ? proc.code : NaN, outText.text, errText.text)
      }
      stdout: StdioCollector { id: outText; onStreamFinished: { proc.outDone = true; proc.maybeFinish(false) } }
      stderr: StdioCollector { id: errText; onStreamFinished: { proc.errDone = true; proc.maybeFinish(false) } }
      onExited: function(exitCode) { proc.exited = true; proc.code = exitCode; proc.maybeFinish(false) }
      onRunningChanged: if (!running) grace.start()
      property Timer grace: Timer { interval: 1500; onTriggered: proc.maybeFinish(true) }
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.load()
  }

  Timer {
    id: hideTimer
    repeat: false
    onTriggered: root.hideAllToasts()
  }

  Timer {
    interval: 400
    running: true
    repeat: true
    onTriggered: root.noteToasts()
  }

  Process {
    id: listProc
    onRunningChanged: if (!running && root.listAgain) { root.listAgain = false; Qt.callLater(root.startList) }
    stdout: StdioCollector {
      onStreamFinished: {
        var data = root.noteLoad(text)
        if (!data) return
        root.loaded = true
        root.entries = data
        root.entriesReset()
      }
    }
  }

  Process {
    id: trashProc
    onRunningChanged: if (!running && root.trashAgain) { root.trashAgain = false; Qt.callLater(root.startTrash) }
    stdout: StdioCollector {
      onStreamFinished: {
        var data = root.noteLoad(text)
        if (!data) return
        root.trashEntries = data
        root.trashReset()
      }
    }
  }

  Process {
    id: appsProc
    onRunningChanged: if (!running && root.appsAgain) { root.appsAgain = false; Qt.callLater(root.startApps) }
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        if (Array.isArray(data)) root.apps = data
      }
    }
  }

  Process {
    id: settingsProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        if (!data || typeof data !== "object") return
        root.cfg = Model.mergeSettings(data)
        root.settingsChanged()
        root.scheduleAutoHide()
      }
    }
  }

  Process {
    id: seenProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data.ok === true) root.lastSeen = Number(data.seen) || 0
        } catch (e) {}
      }
    }
  }

  Component.onCompleted: {
    root.readDnd(dndFile.text())
    loadSettings()
    readSeen()
    load()
  }
}
