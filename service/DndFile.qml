import QtQuick
import Quickshell
import Quickshell.Io

// Do Not Disturb as Omarchy stores it: notifications.json (4.0) or the
// service's notifications/quiet.json (4.5). Single source of truth: polling
// `dndState` raced the file (CLI lagged behind JSON) and made the
// bell/toggle flicker.
Item {
  id: dnd
  visible: false

  property string engine: ""
  readonly property string path: {
    var state = Quickshell.env("XDG_STATE_HOME")
    var home = Quickshell.env("HOME")
    var rootDir = state ? state : (home + "/.local/state")
    if (dnd.engine === "omapager") return rootDir + "/omarchy/notifications/quiet.json"
    return rootDir + "/omarchy/notifications.json"
  }

  // The file says DND is on/off (read at load and on every change).
  signal stored(bool on)

  // Re-read the file now (after a failed change, to roll back).
  function read() { dnd.parse(file.text()) }

  function parse(raw) {
    var data = null
    try { data = JSON.parse(String(raw || "{}")) } catch (e) { return }
    if (data && typeof data.dnd === "boolean") dnd.stored(data.dnd)
  }

  FileView {
    id: file
    path: dnd.path
    watchChanges: true
    printErrors: false
    preload: true
    onLoaded: dnd.parse(file.text())
    onFileChanged: file.reload()
  }
}
