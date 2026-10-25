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
    var list = card.samples.slice()
    list.push(next.lab)
    if (list.length > 30) list.shift()
    card.samples = list
    // Ping-only samples refresh the latency but keep the last full status.
    var merged = Object.assign({}, card.status || {}, next)
    card.status = merged
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
