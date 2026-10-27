import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Backups (Desktop settings → Backups): checkpoints of the whole desktop
// setup (hypr, Omarchy plugins + settings, ~/.local/bin, autostart, lab
// sheet) through ~/.local/bin/checkpoint. Restoring saves a "before restore"
// checkpoint first, so a restore can itself be undone.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/checkpoint"

  spacing: Style.space(4)

  property var rows: []
  property string newName: ""
  property string status: ""
  // A restore waits for a second click on the same row.
  property string confirmFile: ""

  function reload() { if (!lister.running) lister.running = true }
  Component.onCompleted: reload()
  Process {
    id: lister
    command: [page.tool, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { page.rows = JSON.parse(text) } catch (e) {} }
    }
  }
  Process {
    id: runner
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(text) } catch (e) {}
        if (!r.ok) page.status = "Something went wrong."
        page.reload()
      }
    }
  }
  function run(args, msg) {
    if (runner.running) return
    page.status = msg
    page.confirmFile = ""
    runner.command = [page.tool].concat(args)
    runner.running = true
  }
  function sizeText(b) { return b > 1048576 ? (b / 1048576).toFixed(1) + " MB" : Math.round(b / 1024) + " KB" }

  // ======================= UI =======================

  component SmallButton: Rectangle {
    id: btn
    property string label: ""
    property bool danger: false
    property bool selected: false
    signal clicked()
    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.space(7)
    color: selected ? Util.alpha(danger ? Commons.Color.urgent : page.accent, 0.3) : btnArea.containsMouse ? Util.alpha(danger ? Commons.Color.urgent : page.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: (btn.selected || btnArea.containsMouse) && btn.danger ? Commons.Color.urgent : btn.selected ? page.accent : page.fg
      font.family: page.font
      font.pixelSize: Style.font.caption
    }
    MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }

  Text {
    x: Style.space(10)
    topPadding: Style.space(6)
    width: page.width - Style.space(20)
    text: "A checkpoint saves the whole desktop setup: Hyprland config, bar and plugins, these settings, scripts, startup and the lab sheet (not wallpapers). Restoring one saves the current setup first."
    color: page.fg
    opacity: 0.55
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.caption
  }

  Row {
    x: Style.space(10)
    topPadding: Style.space(6)
    spacing: Style.space(6)
    Rectangle {
      width: page.width - saveBtn.width - Style.space(30)
      height: Style.space(26)
      radius: Style.space(6)
      color: Qt.rgba(1, 1, 1, 0.06)
      TextInput {
        id: nameInput
        anchors.fill: parent
        anchors.margins: Style.space(5)
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        text: page.newName
        color: page.fg
        font.family: page.font
        font.pixelSize: Style.font.bodySmall
        onTextEdited: page.newName = text
        Keys.onReturnPressed: saveBtn.clicked()
        Text { visible: nameInput.text === ""; text: "Name (optional), e.g. before theme experiments"; color: page.fg; opacity: 0.4; font: nameInput.font }
      }
    }
    SmallButton {
      id: saveBtn
      label: "Save checkpoint"
      onClicked: { page.run(["save", page.newName], "Saved."); page.newName = "" }
    }
  }

  Text {
    visible: page.status !== ""
    x: Style.space(10)
    text: page.status
    color: page.fg
    opacity: 0.75
    font.family: page.font
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: page.rows
    Item {
      required property var modelData
      width: page.width
      height: Style.space(40)
      Column {
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        Text { text: modelData.name ? modelData.name.charAt(0).toUpperCase() + modelData.name.slice(1) : "Checkpoint"; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
        Text { text: modelData.date + "  ·  " + page.sizeText(modelData.size); color: page.fg; opacity: 0.55; font.family: page.font; font.pixelSize: Style.font.caption }
      }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        SmallButton {
          label: page.confirmFile === modelData.file ? "Click again to restore" : "Restore"
          selected: page.confirmFile === modelData.file
          onClicked: {
            if (page.confirmFile !== modelData.file) { page.confirmFile = modelData.file; return }
            page.run(["restore", modelData.file], "Restoring… the shell restarts in a moment.")
          }
        }
        SmallButton { label: "Delete"; danger: true; onClicked: page.run(["delete", modelData.file], "Deleted.") }
      }
    }
  }
  Text {
    visible: page.rows.length === 0
    x: Style.space(10)
    text: "No checkpoints yet."
    color: page.fg
    opacity: 0.5
    font.family: page.font
    font.pixelSize: Style.font.bodySmall
  }
  Item { width: 1; height: Style.space(10) }
}
