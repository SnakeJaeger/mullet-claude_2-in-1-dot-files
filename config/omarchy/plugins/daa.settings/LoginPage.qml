import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Login screen (Desktop settings → Login): SDDM theme with a live preview
// window, a theme's background picture, and your picture on the login
// screen. Through ~/.local/bin/sddm-tool; changes need the admin password
// (polkit dialog), previews don't.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/sddm-tool"
  readonly property string wallpaper: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"

  spacing: Style.space(4)

  property var info: ({ themes: [], current: "", avatar: "" })
  property string status: ""
  // The settings layer covers the screen: step aside for the preview window,
  // the file chooser and the password dialog, and come back after.
  property bool reopen: false
  function stepAside() { if (page.host) page.host.dismiss() }

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
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(text) } catch (e) {}
        page.status = r.ok ? "Done. You'll see it at the next login." : (r.error || "Something went wrong.")
        page.reload()
        // Back after the file chooser / password dialog took the screen.
        if (page.reopen) Quickshell.execDetached(["omarchy-shell", "shell", "summon", "daa.settings", "{\"page\":\"login\"}"])
        page.reopen = false
      }
    }
  }
  function run(args, msg) {
    if (runner.running) return
    page.status = msg || ""
    if (args[0] !== "preview") page.reopen = true
    page.stepAside()
    runner.command = [page.tool].concat(args)
    runner.running = true
  }
  // "Choose…": a file chooser, then the change (with the password prompt).
  Process {
    id: chooser
    property var then: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text).trim()
        if (p) page.run(chooser.then.concat([p]), "Waiting for the password…")
        else Quickshell.execDetached(["omarchy-shell", "shell", "summon", "daa.settings", "{\"page\":\"login\"}"])
      }
    }
  }
  function choose(args) {
    if (chooser.running) return
    chooser.then = args
    page.stepAside()
    chooser.command = ["zenity", "--file-selection", "--title=Choose a picture",
      "--file-filter=Pictures | *.png *.jpg *.jpeg *.webp", "--filename=" + Quickshell.env("HOME") + "/Pictures/"]
    chooser.running = true
  }

  component SmallButton: Rectangle {
    id: btn
    property string label: ""
    property bool selected: false
    signal clicked()
    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.space(7)
    color: selected ? Util.alpha(page.accent, 0.3) : btnArea.containsMouse ? Util.alpha(page.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: btn.selected ? page.accent : page.fg
      font.family: page.font
      font.pixelSize: Style.font.caption
    }
    MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }
  component Heading: Text {
    x: Style.space(10)
    topPadding: Style.space(10)
    color: page.accent
    font.family: page.font
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }

  Text {
    x: Style.space(10)
    topPadding: Style.space(6)
    width: page.width - Style.space(20)
    text: "Preview opens the theme in a window (close it like any window). Changes ask for your password."
    color: page.fg
    opacity: 0.55
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.caption
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

  Heading { text: "Theme" }
  Repeater {
    model: page.info.themes
    Item {
      required property var modelData
      width: page.width
      height: Style.space(52)
      Rectangle {
        id: thumb
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(72)
        height: Style.space(42)
        radius: Style.space(5)
        color: Qt.rgba(1, 1, 1, 0.05)
        clip: true
        border.width: page.info.current === modelData.id ? 2 : 0
        border.color: page.accent
        Image {
          anchors.fill: parent
          anchors.margins: parent.border.width
          source: modelData.screenshot || modelData.background ? "file://" + (modelData.screenshot || modelData.background) : ""
          fillMode: Image.PreserveAspectCrop
          sourceSize.width: 160
          asynchronous: true
        }
      }
      Column {
        anchors.left: thumb.right
        anchors.leftMargin: Style.space(10)
        anchors.right: themeButtons.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
        Text { text: page.info.current === modelData.id ? "In use" : modelData.id; color: page.info.current === modelData.id ? page.accent : page.fg; opacity: page.info.current === modelData.id ? 1 : 0.5; font.family: page.font; font.pixelSize: Style.font.caption }
      }
      Row {
        id: themeButtons
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        SmallButton { label: "Preview"; onClicked: page.run(["preview", modelData.id], "Opening the preview…") }
        SmallButton {
          visible: !!modelData.background
          label: "Background…"
          onClicked: page.choose(["background", modelData.id])
        }
        SmallButton {
          visible: !!modelData.background
          label: "Use wallpaper"
          onClicked: page.run(["background", modelData.id, page.wallpaper], "Waiting for the password…")
        }
        SmallButton {
          visible: page.info.current !== modelData.id
          label: "Use"
          selected: true
          onClicked: page.run(["theme", modelData.id], "Waiting for the password…")
        }
      }
    }
  }

  Heading { text: "Your picture" }
  Row {
    x: Style.space(10)
    spacing: Style.space(10)
    Rectangle {
      width: Style.space(48)
      height: width
      radius: width / 2
      color: Qt.rgba(1, 1, 1, 0.06)
      clip: true
      Image {
        anchors.fill: parent
        source: page.info.avatar ? "file://" + page.info.avatar : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 96
        cache: false
      }
      Text { visible: !page.info.avatar; anchors.centerIn: parent; text: "󰀄"; color: page.fg; opacity: 0.5; font.family: Style.font.family; font.pixelSize: Style.font.title }
    }
    SmallButton { anchors.verticalCenter: parent.verticalCenter; label: "Choose picture…"; onClicked: page.choose(["avatar"]) }
  }
  Item { width: 1; height: Style.space(10) }
}
