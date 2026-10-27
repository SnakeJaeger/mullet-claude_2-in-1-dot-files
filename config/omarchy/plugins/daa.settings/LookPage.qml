import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Look (Desktop settings → Look): icon theme (or follow the Omarchy theme's
// own) and cursor theme + size, through ~/.local/bin/appearance-tool.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/appearance-tool"

  spacing: Style.space(4)

  property var info: ({ icons: [], cursors: [], icon: "", cursor: "", cursorSize: 24, iconFollowsTheme: true, themeIcons: "" })

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
  component Pill: Rectangle {
    id: pill
    property string label: ""
    property bool current: false
    signal clicked()
    width: pillLabel.implicitWidth + Style.space(18)
    height: Style.space(24)
    radius: height / 2
    color: current ? page.accent : pillArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
    Text {
      id: pillLabel
      anchors.centerIn: parent
      text: pill.label
      color: pill.current ? Commons.Color.background : page.fg
      font.family: page.font
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea { id: pillArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
  }

  Heading { text: "Icons" }
  Hint { text: "Apps pick up a new icon theme as they restart. Follow theme uses each Omarchy theme's own (" + (page.info.themeIcons || "?") + ")." }
  Flow {
    x: Style.space(10)
    width: page.width - Style.space(20)
    spacing: Style.space(5)
    Pill { label: "Follow theme"; current: page.info.iconFollowsTheme; onClicked: page.run(["icons", "theme"]) }
    Repeater {
      model: page.info.icons
      Pill {
        required property var modelData
        label: modelData.name
        current: !page.info.iconFollowsTheme && page.info.icon === modelData.id
        onClicked: page.run(["icons", modelData.id])
      }
    }
  }

  Heading { text: "Cursor" }
  Hint { text: "Changes now; apps started before the change catch up at the next login." }
  Flow {
    x: Style.space(10)
    width: page.width - Style.space(20)
    spacing: Style.space(5)
    Repeater {
      model: page.info.cursors
      Pill {
        required property var modelData
        label: modelData.name
        current: page.info.cursor === modelData.id
        onClicked: page.run(["cursor", modelData.id, String(page.info.cursorSize)])
      }
    }
  }
  Row {
    x: Style.space(10)
    topPadding: Style.space(6)
    spacing: Style.space(5)
    Text { text: "Size"; width: Style.space(50); color: page.fg; opacity: 0.75; font.family: page.font; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
    Repeater {
      model: [24, 32, 40, 48]
      Pill {
        required property var modelData
        label: String(modelData)
        current: page.info.cursorSize === modelData
        onClicked: page.run(["cursor", page.info.cursor, String(modelData)])
      }
    }
  }
  Item { width: 1; height: Style.space(10) }
}
