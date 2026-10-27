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

  // Desktop UI settings (daa.settings writes ~/.config/omarchy/daa-ui.json;
  // a missing key means its default, i.e. on).
  property var ui: ({})
  function uiOpt(key, fallback) {
    // Calm mode (power-saver; daa.settings writes ~/.local/state/daa/calm):
    // the decorative animations pause, whatever their own switches say.
    if (root.calm && root.calmKeys.indexOf(key) !== -1) return false
    var v = root.ui ? root.ui[key] : undefined; return v === undefined || v === null ? fallback : v
  }
  readonly property var calmKeys: ["goMenuAnimations", "duel", "launcherTrails", "shortcutCardAnimations",
    "shortcutCardTrails", "workspaceSpring", "magellanic", "breathingBorders", "barAlertPulse"]
  property bool calm: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/daa/calm"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.calm = String(text()).trim() === "1"
    onLoadFailed: root.calm = false
  }
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/daa-ui.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.ui = JSON.parse(text() || "{}") } catch (e) {} }
    onLoadFailed: root.ui = ({})   // file deleted: all defaults
  }

  property int repo: 0
  property int aur: 0
  readonly property int count: repo + aur
  readonly property color coral: Color.urgent
  // White, or light coral while the ABACABB blood mode (daa.search) is on.
  // Light themes get dark tiles/text: the theme's foreground instead of white.
  readonly property bool lightTheme: 0.299 * Color.background.r + 0.587 * Color.background.g + 0.114 * Color.background.b > 0.5
  readonly property color white: Qt.colorEqual(Color.accent, "#e0607a") ? "#ffb8c6" : lightTheme ? Color.foreground : "#ffffff"

  visible: count > 0
  implicitWidth: visible ? content.implicitWidth : 0
  implicitHeight: button.implicitHeight

  property real pulse: 0
  SequentialAnimation on pulse {
    // Settings: "barAlertPulse" off = steady colour.
    running: root.count > 30 && root.uiOpt("barAlertPulse", true)
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
