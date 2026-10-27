import Quickshell
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings hub front page: one search across every setting, page, device app
// and keyboard shortcut; below it (when not searching) the categories as
// tiles, the device-settings apps and a few quick actions.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily

  spacing: Style.space(10)

  property string query: ""
  property int selected: 0

  // Things that live on the loader pages (not in the sections list), so the
  // search can find them too.
  readonly property var extras: [
    ["look", "Icon theme", "Follow the Omarchy theme or pick one"],
    ["look", "Cursor theme and size", ""],
    ["look", "Accent colors", "Override the theme's accent and second accent"],
    ["bar", "Bar islands", "Logo card, app name, now playing"],
    ["bar", "Hide or reorder bar widgets", ""],
    ["bar", "Clock format", "12 / 24 hour, date, seconds"],
    ["bar", "Info bar items", "Calendar event, weather, battery, network, bluetooth, quote"],
    ["bar", "Quotes", "Edit the info bar's quotes"],
    ["favorites", "Favorites", "Top row of the logo card"],
    ["favorites", "Icon color", "Original, white or accent"],
    ["rules", "Window opacity per app", ""],
    ["rules", "Always on top", "Pin a window to every workspace"],
    ["rules", "Open an app on a workspace", ""],
    ["rules", "Float an app at a size", ""],
    ["scratchpads", "Build a dropdown", "Turn any app into a SUPER-key dropdown"],
    ["keys", "Rebind a key", ""],
    ["startup", "Login apps", "Apps that start when you log in"],
    ["startup", "Preload dropdowns", ""],
    ["startup", "System autostart entries", ""],
    ["login", "Login screen theme", "SDDM"],
    ["login", "Login background", ""],
    ["login", "Your picture", "Avatar on the login screen"],
    ["backups", "Save a checkpoint", ""],
    ["backups", "Restore a checkpoint", ""],
    ["lab", "Lab address", "Tailscale IP, VNC port, ssh user"],
    ["lab", "Server card services", ""],
    ["lab", "Lab API", ""],
    ["devices", "Add a settings app", "Incorporate any app into Device settings"]
  ]

  function navOf(p) {
    var nav = page.host ? page.host.nav : []
    for (var i = 0; i < nav.length; i++) if (nav[i].page === p) return nav[i]
    return { icon: "", label: p }
  }
  function catName(c) {
    var cats = page.host ? page.host.deviceCats : []
    for (var i = 0; i < cats.length; i++) if (cats[i][0] === c) return cats[i][1]
    return c
  }

  // [{kind, title, sub, glyph, icon, run()}], best first.
  readonly property var results: {
    var q = page.query.trim().toLowerCase()
    if (!page.host || q.length === 0) return []
    var words = q.split(/\s+/)
    var out = []
    function consider(item, hay) {
      hay = hay.toLowerCase()
      for (var w = 0; w < words.length; w++) if (hay.indexOf(words[w]) === -1) return
      var t = item.title.toLowerCase()
      item.score = (t.indexOf(q) === 0 ? 0 : t.indexOf(q) !== -1 ? 1 : 2) + (item.kind === "page" ? -0.5 : 0)
      out.push(item)
    }
    var nav = page.host.nav
    for (var i = 0; i < nav.length; i++) {
      if (!nav[i].page || nav[i].page === "home") continue
      consider({ kind: "page", title: nav[i].label, sub: "Page", glyph: nav[i].icon, page: nav[i].page },
        nav[i].label + " " + (nav[i].keywords || ""))
    }
    var secs = page.host.sections
    for (var s = 0; s < secs.length; s++) {
      for (var r = 0; r < secs[s].rows.length; r++) {
        var row = secs[s].rows[r]
        consider({ kind: "setting", title: row.label, sub: page.navOf(secs[s].page).label + " › " + secs[s].title + (row.hint ? "  ·  " + row.hint : ""),
                   glyph: page.navOf(secs[s].page).icon, page: secs[s].page, key: row.key },
          row.label + " " + secs[s].title + " " + (row.hint || "") + " " + page.navOf(secs[s].page).label)
      }
    }
    for (var e = 0; e < page.extras.length; e++) {
      var x = page.extras[e]
      consider({ kind: "setting", title: x[1], sub: page.navOf(x[0]).label + (x[2] ? "  ·  " + x[2] : ""), glyph: page.navOf(x[0]).icon, page: x[0] },
        x[1] + " " + x[2] + " " + page.navOf(x[0]).label)
    }
    var dev = page.host.deviceItems
    for (var d = 0; d < dev.length; d++) {
      consider({ kind: "app", title: dev[d].name, sub: "Device settings › " + page.catName(dev[d].cat), glyph: dev[d].glyph, icon: dev[d].icon, device: dev[d] },
        dev[d].name + " " + page.catName(dev[d].cat) + " " + dev[d].id)
    }
    out.sort(function(a, b) { return a.score - b.score })
    out = out.slice(0, 12)
    if (q.length >= 2) out.push({ kind: "keys", title: "Find “" + page.query.trim() + "” in keyboard shortcuts", sub: "Keyboard shortcuts", glyph: "󰌌", page: "keys" })
    return out
  }
  onResultsChanged: page.selected = 0

  function activate(item) {
    if (!item || !page.host) return
    if (item.kind === "app") page.host.launchDevice(item.device)
    else if (item.kind === "keys") page.host.go("keys", "", page.query.trim())
    else page.host.go(item.page, item.key || "")
    if (item.kind !== "app") page.query = ""
  }

  // Focus the search whenever Home shows.
  readonly property bool shown: !!page.host && page.host.opened && page.host.page === "home"
  onShownChanged: if (shown) Qt.callLater(function() { search.forceActiveFocus() })

  // ======================= UI =======================

  component Heading: Text {
    color: page.fg
    opacity: 0.5
    font.family: page.font
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }

  // Search
  Rectangle {
    width: page.width
    height: Style.space(48)
    radius: Style.space(12)
    color: Qt.rgba(1, 1, 1, 0.06)
    border.width: search.activeFocus ? 1 : 0
    border.color: Util.alpha(page.accent, 0.6)
    Text {
      x: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      text: "󰍉"
      color: page.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }
    TextInput {
      id: search
      anchors.left: parent.left
      anchors.leftMargin: Style.space(48)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      color: page.fg
      font.family: page.font
      font.pixelSize: Style.font.body
      clip: true
      text: page.query
      onTextEdited: page.query = text
      Keys.onDownPressed: page.selected = Math.min(page.selected + 1, page.results.length - 1)
      Keys.onUpPressed: page.selected = Math.max(page.selected - 1, 0)
      Keys.onReturnPressed: page.activate(page.results[page.selected])
      Keys.onEnterPressed: page.activate(page.results[page.selected])
      Keys.onEscapePressed: { if (page.query !== "") page.query = ""; else if (page.host) page.host.dismiss() }
      Text { visible: search.text === ""; text: "Search settings, device apps and shortcuts…"; color: page.fg; opacity: 0.4; font: search.font }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: search.forceActiveFocus() }
  }

  // ---- Results ----
  Column {
    visible: page.query.trim() !== ""
    width: page.width
    spacing: Style.space(2)
    Repeater {
      model: page.results
      Rectangle {
        id: res
        required property var modelData
        required property int index
        width: page.width
        height: Style.space(46)
        radius: Style.space(8)
        color: page.selected === index ? Util.alpha(page.accent, 0.16) : resArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
        Item {
          id: resIcon
          x: Style.space(12)
          width: Style.space(24)
          height: width
          anchors.verticalCenter: parent.verticalCenter
          Image {
            anchors.fill: parent
            visible: !!res.modelData.icon
            source: res.modelData.icon || ""
            sourceSize.width: width * 2
            sourceSize.height: height * 2
          }
          Text {
            anchors.centerIn: parent
            visible: !res.modelData.icon
            text: res.modelData.glyph || ""
            color: page.selected === res.index ? page.accent : page.fg
            font.family: res.modelData.glyph === "\ue900" ? "omarchy" : Style.font.family
            font.pixelSize: Style.font.body
          }
        }
        Column {
          anchors.left: resIcon.right
          anchors.leftMargin: Style.space(12)
          anchors.right: kindLabel.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          Text { width: parent.width; elide: Text.ElideRight; text: res.modelData.title; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
          Text { width: parent.width; elide: Text.ElideRight; text: res.modelData.sub; color: page.fg; opacity: 0.5; font.family: page.font; font.pixelSize: Style.font.caption }
        }
        Text {
          id: kindLabel
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: res.modelData.kind === "app" ? "open" : res.modelData.kind === "page" ? "page" : res.modelData.kind === "keys" ? "search" : "setting"
          color: page.fg
          opacity: 0.4
          font.family: page.font
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          id: resArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: page.selected = res.index
          onClicked: page.activate(res.modelData)
        }
      }
    }
    Text {
      visible: page.results.length === 0
      text: "Nothing matches."
      color: page.fg
      opacity: 0.5
      font.family: page.font
      font.pixelSize: Style.font.bodySmall
    }
  }

  // ---- Categories ----
  Heading { visible: page.query.trim() === ""; text: "CATEGORIES" }
  Grid {
    id: tiles
    visible: page.query.trim() === ""
    columns: 2
    spacing: Style.space(10)
    width: page.width
    readonly property var groups: {
      var nav = page.host ? page.host.nav : []
      var out = [], cur = null
      var icons = { "Look and feel": "󰏘", "Desktop": "󰖯", "System": "󰒓", "Network": "󰛳" }
      for (var i = 0; i < nav.length; i++) {
        if (nav[i].group) { cur = { name: nav[i].group, icon: icons[nav[i].group] || "", pages: [] }; out.push(cur) }
        else if (cur) cur.pages.push(nav[i])
      }
      return out
    }
    Repeater {
      model: tiles.groups
      Rectangle {
        id: tile
        required property var modelData
        width: (tiles.width - tiles.spacing) / 2
        height: tileCol.implicitHeight + Style.space(24)
        radius: Style.space(12)
        color: Qt.rgba(1, 1, 1, 0.04)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)
        Column {
          id: tileCol
          x: Style.space(14)
          y: Style.space(12)
          width: parent.width - Style.space(28)
          spacing: Style.space(4)
          Row {
            spacing: Style.space(8)
            bottomPadding: Style.space(4)
            Text { text: tile.modelData.icon; color: page.accent; font.family: tile.modelData.icon === "\ue900" ? "omarchy" : Style.font.family; font.pixelSize: Style.font.title }
            Text { text: tile.modelData.name; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
          }
          Repeater {
            model: tile.modelData.pages
            Text {
              id: link
              required property var modelData
              text: modelData.label
              color: linkArea.containsMouse ? page.accent : page.fg
              opacity: linkArea.containsMouse ? 1 : 0.75
              font.family: page.font
              font.pixelSize: Style.font.bodySmall
              MouseArea { id: linkArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.host.go(link.modelData.page) }
            }
          }
        }
      }
    }
  }

  // ---- Device settings apps ----
  Item {
    visible: page.query.trim() === ""
    width: page.width
    height: Style.space(22)
    Heading { anchors.bottom: parent.bottom; text: "DEVICE SETTINGS" }
    Text {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      text: "Manage apps ›"
      color: manageArea.containsMouse ? page.accent : page.fg
      opacity: 0.7
      font.family: page.font
      font.pixelSize: Style.font.caption
      MouseArea { id: manageArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.host.go("devices") }
    }
  }
  Flow {
    visible: page.query.trim() === ""
    width: page.width
    spacing: Style.space(8)
    Repeater {
      model: page.host ? page.host.deviceItems : []
      Rectangle {
        id: dev
        required property var modelData
        width: Style.space(104)
        height: Style.space(84)
        radius: Style.space(10)
        color: devArea.containsMouse ? Util.alpha(page.accent, 0.14) : Qt.rgba(1, 1, 1, 0.04)
        Item {
          id: devIcon
          anchors.horizontalCenter: parent.horizontalCenter
          y: Style.space(12)
          width: Style.space(30)
          height: width
          Image { anchors.fill: parent; visible: !!dev.modelData.icon; source: dev.modelData.icon || ""; sourceSize.width: width * 2; sourceSize.height: height * 2 }
          Text {
            anchors.centerIn: parent
            visible: !dev.modelData.icon
            text: dev.modelData.glyph
            color: devArea.containsMouse ? page.accent : page.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }
        }
        Text {
          anchors.top: devIcon.bottom
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width - Style.space(10)
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          maximumLineCount: 2
          wrapMode: Text.Wrap
          text: dev.modelData.name
          color: page.fg
          font.family: page.font
          font.pixelSize: Style.font.caption
        }
        MouseArea { id: devArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.host.launchDevice(dev.modelData) }
      }
    }
  }

  // ---- Quick actions ----
  Heading { visible: page.query.trim() === ""; text: "QUICK ACTIONS" }
  Flow {
    visible: page.query.trim() === ""
    width: page.width
    spacing: Style.space(8)
    Repeater {
      model: [
        ["󰁯", "Save a checkpoint", "checkpoint save quick"],
        ["󰈙", "Desktop map", "config-map && uwsm-app -- xdg-open ~/Documents/desktop-map.md"],
        ["󰛨", "Ideas list", "uwsm-app -- xdg-open ~/Documents/desktop-ideas.md"],
        ["󰽥", "Focus mode", "~/.local/bin/focus-mode"]
      ]
      Rectangle {
        id: qa
        required property var modelData
        width: qaRow.implicitWidth + Style.space(24)
        height: Style.space(34)
        radius: height / 2
        color: qaArea.containsMouse ? Util.alpha(page.accent, 0.18) : Qt.rgba(1, 1, 1, 0.06)
        Row {
          id: qaRow
          anchors.centerIn: parent
          spacing: Style.space(8)
          Text { text: qa.modelData[0]; color: page.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
          Text { text: qa.modelData[1]; color: page.fg; font.family: page.font; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
          id: qaArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            page.host.dismiss()
            Quickshell.execDetached(["bash", "-lc", qa.modelData[2]])
          }
        }
      }
    }
  }
  Item { width: 1; height: Style.space(6) }
}
