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

  // Which Omarchy notification engine is running (Model.engineOf): "legacy"
  // (4.0.x, popupModel), "omapager" (4.5, liveEntries/historyEntries), or
  // "auto" when no service turned up (the backend then goes by the files).
  // "" until known; the watcher starts once it is.
  property string engine: ""
  property var engineService: null

  readonly property string dndSettingsPath: {
    var state = Quickshell.env("XDG_STATE_HOME")
    var home = Quickshell.env("HOME")
    var rootDir = state ? state : (home + "/.local/state")
    if (root.engine === "omapager") return rootDir + "/omarchy/notifications/quiet.json"
    return rootDir + "/omarchy/notifications.json"
  }

  readonly property int unread: Model.unreadCount(entries, lastSeen)

  // --- Omarchy 4.5: pictures and actions of live toasts ----------------------
  // history.json keeps no pictures and a sender's actions die with its
  // notification, so both are only there while the toast is. Omapager
  // publishes the live Notification objects as refs (key -> object) and bumps
  // refsRevision the moment one arrives, before it stores the row or lets a
  // silenced one go. Then the picture is drawn once into captureHost (a 0x0
  // clipped item in the bar's window: this service has none), grabbed, and
  // saved as captures/KEY.png once the stored row shows it is not a redacted
  // secret; `backend.sh capture KEY` files it.
  property Item captureHost: null
  readonly property string storeDir: {
    var custom = Quickshell.env("YANC_STORE")
    if (custom) return custom
    var state = Quickshell.env("XDG_STATE_HOME")
    return (state ? state : Quickshell.env("HOME") + "/.local/state") + "/omarchy/yoyo.notification-center"
  }
  property var captureSeen: ({})
  property var captureShots: ({})
  // Bumped when a live row's sender actions may have changed.
  readonly property int liveRevision: root.engineService && root.engineService.refsRevision !== undefined
    ? Number(root.engineService.refsRevision) : 0

  function liveRef(key) {
    var s = root.engineService
    if (root.engine !== "omapager" || !s || !s.refs || !Model.isSafeKey(key)) return null
    return s.refs[key] || null
  }

  // The sender's actions while its toast is up ([] after): { id, text }.
  function liveActions(key, revision) {
    return Model.liveActions(root.liveRef(key))
  }

  // Run a sender action of a live toast (D-Bus ActionInvoked, through
  // Omapager, which then closes the toast). false when it is gone.
  function invokeLive(key, id) {
    var s = root.engineService
    if (!s || typeof s.invokeAction !== "function") return false
    if (!Model.hasLiveAction(root.liveRef(key), String(id))) return false
    s.invokeAction(String(key), String(id))
    return true
  }

  function captureLive() {
    var s = root.engineService
    if (root.engine !== "omapager" || !s || !s.refs) return
    var refs = s.refs
    var live = {}
    for (var key in refs) {
      live[key] = true
      if (root.captureSeen[key]) continue
      root.captureSeen[key] = true
      if ((root.cfg || {}).showPreview === false || !root.captureHost || !Model.isSafeKey(key)) continue
      var ref = refs[key]
      var src = Model.captureSource(ref ? ref.image : "")
      if (!src) continue
      var shot = captureImage.createObject(root.captureHost, { key: key, source: src })
      if (shot) shot.grab()
    }
    for (var old in root.captureSeen)
      if (!live[old]) delete root.captureSeen[old]
  }

  // Save grabbed pictures whose rows are stored; drop redacted ones and any
  // whose row never turned up.
  function fileShots() {
    var s = root.engineService
    var now = Date.now()
    for (var key in root.captureShots) {
      var shot = root.captureShots[key]
      var verdict = s ? Model.captureVerdict(key, s.liveEntries, s.historyEntries) : "drop"
      if (verdict === "wait" && now - shot.at < 120000) continue
      delete root.captureShots[key]
      if (verdict !== "save") continue
      if (!shot.result.saveToFile(root.storeDir + "/captures/" + key + ".png")) {
        console.warn("yoyo.notification-center: could not save the picture of " + key)
        continue
      }
      root.fileCapture(key)
    }
  }

  function fileCapture(key) {
    root.run("capture", root.storeCommand(["capture", key]), function(res) {
      if (!res.ok || !res.data || res.data.key !== key) return
      var next = Model.patchLine(root.entries, JSON.stringify(res.data))
      if (next) { root.entries = next; root.entriesReset() }
    })
  }

  Component {
    id: captureImage
    Image {
      id: shot
      property string key: ""
      property bool grabbing: false
      asynchronous: false
      cache: false
      smooth: true
      fillMode: Image.PreserveAspectFit
      function grab() {
        if (shot.grabbing || shot.status === Image.Loading) return
        shot.grabbing = true
        var size = Model.fitSize(shot.implicitWidth, shot.implicitHeight, 512)
        if (shot.status !== Image.Ready || !size.width) { shot.destroy(); return }
        shot.width = size.width
        shot.height = size.height
        var key = shot.key
        var started = shot.grabToImage(function(result) {
          root.captureShots[key] = { result: result, at: Date.now() }
          shot.destroy()
          Qt.callLater(root.fileShots)
        }, Qt.size(size.width, size.height))
        if (!started) shot.destroy()
      }
      onStatusChanged: if (shot.status !== Image.Loading) shot.grab()
    }
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
  property bool watchSwitch: false

  // (Re)start the backend watcher for the current engine.
  function startWatch() {
    if (!root.engine) return
    if (watchProc.running) {
      root.watchSwitch = true
      watchProc.running = false
      return
    }
    watchProc.running = true
  }

  // Single source of truth: notifications.json via FileView (4.5: the
  // service's quiet.json, plus its doNotDisturb property).
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

  // Auto-hide (autoHideMs > 0): every toast is expired autoHideMs after it
  // appears or last changes (Model.autoHidePlan), critical included — Omarchy
  // never expires those itself. Toasts go through expirePopup, so senders see
  // "expired", not "dismissed by the user". Driven by changes to Omarchy's
  // popupModel, a timer for the next deadline, and a 400 ms poll as backstop.
  property var popupModel: null
  property var toastSeen: ({})

  function scheduleAutoHide() {
    var n = root.notificationService()
    if (root.engine === "omapager" || (n && n.popupModel)) {
      root.noteToasts()
      return
    }
    // No popupModel (older Omarchy): hide everything autoHideMs after the
    // newest notification, through `omarchy-shell notifications dismissAll`.
    var ms = Number(root.cfg.autoHideMs || 0)
    if (ms <= 0) {
      hideTimer.stop()
      return
    }
    hideTimer.interval = ms
    hideTimer.restart()
  }

  function noteToasts() {
    var n = root.notificationService()
    if (root.engine === "omapager") {
      root.noteLive(n)
      return
    }
    var model = n && n.popupModel ? n.popupModel : null
    if (root.popupModel !== model) root.popupModel = model
    var ms = Number(root.cfg.autoHideMs || 0)
    if (!model) {
      if (ms <= 0) hideTimer.stop()
      return
    }
    var keys = []
    for (var i = 0; i < model.count; i++) keys.push(Model.toastKey(model.get(i)))
    var plan = Model.autoHidePlan(ms, keys, root.toastSeen, Date.now())
    root.toastSeen = plan.seen
    if (plan.expire.length > 0) {
      root.expireToasts(n, plan.expire)
      Qt.callLater(root.noteToasts)
    }
    if (plan.next >= 0) {
      hideTimer.interval = Math.max(10, Math.ceil(plan.next))
      hideTimer.restart()
    } else {
      hideTimer.stop()
    }
  }

  // 4.5: the same per-toast plan over liveEntries (key + arrival time), and
  // closeToasts(keys, "expired"). While the deck is held open (pointer or
  // keyboard on it) nothing is closed; the 400 ms poll retries.
  function noteLive(n) {
    var ms = Number(root.cfg.autoHideMs || 0)
    var live = Model.liveToasts(n ? n.liveEntries : [])
    var ids = []
    for (var i = 0; i < live.length; i++) ids.push(live[i].id)
    var plan = Model.autoHidePlan(ms, ids, root.toastSeen, Date.now())
    root.toastSeen = plan.seen
    var held = !!n && typeof n.holding === "function" && n.holding() === true
    if (plan.expire.length > 0 && !held) {
      var keys = []
      for (var j = plan.expire.length - 1; j >= 0; j--) keys.push(live[plan.expire[j]].key)
      root.closeLive(n, keys)
    }
    if (plan.next >= 0) {
      hideTimer.interval = Math.max(10, Math.ceil(plan.next))
      hideTimer.restart()
    } else {
      hideTimer.stop()
    }
  }

  function closeLive(n, keys) {
    if (n && typeof n.closeToasts === "function") {
      n.closeToasts(keys, "expired")
      return
    }
    if (n && typeof n.closeToast === "function") {
      for (var i = 0; i < keys.length; i++) n.closeToast(keys[i], "expired")
      return
    }
    root.run("dismiss-toasts", ["omarchy-shell", "notifications", "dismissAll"])
  }

  function expireToasts(n, indexes) {
    for (var i = 0; i < indexes.length; i++) {
      var idx = indexes[i]
      if (typeof n.expirePopup === "function") n.expirePopup(idx)
      else if (typeof n.dismissPopup === "function") n.dismissPopup(idx)
      else {
        root.run("dismiss-toasts", ["omarchy-shell", "notifications", "dismissAll"])
        return
      }
    }
  }

  Connections {
    target: root.popupModel
    ignoreUnknownSignals: true
    function onCountChanged() { Qt.callLater(root.noteToasts) }
    function onDataChanged() { Qt.callLater(root.noteToasts) }
  }

  Connections {
    target: root.engineService
    ignoreUnknownSignals: true
    function onLiveEntriesChanged() { Qt.callLater(root.noteToasts); Qt.callLater(root.fileShots) }
    function onHistoryEntriesChanged() { Qt.callLater(root.fileShots) }
    // Synchronous on purpose: a silenced toast is let go right after.
    function onRefsRevisionChanged() { root.captureLive() }
    function onDoNotDisturbChanged() {
      if (root.engineService) root.doNotDisturb = root.engineService.doNotDisturb === true
    }
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
    command: root.storeCommand(root.watchArgs)
    running: false
    stdout: SplitParser {
      onRead: function(line) { root.absorb(line) }
    }
    onExited: {
      if (root.watchSwitch) {
        root.watchSwitch = false
        watchProc.running = true
        return
      }
      restartWatch.restart()
    }
  }

  Timer {
    id: restartWatch
    interval: 5000
    onTriggered: if (!watchProc.running && root.engine) watchProc.running = true
  }

  // No notification service after 3 s: let the backend pick by the files.
  Timer {
    id: engineFallback
    interval: 3000
    onTriggered: if (!root.engine) { root.engine = "auto"; root.startWatch() }
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
    onTriggered: {
      var n = root.notificationService()
      if (root.engine === "omapager" || (n && n.popupModel)) root.noteToasts()
      else root.hideAllToasts()
    }
  }

  Timer {
    interval: 400
    running: true
    repeat: true
    onTriggered: {
      root.refreshEngine()
      root.noteToasts()
      for (var k in root.captureShots) { root.fileShots(); break }
    }
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
    root.refreshEngine()
    if (!root.engine) engineFallback.start()
    root.readDnd(dndFile.text())
    loadSettings()
    readSeen()
    load()
  }
}
