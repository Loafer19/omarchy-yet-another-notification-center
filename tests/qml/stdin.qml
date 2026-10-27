// Copy via stdin harness: the real components/RowOpener.qml and
// service/ActionRunner.qml, with a stub wl-copy first on PATH (tests/stdin.sh).
// Prints "RES <case> <ok> <error>" per call, then "END".
import QtQuick
import Quickshell
import "nc/service" as S
import "nc/components" as C

ShellRoot {
  id: h
  property var queue: []

  S.ActionRunner { id: runner }

  // Stands in for Service.qml, whose run() only forwards to ActionRunner.
  QtObject {
    id: store
    function run(action, command, done, input) { runner.run(action, command, done, input) }
  }

  C.RowOpener { id: opener; store: store }

  function result(name) {
    return function(ok, error) {
      console.log("RES " + name + " " + ok + " " + (error || "-"))
      h.nextCase()
    }
  }
  // Fake ListView: copyFinished lands on the row like NotificationRow's.
  function fakeList(name) {
    var cb = h.result(name)
    return { itemAtIndex: function() { return { copyFinished: cb } } }
  }

  function nextCase() {
    if (!h.queue.length) { console.log("END"); Qt.quit(); return }
    var c = h.queue.shift()
    c()
  }

  Timer {
    interval: 200; running: true
    onTriggered: {
      var secret = String(Quickshell.env("STDIN_SECRET") || "")
      h.queue = [
        function() { opener.copyRow(h.fakeList("copy"), 0, { body: "  " + secret + "\n", summary: "s" }) },
        function() { opener.copyRow(h.fakeList("copy-summary"), 0, { body: " ", summary: "Тільки заголовок" }) },
        function() {
          runner.run("plain", ["sh", "-c", "echo done"], function(res) {
            console.log("RES plain " + res.ok + " " + (res.error || "-"))
            h.nextCase()
          })
        },
        function() {
          runner.run("fail", ["sh", "-c", "cat >/dev/null; echo nope >&2; exit 3"], function(res) {
            console.log("RES fail " + res.ok + " " + (res.error || "-"))
            h.nextCase()
          }, "x")
        }
      ]
      h.nextCase()
    }
  }
}
