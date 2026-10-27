import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar menu (Desktop settings → Bar): switch the fixed islands (logo card, app
// name, now playing) off and on, hide / show / reorder the widgets in
// shell.json's bar layout, pick the clock's format, and choose what the info
// bar (with the quick search) shows, including its quotes.
// Islands are daa-ui.json keys (read by daa.desktop-bar/Bar.qml); widgets go
// through ~/.local/bin/bar-tool, which edits shell.json and remembers hidden
// widgets (with their settings) in daa-bar-hidden.json.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/bar-tool"

  spacing: Style.space(4)

  property var layout: ({ regions: { left: [], center: [], right: [] }, hidden: [], clock: "" })

  readonly property var islands: [
    ["barLogo", "Omarchy logo card", "The shortcut card next to the workspaces"],
    ["barAppName", "App name", "Focused app, with the open-windows dropdown"],
    ["barMedia", "Now playing", "Between the app name and the clock"]
  ]
  readonly property var infoItems: [
    ["infoEvent", "Next calendar event", "Under the date"],
    ["infoWeather", "Weather", "Next to the clock"],
    ["infoBattery", "Battery line", "Right side"],
    ["infoNetwork", "Network line", "Right side"],
    ["infoBluetooth", "Bluetooth line", "Right side"],
    ["infoQuote", "Quote", "Along the bottom; a new one every 6 hours"]
  ]
  readonly property string quotesPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.infobar/quotes.txt"
  property string quotesStatus: ""
  FileView {
    id: quotesFile
    path: page.quotesPath
    printErrors: false
    onLoaded: quotesEdit.text = text()
  }
  readonly property var regionNames: [["left", "Left"], ["center", "Centre"], ["right", "Right"]]
  readonly property var clockFormats: [
    ["dddd HH:mm", "Sunday 16:41"], ["ddd h:mm AP", "Sun 4:41 PM"], ["HH:mm", "16:41"],
    ["h:mm AP", "4:41 PM"], ["ddd d MMM HH:mm", "Sun 25 Oct 16:41"], ["HH:mm:ss", "16:41:07"]
  ]

  function uiOn(key) {
    var v = page.host ? page.host.ui[key] : undefined
    return v === undefined || v === null ? true : v
  }
  function reload() { if (!lister.running) lister.running = true }
  Component.onCompleted: reload()

  Process {
    id: lister
    command: [page.tool, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { page.layout = JSON.parse(text) } catch (e) {} }
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
    property bool selected: false
    signal clicked()
    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.space(7)
    color: selected ? Util.alpha(page.accent, 0.25) : btnArea.containsMouse ? Util.alpha(page.accent, 0.15) : Qt.rgba(1, 1, 1, 0.06)
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

  Heading { text: "Islands" }
  Repeater {
    model: page.islands
    Item {
      required property var modelData
      width: page.width
      height: Style.space(40)
      Column {
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        Text { text: modelData[1]; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
        Text { text: modelData[2]; color: page.fg; opacity: 0.55; font.family: page.font; font.pixelSize: Style.font.caption }
      }
      Rectangle {
        id: sw
        readonly property bool on: page.uiOn(modelData[0])
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(38)
        height: Style.space(20)
        radius: height / 2
        color: on ? Util.alpha(page.accent, 0.6) : Qt.rgba(1, 1, 1, 0.12)
        Rectangle {
          width: parent.height - Style.space(4)
          height: width
          radius: width / 2
          y: Style.space(2)
          x: sw.on ? parent.width - width - Style.space(2) : Style.space(2)
          color: sw.on ? page.accent : page.fg
          Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: if (page.host) page.host.set(modelData[0], !sw.on)
        }
      }
    }
  }

  Heading { text: "Info bar (quick search)" }
  Repeater {
    model: page.infoItems
    Item {
      required property var modelData
      width: page.width
      height: Style.space(40)
      Column {
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        Text { text: modelData[1]; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
        Text { text: modelData[2]; color: page.fg; opacity: 0.55; font.family: page.font; font.pixelSize: Style.font.caption }
      }
      Rectangle {
        id: isw
        readonly property bool on: page.uiOn(modelData[0])
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(38)
        height: Style.space(20)
        radius: height / 2
        color: on ? Util.alpha(page.accent, 0.6) : Qt.rgba(1, 1, 1, 0.12)
        Rectangle {
          width: parent.height - Style.space(4)
          height: width
          radius: width / 2
          y: Style.space(2)
          x: isw.on ? parent.width - width - Style.space(2) : Style.space(2)
          color: isw.on ? page.accent : page.fg
          Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: if (page.host) page.host.set(modelData[0], !isw.on)
        }
      }
    }
  }
  Text {
    x: Style.space(10)
    topPadding: Style.space(6)
    text: "Quotes: one per line, \"text — author\"; lines starting with # are skipped."
    color: page.fg
    opacity: 0.55
    font.family: page.font
    font.pixelSize: Style.font.caption
  }
  Rectangle {
    x: Style.space(10)
    width: page.width - Style.space(20)
    height: Style.space(160)
    radius: Style.space(8)
    color: Qt.rgba(1, 1, 1, 0.05)
    Flickable {
      id: quotesFlick
      anchors.fill: parent
      anchors.margins: Style.space(8)
      clip: true
      contentHeight: quotesEdit.contentHeight
      boundsBehavior: Flickable.StopAtBounds
      TextEdit {
        id: quotesEdit
        width: quotesFlick.width
        wrapMode: TextEdit.Wrap
        color: page.fg
        selectByMouse: true
        font.family: page.font
        font.pixelSize: Style.font.caption
        onCursorRectangleChanged: {
          if (cursorRectangle.y < quotesFlick.contentY) quotesFlick.contentY = cursorRectangle.y
          else if (cursorRectangle.y + cursorRectangle.height > quotesFlick.contentY + quotesFlick.height)
            quotesFlick.contentY = cursorRectangle.y + cursorRectangle.height - quotesFlick.height
        }
      }
    }
  }
  Row {
    x: Style.space(10)
    spacing: Style.space(8)
    SmallButton {
      label: "Save quotes"
      onClicked: {
        quotesFile.setText(quotesEdit.text.replace(/\s*$/, "") + "\n")
        page.quotesStatus = "Saved " + quotesEdit.text.split("\n").filter(function(l) { return l.trim() && l.trim().charAt(0) !== "#" }).length + " quotes."
      }
    }
    SmallButton { label: "Undo changes"; onClicked: { quotesFile.reload(); page.quotesStatus = "" } }
    Text { text: page.quotesStatus; color: page.fg; opacity: 0.6; font.family: page.font; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
  }

  Heading { text: "Clock" }
  Flow {
    x: Style.space(10)
    width: page.width - Style.space(20)
    spacing: Style.space(6)
    Repeater {
      model: page.clockFormats
      SmallButton {
        required property var modelData
        label: modelData[1]
        selected: page.layout.clock === modelData[0]
        onClicked: page.run(["clock", modelData[0]])
      }
    }
  }

  Heading { text: "Widgets" }
  Text {
    x: Style.space(10)
    width: page.width - Style.space(20)
    text: "◀ ▶ move a widget within its side of the bar. Hidden widgets keep their settings."
    color: page.fg
    opacity: 0.55
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.caption
  }
  Repeater {
    model: page.regionNames
    Column {
      id: region
      required property var modelData
      readonly property var items: page.layout.regions[modelData[0]] || []
      width: page.width
      Text {
        x: Style.space(10)
        topPadding: Style.space(6)
        text: region.modelData[1]
        color: page.fg
        opacity: 0.7
        font.family: page.font
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Repeater {
        model: region.items
        Item {
          required property var modelData
          required property int index
          width: page.width
          height: Style.space(30)
          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            radius: Style.space(6)
            color: rowHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
            HoverHandler { id: rowHover }
          }
          Text {
            x: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: page.fg
            font.family: page.font
            font.pixelSize: Style.font.body
          }
          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            SmallButton { label: "◀"; opacity: index > 0 ? 1 : 0.25; onClicked: if (index > 0) page.run(["move", modelData.id, "-1"]) }
            SmallButton { label: "▶"; opacity: index < region.items.length - 1 ? 1 : 0.25; onClicked: if (index < region.items.length - 1) page.run(["move", modelData.id, "1"]) }
            SmallButton { label: "Hide"; visible: !modelData.locked; onClicked: page.run(["hide", modelData.id]) }
          }
        }
      }
    }
  }

  Heading { text: "Hidden"; visible: page.layout.hidden.length > 0 }
  Repeater {
    model: page.layout.hidden
    Item {
      required property var modelData
      width: page.width
      height: Style.space(30)
      Text {
        x: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.label
        color: page.fg
        opacity: 0.6
        font.family: page.font
        font.pixelSize: Style.font.body
      }
      SmallButton {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        label: "Show"
        onClicked: page.run(["show", modelData.id])
      }
    }
  }
  Item { width: 1; height: Style.space(10) }
}
