.pragma library
// Keyboard cursor of the panel, as pure functions (tests/model.test.js).
// The cursor sits in one section: "tabs", "filters" (the chip row under the
// header) or "rows" (the list). ctx describes the panel:
//   { tabs, activeTab, chips, filterKey, count }
// tabs/chips are [{ key, label }], filterKey is the active chip's key and
// count the number of rows in the active list.
// A step returns { section, index } plus, when the step also does
// something, tab (switch to this tab), filter (apply this chip key) or
// nudge (change the setting under the cursor by this much). The panel sets
// section and index first, then tab or filter, then nudges.

function indexOfKey(chips, key) {
  for (var i = 0; i < chips.length; i++) {
    if (String(chips[i].key) === String(key)) return i
  }
  return 0
}

function clampIndex(i, len) {
  if (len <= 0) return 0
  if (i < 0) return 0
  if (i >= len) return len - 1
  return i
}

function atFilters(ctx) { return { section: "filters", index: indexOfKey(ctx.chips, ctx.filterKey) } }
function atTabs(ctx) { return { section: "tabs", index: indexOfKey(ctx.tabs, ctx.activeTab) } }
function atRows() { return { section: "rows", index: 0 } }

// Where the cursor shows up on the first key press: the first row, else the
// active chip, else the active tab.
function start(ctx) {
  if (ctx.count > 0) return atRows()
  if (ctx.chips.length > 0) return atFilters(ctx)
  return atTabs(ctx)
}

// One tab to the left (-1) or right (+1), wrapping; the cursor follows.
function cycleTab(ctx, direction) {
  var n = ctx.tabs.length
  var i = (indexOfKey(ctx.tabs, ctx.activeTab) + direction) % n
  if (i < 0) i += n
  return { section: "tabs", index: i, tab: ctx.tabs[i].key }
}

function moveVertical(cur, dy, ctx) {
  if (cur.section === "tabs") {
    if (dy > 0 && ctx.chips.length > 0) return atFilters(ctx)
    if (dy > 0 && ctx.count > 0) return atRows()
    return cur
  }
  if (cur.section === "filters") {
    if (dy > 0 && ctx.count > 0) return atRows()
    if (dy < 0) return atTabs(ctx)
    return cur
  }
  if (dy > 0) return { section: cur.section, index: clampIndex(cur.index + 1, ctx.count) }
  if (cur.index > 0) return { section: cur.section, index: cur.index - 1 }
  if (ctx.chips.length > 0) return atFilters(ctx)
  return atTabs(ctx)
}

function moveHorizontal(cur, dx, ctx) {
  if (cur.section === "tabs") {
    var t = clampIndex(cur.index + dx, ctx.tabs.length)
    return { section: "tabs", index: t, tab: ctx.tabs[t].key }
  }
  if (cur.section === "filters" && ctx.chips.length > 0) {
    var f = clampIndex(cur.index + dx, ctx.chips.length)
    return { section: "filters", index: f, filter: ctx.chips[f].key }
  }
  if (cur.section === "rows" && ctx.activeTab === "settings")
    return { section: cur.section, index: cur.index, nudge: dx }
  return cur
}

// An arrow key: dy (up -1 / down +1) wins over dx (left -1 / right +1).
// cur: { section, index }.
function move(cur, dx, dy, ctx) {
  if (dy !== 0) return moveVertical(cur, dy, ctx)
  if (dx === 0) return cur
  return moveHorizontal(cur, dx, ctx)
}
