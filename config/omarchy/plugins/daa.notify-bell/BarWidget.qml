import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui

// Notification bell at the right end of the right island, with the count
// beside it (toasts on screen plus history, the files daa.notifications
// keeps under ~/.local/state/omarchy/notifications). Up to 5 it sits still;
// past 5 it slowly pulses cyan (the accent), past 10 coral (the theme's red).
// Hover or click slides a panel in from the right edge with every
// notification: click one to run its action (or focus its app) and drop it,
// × drops it, Clear all drops everything.
BarWidget {
  id: root
  moduleName: "daa.notify-bell"

  // Desktop UI settings (daa.settings writes ~/.config/omarchy/daa-ui.json;
  // a missing key means its default, i.e. on).
  property var ui: ({})
  function uiOpt(key, fallback) {
    // Calm mode (power-saver; daa.settings writes ~/.local/state/daa/calm):
    // the decorative animations pause, whatever their own switches say.
    if (root.calm && root.calmKeys.indexOf(key) !== -1) return false
    var v = root.ui ? root.ui[key] : undefined; return v === undefined || v === null ? fallback : v
  }
  readonly property var calmKeys: ["goMenuAnimations", "duel", "launcherTrails", "shortcutCardAnimations",
    "shortcutCardTrails", "workspaceSpring", "magellanic", "breathingBorders", "barAlertPulse"]
  property bool calm: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/daa/calm"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.calm = String(text()).trim() === "1"
    onLoadFailed: root.calm = false
  }
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/daa-ui.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.ui = JSON.parse(text() || "{}") } catch (e) {} }
    onLoadFailed: root.ui = ({})   // file deleted: all defaults
  }

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications"
  readonly property string historyDir: stateDir + "/history"
  readonly property int count: liveFiles.count + historyFiles.count
  readonly property color coral: Color.urgent
  readonly property color barForeground: root.bar ? root.bar.barForeground : Color.foreground

  property bool open: false
  property bool buttonHovered: false
  property bool panelHovered: false
  property var rows: []

  implicitWidth: content.implicitWidth
  implicitHeight: button.implicitHeight

  // Both directories are watched, so the count follows toasts arriving,
  // expiring into history and being cleared.
  FolderListModel {
    id: liveFiles
    folder: "file://" + root.stateDir
    nameFilters: ["*.json"]
    showDirs: false
    onCountChanged: if (root.open) root.reload()
  }
  FolderListModel {
    id: historyFiles
    folder: "file://" + root.historyDir
    nameFilters: ["*.json"]
    showDirs: false
    onCountChanged: if (root.open) root.reload()
  }

  // Slow pulse once more than 5 are waiting.
  property real pulse: 0
  SequentialAnimation on pulse {
    // Settings: "barAlertPulse" off = steady colour.
    running: root.count > 5 && root.uiOpt("barAlertPulse", true)
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0; duration: 1100; easing.type: Easing.InOutSine }
    onRunningChanged: if (!running) root.pulse = 0
  }

  function mix(a, b, k) {
    return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k)
  }
  readonly property color pulseColor: count > 10 ? coral : Color.accent
  readonly property color tint: count > 5 ? mix(barForeground, pulseColor, 0.35 + 0.65 * pulse) : barForeground

  function setHover(which, value) {
    if (which === "button") buttonHovered = value
    else panelHovered = value
    if (buttonHovered || panelHovered) {
      closeTimer.stop()
      if (!open) openTimer.restart()
    } else {
      openTimer.stop()
      closeTimer.restart()
    }
  }

  Timer {
    id: openTimer
    interval: 250
    onTriggered: if (!root.vertical && !(root.bar && root.bar.activePopout)) root.open = true
  }
  Timer {
    id: closeTimer
    interval: 300
    onTriggered: root.open = false
  }

  onOpenChanged: {
    if (open) {
      // The bar spans the screen, so its root item's width is the screen's.
      var top = root
      while (top.parent) top = top.parent
      var win = root.QsWindow.window
      panel.screenHeight = win && win.screen ? win.screen.height : 900
      var p = root.mapToItem(null, 0, 0)
      panel.anchorX = Math.round(top.width - Style.space(10) - panel.panelWidth - p.x)
      panel.anchorY = Math.round(root.barSize + Style.space(6) - p.y)
      reload()
    }
    slide.stop()
    slide.to = open ? 1 : 0
    slide.duration = open ? 260 : 180
    slide.easing.type = open ? Easing.OutCubic : Easing.InCubic
    slide.start()
  }

  property real shown: 0
  NumberAnimation { id: slide; target: root; property: "shown" }

  // Every notification as "path<TAB>json", one per line.
  Process {
    id: readProc
    command: ["bash", "-c",
      "for f in \"$1\"/*.json \"$2\"/*.json; do [[ -e $f ]] || continue; printf '%s\\t' \"$f\"; head -n1 \"$f\"; echo; done",
      "--", root.stateDir, root.historyDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var tab = lines[i].indexOf("\t")
          if (tab < 0) continue
          try {
            var entry = JSON.parse(lines[i].slice(tab + 1))
            entry.path = lines[i].slice(0, tab)
            entry.live = entry.path.indexOf("/history/") < 0
            list.push(entry)
          } catch (e) {}
        }
        list.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
        root.rows = list
      }
    }
  }

  function reload() {
    if (readProc.running) reloadAgain.restart()
    else readProc.running = true
  }
  Timer { id: reloadAgain; interval: 150; onTriggered: root.reload() }

  // Toasts still on screen are taken down through the service (which moves
  // them into history), then their history copy is deleted along with any
  // images; history entries are just deleted.
  function remove(entry) {
    var name = entry.path.slice(entry.path.lastIndexOf("/") + 1)
    var stem = name.replace(/\.json$/, "")
    var script = (entry.live ? "omarchy-shell -q notifications dismiss \"$3\"; sleep 0.6; " : "")
      + "rm -f \"$1/history/$2\" \"$1/$2\" \"$1/images/$4\"-*"
    Util.execArgv(["bash", "-c", script, "--", root.stateDir, name, String(entry.summary || ""), stem])
  }

  function activate(entry) {
    var argv = []
    try { argv = entry.execArgv ? JSON.parse(entry.execArgv) : [] } catch (e) { argv = [] }
    if (argv && argv.length) Util.execArgv(argv)
    else if (entry.app && entry.app !== "omarchy-action")
      Util.execArgv([Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-hyprland-focus-app", String(entry.app)])
    remove(entry)
    open = false
  }

  function clearAll() {
    Util.execDetached("omarchy-shell -q notifications dismissAll; sleep 0.6; omarchy-shell -q notifications clear")
    rows = []
  }

  function ago(ts) {
    var s = Math.max(0, Math.floor((Date.now() - ts) / 1000))
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }

  HoverHandler {
    onHoveredChanged: root.setHover("button", hovered)
    Component.onDestruction: if (hovered) root.setHover("button", false)
  }

  Row {
    id: content
    anchors.verticalCenter: parent.verticalCenter

    BarIconButton {
      id: button
      bar: root.bar
      text: root.count > 0 ? "󰂚" : "󰂜"
      foreground: root.tint
      tooltipText: ""
      onPressed: function(mouseButton) { root.open = !root.open }
    }

    Text {
      visible: root.count > 0
      anchors.verticalCenter: parent.verticalCenter
      rightPadding: Style.space(4)
      text: root.count
      color: root.tint
      font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
      font.pixelSize: Style.font.bodySmall
    }
  }

  PopupWindow {
    id: panel

    readonly property int panelWidth: Style.space(380)
    property real screenHeight: 900
    readonly property int maxHeight: Math.round(screenHeight * 0.75)
    property int anchorX: 0
    property int anchorY: 0

    visible: root.open || root.shown > 0
    color: "transparent"
    implicitWidth: panelWidth
    implicitHeight: Math.min(maxHeight, column.implicitHeight + Style.space(24))

    anchor {
      item: root
      adjustment: PopupAdjustment.None
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.x: panel.anchorX
      rect.y: panel.anchorY
      rect.width: 1
      rect.height: 1
    }

    // Slides in from past the right edge of the screen.
    Rectangle {
      id: sheet
      width: parent.width
      height: parent.height
      x: (1 - root.shown) * (parent.width + Style.space(12))
      radius: Style.space(14)
      color: Color.menu.background
      clip: true

      HoverHandler {
        onHoveredChanged: root.setHover("panel", hovered)
      }

      Column {
        id: column
        x: Style.space(12)
        y: Style.space(12)
        width: parent.width - Style.space(24)
        spacing: Style.space(8)

        // Notifications              Clear all
        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, clearButton.implicitHeight)

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.rows.length ? "Notifications  " + root.rows.length : "Notifications"
            color: Color.menu.text
            opacity: 0.7
            font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
            font.pixelSize: Style.font.body
          }

          Rectangle {
            id: clearButton
            visible: root.rows.length > 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: clearLabel.implicitWidth + Style.space(20)
            implicitHeight: clearLabel.implicitHeight + Style.space(8)
            radius: Style.space(8)
            color: clearArea.containsMouse ? Util.alpha(root.coral, 0.22) : Qt.rgba(1, 1, 1, 0.06)
            Text {
              id: clearLabel
              anchors.centerIn: parent
              text: "Clear all"
              color: clearArea.containsMouse ? root.coral : Color.menu.text
              font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: clearArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.clearAll()
            }
          }
        }

        Text {
          visible: root.rows.length === 0
          width: parent.width
          topPadding: Style.space(10)
          bottomPadding: Style.space(10)
          horizontalAlignment: Text.AlignHCenter
          text: "No notifications"
          color: Color.menu.text
          opacity: 0.5
          font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
          font.pixelSize: Style.font.body
        }

        ListView {
          id: list
          visible: root.rows.length > 0
          width: parent.width
          height: Math.min(contentHeight, panel.maxHeight - Style.space(24) - y)
          clip: true
          spacing: Style.space(4)
          boundsBehavior: Flickable.StopAtBounds
          model: root.rows

          delegate: Rectangle {
            id: rowItem
            required property var modelData
            required property int index
            width: list.width
            height: rowContent.implicitHeight + Style.space(16)
            radius: Style.space(10)
            color: rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03)
            Behavior on color { ColorAnimation { duration: 90 } }
            // Each row slides in a beat after the one above.
            opacity: Math.max(0, Math.min(1, root.shown * 3 - index * 0.25))

            MouseArea {
              id: rowArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.activate(rowItem.modelData)
            }

            Row {
              id: rowContent
              x: Style.space(10)
              y: Style.space(8)
              width: parent.width - Style.space(20)
              spacing: Style.space(10)

              Text {
                id: glyph
                width: Style.space(22)
                text: rowItem.modelData.glyph || "󰂚"
                color: rowItem.modelData.urgency === 2 ? root.coral : Color.accent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.heading
              }

              Column {
                width: parent.width - glyph.width - closeX.width - parent.spacing * 2
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: (rowItem.modelData.app === "omarchy-action" ? "Omarchy" : (rowItem.modelData.app || ""))
                    + "  ·  " + root.ago(rowItem.modelData.timestamp || 0)
                  color: Color.menu.text
                  opacity: 0.5
                  elide: Text.ElideRight
                  font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
                  font.pixelSize: Style.font.caption
                }
                Text {
                  width: parent.width
                  text: rowItem.modelData.summary || ""
                  color: Color.menu.text
                  elide: Text.ElideRight
                  font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  visible: text !== ""
                  width: parent.width
                  text: rowItem.modelData.body || ""
                  textFormat: Text.PlainText
                  color: Color.menu.text
                  opacity: 0.75
                  wrapMode: Text.Wrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                  font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Text {
                id: closeX
                width: Style.space(18)
                text: "󰅖"
                color: closeArea.containsMouse ? root.coral : Color.menu.text
                opacity: rowArea.containsMouse || closeArea.containsMouse ? 0.9 : 0.35
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.body
                MouseArea {
                  id: closeArea
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.remove(rowItem.modelData)
                }
              }
            }
          }
        }
      }
    }
  }
}
