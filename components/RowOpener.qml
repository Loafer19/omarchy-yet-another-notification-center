import QtQuick
import Quickshell.Io
import "../Model.js" as Model

// What clicking a History row does (settings "Clicking a notification"):
// open its picture, run the sender's default action while the toast is up
// (4.5), focus the app, or open its web address. Problems show on the row
// (list.itemAtIndex(index).showNotice); success closes the panel.
Item {
  id: opener
  visible: false

  property var store: null
  property var cfg: ({})
  property string omarchyPath: ""

  signal closeRequested()

  property var pendingFocus: null
  // xdg-open may stay up as long as the viewer does: close the panel once it
  // has run for a moment or exited cleanly; a quick non-zero exit keeps the
  // panel open and says so on the row.
  property var pendingOpen: null

  function flashNotice(list, index, title, detail) {
    var wrap = list && list.itemAtIndex ? list.itemAtIndex(index) : null
    if (wrap && wrap.showNotice) wrap.showNotice(title, detail)
  }

  function activateAt(list, index, row) {
    if (!row) {
      opener.flashNotice(list, index, "Can't open", "")
      return
    }
    var who = Model.noticeIdentity(row)
    var action = String(opener.cfg.clickAction || "Auto")
    if (action === "Nothing") {
      opener.flashNotice(list, index, "Clicks are off", who)
      return
    }
    if (action === "Auto" && Model.isStoreImage(row.preview || row.file)) {
      const openPath = Model.storeImageUrl(row.preview || row.file).replace(/^file:\/\//, "")
      if (!openPath || openPath.charAt(0) !== "/" || openPath.indexOf("..") >= 0) {
        opener.flashNotice(list, index, "Can't open", who)
        return
      }
      opener.openPicture(list, index, who, openPath)
      return
    }
    // Omarchy 4.5, toast still up: what clicking the toast does for the
    // sender (its "default" D-Bus action), which closes it like a click would.
    var s = opener.store
    if (action === "Auto" && s && typeof s.invokeLive === "function" && s.invokeLive(row.key, "default")) {
      opener.closeRequested()
      return
    }
    if (!opener.omarchyPath) {
      if (!opener.openLink(list, index, row)) opener.flashNotice(list, index, "Can't open", who)
      return
    }
    if (!Model.isSafeAppName(row.app)) {
      if (opener.openLink(list, index, row)) return
      opener.flashNotice(list, index, String(row.app || "").length ? "Can't open" : "No app to open", who)
      return
    }
    opener.pendingFocus = { list: list, index: index, row: row }
    focusProc.running = false
    focusProc.command = [opener.omarchyPath + "/bin/omarchy-hyprland-focus-app", row.app]
    focusProc.running = true
  }

  // The row's web address (Omarchy 4.5: from its text or the site a browser
  // notification came from), when the app can't be focused. Auto only.
  function openLink(list, index, row) {
    if (String(opener.cfg.clickAction || "Auto") !== "Auto") return false
    var url = Model.safeLink(row ? row.link : "")
    if (!url) return false
    opener.openPicture(list, index, Model.noticeIdentity(row), url)
    return true
  }

  function openPicture(list, index, who, path) {
    var s = opener.store
    if (!s) return
    var token = { settled: false }
    opener.pendingOpen = token
    openSettle.restart()
    s.run("open", ["xdg-open", path], function(res) {
      if (opener.pendingOpen === token) { opener.pendingOpen = null; openSettle.stop() }
      if (res.ok) {
        if (!token.settled) opener.closeRequested()
        return
      }
      if (!token.settled) opener.flashNotice(list, index, "Can't open", who)
    })
  }

  function copyRow(list, index, row) {
    var s = opener.store
    if (!row || !s) return
    var text = Model.copyTextFor(row)
    if (!text) return
    // The text goes to wl-copy on stdin, not in argv: wl-copy's background
    // clipboard owner would keep argv in /proc/<pid>/cmdline, readable by
    // other local users.
    s.run("copy", ["wl-copy", "--type", "text/plain;charset=utf-8"], function(res) {
      var wrap = list && list.itemAtIndex ? list.itemAtIndex(index) : null
      if (wrap && wrap.copyFinished) wrap.copyFinished(res.ok, res.error)
    }, text)
  }

  Process {
    id: focusProc
    onExited: function(exitCode) {
      var pending = opener.pendingFocus
      opener.pendingFocus = null
      if (exitCode === 0) {
        opener.closeRequested()
        return
      }
      if (!pending) return
      if (opener.openLink(pending.list, pending.index, pending.row)) return
      opener.flashNotice(pending.list, pending.index, "No window", Model.noticeIdentity(pending.row))
    }
  }

  Timer {
    id: openSettle
    interval: 700
    onTriggered: if (opener.pendingOpen) { opener.pendingOpen.settled = true; opener.closeRequested() }
  }
}
