import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// SUPER + SHIFT + Q: xkill with a scope. The screen dims a touch and the
// cursor becomes a reticle; the window under it is outlined and labelled
// with what will go. Left click kills every process of that program
// (~/.local/bin/zap-app: TERM, then KILL after 1.5 s); right click or
// Escape cancels.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property var clients: []
  property var monitors: []
  property var target: null
  property real mx: -100
  property real my: -100

  // "pick" mode (payload {"mode":"pick"}): same scope in the accent colour;
  // a click hands the window to the scratchpad builder (or, with
  // "returnTo":"rules", the window rules page) instead of killing.
  property string mode: "zap"
  property string returnTo: "scratchpads"
  readonly property bool picking: mode === "pick"
  readonly property color coral: picking ? Commons.Color.accent : Commons.Color.urgent

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.mode = payload.mode === "pick" ? "pick" : "zap"
    root.returnTo = payload.returnTo === "rules" ? "rules" : "scratchpads"
    root.target = null
    root.clients = []
    if (!snapshot.running) snapshot.running = true
    root.opened = true
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "daa.zap")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Windows and what each monitor is showing, read once per open.
  Process {
    id: snapshot
    command: ["bash", "-c", "printf '{\"clients\":%s,\"monitors\":%s,\"cursor\":%s}' \"$(hyprctl clients -j)\" \"$(hyprctl monitors -j)\" \"$(hyprctl cursorpos -j)\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          root.clients = d.clients || []
          root.monitors = d.monitors || []
          // Start the scope where the pointer already is.
          if (d.cursor) { root.mx = d.cursor.x; root.my = d.cursor.y }
        } catch (e) {}
        root.pick()
      }
    }
  }

  // The window under (mx, my): on a shown special workspace first, then
  // floating windows, then the most recently focused.
  function pick() {
    var best = null, bestRank = 1e9
    var gx = root.mx, gy = root.my
    for (var i = 0; i < root.clients.length; i++) {
      var c = root.clients[i]
      if (!c.mapped || c.hidden || !c.at || !c.size) continue
      var onShown = false, special = false
      for (var m = 0; m < root.monitors.length; m++) {
        var mon = root.monitors[m]
        if (mon.specialWorkspace && mon.specialWorkspace.name && c.workspace.name === mon.specialWorkspace.name) { onShown = true; special = true }
        else if (mon.activeWorkspace && c.workspace.id === mon.activeWorkspace.id) onShown = true
      }
      if (!onShown) continue
      if (gx < c.at[0] || gy < c.at[1] || gx >= c.at[0] + c.size[0] || gy >= c.at[1] + c.size[1]) continue
      var rank = (special ? 0 : 1000) + (c.floating ? 0 : 500) + (c.focusHistoryID >= 0 ? c.focusHistoryID : 400)
      if (rank < bestRank) { bestRank = rank; best = c }
    }
    if (best) {
      var same = 0
      for (var j = 0; j < root.clients.length; j++) if (root.clients[j].pid === best.pid || root.clients[j].class === best.class) same++
      best = { pid: best.pid, cls: best.class, title: best.title, x: best.at[0], y: best.at[1], w: best.size[0], h: best.size[1], windows: same }
    }
    root.target = best
  }

  function nameOf(t) {
    if (!t) return ""
    var app = DesktopEntries.heuristicLookup(t.cls)
    return app ? String(app.name) : String(t.cls || t.title || "this program")
  }

  function fire() {
    if (!root.target) return
    var t = root.target
    root.dismiss()
    if (root.picking) {
      Quickshell.execDetached(["bash", "-c", "mkdir -p ~/.local/state/daa; ~/.local/bin/scratch-tool window \"$1\" > ~/.local/state/daa/picked.json; " +
        "omarchy-shell shell summon daa.settings \"{\\\"page\\\":\\\"$2\\\",\\\"picked\\\":true}\"", "--", String(t.pid), root.returnTo])
      return
    }
    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/zap-app", String(t.pid), root.nameOf(t)])
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-zap"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.18) }

    Item {
      id: keys
      focus: true
      Keys.onEscapePressed: root.dismiss()
    }

    // The target window, outlined.
    Rectangle {
      visible: !!root.target
      x: root.target ? root.target.x - (panel.screen ? panel.screen.x : 0) : 0
      y: root.target ? root.target.y - (panel.screen ? panel.screen.y : 0) : 0
      width: root.target ? root.target.w : 0
      height: root.target ? root.target.h : 0
      color: Util.alpha(root.coral, 0.08)
      border.width: 2
      border.color: root.coral
      radius: 6
    }

    // Reticle: ring, gap crosshair, centre dot.
    Item {
      id: reticle
      x: root.mx - (panel.screen ? panel.screen.x : 0)
      y: root.my - (panel.screen ? panel.screen.y : 0)
      readonly property real r: 18
      Rectangle {
        x: -reticle.r; y: -reticle.r
        width: reticle.r * 2; height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: root.coral
      }
      Repeater {
        model: [[1, 0], [-1, 0], [0, 1], [0, -1]]
        Rectangle {
          required property var modelData
          readonly property bool horiz: modelData[1] === 0
          width: horiz ? 12 : 2
          height: horiz ? 2 : 12
          x: horiz ? (modelData[0] > 0 ? 8 : -20) : -1
          y: horiz ? -1 : (modelData[1] > 0 ? 8 : -20)
          color: root.coral
        }
      }
      Rectangle { x: -2; y: -2; width: 4; height: 4; radius: 2; color: root.coral }

      // What goes if you click.
      Rectangle {
        visible: !!root.target
        x: 26
        y: 14
        width: label.implicitWidth + 18
        height: label.implicitHeight + 10
        radius: 8
        color: Util.alpha(Commons.Color.background, 0.92)
        border.width: 1
        border.color: root.coral
        Text {
          id: label
          anchors.centerIn: parent
          text: !root.target ? ""
            : root.picking ? "pick " + root.nameOf(root.target) + "  ·  " + root.target.cls
            : "kill " + root.nameOf(root.target) + (root.target.windows > 1 ? "  ·  all " + root.target.windows + " windows" : "")
          color: Commons.Color.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.BlankCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      function track(mouse) {
        root.mx = mouse.x + (panel.screen ? panel.screen.x : 0)
        root.my = mouse.y + (panel.screen ? panel.screen.y : 0)
        root.pick()
      }
      onPositionChanged: function(mouse) { track(mouse) }
      onClicked: function(mouse) {
        track(mouse)
        if (mouse.button === Qt.RightButton) root.dismiss()
        else root.fire()
      }
    }
  }
}
