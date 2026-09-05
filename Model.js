.pragma library

var DEFAULTS = {
  displayLimit: 50,
  keepDays: 30,
  maxItems: 1000,
  trashDays: 30,
  autoHideMs: 0,
  soundEnabled: true,
  defaultSound: "message-new-instant",
  soundLow: "complete",
  soundNormal: "message-new-instant",
  soundCritical: "dialog-warning",
  muteSoundWhenDnd: true,
  appSounds: {},
  badge: "Dot",
  clickAction: "Auto",
  showBody: true,
  showPreview: true
}

var SOUND_IDS = [
  "mute",
  "message-new-instant",
  "dialog-warning",
  "dialog-error",
  "complete",
  "bell",
  "camera-shutter",
  "alarm-clock-elapsed",
  "phone-incoming-call"
]
var SOUND_LABELS = {
  mute: "Mute",
  "message-new-instant": "Message",
  "dialog-warning": "Warning",
  "dialog-error": "Error",
  complete: "Complete",
  bell: "Bell",
  "camera-shutter": "Camera",
  "alarm-clock-elapsed": "Alarm",
  "phone-incoming-call": "Call",
  inherit: "Default"
}

function canonicalSound(id) {
  var s = String(id || "")
  if (s === "email" || s === "message") return "message-new-instant"
  if (s === "warning") return "dialog-warning"
  if (s === "camera") return "camera-shutter"
  if (s === "inherit" || s === "") return s
  var i
  for (i = 0; i < SOUND_IDS.length; i++) {
    if (SOUND_IDS[i] === s) return s
  }
  return "message-new-instant"
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
      for (var app in raw[key]) {
        if (!isSafeAppName(app)) continue
        sounds[app] = canonicalSound(raw[key][app])
      }
      out.appSounds = sounds
    } else if (key === "soundLow" || key === "soundNormal" || key === "soundCritical" || key === "defaultSound") {
      out[key] = canonicalSound(raw[key])
    } else if (key === "displayLimit") {
      out[key] = clampInt(raw[key], 10, 500, 50)
    } else if (key === "keepDays" || key === "trashDays") {
      out[key] = clampInt(raw[key], 1, 365, 30)
    } else if (key === "maxItems") {
      out[key] = clampInt(raw[key], 50, 10000, 1000)
    } else if (key === "autoHideMs") {
      out[key] = clampInt(raw[key], 0, 30000, 0)
    } else if (key === "badge") {
      var badge = String(raw[key])
      out[key] = (badge === "Dot" || badge === "Highlight" || badge === "Count" || badge === "None") ? badge : "Dot"
    } else if (key === "clickAction") {
      var click = String(raw[key])
      out[key] = (click === "Auto" || click === "Focus the app" || click === "Nothing") ? click : "Auto"
    } else if (key === "soundEnabled" || key === "muteSoundWhenDnd" || key === "showBody" || key === "showPreview") {
      out[key] = raw[key] === true
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

var MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function formatTime(timestamp, nowMs) {
  var when = new Date(Number(timestamp) || 0)
  var now = nowMs ? new Date(nowMs) : new Date()
  var clock = pad2(when.getHours()) + ":" + pad2(when.getMinutes())
  var sameDay = when.getFullYear() === now.getFullYear()
    && when.getMonth() === now.getMonth()
    && when.getDate() === now.getDate()
  if (sameDay) return clock
  var day = when.getDate() + " " + MONTHS_SHORT[when.getMonth()]
  if (when.getFullYear() !== now.getFullYear()) day += " " + when.getFullYear()
  return day + " " + clock
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
    time: formatTime(e.timestamp, nowMs)
  }
}

function matches(entry, needle) {
  if (!needle) return true
  var n = String(needle).toLowerCase()
  return String(entry.app || "").toLowerCase().indexOf(n) >= 0
      || String(entry.summary || "").toLowerCase().indexOf(n) >= 0
      || String(entry.body || "").toLowerCase().indexOf(n) >= 0
}

function storeImageUrl(value) {
  var s = String(value || "")
  if (!s) return ""
  if (s.indexOf("image:") === 0 || s.indexOf("http:") === 0 || s.indexOf("https:") === 0 || s.indexOf("qrc:") === 0)
    return ""
  if (s.indexOf("file://") === 0) s = s.slice(7)
  if (s.charAt(0) !== "/") return ""
  if (s.indexOf("..") >= 0 || s.indexOf("\\") >= 0 || s.indexOf("\0") >= 0) return ""
  var marker = "/omarchy/yoyo.notification-center/images/"
  var at = s.indexOf(marker)
  if (at < 0) return ""
  var rest = s.slice(at + marker.length)
  if (!rest || rest.indexOf("/") >= 0) return ""
  return "file://" + s
}

function themedIconName(value) {
  var s = String(value || "")
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(s)) return ""
  if (s.indexOf("..") >= 0) return ""
  return s
}

function isSafeAppName(name) {
  return /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$/.test(String(name || ""))
}

function isSafeKey(key) {
  return /^[A-Za-z0-9._+-]{1,128}$/.test(String(key || ""))
}

function isStoreImage(path) {
  return storeImageUrl(path) !== ""
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
  if (override) return canonicalSound(override)
  var n = urgencyLevel(entry && entry.urgency)
  if (n === 2) return canonicalSound(cfg.soundCritical || "dialog-warning")
  if (n === 0) return canonicalSound(cfg.soundLow || "complete")
  return canonicalSound(cfg.soundNormal || cfg.defaultSound || "message-new-instant")
}

function soundLabel(id) {
  var key = String(id || "inherit")
  return SOUND_LABELS[key] || key
}

function optionsFor(set) {
  if (set === "clickAction") {
    return [
      { value: "Auto", label: "Auto" },
      { value: "Focus the app", label: "Focus the app" },
      { value: "Nothing", label: "Nothing" }
    ]
  }
  if (set === "badge") {
    return [
      { value: "Dot", label: "Dot" },
      { value: "Highlight", label: "Highlight" },
      { value: "Count", label: "Count" },
      { value: "None", label: "None" }
    ]
  }
  var sounds = []
  var i
  if (set === "appSound") sounds.push({ value: "inherit", label: "Default" })
  if (set === "sound" || set === "appSound") {
    for (i = 0; i < SOUND_IDS.length; i++) {
      sounds.push({ value: SOUND_IDS[i], label: soundLabel(SOUND_IDS[i]) })
    }
    return sounds
  }
  return []
}
