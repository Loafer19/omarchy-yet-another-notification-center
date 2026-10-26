import QtQuick
import "../Model.js" as Model

// settings.json through the backend (settings-get / settings-set). A change
// shows at once; the store then clamps and validates it and its answer is
// adopted, or, if it was not saved, what the store really has is reloaded.
Item {
  id: settings
  visible: false

  property var cfg: ({})
  property int seq: 0
  // function(args) -> backend command; function(action, command, done).
  property var command: null
  property var run: null

  // cfg changed (shown, saved, or loaded).
  signal changed()
  // autoHideMs may have changed: reschedule.
  signal autoHideChanged()
  // A history limit was saved: prune, then reload the lists.
  signal limitsSaved()

  function load() { reader.start(settings.command(["settings-get"])) }

  function set(key, value) {
    if (Model.DEFAULTS[key] === undefined) return
    var patch = {}
    patch[key] = value
    var next = {}
    for (var k in settings.cfg) next[k] = settings.cfg[k]
    next[key] = value
    settings.cfg = next
    settings.changed()
    if (key === "autoHideMs") Qt.callLater(settings.autoHideChanged)
    var limits = key === "keepDays" || key === "maxItems" || key === "displayLimit" || key === "trashDays"
    var seq = ++settings.seq
    settings.run("settings-set", settings.command(["settings-set", JSON.stringify(patch)]), function(res) {
      if (seq !== settings.seq) return   // a newer change is in flight
      if (!res.ok) {
        // Not saved: show what the store really has.
        settings.load()
        return
      }
      // The store clamps and validates; adopt what it saved.
      if (res.data && typeof res.data === "object" && !Array.isArray(res.data)) {
        settings.cfg = Model.mergeSettings(res.data)
        settings.changed()
        if (key === "autoHideMs") settings.autoHideChanged()
      }
      // displayLimit trims History into Trash — prune after the new limit is
      // saved, then reload, so the list matches the new ceiling.
      if (limits) settings.limitsSaved()
    })
  }

  // One app's sound; "inherit" (or none) drops the override.
  function setAppSound(app, sound) {
    if (!Model.isSafeAppName(app)) return
    var sounds = {}
    var current = settings.cfg.appSounds || {}
    for (var k in current) sounds[k] = current[k]
    if (!sound || sound === "inherit") delete sounds[app]
    else sounds[app] = sound
    settings.set("appSounds", sounds)
  }

  ListReader {
    id: reader
    queue: false
    onOutput: function(text) {
      var data
      try { data = JSON.parse(text) } catch (e) { return }
      if (!data || typeof data !== "object") return
      settings.cfg = Model.mergeSettings(data)
      settings.changed()
      settings.autoHideChanged()
    }
  }
}
