// Omarchy 4.5 harness: the real Service.qml against a fake Omapager service
// (liveEntries/historyEntries, closeToasts, holding, doNotDisturb). The fake
// writes live.json/history.json the way Omarchy does, so the real backend
// watcher archives from them. Events come from AH_EVENTS ("ms:verb:arg[:arg]"
// separated by ";"); prints "HIDE <key> <ms> <reason>" for every toast the
// plugin closes (USERCLOSE for the user's own), "ARCHIVED <key> <ms>",
// "DND ...". Run by tests/omapager.sh, never against the real daemon.
import QtQuick
import Quickshell
import Quickshell.Io
import "nc" as N

ShellRoot {
  id: h
  property double t0: 0
  property var events: []
  property int next: 0
  property bool held: false
  readonly property string dir: String(Quickshell.env("YANC_SRC_DIR") || "")

  function now() { return Math.round(Date.now() - h.t0) }

  QtObject {
    id: fake
    property var liveEntries: []
    property var historyEntries: []
    property bool doNotDisturb: false
    function setDoNotDisturb(v) {
      console.log("SETDND " + (v === true) + " " + h.now())
      doNotDisturb = v === true
    }
    function holding() { return h.held }
    function put(row) {
      var out = [], replaced = false
      for (var i = 0; i < liveEntries.length; i++) {
        if (liveEntries[i].key === row.key) { out.push(row); replaced = true }
        else out.push(liveEntries[i])
      }
      if (!replaced) out.push(row)
      liveEntries = out
      liveFile.setText(JSON.stringify(liveEntries) + "\n")
    }
    function closeToasts(keys, reason) {
      for (var i = 0; i < keys.length; i++) closeToast(keys[i], reason)
    }
    function closeToast(key, reason) { leave(key, reason, "HIDE") }
    function leave(key, reason, tag) {
      var row = null, rest = []
      for (var i = 0; i < liveEntries.length; i++) {
        if (liveEntries[i].key === key) row = liveEntries[i]
        else rest.push(liveEntries[i])
      }
      if (!row) return
      console.log(tag + " " + key + " " + h.now() + " " + reason)
      liveEntries = rest
      var closed = JSON.parse(JSON.stringify(row))
      closed.closed_ts = Date.now() / 1000
      closed.closed_reason = reason
      historyEntries = [closed].concat(historyEntries)
      liveFile.setText(JSON.stringify(liveEntries) + "\n")
      historyFile.setText(JSON.stringify(historyEntries) + "\n")
    }
  }

  FileView { id: liveFile; path: h.dir + "/live.json"; printErrors: false }
  FileView { id: historyFile; path: h.dir + "/history.json"; printErrors: false }

  QtObject {
    id: fakeShell
    function firstPartyServiceFor(name) { return name === "omarchy.notifications" ? fake : null }
  }

  N.Service { id: svc; shell: fakeShell; onEntryAdded: function(e) { console.log("ARCHIVED " + e.key + " " + h.now()) } }

  function row(key, summary, urgency) {
    return { key: key, originalId: 1, senderPid: 0, execArgv: "", execActions: "", glyph: "", app: "Test",
             appIcon: "", summary: summary, body: "", rawBody: "", source: "Test", groupKey: "app:test",
             urgency: urgency, expireTimeout: 0, duration: urgency === 2 ? 0 : 8000, ts: Date.now() / 1000 }
  }

  function step() {
    var t = h.now()
    while (h.next < h.events.length && h.events[h.next].t <= t) {
      var e = h.events[h.next++]
      if (e.verb === "add") fake.put(row(e.a, e.a, Number(e.b || 1)))
      else if (e.verb === "update") fake.put(row(e.a, e.b || "updated", 1))   // replaces_id: same key, new ts
      else if (e.verb === "gone") fake.leave(e.a, "dismissed", "USERCLOSE")  // the user closed it
      else if (e.verb === "hold") h.held = true
      else if (e.verb === "release") h.held = false
      else if (e.verb === "set") svc.setSetting("autoHideMs", Number(e.a))
      else if (e.verb === "dnd") fake.doNotDisturb = e.a === "on"            // toggled elsewhere
      else if (e.verb === "setdnd") svc.setDnd(e.a === "on")                 // toggled in the panel
      else if (e.verb === "probe") console.log("DND svc=" + svc.doNotDisturb + " fake=" + fake.doNotDisturb + " " + t)
      else if (e.verb === "end") {
        var left = []
        for (var i = 0; i < fake.liveEntries.length; i++) left.push(fake.liveEntries[i].key)
        console.log("END " + t + " left=" + left.join(","))
        Qt.quit()
      }
    }
  }

  Timer { id: ticker; interval: 5; repeat: true; onTriggered: h.step() }

  Timer {
    interval: 1500; running: true
    onTriggered: {
      console.log("CFG autoHideMs=" + svc.cfg.autoHideMs)
      console.log("ENGINE " + svc.engine + " args=" + svc.watchArgs.join(","))
      var spec = String(Quickshell.env("AH_EVENTS") || "")
      h.events = spec.split(";").filter(function(s) { return s.length > 0 }).map(function(s) {
        var p = s.split(":")
        return { t: Number(p[0]), verb: p[1], a: p[2], b: p[3] }
      })
      h.t0 = Date.now()
      ticker.start()
    }
  }
}
