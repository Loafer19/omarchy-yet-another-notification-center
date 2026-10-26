import QtQuick
import "../Model.js" as Model

// Auto-hide (autoHideMs > 0): every toast is expired autoHideMs after it
// appears or last changes (Model.autoHidePlan), critical included — Omarchy
// never expires those itself. Two engines, one plan:
// - legacy (4.0): Omarchy's popupModel; toasts go through expirePopup, so
//   senders see "expired", not "dismissed by the user";
// - omapager (4.5): liveEntries (key + arrival time) and
//   closeToasts(keys, "expired"). While the deck is held open (pointer or
//   keyboard on it) nothing is closed; the 400 ms poll retries.
// Driven by changes to the toasts, a timer for the next deadline, and the
// service's 400 ms poll (note()) as backstop.
Item {
  id: hide
  visible: false

  property string engine: ""
  property real autoHideMs: 0
  // function() -> Omarchy's notification service (looked up on every use).
  property var lookup: null

  // Nothing better is there: `omarchy-shell notifications dismissAll`.
  signal dismissAll()

  property var popupModel: null
  property var toastSeen: ({})

  function service() {
    return typeof hide.lookup === "function" ? hide.lookup() : null
  }

  function perToast(n) {
    return hide.engine === "omapager" || !!(n && n.popupModel)
  }

  // A notification arrived or the setting changed.
  function schedule() {
    if (hide.perToast(hide.service())) {
      hide.note()
      return
    }
    // No popupModel (older Omarchy): hide everything autoHideMs after the
    // newest notification.
    if (hide.autoHideMs <= 0) {
      hideTimer.stop()
      return
    }
    hideTimer.interval = hide.autoHideMs
    hideTimer.restart()
  }

  function note() {
    var n = hide.service()
    if (hide.engine === "omapager") hide.noteLive(n)
    else hide.notePopups(n)
  }

  function notePopups(n) {
    var model = n && n.popupModel ? n.popupModel : null
    if (hide.popupModel !== model) hide.popupModel = model
    if (!model) {
      if (hide.autoHideMs <= 0) hideTimer.stop()
      return
    }
    var keys = []
    for (var i = 0; i < model.count; i++) keys.push(Model.toastKey(model.get(i)))
    var plan = hide.plan(keys)
    if (plan.expire.length > 0) {
      hide.expirePopups(n, plan.expire)
      Qt.callLater(hide.note)
    }
    hide.wake(plan.next)
  }

  function noteLive(n) {
    var live = Model.liveToasts(n ? n.liveEntries : [])
    var ids = []
    for (var i = 0; i < live.length; i++) ids.push(live[i].id)
    var plan = hide.plan(ids)
    var held = !!n && typeof n.holding === "function" && n.holding() === true
    if (plan.expire.length > 0 && !held) {
      var keys = []
      for (var j = plan.expire.length - 1; j >= 0; j--) keys.push(live[plan.expire[j]].key)
      hide.closeLive(n, keys)
    }
    hide.wake(plan.next)
  }

  function plan(ids) {
    var p = Model.autoHidePlan(hide.autoHideMs, ids, hide.toastSeen, Date.now())
    hide.toastSeen = p.seen
    return p
  }

  // Run note() again at the next deadline (ms from now), if any.
  function wake(next) {
    if (next >= 0) {
      hideTimer.interval = Math.max(10, Math.ceil(next))
      hideTimer.restart()
    } else {
      hideTimer.stop()
    }
  }

  function closeLive(n, keys) {
    if (n && typeof n.closeToasts === "function") {
      n.closeToasts(keys, "expired")
      return
    }
    if (n && typeof n.closeToast === "function") {
      for (var i = 0; i < keys.length; i++) n.closeToast(keys[i], "expired")
      return
    }
    hide.dismissAll()
  }

  function expirePopups(n, indexes) {
    for (var i = 0; i < indexes.length; i++) {
      var idx = indexes[i]
      if (typeof n.expirePopup === "function") n.expirePopup(idx)
      else if (typeof n.dismissPopup === "function") n.dismissPopup(idx)
      else {
        hide.dismissAll()
        return
      }
    }
  }

  // Every toast at once (no popupModel to go by).
  function hideAll() {
    var n = hide.service()
    if (n && typeof n.clearPopups === "function") {
      n.clearPopups()
      return
    }
    if (n && n.popupModel && typeof n.dismissPopup === "function") {
      var guard = 0
      while (n.popupModel.count > 0 && guard < 32) {
        n.dismissPopup(0)
        guard++
      }
      if (guard > 0) return
    }
    hide.dismissAll()
  }

  Connections {
    target: hide.popupModel
    ignoreUnknownSignals: true
    function onCountChanged() { Qt.callLater(hide.note) }
    function onDataChanged() { Qt.callLater(hide.note) }
  }

  Timer {
    id: hideTimer
    repeat: false
    onTriggered: {
      if (hide.perToast(hide.service())) hide.note()
      else hide.hideAll()
    }
  }
}
