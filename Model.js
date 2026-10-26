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
      out[key] = typeof raw[key] === "boolean" ? raw[key] : DEFAULTS[key]
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
    link: safeLink(e.link),
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

// A web address the panel may hand to xdg-open: http(s) only, a plain host,
// nothing that could be read as an option or a second argument.
function safeLink(value) {
  var s = String(value || "")
  if (!s || s.length > 2048) return ""
  if (/[\x00-\x20\x7f-\x9f"'<>\\`]/.test(s)) return ""
  if (!/^https?:\/\/[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*(:[0-9]{1,5})?([\/?#].*)?$/.test(s)) return ""
  return s
}

// --- Omarchy 4.5: pictures of live toasts -----------------------------------
// history.json keeps no pictures, so the panel draws a toast's picture once
// while the toast is up and saves it (backend.sh capture). Omapager's
// Security.localImagePath, ported: the image-path hint as Quickshell hands it
// over (image://icon//path) or a file:// URL, one spelling per file, never
// kernel interfaces or other services' runtime state.
function localImagePath(raw) {
  var text = typeof raw === "string" && raw.length <= 3072 ? raw : ""
  if (text.indexOf("image://icon/") === 0) text = text.slice("image://icon/".length)
  if (/^file:\/\//i.test(text)) {
    if (!/^file:\/\/\//i.test(text) || /[?#]/.test(text)) return ""
    try { text = decodeURIComponent(text.slice("file://".length)) } catch (e) { return "" }
  }
  if (!text || text.length > 1024 || text.charAt(0) !== "/" || /[\x00-\x1f\x7f-\x9f]/.test(text)) return ""
  var parts = text.slice(1).split("/")
  for (var i = 0; i < parts.length; i++)
    if (parts[i] === "" || parts[i] === "." || parts[i] === "..") return ""
  if (/^\/(?:proc|sys|dev)(?:\/|$)/.test(text)) return ""
  if (/^\/(?:var\/)?run(?:\/|$)/.test(text) && !/^\/run\/user\/[0-9]+\/./.test(text)) return ""
  return text
}

// What to draw for a live notification's picture: Quickshell's in-process
// image (inline image-data, valid only while the toast exists) or a local
// file. A themed icon name (image://icon/name) is no picture. "" = nothing.
function captureSource(image) {
  var s = String(image || "")
  if (/^image:\/\/qsimage\/[0-9]+\/[0-9]+$/.test(s)) return s
  if (s.indexOf("image://icon/") === 0 && !/^image:\/\/icon\/(?:\/|file:)/i.test(s)) return ""
  var p = localImagePath(s)
  return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : ""
}

// Pixel size to save a w x h picture at: never upscaled, longest side <= max.
function fitSize(w, h, max) {
  w = Number(w) || 0; h = Number(h) || 0; max = Number(max) || 512
  if (w <= 0 || h <= 0) return { width: 0, height: 0 }
  var k = Math.min(1, max / Math.max(w, h))
  return { width: Math.max(1, Math.round(w * k)), height: Math.max(1, Math.round(h * k)) }
}

// Omapager's placeholder for a secret-bearing notification (Store.redacted).
function isRedacted(row) {
  return !!row && row.summary === "Verification notification" && (row.body === "[redacted]" || row.bodyLine === "[redacted]")
}

// The persisted row for key in liveEntries / historyEntries, or null.
function engineRow(key, live, history) {
  var lists = [live || [], history || []]
  for (var l = 0; l < lists.length; l++)
    for (var i = 0; i < lists[l].length; i++)
      if (lists[l][i] && String(lists[l][i].key) === String(key)) return lists[l][i]
  return null
}

// Whether a captured picture for key may be saved: its row is known and is
// not a redacted placeholder. "wait" while the engine has not stored it yet.
function captureVerdict(key, live, history) {
  if (!isSafeKey(key)) return "drop"
  var row = engineRow(key, live, history)
  if (!row) return "wait"
  return isRedacted(row) ? "drop" : "save"
}

// Replace the entry with line's key (a JSON line from backend.sh capture) in
// entries. Returns the new list, or null if nothing changed.
function patchLine(entries, line) {
  var entry
  try { entry = JSON.parse(line) } catch (e) { return null }
  if (!entry || typeof entry !== "object" || !isSafeKey(entry.key)) return null
  var list = entries || []
  for (var i = 0; i < list.length; i++) {
    if (list[i].key === entry.key) {
      var next = list.slice()
      next[i] = entry
      return next
    }
  }
  return null
}

// A sender's D-Bus action is only there while its notification is: the
// live notification object's actions, as { id, text }.
function liveActions(ref) {
  var out = []
  if (!ref || !ref.actions) return out
  var n = Math.min(Number(ref.actions.length) || 0, 8)
  for (var i = 0; i < n; i++) {
    var a = ref.actions[i]
    var id = String((a && a.identifier) || "")
    if (!id || id.length > 128) continue
    out.push({ id: id, text: String((a && a.text) || id).slice(0, 64) })
  }
  return out
}

function hasLiveAction(ref, id) {
  var list = liveActions(ref)
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return true
  return false
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

// engine: "omapager" (Omarchy 4.5) changes the wording where 4.5 differs.
function settingRows(cfg, filter, apps, engine) {
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
  add({ key: "displayLimit", kind: "step", title: "Keep in History", subtitle: "Older cards move to Trash automatically", numericValue: clampNamed("displayLimit", c.displayLimit), min: display.min, max: display.max, step: display.step })
  add({ key: "keepDays", kind: "step", title: "Keep history for", subtitle: "Days. Older entries are deleted", numericValue: clampNamed("keepDays", c.keepDays), min: keep.min, max: keep.max, step: keep.step })
  add({ key: "trashDays", kind: "step", title: "Keep trash for", subtitle: "Days. Then purged for good", numericValue: clampNamed("trashDays", c.trashDays), min: trash.min, max: trash.max, step: trash.step })
  add({ key: "maxItems", kind: "step", title: "Hard ceiling", subtitle: "Extra History still overflows to Trash", numericValue: clampNamed("maxItems", c.maxItems), min: maxItems.min, max: maxItems.max, step: maxItems.step })
  add({ key: "clickAction", kind: "enum", title: "Clicking a notification", subtitle: "Never runs the sender's command", optionSet: "clickAction", currentValue: String(c.clickAction || DEFAULTS.clickAction) })
  add({ key: "showBody", kind: "toggle", title: "Show the message text", subtitle: "Off leaves the sender and subject", checked: !!c.showBody })
  add({ key: "showPreview", kind: "toggle", title: "Show pictures",
        subtitle: "Off stops keeping copies of new ones",
        checked: !!c.showPreview })
  add({ key: "badge", kind: "enum", title: "Unread mark", subtitle: "On the bar bell", optionSet: "badge", currentValue: String(c.badge || DEFAULTS.badge) })
  return rows
}

// --- actions -----------------------------------------------------------------
// Every store/helper call is checked: a non-zero exit code or {"ok":false}
// on stdout is a failure. The error text is the backend's "error" field, else
// the last stderr line, else the exit code.
var ACTION_LABELS = {
  "dismiss": "Couldn't move to Trash",
  "restore": "Couldn't restore",
  "purge": "Couldn't delete",
  "clear": "Couldn't clear History",
  "empty-trash": "Couldn't empty Trash",
  "settings-set": "Couldn't save the setting",
  "prune": "Couldn't apply the limits",
  "seen": "Couldn't save the read mark",
  "play-sound": "Couldn't play the sound",
  "dnd": "Couldn't change Do Not Disturb",
  "dismiss-toasts": "Couldn't hide the toasts",
  "load": "Couldn't read the archive",
  "copy": "Couldn't copy",
  "open": "Couldn't open",
  "capture": "Couldn't save the picture"
}

function lastLine(text) {
  var lines = String(text || "").split("\n")
  var i
  for (i = lines.length - 1; i >= 0; i--) {
    var s = lines[i].replace(/^\s+|\s+$/g, "")
    if (s) return s
  }
  return ""
}

function actionResult(exitCode, stdout, stderr) {
  var data = null
  var line = lastLine(stdout)
  if (line) {
    try { data = JSON.parse(line) } catch (e) { data = null }
  }
  var err = ""
  if (data && typeof data === "object" && !Array.isArray(data) && data.ok === false)
    err = String(data.error || "failed")
  var code = Number(exitCode)
  if (!err && code !== 0)
    err = lastLine(stderr) || (isFinite(code) ? "exit code " + code : "did not run")
  if (err.length > 160) err = err.slice(0, 159) + "…"
  return { ok: err === "", error: err, data: data }
}

function actionMessage(action, error) {
  var label = ACTION_LABELS[action] || ("Couldn't run " + String(action || "the action"))
  var e = String(error || "")
  return e ? label + ": " + e : label
}

// Text the copy button puts on the clipboard: body, else summary (trimmed).
function copyTextFor(row) {
  var r = row || {}
  var text = String(r.body || "").replace(/^\s+|\s+$/g, "")
  if (!text) text = String(r.summary || "").replace(/^\s+|\s+$/g, "")
  return text
}

// --- service logic (pure, so tests/model.test.js can cover it) ---------------

// History is newest first: count the leading entries newer than the read mark.
function unreadCount(entries, lastSeen) {
  var list = entries || []
  var seen = Number(lastSeen) || 0
  var count = 0
  var i
  for (i = 0; i < list.length; i++) {
    if (Number(list[i].timestamp) > seen) count++
    else break
  }
  return count
}

// One line from `backend.sh watch`. Returns { entries, entry } with the entry
// prepended (capped at limit), or null for bad JSON, unsafe keys and
// duplicates.
function absorbLine(entries, line, limit) {
  var entry
  try { entry = JSON.parse(line) } catch (e) { return null }
  if (!entry || typeof entry !== "object" || !isSafeKey(entry.key)) return null
  var list = entries || []
  var i
  for (i = 0; i < list.length; i++)
    if (list[i].key === entry.key) return null
  var next = [entry].concat(list)
  var cap = Number(limit || 50)
  if (next.length > cap) next = next.slice(0, cap)
  return { entries: next, entry: entry }
}

// Auto-hide works per toast, like Omarchy's own countdown: each toast goes
// `ms` after it first appeared, and a toast whose content changed (a
// replaces_id update or an in-place edit) counts as new, so its clock starts
// over. toastKey is that identity.
function toastKey(row) {
  if (!row) return ""
  var parts = [row.originalId, row.timestamp, row.summary, row.body, row.image]
  for (var i = 0; i < parts.length; i++)
    parts[i] = (parts[i] === undefined || parts[i] === null) ? "" : String(parts[i])
  return parts.join("\u001f")
}

// Omarchy 4.5's notification service (Omapager) keeps its toasts private and
// publishes them as liveEntries (persisted rows, each with a stable key and
// ts, the arrival time in seconds, which an update renews). 4.0.x has
// popupModel instead. "" = no service (yet).
function engineOf(service) {
  if (!service) return ""
  if (service.liveEntries !== undefined && service.historyEntries !== undefined) return "omapager"
  return "legacy"
}

// On 4.5 a toast is its key plus its arrival time, so an update is new.
function liveToastKey(row) {
  if (!row || !row.key) return ""
  return String(row.key) + "\u001f" + String(row.ts === undefined || row.ts === null ? "" : row.ts)
}

// liveEntries as [{ key, id }] (id = liveToastKey), invalid rows skipped.
function liveToasts(entries) {
  var out = []
  var list = entries || []
  for (var i = 0; i < list.length; i++) {
    var id = liveToastKey(list[i])
    if (id) out.push({ key: String(list[i].key), id: id })
  }
  return out
}

// keys: toastKey of each on-screen toast, in model order. firstSeen: key ->
// ms it was first seen (from the previous call). Returns the new firstSeen
// (only toasts still on screen), the indexes to expire now (high to low, so
// removing one keeps the others valid) and ms until the next deadline (-1:
// nothing pending). ms <= 0 turns auto-hide off and forgets every clock.
function autoHidePlan(ms, keys, firstSeen, now) {
  ms = Number(ms || 0)
  var plan = { seen: {}, expire: [], next: -1 }
  if (!(ms > 0)) return plan
  var prev = firstSeen || {}
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    var t = Object.prototype.hasOwnProperty.call(prev, k) ? Number(prev[k]) : now
    if (Object.prototype.hasOwnProperty.call(plan.seen, k)) t = plan.seen[k]
    plan.seen[k] = t
    var left = t + ms - now
    if (left <= 0) plan.expire.unshift(i)
    else if (plan.next < 0 || left < plan.next) plan.next = left
  }
  return plan
}

// "App · summary" for row notices (summary cut at 42 chars).
function noticeIdentity(row) {
  var app = String((row && row.app) || "").replace(/^\s+|\s+$/g, "")
  if (!app) app = "Notification"
  var summary = String((row && row.summary) || "").replace(/^\s+|\s+$/g, "")
  if (summary.length > 42) summary = summary.slice(0, 41) + "\u2026"
  if (summary) return app + " \u00b7 " + summary
  return app
}

// What changing setting row ROW by DELTA (a key press or click) does:
// { key, value } for settings.json, plus play: true for a sound, or
// { app, value } for one app's sound; null when nothing changes.
var NUDGE_SOUNDS = ["defaultSound", "soundLow", "soundNormal", "soundCritical"]
function settingNudge(row, cfg, delta) {
  if (!row) return null
  if (row.kind === "toggle") return { key: row.key, value: !(cfg[row.key]) }
  if (row.kind === "step") {
    var min = Number(row.min || 1)
    var max = Number(row.max || 100)
    var step = Number(row.step || 1)
    return { key: row.key, value: clampInt(Number(cfg[row.key] || min) + delta * step, min, max, min) }
  }
  if (row.kind === "enum" && enumList(row.key).length)
    return { key: row.key, value: cycle(enumList(row.key), cfg[row.key], delta) }
  if (row.kind === "enum" && NUDGE_SOUNDS.indexOf(row.key) >= 0)
    return { key: row.key, value: cycle(SOUND_IDS, cfg[row.key], delta), play: true }
  if (row.kind === "appSound") {
    var cur = (cfg.appSounds && cfg.appSounds[row.app]) ? cfg.appSounds[row.app] : "inherit"
    return { app: row.app, value: cycle(["inherit"].concat(SOUND_IDS), cur, delta) }
  }
  return null
}
