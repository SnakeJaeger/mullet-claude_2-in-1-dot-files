import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// Pending package updates (checkupdates + yay -Qua) at the left end of the
// right island, with the count beside the icon. Hidden with nothing to do;
// white up to 20, the accent (cyan) up to 30, past that it slowly blinks
// coral (the theme's red). Click toggles the "update" dropdown (omarchy-update
// in the upper right corner), which recounts when the update ends. Rechecks
// every 30 minutes.
BarWidget {
  id: root
  moduleName: "daa.updates"

  property int repo: 0
  property int aur: 0
  readonly property int count: repo + aur
  readonly property color coral: Color.urgent
  // White, or light coral while the ABACABB blood mode (daa.search) is on.
  readonly property color white: Qt.colorEqual(Color.accent, "#e0607a") ? "#ffb8c6" : "#ffffff"

  visible: count > 0
  implicitWidth: visible ? content.implicitWidth : 0
  implicitHeight: button.implicitHeight

  property real pulse: 0
  SequentialAnimation on pulse {
    running: root.count > 30
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0; duration: 1100; easing.type: Easing.InOutSine }
    onRunningChanged: if (!running) root.pulse = 0
  }

  readonly property color tint: count > 30 ? Qt.rgba(coral.r, coral.g, coral.b, 0.35 + 0.65 * (1 - pulse))
    : count > 20 ? Color.accent
    : root.white

  function refresh() {
    if (!countProc.running) countProc.running = true
  }

  Process {
    id: countProc
    command: ["bash", "-c",
      "echo repo $(checkupdates 2>/dev/null | wc -l); echo aur $(yay -Qua 2>/dev/null | wc -l)"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var f = lines[i].trim().split(/\s+/)
          if (f[0] === "repo") root.repo = Number(f[1]) || 0
          else if (f[0] === "aur") root.aur = Number(f[1]) || 0
        }
      }
    }
  }

  Timer {
    interval: 1800000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "daa.updates"
    function refresh(): void { root.broadcast("refresh") }
  }

  Row {
    id: content
    anchors.verticalCenter: parent.verticalCenter

    BarIconButton {
      id: button
      bar: root.bar
      text: "󰚰"
      foreground: root.tint
      tooltipText: root.repo + " repo + " + root.aur + " AUR updates"
      // The "update" dropdown (hypr/dropdowns.lua), which refreshes this
      // count itself once the update finishes.
      onPressed: function(mouseButton) { Util.execArgv(["hyprctl", "eval", "dropdown_toggle(\"update\")"]) }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      rightPadding: Style.space(4)
      text: root.count
      color: root.tint
      font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
      font.pixelSize: Style.font.bodySmall
    }
  }
}
