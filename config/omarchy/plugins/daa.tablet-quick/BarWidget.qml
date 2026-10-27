import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Tablet bar button (tune sliders; the Omarchy logo next to it is the
// greeter, daa.tablet-greet): tap opens the quick toggles menu
// (~/.config/omarchy/extensions/omarchy-menu.jsonc). Only the tablet bar
// (daa.tablet-bar) uses it.
BarWidget {
  id: root
  moduleName: "daa.tablet-quick"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰘮"
    fontFamily: "JetBrainsMono Nerd Font"
    fontSize: Math.round(Style.font.body * 1.2)
    horizontalMargin: 7.5
    tooltipText: "Quick toggles"
    foreground: ((root.bar && root.bar.flashModule === root.moduleName) || (button.tooltipHovered && !(root.bar && root.bar.hoverCleared))) ? Color.pick("tablet.accent", Color.accent) : (root.bar ? root.bar.barForeground : Color.foreground)
    onPressed: function() { if (root.bar) root.bar.run("omarchy menu summon tablet.quick") }
  }
}
