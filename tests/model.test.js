// Tests for Model.js / defaults.js outside QML:  node tests/model.test.js
// Pure logic only; the one backend call (settings defaults) uses a temp store.
process.env.TZ = "UTC"
const fs = require("fs"), path = require("path"), vm = require("vm"), cp = require("child_process"), os = require("os")
const dir = path.join(__dirname, "..")
const strip = src => src.replace(/^\.(pragma|import).*$/gm, "")
const dctx = {}
vm.createContext(dctx)
vm.runInContext(strip(fs.readFileSync(path.join(dir, "defaults.js"), "utf8")), dctx)
const ctx = { Defaults: { CONFIG: dctx.CONFIG } }
vm.createContext(ctx)
vm.runInContext(strip(fs.readFileSync(path.join(dir, "Model.js"), "utf8")), ctx)
const M = ctx
const nctx = {}
vm.createContext(nctx)
vm.runInContext(strip(fs.readFileSync(path.join(dir, "Nav.js"), "utf8")), nctx)
const N = nctx
let pass = 0, fail = 0
function eq(label, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) { pass++; console.log("PASS  " + label) } else { fail++; console.log("FAIL  " + label + "\n      got " + g + " want " + w) }
}
const plain = v => JSON.parse(JSON.stringify(v))

// --- defaults are shared with the backend -------------------------------------
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "yanc-model."))
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }))
function backend(...args) {
  const env = Object.assign({}, process.env, {
    HOME: tmp, XDG_STATE_HOME: path.join(tmp, "state"),
    YANC_STORE: path.join(tmp, "store"), YANC_SRC_DIR: path.join(tmp, "src")
  })
  return cp.execFileSync("bash", [path.join(dir, "scripts/backend.sh"), ...args], { env }).toString()
}
eq("backend settings-get == defaults.js defaults", JSON.parse(backend("settings-get")), plain(M.DEFAULTS))
eq("every limit has min <= fallback <= max", Object.keys(M.LIMITS).filter(k => {
  const l = M.LIMITS[k]; return !(l.min <= l.fallback && l.fallback <= l.max)
}), [])
eq("every limit default is inside its range", Object.keys(M.LIMITS).filter(k => M.clampNamed(k, M.DEFAULTS[k]) !== M.DEFAULTS[k]), [])
eq("enum defaults are valid", Object.keys(M.ENUMS).filter(k => M.ENUMS[k].indexOf(M.DEFAULTS[k]) < 0), [])
eq("sound defaults are known sounds", ["defaultSound", "soundLow", "soundNormal", "soundCritical"].filter(k => M.SOUND_IDS.indexOf(M.DEFAULTS[k]) < 0), [])

// --- settings ----------------------------------------------------------------------
eq("mergeSettings(null) = defaults", plain(M.mergeSettings(null)), plain(M.DEFAULTS))
const ms = M.mergeSettings({ displayLimit: 3, keepDays: 9999, maxItems: "200", autoHideMs: -5, badge: "Huge",
  clickAction: "Nothing", soundCritical: "warning", soundLow: "nope", appSounds: { "Slack": "camera", "../x": "bell", "Mail": "zzz" },
  showBody: false, showPreview: true, unknownKey: 1 })
eq("mergeSettings clamps limits", [ms.displayLimit, ms.keepDays, ms.maxItems, ms.autoHideMs], [10, 365, 200, 0])
eq("mergeSettings enums", [ms.badge, ms.clickAction], ["Dot", "Nothing"])
eq("mergeSettings sounds (alias + unknown -> default)", [ms.soundCritical, ms.soundLow], ["dialog-warning", "message-new-instant"])
eq("mergeSettings appSounds: unsafe names dropped, aliases resolved", plain(ms.appSounds), { Slack: "camera-shutter", Mail: "message-new-instant" })
eq("mergeSettings booleans", [ms.showBody, ms.showPreview], [false, true])
eq("mergeSettings drops unknown keys", ms.unknownKey, undefined)
eq("clampNamed non-number -> fallback", M.clampNamed("keepDays", "abc"), 30)
eq("clampNamed rounds", M.clampNamed("displayLimit", 54.6), 55)
eq("clampInt", [M.clampInt(5, 1, 3, 2), M.clampInt(-1, 0, 9, 4), M.clampInt(NaN, 0, 9, 4)], [3, 0, 4])
eq("canonicalSound", ["", "inherit", "email", "bell", "x"].map(M.canonicalSound), ["", "inherit", "message-new-instant", "bell", "message-new-instant"])
eq("cycle wraps both ways", [M.cycle(["a", "b", "c"], "c", 1), M.cycle(["a", "b", "c"], "a", -1), M.cycle(["a", "b"], "zz", 1)], ["a", "c", "b"])
eq("optionsFor badge", M.optionsFor("badge").map(o => o.value), ["Dot", "Highlight", "Count", "None"])
eq("optionsFor appSound starts with Default", M.optionsFor("appSound")[0], { value: "inherit", label: "Default" })
eq("soundLabel", [M.soundLabel("bell"), M.soundLabel("inherit"), M.soundLabel("odd")], ["Bell", "Default", "odd"])

// --- sounds per notification --------------------------------------------------------
const cfg = M.mergeSettings({ appSounds: { Slack: "bell" } })
eq("soundFor app override", M.soundFor({ app: "Slack", urgency: 2 }, cfg), "bell")
eq("soundFor by urgency", [0, 1, 2].map(u => M.soundFor({ app: "X", urgency: u }, cfg)), ["complete", "message-new-instant", "dialog-warning"])
eq("soundFor disabled -> mute", M.soundFor({ app: "Slack" }, M.mergeSettings({ soundEnabled: false })), "mute")

// --- urgency ------------------------------------------------------------------------
eq("urgencyLevel", [-3, 0, 1, 2, 7, "x", null].map(M.urgencyLevel), [0, 0, 1, 2, 2, 1, 0])
eq("urgencyName/Label", [M.urgencyName(2), M.urgencyLabel(0), M.urgencyName(undefined)], ["critical", "Low", "normal"])
eq("matchesUrgency", [M.matchesUrgency({ urgency: 2 }, "critical"), M.matchesUrgency({ urgency: 1 }, "low"), M.matchesUrgency({}, "all")], [true, false, true])

// --- time ---------------------------------------------------------------------------
const now = Date.UTC(2026, 9, 26, 12, 0)
eq("formatTime same day", M.formatTime(Date.UTC(2026, 9, 26, 7, 5), now), "07:05")
eq("formatTime other day", M.formatTime(Date.UTC(2026, 9, 3, 23, 59), now), "3 Oct 23:59")
eq("formatTime other year", M.formatTime(Date.UTC(2025, 0, 1, 0, 0), now), "1 Jan 2025 00:00")

// --- safety filters -----------------------------------------------------------------
eq("isSafeKey", ["1792963869372-3", "seed-1-2", "a b", "../x", "", "x".repeat(129)].map(M.isSafeKey), [true, true, false, false, false, false])
eq("isSafeAppName", ["Slack", "Google Chrome", " lead", "a/b", ""].map(M.isSafeAppName), [true, true, false, false, false])
eq("themedIconName", ["firefox", "org.gnome.Nautilus", "../etc", "a..b", "/usr/x.png", ""].map(M.themedIconName), ["firefox", "org.gnome.Nautilus", "", "", "", ""])
const img = "/home/u/.local/state/omarchy/yoyo.notification-center/images/k1-image.png"
eq("storeImageUrl only inside the store images dir", [img, "file://" + img, "/tmp/x.png", img.replace("k1", "../k1"),
  "https://x/y.png", "/home/u/.local/state/omarchy/yoyo.notification-center/images/sub/x.png"].map(M.storeImageUrl),
  ["file://" + img, "file://" + img, "", "", "", ""])
eq("isStoreImage", [M.isStoreImage(img), M.isStoreImage("/etc/passwd")], [true, false])

// --- rows ---------------------------------------------------------------------------
const entries = [
  { key: "a", app: "Slack", summary: "Deploy", body: "is live", urgency: 2, timestamp: 300 },
  { key: "b", app: "Mail", summary: "Invoice", body: "", urgency: 1, timestamp: 200 },
  { key: "c", app: "Spotify", summary: "Song", body: "Deploy song", urgency: 0, timestamp: 100 }
]
eq("visibleEntries search (app/summary/body, case-insensitive)", M.visibleEntries(entries, "DEPLOY", "all").map(r => r.key), ["a", "c"])
eq("visibleEntries urgency chip", M.visibleEntries(entries, "", "low").map(r => r.key), ["c"])
eq("rowsFor newest first", M.rowsFor([entries[2], entries[0], entries[1]]).map(r => r.key), ["a", "b", "c"])
const r0 = M.rowFor({ key: "k", timestamp: 5, trashedAt: 9 }, now)
eq("rowFor defaults", [r0.app, r0.urgency, r0.trashedAt, typeof r0.time], ["", 1, 9, "string"])
eq("settingRows general", M.settingRows(M.DEFAULTS, "general", []).map(r => r.key),
  ["displayLimit", "keepDays", "trashDays", "maxItems", "clickAction", "showBody", "showPreview", "badge"])
eq("settingRows sound", M.settingRows(M.DEFAULTS, "sound", []).map(r => r.key),
  ["soundEnabled", "soundCritical", "soundNormal", "soundLow", "muteSoundWhenDnd"])
eq("settingRows apps", M.settingRows(cfg, "apps", [{ app: "Slack", count: 3 }, { app: "Mail" }]).map(r => [r.title, r.subtitle, r.currentValue]),
  [["Slack", "3 in archive", "bell"], ["Mail", "1 in archive", "inherit"]])
eq("parseJsonArray/Object tolerate junk", [M.parseJsonArray("nope"), M.parseJsonArray("{}"), M.parseJsonObject("[")], [[], [], {}])

// --- service logic ------------------------------------------------------------------
eq("unreadCount stops at first seen", M.unreadCount(entries, 150), 2)
eq("unreadCount none", M.unreadCount(entries, 300), 0)
const ab = M.absorbLine(entries, JSON.stringify({ key: "d", timestamp: 400 }), 3)
eq("absorbLine prepends and caps", ab.entries.map(e => e.key), ["d", "a", "b"])
eq("absorbLine returns the entry", ab.entry.key, "d")
eq("absorbLine rejects dup / bad key / junk", [
  M.absorbLine(entries, JSON.stringify({ key: "a" }), 50),
  M.absorbLine(entries, JSON.stringify({ key: "../x" }), 50),
  M.absorbLine(entries, "{not json", 50),
  M.absorbLine(entries, "null", 50)], [null, null, null, null])
// auto-hide: per-toast clocks
const K = (id, summary, extra) => M.toastKey(Object.assign({ originalId: id, timestamp: 100 + id, summary: summary || "s", body: "b", image: "" }, extra || {}))
eq("toastKey: same toast, same key; edit/replace -> new key",
  [K(1) === K(1), K(1) === K(1, "edited"), K(1) === K(1, "s", { image: "/x.png" }), K(1) === K(2), M.toastKey(null), M.toastKey({})],
  [true, false, false, false, "", "\u001f\u001f\u001f\u001f"])
eq("plan: off forgets every clock", plain(M.autoHidePlan(0, [K(1)], { [K(1)]: 0 }, 5000)), { seen: {}, expire: [], next: -1 })
eq("plan: off for junk ms", plain(M.autoHidePlan("abc", [K(1)], {}, 0)).next, -1)
eq("plan: no toasts", plain(M.autoHidePlan(2000, [], { [K(1)]: 0 }, 100)), { seen: {}, expire: [], next: -1 })
let p1 = M.autoHidePlan(2000, [K(1)], {}, 1000)
eq("plan: new toast starts its clock now", [p1.seen[K(1)], plain(p1.expire), p1.next], [1000, [], 2000])
eq("plan: not yet", plain(M.autoHidePlan(2000, [K(1)], p1.seen, 2999)).next, 1)
eq("plan: due -> expire", plain(M.autoHidePlan(2000, [K(1)], p1.seen, 3000)).expire, [0])
// stacked: newest is index 0 (Omarchy inserts at 0)
let st = M.autoHidePlan(2000, [K(3), K(2), K(1)], { [K(1)]: 0, [K(2)]: 1000 }, 2500)
eq("plan: stacked toasts keep their own clocks", [plain(st.expire), st.next, st.seen[K(3)]], [[2], 500, 2500])
st = M.autoHidePlan(2000, [K(3), K(2), K(1)], { [K(1)]: 0, [K(2)]: 0, [K(3)]: 0 }, 9000)
eq("plan: several due -> indexes high to low", plain(st.expire), [2, 1, 0])
eq("plan: a newer toast does not extend older ones", plain(M.autoHidePlan(2000, [K(9), K(1)], { [K(1)]: 0 }, 2000).expire), [1])
eq("plan: replaced/edited toast gets a fresh clock", (() => { const q = M.autoHidePlan(2000, [K(1, "edited")], { [K(1)]: 0 }, 1500); return [plain(q.expire), q.next] })(), [[], 2000])
eq("plan: gone toasts are forgotten", Object.keys(M.autoHidePlan(2000, [K(2)], { [K(1)]: 0, [K(2)]: 0 }, 10)).length && Object.keys(M.autoHidePlan(2000, [K(2)], { [K(1)]: 0, [K(2)]: 0 }, 10).seen), [K(2)])
eq("plan: duplicate keys share a clock", plain(M.autoHidePlan(2000, [K(1), K(1)], { [K(1)]: 0 }, 2000).expire), [1, 0])
eq("plan: shorter setting applies to toasts already up", plain(M.autoHidePlan(1000, [K(1)], { [K(1)]: 0 }, 1200).expire), [0])
eq("noticeIdentity", [M.noticeIdentity({ app: " Slack ", summary: "Hi" }), M.noticeIdentity({}), M.noticeIdentity({ app: "A", summary: "x".repeat(50) }).length],
  ["Slack · Hi", "Notification", 4 + 42])
eq("copyTextFor body, else summary", [M.copyTextFor({ body: "  b ", summary: "s" }), M.copyTextFor({ body: " ", summary: "s" }), M.copyTextFor(null)], ["b", "s", ""])

// --- action results -------------------------------------------------------------------
eq("actionResult ok", M.actionResult(0, '{"ok":true,"dismissed":"k"}\n', "").ok, true)
eq("actionResult settings object counts as ok", M.actionResult(0, '{"badge":"Dot"}', "").data.badge, "Dot")
eq("actionResult ok:false from stdout", plain(M.actionResult(1, '{"ok":false,"error":"not in history"}\n', "yoyo: not in history\n")),
  { ok: false, error: "not in history", data: { ok: false, error: "not in history" } })
eq("actionResult ok:false even with exit 0", M.actionResult(0, '{"ok":false,"error":"x"}', "").error, "x")
eq("actionResult exit code + stderr", M.actionResult(2, "", "warn\nwl-copy: no display\n\n").error, "wl-copy: no display")
eq("actionResult exit code only", M.actionResult(127, "", "").error, "exit code 127")
eq("actionResult never ran", M.actionResult(NaN, "", "").error, "did not run")
eq("actionResult caps long errors", M.actionResult(1, "", "e".repeat(400)).error.length, 160)
eq("actionMessage", [M.actionMessage("dismiss", "not in history"), M.actionMessage("weird", ""), M.actionMessage("clear", "")],
  ["Couldn't move to Trash: not in history", "Couldn't run weird", "Couldn't clear History"])
eq("every action the QML runs has a label", ["dismiss", "restore", "purge", "clear", "empty-trash", "settings-set", "prune", "seen",
  "play-sound", "dnd", "dismiss-toasts", "load", "copy", "open", "capture"].filter(a => !M.ACTION_LABELS[a]), [])
const qml = ["Service.qml", "Panel.qml"].map(f => fs.readFileSync(path.join(dir, f), "utf8")).join("\n")
eq("no fire-and-forget execDetached left in Service/Panel", (qml.match(/execDetached/g) || []).length, 0)
eq("every run(\"…\") action has a label", [...qml.matchAll(/\brun\("([a-z-]+)"/g)].map(m => m[1]).filter(a => !M.ACTION_LABELS[a]), [])
// Notification text never goes into argv (/proc/<pid>/cmdline is world-readable;
// wl-copy's clipboard owner lives on): Copy hands it to wl-copy on stdin.
const opener = fs.readFileSync(path.join(dir, "components", "RowOpener.qml"), "utf8")
const copyArgv = (opener.match(/run\("copy",\s*(\[[^\]]*\])/) || ["", ""])[1]
eq("copy: wl-copy argv is string literals only (no text)", /^\[\s*"wl-copy"(\s*,\s*"[^"]*")*\s*\]$/.test(copyArgv), true)
eq("copy: text passed as run() input (stdin)", /\},\s*text\)/.test(opener), true)
const allQml = cp.execSync("git ls-files '*.qml'", { cwd: dir, encoding: "utf8" }).split("\n").filter(Boolean)
  .map(f => fs.readFileSync(path.join(dir, f), "utf8")).join("\n")
eq("no shell wrapper around wl-copy", /sh"\s*,\s*"-c"[^\n]*wl-copy/.test(allQml), false)

// --- settings: one source of truth, same rules in JS and the backend ---------------
const settingsFile = path.join(tmp, "store", "settings.json")
function backendSet(patch) {
  fs.rmSync(settingsFile, { force: true })
  return JSON.parse(backend("settings-set", JSON.stringify(patch)))
}
function jsSet(patch) {
  const raw = Object.assign({}, plain(M.DEFAULTS))
  for (const k in patch) if (patch[k] !== null) raw[k] = patch[k]
  return plain(M.mergeSettings(raw))
}
const patches = [
  {},
  { soundEnabled: false, showBody: false, showPreview: false, muteSoundWhenDnd: false },
  { soundEnabled: "yes", showBody: 0, showPreview: null, muteSoundWhenDnd: 1 },
  { displayLimit: 3, keepDays: 9999, trashDays: 0, maxItems: 20000, autoHideMs: -5 },
  { displayLimit: "120", keepDays: "abc", autoHideMs: 8000 },
  { badge: "Count", clickAction: "Nothing" },
  { badge: "Huge", clickAction: 7 },
  { defaultSound: "warning", soundLow: "nope", soundNormal: "bell", soundCritical: "dialog-warning" },
  { appSounds: { Slack: "bell", "../x": "bell", Mail: "nope", " bad": "bell" } }
]
patches.forEach((p, i) => eq("settings-set == JS mergeSettings #" + i + " " + JSON.stringify(p), backendSet(p), jsSet(p)))
patches.forEach((p, i) => { const b = backendSet(p); eq("JS mergeSettings keeps backend output #" + i, plain(M.mergeSettings(b)), b) })
fs.rmSync(settingsFile, { force: true })
backend("settings-set", '{"soundEnabled":false,"showBody":false}')
const after = JSON.parse(backend("settings-set", '{"badge":"Count"}'))
eq("booleans can be switched off and stay off", [after.soundEnabled, after.showBody, after.badge], [false, false, "Count"])
eq("...and back on", JSON.parse(backend("settings-set", '{"soundEnabled":true}')).soundEnabled, true)
const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"))
eq("manifest has no second copy of the settings", [manifest.barWidget.schema, manifest.barWidget.defaults], [undefined, undefined])
const panel = fs.readFileSync(path.join(dir, "Panel.qml"), "utf8")
eq("Panel reads no Omarchy widget settings", [/\bsetting\(/.test(panel), /pushSchemaSettings/.test(panel)], [false, false])

// --- Omarchy 4.5 (Omapager) ---------------------------------------------------------
// Fixtures: anonymised rows from a real 4.5 history.json/live.json.
const fx = name => JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures/omapager", name), "utf8"))
const hist45 = fx("history.json"), live45 = fx("live.json")
eq("engineOf: no service", M.engineOf(null), "")
eq("engineOf: 4.0 (popupModel)", M.engineOf({ popupModel: { count: 0 }, expirePopup() {} }), "legacy")
eq("engineOf: older Omarchy (no toast API)", M.engineOf({ setDoNotDisturb() {} }), "legacy")
eq("engineOf: 4.5 (liveEntries + historyEntries)", M.engineOf({ liveEntries: live45, historyEntries: hist45, closeToast() {} }), "omapager")
eq("engineOf: 4.5 with nothing on screen yet", M.engineOf({ liveEntries: [], historyEntries: [] }), "omapager")
eq("engineOf: half the 4.5 API is not 4.5", M.engineOf({ liveEntries: [] }), "legacy")
eq("liveToasts: one per keyed row", M.liveToasts(live45).map(t => t.key), ["nmvp5a1b2c", "nmvp5a3d4e"])
eq("liveToasts: every real history row has a key", M.liveToasts(hist45).length, hist45.length)
eq("liveToasts: junk skipped", M.liveToasts([null, {}, { key: "" }, { key: "a", ts: 1 }]).map(t => t.key), ["a"])
eq("liveToasts(null)", M.liveToasts(null), [])
eq("liveToastKey: an update (new ts) is a new toast", M.liveToastKey(live45[0]) === M.liveToastKey(Object.assign({}, live45[0], { ts: live45[0].ts + 3 })), false)
eq("liveToastKey: same row, same toast", M.liveToastKey(live45[0]) === M.liveToastKey(JSON.parse(JSON.stringify(live45[0]))), true)
{
  // The 4.5 auto-hide path: Model.autoHidePlan over liveToasts ids, expire
  // indexes mapped back to keys (as Service.noteLive does).
  const ids = rows => M.liveToasts(rows).map(t => t.id)
  const keysOf = (rows, plan) => plan.expire.slice().reverse().map(i => M.liveToasts(rows)[i].key)
  let p = M.autoHidePlan(2000, ids(live45), {}, 0)
  eq("4.5 plan: both live rows clocked, critical too", [Object.keys(p.seen).length, p.next], [2, 2000])
  const later = live45.concat([Object.assign({}, live45[0], { key: "nlater", ts: 1793012010 })])
  p = M.autoHidePlan(2000, ids(later), p.seen, 1000)
  eq("4.5 plan: a later row gets its own clock", p.next, 1000)
  p = M.autoHidePlan(2000, ids(later), p.seen, 2000)
  eq("4.5 plan: the first two close by key", keysOf(later, p).sort(), ["nmvp5a1b2c", "nmvp5a3d4e"])
  const updated = [Object.assign({}, live45[0], { ts: live45[0].ts + 1.5 })]
  p = M.autoHidePlan(2000, ids(updated), { [M.liveToastKey(live45[0])]: 0 }, 1500)
  eq("4.5 plan: an update restarts the clock", [p.expire, p.next], [[], 2000])
}
eq("settingRows: 4.0 wording unchanged", M.settingRows(M.DEFAULTS, "general", []).filter(r => r.key === "showPreview")[0].subtitle,
  "Off stops keeping copies of new ones")
eq("settingRows: legacy engine = 4.0 wording", JSON.stringify(M.settingRows(M.DEFAULTS, "general", [], "legacy")), JSON.stringify(M.settingRows(M.DEFAULTS, "general", [])))
eq("settingRows: 4.5 keeps pictures again (captured live)", M.settingRows(M.DEFAULTS, "general", [], "omapager").filter(r => r.key === "showPreview")[0].subtitle,
  "Off stops keeping copies of new ones")

// --- 4.5: live captures, links, actions ---------------------------------------
eq("captureSource: inline image-data (qsimage)", M.captureSource("image://qsimage/12/3"), "image://qsimage/12/3")
eq("captureSource: image-path hint", M.captureSource("image://icon//tmp/.org.chromium.Chromium.abc"), "file:///tmp/.org.chromium.Chromium.abc")
eq("captureSource: file:// with spaces escaped", M.captureSource("file:///home/u/My%20Pics/a.png"), "file:///home/u/My%20Pics/a.png")
eq("captureSource: themed icon is no picture", M.captureSource("image://icon/firefox"), "")
eq("captureSource: refuses kernel/run/dotdot/relative/query", [
  "image://icon//proc/self/environ", "/dev/zero", "/run/dbus/x", "/home/u/../etc/x", "a.png", "file://host/x.png",
  "file:///tmp/a.png?x", "image://qsimage/a/b", "https://e.org/a.png", "/tmp//a.png"].map(M.captureSource), Array(10).fill(""))
eq("captureSource: runtime dir allowed", M.captureSource("/run/user/1000/pic.png"), "file:///run/user/1000/pic.png")
eq("fitSize: never upscales", plain(M.fitSize(64, 32, 512)), { width: 64, height: 32 })
eq("fitSize: longest side capped", plain(M.fitSize(2000, 1000, 512)), { width: 512, height: 256 })
eq("fitSize: empty", plain(M.fitSize(0, 10)), { width: 0, height: 0 })
const red = { key: "r1", summary: "Verification notification", body: "[redacted]" }
eq("captureVerdict: unknown yet -> wait", M.captureVerdict("k1", [], []), "wait")
eq("captureVerdict: live row -> save", M.captureVerdict("k1", [{ key: "k1", summary: "a", body: "b" }], []), "save")
eq("captureVerdict: closed row -> save", M.captureVerdict("k1", [], [{ key: "k1", summary: "a", body: "b" }]), "save")
eq("captureVerdict: redacted -> drop", M.captureVerdict("r1", [red], []), "drop")
eq("captureVerdict: bad key -> drop", M.captureVerdict("../x", [], []), "drop")
eq("patchLine: replaces the entry", plain(M.patchLine([{ key: "a", image: "" }, { key: "b" }], '{"key":"a","image":"file:///x"}')),
  [{ key: "a", image: "file:///x" }, { key: "b" }])
eq("patchLine: unknown key / junk", [M.patchLine([{ key: "a" }], '{"key":"z"}'), M.patchLine([], "nope"), M.patchLine([], '{"key":"../a"}')], [null, null, null])
eq("safeLink: http(s) kept", [M.safeLink("https://github.com/a/b?x=1#c"), M.safeLink("http://localhost:8080/")], ["https://github.com/a/b?x=1#c", "http://localhost:8080/"])
eq("safeLink: everything else dropped", ["javascript:alert(1)", "file:///etc/passwd", "https://a b/", "-https://x.org", "https://x.org/'a",
  "https://a..b/", "https://x.org/\n", "ftp://x.org/", "https://" + "a".repeat(2050)].map(M.safeLink), Array(9).fill(""))
eq("rowFor: link sanitised", [M.rowFor({ key: "a", link: "https://x.org/" }, 0).link, M.rowFor({ key: "a", link: "javascript:1" }, 0).link, M.rowFor({ key: "a" }, 0).link],
  ["https://x.org/", "", ""])
const ref = { actions: [{ identifier: "default", text: "" }, { identifier: "reply", text: "Reply" }, { identifier: "", text: "x" }] }
eq("liveActions: identifiers and labels", plain(M.liveActions(ref)), [{ id: "default", text: "default" }, { id: "reply", text: "Reply" }])
eq("hasLiveAction", [M.hasLiveAction(ref, "default"), M.hasLiveAction(ref, "nope"), M.hasLiveAction(null, "default")], [true, false, false])

// --- keyboard cursor (Nav.js) -------------------------------------------------
const TABS = [{ key: "history" }, { key: "trash" }, { key: "settings" }]
const CHIPS = [{ key: "all" }, { key: "critical" }, { key: "normal" }, { key: "low" }]
const nav = (o) => Object.assign({ tabs: TABS, activeTab: "history", chips: CHIPS, filterKey: "normal", count: 3 }, o || {})
const at = (section, index) => ({ section, index })
eq("indexOfKey: found / missing -> 0", [N.indexOfKey(CHIPS, "low"), N.indexOfKey(CHIPS, "nope"), N.indexOfKey([], "x")], [3, 0, 0])
eq("clampIndex", [N.clampIndex(-1, 3), N.clampIndex(5, 3), N.clampIndex(1, 3), N.clampIndex(4, 0)], [0, 2, 1, 0])
eq("start: rows first", plain(N.start(nav())), at("rows", 0))
eq("start: no rows -> active chip", plain(N.start(nav({ count: 0 }))), at("filters", 2))
eq("start: no rows, no chips -> active tab", plain(N.start(nav({ count: 0, chips: [], activeTab: "trash" }))), at("tabs", 1))
eq("cycleTab wraps both ways", [plain(N.cycleTab(nav(), -1)), plain(N.cycleTab(nav({ activeTab: "settings" }), 1))],
  [{ section: "tabs", index: 2, tab: "settings" }, { section: "tabs", index: 0, tab: "history" }])
eq("down from tabs -> active chip", plain(N.move(at("tabs", 0), 0, 1, nav())), at("filters", 2))
eq("down from tabs, no chips -> rows", plain(N.move(at("tabs", 1), 0, 1, nav({ chips: [] }))), at("rows", 0))
eq("down from tabs, nothing below -> stays", plain(N.move(at("tabs", 1), 0, 1, nav({ chips: [], count: 0 }))), at("tabs", 1))
eq("up from tabs -> stays", plain(N.move(at("tabs", 1), 0, -1, nav())), at("tabs", 1))
eq("down from chips -> first row", plain(N.move(at("filters", 1), 0, 1, nav())), at("rows", 0))
eq("down from chips, no rows -> stays", plain(N.move(at("filters", 1), 0, 1, nav({ count: 0 }))), at("filters", 1))
eq("up from chips -> active tab", plain(N.move(at("filters", 1), 0, -1, nav({ activeTab: "settings" }))), at("tabs", 2))
eq("down in rows stops at the last", [plain(N.move(at("rows", 1), 0, 1, nav())), plain(N.move(at("rows", 2), 0, 1, nav()))], [at("rows", 2), at("rows", 2)])
eq("up in rows", plain(N.move(at("rows", 2), 0, -1, nav())), at("rows", 1))
eq("up from the first row -> active chip", plain(N.move(at("rows", 0), 0, -1, nav())), at("filters", 2))
eq("up from the first row, no chips -> active tab", plain(N.move(at("rows", 0), 0, -1, nav({ chips: [], activeTab: "trash" }))), at("tabs", 1))
eq("left/right on tabs switches tab (clamped)", [plain(N.move(at("tabs", 0), 1, 0, nav())), plain(N.move(at("tabs", 0), -1, 0, nav()))],
  [{ section: "tabs", index: 1, tab: "trash" }, { section: "tabs", index: 0, tab: "history" }])
eq("left/right on chips applies the chip", plain(N.move(at("filters", 3), 1, 0, nav())), { section: "filters", index: 3, filter: "low" })
eq("left/right on a settings row nudges it", plain(N.move(at("rows", 1), -1, 0, nav({ activeTab: "settings" }))), { section: "rows", index: 1, nudge: -1 })
eq("left/right on a history row does nothing", plain(N.move(at("rows", 1), 1, 0, nav())), at("rows", 1))
eq("no direction does nothing", plain(N.move(at("rows", 1), 0, 0, nav())), at("rows", 1))

// --- settingNudge -------------------------------------------------------------
const srow = (key, filter) => M.settingRows(M.DEFAULTS, filter || "general", []).filter(r => r.key === key)[0]
eq("nudge: toggle flips", plain(M.settingNudge(srow("showBody"), { showBody: true }, 1)), { key: "showBody", value: false })
const dl = srow("displayLimit")
eq("nudge: step moves by step, clamped", [M.settingNudge(dl, { displayLimit: dl.min }, -1).value, M.settingNudge(dl, { displayLimit: dl.max }, 1).value, M.settingNudge(dl, { displayLimit: dl.min }, 1).value],
  [dl.min, dl.max, dl.min + dl.step])
eq("nudge: enum cycles", plain(M.settingNudge(srow("badge"), { badge: "Dot" }, 1)).key, "badge")
eq("nudge: enum value is one of the list", M.ENUMS.badge.indexOf(M.settingNudge(srow("badge"), { badge: "Dot" }, 1).value) >= 0, true)
const sn = M.settingNudge(srow("soundNormal", "sound"), M.DEFAULTS, 1)
eq("nudge: a sound plays", [sn.key, sn.play, M.SOUND_IDS.indexOf(sn.value) >= 0], ["soundNormal", true, true])
const an = M.settingNudge({ kind: "appSound", app: "Slack" }, { appSounds: {} }, 1)
eq("nudge: app sound starts from inherit", [an.app, an.value], ["Slack", M.cycle(["inherit"].concat(M.SOUND_IDS), "inherit", 1)])
eq("nudge: nothing for no row / unknown kind", [M.settingNudge(null, {}, 1), M.settingNudge({ kind: "x" }, {}, 1)], [null, null])

console.log(`\npassed ${pass}, failed ${fail}`)
process.exit(fail ? 1 : 0)
