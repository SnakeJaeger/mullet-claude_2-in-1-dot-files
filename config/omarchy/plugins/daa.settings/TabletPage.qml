import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Tablet (Desktop settings → Tablet): the greeter's tiles (daa.tablet-greeter),
// tablet mode's own colour and wallpaper. The switches and sliders below this
// (greeter, tablet bar size and style, text size) are ordinary `sections`
// rows in Settings.qml. Colour and text size reach the shell through
// `tablet-mode restyle`; the wallpaper is ~/.local/state/tablet-mode/background-tablet,
// which tablet mode applies on entry.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property string home: Quickshell.env("HOME")
  readonly property string tabletTool: page.home + "/.local/bin/tablet-mode"

  spacing: Style.space(4)

  // Keep in step with Greeter.qml's defaultTiles.
  readonly property var defaultTiles: [
    { id: "clock", size: "w" }, { id: "org.jellyfin.JellyfinDesktop", size: "l" }, { id: "org.gnome.Showtime", size: "s" },
    { id: "com.github.johnfactotum.Foliate", size: "s" }, { id: "info.febvre.Komikku", size: "s" },
    { id: "Kindle", size: "s" }, { id: "battery", size: "s" }, { id: "org.kde.krita", size: "w" },
    { id: "com.github.flxzt.rnote", size: "s" }, { id: "com.github.xournalpp.xournalpp", size: "s" },
    { id: "org.es_de.frontend", size: "s" }, { id: "com.libretro.RetroArch", size: "s" }, { id: "steam", size: "s" },
    { id: "firefox", size: "w" }
  ]
  readonly property var specials: ({ clock: ["Clock", "󰥔"], battery: ["Battery", "󰁹"], apps: ["All apps", "󰀻"] })
  readonly property var tiles: page.host && Array.isArray(page.host.ui.tabletTiles) ? page.host.ui.tabletTiles : page.defaultTiles
  readonly property string defaultAccent: "#ff6b81"
  readonly property string tabletAccent: page.host && page.host.ui.tabletAccent ? page.host.ui.tabletAccent : page.defaultAccent

  function setTiles(list) { page.host.set("tabletTiles", list) }
  function copyTiles() { return page.tiles.map(function(t) { return { id: t.id, size: t.size } }) }
  function moveTile(i, d) {
    var l = page.copyTiles(), j = i + d
    if (j < 0 || j >= l.length) return
    var t = l[i]; l[i] = l[j]; l[j] = t
    page.setTiles(l)
  }
  function sizeTile(i, s) { var l = page.copyTiles(); l[i].size = s; page.setTiles(l) }
  function removeTile(i) { var l = page.copyTiles(); l.splice(i, 1); page.setTiles(l) }
  function addTile(id) { var l = page.copyTiles(); l.push({ id: id, size: "s" }); page.setTiles(l); page.addQuery = "" }
  function tileName(id) {
    if (page.specials[id]) return page.specials[id][0]
    var app = DesktopEntries.byId(id)
    return app ? String(app.name) : id + " (not installed)"
  }
  function tileIcon(id) {
    if (page.specials[id]) return ""
    var app = DesktopEntries.byId(id)
    return app && page.host ? page.host.appIcon(app) : ""
  }

  // Colour and text size apply through tablet-mode (it rewrites the shell's
  // tablet overlay, only while tablet mode is on).
  property string lastStyle: ""
  Connections {
    target: page.host
    function onUiChanged() {
      var s = String(page.host.ui.tabletAccent || "") + "|" + String(page.host.ui.tabletTextScale || "")
      if (page.lastStyle !== "" && s !== page.lastStyle) restyleTimer.restart()
      page.lastStyle = s
    }
  }
  onHostChanged: if (page.host) page.lastStyle = String(page.host.ui.tabletAccent || "") + "|" + String(page.host.ui.tabletTextScale || "")
  Timer { id: restyleTimer; interval: 700; onTriggered: Quickshell.execDetached([page.tabletTool, "restyle"]) }

  // ---- Wallpapers: the current theme's, Aether's, ~/Pictures/Wallpapers ----
  property var wallpapers: []
  property string tabletWallpaper: ""
  function reload() {
    if (!wallLister.running) wallLister.running = true
  }
  Process {
    id: wallLister
    command: ["bash", "-c",
      "cat ~/.local/state/tablet-mode/background-tablet 2>/dev/null | head -1; echo ---; " +
      "theme=$(cat ~/.local/state/omarchy/current/theme.name 2>/dev/null); " +
      "for d in ~/.config/omarchy/backgrounds/\"$theme\" ~/.local/state/omarchy/current/theme/backgrounds ~/.local/share/aether/wallpapers ~/Pictures/Wallpapers; do " +
      "[[ -d $d ]] && find -L \"$d\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\); done | " +
      "while read -r f; do readlink -f \"$f\"; done | awk '!seen[$0]++' | head -60"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split("---\n")
        page.tabletWallpaper = String(parts[0] || "").trim()
        page.wallpapers = String(parts[1] || "").split("\n").filter(function(l) { return l.length > 0 })
      }
    }
  }
  Component.onCompleted: reload()
  function pickWallpaper(path) {
    page.tabletWallpaper = path
    Quickshell.execDetached(["bash", "-c",
      "mkdir -p ~/.local/state/tablet-mode && printf '%s\\n' \"$1\" > ~/.local/state/tablet-mode/background-tablet && " +
      "[[ $(cat ~/.local/state/tablet-mode/state 2>/dev/null) == on ]] && omarchy theme bg set \"$1\" >/dev/null 2>&1; true",
      "_", path])
  }

  property string addQuery: ""
  readonly property var addCandidates: {
    var q = page.addQuery.trim().toLowerCase()
    var out = []
    var have = {}
    for (var i = 0; i < page.tiles.length; i++) have[page.tiles[i].id] = true
    for (var s in page.specials) if (!have[s] && (q === "" || page.specials[s][0].toLowerCase().indexOf(q) !== -1)) out.push({ id: s, name: page.specials[s][0] })
    if (q.length < 2) return out
    var apps = DesktopEntries.applications.values || []
    for (var j = 0; j < apps.length && out.length < 10; j++) {
      var a = apps[j]
      if (!a || a.noDisplay || have[a.id]) continue
      if ((String(a.name) + " " + a.id + " " + (a.genericName || "")).toLowerCase().indexOf(q) === -1) continue
      out.push({ id: String(a.id), name: String(a.name) })
    }
    return out
  }

  component Heading: Text {
    x: Style.space(10)
    topPadding: Style.space(12)
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
    property bool selected: false
    property bool danger: false
    signal clicked()
    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(26)
    radius: Style.space(7)
    color: selected ? Util.alpha(page.accent, 0.3) : btnArea.containsMouse ? Util.alpha(danger ? Commons.Color.urgent : page.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: btn.selected ? page.accent : btnArea.containsMouse && btn.danger ? Commons.Color.urgent : page.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }

  // ---- Greeter tiles ----
  Item {
    width: page.width
    height: Style.space(40)
    Heading { anchors.verticalCenter: parent.verticalCenter; topPadding: 0; text: "Greeter tiles" }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      SmallButton { label: "Default tiles"; onClicked: page.host.set("tabletTiles", null) }
      SmallButton {
        label: "Preview greeter"
        selected: true
        // Settings steps aside while the preview shows; closing the
        // greeter brings it back.
        onClicked: {
          page.host.dismiss()
          Quickshell.execDetached(["omarchy-shell", "shell", "summon", "daa.tablet-greeter", JSON.stringify({ preview: true })])
        }
      }
    }
  }
  Hint { text: "Shown when the screen folds back into tablet mode, filled in order: small is one square, wide two, large a 2 × 2 block. Apps that aren't installed are skipped." }

  Repeater {
    model: page.tiles
    Rectangle {
      id: tileRow
      required property var modelData
      required property int index
      width: page.width
      height: Style.space(40)
      radius: Style.space(8)
      color: rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
      MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

      Rectangle {
        id: swatch
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(28)
        height: width
        color: page.tabletAccent
        Image {
          anchors.centerIn: parent
          width: parent.width * 0.7
          height: width
          visible: source !== ""
          source: page.tileIcon(tileRow.modelData.id)
          sourceSize.width: width * 2
          sourceSize.height: height * 2
        }
        Text {
          anchors.centerIn: parent
          visible: !!page.specials[tileRow.modelData.id]
          text: page.specials[tileRow.modelData.id] ? page.specials[tileRow.modelData.id][1] : ""
          color: "white"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
      Text {
        anchors.left: swatch.right
        anchors.leftMargin: Style.space(12)
        anchors.right: tileButtons.left
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: page.tileName(tileRow.modelData.id)
        color: page.fg
        font.family: page.font
        font.pixelSize: Style.font.body
      }
      Row {
        id: tileButtons
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        Repeater {
          model: [["s", "Small"], ["w", "Wide"], ["l", "Large"]]
          SmallButton {
            required property var modelData
            label: modelData[1]
            selected: tileRow.modelData.size === modelData[0]
            onClicked: page.sizeTile(tileRow.index, modelData[0])
          }
        }
        Item { width: Style.space(6); height: 1 }
        SmallButton { label: "󰁝"; onClicked: page.moveTile(tileRow.index, -1) }
        SmallButton { label: "󰁅"; onClicked: page.moveTile(tileRow.index, 1) }
        SmallButton { label: "󰅖"; danger: true; onClicked: page.removeTile(tileRow.index) }
      }
    }
  }

  // Add a tile: an app (search) or a live tile.
  Rectangle {
    width: page.width
    height: Style.space(32)
    radius: Style.space(8)
    color: Qt.rgba(1, 1, 1, 0.06)
    TextInput {
      id: addInput
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      text: page.addQuery
      color: page.fg
      font.family: page.font
      font.pixelSize: Style.font.bodySmall
      onTextEdited: page.addQuery = text
      Keys.onEscapePressed: { if (page.addQuery !== "") page.addQuery = ""; else page.host.dismiss() }
      Text { visible: addInput.text === ""; text: "Add a tile: search apps, e.g. mpv, Papers, Pinta…"; color: page.fg; opacity: 0.4; font: addInput.font }
    }
  }
  Flow {
    x: Style.space(10)
    width: page.width - Style.space(20)
    spacing: Style.space(5)
    Repeater {
      model: page.addCandidates
      SmallButton {
        required property var modelData
        label: "+ " + modelData.name
        onClicked: page.addTile(modelData.id)
      }
    }
  }

  // ---- Tablet colour ----
  Heading { text: "Tablet colour" }
  Hint { text: "Tablet mode's own accent: the tiles, menu highlights, the touch bar. The laptop keeps its colour." }
  Flow {
    x: Style.space(10)
    width: page.width - Style.space(20)
    spacing: Style.space(6)
    Repeater {
      model: [page.defaultAccent].concat(page.host ? page.host.swatches : [])
      Rectangle {
        required property var modelData
        required property int index
        width: Style.space(30)
        height: width
        radius: width / 2
        color: modelData
        border.width: Qt.colorEqual(page.tabletAccent, modelData) ? Style.space(3) : 0
        border.color: page.fg
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: page.host.set("tabletAccent", index === 0 ? null : modelData)
        }
      }
    }
  }

  // ---- Tablet wallpaper ----
  Heading { text: "Tablet wallpaper" }
  Hint { text: "Each mode keeps its own wallpaper; this one shows whenever tablet mode is on. (Changing the wallpaper while in tablet mode also sets it.)" }
  Flow {
    x: Style.space(10)
    width: page.width - Style.space(20)
    spacing: Style.space(6)
    Repeater {
      model: page.wallpapers
      Rectangle {
        required property var modelData
        width: Style.space(112)
        height: Style.space(70)
        radius: Style.space(6)
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: page.tabletWallpaper === modelData ? Style.space(3) : 0
        border.color: page.accent
        clip: true
        Image {
          anchors.fill: parent
          anchors.margins: parent.border.width
          source: "file://" + parent.modelData
          sourceSize.width: 224
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.pickWallpaper(parent.modelData) }
      }
    }
  }
  Item { width: 1; height: Style.space(6) }
}
