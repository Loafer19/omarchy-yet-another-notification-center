// Live auto-hide harness: the real Service.qml against a fake Omarchy
// notification service (popupModel + expirePopup/dismissPopup). Events come
// from AH_EVENTS ("ms:verb:arg[:arg]" separated by ";"); every toast that
// leaves is printed as "HIDE <id> <ms> <expire|dismiss>". Run by
// tests/autohide.sh, never against the real notification daemon.
import QtQuick
import Quickshell
import "nc" as N

ShellRoot {
  id: h
  property double t0: 0
  property var events: []
  property int next: 0
  property int seq: 0

  function now() { return Math.round(Date.now() - h.t0) }
  function find(id) {
    for (var i = 0; i < fake.popupModel.count; i++)
      if (fake.popupModel.get(i).tid === id) return i
    return -1
  }
  function row(id, summary, urgency) {
    h.seq++
    return { tid: id, originalId: h.seq, timestamp: Date.now(), app: "Test", summary: summary,
             body: "", image: "", urgency: urgency, expireTimeout: 0 }
  }

  QtObject {
    id: fake
    property ListModel popupModel: ListModel {}
    function leave(i, how) {
      if (i < 0 || i >= popupModel.count) return
      console.log("HIDE " + popupModel.get(i).tid + " " + h.now() + " " + how)
      popupModel.remove(i)
    }
    function expirePopup(i) { leave(i, "expire") }
    function dismissPopup(i) { leave(i, "dismiss") }
    function clearPopups() { while (popupModel.count > 0) dismissPopup(0) }
    function setDoNotDisturb(v) {}
  }

  QtObject {
    id: fakeShell
    function serviceFor(name) { return name === "omarchy.notifications" ? fake : null }
  }

  N.Service { id: svc; shell: fakeShell }

  function step() {
    var t = h.now()
    while (h.next < h.events.length && h.events[h.next].t <= t) {
      var e = h.events[h.next++]
      var i
      if (e.verb === "add") fake.popupModel.insert(0, row(e.a, e.a, Number(e.b || 1)))
      else if (e.verb === "edit") { i = find(e.a); if (i >= 0) fake.popupModel.setProperty(i, "summary", e.b || "edited") }
      else if (e.verb === "replace") {
        // Omarchy: removePopupsByOriginalId + insert(0) in one callLater.
        i = find(e.a); if (i >= 0) fake.popupModel.remove(i)
        fake.popupModel.insert(0, row(e.a, e.b || "replaced", 1))
      }
      else if (e.verb === "gone") { i = find(e.a); if (i >= 0) fake.popupModel.remove(i) }  // Omarchy's own expiry
      else if (e.verb === "set") svc.setSetting("autoHideMs", Number(e.a))
      else if (e.verb === "end") {
        var left = []
        for (i = 0; i < fake.popupModel.count; i++) left.push(fake.popupModel.get(i).tid)
        console.log("END " + t + " left=" + left.join(","))
        Qt.quit()
      }
    }
  }

  Timer { id: ticker; interval: 5; repeat: true; onTriggered: h.step() }

  Timer {
    // Give the service time to read settings.json, then start the clock.
    interval: 1500; running: true
    onTriggered: {
      console.log("CFG autoHideMs=" + svc.cfg.autoHideMs)
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
