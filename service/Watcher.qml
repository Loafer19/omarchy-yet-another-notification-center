import QtQuick
import Quickshell.Io

// The backend watcher (`backend.sh watch [ENGINE]`): every stdout line is a
// newly archived entry. Restarted 5 s after it dies; restart() switches it
// to a new command (engine) at once.
Item {
  id: watcher
  visible: false

  property var command: []
  property bool ready: false       // the engine is known
  property bool switching: false

  signal line(string text)

  function restart() {
    if (!watcher.ready) return
    if (proc.running) {
      watcher.switching = true
      proc.running = false
      return
    }
    proc.running = true
  }

  Process {
    id: proc
    command: watcher.command
    running: false
    stdout: SplitParser {
      onRead: function(line) { watcher.line(line) }
    }
    onExited: {
      if (watcher.switching) {
        watcher.switching = false
        proc.running = true
        return
      }
      again.restart()
    }
  }

  Timer {
    id: again
    interval: 5000
    onTriggered: if (!proc.running && watcher.ready) proc.running = true
  }
}
