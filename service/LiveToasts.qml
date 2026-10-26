pragma ComponentBehavior: Bound

import QtQuick
import "../Model.js" as Model

// Omarchy 4.5: pictures and sender actions of live toasts.
// history.json keeps no pictures and a sender's actions die with its
// notification, so both are only there while the toast is.
// Omapager publishes the live Notification objects as refs (key -> object)
// and bumps refsRevision the moment one arrives, before it stores the row or
// lets a silenced one go. Then the picture is drawn once into host (a 0x0
// clipped item in the bar's window: the service has none), grabbed, and
// saved as captures/KEY.png once the stored row shows it is not a redacted
// secret; filed(KEY) then has `backend.sh capture KEY` file it.
Item {
  id: capture
  visible: false

  property var engineService: null
  property bool active: false          // engine is omapager
  property bool pictures: true         // showPreview: capture pictures
  property Item host: null
  property string storeDir: ""

  property var seen: ({})
  property var shots: ({})
  function hasShots() {
    for (var k in capture.shots) return true
    return false
  }

  signal filed(string key)

  function liveRef(key) {
    var s = capture.engineService
    if (!capture.active || !s || !s.refs || !Model.isSafeKey(key)) return null
    return s.refs[key] || null
  }

  // Run a sender action of a live toast (D-Bus ActionInvoked, through
  // Omapager, which then closes the toast). false when it is gone.
  function invoke(key, id) {
    var s = capture.engineService
    if (!s || typeof s.invokeAction !== "function") return false
    if (!Model.hasLiveAction(capture.liveRef(key), String(id))) return false
    s.invokeAction(String(key), String(id))
    return true
  }

  function captureLive() {
    var s = capture.engineService
    if (!capture.active || !s || !s.refs) return
    var refs = s.refs
    var live = {}
    for (var key in refs) {
      live[key] = true
      if (capture.seen[key]) continue
      capture.seen[key] = true
      if (!capture.pictures || !capture.host || !Model.isSafeKey(key)) continue
      var ref = refs[key]
      var src = Model.captureSource(ref ? ref.image : "")
      if (!src) continue
      var shot = captureImage.createObject(capture.host, { key: key, source: src })
      if (shot) shot.grab()
    }
    for (var old in capture.seen)
      if (!live[old]) delete capture.seen[old]
  }

  // Save grabbed pictures whose rows are stored; drop redacted ones and any
  // whose row never turned up.
  function fileShots() {
    var s = capture.engineService
    var now = Date.now()
    for (var key in capture.shots) {
      var shot = capture.shots[key]
      var verdict = s ? Model.captureVerdict(key, s.liveEntries, s.historyEntries) : "drop"
      if (verdict === "wait" && now - shot.at < 120000) continue
      delete capture.shots[key]
      if (verdict !== "save") continue
      if (!shot.result.saveToFile(capture.storeDir + "/captures/" + key + ".png")) {
        console.warn("yoyo.notification-center: could not save the picture of " + key)
        continue
      }
      capture.filed(key)
    }
  }

  Component {
    id: captureImage
    Image {
      id: shot
      property string key: ""
      property bool grabbing: false
      asynchronous: false
      cache: false
      smooth: true
      fillMode: Image.PreserveAspectFit
      function grab() {
        if (shot.grabbing || shot.status === Image.Loading) return
        shot.grabbing = true
        var size = Model.fitSize(shot.implicitWidth, shot.implicitHeight, 512)
        if (shot.status !== Image.Ready || !size.width) { shot.destroy(); return }
        shot.width = size.width
        shot.height = size.height
        var key = shot.key
        var started = shot.grabToImage(function(result) {
          capture.shots[key] = { result: result, at: Date.now() }
          shot.destroy()
          Qt.callLater(capture.fileShots)
        }, Qt.size(size.width, size.height))
        if (!started) shot.destroy()
      }
      onStatusChanged: if (shot.status !== Image.Loading) shot.grab()
    }
  }
}
