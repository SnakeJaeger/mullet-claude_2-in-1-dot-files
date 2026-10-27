import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// SUPER + TAB (tablet mode: a diagonal swipe in from a screen corner): every
// open app outside the scratchpads, one row per workspace, each with a live
// preview. Tap a card to go to it, the x in its corner closes it, and dragging
// it onto another row (or "New workspace") moves it there.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property var clients: []
  property int activeWs: 1
  // Drag state: the card being dragged and the row under the pointer.
  property var dragging: null
  property int dropWs: 0
  property real dragX: 0
  property real dragY: 0

  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.pick("tablet.accent", Commons.Color.accent)
  readonly property color coral: Commons.Color.urgent
  readonly property string font: Style.font.menuFamily

  readonly property var rows: {
    var by = {}
    for (var i = 0; i < root.clients.length; i++) {
      var c = root.clients[i]
      if (!c.mapped || !c.workspace || c.workspace.id <= 0) continue
      ;(by[c.workspace.id] = by[c.workspace.id] || []).push(c)
    }
    var ids = Object.keys(by).map(Number).sort(function(a, b) { return a - b })
    var out = ids.map(function(id) {
      return { ws: id, windows: by[id].sort(function(a, b) { return (a.at[0] - b.at[0]) || (a.at[1] - b.at[1]) }) }
    })
    return out
  }
  // First workspace number with nothing on it, for "New workspace".
  readonly property int freeWs: {
    var used = {}
    for (var i = 0; i < root.rows.length; i++) used[root.rows[i].ws] = true
    for (var n = 1; n < 100; n++) if (!used[n]) return n
    return 100
  }

  function open(payloadJson) {
    root.dragging = null
    // A shown scratchpad / dropdown would sit on top of the overview.
    Quickshell.execDetached(["bash", "-c", "hyprctl monitors -j | jq -r '.[].specialWorkspace.name | select(. != \"\")' | " +
      "while read -r s; do hyprctl dispatch \"hl.dsp.workspace.toggle_special(\\\"${s#special:}\\\")\"; done"])
    refresh()
    Hyprland.refreshToplevels()
    root.opened = true
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.dragging = null
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "daa.overview")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refresh() {
    if (!snapshot.running) snapshot.running = true
  }

  function dispatch(lua) {
    Quickshell.execDetached(["hyprctl", "dispatch", lua])
  }

  function focusWindow(c) {
    root.dismiss()
    dispatch("hl.dsp.focus({ window = \"address:" + c.address + "\" })")
  }

  function closeWindow(c) {
    dispatch("hl.dsp.window.close({ window = \"address:" + c.address + "\" })")
    // Drop it from the list right away; the snapshot confirms shortly after.
    root.clients = root.clients.filter(function(x) { return x.address !== c.address })
    refreshLater.restart()
  }

  function moveWindow(c, ws) {
    if (!c || !ws || (c.workspace && c.workspace.id === ws)) return
    dispatch("hl.dsp.window.move({ window = \"address:" + c.address + "\", workspace = \"" + ws + "\", follow = false })")
    refreshLater.restart()
  }

  function toplevelFor(c) {
    var want = String(c.address).replace(/^0x/, "")
    var list = Hyprland.toplevels.values || []
    for (var i = 0; i < list.length; i++)
      if (String(list[i].address).replace(/^0x/, "") === want) return list[i].wayland
    return null
  }

  function appIcon(c) {
    var app = DesktopEntries.heuristicLookup(c.class)
    var name = app && app.icon ? String(app.icon) : String(c.class || "")
    return name ? Quickshell.iconPath(name, true) : ""
  }

  function appName(c) {
    var app = DesktopEntries.heuristicLookup(c.class)
    return app ? String(app.name) : String(c.class || "")
  }

  Timer { id: refreshLater; interval: 250; onTriggered: root.refresh() }

  Process {
    id: snapshot
    command: ["bash", "-c", "printf '{\"clients\":%s,\"ws\":%s}' \"$(hyprctl clients -j)\" \"$(hyprctl activeworkspace -j)\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          root.clients = d.clients || []
          if (d.ws && d.ws.id > 0) root.activeWs = d.ws.id
        } catch (e) {}
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "daa-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: if (visible) popIn.restart()
    ParallelAnimation {
      id: popIn
      NumberAnimation { target: dim; property: "opacity"; from: 0; to: 1; duration: 140 }
      NumberAnimation { target: body; property: "opacity"; from: 0; to: 1; duration: 140 }
      NumberAnimation { target: body; property: "scale"; from: 0.97; to: 1; duration: 170; easing.type: Easing.OutCubic }
    }

    Rectangle {
      id: dim
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.62)
    }

    // Empty space closes it.
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keys
      focus: true
      Keys.onEscapePressed: root.dismiss()
      Keys.onTabPressed: root.dismiss()
    }

    Item {
      id: body
      anchors.fill: parent
      anchors.margins: Style.space(40)

      Text {
        id: heading
        text: "Open apps"
        color: root.fg
        font.family: root.font
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        anchors.left: heading.right
        anchors.leftMargin: Style.space(16)
        anchors.baseline: heading.baseline
        text: "tap to go  ·  drag to another workspace  ·  x closes  ·  Esc"
        color: root.fg
        opacity: 0.5
        font.family: root.font
        font.pixelSize: Style.font.caption
      }

      Flickable {
        id: flick
        anchors.top: heading.bottom
        anchors.topMargin: Style.space(18)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: list.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.dragging
        clip: true

        Column {
          id: list
          width: flick.width
          spacing: Style.space(12)

          Text {
            visible: root.rows.length === 0
            text: "Nothing open."
            color: root.fg
            opacity: 0.6
            font.family: root.font
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.rows.concat([{ ws: -1, windows: [] }])
            Rectangle {
              id: row
              required property var modelData
              readonly property bool isNew: modelData.ws === -1
              readonly property int target: isNew ? root.freeWs : modelData.ws
              readonly property bool hot: !!root.dragging && root.dropWs === target && root.dragging.workspace.id !== target
              visible: !isNew || !!root.dragging
              width: list.width
              height: isNew ? Style.space(70) : cards.implicitHeight + Style.space(20)
              radius: Style.space(12)
              color: hot ? Util.alpha(root.accent, 0.16) : Qt.rgba(1, 1, 1, modelData.ws === root.activeWs ? 0.07 : 0.035)
              border.width: hot ? 2 : 0
              border.color: root.accent
              Behavior on color { ColorAnimation { duration: 90 } }

              // Tells the drag which row the pointer is over.
              function contains(px, py) {
                var p = row.mapFromItem(panel.contentItem, px, py)
                return visible && p.x >= 0 && p.y >= 0 && p.x < width && p.y < height
              }
              Component.onCompleted: rowRegistry.add(row)
              Component.onDestruction: rowRegistry.remove(row)

              // Workspace number; tap to go there.
              Rectangle {
                id: wsTag
                x: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(46)
                height: width
                radius: Style.space(10)
                color: wsArea.containsMouse ? Util.alpha(root.accent, 0.2) : "transparent"
                Text {
                  anchors.centerIn: parent
                  text: row.isNew ? "+" : row.modelData.ws
                  color: row.modelData.ws === root.activeWs || row.hot ? root.accent : root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.title * 1.3
                  font.bold: true
                }
                MouseArea {
                  id: wsArea
                  anchors.fill: parent
                  enabled: !row.isNew
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.dismiss(); root.dispatch("hl.dsp.focus({ workspace = \"" + row.modelData.ws + "\" })") }
                }
              }

              Text {
                visible: row.isNew
                anchors.left: wsTag.right
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: "Drop here for a new workspace (" + root.freeWs + ")"
                color: row.hot ? root.accent : root.fg
                opacity: row.hot ? 1 : 0.6
                font.family: root.font
                font.pixelSize: Style.font.body
              }

              Flow {
                id: cards
                anchors.left: wsTag.right
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(12)

                Repeater {
                  model: row.modelData.windows
                  Item {
                    id: card
                    required property var modelData
                    readonly property bool lifted: root.dragging && root.dragging.address === modelData.address
                    readonly property real aspect: modelData.size && modelData.size[1] > 0 ? modelData.size[0] / modelData.size[1] : 1.6
                    width: Style.space(236)
                    height: Style.space(176)
                    opacity: lifted ? 0.3 : 1

                    Rectangle {
                      id: frame
                      anchors.fill: parent
                      radius: Style.space(10)
                      color: Util.alpha(Commons.Color.menu.background, 0.96)
                      border.width: cardArea.containsMouse && !root.dragging ? 2 : 1
                      border.color: cardArea.containsMouse && !root.dragging ? root.accent : Qt.rgba(1, 1, 1, 0.1)

                      Item {
                        id: shot
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: caption.top
                        anchors.margins: Style.space(8)

                        ScreencopyView {
                          id: preview
                          anchors.centerIn: parent
                          width: Math.min(parent.width, parent.height * card.aspect)
                          height: width / card.aspect
                          captureSource: root.opened ? root.toplevelFor(card.modelData) : null
                          live: false
                        }
                        // Until (or unless) a preview arrives: the app's icon.
                        Image {
                          anchors.centerIn: parent
                          visible: !preview.hasContent
                          width: Style.space(56)
                          height: width
                          source: root.appIcon(card.modelData)
                          sourceSize.width: width * 2
                          sourceSize.height: height * 2
                        }
                      }

                      Row {
                        id: caption
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Style.space(8)
                        spacing: Style.space(6)
                        Image {
                          width: Style.space(18)
                          height: width
                          anchors.verticalCenter: parent.verticalCenter
                          source: root.appIcon(card.modelData)
                          sourceSize.width: width * 2
                          sourceSize.height: height * 2
                        }
                        Text {
                          width: parent.width - Style.space(24)
                          anchors.verticalCenter: parent.verticalCenter
                          elide: Text.ElideRight
                          text: card.modelData.title || root.appName(card.modelData)
                          color: root.fg
                          font.family: root.font
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }

                    MouseArea {
                      id: cardArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                      preventStealing: true
                      property point start
                      property bool moved: false
                      onPressed: function(mouse) { start = Qt.point(mouse.x, mouse.y); moved = false }
                      onPositionChanged: function(mouse) {
                        if (!pressed) return
                        if (!moved && Math.abs(mouse.x - start.x) + Math.abs(mouse.y - start.y) < 12) return
                        moved = true
                        var p = cardArea.mapToItem(panel.contentItem, mouse.x, mouse.y)
                        root.dragX = p.x
                        root.dragY = p.y
                        if (!root.dragging) {
                          root.dragging = card.modelData
                          ghost.grabX = mouse.x
                          ghost.grabY = mouse.y
                        }
                        root.dropWs = rowRegistry.hit(p.x, p.y)
                      }
                      onReleased: {
                        if (root.dragging) {
                          var c = root.dragging
                          var ws = root.dropWs
                          root.dragging = null
                          root.moveWindow(c, ws)
                        } else if (!moved) {
                          root.focusWindow(card.modelData)
                        }
                      }
                      onCanceled: root.dragging = null
                    }

                    // Close: the x in the corner.
                    Rectangle {
                      anchors.top: parent.top
                      anchors.right: parent.right
                      anchors.margins: -Style.space(7)
                      width: Style.space(28)
                      height: width
                      radius: width / 2
                      visible: !card.lifted
                      color: xArea.containsMouse ? root.coral : Commons.Color.menu.background
                      border.width: 1
                      border.color: xArea.containsMouse ? root.coral : Qt.rgba(1, 1, 1, 0.25)
                      Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        color: xArea.containsMouse ? Commons.Color.menu.background : root.fg
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }
                      MouseArea {
                        id: xArea
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeWindow(card.modelData)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // The card under the finger / pointer while dragging.
    Rectangle {
      id: ghost
      property real grabX: 0
      property real grabY: 0
      visible: !!root.dragging
      x: root.dragX - grabX
      y: root.dragY - grabY
      width: Style.space(236)
      height: Style.space(176)
      radius: Style.space(10)
      color: Util.alpha(Commons.Color.menu.background, 0.96)
      border.width: 2
      border.color: root.accent
      rotation: -2
      Image {
        anchors.centerIn: parent
        width: Style.space(56)
        height: width
        source: root.dragging ? root.appIcon(root.dragging) : ""
        sourceSize.width: width * 2
        sourceSize.height: height * 2
      }
      Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Style.space(10)
        width: parent.width - Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.dragging ? (root.dropWs ? "to workspace " + root.dropWs : root.appName(root.dragging)) : ""
        color: root.dropWs ? root.accent : root.fg
        font.family: root.font
        font.pixelSize: Style.font.caption
      }
    }

    QtObject {
      id: rowRegistry
      property var items: []
      function add(r) { items = items.concat([r]) }
      function remove(r) { items = items.filter(function(x) { return x !== r }) }
      function hit(px, py) {
        for (var i = 0; i < items.length; i++)
          if (items[i].contains(px, py)) return items[i].target
        return 0
      }
    }
  }
}
