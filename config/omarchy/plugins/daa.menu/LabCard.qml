import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Go menu lab card: is the lab box up, how fast, is GNS3 serving, and are
// Tailscale / Mullvad on. Polls ~/.local/bin/lab-status (which reads the lab
// address from the Remmina profile) every 2s: the full check while `active`
// (menu open), just the heartbeat otherwise, so the sparkline always holds the
// last minute. The heartbeat is a `tailscale ping` to the lab, so it measures
// the tailnet link itself (internet latency is on the system card).
// Click: open VNC.
Item {
  id: card

  property bool active: false
  property color foreground: "white"
  property color hoverBackground: "transparent"
  property string fontFamily: ""
  property int radius: 0
  readonly property color accent: Commons.Color.pick("tablet.accent", Commons.Color.accent)
  readonly property color down: Commons.Color.urgent

  property var status: null
  property var samples: []        // last 30 tailscale pings in ms (null = no reply)
  readonly property bool labUp: !!status && status.lab !== null

  implicitHeight: Style.space(110)

  function record(json) {
    var next
    try { next = JSON.parse(json) } catch (e) { return }
    var wasKnown = card.status !== null, wasUp = card.labUp
    var list = card.samples.slice()
    list.push(next.lab)
    if (list.length > 30) list.shift()
    card.samples = list
    // Ping-only samples refresh the latency but keep the last full status.
    var merged = Object.assign({}, card.status || {}, next)
    card.status = merged
    if (!card.active) return
    // Comets: one runs the heartbeat line with each reply; the lab going
    // down or coming back sends two round the card.
    if (next.lab !== null && next.lab !== undefined) spark.pulse = 0
    if (wasKnown && wasUp !== card.labUp) lap.start()
  }

  Process {
    id: poll
    command: card.active ? [Quickshell.env("HOME") + "/.local/bin/lab-status"]
      : [Quickshell.env("HOME") + "/.local/bin/lab-status", "ping"]
    stdout: SplitParser { onRead: function(line) { card.record(line) } }
  }

  Timer {
    interval: 2000
    repeat: true
    triggeredOnStart: true
    running: true
    onTriggered: if (!poll.running) poll.running = true
  }

  Rectangle {
    anchors.fill: parent
    radius: card.radius
    color: area.containsMouse ? card.hoverBackground : "transparent"
    border.width: Style.spacing.hairline
    border.color: Util.alpha(card.foreground, 0.15)
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(6)

    // Lab ● 23 ms
    Item {
      width: parent.width
      height: Style.font.body + Style.space(4)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Lab"
        color: card.foreground
        opacity: 0.58
        font.family: card.fontFamily
        font.pixelSize: Style.font.body
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(7)
          height: width
          radius: width / 2
          color: !card.status ? Util.alpha(card.foreground, 0.3) : (card.labUp ? card.accent : card.down)
        }
        Text {
          text: !card.status ? "checking…"
            // "direct" once NAT traversal has a path, else the DERP relay region.
            : card.labUp ? (card.status.route === "direct" ? "tailscale direct"
                : "tailscale DERP " + card.status.route) + ": " + Math.round(card.status.lab) + " ms"
            : "offline"
          color: card.foreground
          font.family: card.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    // Heartbeat sparkline.
    Item {
      width: parent.width
      height: Style.space(26)

      Canvas {
        id: spark
        anchors.fill: parent
        property var points: card.samples
        property color line: card.accent
        // Heartbeat comet: 0..1 along the line (left to the newest reply), -1 = none.
        property real pulse: -1
        FrameAnimation {
          running: spark.pulse >= 0
          onTriggered: {
            spark.pulse += frameTime / 0.85
            if (spark.pulse > 1.25) spark.pulse = -1
            spark.requestPaint()
          }
        }
        onPointsChanged: requestPaint()
        onLineChanged: requestPaint()
        onWidthChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var pts = points || []
          if (pts.length < 2) return
          // Scaled against at least 80 ms, so a steady low latency rides low
          // instead of filling the box; spikes still reach the top.
          var max = 80
          for (var i = 0; i < pts.length; i++) if (pts[i] !== null && pts[i] * 1.2 > max) max = pts[i] * 1.2
          var step = width / 29
          var x0 = width - (pts.length - 1) * step
          var top = 3, bottom = height - 3
          ctx.lineWidth = 1.5
          ctx.lineJoin = "round"
          ctx.strokeStyle = line
          ctx.beginPath()
          var drawing = false
          for (var j = 0; j < pts.length; j++) {
            var x = x0 + j * step
            if (pts[j] === null) {
              // A lost ping: a mark on the floor, and break the line.
              ctx.fillStyle = card.down
              ctx.fillRect(x - 1, bottom - 2, 2, 2)
              drawing = false
              continue
            }
            var y = bottom - (pts[j] / max) * (bottom - top)
            if (drawing) ctx.lineTo(x, y)
            else ctx.moveTo(x, y)
            drawing = true
          }
          ctx.stroke()

          if (pulse < 0) return
          // The comet: along the replies' points, white head, accent tail.
          var poly = []
          for (var m = 0; m < pts.length; m++)
            if (pts[m] !== null) poly.push({ x: x0 + m * step, y: bottom - (pts[m] / max) * (bottom - top) })
          if (poly.length < 2) return
          var lens = [0]
          for (var q = 1; q < poly.length; q++) lens.push(lens[q - 1] + Math.hypot(poly[q].x - poly[q - 1].x, poly[q].y - poly[q - 1].y))
          var total = lens[lens.length - 1]
          function pointAt(d) {
            d = Math.max(0, Math.min(total, d))
            for (var z = 1; z < poly.length; z++) if (lens[z] >= d) {
              var f = (d - lens[z - 1]) / Math.max(0.001, lens[z] - lens[z - 1])
              return { x: poly[z - 1].x + (poly[z].x - poly[z - 1].x) * f, y: poly[z - 1].y + (poly[z].y - poly[z - 1].y) * f }
            }
            return poly[poly.length - 1]
          }
          var k = Math.min(1, pulse), ease = 1 - Math.pow(1 - k, 2)
          var head = ease * total, trail = Math.min(head, total * 0.3), steps = 18
          var fade = pulse <= 1 ? 1 : Math.max(0, 1 - (pulse - 1) / 0.25)
          ctx.lineCap = "round"
          for (var a = 0; a < steps; a++) {
            var p0 = pointAt(head - trail * a / steps), p1 = pointAt(head - trail * (a + 1) / steps)
            var al = fade * Math.pow(1 - a / steps, 1.5)
            ctx.strokeStyle = a < 2 ? Qt.rgba(1, 1, 1, al) : Qt.rgba(line.r, line.g, line.b, al)
            ctx.lineWidth = 3 * (1 - a / steps) + 1
            ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(p1.x, p1.y); ctx.stroke()
          }
        }
      }

    }

    // Its own line, so the trace never runs over it.
    Item {
      width: parent.width
      height: Style.font.bodySmall + Style.space(2)

      StatusDot {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        label: card.status && card.status.gns3 ? "GNS3 " + card.status.gns3 : "GNS3"
        on: !!(card.status && card.status.gns3)
      }
    }

    // ● Tailscale   ○ Mullvad
    Row {
      spacing: Style.space(14)

      StatusDot { label: "Tailscale"; on: !!(card.status && card.status.tailscale) }
      StatusDot { label: "Mullvad"; on: !!(card.status && card.status.mullvad) }
    }
  }

  // ● label: filled accent dot when on, hollow and dimmed when off.
  component StatusDot: Row {
    property string label: ""
    property bool on: false
    spacing: Style.space(5)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(6)
      height: width
      radius: width / 2
      color: parent.on ? card.accent : "transparent"
      border.width: parent.on ? 0 : 1
      border.color: Util.alpha(card.foreground, 0.45)
    }
    Text {
      text: parent.label
      color: card.foreground
      opacity: parent.on ? 1 : 0.58
      font.family: card.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Two comets once round the card when the lab goes down (coral) or comes
  // back (accent).
  Canvas {
    id: lap
    anchors.fill: parent
    property real t: -1
    readonly property real dur: 1.4
    function start() { t = 0; requestPaint() }
    FrameAnimation {
      running: lap.t >= 0
      onTriggered: {
        lap.t += frameTime
        if (lap.t > lap.dur + 0.3) lap.t = -1
        lap.requestPaint()
      }
    }
    // s along the rounded outline, clockwise from the top-left corner's end.
    function at(s) {
      var w = width, h = height, r = Math.min(card.radius, w / 2, h / 2)
      var sw = w - 2 * r, sh = h - 2 * r, arc = Math.PI * r / 2
      var P = 2 * sw + 2 * sh + 4 * arc
      s = ((s % P) + P) % P
      var segs = [
        function(u) { return { x: r + u, y: 0 } }, sw,
        function(u) { var a = -Math.PI / 2 + u / Math.max(r, 0.001); return { x: w - r + r * Math.cos(a), y: r + r * Math.sin(a) } }, arc,
        function(u) { return { x: w, y: r + u } }, sh,
        function(u) { var a = u / Math.max(r, 0.001); return { x: w - r + r * Math.cos(a), y: h - r + r * Math.sin(a) } }, arc,
        function(u) { return { x: w - r - u, y: h } }, sw,
        function(u) { var a = Math.PI / 2 + u / Math.max(r, 0.001); return { x: r + r * Math.cos(a), y: h - r + r * Math.sin(a) } }, arc,
        function(u) { return { x: 0, y: h - r - u } }, sh,
        function(u) { var a = Math.PI + u / Math.max(r, 0.001); return { x: r + r * Math.cos(a), y: r + r * Math.sin(a) } }, arc
      ]
      for (var i = 0; i < segs.length; i += 2) {
        if (s <= segs[i + 1]) return segs[i](s)
        s -= segs[i + 1]
      }
      return { x: r, y: 0 }
    }
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (t < 0) return
      var r = Math.min(card.radius, width / 2, height / 2)
      var P = 2 * (width - 2 * r) + 2 * (height - 2 * r) + 2 * Math.PI * r
      var k = Math.min(1, t / dur), head = (1 - Math.pow(1 - k, 3)) * P
      var fade = Math.min(1, t / 0.12) * Math.max(0, 1 - Math.max(0, t - dur * 0.7) / (dur * 0.3 + 0.3))
      var trail = Math.min(head, P * 0.18), steps = 24
      var col = card.labUp ? card.accent : card.down
      ctx.lineCap = "round"
      for (var c = 0; c < 2; c++) {
        var base = c * P / 2
        for (var i = 0; i < steps; i++) {
          var p0 = at(base + head - trail * i / steps), p1 = at(base + head - trail * (i + 1) / steps)
          var al = fade * Math.pow(1 - i / steps, 1.6)
          ctx.strokeStyle = i < 2 ? Qt.rgba(1, 1, 1, al) : Qt.rgba(col.r, col.g, col.b, al)
          ctx.lineWidth = 2.5 * (1 - i / steps) + 0.8
          ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(p1.x, p1.y); ctx.stroke()
        }
      }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: card.clicked()
  }

  // The menu closes itself and opens VNC (see Menu.qml).
  signal clicked()
}
