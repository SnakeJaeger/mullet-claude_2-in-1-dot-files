import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Minimized windows (parked on special:minimized by ~/.local/bin/minimize),
// one icon each, after the app name. Click brings it back to the current
// workspace. Hidden when there are none.
BarWidget {
  id: root
  moduleName: "daa.desktop-minimized"

  property var windows: []

  function refresh() {
    if (!listProc.running) listProc.running = true
    else listProc.stale = true
  }

  Process {
    id: listProc
    property bool stale: false
    command: ["sh", "-c", "hyprctl clients -j | jq -c '[.[] | select(.workspace.name == \"special:minimized\") | {address, class, title}]'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.windows = JSON.parse(text || "[]") } catch (e) { root.windows = [] } }
    }
    onExited: if (stale) { stale = false; running = true }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name
      if (name === "movewindowv2" || name === "closewindow" || name === "openwindow" || name === "windowtitlev2")
        root.refresh()
    }
  }
  Component.onCompleted: refresh()

  // Quickshell's own windows (Desktop settings) have no desktop entry.
  readonly property var glyphs: ({ "org.quickshell": "󰒓" })
  function iconFor(cls) {
    var entry = DesktopEntries.heuristicLookup(cls)
    var name = entry && entry.icon ? entry.icon : ""
    if (name.charAt(0) === "/") return "file://" + name
    var themed = name ? Quickshell.iconPath(name, true) : ""
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  visible: windows.length > 0 && !vertical
  implicitWidth: visible ? iconRow.implicitWidth + Style.space(12) : 0
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Row {
    id: iconRow
    anchors.centerIn: parent
    spacing: Style.space(6)
    Repeater {
      model: root.windows
      Item {
        id: chip
        required property var modelData
        width: Style.space(20)
        height: width
        scale: chipArea.containsMouse ? 1.18 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Image {
          anchors.fill: parent
          visible: !root.glyphs[chip.modelData["class"]]
          source: visible ? root.iconFor(chip.modelData["class"]) : ""
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          opacity: 0.85
        }
        Text {
          anchors.centerIn: parent
          visible: !!root.glyphs[chip.modelData["class"]]
          text: root.glyphs[chip.modelData["class"]] || ""
          color: Commons.Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
        // A small dot under each: "parked".
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.bottom
          anchors.topMargin: 1
          width: 4; height: 4; radius: 2
          color: Commons.Color.accent
          opacity: 0.8
        }
        MouseArea {
          id: chipArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: if (root.bar) root.bar.showTooltip(chip, "Restore " + (chip.modelData.title || chip.modelData["class"]))
          onExited: if (root.bar) root.bar.hideTooltip(chip)
          onClicked: {
            if (root.bar) root.bar.hideTooltip(chip)
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/minimize", "restore", chip.modelData.address])
          }
        }
      }
    }
  }
}
