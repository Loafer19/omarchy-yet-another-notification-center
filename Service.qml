import QtQuick
import Quickshell
import Quickshell.Io

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

  function storeCommand(args) {
    return ["bash", root.script].concat(args)
  }

  function notificationService() {
    var id = "omarchy.notifications"
    if (pluginRegistry && typeof pluginRegistry.resolveEnabledId === "function")
      id = pluginRegistry.resolveEnabledId(id)
    if (!shell) return null
    if (typeof shell.serviceFor === "function") return shell.serviceFor(id)
    if (typeof shell.firstPartyServiceFor === "function") return shell.firstPartyServiceFor(id)
    return null
  }

  function load() {
    if (!listProc.running) {
      listProc.command = root.storeCommand(["list", String(root.cfg.displayLimit || 50)])
      listProc.running = true
    }
    if (!trashProc.running) {
      trashProc.command = root.storeCommand(["trash-list", "200"])
      trashProc.running = true
    }
    if (!appsProc.running) {
      appsProc.command = root.storeCommand(["apps"])
      appsProc.running = true
    }
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
    Quickshell.execDetached(root.storeCommand(["seen", String(stamp)]))
  }

  function setSetting(key, value) {
    var patch = {}
    patch[key] = value
    var next = {}
    for (var k in root.cfg) next[k] = root.cfg[k]
    next[key] = value
    root.cfg = next
    root.settingsChanged()
    Quickshell.execDetached(root.storeCommand(["settings-set", JSON.stringify(patch)]))
    if (key === "keepDays" || key === "maxItems" || key === "displayLimit" || key === "trashDays")
      Qt.callLater(root.load)
  }

  function setAppSound(app, sound) {
    var sounds = {}
    var current = root.cfg.appSounds || {}
    for (var k in current) sounds[k] = current[k]
    if (!sound || sound === "inherit") delete sounds[app]
    else sounds[app] = sound
    root.setSetting("appSounds", sounds)
  }

  function dismiss(key) {
    if (!key) return
    var next = []
    for (var i = 0; i < entries.length; i++)
      if (entries[i].key !== key) next.push(entries[i])
    entries = next
    entriesReset()
    Quickshell.execDetached(root.storeCommand(["dismiss", String(key)]))
    reloadSoon.restart()
  }

  function restore(key) {
    if (!key) return
    Quickshell.execDetached(root.storeCommand(["restore", String(key)]))
    reloadSoon.restart()
  }

  function purge(key) {
    if (!key) return
    Quickshell.execDetached(root.storeCommand(["purge", String(key)]))
    reloadSoon.restart()
  }

  function clearAll() {
    entries = []
    entriesReset()
    Quickshell.execDetached(root.storeCommand(["clear"]))
    reloadSoon.restart()
  }

  function emptyTrash() {
    trashEntries = []
    trashReset()
    Quickshell.execDetached(root.storeCommand(["empty-trash"]))
  }

  function playSound(id) {
    if (!id || id === "mute") return
    Quickshell.execDetached(root.storeCommand(["play-sound", String(id)]))
  }

  function absorb(line) {
    var entry
    try { entry = JSON.parse(line) } catch (e) { return }
    if (!entry || !entry.key) return
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
    if (!cfg.soundEnabled) return
    var n = root.notificationService()
    if (cfg.muteSoundWhenDnd && n && n.doNotDisturb) return
    var app = String(entry.app || "")
    var id = (cfg.appSounds && cfg.appSounds[app]) ? cfg.appSounds[app] : ""
    if (!id) id = Number(entry.urgency || 0) >= 3 ? "warning" : (cfg.defaultSound || "message")
    root.playSound(id)
  }

  function hideAllToasts() {
    var n = root.notificationService()
    if (!n) return
    if (typeof n.clearPopups === "function") {
      n.clearPopups()
      return
    }
    if (n.popupModel) {
      while (n.popupModel.count > 0 && typeof n.dismissPopup === "function")
        n.dismissPopup(0)
    }
  }

  property int lastPopupCount: 0

  function noteToasts() {
    var n = root.notificationService()
    var count = n && n.popupModel ? n.popupModel.count : 0
    var ms = Number(root.cfg.autoHideMs || 0)
    if (count === 0 || ms <= 0) {
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
    interval: 30000
    onTriggered: if (!watchProc.running) watchProc.running = true
  }

  Timer {
    id: reloadSoon
    interval: 400
    onTriggered: root.load()
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
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        if (!Array.isArray(data)) return
        root.loaded = true
        root.entries = data
        root.entriesReset()
      }
    }
  }

  Process {
    id: trashProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        if (!Array.isArray(data)) return
        root.trashEntries = data
        root.trashReset()
      }
    }
  }

  Process {
    id: appsProc
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
        root.cfg = data
        root.settingsChanged()
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
    loadSettings()
    readSeen()
    load()
  }
}
