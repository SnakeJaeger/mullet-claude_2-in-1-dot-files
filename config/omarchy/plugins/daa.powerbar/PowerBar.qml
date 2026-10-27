import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Power bar (SUPER + ESC, power button): a band right across the middle of
// the dimmed screen with the power options, XBMC-style. Shows instantly (no
// animation). Each option's key letter is highlighted: S L R O D. Press the
// letter, or Left / Right then Enter, or click; Escape or a click on the
// dimmed screen closes it.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property int selected: 0

  // label, the highlighted letter's index in it, key, glyph, command; `key`
  // also names its switch in Desktop settings (powerScreensaver…), and
  // Suspend / Hibernate start switched off.
  readonly property var allOptions: [
    { id: "Screensaver", label: "Screensaver", at: 0, key: Qt.Key_S, glyph: "󱄄", command: "omarchy-launch-screensaver force" },
    { id: "Lock", label: "Lock", at: 0, key: Qt.Key_L, glyph: "󰌾", command: "omarchy-system-lock" },
    { id: "Suspend", label: "Suspend", at: 1, key: Qt.Key_U, glyph: "󰤄", command: "systemctl suspend", off: true },
    { id: "Hibernate", label: "Hibernate", at: 0, key: Qt.Key_H, glyph: "󰒲", command: "systemctl hibernate", off: true },
    { id: "Reboot", label: "Reboot", at: 0, key: Qt.Key_R, glyph: "󰜉", command: "omarchy-system-reboot" },
    { id: "Logout", label: "Logout", at: 1, key: Qt.Key_O, glyph: "󰍃", command: "omarchy-system-logout" },
    { id: "Shutdown", label: "Shutdown", at: 4, key: Qt.Key_D, glyph: "󰐥", command: "omarchy-system-shutdown" }
  ]
  readonly property var options: {
    var out = []
    for (var i = 0; i < allOptions.length; i++) {
      var o = allOptions[i], v = root.ui["power" + o.id]
      if (v === undefined || v === null ? !o.off : v) out.push(o)
    }
    if (root.ui.powerOrder === "shutdownFirst") out.reverse()
    return out
  }

  property var ui: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/daa-ui.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.ui = JSON.parse(text() || "{}") } catch (e) {} }
    onLoadFailed: root.ui = ({})
  }

  property color accent: Commons.Color.accent
  property color foreground: Commons.Color.menu.text
  property string fontFamily: Style.font.menuFamily

  function open(payloadJson) {
    root.selected = 0
    root.opened = true
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "daa.powerbar")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function run(i) {
    if (i < 0 || i >= root.options.length) return
    var command = root.options[i].command
    root.dismiss()
    // A beat later, so the screensaver / lock screen don't start under it.
    Quickshell.execDetached(["bash", "-lc", "sleep 0.15; " + command])
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-powerbar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Dimmed screen; a click on it closes.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.6)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    Item {
      id: keys
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true; return }
        if (event.key === Qt.Key_Left) { root.selected = (root.selected + root.options.length - 1) % root.options.length; event.accepted = true; return }
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) { root.selected = (root.selected + 1) % root.options.length; event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { root.run(root.selected); event.accepted = true; return }
        for (var i = 0; i < root.options.length; i++) {
          if (event.key === root.options[i].key) { root.run(i); event.accepted = true; return }
        }
      }
    }

    // The band: full width, centred vertically, hairlines top and bottom.
    Rectangle {
      id: band
      width: parent.width
      height: Style.space(150)
      anchors.verticalCenter: parent.verticalCenter
      // Nearly opaque, so whatever's behind doesn't show through.
      color: Util.alpha(Commons.Color.background, 0.96)

      // Clicks on the band itself don't close it.
      MouseArea { anchors.fill: parent }

      Rectangle { width: parent.width; height: 1; color: Util.alpha(root.accent, 0.5) }
      Rectangle { width: parent.width; height: 1; anchors.bottom: parent.bottom; color: Util.alpha(root.accent, 0.5) }

      Row {
        anchors.centerIn: parent
        spacing: Style.space(18)

        Repeater {
          model: root.options

          Item {
            id: opt
            required property var modelData
            required property int index
            readonly property bool current: index === root.selected
            width: Style.space(150)
            height: band.height

            // XBMC-style focus: a lit strip behind the selected option.
            Rectangle {
              anchors.fill: parent
              anchors.topMargin: Style.space(12)
              anchors.bottomMargin: Style.space(12)
              radius: Style.space(12)
              color: opt.current ? Util.alpha(root.accent, 0.16) : optArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
              border.width: opt.current ? 1 : 0
              border.color: Util.alpha(root.accent, 0.6)
            }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(10)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: opt.modelData.glyph
                color: opt.current ? root.accent : root.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.space(46)
              }

              // The key letter in the accent, underlined.
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.StyledText
                readonly property string l: opt.modelData.label
                readonly property int a: opt.modelData.at
                text: l.slice(0, a) + "<u><font color='" + root.accent + "'>" + l.charAt(a) + "</font></u>" + l.slice(a + 1)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: opt.current
              }
            }

            MouseArea {
              id: optArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selected = opt.index
              onClicked: root.run(opt.index)
            }
          }
        }
      }
    }
  }
}
