import QtQuick
import Qt5Compat.GraphicalEffects as GE
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.weather"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root). Open maps to the
  // panel's hotkey path so summoning suppresses the center hover reveal,
  // matching what the old per-plugin IpcHandler did.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: panelLoader.item && panelLoader.item.label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : ""
    slotSize: Style.bar.statusSlot
    // Theme cyan (the accent) on hover, like the globe (Devan, 2026-11-08).
    foreground: (tooltipHovered || root.opened) ? Color.accent : (root.bar ? root.bar.barForeground : Color.foreground)
    // Press: while the button is held (pressScale < 1, the shell's own
    // held state) the icon glows brighter in its hover color; it clears on
    // release, when the click opens as before (Devan, 2026-11-08).
    readonly property bool held: pressScale < 1
    // Open: the glow (and hover color) stays on while its popup is showing (Devan, 2026-11-10).
    layer.enabled: held || root.opened
    layer.effect: GE.Glow {
      radius: button.held ? 12 : 8
      samples: 25
      spread: button.held ? 0.35 : 0.1
      color: Color.accent
      transparentBorder: true
    }
    // On the side bar the weather glyphs' ink sits about 1 px left of the
    // other icons; nudge it back to centre (measured, Devan 2026-11-01).
    transform: Translate { x: 0 }
    // Tooltip suppressed because the panel is the detail view.
    tooltipText: ""

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
      else if (b === Qt.MiddleButton) root.refresh()
      // Omarchy's own popup panel, like the calendar and globe (Devan,
      // 2026-11-08, back from the GNOME Weather dropdown, which is still
      // on SUPER + ALT + W).
      else root.togglePanel()
    }
  }
}
