import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Tablet greeter: entering tablet mode (~/.local/bin/tablet-mode on) usually
// means watching, reading or drawing, so it opens on big tiles for those.
// Windows Phone style: flat tiles in the tablet accent, small / wide / large,
// a clock and battery live tile, tiles turnstile in and out. The frame is the
// SUPER + R launcher's Omarchy-logo frame with its light trails.
// Easy to get rid of: tap outside, the x, "Not now", or Esc. Swipes are
// never needed (the screen drags), every action is a button.
// Tiles, colours and the on/off switch: Desktop settings → Tablet
// (daa-ui.json: tabletGreeter, tabletTiles, tabletTileColors, tabletTileIcons).
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // ---- Settings (daa-ui.json) and calm mode, as in daa.launcher ----
  property var ui: ({})
  function uiOpt(key, fallback) {
    if (root.calm && root.calmKeys.indexOf(key) !== -1) return false
    var v = root.ui ? root.ui[key] : undefined; return v === undefined || v === null ? fallback : v
  }
  readonly property var calmKeys: ["launcherTrails", "tabletTurnstile"]
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
    onLoaded: { try { root.ui = JSON.parse(text()) || {} } catch (e) { root.ui = {} } }
    onLoadFailed: root.ui = {}
  }
  // The theme's extra colours, for the trails and "Theme colors" tiles.
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

  // Tablet mode's accent (tablet-mode writes [tablet] accent); its default
  // when previewed from the laptop.
  readonly property color accent: root.ui.tabletAccent || Commons.Color.pick("tablet.accent", "#ff6b81")
  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color border: Commons.Color.menu.border
  readonly property string fontFamily: Style.font.menuFamily

  // ---- Tiles ----
  // { id: desktop id or "clock" / "battery" / "apps", size: "s" | "w" | "l" }
  readonly property var defaultTiles: [
    { id: "clock", size: "w" },
    { id: "org.jellyfin.JellyfinDesktop", size: "l" },
    { id: "org.gnome.Showtime", size: "s" },
    { id: "com.github.johnfactotum.Foliate", size: "s" },
    { id: "info.febvre.Komikku", size: "s" },
    { id: "Kindle", size: "s" },
    { id: "battery", size: "s" },
    { id: "org.kde.krita", size: "w" },
    { id: "com.github.flxzt.rnote", size: "s" },
    { id: "com.github.xournalpp.xournalpp", size: "s" },
    { id: "org.es_de.frontend", size: "s" },
    { id: "com.libretro.RetroArch", size: "s" },
    { id: "steam", size: "s" },
    { id: "firefox", size: "w" }
  ]
  readonly property var tiles: {
    var list = Array.isArray(root.ui.tabletTiles) ? root.ui.tabletTiles : root.defaultTiles
    // Skip apps that aren't installed (any more).
    list = list.filter(function(t) { return t && (root.special(t.id) || DesktopEntries.byId(t.id)) })
    // "Continue" tiles first: where you left off (~/.local/bin/tablet-continue).
    var cont = []
    if (root.uiOpt("tabletContinue", true))
      for (var i = 0; i < root.continueItems.length; i++) cont.push({ id: "continue", size: "w", item: root.continueItems[i] })
    return cont.concat(list)
  }

  // ---- Continue: the latest book, comic, drawing, show ----
  property var continueItems: []
  Process {
    id: continueProc
    command: [Quickshell.env("HOME") + "/.local/bin/tablet-continue"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.continueItems = JSON.parse(text) || [] } catch (e) { root.continueItems = [] } }
    }
  }
  function special(id) { return id === "clock" || id === "battery" || id === "apps" || id === "continue" }
  function tileLabel(t) {
    if (t.id === "clock" || t.id === "continue") return ""
    if (t.id === "battery") return "battery"
    if (t.id === "apps") return "all apps"
    var app = DesktopEntries.byId(t.id)
    return app ? String(app.name) : t.id
  }
  function tileIcon(t) {
    if (root.special(t.id)) return ""
    var app = DesktopEntries.byId(t.id)
    var value = app ? String(app.icon || "") : ""
    if (value.charAt(0) === "/") return "file://" + value
    var themed = value ? Quickshell.iconPath(value, true) : ""
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }
  function tileColor(i) {
    var mode = root.uiOpt("tabletTileColors", "accent")
    if (mode === "palette") return root.themePalette[i % root.themePalette.length]
    if (mode === "dark") return Qt.rgba(1, 1, 1, 0.08)
    return root.accent
  }

  // Columns: 6 across in landscape, 4 when the screen stands upright.
  readonly property bool portrait: panel.height > panel.width
  readonly property int columns: portrait ? 4 : 6
  // First-fit packing into a grid of `columns`; returns positions in cells.
  readonly property var layout: {
    var C = root.columns, grid = [], out = [], rows = 0
    function free(x, y, w, h) {
      if (x + w > C) return false
      for (var yy = y; yy < y + h; yy++) for (var xx = x; xx < x + w; xx++) if (grid[yy] && grid[yy][xx]) return false
      return true
    }
    for (var i = 0; i < root.tiles.length; i++) {
      var t = root.tiles[i]
      var w = t.size === "s" ? 1 : 2, h = t.size === "l" ? 2 : 1
      var placed = false
      for (var y = 0; !placed && y < 100; y++) {
        for (var x = 0; x + w <= C; x++) {
          if (!free(x, y, w, h)) continue
          for (var yy = y; yy < y + h; yy++) { grid[yy] = grid[yy] || []; for (var xx = x; xx < x + w; xx++) grid[yy][xx] = true }
          out.push({ x: x, y: y, w: w, h: h })
          rows = Math.max(rows, y + h)
          placed = true
          break
        }
      }
    }
    return { cells: out, rows: Math.max(1, rows) }
  }

  // ---- Live tiles: clock and battery ----
  property date now: new Date()
  Timer { interval: 1000; repeat: true; running: root.opened; triggeredOnStart: true; onTriggered: root.now = new Date() }
  property int battery: -1
  property bool charging: false
  FileView { id: batCap; path: "/sys/class/power_supply/BAT0/capacity"; printErrors: false; onLoaded: root.battery = parseInt(String(text())) }
  FileView { id: batStatus; path: "/sys/class/power_supply/BAT0/status"; printErrors: false; onLoaded: root.charging = /Charging|Full/.test(String(text())) }
  Timer { interval: 20000; repeat: true; running: root.opened; triggeredOnStart: true; onTriggered: { batCap.reload(); batStatus.reload() } }

  // ---- Open / close ----
  // Tiles swing in like Windows Phone's turnstile; `phase` drives it
  // (0 = folded away, 1 = in place) with each tile a little behind the last.
  property real phase: 0
  property bool leaving: false
  NumberAnimation { id: turnIn; target: root; property: "phase"; from: 0; to: 1; duration: 620; easing.type: Easing.Linear }
  SequentialAnimation {
    id: turnOut
    property var after: null
    NumberAnimation { target: root; property: "phase"; to: 0; duration: 300; easing.type: Easing.Linear }
    ScriptAction { script: { var f = turnOut.after; turnOut.after = null; root.dismiss(); if (f) f() } }
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    // Entering tablet mode: only if the greeter is switched on.
    if (payload.auto === true && root.uiOpt("tabletGreeter", true) === false) { root.dismiss(); return }
    // Previewed from Desktop settings → Tablet: closing goes back there.
    root.preview = payload.preview === true
    // Opened by folding the screen back: hands are still on the screen, so
    // touches don't count for a moment (none at all for 1.2 s, none outside
    // the box for 3 s).
    if (payload.auto === true) { root.settling = true; root.folding = true; settleTimer.restart(); foldTimer.restart() }
    root.leaving = false
    if (root.uiOpt("tabletContinue", true) && !continueProc.running) continueProc.running = true
    root.opened = true
    root.now = new Date()
    if (root.uiOpt("tabletTurnstile", true)) turnIn.restart()
    else root.phase = 1
    Qt.callLater(function() { keys.forceActiveFocus() })
  }
  property bool preview: false
  property bool settling: false
  property bool folding: false
  Timer { id: settleTimer; interval: 1200; onTriggered: root.settling = false }
  Timer { id: foldTimer; interval: 3000; onTriggered: root.folding = false }
  function backToSettings() {
    if (!root.preview) return
    root.preview = false
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "daa.settings", JSON.stringify({ page: "tablet" })])
  }
  function close() { root.opened = false; turnIn.stop() }
  function dismiss() {
    root.opened = false
    turnIn.stop()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "daa.tablet-greeter")
  }
  function toggle() { if (root.opened) root.dismiss(); else root.open("{}") }
  // Swing the tiles away, then run `after` (or just close).
  function leave(after) {
    if (root.leaving) return
    root.leaving = true
    if (after) root.preview = false
    else if (root.preview) after = root.backToSettings
    if (!root.uiOpt("tabletTurnstile", true)) { root.dismiss(); if (after) after(); return }
    turnIn.stop()
    turnOut.after = after || null
    turnOut.restart()
  }
  function launch(t) {
    if (t.id === "clock" || t.id === "battery") return
    if (t.id === "continue") { var cmd = t.item.cmd; root.leave(function() { Quickshell.execDetached(cmd) }); return }
    root.leave(function() {
      if (t.id === "apps") Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "daa.tablet-apps-grid"])
      else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", t.id + ".desktop"])
    })
  }

  // A new window (an app launched some other way) means we're done here.
  Connections {
    target: root.opened ? Hyprland : null
    function onRawEvent(event) { if (event.name === "openwindow" && !root.leaving) root.dismiss() }
  }

  // ---- Easter egg: turn the tablet all the way round anticlockwise while
  // this is open (tablet-mode autorotate → daa.spin "crash" calls fall()).
  // The box tips over backwards and the tiles, like sheets of paper with air
  // under them, come loose and drift down, swaying and flipping. ----
  property bool falling: false
  property real fallT: 0
  property var paperStart: []      // each tile's top-left on screen when it started
  IpcHandler {
    target: "daa.tablet-greeter"
    function fall(): void {
      if (!root.opened || root.falling || root.leaving) return
      var pts = []
      for (var i = 0; i < tileRep.count; i++) {
        var it = tileRep.itemAt(i)
        pts.push(it ? it.mapToItem(panelRoot, 0, 0) : Qt.point(0, 0))
      }
      root.paperStart = pts
      root.fallT = 0
      root.falling = true
    }
    // A double tap (on daa.spin or here) skips the rest.
    function endFall(): void {
      if (!root.falling) return
      root.falling = false
      root.fallT = 0
      root.dismiss()
    }
  }
  FrameAnimation {
    running: root.falling
    onTriggered: {
      root.fallT += frameTime
      if (root.fallT > 4.6) { root.falling = false; root.fallT = 0; root.dismiss() }
    }
  }
  // The box: tips back about its bottom edge, faster and faster, then gone.
  readonly property real tip: root.falling ? Math.min(88, 88 * Math.pow(Math.max(0, root.fallT - 0.25) / 0.85, 2)) : 0

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "daa-tablet-greeter"
    WlrLayershell.layer: WlrLayer.Overlay
    // The keyboard is folded away in tablet mode: don't take it from anything.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    // Desktop settings → Tablet → Background opacity (box and dimming).
    readonly property real boxOpacity: Math.max(0.15, Math.min(1, Number(root.uiOpt("tabletGreeterOpacity", 85)) / 100))
    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: Math.min(1, root.phase * 2) * Math.min(1, panel.boxOpacity / 0.85)
    }
    // Tap anywhere outside the box: dismiss (not while the screen is still
    // being folded back).
    MouseArea { anchors.fill: parent; onClicked: if (!root.folding) root.leave(null) }

    Item {
      id: keys
      focus: true
      Keys.onEscapePressed: root.leave(null)
    }

    BorderSurface {
      id: card
      readonly property int pad: Style.space(34)
      readonly property int gap: Style.space(8)
      readonly property int headerH: Style.space(64)
      readonly property int footerH: Style.space(72)
      // Cell size: fill ~80% of the width, but never taller than the screen allows.
      readonly property real cellByW: (panel.width * (root.portrait ? 0.9 : 0.72) - pad * 2 - gap * (root.columns - 1)) / root.columns
      readonly property real cellByH: (panel.height * 0.9 - pad * 2 - headerH - footerH - gap * (root.layout.rows - 1)) / root.layout.rows
      readonly property real cell: Math.floor(Math.max(Style.space(60), Math.min(cellByW, cellByH, Style.space(150))))
      width: root.columns * cell + gap * (root.columns - 1) + pad * 2
      height: headerH + root.layout.rows * cell + gap * (root.layout.rows - 1) + footerH + pad * 2
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, panel.boxOpacity)
      borderSpec: Border.none()
      padding: 0
      scale: 0.94 + 0.06 * Math.min(1, root.phase * 1.6)
      opacity: Math.min(1, root.phase * 2.5) * (root.falling ? Math.max(0, 1 - Math.max(0, root.fallT - 1.0) / 0.35) : 1)
      transform: Rotation {
        origin.x: card.width / 2
        origin.y: card.height
        axis { x: 1; y: 0; z: 0 }
        angle: -root.tip
      }

      MouseArea { anchors.fill: parent; onClicked: {} }
      // While settling, a shield over the whole box eats stray touches.
      MouseArea { anchors.fill: parent; z: 100; visible: root.settling; onClicked: {} }

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
        readonly property color cyan: root.accent
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


      // ---- Header: "tablet", lower-case and light, Windows Phone style ----
      Item {
        id: header
        x: card.pad
        y: card.pad
        width: card.width - card.pad * 2
        height: card.headerH
        Text {
          id: title
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          text: "tablet"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(46)
          font.weight: Font.Light
          // Slides in from the right, like a Windows Phone page title.
          transform: Translate { x: (1 - Math.min(1, root.phase * 1.4)) * Style.space(60) }
        }
        Text {
          anchors.left: title.right
          anchors.leftMargin: Style.space(14)
          anchors.baseline: title.baseline
          text: "what are we doing?"
          color: root.foreground
          opacity: 0.45 * Math.min(1, root.phase * 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.Light
        }
      }

      // ---- Close: a big x in the corner ----
      Rectangle {
        id: closeButton
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.pad - Style.space(4)
        width: Style.space(52)
        height: width
        radius: width / 2
        color: closeArea.pressed ? Util.alpha(root.accent, 0.35) : Qt.rgba(1, 1, 1, 0.07)
        Text {
          anchors.centerIn: parent
          text: "󰅖"
          color: closeArea.pressed ? root.accent : root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.space(26)
        }
        MouseArea { id: closeArea; anchors.fill: parent; anchors.margins: -Style.space(8); onClicked: root.leave(null) }
      }

      // ---- Tiles ----
      Item {
        id: grid
        x: card.pad
        y: card.pad + card.headerH
        width: card.width - card.pad * 2
        height: root.layout.rows * card.cell + card.gap * (root.layout.rows - 1)

        Repeater {
          id: tileRep
          model: root.tiles
          Item {
            id: tile
            required property var modelData
            required property int index
            readonly property var pos: root.layout.cells[index] || { x: 0, y: 0, w: 1, h: 1 }
            readonly property bool live: modelData.id === "clock" || modelData.id === "battery"
            x: pos.x * (card.cell + card.gap)
            y: pos.y * (card.cell + card.gap)
            width: pos.w * card.cell + (pos.w - 1) * card.gap
            height: pos.h * card.cell + (pos.h - 1) * card.gap

            // Turnstile: swing about the grid's left edge, top rows first.
            readonly property real delay: Math.min(0.45, (pos.y * 0.09 + pos.x * 0.035))
            readonly property real k: Math.max(0, Math.min(1, (root.phase - delay) / (1 - 0.45)))
            readonly property real eased: 1 - Math.pow(1 - k, 3)
            opacity: Math.min(1, k * 2.2)
            transform: [
              Rotation {
                origin.x: -tile.x
                origin.y: tile.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: (1 - tile.eased) * (root.leaving ? 70 : -80)
              },
              // Press tilt: the tile leans toward where it's pressed.
              Rotation {
                origin.x: tile.width / 2
                origin.y: tile.height / 2
                axis { x: tileArea.tiltY; y: tileArea.tiltX; z: 0 }
                angle: tileArea.pressed ? 9 : 0
                Behavior on angle { NumberAnimation { duration: 110 } }
              }
            ]
            scale: tileArea.pressed ? 0.96 : 1
            Behavior on scale { NumberAnimation { duration: 110 } }

            Rectangle {
              anchors.fill: parent
              color: root.tileColor(tile.index)
              // Live tiles sit a shade darker so the apps stand out.
              Rectangle { anchors.fill: parent; color: "black"; opacity: tile.live ? 0.25 : 0 }
            }

            // App icon: full colour, or a white silhouette (classic, best for flat icons).
            Image {
              id: icon
              visible: !tile.live && !root.special(tile.modelData.id) && root.uiOpt("tabletTileIcons", "colour") !== "mono"
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -Style.space(6)
              width: Math.min(tile.width, tile.height) * (tile.modelData.size === "l" ? 0.42 : 0.46)
              height: width
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              source: root.tileIcon(tile.modelData)
              smooth: true
            }
            MultiEffect {
              visible: !tile.live && root.uiOpt("tabletTileIcons", "colour") === "mono" && !root.special(tile.modelData.id)
              source: icon
              anchors.fill: icon
              brightness: 1.0
              colorization: 1.0
              colorizationColor: "white"
            }
            Text {
              visible: tile.modelData.id === "apps"
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -Style.space(6)
              text: "󰀻"
              color: "white"
              font.family: Style.font.family
              font.pixelSize: Math.min(tile.width, tile.height) * 0.38
            }

            // Continue tile: the cover / thumbnail, what it is, how far in.
            Item {
              visible: tile.modelData.id === "continue"
              anchors.fill: parent
              clip: true
              readonly property var item: tile.modelData.item || ({})
              Image {
                id: contImage
                anchors.fill: parent
                source: parent.item.image ? "file://" + parent.item.image : ""
                sourceSize.width: 480
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
              Text {
                visible: contImage.status !== Image.Ready
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                text: ({ read: "󰂿", comic: "󱗖", draw: "󰏬", watch: "󰐊" })[parent.item.kind] || "󰐊"
                color: "white"
                opacity: 0.8
                font.family: Style.font.family
                font.pixelSize: tile.height * 0.32
              }
              Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                  GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
                  GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.05) }
                  GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.75) }
                }
              }
              Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                text: parent.item.label || ""
                color: "white"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.Light
              }
              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.space(10)
                anchors.bottomMargin: Style.space(12)
                Text {
                  width: parent.width
                  text: parent.parent.item.title || ""
                  elide: Text.ElideRight
                  color: "white"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  width: parent.width
                  visible: text !== ""
                  text: parent.parent.item.sub || ""
                  elide: Text.ElideRight
                  color: "white"
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              // How far in: a thin accent line along the bottom.
              Rectangle {
                visible: typeof parent.item.progress === "number"
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: Style.space(4)
                width: parent.width * Math.max(0.02, parent.item.progress || 0)
                color: root.accent
              }
            }

            // Clock live tile: big time, day and date.
            Column {
              visible: tile.modelData.id === "clock"
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(12)
              Text {
                text: Qt.formatTime(root.now, "h:mm")
                color: "white"
                font.family: root.fontFamily
                font.pixelSize: tile.height * 0.42
                font.weight: Font.Light
              }
              Text {
                text: Qt.formatDate(root.now, "dddd d MMMM").toLowerCase()
                color: "white"
                opacity: 0.85
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
            // Battery live tile: the level, filling the tile from the bottom.
            Rectangle {
              visible: tile.modelData.id === "battery" && root.battery >= 0
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: parent.height * Math.max(0, root.battery) / 100
              color: "white"
              opacity: 0.12
            }
            Text {
              visible: tile.modelData.id === "battery"
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -Style.space(6)
              text: root.battery >= 0 ? root.battery + (root.charging ? "󱐋" : "%") : "—"
              color: "white"
              font.family: root.fontFamily
              font.pixelSize: tile.height * 0.3
              font.weight: Font.Light
            }

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(9)
              text: root.tileLabel(tile.modelData)
              elide: Text.ElideRight
              color: "white"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: tileArea
              anchors.fill: parent
              property real tiltX: 0
              property real tiltY: 0
              onPressed: function(mouse) {
                tiltX = (mouse.x / width - 0.5) * 2
                tiltY = -(mouse.y / height - 0.5) * 2
              }
              onClicked: root.launch(tile.modelData)
            }
          }
        }
      }

      // ---- Footer: big buttons, never a swipe ----
      Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: card.pad
        anchors.right: parent.right
        anchors.rightMargin: card.pad
        spacing: Style.space(10)
        opacity: Math.min(1, root.phase * 1.5)

        Repeater {
          model: [
            { label: "All apps", glyph: "󰀻", act: "apps" },
            { label: "Settings", glyph: "󰒓", act: "settings" },
            { label: "Not now", glyph: "󰅖", act: "close" }
          ]
          Rectangle {
            id: footButton
            required property var modelData
            width: footLabel.implicitWidth + Style.space(58)
            height: Style.space(52)
            radius: height / 2
            color: footArea.pressed ? Util.alpha(root.accent, 0.35)
              : modelData.act === "close" ? Util.alpha(root.accent, 0.18) : Qt.rgba(1, 1, 1, 0.07)
            Row {
              anchors.centerIn: parent
              spacing: Style.space(8)
              Text {
                text: footButton.modelData.glyph
                color: footButton.modelData.act === "close" ? root.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: footLabel
                text: footButton.modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            MouseArea {
              id: footArea
              anchors.fill: parent
              onClicked: {
                var act = footButton.modelData.act
                if (act === "close") root.leave(null)
                else if (act === "apps") root.launch({ id: "apps" })
                else root.leave(function() {
                  Quickshell.execDetached(["omarchy-shell", "shell", "summon", "daa.settings", JSON.stringify({ page: "tablet" })])
                })
              }
            }
          }
        }
      }
    }

    // While falling, a double tap anywhere skips the whole show.
    MouseArea {
      anchors.fill: parent
      z: 1000
      visible: root.falling
      onDoubleClicked: {
        Quickshell.execDetached(["omarchy-shell", "-q", "daa.spin", "stop"])
        root.falling = false
        root.fallT = 0
        root.dismiss()
      }
    }

    // The paper tiles (copies of the real ones, which hide while falling).
    Item {
      id: panelRoot
      anchors.fill: parent
      Repeater {
        model: root.falling ? tileRep.count : 0
        ShaderEffectSource {
          id: paper
          required property int index
          readonly property var src: tileRep.itemAt(index)
          readonly property point start: root.paperStart[index] || Qt.point(0, 0)
          // Stable per-tile randomness.
          readonly property real r1: Math.abs(Math.sin(index * 12.9898) * 43758.5453) % 1
          readonly property real r2: Math.abs(Math.sin(index * 78.233) * 12543.1234) % 1
          // The box drops away first; each sheet lifts off a moment later.
          readonly property real lt: Math.max(0, root.fallT - 0.3 - r1 * 0.35)
          // Paper: barely accelerates, then a slow terminal speed.
          readonly property real vTerm: 170 + r2 * 140
          readonly property real dropY: lt < 0.45 ? 0.5 * (vTerm / 0.45) * lt * lt : 0.5 * vTerm * 0.45 + vTerm * (lt - 0.45)
          readonly property real w: 2.2 + r1 * 1.6
          readonly property real ph: r2 * 6.28
          sourceItem: src
          hideSource: true
          live: false
          width: src ? src.width : 0
          height: src ? src.height : 0
          x: start.x + Math.sin(w * lt + ph) * (30 + r1 * 50) * Math.min(1, lt * 1.5) + (r2 - 0.5) * 120 * lt
          y: start.y + dropY
          // Sway tilt and a slow flip, as air catches it.
          rotation: Math.sin(w * lt + ph + 1.57) * 22 * Math.min(1, lt * 2)
          transform: Rotation {
            origin.x: paper.width / 2
            origin.y: paper.height / 2
            axis { x: 1; y: 0.3; z: 0 }
            angle: Math.sin(paper.w * 0.8 * paper.lt + paper.ph) * 55 * Math.min(1, paper.lt * 1.5)
          }
          scale: 1 - Math.min(0.25, lt * 0.06)
          opacity: Math.min(1, Math.max(0, (4.6 - root.fallT) / 0.5))
        }
      }
    }
  }
}
