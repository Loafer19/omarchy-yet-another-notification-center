.pragma library

var DEFAULTS = {
  displayLimit: 50,
  keepDays: 30,
  maxItems: 1000,
  trashDays: 30,
  autoHideMs: 0,
  soundEnabled: true,
  defaultSound: "message",
  soundLow: "complete",
  soundNormal: "message",
  soundCritical: "warning",
  muteSoundWhenDnd: true,
  appSounds: {},
  badge: "Dot",
  clickAction: "Auto",
  showBody: true,
  showPreview: true
}

var SOUND_IDS = ["message", "email", "warning", "complete", "camera", "mute"]
var SOUND_LABELS = {
  message: "Message",
  email: "Email",
  warning: "Warning",
  complete: "Complete",
  camera: "Camera",
  mute: "Mute",
  inherit: "Default"
}

function mergeSettings(raw) {
  var out = {}
  var key
  for (key in DEFAULTS) out[key] = DEFAULTS[key]
  if (!raw || typeof raw !== "object") return out
  for (key in DEFAULTS) {
    if (raw[key] === undefined || raw[key] === null) continue
    if (key === "appSounds" && typeof raw[key] === "object") {
      var sounds = {}
      for (var app in raw[key]) sounds[app] = String(raw[key][app] || "")
      out.appSounds = sounds
    } else {
      out[key] = raw[key]
    }
  }
  return out
}

function parseJsonArray(text) {
  try {
    var data = JSON.parse(String(text || "[]"))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

function parseJsonObject(text) {
  try {
    var data = JSON.parse(String(text || "{}"))
    return data && typeof data === "object" ? data : {}
  } catch (e) {
    return {}
  }
}

var WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function formatTime(timestamp) {
  var d = new Date(Number(timestamp) || 0)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function dayOf(timestamp, nowMs) {
  var when = new Date(Number(timestamp) || 0)
  var now = nowMs ? new Date(nowMs) : new Date()
  var midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  var ts = when.getTime()
  if (ts >= midnight) return "Today"
  if (ts >= midnight - 86400000) return "Yesterday"
  if (ts >= midnight - 6 * 86400000) return WEEKDAYS[when.getDay()]
  var label = when.getDate() + " " + MONTHS[when.getMonth()]
  if (when.getFullYear() !== now.getFullYear()) label += " " + when.getFullYear()
  return label
}

function rowFor(entry, nowMs) {
  var e = entry || {}
  return {
    key: String(e.key || ""),
    app: String(e.app || ""),
    appIcon: String(e.appIcon || ""),
    summary: String(e.summary || ""),
    body: String(e.body || ""),
    image: String(e.image || ""),
    preview: String(e.preview || ""),
    file: String(e.file || ""),
    glyph: String(e.glyph || ""),
    urgency: (e.urgency === undefined || e.urgency === null) ? 1 : Number(e.urgency),
    timestamp: Number(e.timestamp || 0),
    trashedAt: Number(e.trashedAt || 0),
    day: dayOf(e.timestamp, nowMs),
    time: formatTime(e.timestamp)
  }
}

function matches(entry, needle) {
  if (!needle) return true
  var n = String(needle).toLowerCase()
  return String(entry.app || "").toLowerCase().indexOf(n) >= 0
      || String(entry.summary || "").toLowerCase().indexOf(n) >= 0
      || String(entry.body || "").toLowerCase().indexOf(n) >= 0
}

function iconSource(icon) {
  var value = String(icon || "")
  if (!value) return ""
  if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
  if (value.charAt(0) === "/") return "file://" + value
  return ""
}

function isSafeAppName(name) {
  return /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$/.test(String(name || ""))
}

function isImagePath(path) {
  var s = String(path || "")
  if (s.indexOf("file://") === 0) s = s.slice(7)
  return /^\/[^'"\r\n]*\.(jpe?g|png|webp|gif)$/i.test(s)
}

function cycle(list, current, delta) {
  var i = 0
  for (i = 0; i < list.length; i++) {
    if (String(list[i]) === String(current)) break
  }
  if (i >= list.length) i = 0
  i = (i + delta) % list.length
  if (i < 0) i += list.length
  return list[i]
}

function clampInt(value, min, max, fallback) {
  var n = Number(value)
  if (!isFinite(n)) n = fallback
  n = Math.round(n)
  if (n < min) return min
  if (n > max) return max
  return n
}

// Quickshell NotificationUrgency, same as Omarchy's cards: Low=0, Normal=1, Critical=2.
function urgencyLevel(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  if (n >= 2) return 2
  if (n <= 0) return 0
  return 1
}

function urgencyName(value) {
  var n = urgencyLevel(value)
  if (n === 2) return "critical"
  if (n === 0) return "low"
  return "normal"
}

function urgencyLabel(value) {
  var n = urgencyLevel(value)
  if (n === 2) return "Critical"
  if (n === 0) return "Low"
  return "Normal"
}

function matchesUrgency(entry, filter) {
  var key = String(filter || "all")
  if (key === "" || key === "all") return true
  return urgencyName(entry && entry.urgency) === key
}

function soundFor(entry, settings) {
  var cfg = settings || DEFAULTS
  if (!cfg.soundEnabled) return "mute"
  var app = String((entry && entry.app) || "")
  var override = cfg.appSounds && app ? cfg.appSounds[app] : ""
  if (override) return String(override)
  var n = urgencyLevel(entry && entry.urgency)
  if (n === 2) return String(cfg.soundCritical || "warning")
  if (n === 0) return String(cfg.soundLow || "complete")
  return String(cfg.soundNormal || cfg.defaultSound || "message")
}

function soundLabel(id) {
  var key = String(id || "inherit")
  return SOUND_LABELS[key] || key
}
