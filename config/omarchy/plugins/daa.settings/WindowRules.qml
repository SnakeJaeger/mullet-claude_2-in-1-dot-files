import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Window rules (Desktop settings → Rules): per-app opacity, floating with a
// size, always on top (pinned), and a home workspace. Pick the app with the
// same scope as the scratchpad builder, or type / choose its class.
// Saved through ~/.local/bin/rules-tool to hypr/windowrules_user.json →
// windowrules_user.lua, which hyprland.lua loads; rules apply to windows
// opened after saving.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/rules-tool"

  spacing: Style.space(4)

  property var rules: []
  property var openClasses: []
  property string status: ""
  // The rule being edited (a copy), and its index (-1 = new).
  property var form: null
  property int editIndex: -1

  function blank() { return { "class": "", opacity: 1, "float": false, w: 900, h: 600, pin: false, workspace: "" } }
  function startNew() { page.form = page.blank(); page.editIndex = -1; page.status = "" }
  function edit(i) {
    var r = page.rules[i], f = page.blank()
    for (var k in r) f[k] = r[k]
    page.form = f
    page.editIndex = i
  }
  function setField(k, v) {
    var f = {}
    for (var key in page.form) f[key] = page.form[key]
    f[k] = v
    page.form = f
  }
  function summary(r) {
    var bits = []
    if (r.opacity !== undefined && r.opacity < 1) bits.push(Math.round(r.opacity * 100) + "% opaque")
    if (r["float"]) bits.push("floating " + r.w + "×" + r.h)
    if (r.pin) bits.push("always on top")
    if (r.workspace) bits.push("workspace " + r.workspace)
    return bits.length ? bits.join(" · ") : "no changes"
  }

  function save(list) {
    page.rules = list
    page.status = "Applying…"
    writer.command = [page.tool, "write", JSON.stringify(list)]
    writer.running = true
  }
  function commit() {
    if (!page.form || !String(page.form["class"]).trim()) { page.status = "Pick a window or type its class first."; return }
    var list = page.rules.slice()
    if (page.editIndex >= 0) list[page.editIndex] = page.form; else list.push(page.form)
    page.form = null
    page.save(list)
  }
  function remove(i) {
    var list = page.rules.slice()
    list.splice(i, 1)
    page.save(list)
  }

  function pick() {
    if (!page.form) page.startNew()
    if (page.host) page.host.dismiss()
    Quickshell.execDetached(["bash", "-c", "sleep 0.3; omarchy-shell shell summon daa.zap '{\"mode\":\"pick\",\"returnTo\":\"rules\"}'"])
  }
  function loadPicked() { pickedFile.reload(); pickTimer.restart() }
  Timer {
    id: pickTimer
    interval: 150
    onTriggered: {
      var r = {}
      try { r = JSON.parse(pickedFile.text() || "{}") } catch (e) {}
      if (!r.ok) { page.status = r.error || "Nothing was picked."; return }
      if (!page.form) page.startNew()
      page.setField("class", r["class"])
      page.setField("w", Math.min(r.w, 1400))
      page.setField("h", Math.min(r.h, 900))
      page.status = "Picked " + r["class"] + " (" + r.title + ")."
    }
  }
  FileView {
    id: pickedFile
    path: Quickshell.env("HOME") + "/.local/state/daa/picked.json"
    printErrors: false
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/hypr/windowrules_user.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { page.rules = JSON.parse(text() || "[]") } catch (e) { page.rules = [] } }
    onLoadFailed: page.rules = []
  }
  Process {
    id: writer
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(text) } catch (e) {}
        page.status = r.ok ? "Saved. Applies to windows opened from now on." : (r.error || "Something went wrong.")
      }
    }
  }
  Process {
    id: classLister
    command: [page.tool, "classes"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { page.openClasses = JSON.parse(text) } catch (e) {} }
    }
  }
  function reload() { if (!classLister.running) classLister.running = true }
  Component.onCompleted: reload()

  // ======================= UI =======================

  component SmallButton: Rectangle {
    id: btn
    property string label: ""
    property bool selected: false
    property bool danger: false
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
  component Label: Text {
    width: Style.space(120)
    color: page.fg
    opacity: 0.75
    font.family: page.font
    font.pixelSize: Style.font.bodySmall
  }
  component NumField: Rectangle {
    id: nf
    property int value: 0
    signal edited(int v)
    width: Style.space(70)
    height: Style.space(26)
    radius: Style.space(6)
    color: Qt.rgba(1, 1, 1, 0.06)
    TextInput {
      anchors.fill: parent
      anchors.margins: Style.space(5)
      verticalAlignment: TextInput.AlignVCenter
      text: String(nf.value)
      color: page.fg
      font.family: page.font
      font.pixelSize: Style.font.bodySmall
      validator: IntValidator { bottom: 0; top: 9999 }
      onEditingFinished: nf.edited(parseInt(text) || 0)
    }
  }

  // Header: what this is + New rule
  Item {
    width: page.width
    height: Style.space(40)
    Text {
      x: Style.space(10)
      width: parent.width - newBtn.width - Style.space(30)
      anchors.verticalCenter: parent.verticalCenter
      text: "Per-app opacity, floating size, always on top and home workspace."
      color: page.fg
      opacity: 0.6
      wrapMode: Text.Wrap
      font.family: page.font
      font.pixelSize: Style.font.caption
    }
    SmallButton {
      id: newBtn
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      label: "+ New rule"
      onClicked: page.startNew()
    }
  }

  Text {
    visible: page.status !== ""
    x: Style.space(10)
    width: page.width - Style.space(20)
    text: page.status
    color: page.fg
    opacity: 0.75
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.caption
  }

  // Saved rules
  Repeater {
    model: page.rules
    Item {
      required property var modelData
      required property int index
      width: page.width
      height: Style.space(40)
      Column {
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        Text { text: modelData["class"]; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
        Text { text: page.summary(modelData); color: page.fg; opacity: 0.55; font.family: page.font; font.pixelSize: Style.font.caption }
      }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        SmallButton { label: "Edit"; onClicked: page.edit(index) }
        SmallButton { label: "Delete"; danger: true; onClicked: page.remove(index) }
      }
    }
  }
  Text {
    visible: page.rules.length === 0 && !page.form
    x: Style.space(10)
    topPadding: Style.space(6)
    text: "No rules yet."
    color: page.fg
    opacity: 0.5
    font.family: page.font
    font.pixelSize: Style.font.bodySmall
  }

  // Editor
  Rectangle {
    visible: page.form !== null
    x: Style.space(6)
    width: page.width - Style.space(12)
    height: editor.implicitHeight + Style.space(20)
    radius: Style.space(10)
    color: Qt.rgba(1, 1, 1, 0.04)
    border.color: Util.alpha(page.accent, 0.35)
    border.width: 1

    Column {
      id: editor
      x: Style.space(10)
      y: Style.space(10)
      width: parent.width - Style.space(20)
      spacing: Style.space(8)

      // App
      Row {
        spacing: Style.space(8)
        Label { text: "App (class)"; anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
          width: Style.space(220)
          height: Style.space(26)
          radius: Style.space(6)
          color: Qt.rgba(1, 1, 1, 0.06)
          TextInput {
            anchors.fill: parent
            anchors.margins: Style.space(5)
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            text: page.form ? page.form["class"] : ""
            color: page.fg
            font.family: page.font
            font.pixelSize: Style.font.bodySmall
            onTextEdited: page.setField("class", text)
          }
        }
        SmallButton { label: "Pick a window"; anchors.verticalCenter: parent.verticalCenter; onClicked: page.pick() }
      }
      Flow {
        width: parent.width
        spacing: Style.space(4)
        visible: page.openClasses.length > 0
        Text { text: "Open now:"; color: page.fg; opacity: 0.5; font.family: page.font; font.pixelSize: Style.font.caption; height: Style.space(24); verticalAlignment: Text.AlignVCenter }
        Repeater {
          model: page.openClasses.slice(0, 8)
          SmallButton {
            required property var modelData
            label: modelData
            selected: page.form && page.form["class"] === modelData
            onClicked: page.setField("class", modelData)
          }
        }
      }

      // Opacity
      Row {
        spacing: Style.space(8)
        Label { text: "Opacity"; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
          model: [[1, "100%"], [0.95, "95%"], [0.9, "90%"], [0.8, "80%"], [0.7, "70%"]]
          SmallButton {
            required property var modelData
            label: modelData[1]
            selected: page.form && Math.abs(page.form.opacity - modelData[0]) < 0.001
            onClicked: page.setField("opacity", modelData[0])
          }
        }
      }

      // Floating + size
      Row {
        spacing: Style.space(8)
        Label { text: "Floating"; anchors.verticalCenter: parent.verticalCenter }
        SmallButton { label: page.form && page.form["float"] ? "On" : "Off"; selected: page.form && page.form["float"]; onClicked: page.setField("float", !page.form["float"]) }
        NumField { visible: page.form && page.form["float"]; value: page.form ? page.form.w : 0; onEdited: v => page.setField("w", v) }
        Text { visible: page.form && page.form["float"]; text: "×"; color: page.fg; anchors.verticalCenter: parent.verticalCenter }
        NumField { visible: page.form && page.form["float"]; value: page.form ? page.form.h : 0; onEdited: v => page.setField("h", v) }
        Text { visible: page.form && page.form["float"]; text: "px, centred"; color: page.fg; opacity: 0.5; font.family: page.font; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
      }

      // Pin
      Row {
        spacing: Style.space(8)
        Label { text: "Always on top"; anchors.verticalCenter: parent.verticalCenter }
        SmallButton { label: page.form && page.form.pin ? "On" : "Off"; selected: page.form && page.form.pin; onClicked: page.setField("pin", !page.form.pin) }
        Text { text: "Floats, and follows you to every workspace"; color: page.fg; opacity: 0.5; font.family: page.font; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
      }

      // Workspace
      Row {
        spacing: Style.space(4)
        Label { text: "Opens on"; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
          model: ["", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
          SmallButton {
            required property var modelData
            label: modelData === "" ? "Current" : modelData
            selected: page.form && String(page.form.workspace || "") === modelData
            onClicked: page.setField("workspace", modelData)
          }
        }
      }

      Row {
        spacing: Style.space(6)
        SmallButton { label: page.editIndex >= 0 ? "Save changes" : "Add rule"; selected: true; onClicked: page.commit() }
        SmallButton { label: "Cancel"; onClicked: page.form = null }
      }
    }
  }
  Item { width: 1; height: Style.space(10) }
}
