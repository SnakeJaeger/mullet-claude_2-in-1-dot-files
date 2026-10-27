import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// App launcher laid out as a 7 x 6 grid (scrolls past 42 apps). Type to
// search, arrows to move, Enter or click to launch, Escape to clear/close.
// Built from omarchy.emojis' grid picker. Apps come from the shell's shared
// app library when the host provides it (hidden entries, icons and launch
// feedback then match the menu), otherwise straight from DesktopEntries.
Item {
  id: root

  // The theme's extra colours (green, magenta, yellow, orange, cyan, blue)
  // for multi-coloured effects, re-read when the theme changes.
  property var themePalette: ["#9ece6a", "#bb9af7", "#e0af68", "#ff9e64", "#73daca", "#7aa2f7"]
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var t = String(text())
      var out = []
      var keys = ["green", "magenta", "yellow", "orange", "cyan", "blue"]
      for (var i = 0; i < keys.length; i++) {
        var m = t.match(new RegExp("^\\s*" + keys[i] + "\\s*=\\s*[\"']?(#[0-9a-fA-F]{6})", "m"))
        if (m) out.push(m[1])
      }
      if (out.length) root.themePalette = out
    }
  }

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

  property var shell: null
  property var manifest: null
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // Desktop ids hidden the same way the app library hides them: Omarchy's
  // launcher.hides list plus entries hidden for this desktop session.
  property var configuredHidden: ({})
  property var sessionHidden: ({})
  onConfiguredHiddenChanged: if (opened) rebuildDisplay()
  onSessionHiddenChanged: if (opened) rebuildDisplay()

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  // Category tabs beside the search. Click (or Ctrl+Tab) to narrow the grid;
  // the active tab clicked again shows everything. Each app lands in one tab:
  // a hand-placed id first, then the first tab (in categoryOrder) sharing one
  // of its desktop categories, else Utility.
  property string category: ""
  readonly property var categoryTabs: [
    { id: "web", label: "Web" },
    { id: "utility", label: "Utility" },
    { id: "create", label: "Create" },
    { id: "communicate", label: "Communicate" },
    { id: "entertain", label: "Entertain" }
  ]
  readonly property var categoryOrder: ["communicate", "entertain", "create", "web"]
  readonly property var categoryMap: ({
    communicate: ["Chat", "InstantMessaging", "Email", "Telephony", "VideoConference", "IRCClient", "ContactManagement"],
    entertain: ["Game", "Player", "Music", "TV", "Amusement", "Emulator"],
    create: ["Graphics", "AudioVideoEditing", "Recorder", "Office", "Development", "TextEditor", "IDE"],
    web: ["WebBrowser", "Network", "RemoteAccess"]
  })
  readonly property var categoryOverrides: ({
    "Zoom": "communicate",
    "Basecamp": "communicate",
    "Kindle": "entertain",
    "info.febvre.Komikku": "entertain",
    "com.github.johnfactotum.Foliate": "entertain",
    "gns3": "utility",
    "org.wireshark.Wireshark": "utility",
    "localsend": "utility",
    "mullvad-vpn": "utility"
  })

  function categoryOf(entry) {
    var id = String(entry.id || "")
    if (root.categoryOverrides[id]) return root.categoryOverrides[id]
    var cats = entry.categories || []
    for (var i = 0; i < root.categoryOrder.length; i++) {
      var wanted = root.categoryMap[root.categoryOrder[i]]
      for (var j = 0; j < cats.length; j++)
        if (wanted.indexOf(String(cats[j])) !== -1) return root.categoryOrder[i]
    }
    return "utility"
  }

  function setCategory(next) {
    root.category = root.category === next ? "" : next
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  // Ctrl+Tab steps through All -> Web -> ... -> Entertain -> All.
  function cycleCategory(delta) {
    var ids = [""]
    for (var i = 0; i < root.categoryTabs.length; i++) ids.push(root.categoryTabs[i].id)
    var at = ids.indexOf(root.category)
    root.category = ids[(at + delta + ids.length) % ids.length]
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  // 5 columns x 6 rows, sized so the window is square like the logo frame.
  readonly property int columns: 5
  readonly property int rows: 6

  // Shares the [menu] surface tokens, like the emoji picker.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  // Two header rows in the square window: search, then the category tabs.
  readonly property int headerRowHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int headerHeight: headerRowHeight * 2 + Style.space(6)
  property int contentSpacing: Style.spacing.md

  property int iconSize: Style.space(48)
  // Square card: the columns together as wide as the header plus the rows are tall.
  property int cellWidth: Math.round((headerHeight + contentSpacing + rows * cellHeight) / columns)
  property int cellHeight: iconSize + Style.font.body * 2 + Style.space(22)

  // Easter egg (SUPER + ALT + R, payload {"mullet":true}): Mullet Claude
  // watches over the apps from behind the grid.
  property bool mullet: false

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.mullet = payload.mullet === true
    root.opened = true
    root.filterText = ""
    root.category = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (root.appLibrary) root.appLibrary.refreshIcons()
    else if (!sessionHiddenScan.running) sessionHiddenScan.running = true
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "daa.launcher")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Fallback app list when no app library is injected: visible desktop
  // entries, prefix matches first, then substring matches, each by name.
  function desktopEntryRows(query) {
    var q = String(query || "").trim().toLowerCase()
    var values = DesktopEntries.applications.values || []
    var rows = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay || !entry.name) continue
      var id = String(entry.id || "")
      if (root.configuredHidden[id] || root.sessionHidden[id]) continue
      var name = String(entry.name)
      var lower = name.toLowerCase()
      var rank = 0
      if (q) {
        var generic = String(entry.genericName || "").toLowerCase()
        if (lower.indexOf(q) === 0) rank = 0
        else if (lower.indexOf(q) !== -1) rank = 1
        else if (generic.indexOf(q) !== -1) rank = 2
        else continue
      }
      rows.push({ id: id, name: name, icon: String(entry.icon || ""), rank: rank, key: lower, entry: entry })
    }
    rows.sort(function(a, b) {
      if (a.rank !== b.rank) return a.rank - b.rank
      return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0)
    })
    return rows
  }

  function iconSource(icon) {
    if (root.appLibrary) return root.appLibrary.iconSource(icon)
    var value = String(icon || "")
    if (value.charAt(0) === "/") return "file://" + value
    var themed = value ? Quickshell.iconPath(value, true) : ""
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  function rebuildDisplay() {
    displayModel.clear()
    if (root.appLibrary) {
      var rows = root.appLibrary.sortedEntries(root.filterText)
      for (var i = 0; i < rows.length; i++) {
        var entry = rows[i].entry
        var appId = String(entry.id || "")
        if (!appId) continue
        if (root.category && root.categoryOf(entry) !== root.category) continue
        displayModel.append({ appId: appId, label: root.appLibrary.entryName(entry), appIcon: String(entry.icon || "") })
      }
    } else {
      var fallback = root.desktopEntryRows(root.filterText)
      for (var j = 0; j < fallback.length; j++) {
        if (!fallback[j].id) continue
        if (root.category && root.categoryOf(fallback[j].entry) !== root.category) continue
        displayModel.append({ appId: fallback[j].id, label: fallback[j].name, appIcon: fallback[j].icon })
      }
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    cursorActive = displayModel.count > 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectRow(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      return
    }
    var newIndex = selectedIndex + delta * columns
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectPage(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      return
    }
    var newIndex = selectedIndex + delta * columns * rows
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.dismiss()
    if (root.appLibrary) root.appLibrary.launch(row.appId, row.label)
    // Same launch path as the app library: a scope outside the compositor's
    // service, with gtk-launch resolving the desktop id.
    else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", row.appId + ".desktop"])
  }

  function idSet(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim()
      if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
      if (id.length > 0) next[id] = true
    }
    return next
  }

  ListModel { id: displayModel }

  // Tablet mode (~/.local/bin/tablet-mode) adds a touch scroll rail beside
  // the grid.
  property bool tabletOn: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/tablet-mode/state"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.tabletOn = String(text() || "").trim() === "on"
  }
  // The rail goes on the bar's side when the bar is vertical (where the thumb
  // is), otherwise on the right. Read from shell.json like the menu does.
  property bool railLeft: false
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.railLeft = (JSON.parse(text() || "{}").bar || {}).position === "left" } catch (e) {}
    }
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.configuredHidden = root.idSet(text())
    onFileChanged: reload()
  }

  Process {
    id: sessionHiddenScan
    property string output: ""
    running: true
    command: ["bash", "-c", Util.shellQuote(root.omarchyPath + "/shell/services/hidden-entries.sh") + " "
      + Util.shellQuote([Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")]
        .filter(function(v) { return String(v || "").length > 0 }).join(":"))]
    stdout: SplitParser { onRead: function(line) { sessionHiddenScan.output += line + "\n" } }
    onStarted: output = ""
    onExited: root.sessionHidden = root.idSet(output)
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.opened) root.rebuildDisplay() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Pop the card in from its centre: 90% -> 105% -> 100%.
    onVisibleChanged: if (visible) cardPop.restart()

    SequentialAnimation {
      id: cardPop
      NumberAnimation { target: card; property: "scale"; from: 0.9; to: 1.05; duration: 130; easing.type: Easing.OutQuad }
      NumberAnimation { target: card; property: "scale"; to: 1.0; duration: 150; easing.type: Easing.InOutQuad }
    }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      // Size from the surface's real insets (padding plus border) so all six
      // rows fit without clipping.
      width: Math.min(root.cellWidth * root.columns + contentLeftInset + contentRightInset, panel.width - Style.gapsOut * 2)
      height: Math.min(root.headerHeight + root.contentSpacing + root.cellHeight * root.rows + contentTopInset + contentBottomInset,
        panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      // The plain border is replaced by the Omarchy square logo (below).
      borderSpec: Border.none()
      // Extra room inside the logo frame.
      padding: root.contentMargin + Style.space(16)

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Clipped just inside the logo frame, so the sketch never spills past it.
      Item {
        id: mulletClip
        visible: root.mullet
        anchors.fill: parent
        anchors.margins: Style.space(30)
        clip: true

        Image {
          id: mulletPic
          anchors.centerIn: parent
          // Up and toward the left, so Mullet Claude sits behind the first columns.
          anchors.horizontalCenterOffset: -parent.width * 0.12
          anchors.verticalCenterOffset: -parent.height * 0.1
          width: parent.width * 1.1
          height: parent.height * 1.1
          source: Qt.resolvedUrl("mullet.png")
          // The sketch from the social preview, zoomed in on Mullet Claude with
          // the paper made transparent: just the pencil strokes.
          sourceSize.width: 800
          fillMode: Image.PreserveAspectCrop
          smooth: true
          opacity: 0
          // Fades up behind the apps, then breathes slowly.
          SequentialAnimation {
            running: root.opened && root.mullet
            NumberAnimation { target: mulletPic; property: "opacity"; from: 0; to: 0.55; duration: 600; easing.type: Easing.OutCubic }
            SequentialAnimation {
              loops: Animation.Infinite
              NumberAnimation { target: mulletPic; property: "scale"; from: 1; to: 1.03; duration: 2400; easing.type: Easing.InOutSine }
              NumberAnimation { target: mulletPic; property: "scale"; from: 1.03; to: 1; duration: 2400; easing.type: Easing.InOutSine }
            }
          }
        }
      }

      // A soft Tokyo Night blue haze in the middle, fading out well before the
      // frame, so the window looks lit from within behind the apps.
      Canvas {
        id: centreTint
        anchors.fill: parent
        readonly property color tint: "#7aa2f7"
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2, cy = height * 0.55, r = Math.min(width, height) * 0.48
          var grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
          grad.addColorStop(0, Qt.rgba(tint.r, tint.g, tint.b, 0.13))
          grad.addColorStop(0.55, Qt.rgba(tint.r, tint.g, tint.b, 0.06))
          grad.addColorStop(1, Qt.rgba(tint.r, tint.g, tint.b, 0))
          ctx.fillStyle = grad
          ctx.fillRect(0, 0, width, height)
        }
      }

      // Window frame drawn as the Omarchy square logo (13x13 cells):
      //   #############   outer line
      //   #.....#.....#   joint (top)
      //   #.#####..##.#   inner line, with its gap
      //   #.#.......#.#
      //   ###.......#.#   joint (left)
      //   #.#.......#.#
      //   #.#########.#   inner line
      //   #.....#.....#   joint (bottom)
      //   #######.#####   outer line, with its notch
      // Lines are thin; the gap between outer and inner is fixed; breaks and
      // joints sit at the same proportional spot along each edge as in the logo
      // (the 7 interior cells share the length evenly).
      Canvas {
        id: logoFrame
        anchors.fill: parent
        anchors.margins: Style.space(4)
        opacity: 0.6
        // Thicker lines grow away from the gap (it stays `gap` wide).
        readonly property real line: Style.spaceReal(6.75)
        readonly property real gap: Style.space(10)   // between outer and inner lines
        readonly property color ink: root.border
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        // Edge of cell i (0..13) along a side of length total.
        function b(i, total) {
          var band = 2 * line + gap
          if (i <= 0) return 0
          if (i === 1) return line
          if (i === 2) return line + gap
          if (i <= 10) return band + (i - 3) * (total - 2 * band) / 7
          if (i === 11) return total - line - gap
          if (i === 12) return total - line
          return total
        }
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.fillStyle = ink
          var W = width, H = height, c = line, g = gap
          function rect(x0, y0, x1, y1) { ctx.fillRect(Math.round(x0), Math.round(y0), Math.round(x1) - Math.round(x0), Math.round(y1) - Math.round(y0)) }
          var x7 = b(7, W), x8 = b(8, W), x9 = b(9, W)
          // Outer line: full top and sides, notch in the bottom (cell 7).
          rect(0, 0, W, c)
          rect(0, 0, c, H)
          rect(W - c, 0, W, H)
          rect(0, H - c, x7, H)
          rect(x8, H - c, W, H)
          // Inner line: gap in the top (cells 7-8), full sides and bottom.
          rect(c + g, c + g, x7, 2 * c + g)
          rect(x9, c + g, W - c - g, 2 * c + g)
          rect(c + g, c + g, 2 * c + g, H - c - g)
          rect(W - 2 * c - g, c + g, W - c - g, H - c - g)
          rect(c + g, H - 2 * c - g, W - c - g, H - c - g)
          // Joints across the gap: top and bottom flush with cell 6's end,
          // left centred on cell 6.
          rect(x7 - c, c, x7, c + g)
          rect(x7 - c, H - c - g, x7, H - c)
          var y6 = (b(6, H) + b(7, H)) / 2
          rect(c, y6 - c / 2, c + g, y6 + c / 2)
        }
      }

      // Light trails running along the logo frame from its 7 entrances: both
      // sides of the inner line's top gap, both sides of the outer line's
      // bottom notch, and the 3 joints. Each leads with a white head, turns
      // cyan or coral, and fades behind; it runs part-way round, fades out,
      // and starts again from its entrance. Staggered so they never sync.
      Canvas {
        id: logoComets
        anchors.fill: logoFrame
        property real t: 0
        readonly property color cyan: Commons.Color.pick("tablet.accent", Commons.Color.accent)
        readonly property color coral: Commons.Color.urgent
        // One trail at a time wears a special colour, starting with lime;
        // when it finishes the next trail to fire takes the next one.
        readonly property var specials: root.themePalette
        property var special: null      // { n, run, color }
        property int specialNext: 0
        // Settings: "launcherTrails" on/off, "launcherTrailSpeed" multiplier.
        visible: root.uiOpt("launcherTrails", true)
        FrameAnimation {
          running: root.opened && logoComets.visible
          onTriggered: { logoComets.t += frameTime * root.uiOpt("launcherTrailSpeed", 1); logoComets.requestPaint() }
        }

        // The outer or inner ring as a rectangle on the lines' centres.
        function ring(inner) {
          var c = logoFrame.line, g = logoFrame.gap
          var o = inner ? c + g + c / 2 : c / 2
          var r = { x0: o, y0: o, x1: width - o, y1: height - o }
          r.w = r.x1 - r.x0; r.h = r.y1 - r.y0; r.p = 2 * (r.w + r.h)
          return r
        }
        // Point at distance s clockwise from the ring's top-left corner.
        function at(r, s) {
          s = ((s % r.p) + r.p) % r.p
          if (s < r.w) return { x: r.x0 + s, y: r.y0 }
          s -= r.w
          if (s < r.h) return { x: r.x1, y: r.y0 + s }
          s -= r.h
          if (s < r.w) return { x: r.x1 - s, y: r.y1 }
          s -= r.w
          return { x: r.x0, y: r.y1 - s }
        }
        // Where a run must stop: the open stretch it would otherwise cross
        // (inner ring: the top gap; outer ring: the bottom notch), as a
        // clockwise interval [g0, g1]. Returns the distance to it along dir.
        function toGap(e) {
          var P = e.r.p
          var d = e.dir > 0 ? e.r.g0 - e.s : e.s - e.r.g1
          return ((d % P) + P) % P
        }
        // The seven entrances: ring, start (distance clockwise), direction.
        function entrances() {
          var W = width, H = height, c = logoFrame.line
          var x7 = logoFrame.b(7, W), x8 = logoFrame.b(8, W), x9 = logoFrame.b(9, W)
          var y6 = (logoFrame.b(6, H) + logoFrame.b(7, H)) / 2
          var ro = ring(false), ri = ring(true)
          ri.g0 = x7 - ri.x0; ri.g1 = x9 - ri.x0
          ro.g0 = ro.w + ro.h + (ro.x1 - x8); ro.g1 = ro.w + ro.h + (ro.x1 - x7)
          return [
            { r: ri, s: x7 - ri.x0, dir: -1, color: cyan },                     // inner gap, left side
            { r: ri, s: x9 - ri.x0, dir: 1, color: coral },                     // inner gap, right side
            { r: ro, s: ro.w + ro.h + (ro.x1 - x7), dir: 1, color: coral },     // outer notch, left side
            { r: ro, s: ro.w + ro.h + (ro.x1 - x8), dir: -1, color: cyan },     // outer notch, right side
            { r: ro, s: (x7 - c / 2) - ro.x0, dir: 1, color: cyan },            // top joint
            { r: ro, s: 2 * ro.w + ro.h + (ro.y1 - y6), dir: -1, color: coral }, // left joint
            { r: ri, s: ri.w + ri.h + (ri.x1 - (x7 - c / 2)), dir: -1, color: coral } // bottom joint
          ]
        }
        // Side of ring r that point q sits on: the normal pointing into the
        // gap between the lines (inward for the outer ring, outward for the
        // inner one), or null at a corner.
        function gapNormal(r, inner, q) {
          var eps = 0.5, n = null
          if (Math.abs(q.y - r.y0) < eps) n = { x: 0, y: 1 }
          else if (Math.abs(q.x - r.x1) < eps) n = { x: -1, y: 0 }
          else if (Math.abs(q.y - r.y1) < eps) n = { x: 0, y: -1 }
          else if (Math.abs(q.x - r.x0) < eps) n = { x: 1, y: 0 }
          if (n && inner) { n.x = -n.x; n.y = -n.y }
          return n
        }
        // Afterglow: light spilling from a beam segment into the gap, fading
        // across the gap. Lingers longer than the beam (see onPaint).
        function glow(ctx, r, inner, p0, p1, col, alpha) {
          var n = gapNormal(r, inner, p0)
          if (!n || !gapNormal(r, inner, p1) || alpha <= 0.004) return
          var c = logoFrame.line, g = logoFrame.gap
          var ax = p0.x + n.x * c / 2, ay = p0.y + n.y * c / 2      // line edge
          var bx = p1.x + n.x * c / 2, by = p1.y + n.y * c / 2
          var fx = n.x * g, fy = n.y * g                             // across the gap
          var grad = ctx.createLinearGradient(ax, ay, ax + fx, ay + fy)
          // Reaches further across the channel, but the quad ends exactly at
          // the opposite line, so it never spills past the lines.
          grad.addColorStop(0, Qt.rgba(col.r, col.g, col.b, alpha))
          grad.addColorStop(0.55, Qt.rgba(col.r, col.g, col.b, alpha * 0.62))
          grad.addColorStop(1, Qt.rgba(col.r, col.g, col.b, alpha * 0.3))
          ctx.fillStyle = grad
          ctx.beginPath()
          ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.lineTo(bx + fx, by + fy); ctx.lineTo(ax + fx, ay + fy)
          ctx.closePath(); ctx.fill()
        }

        function mix(a, b, k) {
          return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1)
        }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          if (width <= 0 || height <= 0) return
          var list = entrances()
          var trail = Style.space(200), steps = 36
          var white = Qt.rgba(1, 1, 1, 1)
          ctx.lineCap = "butt"
          ctx.lineWidth = logoFrame.line
          // Each runs on its own cycle: travel 2.2 s, a short rest, repeat.
          var travel = 2.2
          function runOf(n) { var cycle = 2.6 + n * 0.29; var x = t + n * 0.97; return { run: Math.floor(x / cycle), local: x % cycle } }
          // Release the special colour once its trail's run is over.
          if (special) {
            var sr = runOf(special.n)
            if (sr.run !== special.run || sr.local > travel) { special = null; specialNext = (specialNext + 1) % specials.length }
          }
          for (var n = 0; n < list.length; n++) {
            var e = list[n]
            var ro = runOf(n), local = ro.local
            if (local > travel) continue
            // A trail just setting off takes the special colour if it's free.
            if (!special && local < 0.12) special = { n: n, run: ro.run, color: specials[specialNext] }
            var color = special && special.n === n && special.run === ro.run ? Qt.color(special.color) : e.color
            var k = local / travel
            // Ease in-out, up to 42% round, stopping short of a gap/notch.
            var reach = Math.min(e.r.p * 0.42, toGap(e) - logoFrame.line * 0.5)
            var dist = (k * k * (3 - 2 * k)) * Math.max(0, reach)
            var fade = Math.min(1, local / 0.25) * Math.min(1, (travel - local) / 0.45)
            var head = e.s + e.dir * dist
            var inner = e.r === list[0].r
            // Glow only inside the channel between the lines: clip to the band
            // between the outer line's inner edge and the inner line's outer
            // edge (even-odd), so corners, the app area and outside stay dark.
            ctx.save()
            ctx.beginPath()
            var c = logoFrame.line, g = logoFrame.gap
            ctx.rect(c, c, width - 2 * c, height - 2 * c)
            ctx.rect(c + g, c + g, width - 2 * (c + g), height - 2 * (c + g))
            ctx.fillRule = Qt.OddEvenFill
            ctx.clip()
            // Afterglow first (under the beam): reaches 1.6x the trail and
            // fades slower; the first stretch behind the head blooms whitish.
            var glowLen = Math.min(trail * 1.6, dist)
            for (var j = 0; j < steps; j++) {
              var b0 = j / steps, b1 = (j + 1) / steps
              var q0 = at(e.r, head - e.dir * b0 * glowLen)
              var q1 = at(e.r, head - e.dir * b1 * glowLen)
              var gcol = j < 4 ? mix(white, color, j / 4) : color
              var ga = fade * (0.55 * Math.pow(1 - b0, 1.1) + (j < 3 ? 0.25 * (1 - j / 3) : 0))
              glow(ctx, e.r, inner, q0, q1, gcol, ga)
            }
            ctx.restore()
            for (var i = 0; i < steps; i++) {
              var a0 = i / steps, a1 = (i + 1) / steps
              var len = Math.min(trail, dist)
              var p0 = at(e.r, head - e.dir * a0 * len)
              var p1 = at(e.r, head - e.dir * a1 * len)
              // White at the head, the colour behind, fading out down the trail.
              var col = i < 2 ? mix(white, color, i / 2) : color
              var alpha = fade * Math.pow(1 - a0, 1.6)
              ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, alpha)
              ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(p1.x, p1.y); ctx.stroke()
            }
          }
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.ControlModifier)) {
            root.cycleCategory(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectRow(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectRow(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.selectPage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.selectPage(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // Search on the left, then the category tabs split by tall rules.
        Item {
          width: parent.width
          height: root.headerHeight

          Item {
            id: searchBox
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.headerRowHeight
            clip: true

            Text {
              id: searchText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              // A quarter of the way from the left edge to centred (the
              // placeholder's centred offset, quartered). Fixed, so typing just
              // grows rightwards.
              anchors.leftMargin: Style.space(10) + Math.max(0, (searchBox.width - Style.space(20) - placeholderMetrics.advanceWidth) / 8)
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText || "Search apps…"
              color: root.foreground
              opacity: root.filterText ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              // Keep the end of a long query (where you're typing) in view.
              elide: root.filterText ? Text.ElideLeft : Text.ElideRight
            }

            TextMetrics {
              id: placeholderMetrics
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              text: "Search apps…"
            }

            // Blinking text cursor: after the query, or before the placeholder.
            Rectangle {
              id: caret
              width: Math.max(2, Style.space(2))
              height: Math.round(Style.font.heading * 1.25)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              readonly property real textStart: searchText.x
              x: root.filterText
                ? textStart + Math.min(searchText.contentWidth, searchText.width) + Style.space(1)
                : textStart - width - Style.space(2)
              color: root.foreground
              visible: root.opened

              SequentialAnimation on opacity {
                id: caretBlink
                running: root.opened
                loops: Animation.Infinite
                PropertyAction { value: 1 }
                PauseAnimation { duration: 530 }
                PropertyAction { value: 0 }
                PauseAnimation { duration: 530 }
              }
            }

            // Hold the caret solid while typing, then resume blinking.
            Connections {
              target: root
              function onFilterTextChanged() { if (root.opened) caretBlink.restart() }
            }
          }

          Row {
            id: tabRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.headerRowHeight

            // Every tab is as wide as the longest label so the rules fall at
            // even intervals.
            TextMetrics {
              id: tabMetrics
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              font.capitalization: Font.AllUppercase
              text: "COMMUNICATE"
            }

            Repeater {
              model: root.categoryTabs

              delegate: Row {
                id: tab
                required property var modelData
                required property int index
                readonly property bool active: root.category === modelData.id
                height: tabRow.height

                // Rule between tabs (none before the first).
                Rectangle {
                  visible: tab.index > 0
                  width: Math.max(2, Style.space(2))
                  height: Math.round(parent.height * 0.5)
                  anchors.verticalCenter: parent.verticalCenter
                  radius: width / 2
                  // Grey: the theme's text colour faded into the card.
                  color: Util.alpha(root.foreground, 0.3)
                }

                // The five tabs share the row evenly (the rules take their bit).
                Item {
                  width: (tabRow.width - (root.categoryTabs.length - 1) * Math.max(2, Style.space(2))) / root.categoryTabs.length
                  height: parent.height

                  Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(4)
                    anchors.rightMargin: Style.space(4)
                    anchors.topMargin: Style.space(4)
                    anchors.bottomMargin: Style.space(4)
                    radius: root.cornerRadius
                    color: tab.active ? root.selectedBackground
                      : (tabMouse.containsMouse ? Util.alpha(root.selectedBackground, 0.5) : "transparent")
                  }

                  Text {
                    id: tabLabel
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: tab.modelData.label
                    color: tab.active ? root.selectedText : root.foreground
                    opacity: tab.active || tabMouse.containsMouse ? 1 : 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                  }

                  MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setCategory(tab.modelData.id)
                  }
                }
              }
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          GridView {
            id: resultGrid
            // Centre the columns in whatever width the card ends up with.
            width: root.cellWidth * root.columns
            height: parent.height
            anchors.horizontalCenter: parent.horizontalCenter
            model: displayModel
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            interactive: false                       // TouchScroll handles scrolling
            boundsBehavior: Flickable.StopAtBounds   // ends glow (TouchScroll)
            flickDeceleration: 900
            maximumFlickVelocity: 12000

            delegate: Item {
              id: cell
              required property int index
              required property string appId
              required property string label
              required property string appIcon

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: root.cellWidth
              height: root.cellHeight

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(3)
                radius: root.cornerRadius
                color: cell.hasCursor ? root.selectedBackground : "transparent"
              }

              Image {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(12)
                width: root.iconSize
                height: root.iconSize
                // Render at device pixels so icons stay sharp on HiDPI.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                source: root.iconSource(cell.appIcon)
              }

              Text {
                textFormat: Text.PlainText
                anchors.top: icon.bottom
                anchors.topMargin: Style.space(6)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                text: cell.label
                color: cell.hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = cell.index
                }
                onClicked: root.activateIndex(cell.index)
              }
            }
          }

          TouchScroll { anchors.fill: resultGrid; view: resultGrid }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              textFormat: Text.PlainText
              text: root.filterText ? "No apps match “" + root.filterText + "”" : "No apps here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }

    // Touch scroll rail (tablet mode, when the apps overflow): drag the handle
    // or tap the rail to jump.
    Rectangle {
      id: rail
      readonly property real overflow: Math.max(0, resultGrid.contentHeight - resultGrid.height)
      readonly property real inset: Style.space(4)
      readonly property real trackHeight: height - inset * 2
      readonly property real handleHeight: overflow > 0
        ? Math.max(width * 2, trackHeight * resultGrid.height / resultGrid.contentHeight) : trackHeight
      readonly property real position: overflow > 0 ? (resultGrid.contentY - resultGrid.originY) / overflow : 0

      visible: root.tabletOn && overflow > 0
      width: Style.space(22)
      height: card.height
      x: root.railLeft ? card.x - Style.space(8) - width : card.x + card.width + Style.space(8)
      y: card.y
      scale: card.scale
      radius: width / 2
      color: root.background
      border.width: 0  // borderless in tablet mode

      Rectangle {
        x: rail.inset
        y: rail.inset + (rail.trackHeight - rail.handleHeight) * Math.max(0, Math.min(1, rail.position))
        width: rail.width - rail.inset * 2
        height: rail.handleHeight
        radius: width / 2
        color: railArea.pressed ? Commons.Color.pick("tablet.accent", Commons.Color.accent) : Util.alpha(root.foreground, 0.5)
      }

      MouseArea {
        id: railArea
        anchors.fill: parent
        preventStealing: true
        property real grab: 0

        function seek(mouseY) {
          if (rail.overflow <= 0) return
          var span = rail.trackHeight - rail.handleHeight
          var p = span > 0 ? (mouseY - rail.inset - grab) / span : 0
          resultGrid.contentY = resultGrid.originY + Math.max(0, Math.min(1, p)) * rail.overflow
        }

        onPressed: function(mouse) {
          var handleTop = rail.inset + (rail.trackHeight - rail.handleHeight) * rail.position
          grab = mouse.y >= handleTop && mouse.y <= handleTop + rail.handleHeight
            ? mouse.y - handleTop : rail.handleHeight / 2
          seek(mouse.y)
        }
        onPositionChanged: function(mouse) { if (pressed) seek(mouse.y) }
      }
    }
  }
}
