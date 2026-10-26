// Omarchy 4.5 live-capture harness: a real Quickshell NotificationServer on a
// private D-Bus plays Omapager (refs/refsRevision, liveEntries/historyEntries
// written to live.json/history.json, invokeAction, Do Not Disturb releasing a
// toast at once, secrets stored as the redacted placeholder) for the real
// Service.qml. Senders are gdbus calls from tests/capture.sh; a summary
// starting with "CTL " is a harness command instead of a toast. Prints
// "NOTIFIED", "ACTIONS", "INVOKE", "CLOSED", "ARCHIVED", "PATCHED". Never
// run against the real daemon: tests/capture.sh starts its own bus.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "nc" as N

ShellRoot {
  id: h
  readonly property string dir: String(Quickshell.env("YANC_SRC_DIR") || "")

  QtObject {
    id: fake
    property var refs: ({})
    property int refsRevision: 0
    property var liveEntries: []
    property var historyEntries: []
    property bool doNotDisturb: false
    function holding() { return false }
    function setDoNotDisturb(v) { doNotDisturb = v === true }
    function put(row) {
      liveEntries = liveEntries.filter(function(r) { return r.key !== row.key }).concat([row])
      liveFile.setText(JSON.stringify(liveEntries) + "\n")
    }
    function release(key, reason) {
      var n = refs[key]
      if (n) { delete refs[key]; refsRevision += 1 }
      var row = null
      liveEntries = liveEntries.filter(function(r) { if (r.key === key) row = r; return r.key !== key })
      if (row) {
        var closed = JSON.parse(JSON.stringify(row))
        closed.closed_ts = Date.now() / 1000
        closed.closed_reason = reason
        historyEntries = [closed].concat(historyEntries)
      }
      liveFile.setText(JSON.stringify(liveEntries) + "\n")
      historyFile.setText(JSON.stringify(historyEntries) + "\n")
      if (n) { console.log("CLOSED " + key + " " + reason); n.dismiss() }
    }
    function closeToast(key, reason) { release(key, reason) }
    function closeToasts(keys, reason) { for (var i = 0; i < keys.length; i++) release(keys[i], reason) }
    // Omapager's own: the sender's action, then the toast closes.
    function invokeAction(key, identifier) {
      var n = refs[key]
      if (n) for (var i = 0; i < n.actions.length; i++)
        if (n.actions[i].identifier === identifier) { console.log("INVOKE " + key + " " + identifier); n.actions[i].invoke() }
      release(key, "activated")
    }
  }

  FileView { id: liveFile; path: h.dir + "/live.json"; printErrors: false }
  FileView { id: historyFile; path: h.dir + "/history.json"; printErrors: false }

  QtObject {
    id: fakeShell
    function firstPartyServiceFor(name) { return name === "omarchy.notifications" ? fake : null }
  }

  N.Service {
    id: svc
    shell: fakeShell
    onEntryAdded: function(e) { console.log("ARCHIVED " + e.key + " image=" + e.image) }
    onEntriesReset: {
      for (var i = 0; i < svc.entries.length; i++)
        if (svc.entries[i].image) console.log("PATCHED " + svc.entries[i].key + " image=" + svc.entries[i].image)
    }
  }

  // The bar's window: the service draws pictures in its 0x0 host.
  FloatingWindow {
    implicitWidth: 40; implicitHeight: 20
    color: "black"
    Item { id: host; width: 0; height: 0; clip: true }
    Component.onCompleted: svc.captureHost = host
  }

  NotificationServer {
    imageSupported: true
    actionsSupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    keepOnReload: false
    onNotification: function(n) {
      var summary = String(n.summary)
      if (summary.indexOf("CTL ") === 0) { h.command(summary.slice(4)); n.tracked = false; return }
      n.tracked = true
      var key = "n" + n.id
      fake.refs[key] = n
      fake.refsRevision += 1
      var secret = /code/i.test(summary)
      fake.put({ key: key, originalId: n.id, senderPid: 0, execArgv: "", execActions: "", glyph: "",
                 app: String(n.appName), appIcon: "", urgency: 1, expireTimeout: 0, duration: 8000,
                 summary: secret ? "Verification notification" : summary, body: secret ? "[redacted]" : String(n.body),
                 rawBody: secret ? "[redacted]" : String(n.body), source: "", groupKey: "app:test", ts: Date.now() / 1000 })
      console.log("NOTIFIED " + key + " " + summary + " image=" + String(n.image).replace(/\/[0-9]+\/[0-9]+$/, "/N"))
      n.closed.connect(function() { if (fake.refs[key]) fake.release(key, "closed") })
      if (fake.doNotDisturb) fake.release(key, "silenced")   // Omapager lets a silenced toast go at once
    }
  }

  function keyOf(summary) {
    for (var i = 0; i < fake.liveEntries.length; i++)
      if (fake.liveEntries[i].summary === summary) return fake.liveEntries[i].key
    for (i = 0; i < fake.historyEntries.length; i++)
      if (fake.historyEntries[i].summary === summary) return fake.historyEntries[i].key
    return ""
  }

  function command(c) {
    var p = c.split(" ")
    if (p[0] === "dnd") fake.doNotDisturb = p[1] === "on"
    else if (p[0] === "previews") svc.setSetting("showPreview", p[1] === "on")
    else if (p[0] === "actions") {
      var k = keyOf(p[1])
      console.log("ACTIONS " + p[1] + " " + JSON.stringify(svc.liveActions(k, svc.liveRevision)))
    } else if (p[0] === "invoke") {
      var key = keyOf(p[1])
      console.log("INVOKED " + p[1] + " " + p[2] + " " + svc.invokeLive(key, p[2]))
    } else if (p[0] === "expire") fake.release(keyOf(p[1]), "expired")
    else if (p[0] === "end") { console.log("END"); Qt.quit() }
  }

  Timer { interval: 1500; running: true; onTriggered: console.log("READY engine=" + svc.engine + " host=" + (svc.captureHost === host)) }
}
