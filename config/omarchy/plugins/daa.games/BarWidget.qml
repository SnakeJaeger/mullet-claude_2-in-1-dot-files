import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// RetroArch's invader between the Arch logo and the workspaces. Left click
// opens ES-DE (the game library front end; falls back to RetroArch until
// ES-DE is installed from the AUR), right click opens Steam. Turns the theme
// accent while hovered, like the Arch logo.
BarWidget {
  id: root
  moduleName: "daa.games"

  readonly property bool hovered: button.tooltipHovered
  readonly property color iconColor: root.hovered ? Color.accent : (root.bar ? root.bar.barForeground : Color.foreground)
  readonly property int iconSize: Math.round(Style.font.body * 1.45)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true
    fixedWidth: root.iconSize + Style.spaceReal(6) * 2
    tooltipText: "Games: ES-DE · right click Steam"
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("uwsm-app -- steam")
      else root.bar.run("command -v es-de >/dev/null && exec uwsm-app -- es-de || exec uwsm-app -- retroarch")
    }

    // Single-colour SVG (#ffffff) recoloured like the Go menu's icons.
    FileView {
      id: svg
      path: Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.games/icons/retroarch.svg"
      printErrors: false
    }
    Image {
      anchors.centerIn: parent
      width: root.iconSize
      height: root.iconSize
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      fillMode: Image.PreserveAspectFit
      smooth: true
      source: svg.loaded
        ? "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg.text().replace(/#ffffff/g, String(root.iconColor)))
        : ""
    }
  }
}
