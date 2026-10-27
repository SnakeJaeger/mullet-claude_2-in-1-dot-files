import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Startup (Desktop settings → Startup): apps to launch at login, which
// dropdowns preload hidden at login, and the system's XDG autostart entries.
// All through ~/.local/bin/startup-apps: login apps live in
// hypr/startup_user.json (launched by hypr/autostart.lua), preload switches
// in hypr/preload_off (read by hypr/dropdowns.lua), XDG entries get a
// Hidden=true copy in ~/.config/autostart. Takes effect at the next login.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/startup-apps"

  spacing: Style.space(4)

  property var info: ({ apps: [], dropdowns: [], xdg: [] })
  property string newName: ""
  property string newCmd: ""
  property int newDelay: 0

  function reload() { if (!lister.running) lister.running = true }
  Component.onCompleted: reload()
  Process {
    id: lister
    command: [page.tool, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { page.info = JSON.parse(text) } catch (e) {} }
    }
  }
  Process {
    id: runner
    onExited: page.reload()
  }
  function run(args) {
    if (runner.running) return
    runner.command = [page.tool].concat(args)
    runner.running = true
  }
  function saveApps(list) { page.run(["save", JSON.stringify(list)]) }
  function setApp(i, key, v) {
    var list = JSON.parse(JSON.stringify(page.info.apps))
    list[i][key] = v
    page.saveApps(list)
  }
  function addApp() {
    var cmd = page.newCmd.trim()
    if (!cmd) return
    var list = page.info.apps.slice()
    list.push({ name: page.newName.trim() || cmd.split(" ")[0], cmd: cmd, enabled: true, delay: page.newDelay })
    page.newName = ""; page.newCmd = ""; page.newDelay = 0
    page.saveApps(list)
  }
  function removeApp(i) {
    var list = page.info.apps.slice()
    list.splice(i, 1)
    page.saveApps(list)
  }

  // ======================= UI =======================

  component Heading: Text {
    x: Style.space(10)
    topPadding: Style.space(10)
    color: page.accent
    font.family: page.font
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }
  component Hint: Text {
    x: Style.space(10)
    width: page.width - Style.space(20)
    color: page.fg
    opacity: 0.55
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.caption
  }
  component SmallButton: Rectangle {
    id: btn
    property string label: ""
    property bool danger: false
    signal clicked()
    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.space(7)
    color: btnArea.containsMouse ? Util.alpha(danger ? Commons.Color.urgent : page.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: btnArea.containsMouse && btn.danger ? Commons.Color.urgent : page.fg
      font.family: page.font
      font.pixelSize: Style.font.caption
    }
    MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }
  component Switch: Rectangle {
    id: sw
    property bool on: false
    signal toggled()
    width: Style.space(38)
    height: Style.space(20)
    radius: height / 2
    color: on ? page.accent : Qt.rgba(1, 1, 1, 0.14)
    Rectangle {
      width: parent.height - Style.space(6)
      height: width
      radius: width / 2
      y: Style.space(3)
      x: sw.on ? parent.width - width - Style.space(3) : Style.space(3)
      color: sw.on ? Commons.Color.background : page.fg
      Behavior on x { NumberAnimation { duration: 120 } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
  }
  component SwitchRow: Item {
    id: sr
    property string label: ""
    property string hint: ""
    property bool on: false
    signal toggled()
    width: page.width
    height: Style.space(hint ? 40 : 32)
    Column {
      x: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      Text { text: sr.label; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
      Text { visible: sr.hint !== ""; text: sr.hint; color: page.fg; opacity: 0.5; font.family: page.font; font.pixelSize: Style.font.caption }
    }
    Switch {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      on: sr.on
      onToggled: sr.toggled()
    }
  }
  component Field: Rectangle {
    id: fld
    property alias text: input.text
    property string placeholder: ""
    signal edited(string v)
    height: Style.space(26)
    radius: Style.space(6)
    color: Qt.rgba(1, 1, 1, 0.06)
    TextInput {
      id: input
      anchors.fill: parent
      anchors.margins: Style.space(5)
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      color: page.fg
      font.family: page.font
      font.pixelSize: Style.font.bodySmall
      onTextEdited: fld.edited(text)
      Keys.onReturnPressed: page.addApp()
      Text { visible: input.text === ""; text: fld.placeholder; color: page.fg; opacity: 0.4; font: input.font }
    }
  }

  Hint { topPadding: Style.space(6); text: "Changes take effect at your next login." }

  Heading { text: "Login apps" }
  Repeater {
    model: page.info.apps
    SwitchRow {
      required property var modelData
      required property int index
      label: modelData.name
      hint: modelData.cmd + (modelData.delay ? "  ·  after " + modelData.delay + " s" : "")
      on: modelData.enabled !== false
      onToggled: page.setApp(index, "enabled", !on)
      SmallButton {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(58)
        anchors.verticalCenter: parent.verticalCenter
        label: "Remove"
        danger: true
        onClicked: page.removeApp(index)
      }
    }
  }
  Row {
    x: Style.space(10)
    spacing: Style.space(6)
    Field { width: Style.space(110); placeholder: "Name"; text: page.newName; onEdited: v => page.newName = v }
    Field { width: page.width - Style.space(330); placeholder: "Command, e.g. obsidian"; text: page.newCmd; onEdited: v => page.newCmd = v }
    Repeater {
      model: [0, 5, 15]
      SmallButton {
        required property var modelData
        label: modelData === 0 ? "now" : "+" + modelData + "s"
        color: page.newDelay === modelData ? Util.alpha(page.accent, 0.3) : Qt.rgba(1, 1, 1, 0.06)
        onClicked: page.newDelay = modelData
      }
    }
    SmallButton { label: "Add"; onClicked: page.addApp() }
  }

  Heading { text: "Dropdowns ready at login" }
  Hint { text: "Preloaded dropdowns open hidden at login, so their first press is instant. Off: they start on first use." }
  Repeater {
    model: page.info.dropdowns
    SwitchRow {
      required property var modelData
      label: modelData.title.charAt(0).toUpperCase() + modelData.title.slice(1)
      on: modelData.enabled
      onToggled: page.run(["preload", modelData.name, on ? "off" : "on"])
    }
  }

  Heading { text: "System autostart" }
  Hint { text: "Desktop-file autostart entries (/etc/xdg/autostart). Off adds a Hidden copy in ~/.config/autostart." }
  Repeater {
    model: page.info.xdg
    SwitchRow {
      required property var modelData
      label: modelData.name
      on: modelData.enabled
      onToggled: page.run(["xdg", modelData.file, on ? "off" : "on"])
    }
  }
  Item { width: 1; height: Style.space(10) }
}
