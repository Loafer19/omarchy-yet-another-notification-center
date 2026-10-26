// Offscreen panel harness for tools/render-previews.sh: the real Service.qml
// and Panel.qml on the made-up store from tests/preview/fixture.sh.
// PREVIEW_TAB / PREVIEW_SUB pick the view; the card is saved to PREVIEW_OUT.
import QtQuick
import Quickshell
import qs.Commons as Commons
import "plugin" as N

ShellRoot {
  id: shell
  property string tab: Quickshell.env("PREVIEW_TAB") || "history"
  property string sub: Quickshell.env("PREVIEW_SUB") || ""
  property string out: Quickshell.env("PREVIEW_OUT") || ""

  N.Service { id: svc }

  QtObject {
    id: fakeBar
    property color barForeground: Commons.Color.foreground
    property color foreground: Commons.Color.foreground
    property string fontFamily: Commons.Style.font.family
    property bool vertical: false
    property int barSize: 30
    property bool urgent: false
    property bool foregroundAnimationEnabled: false
    property QtObject shell: QtObject { function serviceFor(n) { return svc } }
    function showTooltip() {}
    function hideTooltip() {}
  }

  FloatingWindow {
    implicitWidth: 1100
    implicitHeight: 1300
    color: "transparent"
    N.Panel { id: panel; bar: fakeBar; anchors.fill: parent }
  }

  Timer {
    interval: 2500; running: true
    onTriggered: {
      panel.open()
      panel.activeTab = shell.tab
      if (shell.sub) panel.applyFilterKey(shell.sub)
      grab.start()
    }
  }
  Timer {
    id: grab; interval: 1500
    onTriggered: {
      var kp = panel.children.filter(function(c) { return c.card !== undefined })[0]
      kp.card.grabToImage(function(r) {
        r.saveToFile(shell.out)
        console.log("saved", shell.out, kp.card.width, kp.card.height)
        Qt.quit()
      })
    }
  }
}
