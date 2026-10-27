import Quickshell
import Quickshell.Io
import QtQuick
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui

// Omarchy logo on its own island after the left island (daa.desktop-bar
// logoEntries). It grows while hovered, and hovering drops a card of
// shortcuts: apps on top; below, the network shortcuts on the left and home
// folders on the right. The card grows out of a stem from the logo, hangs
// with its left edge under workspace 2, and light trails run round its
// border like the SUPER+R launcher's logo frame (white head, accent or red
// body, fading tail; now and then another theme colour). The tiles flip in
// one after another like a split-flap board. Shortcuts
// that have a dropdown show it (dropdowns.lua then centres the cursor on it).
BarWidget {
  id: root
  moduleName: "daa.desktop-shortcuts"

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

  readonly property bool guest: Quickshell.env("USER") === "guest"

  // White, or light coral while the ABACABB blood mode (daa.search) is on;
  // the white SVG icons get recoloured copies then.
  readonly property bool blood: Qt.colorEqual(Color.accent, "#e0607a")
  // Light themes get dark tiles/text: the theme's foreground instead of white.
  readonly property bool lightTheme: 0.299 * Color.background.r + 0.587 * Color.background.g + 0.114 * Color.background.b > 0.5
  readonly property color white: blood ? "#ffb8c6" : lightTheme ? Color.foreground : "#ffffff"
  readonly property var svgText: {
    // text() isn't a property; the loaded flags make this re-evaluate.
    if (!(gns3Svg.loaded && tailscaleSvg.loaded && obsidianSvg.loaded && retroarchSvg.loaded)) return ({})
    return { "gns3.svg": gns3Svg.text(), "tailscale.svg": tailscaleSvg.text(),
      "obsidian.svg": obsidianSvg.text(), "retroarch.svg": retroarchSvg.text() }
  }
  FileView { id: gns3Svg; path: root.home + "/.config/omarchy/plugins/daa.desktop-shortcuts/gns3.svg"; printErrors: false }
  FileView { id: tailscaleSvg; path: root.home + "/.config/omarchy/plugins/daa.desktop-shortcuts/tailscale.svg"; printErrors: false }
  FileView { id: obsidianSvg; path: root.home + "/.config/omarchy/plugins/daa.desktop-shortcuts/obsidian.svg"; printErrors: false }
  FileView { id: retroarchSvg; path: root.home + "/.config/omarchy/plugins/daa.desktop-shortcuts/retroarch.svg"; printErrors: false }
  // The white SVG icons, recoloured when the tile colour isn't plain white
  // (accent mode, or the blood mode's light coral).
  function iconSource(name) {
    if (!name) return ""
    var tint = String(root.builtinTint)
    if (!Qt.colorEqual(root.builtinTint, "#ffffff") && root.svgText[name])
      return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(String(root.svgText[name]).replace(/#ffffff/gi, tint))
    return "file://" + root.home + "/.config/omarchy/plugins/daa.desktop-shortcuts/" + name
  }
  readonly property string home: Quickshell.env("HOME")

  // Files open in the Files dropdown, relaunched at that folder.
  function folder(path) {
    return "hyprctl eval 'dropdown_relaunch(\"files\", [==[" + Util.shellQuote(path) + "]==])'"
  }

  // Built-in shortcuts by key. "favorites" (settings, ordered) picks the top
  // row from these keys and/or desktop-entry ids (any installed app, shown
  // with its own icon); "shortcutsHidden" hides bottom-row keys.
  // daa.settings' Favorites tab edits both.
  readonly property var builtins: ({
    firefox: { icon: "\uf269", label: "Firefox", command: "omarchy-launch-browser" },
    obsidian: { image: "obsidian.svg", label: "Obsidian", command: "uwsm-app -- obsidian" },
    sublime: { icon: "\ue7aa", label: "Sublime", command: "uwsm-app -- subl" },
    jellyfin: { icon: "󰎁", label: "Jellyfin", command: "uwsm-app -- jellyfin-desktop" },
    immich: { icon: "󰋩", label: "Immich", command: "~/.local/bin/server-status open Immich" },
    gns3: { image: "gns3.svg", label: "GNS3", command: "uwsm-app -- ~/.local/bin/gns3" },
    // Same as the games button: ES-DE, or RetroArch when it's missing.
    esde: { image: "retroarch.svg", label: "ES-DE", command: "command -v es-de >/dev/null && exec uwsm-app -- es-de || exec uwsm-app -- retroarch" },
    terminal: { icon: "\uf120", label: "Terminal", command: "hyprctl eval 'dropdown_show(\"terminal\")'" },
    tailscale: { image: "tailscale.svg", label: "Tailscale", command: "~/.local/bin/tailscale-toggle" },
    lab: { icon: "󰢹", label: "Lab", command: "uwsm-app -- remmina", lab: true },
    mullvad: { icon: "󰦝", label: "Mullvad", command: "hyprctl eval 'dropdown_show(\"vpn\")'" },
    home: { icon: "󰋜", label: "Home", command: folder(home) },
    documents: { icon: "󰈙", label: "Documents", command: folder(home + "/Documents") },
    downloads: { icon: "󰉍", label: "Downloads", command: folder(home + "/Downloads") }
  })
  readonly property var defaultFavorites: ["firefox", "obsidian", "sublime", "jellyfin", "immich", "gns3", "esde"]

  // Settings "favoriteIconColor": original (app's own icon) / white /
  // accent. Recoloured apps use, in order: the app's -symbolic icon, a Nerd
  // Font glyph from appGlyphs, else a badge with the app's initial (tinting
  // the full-colour icon turned square icons into solid blocks).
  readonly property string iconColorMode: root.uiOpt("favoriteIconColor", "original")
  readonly property color favTint: iconColorMode === "accent" ? Color.accent : root.white
  // Built-ins have no "original" colours, so only accent changes them.
  readonly property color builtinTint: iconColorMode === "accent" ? Color.accent : root.white

  // Built-ins whose app isn't installed are skipped (not everyone has
  // Tailscale, GNS3, Mullvad, …). `needs`: a command or a path to check.
  readonly property var needs: ({
    obsidian: "obsidian", sublime: "subl", jellyfin: "jellyfin-desktop", gns3: "gns3",
    immich: "~/.local/bin/server-status", esde: "es-de|retroarch", tailscale: "tailscale",
    lab: "remmina", mullvad: "mullvad"
  })
  property var missing: []
  Process {
    running: true
    command: ["bash", "-c",
      "while read -r key alts; do ok=; IFS='|' read -ra opts <<<\"$alts\"; " +
      "for o in \"${opts[@]}\"; do o=${o/#\\~/$HOME}; " +
      "if [[ $o == /* ]]; then [[ -x $o ]] && ok=1; else command -v \"$o\" >/dev/null && ok=1; " +
      "[[ -x $HOME/.local/bin/$o ]] && ok=1; fi; done; [[ $ok ]] || echo \"$key\"; done"]
    stdinEnabled: true
    onStarted: {
      var lines = []
      for (var k in root.needs) lines.push(k + " " + root.needs[k])
      write(lines.join("\n") + "\n")
      stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.missing = String(text || "").split("\n").filter(function(l) { return l.length > 0 })
    }
  }
  readonly property var appGlyphs: ({
    "Alacritty": "\ue795", "org.gnome.Ptyxis": "\ue795", "kitty": "\ue795",
    "org.gnome.Nautilus": "󰉋", "org.kde.dolphin": "󰉋",
    "chromium": "\uf268", "google-chrome": "\uf268", "brave-browser": "󰖟", "firefox": "\uf269",
    "code": "󰨞", "visual-studio-code": "󰨞", "sublime_text": "\ue7aa", "nvim": "\ue7c5",
    "steam": "\uf1b6", "discord": "\uf1ff", "spotify": "\uf1bc", "thunderbird": "\uf0e0",
    "org.gnome.Calculator": "󰃬", "org.gnome.Calendar": "󰃭", "org.gnome.Weather": "󰖐",
    "org.remmina.Remmina": "󰢹", "com.obsproject.Studio": "󰑋", "gimp": "\uf338",
    "org.inkscape.Inkscape": "\uf33b", "libreoffice-writer": "󰈬", "libreoffice-calc": "󰈛",
    "org.wireshark.Wireshark": "󰒍", "bitwarden": "󰞀", "Bitwarden": "󰞀"
  })

  function entryFor(key) {
    if (root.builtins[key]) return root.builtins[key]
    var app = DesktopEntries.byId(key)
    if (!app) return null
    var icon = String(app.icon || "")
    var symbolic = icon && icon.charAt(0) !== "/" ? Quickshell.iconPath(icon + "-symbolic", true) : ""
    return { appIcon: icon, label: String(app.name || key), symbolic: symbolic || "",
      glyph: root.appGlyphs[key] || "",
      command: "uwsm-app -- gtk-launch " + Util.shellQuote(key + ".desktop") }
  }
  function rowOf(keys) {
    var hidden = root.uiOpt("shortcutsHidden", [])
    var out = []
    for (var i = 0; i < keys.length; i++) {
      if (hidden.indexOf(keys[i]) !== -1 || root.missing.indexOf(keys[i]) !== -1) continue
      var e = root.entryFor(keys[i])
      if (e && !(e.lab && root.guest)) out.push(e)
    }
    return out
  }

  readonly property var topRow: {
    DesktopEntries.applications.values   // re-check once entries load
    return rowOf(root.uiOpt("favorites", root.defaultFavorites))
  }

  // Bottom row: network on the left, folders on the right.
  readonly property var networkRow: rowOf(["terminal", "tailscale", "lab", "mullvad"])
  readonly property var folderRow: rowOf(["home", "documents", "downloads"])

  readonly property bool hovered: button.tooltipHovered
  property bool buttonHovered: false
  property bool popupHovered: false   // the popup's open area (over the island, by the stem)
  property bool cardHovered: false    // the card itself: its tiles take hover from what's behind them
  property bool open: false
  // 0 → 1 drives the whole entrance; stem, card, trace and tiles each read
  // their own slice of it.
  property real reveal: 0

  function phase(from, length) { return Math.max(0, Math.min(1, (reveal - from) / length)) }
  function outCubic(t) { return 1 - Math.pow(1 - t, 3) }
  readonly property real stemT: outCubic(phase(0, 0.2))
  readonly property real bloomT: outCubic(phase(0.14, 0.34))

  // Theme colours for the light trails, re-read when the theme changes:
  // accent and red, plus the specials one trail at a time borrows.
  // The live accent (follows theme switches and the ABACABB blood mode).
  readonly property color traceStart: Color.accent
  property color traceEnd: Color.urgent
  property var traceSpecials: ["#9ece6a", "#ad8ee6", "#e0af68", "#eb927b", "#7aa2f7"]
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var text = String(this.text())
      function pick(key) {
        var m = text.match(new RegExp("^" + key + "\\s*=\\s*\"(#[0-9a-fA-F]{6})\"", "m"))
        return m ? m[1] : null
      }
      root.traceEnd = pick("red") || Color.urgent
      var specials = ["green", "magenta", "yellow", "orange", "blue"].map(pick).filter(Boolean)
      if (specials.length) root.traceSpecials = specials
    }
  }

  // The island widens while the logo grows, making room for the stem.
  property real grow: root.hovered || root.open ? 1 : 0
  Behavior on grow { enabled: root.uiOpt("shortcutCardAnimations", true); NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
  implicitWidth: button.implicitWidth + Style.space(8) * grow
  implicitHeight: button.implicitHeight

  function setHover(which, value) {
    if (which === "button") buttonHovered = value
    else if (which === "popup") popupHovered = value
    else cardHovered = value
    if (buttonHovered || popupHovered || cardHovered) {
      closeTimer.stop()
      if (!open) openTimer.restart()
    } else {
      openTimer.stop()
      closeTimer.restart()
    }
  }

  function launch(command) {
    open = false
    if (root.bar) root.bar.run(command)
  }

  // Card's left edge, in bar coordinates: under workspace 2.
  readonly property real cardLeft: 65
  // Where the logo sits in the bar, taken when the card opens (the anchor
  // needs plain numbers; mapToItem isn't a live binding).
  property real logoX: 0

  onOpenChanged: {
    if (open) logoX = root.mapToItem(null, 0, 0).x
    revealAnim.stop()
    revealAnim.to = open ? 1 : 0
    // Settings: "shortcutCardAnimations" off = the card just appears.
    revealAnim.duration = !root.uiOpt("shortcutCardAnimations", true) ? 1 : open ? 520 : 180
    revealAnim.easing.type = open ? Easing.Linear : Easing.InQuad
    revealAnim.start()
  }

  NumberAnimation { id: revealAnim; target: root; property: "reveal" }

  Timer {
    id: openTimer
    interval: 150
    onTriggered: if (!root.vertical && !(root.bar && root.bar.activePopout)) root.open = true
  }

  Timer {
    id: closeTimer
    // Closes once the pointer has been off the shape (logo island, stem,
    // card) for 0.3 s.
    interval: 300
    onTriggered: root.open = false
  }

  HoverHandler {
    onHoveredChanged: root.setHover("button", hovered)
    Component.onDestruction: if (hovered) root.setHover("button", false)
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    fontFamily: "omarchy"
    horizontalMargin: 7.5
    foreground: root.hovered || root.open ? Color.accent : (root.bar ? root.bar.barForeground : Color.foreground)
    // Left click toggles the card; right click edits the favourites.
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        root.open = false
        if (root.bar) root.bar.run("omarchy-shell shell summon daa.settings '{\"page\":\"favorites\"}'")
      } else root.open = !root.open
    }
    // Grows while hovered (and while its card is open); see `grow`.
    scale: 1 + 0.45 * root.grow
  }

  PopupWindow {
    id: popup

    readonly property int padding: Style.space(12)
    readonly property int stemLength: Style.space(14)
    // daa.desktop-bar's island geometry (BarPill: pillInset 4, pillPadding
    // space(6)); the bar doesn't hand these to widgets.
    readonly property real islandPadding: Style.space(6)
    // The island grows to the bar's full height with the logo (Bar.qml);
    // the popup is sized for the grown island.
    readonly property real pillHeight: root.barSize
    readonly property real islandInset: 4 * (1 - root.grow)
    // The logo island has square corners (its BarPill radius in Bar.qml).
    readonly property real islandRadius: 0
    // Popup coordinates: x 0 = the card's left edge, y 0 = the island's top.
    readonly property int offsetX: Math.round(root.cardLeft - root.logoX)
    readonly property real islandX0: -offsetX - islandPadding
    readonly property real islandX1: -offsetX + root.width + islandPadding
    readonly property real stemX: -offsetX + root.width / 2
    // As wide as the island's flat bottom allows, leaving a little shoulder.
    readonly property real stemWidth: Math.max(4, Math.min(Style.space(18),
      islandX1 - islandX0 - islandRadius * 2 - Style.space(6)))
    readonly property int tileWidth: Style.space(70)
    readonly property int tileHeight: Style.space(62)
    readonly property int rowGap: Style.space(6)
    readonly property int groupGap: Style.space(24)
    readonly property real innerWidth: Math.max(root.topRow.length,
      root.networkRow.length + root.folderRow.length) * tileWidth + groupGap
    readonly property real fullWidth: innerWidth + padding * 2
    readonly property real cardHeight: tileHeight * 2 + rowGap + padding * 2
    readonly property real cardTop: pillHeight + stemLength
    readonly property real fullHeight: cardTop + cardHeight
    readonly property int tileCount: root.topRow.length + root.networkRow.length + root.folderRow.length

    visible: root.open || root.reveal > 0
    color: "transparent"
    implicitWidth: Math.ceil(fullWidth)
    implicitHeight: Math.ceil(fullHeight)

    // Covers the island too (the light trails run round it), so the top
    // corner lines up with the island's top and the card's left edge.
    anchor {
      item: root
      adjustment: PopupAdjustment.None
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.x: popup.offsetX
      rect.y: Math.round(root.height / 2 - popup.pillHeight / 2)
      rect.width: 1
      rect.height: 1
    }

    // The popup sits over the logo while open, so it takes over the logo's
    // hover, and a click there closes the card like clicking the logo.
    // Only the island and the stem count as hovering here (the card has
    // its own handler); the see-through rest of the popup doesn't.
    Item {
      x: popup.islandX0
      width: popup.islandX1 - popup.islandX0
      height: popup.cardTop
      HoverHandler {
        // Inside the island, or over the stem below it.
        readonly property bool overShape: hovered && (point.position.y < popup.pillHeight
          || Math.abs(point.position.x + popup.islandX0 - popup.stemX) <= popup.stemWidth / 2)
        onOverShapeChanged: root.setHover("popup", overShape)
      }
    }
    MouseArea {
      x: popup.islandX0
      width: popup.islandX1 - popup.islandX0
      height: popup.pillHeight
      cursorShape: Qt.PointingHandCursor
      onClicked: root.open = false
    }

    // The stem grows down out of the island first, in the menus' background
    // like the card...
    Rectangle {
      x: popup.stemX - width / 2
      // From the island's bottom, wherever it is while the island grows.
      y: popup.pillHeight - popup.islandInset
      width: popup.stemWidth
      height: (popup.stemLength + popup.islandInset) * root.stemT + (root.bloomT > 0 ? 1 : 0)
      color: Color.menu.background
    }

    // Light trails round the whole shape -- island, stem and card -- as on
    // the SUPER+R frame: two set off both ways from the top of the island as
    // the card opens, two more from the card's bottom middle a moment later.
    // Each runs part-way round with a white head, the accent or red behind
    // it, fading down its tail and glowing inward, then rests and goes again
    // from its start. Staggered cycles so they drift apart; one trail at a
    // time wears a special colour.
    Canvas {
      id: trace
      anchors.fill: parent
      z: 2
      // Settings: "shortcutCardTrails" on/off, "shortcutCardTrailSpeed".
      visible: root.reveal >= 0.3 && root.uiOpt("shortcutCardTrails", true)
      property real t: 0
      property var special: null      // { n, run, color }
      property int specialNext: 0

      FrameAnimation {
        running: popup.visible && trace.visible
        onTriggered: { trace.t += frameTime * root.uiOpt("shortcutCardTrailSpeed", 1); trace.requestPaint() }
      }
      Connections {
        target: root
        function onOpenChanged() { if (root.open) { trace.t = 0; trace.special = null } }
      }

      function mix(a, b, k) {
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1)
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (width <= 0 || height <= 0) return
        // Outline, clockwise from the top middle of the island.
        var ix0 = popup.islandX0, ix1 = popup.islandX1, ir = popup.islandRadius
        var iy = popup.islandInset, ih = popup.pillHeight - popup.islandInset
        var sl = popup.stemX - popup.stemWidth / 2, sr = popup.stemX + popup.stemWidth / 2
        var cx0 = card.x, cy0 = card.y, cx1 = card.x + card.width, cy1 = card.y + card.height
        var cr = card.radius
        var pts = [[(ix0 + ix1) / 2, iy]]
        var bottomAt = 0
        function arc(cx, cy, r, from, to, n) {
          for (var i = 1; i <= n; i++) {
            var a = from + (to - from) * i / n
            pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)])
          }
        }
        pts.push([ix1 - ir, iy]); arc(ix1 - ir, iy + ir, ir, -Math.PI / 2, 0, 8)
        pts.push([ix1, ih - ir]); arc(ix1 - ir, ih - ir, ir, 0, Math.PI / 2, 8)
        pts.push([sr, ih]); pts.push([sr, cy0])
        pts.push([cx1 - cr, cy0]); arc(cx1 - cr, cy0 + cr, cr, -Math.PI / 2, 0, 8)
        pts.push([cx1, cy1 - cr]); arc(cx1 - cr, cy1 - cr, cr, 0, Math.PI / 2, 8)
        pts.push([(cx0 + cx1) / 2, cy1]); bottomAt = pts.length - 1
        pts.push([cx0 + cr, cy1]); arc(cx0 + cr, cy1 - cr, cr, Math.PI / 2, Math.PI, 8)
        pts.push([cx0, cy0 + cr]); arc(cx0 + cr, cy0 + cr, cr, Math.PI, Math.PI * 1.5, 8)
        pts.push([sl, cy0]); pts.push([sl, ih])
        pts.push([ix0 + ir, ih]); arc(ix0 + ir, ih - ir, ir, Math.PI / 2, Math.PI, 8)
        pts.push([ix0, iy + ir]); arc(ix0 + ir, iy + ir, ir, Math.PI, Math.PI * 1.5, 8)
        pts.push(pts[0])
        var cum = [0]
        for (var k = 1; k < pts.length; k++) {
          var ddx = pts[k][0] - pts[k - 1][0], ddy = pts[k][1] - pts[k - 1][1]
          cum.push(cum[k - 1] + Math.sqrt(ddx * ddx + ddy * ddy))
        }
        var P = cum[cum.length - 1]
        function at(d) {
          d = ((d % P) + P) % P
          var i = 1
          while (i < cum.length - 1 && cum[i] < d) i++
          var seg = cum[i] - cum[i - 1], f = seg > 0 ? (d - cum[i - 1]) / seg : 0
          return { x: pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * f, y: pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * f }
        }

        // Everything stays inside the shape: the outer half of each line and
        // all of the glow are clipped off outside it.
        ctx.beginPath()
        ctx.moveTo(pts[0][0], pts[0][1])
        for (var q = 1; q < pts.length; q++) ctx.lineTo(pts[q][0], pts[q][1])
        ctx.closePath()
        ctx.save()
        ctx.clip()
        // Faint outline the trails run along.
        ctx.lineWidth = 2
        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12)
        ctx.stroke()

        var lw = 3
        var list = [
          { s: 0, dir: 1, color: root.traceStart, delay: 0 },
          { s: 0, dir: -1, color: root.traceEnd, delay: 0 },
          { s: cum[bottomAt], dir: 1, color: root.traceEnd, delay: 0.7 },
          { s: cum[bottomAt], dir: -1, color: root.traceStart, delay: 1.1 }
        ]
        var white = Qt.rgba(1, 1, 1, 1)
        var trail = Style.space(150), steps = 30, travel = 2.2
        function runOf(n) {
          var x = t - list[n].delay
          if (x < 0) return { run: -1, local: travel + 1 }
          var cycle = 2.6 + n * 0.29
          return { run: Math.floor(x / cycle), local: x % cycle }
        }
        if (special) {
          var sr2 = runOf(special.n)
          if (sr2.run !== special.run || sr2.local > travel) { special = null; specialNext = (specialNext + 1) % root.traceSpecials.length }
        }
        ctx.lineCap = "round"
        for (var n = 0; n < list.length; n++) {
          var e = list[n], ro = runOf(n), local = ro.local
          if (local > travel) continue
          // The opening pair's first run doesn't take the special colour.
          if (!special && local < 0.12 && !(ro.run === 0 && e.s === 0)) special = { n: n, run: ro.run, color: root.traceSpecials[specialNext] }
          var color = special && special.n === n && special.run === ro.run ? Qt.color(special.color) : e.color
          var kk = local / travel
          var dist = (kk * kk * (3 - 2 * kk)) * P * 0.42
          var fade = Math.min(1, local / 0.2) * Math.min(1, (travel - local) / 0.45)
          var head = e.s + e.dir * dist
          var len = Math.min(trail, dist)
          for (var i = 0; i < steps; i++) {
            var a0 = i / steps, a1 = (i + 1) / steps
            var p0 = at(head - e.dir * a0 * len), p1 = at(head - e.dir * a1 * len)
            var col = i < 2 ? mix(white, color, i / 2) : color
            var alpha = fade * Math.pow(1 - a0, 1.6)
            ctx.lineWidth = lw * 4
            ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, alpha * 0.22)
            ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(p1.x, p1.y); ctx.stroke()
            ctx.lineWidth = lw
            ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, alpha)
            ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(p1.x, p1.y); ctx.stroke()
          }
        }
        ctx.restore()
      }
    }

    // ...then the card blooms out of its tip, widening from the stem and
    // dropping open.
    Rectangle {
      id: card
      readonly property real fromX: popup.stemX - popup.stemWidth / 2
      x: fromX * (1 - root.bloomT)
      y: popup.cardTop
      width: popup.stemWidth + (popup.fullWidth - popup.stemWidth) * root.bloomT
      height: 2 + (popup.cardHeight - 2) * root.outCubic(root.phase(0.2, 0.34))
      radius: Math.min(Style.space(14), height / 2, width / 2)
      color: Color.menu.background
      clip: true
      visible: root.bloomT > 0

      HoverHandler {
        onHoveredChanged: root.setHover("card", hovered)
      }

      Column {
        x: popup.padding
        y: popup.padding
        width: popup.innerWidth
        spacing: popup.rowGap

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          Repeater {
            model: root.topRow
            Tile { index: model.index; entry: modelData }
          }
        }

        Item {
          width: parent.width
          height: popup.tileHeight

          Row {
            anchors.left: parent.left
            Repeater {
              model: root.networkRow
              Tile { index: root.topRow.length + model.index; entry: modelData }
            }
          }

          Row {
            anchors.right: parent.right
            Repeater {
              model: root.folderRow
              Tile { index: root.topRow.length + root.networkRow.length + model.index; entry: modelData }
            }
          }
        }
      }
    }
  }

  // The tiles flip down one after another, each from edge-on to flat
  // with a slight overshoot, top row left to right, then the folders.
  component Tile: Item {
    id: tile
    property int index: 0
    property var entry: ({})
    readonly property real local: {
      return root.phase(0.36 + index * (0.36 / popup.tileCount), 0.28)
    }
    // OutBack, by hand: overshoots past flat and settles.
    readonly property real flip: {
      var s = 1.9, t = local - 1
      return local <= 0 ? 0 : 1 + (s + 1) * t * t * t + s * t * t
    }

    width: popup.tileWidth
    height: popup.tileHeight
    opacity: Math.min(1, local * 3)

    transform: Rotation {
      origin.x: tile.width / 2
      origin.y: 0
      axis { x: 1; y: 0; z: 0 }
      angle: -90 * (1 - tile.flip)
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      radius: Style.space(10)
      color: tileArea.containsMouse ? Util.alpha(root.white, tileArea.pressed ? 0.22 : 0.12) : "transparent"
      Behavior on color { ColorAnimation { duration: 90 } }
    }

    Column {
      anchors.centerIn: parent
      spacing: Style.space(5)

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(Style.font.heading * 1.35)
        height: width

        // Recoloured app favourites with no symbolic icon but a known glyph.
        readonly property bool recolour: root.iconColorMode !== "original" && tile.entry.appIcon !== undefined
        readonly property bool useGlyph: recolour && !tile.entry.symbolic && !!tile.entry.glyph
        readonly property bool useBadge: recolour && !tile.entry.symbolic && !tile.entry.glyph
        Rectangle {
          visible: parent.useBadge
          anchors.fill: parent
          anchors.margins: parent.width * 0.06
          radius: width * 0.28
          color: "transparent"
          border.width: Math.max(1.5, parent.width * 0.07)
          border.color: root.favTint
          Text {
            anchors.centerIn: parent
            text: String(tile.entry.label || "?").charAt(0).toUpperCase()
            color: root.favTint
            font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
            font.pixelSize: parent.height * 0.62
            font.bold: true
          }
        }
        Text {
          visible: parent.useGlyph
          anchors.centerIn: parent
          text: tile.entry.glyph || ""
          color: root.favTint
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: parent.width
        }
        Text {
          visible: !tile.entry.image && tile.entry.appIcon === undefined
          anchors.centerIn: parent
          text: tile.entry.icon || ""
          color: root.builtinTint
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: parent.width
        }
        // Apps added as favourites: their own (colour) icon, or recoloured
        // (symbolic icon if there is one, else the icon flattened) via the
        // overlay below.
        Image {
          id: appImage
          visible: tile.entry.appIcon !== undefined && !parent.recolour
          anchors.fill: parent
          source: tile.entry.appIcon === undefined || parent.useGlyph || parent.useBadge ? ""
            : parent.recolour && tile.entry.symbolic ? tile.entry.symbolic
            : (tile.entry.appIcon.charAt(0) === "/" ? "file://" + tile.entry.appIcon
            : Quickshell.iconPath(tile.entry.appIcon || "application-x-executable", true))
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          smooth: true
          asynchronous: true
        }
        ColorOverlay {
          visible: parent.recolour && !parent.useGlyph && !parent.useBadge
          anchors.fill: appImage
          source: appImage
          color: root.favTint
        }
        // Single-colour #ffffff SVGs, so they're already white.
        Image {
          visible: !!tile.entry.image
          anchors.fill: parent
          source: root.iconSource(tile.entry.image)
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          smooth: true
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.entry.label || ""
        color: root.white
        font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : ""
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: tileArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.launch(tile.entry.command)
    }
  }
}
