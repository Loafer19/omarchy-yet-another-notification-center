.pragma library
.import "defaults.js" as Defaults

var CONFIG = Defaults.CONFIG
var DEFAULTS = CONFIG.defaults
var LIMITS = CONFIG.limits
var ENUMS = CONFIG.enums
var SOUND_ALIASES = CONFIG.soundAliases
var SOUND_IDS = (function() {
  var ids = []
  var list = CONFIG.sounds || []
  var i
  for (i = 0; i < list.length; i++) ids.push(list[i].id)
  return ids
})()
var SOUND_LABELS = (function() {
  var labels = { inherit: "Default" }
  var list = CONFIG.sounds || []
  var i
  for (i = 0; i < list.length; i++) labels[list[i].id] = list[i].label
  return labels
})()

function canonicalSound(id) {
  var s = String(id || "")
  if (s === "inherit" || s === "") return s
  if (SOUND_ALIASES && SOUND_ALIASES[s]) s = SOUND_ALIASES[s]
  var i
  for (i = 0; i < SOUND_IDS.length; i++) {
    if (SOUND_IDS[i] === s) return s
  }
  return DEFAULTS.defaultSound || "message-new-instant"
}

function clampNamed(name, value) {
  var L = LIMITS[name] || {}
  return clampInt(value, L.min, L.max, L.fallback)
}

function enumList(name) {
  return ENUMS[name] || []
}

function pickEnum(name, value, fallback) {
  var list = enumList(name)
  var s = String(value)
  var i
  for (i = 0; i < list.length; i++) {
    if (list[i] === s) return s
  }
  return fallback
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
    } else if (LIMITS[key]) {
      out[key] = clampNamed(key, raw[key])
    } else if (ENUMS[key]) {
      out[key] = pickEnum(key, raw[key], DEFAULTS[key])
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
  var list = enumList(set)
  var i
  if (list.length) {
    var opts = []
    for (i = 0; i < list.length; i++) opts.push({ value: list[i], label: list[i] })
    return opts
  }
  var sounds = []
  if (set === "appSound") sounds.push({ value: "inherit", label: "Default" })
  if (set === "sound" || set === "appSound") {
    for (i = 0; i < SOUND_IDS.length; i++) {
      sounds.push({ value: SOUND_IDS[i], label: soundLabel(SOUND_IDS[i]) })
    }
    return sounds
  }
  return []
}

function newestFirst(entries) {
  var list = (entries || []).slice()
  list.sort(function(a, b) {
    return Number(b.timestamp || 0) - Number(a.timestamp || 0)
  })
  return list
}

function visibleEntries(entries, needle, urgencyFilter) {
  var out = []
  var list = entries || []
  var i
  for (i = 0; i < list.length; i++) {
    if (matches(list[i], needle) && matchesUrgency(list[i], urgencyFilter))
      out.push(rowFor(list[i], 0))
  }
  return newestFirst(out)
}

function rowsFor(entries) {
  var out = []
  var list = entries || []
  var i
  for (i = 0; i < list.length; i++) out.push(rowFor(list[i], 0))
  return newestFirst(out)
}

function limitOf(name) {
  return LIMITS[name] || { min: 0, max: 0, step: 1, fallback: 0 }
}

function settingRows(cfg, filter, apps) {
  var c = cfg || DEFAULTS
  var rows = []
  function add(row) {
    rows.push({
      key: row.key,
      kind: row.kind,
      title: row.title,
      subtitle: row.subtitle || "",
      app: row.app || "",
      optionSet: row.optionSet || "",
      currentValue: row.currentValue || "",
      checked: row.checked === true,
      numericValue: row.numericValue || 0,
      min: row.min || 0,
      max: row.max || 0,
      step: row.step || 1
    })
  }
  if (filter === "sound") {
    add({ key: "soundEnabled", kind: "toggle", title: "Play a sound", subtitle: "Omarchy's daemon is silent — this plays one when a notification arrives", checked: !!c.soundEnabled })
    add({ key: "soundCritical", kind: "enum", title: "Critical", subtitle: "Omarchy -u critical", optionSet: "sound", currentValue: canonicalSound(c.soundCritical || DEFAULTS.soundCritical) })
    add({ key: "soundNormal", kind: "enum", title: "Normal", subtitle: "The usual desktop notification", optionSet: "sound", currentValue: canonicalSound(c.soundNormal || c.defaultSound || DEFAULTS.soundNormal) })
    add({ key: "soundLow", kind: "enum", title: "Low", subtitle: "Omarchy -u low", optionSet: "sound", currentValue: canonicalSound(c.soundLow || DEFAULTS.soundLow) })
    add({ key: "muteSoundWhenDnd", kind: "toggle", title: "Mute while Do Not Disturb", subtitle: "No sound while DND is on. History still records them.", checked: !!c.muteSoundWhenDnd })
    return rows
  }
  if (filter === "apps") {
    var list = apps || []
    var i
    for (i = 0; i < list.length; i++) {
      var app = list[i].app
      add({
        key: "app:" + app,
        kind: "appSound",
        title: app,
        subtitle: (list[i].count || 1) + " in archive",
        app: app,
        optionSet: "appSound",
        currentValue: (c.appSounds && c.appSounds[app]) ? c.appSounds[app] : "inherit"
      })
    }
    return rows
  }
  var display = limitOf("displayLimit")
  var keep = limitOf("keepDays")
  var trash = limitOf("trashDays")
  var maxItems = limitOf("maxItems")
  add({ key: "displayLimit", kind: "step", title: "Show at most", subtitle: "Cards on the History tab", numericValue: clampNamed("displayLimit", c.displayLimit), min: display.min, max: display.max, step: display.step })
  add({ key: "keepDays", kind: "step", title: "Keep history for", subtitle: "Days. Older entries are deleted", numericValue: clampNamed("keepDays", c.keepDays), min: keep.min, max: keep.max, step: keep.step })
  add({ key: "trashDays", kind: "step", title: "Keep trash for", subtitle: "Days. Then purged for good", numericValue: clampNamed("trashDays", c.trashDays), min: trash.min, max: trash.max, step: trash.step })
  add({ key: "maxItems", kind: "step", title: "Keep at most", subtitle: "Archive ceiling, regardless of age", numericValue: clampNamed("maxItems", c.maxItems), min: maxItems.min, max: maxItems.max, step: maxItems.step })
  add({ key: "clickAction", kind: "enum", title: "Clicking a notification", subtitle: "Never runs the sender's command", optionSet: "clickAction", currentValue: String(c.clickAction || DEFAULTS.clickAction) })
  add({ key: "showBody", kind: "toggle", title: "Show the message text", subtitle: "Off leaves the sender and subject", checked: !!c.showBody })
  add({ key: "showPreview", kind: "toggle", title: "Show pictures", subtitle: "Off stops keeping copies of new ones", checked: !!c.showPreview })
  add({ key: "badge", kind: "enum", title: "Unread mark", subtitle: "On the bar bell", optionSet: "badge", currentValue: String(c.badge || DEFAULTS.badge) })
  return rows
}
