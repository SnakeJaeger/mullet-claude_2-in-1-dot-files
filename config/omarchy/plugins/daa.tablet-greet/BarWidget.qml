import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Tablet bar button (Omarchy logo): tap opens / closes the tablet greeter
// (daa.tablet-greeter). Quick toggles moved to daa.tablet-quick's own icon.
// Only the tablet bar (daa.tablet-bar) uses it.
BarWidget {
  id: root
  moduleName: "daa.tablet-greet"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    fontFamily: "omarchy"
    fontSize: Math.round(Style.font.body * 1.2)
    horizontalMargin: 7.5
    tooltipText: "Greeter"
    foreground: ((root.bar && root.bar.flashModule === root.moduleName) || (button.tooltipHovered && !(root.bar && root.bar.hoverCleared))) ? Color.pick("tablet.accent", Color.accent) : (root.bar ? root.bar.barForeground : Color.foreground)
    onPressed: function() { if (root.bar) root.bar.run("omarchy-shell shell toggle daa.tablet-greeter") }
  }
}
