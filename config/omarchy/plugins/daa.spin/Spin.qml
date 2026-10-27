import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Turn the tablet all the way round (tablet-mode autorotate spots four
// quarter-turns the same way in a few seconds):
//   clockwise          "dizzy": the zedonk, hypnotised, spinning, stars
//   counter-clockwise  "crash": the bar's icons fall off and pile up at the
//                      bottom, drop through it, and comets burst up from
//                      the bottom edge; then the bar rebuilds itself
//                      (the old VHS rewind is in config-backups/daa.spin-Spin.qml.rewind)
// Click-through, a few seconds, then gone. Deliberately not in any menu.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string mode: "dizzy"
  property real t: 0          // seconds since it started

  readonly property real length: root.mode === "dizzy" ? 4.6 : 6.0
  readonly property color accent: Commons.Color.pick("tablet.accent", Commons.Color.accent)
  readonly property color coral: Commons.Color.urgent

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.mode = payload.mode === "crash" || payload.mode === "rewind" ? "crash" : "dizzy"
    root.t = 0
    root.skipAt = -1
    root.startTime = new Date()
    root.barRect = null
    if (root.mode === "crash") {
      // An open tablet greeter tips over and its tiles flutter down too.
      Quickshell.execDetached(["omarchy-shell", "-q", "daa.tablet-greeter", "fall"])
      // Find the bar first, then freeze the screen and start.
      barProbe.running = true
    } else root.opened = true
  }
  function close() { root.opened = false }
  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "daa.spin")
  }

  property date startTime: new Date()

  // A double tap anywhere skips out: a quick fade, and an open greeter
  // that's mid-fall is put away too.
  property real skipAt: -1
  function skip() {
    if (!root.opened || root.skipAt >= 0) return
    root.skipAt = root.t
    Quickshell.execDetached(["omarchy-shell", "-q", "daa.tablet-greeter", "endFall"])
  }
  readonly property real skipFade: root.skipAt < 0 ? 1 : Math.max(0, 1 - (root.t - root.skipAt) / 0.25)
  IpcHandler {
    target: "daa.spin"
    function stop(): void { root.skip() }
  }
  FrameAnimation {
    running: root.opened
    onTriggered: {
      root.t += frameTime
      if (root.t > root.length || root.skipFade <= 0) root.dismiss()
    }
  }
  // Fade in over 0.3 s, out over the last 0.5 s.
  readonly property real fade: Math.min(1, root.t / 0.3, Math.max(0, (root.length - root.t) / 0.5))

  // ---- Crash: where the bar is, cut into icon-sized pieces ----
  property var barRect: null
  Process {
    id: barProbe
    command: ["bash", "-c", "hyprctl layers -j | jq -c '[.. | objects | select(.namespace? == \"omarchy-bar\")] | max_by(.w * .h) // empty'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.barRect = JSON.parse(text) } catch (e) { root.barRect = null }
        root.opened = true
      }
    }
  }
  readonly property bool barVertical: !!root.barRect && root.barRect.h > root.barRect.w
  readonly property real pieceSize: root.barRect ? Math.min(root.barRect.w, root.barRect.h) : 0
  readonly property var pieces: {
    var out = []
    if (!root.barRect || root.pieceSize < 4) return out
    var b = root.barRect, n = Math.floor((root.barVertical ? b.h : b.w) / root.pieceSize)
    for (var i = 0; i < n; i++) {
      var x = root.barVertical ? b.x : b.x + i * root.pieceSize
      var y = root.barVertical ? b.y + i * root.pieceSize : b.y
      // Pseudo-random but stable per piece.
      var r1 = Math.abs(Math.sin(i * 12.9898) * 43758.5453) % 1
      var r2 = Math.abs(Math.sin(i * 78.233) * 12543.1234) % 1
      out.push({ x: x, y: y, delay: 0.05 + r1 * 0.55, spin: (r2 - 0.5) * 900, drift: (r1 - 0.5) * 160 })
    }
    return out
  }
  // Seconds: icons fall until ~1.5, the floor cracks at 1.5, breaks at 2.1.
  readonly property real crackAt: 1.5
  readonly property real breakAt: 2.1
  readonly property real gravity: 2600

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "daa-spin"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Takes the screen for the few seconds it runs; a double tap skips.
    MouseArea { anchors.fill: parent; onDoubleClicked: root.skip() }

    // ---------------- Dizzy (clockwise) ----------------
    Item {
      anchors.fill: parent
      visible: root.mode === "dizzy"
      opacity: root.fade * root.skipFade

      Rectangle { anchors.fill: parent; color: "black"; opacity: 0.45 }

      // The zedonk wobbles round, slowing down as it gets its bearings.
      Item {
        id: zed
        anchors.centerIn: parent
        width: face.implicitWidth
        height: face.implicitHeight
        rotation: 26 * Math.sin(root.t * 5.2) * Math.max(0.15, 1 - root.t / 4)
        scale: 1 + 0.06 * Math.sin(root.t * 3.1)
        Text {
          id: face
          anchors.centerIn: parent
          textFormat: Text.PlainText
          color: "white"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: Math.round(panel.height / 26)
          lineHeight: 0.95
          // The eyes spin: @ / o / @ / O.
          readonly property string eye: ["@", "o", "@", "O"][Math.floor(root.t * 7) % 4]
          text: " ___                ___ \n" +
                "(___\\______________/___)\n" +
                "     \\             /     \n" +
                "      |  " + eye + "     " + eye + "  |      \n" +
                "      |           |      \n" +
                "      |           |      \n" +
                "      |           |      \n" +
                "      |           |      \n" +
                "     /  (o)   (o)  \\     \n" +
                "     \\     ~~~     /     \n" +
                "      \\___________/      "
        }
        // Stars and birds circling the ears.
        Repeater {
          model: 5
          Text {
            required property int index
            readonly property real a: root.t * 4.2 + index * 2 * Math.PI / 5
            x: zed.width / 2 + Math.cos(a) * zed.width * 0.62 - width / 2
            y: -zed.height * 0.06 + Math.sin(a) * zed.height * 0.13 - height / 2
            text: ["✦", "★", "✧", "♪", "✶"][index]
            color: [root.accent, "#e0af68", "white", root.coral, "#9ece6a"][index]
            font.pixelSize: Math.round(panel.height / 22)
            scale: 0.8 + 0.4 * (Math.sin(a) + 1) / 2
          }
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: zed.bottom
        anchors.topMargin: panel.height * 0.05
        text: root.t < 2.6 ? "w h e e e e !" : "...again?"
        color: root.t < 2.6 ? root.accent : "white"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: Math.round(panel.height / 18)
        font.bold: root.t < 2.6
        rotation: root.t < 2.6 ? 6 * Math.sin(root.t * 9) : 0
      }
    }

    // ---------------- Crash (counter-clockwise) ----------------
    Item {
      id: crash
      anchors.fill: parent
      visible: root.mode === "crash"
      opacity: root.skipFade
      readonly property real floorY: panel.height
      // Where the pile lands: under the bar (or the screen's middle).
      readonly property real impactX: root.barRect ? (root.barVertical ? root.barRect.x + root.barRect.w / 2 : panel.width / 2) : panel.width / 2
      readonly property bool broken: root.t >= root.breakAt
      // The ending: the hole seals (3.7-4.3 s) and the pieces fly back up
      // into the bar (4.0-5.4 s); the cover fades as the last one lands.
      readonly property real sealAt: 3.7
      readonly property real rebuildAt: 4.0
      readonly property real seal: Math.max(0, Math.min(1, (root.t - sealAt) / 0.6))

      // The screen as it was, frozen; the bar's pieces are cut from it (the
      // capture itself never shows: the live screen, greeter and all, stays).
      ScreencopyView {
        id: frozen
        anchors.fill: parent
        captureSource: root.opened && root.mode === "crash" ? panel.screen : null
        live: false
      }
      // Where the bar was: just the wallpaper's dark.
      Rectangle {
        visible: !!root.barRect && frozen.hasContent
        x: root.barRect ? root.barRect.x : 0
        y: root.barRect ? root.barRect.y : 0
        width: root.barRect ? root.barRect.w : 0
        height: root.barRect ? root.barRect.h : 0
        color: "#08080c"
        opacity: Math.min(1, root.t / 0.15) * Math.max(0, Math.min(1, (5.6 - root.t) / 0.3))
      }

      // The pieces: fall, tumble, pile up on the floor; through it once broken.
      Repeater {
        model: frozen.hasContent ? root.pieces : []
        ShaderEffectSource {
          id: piece
          required property var modelData
          required property int index
          readonly property real s: root.pieceSize
          readonly property real ft: Math.max(0, root.t - modelData.delay)
          // Rest height on the pile: a loose heap around the impact point.
          readonly property real restY: crash.floorY - s * (1 + (index % 4) * 0.55)
          readonly property real fallY: modelData.y + 0.5 * root.gravity * ft * ft
          readonly property real landed: Math.min(fallY, restY)
          readonly property real throughY: crash.broken ? 0.5 * root.gravity * Math.pow(root.t - root.breakAt, 2) * 1.4 : 0
          sourceItem: frozen
          hideSource: true
          sourceRect: Qt.rect(modelData.x, modelData.y, s, s)
          width: s
          height: s
          // Back home: from just below the screen, overshooting a touch.
          readonly property real bt: Math.max(0, Math.min(1, (root.t - crash.rebuildAt - modelData.delay * 0.6) / 0.75))
          readonly property real back: bt <= 0 ? 0 : 1 + 2.2 * Math.pow(bt - 1, 3) + 1.2 * Math.pow(bt - 1, 2)
          readonly property real fallRot: fallY < restY ? modelData.spin * ft : modelData.spin * 0.12 + (crash.broken ? modelData.spin * (root.t - root.breakAt) : 0)
          x: bt > 0 ? modelData.x + (1 - back) * modelData.drift : modelData.x + modelData.drift * Math.min(1, ft * 1.4)
          y: bt > 0 ? (panel.height + s) + (modelData.y - panel.height - s) * back : landed + throughY
          rotation: bt > 0 ? (1 - back) * modelData.spin * 0.5 : fallRot
          visible: y < panel.height + s
        }
      }

      // Comets bursting up from the bottom edge (where the pile went through):
      // white heads, coloured tails, arcing back down. (The cracked-ground
      // version is in config-backups/daa.spin-Spin.qml.with-cracks.)
      Canvas {
        anchors.fill: parent
        property real t: root.t
        onTChanged: if (crash.broken && crash.seal < 1.05) requestPaint()
        readonly property var comets: {
          var out = []
          var cols = [root.accent, root.coral, "#9ece6a", "#bb9af7", "#e0af68", "#ff9e64", "#73daca", "#7aa2f7"]
          for (var k = 0; k < 14; k++) {
            var r = Math.abs(Math.sin(k * 45.164) * 1000) % 1
            var r2 = Math.abs(Math.sin(k * 17.37) * 1000) % 1
            // Mostly up and into the screen (away from the bar's edge).
            var ang = -Math.PI / 2 + (r - 0.62) * 1.9
            var speed = 1500 + r2 * 900
            out.push({ vx: Math.cos(ang) * speed, vy: Math.sin(ang) * speed, at: k * 0.07 + r * 0.25,
                       dx: (r2 - 0.5) * 220, col: cols[k % cols.length] })
          }
          return out
        }
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          if (!crash.broken) return
          var g = 1500
          for (var k = 0; k < comets.length; k++) {
            var c = comets[k], lt = root.t - root.breakAt - c.at
            if (lt <= 0) continue
            var x0 = crash.impactX + c.dx, y0 = crash.floorY - 30
            var col = Qt.color(c.col), steps = 16, span = 0.16
            for (var i = 0; i < steps; i++) {
              var t0 = Math.max(0, lt - span * i / steps), t1 = Math.max(0, lt - span * (i + 1) / steps)
              var ax = x0 + c.vx * t0, ay = y0 + c.vy * t0 + 0.5 * g * t0 * t0
              var bx = x0 + c.vx * t1, by = y0 + c.vy * t1 + 0.5 * g * t1 * t1
              var a = Math.pow(1 - i / steps, 1.5) * (1 - crash.seal)
              ctx.strokeStyle = i < 2 ? "rgba(255,255,255," + a + ")" : Qt.rgba(col.r, col.g, col.b, a)
              ctx.lineWidth = 6 * (1 - i / steps) + 1
              ctx.lineCap = "round"
              ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.stroke()
            }
          }
        }
      }
    }
  }
}
