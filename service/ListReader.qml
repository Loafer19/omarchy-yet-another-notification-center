import QtQuick
import Quickshell.Io

// One backend read (list, trash-list, apps, settings-get, seen). A list read
// that is already running may have started before the last write, so
// start() then queues one more and the lists never settle on pre-action data.
Process {
  id: reader
  // false: start() while running is ignored instead of queued.
  property bool queue: true
  property bool again: false

  // The full stdout of a finished read.
  signal output(string text)
  // A queued read is due: start() it again with a fresh command.
  signal rerun()

  function start(command) {
    if (reader.running) { if (reader.queue) reader.again = true; return }
    reader.command = command
    reader.running = true
  }

  onRunningChanged: if (!reader.running && reader.again) { reader.again = false; Qt.callLater(reader.rerun) }
  stdout: StdioCollector {
    onStreamFinished: reader.output(text)
  }
}
