import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Go menu system card, beside the lab card: CPU / RAM / disk / temperature /
// internet latency (ping 1.1.1.1) as meters, uptime in the header. Samples
// every 1.5s, only while `active` (menu open). Click: the btop dropdown (SUPER + I).
Item {
  id: card

  property bool active: false
  property color foreground: "white"
  property color hoverBackground: "transparent"
  property string fontFamily: ""
  property int radius: 0
  readonly property color accent: Commons.Color.pick("tablet.accent", Commons.Color.accent)
  readonly property color hot: Commons.Color.urgent

  property real cpu: -1
  property real memUsed: 0
  property real memTotal: 0
  property real swapUsed: 0
  property real diskUsed: 0
  property real diskTotal: 0
  property real temp: -1
  property int uptime: 0
  property real netMs: -2           // ping to 1.1.1.1; -1 = no reply, -2 = not sampled yet

  implicitHeight: Style.space(140)

  function parse(text) {
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].trim().split(/\s+/)
      // Two /proc/stat readings a quarter second apart, so there is a CPU
      // figure as soon as the menu opens: cpu total1 idle1 total2 idle2.
      if (f[0] === "cpu" && f.length >= 5) {
        var dTotal = Number(f[3]) - Number(f[1]), dIdle = Number(f[4]) - Number(f[2])
        if (dTotal > 0) cpu = 100 * (1 - dIdle / dTotal)
      } else if (f[0] === "mem" && f.length >= 5) {
        memTotal = Number(f[1]) * 1024
        memUsed = (Number(f[1]) - Number(f[2])) * 1024
        swapUsed = (Number(f[3]) - Number(f[4])) * 1024
      } else if (f[0] === "disk" && f.length >= 3) {
        diskTotal = Number(f[1])
        diskUsed = Number(f[2])
      } else if (f[0] === "temp" && f.length >= 2) {
        temp = Number(f[1]) / 1000
      } else if (f[0] === "up" && f.length >= 2) {
        uptime = Number(f[1])
      } else if (f[0] === "net") {
        netMs = f.length >= 2 ? Number(f[1]) : -1
      }
    }
  }

  function gib(bytes, decimals) {
    return (bytes / 1073741824).toFixed(decimals)
  }

  function formatUptime(seconds) {
    var d = Math.floor(seconds / 86400)
    var h = Math.floor(seconds % 86400 / 3600)
    var m = Math.floor(seconds % 3600 / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
  }

  Process {
    id: poll
    command: ["sh", "-c",
      // Internet ping runs alongside the rest; an empty "net" line = no reply.
      "{ echo net $(ping -c1 -W1 1.1.1.1 2>/dev/null | sed -n 's/.*time=\\([0-9.]*\\).*/\\1/p'); } & " +
      "read _ u n s i w q sq st _ < /proc/stat; t1=$((u+n+s+i+w+q+sq+st)); i1=$((i+w)); sleep 0.25; " +
      "read _ u n s i w q sq st _ < /proc/stat; echo cpu $t1 $i1 $((u+n+s+i+w+q+sq+st)) $((i+w)); " +
      "awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} /^SwapTotal/{st=$2} /^SwapFree/{sf=$2} END{print \"mem\",t,a,st,sf}' /proc/meminfo; " +
      "df -B1 --output=size,used / | tail -n1 | sed 's/^/disk /'; " +
      "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat $h/name)\" = coretemp ] && echo temp $(cat $h/temp1_input); done; " +
      "echo up $(cut -d. -f1 /proc/uptime); wait"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: card.parse(text) }
  }

  Timer {
    interval: 1500
    repeat: true
    triggeredOnStart: true
    running: card.active
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
    spacing: Style.space(7)

    // System            up 23h 46m
    Item {
      width: parent.width
      height: Style.font.body + Style.space(4)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "System"
        color: card.foreground
        opacity: 0.58
        font.family: card.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: card.uptime > 0 ? "up " + card.formatUptime(card.uptime) : "…"
        color: card.foreground
        font.family: card.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Repeater {
      model: [
        { label: "CPU", fraction: card.cpu < 0 ? 0 : card.cpu / 100,
          value: card.cpu < 0 ? "…" : Math.round(card.cpu) + "%" },
        { label: "RAM", fraction: card.memTotal > 0 ? card.memUsed / card.memTotal : 0,
          value: card.gib(card.memUsed, 1) + "/" + card.gib(card.memTotal, 0) + "G"
            + (card.swapUsed > 104857600 ? " +" + card.gib(card.swapUsed, 1) : "") },
        { label: "Disk", fraction: card.diskTotal > 0 ? card.diskUsed / card.diskTotal : 0,
          value: card.gib(card.diskUsed, 0) + "/" + card.gib(card.diskTotal, 0) + "G" },
        { label: "Temp", fraction: card.temp < 0 ? 0 : card.temp / 100,
          value: card.temp < 0 ? "–" : Math.round(card.temp) + "°" },
        // Latency against 200 ms, so it turns red past 180 ms; offline = full red bar.
        { label: "Net", fraction: card.netMs === -1 ? 1 : card.netMs < 0 ? 0 : card.netMs / 200,
          value: card.netMs === -2 ? "…" : card.netMs === -1 ? "offline" : Math.round(card.netMs) + " ms" }
      ]

      // CPU  ▬▬▬▬▬▬────────  9%
      Item {
        id: meter
        required property var modelData
        readonly property bool high: modelData.fraction >= 0.9
        width: parent.width
        height: Style.font.bodySmall + Style.space(2)

        Text {
          id: meterLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(38)
          text: meter.modelData.label
          color: card.foreground
          opacity: 0.58
          font.family: card.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          id: meterValue
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(78)
          horizontalAlignment: Text.AlignRight
          text: meter.modelData.value
          color: meter.high ? card.hot : card.foreground
          font.family: card.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          anchors.left: meterLabel.right
          anchors.right: meterValue.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(4)
          radius: height / 2
          color: Util.alpha(card.foreground, 0.12)

          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, meter.modelData.fraction))
            height: parent.height
            radius: parent.radius
            color: meter.high ? card.hot : card.accent
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
          }
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

  // The menu closes itself and toggles the btop dropdown (see Menu.qml).
  signal clicked()
}
