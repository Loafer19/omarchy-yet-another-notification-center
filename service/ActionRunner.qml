pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../Model.js" as Model

// Checked store/helper calls: exit code and {"ok":false} both count as
// failure. Failures are logged and raised through failed(); done(res)
// always runs with { ok, error, data } so callers can roll back.
// input (optional string) is written to the process's stdin, which is then
// closed: user content (notification text) goes there, never into argv,
// where /proc/<pid>/cmdline shows it to every local user.
Item {
  id: runner
  visible: false

  // A call failed. message is user-facing ("Couldn't …: why").
  signal failed(string action, string message)
  property string lastError: ""

  function run(action, command, done, input) {
    var piped = typeof input === "string"
    var p = actionProcess.createObject(runner, {
      action: action, done: done || null,
      input: piped ? input : "", stdinEnabled: piped
    }) as Process
    if (!p) {
      runner.reportFailure(action, "could not start")
      if (typeof done === "function") done({ ok: false, error: "could not start", data: null })
      return
    }
    p.command = command
    p.running = true
  }

  function finish(p, exitCode, stdout, stderr) {
    var res = Model.actionResult(exitCode, stdout, stderr)
    if (!res.ok) runner.reportFailure(p.action, res.error)
    if (typeof p.done === "function") {
      try { p.done(res) } catch (e) { console.warn("yoyo.notification-center: " + p.action + " callback: " + e) }
    }
    p.destroy()
  }

  function reportFailure(action, error) {
    var msg = Model.actionMessage(action, error)
    runner.lastError = msg
    console.warn("yoyo.notification-center: " + msg)
    runner.failed(action, msg)
  }

  // One checked call. Finishes once the process has exited and both
  // streams are drained; a process that never starts is finished by the
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
      property string input: ""
      function maybeFinish(force) {
        if (proc.finished) return
        if (!force && !(proc.exited && proc.outDone && proc.errDone)) return
        proc.finished = true
        runner.finish(proc, proc.exited ? proc.code : NaN, outText.text, errText.text)
      }
      stdout: StdioCollector { id: outText; onStreamFinished: { proc.outDone = true; proc.maybeFinish(false) } }
      stderr: StdioCollector { id: errText; onStreamFinished: { proc.errDone = true; proc.maybeFinish(false) } }
      // stdin is only open when run() was given input: write it, then close
      // stdin (closeWriteChannel flushes first) so the reader sees EOF.
      onStarted: {
        if (!proc.stdinEnabled) return
        proc.write(proc.input)
        proc.input = ""
        proc.stdinEnabled = false
      }
      onExited: function(exitCode) { proc.exited = true; proc.code = exitCode; proc.maybeFinish(false) }
      onRunningChanged: if (!proc.running) grace.start()
      property Timer grace: Timer { interval: 1500; onTriggered: proc.maybeFinish(true) }
    }
  }
}
