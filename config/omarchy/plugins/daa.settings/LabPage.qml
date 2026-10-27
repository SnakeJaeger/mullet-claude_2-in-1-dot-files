import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Lab sheet (Desktop settings → Lab): the lab box's address, VNC port, ssh
// user, Lab API address and the server card's services, in one place.
// ~/.local/bin/lab-tool reads them from, and writes them back to, the files
// the cards and scripts already use (Remmina profile, ~/.ssh/config "Host
// lab", ~/.config/lab-services/api and services).
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/lab-tool"

  spacing: Style.space(4)

  property var sheet: ({ host: "", vncport: "5900", api: "", sshUser: "", services: [] })
  property string status: ""
  property bool dirty: false

  function reload() {
    if (lister.running) return
    page.dirty = false
    lister.running = true
  }
  Component.onCompleted: reload()
  Process {
    id: lister
    command: [page.tool, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { page.sheet = JSON.parse(text) } catch (e) {} }
    }
  }
  Process {
    id: writer
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(text) } catch (e) {}
        page.status = r.ok ? (r.changed.length ? "Saved: " + r.changed.join(", ") + "." : "Nothing changed.") : (r.error || "Something went wrong.")
        page.reload()
      }
    }
  }
  function save() {
    writer.command = [page.tool, "set", JSON.stringify(page.sheet)]
    writer.running = true
  }
  // Typing edits the sheet in place: reassigning it would rebuild the
  // service rows (and drop the focus) on every key.
  function setField(k, v) {
    page.sheet[k] = v
    page.dirty = true
  }
  function setService(i, k, v) {
    page.sheet.services[i][k] = v
    page.dirty = true
  }
  function addService() {
    var s = JSON.parse(JSON.stringify(page.sheet))
    s.services.push({ name: "", port: "", path: "/", glyph: "󰒋", scheme: "", page: "" })
    page.sheet = s
    page.dirty = true
  }
  function removeService(i) {
    var s = JSON.parse(JSON.stringify(page.sheet))
    s.services.splice(i, 1)
    page.sheet = s
    page.dirty = true
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
  component SmallButton: Rectangle {
    id: btn
    property string label: ""
    property bool danger: false
    property bool selected: false
    signal clicked()
    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.space(7)
    color: selected ? Util.alpha(page.accent, 0.3) : btnArea.containsMouse ? Util.alpha(danger ? Commons.Color.urgent : page.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: btn.selected ? page.accent : btnArea.containsMouse && btn.danger ? Commons.Color.urgent : page.fg
      font.family: page.font
      font.pixelSize: Style.font.caption
    }
    MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }
  component Field: Rectangle {
    id: fld
    property string value: ""
    property string placeholder: ""
    property string fontFamily: page.font
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
      text: fld.value
      color: page.fg
      font.family: fld.fontFamily
      font.pixelSize: Style.font.bodySmall
      onTextEdited: fld.edited(text)
      Text { visible: input.text === ""; text: fld.placeholder; color: page.fg; opacity: 0.4; font: input.font }
    }
  }
  component FormRow: Row {
    property string label: ""
    property string hint: ""
    x: Style.space(10)
    spacing: Style.space(8)
    Text { width: Style.space(110); text: parent.label; color: page.fg; opacity: 0.8; font.family: page.font; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
  }

  Text {
    x: Style.space(10)
    topPadding: Style.space(6)
    width: page.width - Style.space(20)
    text: "The lab box, once: the Lab card's heartbeat, the server card, the Lab button (VNC), ssh lab, /ssh and /lab all read from here."
    color: page.fg
    opacity: 0.55
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.caption
  }

  Heading { text: "Lab box" }
  FormRow {
    label: "Address"
    Field { width: Style.space(200); value: page.sheet.host; placeholder: "Tailscale IP or name"; onEdited: v => page.setField("host", v) }
    Text { text: "VNC port"; color: page.fg; opacity: 0.6; font.family: page.font; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
    Field { width: Style.space(60); value: page.sheet.vncport; onEdited: v => page.setField("vncport", v) }
  }
  FormRow {
    label: "ssh user"
    Field { width: Style.space(200); value: page.sheet.sshUser; placeholder: "user on the lab box"; onEdited: v => page.setField("sshUser", v) }
  }
  FormRow {
    label: "Lab API"
    Field { width: page.width - Style.space(150); value: page.sheet.api; placeholder: "https://<box>:8444/api/v1 (optional)"; onEdited: v => page.setField("api", v) }
  }

  Heading { text: "Services (server card)" }
  Text {
    x: Style.space(10)
    width: page.width - Style.space(20)
    text: "Name, port, health path (any HTTP reply counts as up), glyph, http / https, page to open. https goes through the box's Tailscale name."
    color: page.fg
    opacity: 0.55
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.caption
  }
  Repeater {
    model: page.sheet.services
    Row {
      required property var modelData
      required property int index
      x: Style.space(10)
      spacing: Style.space(4)
      Field { width: Style.space(34); value: modelData.glyph; fontFamily: Style.font.family; onEdited: v => page.setService(index, "glyph", v) }
      Field { width: Style.space(90); value: modelData.name; placeholder: "Name"; onEdited: v => page.setService(index, "name", v) }
      Field { width: Style.space(54); value: modelData.port; placeholder: "port"; onEdited: v => page.setService(index, "port", v) }
      Field { width: Style.space(104); value: modelData.path; placeholder: "/health"; onEdited: v => page.setService(index, "path", v) }
      SmallButton { label: modelData.scheme === "https" ? "https" : "http"; selected: modelData.scheme === "https"; onClicked: { page.setService(index, "scheme", modelData.scheme === "https" ? "" : "https"); page.sheet = JSON.parse(JSON.stringify(page.sheet)) } }
      Field { width: Style.space(96); value: modelData.page; placeholder: "page (/)"; onEdited: v => page.setService(index, "page", v) }
      SmallButton { label: "✕"; danger: true; onClicked: page.removeService(index) }
    }
  }
  SmallButton { x: Style.space(10); label: "+ Add service"; onClicked: page.addService() }

  Row {
    x: Style.space(10)
    topPadding: Style.space(10)
    spacing: Style.space(8)
    SmallButton { label: "Save"; selected: page.dirty; onClicked: page.save() }
    SmallButton { label: "Undo changes"; visible: page.dirty; onClicked: { page.status = ""; page.reload() } }
    Text { text: page.status; color: page.fg; opacity: 0.7; font.family: page.font; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
  }
  Item { width: 1; height: Style.space(10) }
}
