import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "MenuModel.js" as MenuModel

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily
    // Easter egg: SUPER + CTRL + ALT + SPACE (~/.config/hypr/bindings.lua) adds "egg".
    root.eggPending = payload.egg === true

    // A list a script is waiting on (SUPER+K) that gets replaced by another
    // menu would leave that script waiting forever; let it go first.
    if (root.requestActive && payload.doneFile !== root.doneFile) root.finishRequest(null)

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
      root.openedAs = "dmenu:" + root.dmenuPrompt
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
      root.openedAs = String(payload.initialMenu || payload.menu || "root")
    }
    // {"menu":"root","apps":true} opens the Go menu on its app panel.
    if (payload.apps === true) Qt.callLater(function() { root.setGoApps(true) })
    if (payload.keys === true) Qt.callLater(function() { root.setGoKeys(true) })
    if (payload.duel === true) Qt.callLater(function() { root.duelOn = true })
  }

  // What the menu was last opened as (a route as requested, or
  // "dmenu:<prompt>"), kept in $XDG_RUNTIME_DIR/omarchy-menu-open while it's
  // up. ~/.local/bin/menu-toggle reads it so a menu key closes its own menu
  // but switches over from any other.
  property string openedAs: ""
  FileView {
    id: openedAsFile
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-menu-open"
    printErrors: false
  }
  function writeOpenedAs() { openedAsFile.setText(root.opened ? root.openedAs : "") }
  onOpenedAsChanged: writeOpenedAs()
  // SUPER+K (menu-toggle go:keys) closes the menu only while the Keybinds
  // panel is what's showing, however it got there (SUPER+K, Tab, a click).
  onGoKeysChanged: {
    if (!root.opened) return
    if (root.goKeys) root.openedAs = "go:keys"
    else if (root.openedAs === "go:keys") root.openedAs = "root"
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  // The menu this opening started at. Back (arrow or Backspace) stops here,
  // so a menu summoned at a submenu never walks up past it.
  property string homeMenu: "root"
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: {
    writeOpenedAs()
    if (!opened) { deleteConfirmOpen = false; deleteTarget = null }
  }
  // Bound to the central [menu] section in shell.toml via Commons.Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property color selectedBorder: Commons.Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  // Side column of shortcuts (folders up top, session actions below) when the
  // menu was opened at its top level: "root" from the desktop Arch button,
  // "tablet" from the tablet bar's.
  readonly property bool showSidebar: !root.dmenuActive && (root.homeMenu === "root" || root.homeMenu === "tablet")
  readonly property int sidebarWidth: Style.space(76)
  // Files: one icon, the Files dropdown (SUPER+E).
  readonly property var sidebarTop: [
    { icon: "󰉋", label: "Files", command: "hyprctl eval 'dropdown_toggle(\"files\")'" }
  ]
  // The shared "guest" account (coworkers using GNS3) gets GNS3, Tailscale and
  // Mullvad only, and the server / phone cards greyed out. Decided here, by
  // user, so it holds whenever guest's copy of this file is refreshed.
  readonly property bool guestMode: Quickshell.env("USER") === "guest"

  // Network group: remote lab over VNC, Remmina, the local GNS3 GUI and the
  // Tailscale / Mullvad toggles. `image` (in icons/) replaces the glyph for
  // apps Nerd Fonts has no icon for; it's recoloured like the glyphs.
  // Mullvad opens the SUPER+M dropdown (status + menu, mullvad-tui). Remmina's
  // own window is a tile on the server card (ServerCard.qml).
  readonly property var sidebarMiddle: root.guestMode ? [
    { icon: "\uf120", label: "Terminal", command: "hyprctl eval 'dropdown_show(\"terminal\")'" },
    { image: "gns3.svg", label: "GNS3", command: "uwsm-app -- ~/.local/bin/gns3" },
    { image: "tailscale.svg", label: "Tailscale", command: "~/.local/bin/tailscale-toggle" },
    { icon: "󰦝", label: "Mullvad VPN", command: "hyprctl eval 'dropdown_toggle(\"vpn\")'" }
  ] : [
    { icon: "\uf120", label: "Terminal", command: "hyprctl eval 'dropdown_show(\"terminal\")'" },
    // Your own remote-desktop button, e.g.
    //   { icon: "󰢹", label: "Lab server", command: "uwsm-app -- remmina -c <profile>" },
    { image: "gns3.svg", label: "GNS3", command: "uwsm-app -- ~/.local/bin/gns3" },
    { image: "tailscale.svg", label: "Tailscale", command: "~/.local/bin/tailscale-toggle" },
    { icon: "󰦝", label: "Mullvad VPN", command: "hyprctl eval 'dropdown_toggle(\"vpn\")'" }
  ]
  readonly property var sidebarBottom: [
    { icon: "󱄄", label: "Screensaver", command: "omarchy-launch-screensaver force" },
    { icon: "󰍃", label: "Log out", command: "omarchy-system-logout" },
    { icon: "󰐥", label: "Shut down", command: "omarchy-system-shutdown" }
  ]
  // The Go menu (homeMenu root) drops the power group from the sidebar and
  // puts Apps / Tablet / System in a row along the bottom instead (kept in
  // every submenu opened from Go, so they stay one click away); those
  // rows (plus About and the lab rows, still searchable) leave its list.
  readonly property bool goLayout: !root.dmenuActive && root.homeMenu === "root"

  // Easter egg (SUPER + CTRL + ALT + SPACE): the Go menu swings in
  // on its hinge near the top-left corner with no brakes. When the bottom-left
  // corner hits the left edge of the screen the hinge snaps, and everything
  // carries on with the momentum it had at that instant: each point was
  // moving along its arc around the hinge, and the corner's hit on the solid
  // left edge kicks all of it back to the right: the card cartwheels right and
  // down, and its contents, which aren't glued on, fly off on their own paths
  // (the further from the hinge, the faster), drifting off the card as it
  // turns, until gravity takes everything off the bottom. Pieces are children of the card, so each one maps
  // its world path back into the card's moving frame (eggPiece).
  property bool eggPending: false
  property bool egging: false
  property bool eggSnapped: false
  property real eggMs: 0                     // ms since the hinge snapped
  readonly property real eggGravity: 2600    // px/s²
  readonly property real eggOmega: 1.9       // rad/s clockwise at the snap (the swing's own speed)
  property real eggTheta0: 0                 // deg, card angle at the snap
  property point eggHinge: Qt.point(0, 0)    // hinge (card top-left) in panel coords
  property size eggCardSize: Qt.size(0, 0)
  signal eggSnap()

  function eggRand(seed) { var x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x) }
  function eggHash(text) { var h = 0; text = String(text || ""); for (var i = 0; i < text.length; i++) h = (h * 31 + text.charCodeAt(i)) % 9973; return h }
  function eggTime() { return root.egging && root.eggSnapped ? root.eggMs / 1000 : 0 }
  // Card-local point -> panel coords at the moment of the snap.
  function eggWorld(p) {
    var a = root.eggTheta0 * Math.PI / 180, c = Math.cos(a), s = Math.sin(a)
    return { x: root.eggHinge.x + c * p.x - s * p.y, y: root.eggHinge.y + s * p.x + c * p.y }
  }
  // Momentum after the snap. The corner's hit on the wall turns the swing
  // into a cartwheel to the right: what was moving into the wall is thrown
  // back off it, so every point heads right and down, faster the further it
  // sat from the hinge (top-left slowest, the right-hand cards fastest).
  function eggVelocity(rx, ry) {
    return { x: root.eggOmega * (0.45 * ry + 0.35 * rx), y: root.eggOmega * 0.8 * rx }
  }
  // The card itself: centre position (panel coords) and angle (deg) t seconds
  // after the snap, plus where its centre was at the snap. It spins on
  // clockwise about its centre (the cartwheel) and never passes the solid
  // left edge of the screen.
  function eggCard(t) {
    var w = root.eggCardSize.width, h = root.eggCardSize.height
    var c0 = eggWorld(Qt.point(w / 2, h / 2))
    var v = eggVelocity(c0.x - root.eggHinge.x, c0.y - root.eggHinge.y)
    var x = c0.x + v.x * t, y = c0.y + v.y * t + 0.5 * root.eggGravity * t * t
    var a = root.eggTheta0 + root.eggOmega * 1.1 * t * 180 / Math.PI
    var r = a * Math.PI / 180, cos = Math.cos(r), sin = Math.sin(r), minX = Infinity
    var corners = [[-w / 2, -h / 2], [w / 2, -h / 2], [-w / 2, h / 2], [w / 2, h / 2]]
    for (var i = 0; i < 4; i++) minX = Math.min(minX, x + cos * corners[i][0] - sin * corners[i][1])
    if (minX < 0) x -= minX
    return { x: x, y: y, a: a, x0: c0.x, y0: c0.y }
  }
  // A piece centred at card-local p: its offset and rotation in the card's
  // (moving) frame, t seconds after the snap. It flies its own path and
  // bounces off the left edge like the card.
  function eggPiece(p, seed) {
    var t = eggTime()
    if (t <= 0) return { x: 0, y: 0, r: 0 }
    var w0 = eggWorld(p)
    var v = eggVelocity(w0.x - root.eggHinge.x, w0.y - root.eggHinge.y)
    var vx = v.x * (0.9 + 0.2 * eggRand(seed)), vy = v.y * (0.9 + 0.2 * eggRand(seed + 1)) - 60 * eggRand(seed + 2)
    var wx = w0.x + vx * t, wy = w0.y + vy * t + 0.5 * root.eggGravity * t * t
    if (wx < 0) wx = -wx * 0.45
    var card = eggCard(t), a = card.a * Math.PI / 180
    var dx = wx - card.x, dy = wy - card.y
    var lx = root.eggCardSize.width / 2 + Math.cos(a) * dx + Math.sin(a) * dy
    var ly = root.eggCardSize.height / 2 - Math.sin(a) * dx + Math.cos(a) * dy
    var spin = (eggRand(seed + 13) - 0.3) * 260 * t
    return { x: lx - p.x, y: ly - p.y, r: root.eggTheta0 + spin - card.a }
  }
  readonly property bool showGoFooter: root.goLayout && !root.filterText
  readonly property int goFooterButtonHeight: Math.round(root.baseRowHeight * 1.5)
  // The lab card (LabCard.qml) and the system card (StatsCard.qml) stack in
  // a column right of the list; the footer runs under both.
  readonly property int labCardHeight: Style.space(110)
  readonly property int statsCardHeight: Style.space(140)
  readonly property bool showGoDash: root.goLayout
  readonly property int goDashWidth: Style.space(250)
  readonly property int goDashGap: Style.space(12)
  readonly property int phoneCardHeight: Style.space(118)
  readonly property int serverCardHeight: Style.space(100)
  readonly property int goDashHeight: root.statsCardHeight + root.labCardHeight + root.serverCardHeight + root.phoneCardHeight + root.contentSpacing * 3
  readonly property int goFooterHeight: root.showGoFooter ? root.goFooterButtonHeight + Math.round(root.contentSpacing * 1.5) : 0
  // Apps panel: the footer's Apps button swaps the Go list and dash for an
  // app grid in the same space ("Go…" stays; Install / Remove / Update sit
  // beside it, the launcher's five categories along the bottom). Typing
  // filters the grid. Categories match daa.launcher (SUPER+R).
  // Touchpad scrolling for the Apps grid and Keybinds list. Qt treats a
  // two-finger scroll as a finger drag: content follows the fingers (the
  // opposite of the rest of the desktop) and there's no momentum, since
  // libinput sends none. This takes over the wheel: fingers down moves the
  // items up, lifting off hands the speed to the view's flick so it coasts,
  // and the view overshoots the ends and springs back (OvershootBounds).
  // Sits on top of the view; clicks pass through to the items.
  component TouchScroll: Item {
    id: touch
    property Flickable view: null
    property real speed: 3.5           // content moves 3.5x the finger travel
    property var samples: []           // recent {t, dy} while fingers move
    // Average speed (contentY px/s) over the recent samples.
    function swipeVelocity() {
      var n = touch.samples.length
      if (n < 2) return 0
      var span = (Date.now() - touch.samples[0].t) / 1000
      if (span <= 0) return 0
      var sum = 0
      for (var i = 0; i < n; i++) sum += touch.samples[i].dy
      return sum / Math.max(span, 0.016)
    }
    property real coastStartedAt: 0
    function startCoast() {
      touch.coastStartedAt = Date.now()
      var vel = touch.swipeVelocity()
      touch.samples = []
      if (Math.abs(vel) > 80 && touch.view) touch.view.flick(0, -vel * 1.7)   // positive = toward the top
    }
    function maxY() { return Math.max(0, touch.view.contentHeight - touch.view.height) + touch.view.originY }
    // A MouseArea that only takes wheel events (no buttons, no hover), so
    // clicks and hovers reach the items underneath. (A WheelHandler here
    // never received the events.)
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      onWheel: function(event) {
        event.accepted = true
        var v = touch.view
        if (!v) return
        var now = Date.now()
        // Zero-movement events mark the start and end of a touchpad scroll.
        // After a swipe (samples recorded) it's the fingers lifting: coast at
        // the swipe's speed. With no swipe in progress it's fingers coming
        // back down: brake, stopping any coast dead.
        // The stop arrives as two zero events back to back, so a zero event
        // within 200 ms of a coast starting is part of that same lift-off.
        if (event.pixelDelta.y === 0 && event.angleDelta.y === 0) {
          coast.stop()
          if (touch.samples.length > 0) touch.startCoast()
          else if ((v.flicking || v.moving) && now - touch.coastStartedAt > 200) v.cancelFlick()
          return
        }
        var dy
        if (event.pixelDelta.y !== 0) {
          dy = -event.pixelDelta.y * touch.speed                 // touchpad
        } else {
          dy = -event.angleDelta.y / 120 * Style.space(90)       // mouse wheel notch
          touch.samples = []
        }
        if (v.flicking) v.cancelFlick()
        var wanted = v.contentY + dy
        v.contentY = Math.max(v.originY, Math.min(touch.maxY(), wanted))
        if (wanted < v.originY - 1) touch.flash(true, 0.5)
        else if (wanted > touch.maxY() + 1) touch.flash(false, 0.5)
        if (event.pixelDelta.y !== 0) {
          // Keep the last ~120 ms of movement to measure the swipe's speed.
          var kept = []
          for (var i = 0; i < touch.samples.length; i++)
            if (now - touch.samples[i].t <= 120) kept.push(touch.samples[i])
          kept.push({ t: now, dy: dy })
          touch.samples = kept
          coast.restart()   // fallback if no stop event arrives
        }
      }
    }
    // GTK-style edge glow: hitting the top or bottom (scrolling into it, or a
    // coast arriving there) flashes a soft accent glow on that edge, which fades.
    property real glowTop: 0
    property real glowBottom: 0
    readonly property color glowColor: Commons.Color.pick("tablet.accent", Commons.Color.accent)
    function flash(top, strength) {
      var g = Math.max(0.35, Math.min(1, strength))
      if (top) { touch.glowTop = Math.max(touch.glowTop, g); fadeTop.restart() }
      else { touch.glowBottom = Math.max(touch.glowBottom, g); fadeBottom.restart() }
    }
    NumberAnimation { id: fadeTop; target: touch; property: "glowTop"; to: 0; duration: 650; easing.type: Easing.OutQuad }
    NumberAnimation { id: fadeBottom; target: touch; property: "glowBottom"; to: 0; duration: 650; easing.type: Easing.OutQuad }
    Connections {
      target: touch.view
      function onAtYBeginningChanged() {
        if (touch.view.atYBeginning && touch.view.flicking) touch.flash(true, Math.abs(touch.view.verticalVelocity) / 3000)
      }
      function onAtYEndChanged() {
        if (touch.view.atYEnd && touch.view.flicking) touch.flash(false, Math.abs(touch.view.verticalVelocity) / 3000)
      }
    }
    Rectangle {
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      height: Style.space(42)
      opacity: touch.glowTop
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(touch.glowColor.r, touch.glowColor.g, touch.glowColor.b, 0.38) }
        GradientStop { position: 1.0; color: Qt.rgba(touch.glowColor.r, touch.glowColor.g, touch.glowColor.b, 0) }
      }
    }
    Rectangle {
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      height: Style.space(42)
      opacity: touch.glowBottom
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(touch.glowColor.r, touch.glowColor.g, touch.glowColor.b, 0) }
        GradientStop { position: 1.0; color: Qt.rgba(touch.glowColor.r, touch.glowColor.g, touch.glowColor.b, 0.38) }
      }
    }

    // Fingers lifted (no events for 60 ms): coast at the last speed.
    Timer {
      id: coast
      interval: 80
      onTriggered: touch.startCoast()
    }
  }

  // Slinky sidebar clock (ms since the Go menu opened; -1 = at rest).
  property real slinkMs: -1
  function slinkOffset(ratio) {
    if (root.slinkMs < 0) return 0
    var t = root.slinkMs - 80 - ratio * 180
    if (t <= 0) return 0
    var amp = Style.space(6) + ratio * Style.space(56)
    return amp * Math.exp(-t / 380) * Math.sin(2 * Math.PI * t / 720)
  }

  // Easter egg: two stick figures sword fighting under "Update" in the Go
  // list. Shows on about 1 in 12 openings, or when "omarchy!" is typed (plain
  // "omarchy" is a real search: it finds Omarchy's own page).
  property bool duelOn: false
  // ABACABB blood mode (daa.search) is on: the accent is its coral. Then the
  // duel always shows and ends after 3 s in a (bloodless) beheading.
  readonly property bool bloodMode: Qt.colorEqual(Commons.Color.accent, "#e0607a")

  property bool goApps: false
  // Keybinds panel (footer Keybinds): the SUPER+K list, smaller, in the same
  // space. goPanel = either panel is up (the Go list and dash hide).
  property bool goKeys: false
  readonly property bool goPanel: root.goApps || root.goKeys
  property var allKeys: []
  ListModel { id: keysModel }
  Process {
    id: keysProc
    command: ["omarchy-menu-keybindings", "--print"]
    property var lines: []
    stdout: SplitParser {
      onRead: function(line) { keysProc.lines.push(line) }
    }
    onStarted: lines = []
    onExited: {
      var rows = []
      for (var i = 0; i < lines.length; i++) {
        var parts = String(lines[i]).split("→")
        if (parts.length < 2) continue
        rows.push({ keys: parts[0].trim(), desc: parts.slice(1).join("→").trim(), line: String(lines[i]) })
      }
      root.allKeys = rows
      root.rebuildKeys()
    }
  }
  function rebuildKeys() {
    keysModel.clear()
    var q = String(root.filterText || "").trim().toLowerCase()
    for (var i = 0; i < root.allKeys.length; i++) {
      var row = root.allKeys[i]
      if (q && (row.keys + " " + row.desc).toLowerCase().indexOf(q) === -1) continue
      keysModel.append(row)
    }
  }
  function setGoKeys(on) {
    root.goKeys = on
    root.footFocus = -1   // focusFooter() sets it again after calling this
    if (on) {
      root.goApps = false
      root.filterText = ""
      if (!keysProc.running) keysProc.running = true
    }
  }
  function closeGoPanel() {
    if (root.goApps) root.setGoApps(false)
    if (root.goKeys) root.setGoKeys(false)
  }
  property string appsCategory: ""
  // "" = All, lit whenever no category is picked (e.g. when the panel opens).
  readonly property var appsCategoryTabs: [
    { id: "", label: "All" },
    { id: "web", label: "Web" },
    { id: "utility", label: "Utility" },
    { id: "create", label: "Create" },
    { id: "communicate", label: "Communicate" },
    { id: "entertain", label: "Entertain" }
  ]
  readonly property var appsCategoryOrder: ["communicate", "entertain", "create", "web"]
  readonly property var appsCategoryMap: ({
    communicate: ["Chat", "InstantMessaging", "Email", "Telephony", "VideoConference", "IRCClient", "ContactManagement"],
    entertain: ["Game", "Player", "Music", "TV", "Amusement", "Emulator"],
    create: ["Graphics", "AudioVideoEditing", "Recorder", "Office", "Development", "TextEditor", "IDE"],
    web: ["WebBrowser", "Network", "RemoteAccess"]
  })
  readonly property var appsCategoryOverrides: ({
    "Zoom": "communicate", "Basecamp": "communicate", "Kindle": "entertain",
    "info.febvre.Komikku": "entertain", "com.github.johnfactotum.Foliate": "entertain",
    "gns3": "utility", "org.wireshark.Wireshark": "utility", "localsend": "utility",
    "mullvad-vpn": "utility"
  })
  function appsCategoryOf(entry) {
    var id = String(entry.id || "")
    if (root.appsCategoryOverrides[id]) return root.appsCategoryOverrides[id]
    var cats = entry.categories || []
    for (var i = 0; i < root.appsCategoryOrder.length; i++) {
      var wanted = root.appsCategoryMap[root.appsCategoryOrder[i]]
      for (var j = 0; j < cats.length; j++)
        if (wanted.indexOf(String(cats[j])) !== -1) return root.appsCategoryOrder[i]
    }
    return "utility"
  }
  ListModel { id: appsModel }
  // Hidden like the SUPER+R launcher: Omarchy's launcher.hides list plus the
  // entries this desktop session hides (hidden-entries.sh).
  property var appsHidden: ({})
  property var appsSessionHidden: ({})
  function appsIdSet(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim()
      if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
      if (id.length > 0) next[id] = true
    }
    return next
  }
  FileView {
    path: Quickshell.env("OMARCHY_PATH") + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.appsHidden = root.appsIdSet(text())
    onFileChanged: reload()
  }
  Process {
    id: appsHiddenScan
    property string output: ""
    running: true
    command: ["bash", "-c", Util.shellQuote(Quickshell.env("OMARCHY_PATH") + "/shell/services/hidden-entries.sh") + " "
      + Util.shellQuote([Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")]
        .filter(function(v) { return String(v || "").length > 0 }).join(":"))]
    stdout: SplitParser { onRead: function(line) { appsHiddenScan.output += line + "\n" } }
    onStarted: output = ""
    onExited: root.appsSessionHidden = root.appsIdSet(output)
  }
  // The Go menu isn't handed the shell's app library (only the launcher is),
  // so this reads the desktop entries directly, like the launcher's fallback.
  function rebuildApps() {
    appsModel.clear()
    var q = String(root.filterText || "").trim().toLowerCase()
    var values = DesktopEntries.applications.values || []
    var rows = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay || !entry.name || !entry.id) continue
      if (root.appsHidden[String(entry.id)] || root.appsSessionHidden[String(entry.id)]) continue
      if (root.appsCategory && root.appsCategoryOf(entry) !== root.appsCategory) continue
      var name = String(entry.name)
      var lower = name.toLowerCase()
      var rank = 0
      if (q) {
        if (lower.indexOf(q) === 0) rank = 0
        else if (lower.indexOf(q) !== -1) rank = 1
        else if (String(entry.genericName || "").toLowerCase().indexOf(q) !== -1) rank = 2
        else continue
      }
      rows.push({ id: String(entry.id), name: name, icon: String(entry.icon || ""), rank: rank, key: lower })
    }
    rows.sort(function(a, b) {
      if (a.rank !== b.rank) return a.rank - b.rank
      return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0)
    })
    for (var j = 0; j < rows.length; j++)
      appsModel.append({ appId: rows[j].id, label: rows[j].name, appIcon: rows[j].icon })
  }
  function appIconSource(icon) {
    var value = String(icon || "")
    if (value.charAt(0) === "/") return "file://" + value
    var themed = value ? Quickshell.iconPath(value, true) : ""
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }
  function setGoApps(on) {
    root.goApps = on
    if (on) root.goKeys = false
    root.footFocus = -1   // focusFooter() sets it again after calling this
    root.appsCategory = ""
    if (on) { root.filterText = ""; root.rebuildApps() }
  }
  function launchApp(appId, label) {
    root.cancel()
    if (root.appLibrary) root.appLibrary.launch(appId, label)
    else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", appId + ".desktop"])
  }
  onFilterTextChanged: {
    if (root.goLayout && String(root.filterText).toLowerCase() === "omarchy!") {
      root.duelOn = true
      Qt.callLater(function() { root.setFilter("") })
      return
    }
    if (root.goApps) root.rebuildApps()
    if (root.goKeys) root.rebuildKeys()
    if (root.filterText && root.footFocus >= 0 && !root.goPanel) root.footFocus = -1
  }

  // Tab walks the footer: Go list -> Apps -> Keybinds -> Tablet -> System ->
  // back to the Go list (Shift+Tab reverses). Buttons that open
  // inside the Go menu (Apps panel, Tablet / System submenus) open as soon as
  // Tab lands on them; the ones that open a window (Terminal, Keybinds) only
  // highlight, and Enter or Space runs them. -1 = no footer button focused.
  property int footFocus: -1
  function stepFooter(step) {
    if (!root.goLayout) return false
    var n = root.goFooterItems.length
    // -1 (the Go list) sits between the last and the first button.
    var next = root.footFocus + step
    if (next >= n) next = -1
    else if (next < -1) next = n - 1
    root.focusFooter(next)
    return true
  }
  function focusFooter(index) {
    var item = index >= 0 ? root.goFooterItems[index] : null
    if (item && item.apps) {
      if (root.activeMenu !== "root") root.setActiveMenu("root", false)
      root.setGoApps(true)
    } else if (item && item.keys) {
      if (root.activeMenu !== "root") root.setActiveMenu("root", false)
      root.setGoKeys(true)
    } else if (item && item.target) {
      root.setActiveMenu(item.target, false)
    } else {
      // The Go list itself, or a window-opening button: show the Go list.
      if (root.activeMenu !== "root") root.setActiveMenu("root", false)
      root.closeGoPanel()
    }
    root.footFocus = index
  }
  // Enter / Space on a window-opening button runs it.
  function runFocusedFooter() {
    var item = root.footFocus >= 0 ? root.goFooterItems[root.footFocus] : null
    if (!item || !item.command || item.apps || item.keys || item.target) return false
    root.cancel()
    root.runAction(item.command)
    return true
  }

  readonly property var goFooterItems: [
    { icon: "󰀻", label: "Apps", apps: true },
    // Right click opens the keybindings file in Sublime Text.
    { icon: "󰌌", label: "Keybinds", keys: true,
      rightCommand: "uwsm-app -- subl ~/.config/hypr/bindings.lua" },
    { icon: "󰓶", label: "Tablet", target: "tablet" },
    { icon: "󰐥", label: "System", target: "system" }
  ]
  readonly property var goHiddenRows: ["apps", "tablet", "system", "about"]
  // The Go menu sits at the left screen edge, so its sidebar goes on the
  // left; the tablet menu (beside the right-hand tablet bar) keeps it right.
  readonly property bool sidebarLeft: root.goLayout
  readonly property int sidebarLabelHeight: Style.font.body + Style.space(8)

  // The keybindings list takes the Bitwarden dropdown's 600x720 frame.
  property int cardWidth: panel.midScreen ? 600 : Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(Math.max(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight + goFooterHeight,
        root.showSidebar ? root.sidebarMinHeight : 0,
        root.showGoDash ? contentMargin * 2 + goDashHeight + goFooterHeight : 0), panel.height - Style.gapsOut * 2)
  // Tall enough for the sidebar's labelled groups, so a search that leaves
  // only a row or two doesn't squash them together. The sidebar runs the
  // full height of the card, beside the Go footer rather than above it.
  readonly property int sidebarButtonCount: sidebarTop.length + (goLayout ? sidebarMiddle.length : sidebarBottom.length)
  readonly property int sidebarMinHeight: contentMargin * 2 + sidebarLabelHeight * (goLayout ? 2 : 1)
    + sidebarButtonCount * (sidebarWidth - Style.space(12))
    + sidebarButtonCount * Style.space(6) + Style.space(goLayout ? 24 : 48)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  // Reloads the open menu's provider rows, e.g. after a row's ✕ closed a window.
  Timer {
    id: providerRefresh
    interval: 450
    onTriggered: {
      root.invalidateVolatileProvider(root.activeMenu)
      root.loadProviderForMenu(root.activeMenu)
    }
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing - root.goFooterHeight
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (panel.midScreen) return 720 - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    // Tablet bar workspace menu (~/.local/bin/tablet-mode workspaces): "Hide
    // scratchpad" while one shows, the current workspace's windows
    // ("win:ADDRESS", tap to focus, ✕ to close), then the workspaces.
    "workspaces": {
      script: "~/.local/bin/tablet-mode workspaces",
      icon: "󰍹",
      volatile: true,
      iconFor: function(value) { return value === "hide" ? "󰘕" : value.indexOf("win:") === 0 ? "󰖯" : "󰍹" },
      actionFor: function(value) {
        if (value === "hide") return "~/.local/bin/tablet-mode hide-scratchpads"
        return value.indexOf("win:") === 0
          ? "~/.local/bin/tablet-mode window focus " + Util.shellQuote(value.slice(4))
          : "~/.local/bin/tablet-mode workspace " + Util.shellQuote(value)
      },
      closeFor: function(value) {
        return value.indexOf("win:") === 0 ? "~/.local/bin/tablet-mode window close " + Util.shellQuote(value.slice(4)) : ""
      }
    },
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      // power-refresh adds less-balanced (balanced at 120 Hz) and ties each
      // profile to a refresh rate.
      script: "current=$(power-refresh list --active-state 2>/dev/null | awk -F'\\t' '$2 == 1 { print $1 }'); power-refresh list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "power-refresh set " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  // The Go menu isn't handed the AppLibrary (root.appLibrary is null), so
  // without it the rows come straight from DesktopEntries, minus the same
  // hidden entries as the Apps panel (appsHidden / appsSessionHidden).
  function mergeAppRows() {
    var rows = []
    if (root.appLibrary) {
      rows = root.appLibrary.sortedEntries("")
    } else {
      var values = DesktopEntries.applications.values || []
      for (var v = 0; v < values.length; v++) {
        var desktop = values[v]
        if (!desktop || desktop.noDisplay || !desktop.name || !desktop.id) continue
        if (root.appsHidden[String(desktop.id)] || root.appsSessionHidden[String(desktop.id)]) continue
        rows.push({ entry: desktop })
      }
    }
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary ? root.appLibrary.entrySubtext(entry) : String(entry.genericName || entry.comment || "")
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary ? root.appLibrary.entryName(entry) : String(entry.name),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.iconFor ? spec.iconFor(value) : (spec.icon || "")),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        closeAction: spec.closeFor ? spec.closeFor(value) : "",
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        closeAction: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        // An installed app whose name matches goes in the top section, so
        // typing "fire" offers Firefox itself before Setup > Defaults etc.
        if (entry.parent === active || (entry.kind === "app" && String(entry.label).toLowerCase().indexOf(query.toLowerCase()) >= 0)) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)

      // Typing in the top-level menu also offers a whole-drive file search,
      // opening the Catfish dropdown (SUPER+D) already searching.
      if (active === "root") {
        rows.push({
          itemId: "daa.file-search",
          kind: "action",
          icon: "\uf002",
          iconFont: "",
          appIcon: "",
          appId: "",
          label: "\u201c" + query + "\u201d",
          target: "daa.file-search",
          detail: "Search all files",
          path: "",
          childCount: 0,
          action: Quickshell.env("HOME") + "/.local/bin/file-search " + Util.shellQuote(query),
          closeAction: "",
          provider: "",
          score: 0,
          section: rows.length > 0 ? "drilldown" : ""
        })
      }
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (active === "root" && root.goLayout && root.goHiddenRows.indexOf(child.id) >= 0) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    root.goApps = false
    root.goKeys = false
    root.footFocus = -1   // focusFooter() sets it again after calling this
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root" || root.activeMenu === root.homeMenu) return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
      else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", appId + ".desktop"])
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    homeMenu = activeMenu
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }
  // The DesktopEntries fallback (no AppLibrary) refreshes on its own changes.
  Connections {
    target: root.appLibrary ? null : DesktopEntries.applications
    function onValuesChanged() { if (root.providersLoaded["apps"]) root.mergeAppRows() }
  }
  onAppsHiddenChanged: if (!root.appLibrary && root.providersLoaded["apps"]) root.mergeAppRows()
  onAppsSessionHiddenChanged: if (!root.appLibrary && root.providersLoaded["apps"]) root.mergeAppRows()

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The card opens centered exactly as always. The first search keystroke
    // or submenu move freezes the top line where it currently sits — from
    // then on the card grows and shrinks downward instead of re-centering
    // on every resize, which made the menu jump around. The rows height is
    // frozen at the same moment, so the starting menu also caps how tall the
    // card may grow from there. Closing unfreezes both.
    property int cardTop: -1
    property int maxRowsHeight: -1
    // The card opens against the bar instead of mid-screen: just below a top
    // bar, just above a bottom one, beside a side bar (centred along it).
    // Read from shell.json directly: the scoped shell API plugins get only
    // carries a snapshot of the bar config from startup.
    property string barEdge: "top"
    FileView {
      path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoaded: {
        try {
          var bar = JSON.parse(text() || "{}").bar || {}
          panel.barEdge = String(bar.position || "top")
        } catch (e) {}
      }
    }
    readonly property bool barVertical: barEdge === "left" || barEdge === "right"
    readonly property int barThickness: barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal + Style.space(4)

    // Tablet mode (~/.local/bin/tablet-mode) adds a touch scroll rail beside
    // lists too long to fit.
    property bool tabletOn: false
    FileView {
      path: Quickshell.env("HOME") + "/.local/state/tablet-mode/state"
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoaded: panel.tabletOn = String(text() || "").trim() === "on"
    }
    // The keybindings list (SUPER+K) hangs off the upper left corner
    // instead, borderless, the Bitwarden dropdown's size mirrored: 10px from
    // the left edge, 50px down, sliding in from the left edge.
    readonly property bool midScreen: root.dmenuActive && root.dmenuPrompt === "Keybindings"
    // The system (shutdown) menu sits in the bottom left corner instead,
    // sliding in from the left edge.
    readonly property bool systemMenu: !root.dmenuActive && root.homeMenu === "system"
    readonly property int centeredTop: midScreen ? 50
      : systemMenu ? Math.max(Style.gapsOut, height - 10 - root.cardHeight)
      : barEdge === "top" ? barThickness + Style.gapsOut
      : barEdge === "bottom" ? Math.max(Style.gapsOut, height - barThickness - Style.gapsOut - root.cardHeight)
      : Math.max(Style.gapsOut, Math.round((height - root.cardHeight) / 2))
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
    function freezeCardTop() {
      // Above a bottom bar the card must keep growing upward, so never freeze.
      if (barEdge === "bottom" || systemMenu) return
      if (visible && cardTop < 0) {
        cardTop = effectiveCardTop
        maxRowsHeight = root.visibleRowsHeight
      }
    }
    onVisibleChanged: {
      if (!visible) { cardTop = -1; maxRowsHeight = -1; root.goApps = false; root.goKeys = false; root.footFocus = -1; root.duelOn = false; return }
      if (midScreen || systemMenu) slideIn.begin()
      else card.slide = 0
      if (root.goLayout && root.eggPending) { root.eggPending = false; eggAnim.restart() }
      else if (root.goLayout) { swingIn.restart(); goDash.bounceIn(); goFooter.deal(); slinkAnim.restart(); root.duelOn = root.bloodMode || Math.random() < 1 / 12 }
      else card.swing = 1
    }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      // Easter egg: the dimming lifts as everything falls away.
      opacity: root.egging && root.eggSnapped ? Math.max(0, 1 - root.eggMs / 900) : 1
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    BorderSurface {
      id: card
      width: root.cardWidth + (root.showSidebar ? root.sidebarWidth : 0) + (root.showGoDash ? root.goDashWidth + root.goDashGap : 0)
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      radius: root.cornerRadius
      // The Go menu (opened at "root" from the desktop Arch button) sits near
      // the left edge under that button, borderless; other menus centre
      // along the bar.
      // In tablet mode the scroll rail goes on the side nearer the screen
      // edge (the bar side when the bar is vertical), where the thumb is, and
      // the card moves over to make room for it.
      readonly property real baseX: panel.barEdge === "left" ? panel.barThickness + Style.gapsOut
        : panel.barEdge === "right" ? panel.width - panel.barThickness - Style.gapsOut - width
        : panel.midScreen || panel.systemMenu ? 10
        : root.homeMenu === "root" && !panel.midScreen ? Style.gapsOut + 20
        : Math.round((panel.width - width) / 2)
      readonly property bool railLeft: panel.barEdge === "left"
        || (!panel.barVertical && baseX + width / 2 < panel.width / 2 - 1)
      readonly property real railSpace: rail.visible ? rail.width + Style.space(8) : 0
      x: baseX + (railLeft ? railSpace : panel.barEdge === "right" ? -railSpace : 0)
      y: panel.effectiveCardTop
      // 1 = pushed fully off the left edge (right edge for other menus);
      // slideIn eases it to 0.
      property real slide: 0
      // The Go menu swings down out of the Arch button like a hinged sign:
      // pivoting on its top-left corner it rotates down from -16° while it
      // unfolds from 55% height, overshooting a touch before it settles.
      property real swing: 1
      opacity: Math.min(1, swing * 2.5)
      // Easter egg: eggTilt carries the swing on past rest until the bottom-left
      // corner meets the screen edge; then the hinge snaps and eggNow (from
      // root.eggCard) spins the card about its centre and moves it.
      property real eggTilt: 0
      readonly property real eggHitAngle: Math.asin(Math.min(1, card.x / Math.max(1, card.height))) * 180 / Math.PI
      readonly property var eggNow: root.eggTime() > 0 ? root.eggCard(root.eggTime()) : null
      transform: [
        Rotation {
          origin.x: card.width / 2
          origin.y: card.height / 2
          angle: card.eggNow ? card.eggNow.a - root.eggTheta0 : 0
        },
        Translate { x: card.slide * (panel.systemMenu || panel.midScreen ? -(card.x + card.width) : panel.width - card.x) },
        Scale { origin.x: 0; origin.y: 0; xScale: 0.92 + 0.08 * card.swing; yScale: 0.55 + 0.45 * card.swing },
        Rotation { origin.x: 0; origin.y: 0; angle: (card.swing - 1) * 16 + card.eggTilt },
        Translate {
          x: card.eggNow ? card.eggNow.x - card.eggNow.x0 : 0
          y: card.eggNow ? card.eggNow.y - card.eggNow.y0 : 0
        }
      ]

      // Backstop: whatever happens to the animation, the menu is closed and
      // back to normal 3s after the easter egg starts.
      Timer {
        id: eggGuard
        interval: 3000
        onTriggered: if (root.egging) {
          eggAnim.stop()
          root.cancel()
          root.egging = false; root.eggSnapped = false; root.eggMs = 0; card.eggTilt = 0
        }
      }

      SequentialAnimation {
        id: eggAnim
        ScriptAction { script: {
          root.egging = true; root.eggSnapped = false; root.eggMs = 0; card.eggTilt = 0
          eggGuard.restart()
          labCard.shove = 0; statsCard.shove = 0; serverCard.shove = 0; phoneCard.shove = 0
          labCard.opacity = 1; statsCard.opacity = 1; serverCard.opacity = 1; phoneCard.opacity = 1
          goFooter.dealClock = 1
        } }
        // Swing in on the hinge with no brakes (ends at ~1.9 rad/s)...
        NumberAnimation { target: card; property: "swing"; from: 0; to: 1; duration: 300; easing.type: Easing.InQuad }
        // ...on past rest at the same speed until the corner meets the edge...
        NumberAnimation { target: card; property: "eggTilt"; to: card.eggHitAngle; duration: Math.max(16, card.eggHitAngle / 107 * 1000) }
        // ...where the hinge snaps.
        ScriptAction { script: {
          root.eggTheta0 = card.eggTilt
          root.eggHinge = Qt.point(card.x, card.y)
          root.eggCardSize = Qt.size(card.width, card.height)
          root.eggSnap()
          root.eggSnapped = true
        } }
        NumberAnimation { target: root; property: "eggMs"; from: 0; to: 1250; duration: 1250 }
        ScriptAction { script: root.cancel() }
        ScriptAction { script: { root.egging = false; root.eggSnapped = false; root.eggMs = 0; card.eggTilt = 0 } }
      }
      // Slinky: as the Go menu swings in, the sidebar sags and springs back.
      // Each item's dip is a damped spring whose size and start grow with
      // how far down the sidebar it sits (ratio 0 = top, 1 = bottom), so the
      // bottom drops furthest and a beat later, like a slinky settling.
      NumberAnimation {
        id: slinkAnim
        target: root
        property: "slinkMs"
        from: 0
        to: 1900
        duration: 1900
        onStopped: root.slinkMs = -1
      }
      NumberAnimation on swing {
        id: swingIn
        running: false
        from: 0
        to: 1
        duration: 480
        easing.type: Easing.OutBack
        easing.overshoot: 1.3
      }
      // daa: stepped per rendered frame (at most 1/60 s each) instead of by
      // wall clock, so a busy first frame -- the surface mapping, the list
      // building -- delays the slide rather than skipping part of it.
      FrameAnimation {
        id: slideIn
        property real t: 0
        function begin() { t = 0; card.slide = 1; start() }
        onTriggered: {
          t = Math.min(1, t + Math.min(frameTime, 1 / 60) / 0.32)
          card.slide = Math.pow(1 - t, 5)   // OutQuint
          if (t >= 1) stop()
        }
      }
      color: root.background
      // The Go menu, the system (shutdown) menu and the keybindings list are borderless.
      borderSpec: (root.homeMenu === "root" || root.homeMenu === "system" || panel.midScreen) ? Border.none() : root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          // Easter egg: keys pressed mid-fall mustn't type into the search.
          if (root.egging) { event.accepted = true; return }
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && root.goLayout) {
            var back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
            if (root.filterText) root.setFilter("")
            root.stepFooter(back ? -1 : 1)
            event.accepted = true
            return
          }
          if (root.footFocus >= 0 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
              && root.runFocusedFooter()) {
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.goPanel) root.closeGoPanel()
            else root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (root.goApps && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            // Enter in the app panel opens the first app shown.
            if (appsModel.count > 0) root.launchApp(appsModel.get(0).appId, appsModel.get(0).label)
            event.accepted = true
          } else if (root.goPanel && event.key === Qt.Key_Backspace && !root.filterText) {
            root.closeGoPanel()
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      Item {
        id: sidebar
        visible: root.showSidebar
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        x: root.sidebarLeft ? card.contentLeftInset : card.width - card.contentRightInset - width
        width: root.sidebarWidth

        Rectangle {
          x: root.sidebarLeft ? parent.width - width : 0
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.spacing.hairline
          color: Util.alpha(root.foreground, 0.2)
        }

        // Files (folders) on top, then the Network group (VNC, Remmina, GNS3, Tailscale, Mullvad).
        Column {
          anchors.top: parent.top
          x: root.sidebarLeft ? 0 : Style.space(12)
          spacing: Style.space(6)
          Text { text: "Files"; width: root.sidebarWidth - Style.space(12); height: root.sidebarLabelHeight; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: root.foreground; opacity: 0.58; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          Repeater { model: root.sidebarTop; delegate: sidebarButton }
          // Network (VNC, Remmina, GNS3, Tailscale, Mullvad) is desktop-only: not in the tablet menu.
          Item { visible: root.goLayout; width: 1; height: Style.space(12) }
          Text { visible: root.goLayout; text: "Network"; width: root.sidebarWidth - Style.space(12); height: root.sidebarLabelHeight; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: root.foreground; opacity: 0.58; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          Repeater { model: root.goLayout ? root.sidebarMiddle : []; delegate: sidebarButton }
        }

        // The tablet menu keeps its power group; the Go menu has System in
        // its bottom row instead.
        Column {
          visible: !root.goLayout
          anchors.bottom: parent.bottom
          x: root.sidebarLeft ? 0 : Style.space(12)
          spacing: Style.space(6)
          Repeater { model: root.sidebarBottom; delegate: sidebarButton }
        }

        Component {
          id: sidebarButton

          Rectangle {
            id: sideButton
            required property var modelData
            property point eggP: Qt.point(0, 0)
            readonly property var eggOff: root.eggPiece(sideButton.eggP, 300 + root.eggHash(sideButton.modelData.label))
            Connections {
              target: root
              function onEggSnap() { sideButton.eggP = sideButton.mapToItem(card, sideButton.width / 2, sideButton.height / 2) }
            }
            readonly property real slinkRatio: parent ? (sideButton.y + sideButton.height / 2) / Math.max(1, parent.height) : 0
            transform: [
              Rotation { origin.x: sideButton.width / 2; origin.y: sideButton.height / 2; angle: sideButton.eggOff.r },
              Translate { x: sideButton.eggOff.x; y: sideButton.eggOff.y },
              Translate { y: root.slinkOffset(sideButton.slinkRatio) }
            ]
            width: root.sidebarWidth - Style.space(12)
            height: width
            radius: root.cornerRadius
            color: sideArea.pressed || sideArea.containsMouse ? root.selectedBackground : "transparent"

            readonly property color iconColor: sideArea.pressed || sideArea.containsMouse ? root.selectedText : root.foreground
            readonly property int iconSize: Math.round(Style.font.heading * 1.35)

            Text {
              visible: !sideButton.modelData.image
              anchors.centerIn: parent
              text: sideButton.modelData.icon || ""
              color: sideButton.iconColor
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: sideButton.iconSize
            }

            // Image icons are single-colour SVGs (#ffffff) recoloured to the
            // glyph colour, so they follow the theme like the Nerd Font icons.
            FileView {
              id: sideSvg
              path: sideButton.modelData.image ? Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.menu/icons/" + sideButton.modelData.image : ""
              printErrors: false
            }
            Image {
              visible: !!sideButton.modelData.image
              anchors.centerIn: parent
              width: sideButton.iconSize
              height: sideButton.iconSize
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              fillMode: Image.PreserveAspectFit
              smooth: true
              source: sideButton.modelData.image && sideSvg.loaded
                ? "data:image/svg+xml;charset=utf-8," + encodeURIComponent(sideSvg.text().replace(/#ffffff/g, String(sideButton.iconColor)))
                : ""
            }

            PanelToolTip {
              visible: sideArea.containsMouse
              text: sideButton.modelData.label
              x: root.sidebarLeft ? sideButton.width + Style.space(10) : -implicitWidth - Style.space(10)
              y: Math.round((sideButton.height - implicitHeight) / 2)
            }

            MouseArea {
              id: sideArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.cancel()
                root.runAction(sideButton.modelData.command)
              }
            }
          }
        }
      }

      // Go menu dash, right of the list: the lab card (lab ping + sparkline,
      // GNS3 / Tailscale / Mullvad; click = VNC) over the system card (CPU /
      // RAM / disk / temp; click = btop). Trails the card's swing-in a beat.
      Column {
        id: goDash
        visible: root.showGoDash && !root.goPanel
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        width: root.goDashWidth
        spacing: root.contentSpacing

        // Momentum: as the menu swings down the cards slide right, hit the
        // menu's right wall and bounce off it before they settle (OutBounce
        // treats the end value as the wall). Each card hangs further from the
        // hinge than the one above, so they land top to bottom.
        function bounceIn() { statsBounce.restart(); labBounce.restart(); serverBounce.restart(); phoneBounce.restart() }

        SequentialAnimation {
          id: serverBounce
          PropertyAction { target: serverCard; property: "shove"; value: -Style.space(135) }
          PropertyAction { target: serverCard; property: "opacity"; value: 0 }
          PauseAnimation { duration: 180 }
          ParallelAnimation {
            NumberAnimation { target: serverCard; property: "shove"; to: 0; duration: 790; easing.type: Easing.OutBounce }
            NumberAnimation { target: serverCard; property: "opacity"; to: 1; duration: 160 }
          }
        }

        SequentialAnimation {
          id: phoneBounce
          PropertyAction { target: phoneCard; property: "shove"; value: -Style.space(160) }
          PropertyAction { target: phoneCard; property: "opacity"; value: 0 }
          PauseAnimation { duration: 240 }
          ParallelAnimation {
            NumberAnimation { target: phoneCard; property: "shove"; to: 0; duration: 840; easing.type: Easing.OutBounce }
            NumberAnimation { target: phoneCard; property: "opacity"; to: 1; duration: 160 }
          }
        }

        SequentialAnimation {
          id: labBounce
          PropertyAction { target: labCard; property: "shove"; value: -Style.space(110) }
          PropertyAction { target: labCard; property: "opacity"; value: 0 }
          PauseAnimation { duration: 120 }
          ParallelAnimation {
            NumberAnimation { target: labCard; property: "shove"; to: 0; duration: 740; easing.type: Easing.OutBounce }
            NumberAnimation { target: labCard; property: "opacity"; to: 1; duration: 160 }
          }
        }

        SequentialAnimation {
          id: statsBounce
          PropertyAction { target: statsCard; property: "shove"; value: -Style.space(90) }
          PropertyAction { target: statsCard; property: "opacity"; value: 0 }
          PauseAnimation { duration: 60 }
          ParallelAnimation {
            NumberAnimation { target: statsCard; property: "shove"; to: 0; duration: 700; easing.type: Easing.OutBounce }
            NumberAnimation { target: statsCard; property: "opacity"; to: 1; duration: 160 }
          }
        }

        Loader {
          id: statsCard
          active: root.showGoDash
          width: parent.width
          property real shove: 0
          property point eggP: Qt.point(0, 0)
          readonly property var eggOff: root.eggPiece(statsCard.eggP, 401)
          Connections {
            target: root
            function onEggSnap() { statsCard.eggP = statsCard.mapToItem(card, statsCard.width / 2, statsCard.height / 2) }
          }
          transform: [
            Rotation { origin.x: statsCard.width / 2; origin.y: statsCard.height / 2; angle: statsCard.eggOff.r },
            Translate { x: statsCard.eggOff.x; y: statsCard.eggOff.y },
            Translate { x: statsCard.shove }
          ]
          height: root.statsCardHeight
          source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.menu/StatsCard.qml"
          onLoaded: {
            item.active = Qt.binding(function() { return root.opened && root.showGoDash })
            item.foreground = Qt.binding(function() { return root.foreground })
            item.hoverBackground = Qt.binding(function() { return root.selectedBackground })
            item.fontFamily = Qt.binding(function() { return root.fontFamily })
            item.radius = Qt.binding(function() { return root.cornerRadius })
          }
          Connections {
            target: statsCard.item
            function onClicked() {
              root.cancel()
              root.runAction("hyprctl clients -j | jq -e 'any(.[]; .class == \"dropdown.btop\")' >/dev/null"
                + " || { uwsm-app -- alacritty --class dropdown.btop -e btop & }; "
                + "hyprctl dispatch 'hl.dsp.workspace.toggle_special(\"dropdown-btop\")'")
            }
          }
        }

        Loader {
          id: labCard
          // Always loaded so it keeps sampling pings while the menu is closed.
          active: true
          width: parent.width
          property real shove: 0
          property point eggP: Qt.point(0, 0)
          readonly property var eggOff: root.eggPiece(labCard.eggP, 402)
          Connections {
            target: root
            function onEggSnap() { labCard.eggP = labCard.mapToItem(card, labCard.width / 2, labCard.height / 2) }
          }
          transform: [
            Rotation { origin.x: labCard.width / 2; origin.y: labCard.height / 2; angle: labCard.eggOff.r },
            Translate { x: labCard.eggOff.x; y: labCard.eggOff.y },
            Translate { x: labCard.shove }
          ]
          height: root.labCardHeight
          source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.menu/LabCard.qml"
          onLoaded: {
            item.active = Qt.binding(function() { return root.opened && root.showGoDash })
            item.foreground = Qt.binding(function() { return root.foreground })
            item.hoverBackground = Qt.binding(function() { return root.selectedBackground })
            item.fontFamily = Qt.binding(function() { return root.fontFamily })
            item.radius = Qt.binding(function() { return root.cornerRadius })
          }
          Connections {
            target: labCard.item
            function onClicked() {
              root.cancel()
              root.runAction("uwsm-app -- remmina")
            }
          }
        }

        // Self-hosted services on the lab box (ServerCard.qml, via ~/.local/bin/server-status).
        Loader {
          id: serverCard
          active: root.showGoDash
          enabled: !root.guestMode
          width: parent.width
          height: root.serverCardHeight
          property real shove: 0
          property point eggP: Qt.point(0, 0)
          readonly property var eggOff: root.eggPiece(serverCard.eggP, 403)
          Connections {
            target: root
            function onEggSnap() { serverCard.eggP = serverCard.mapToItem(card, serverCard.width / 2, serverCard.height / 2) }
          }
          transform: [
            Rotation { origin.x: serverCard.width / 2; origin.y: serverCard.height / 2; angle: serverCard.eggOff.r },
            Translate { x: serverCard.eggOff.x; y: serverCard.eggOff.y },
            Translate { x: serverCard.shove }
          ]
          source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.menu/ServerCard.qml"
          onLoaded: {
            // Guest: greyed out and never polls (no lab profile, no phone).
            item.opacity = root.guestMode ? 0.3 : 1
            item.active = Qt.binding(function() { return root.opened && root.showGoDash && !root.guestMode })
            item.foreground = Qt.binding(function() { return root.foreground })
            item.hoverBackground = Qt.binding(function() { return root.selectedBackground })
            item.fontFamily = Qt.binding(function() { return root.fontFamily })
            item.radius = Qt.binding(function() { return root.cornerRadius })
          }
          Connections {
            target: serverCard.item
            function onOpened(name) {
              root.cancel()
              // Jellyfin opens the desktop app (jellyfin-desktop); the rest
              // open their web page.
              if (name === "Jellyfin") root.runAction("uwsm-app -- jellyfin-desktop")
              else root.runAction("~/.local/bin/server-status open " + Util.shellQuote(name))
            }
            function onRemminaRequested() {
              root.cancel()
              root.runAction("uwsm-app -- remmina")
            }
          }
        }

        // KDE Connect phone (PhoneCard.qml, via ~/.local/bin/phone-status).
        Loader {
          id: phoneCard
          active: root.showGoDash
          enabled: !root.guestMode
          width: parent.width
          height: root.phoneCardHeight
          property real shove: 0
          property point eggP: Qt.point(0, 0)
          readonly property var eggOff: root.eggPiece(phoneCard.eggP, 404)
          Connections {
            target: root
            function onEggSnap() { phoneCard.eggP = phoneCard.mapToItem(card, phoneCard.width / 2, phoneCard.height / 2) }
          }
          transform: [
            Rotation { origin.x: phoneCard.width / 2; origin.y: phoneCard.height / 2; angle: phoneCard.eggOff.r },
            Translate { x: phoneCard.eggOff.x; y: phoneCard.eggOff.y },
            Translate { x: phoneCard.shove }
          ]
          source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.menu/PhoneCard.qml"
          onLoaded: {
            // Guest: greyed out and never polls (no lab profile, no phone).
            item.opacity = root.guestMode ? 0.3 : 1
            item.active = Qt.binding(function() { return root.opened && root.showGoDash && !root.guestMode })
            item.foreground = Qt.binding(function() { return root.foreground })
            item.hoverBackground = Qt.binding(function() { return root.selectedBackground })
            item.fontFamily = Qt.binding(function() { return root.fontFamily })
            item.radius = Qt.binding(function() { return root.cornerRadius })
          }
          Connections {
            target: phoneCard.item
            function onRequested(action, closeMenu) {
              if (closeMenu) root.cancel()
              root.runAction("~/.local/bin/phone-status " + action)
            }
          }
        }
      }

      // App panel (footer Apps): the grid fills the Go list + dash space, with
      // the launcher's five categories underneath. The scrollbar turns cyan
      // (theme accent) while hovered, dragged or scrolling.
      Item {
        id: appsPanel
        visible: root.goApps && root.goLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: card.contentLeftInset + (root.showSidebar && root.sidebarLeft ? root.sidebarWidth + Style.space(12) : 0)
        anchors.rightMargin: card.contentRightInset
        anchors.topMargin: card.contentTopInset + root.headerHeight + root.contentSpacing
        anchors.bottomMargin: card.contentBottomInset + root.goFooterHeight

        readonly property int columns: 5
        readonly property color accent: Commons.Color.pick("tablet.accent", Commons.Color.accent)

        Connections {
          target: DesktopEntries.applications
          function onValuesChanged() { if (root.goApps) root.rebuildApps() }
        }

        GridView {
          id: appsGrid
          anchors.left: parent.left
          anchors.right: appsScroll.left
          anchors.rightMargin: Style.space(6)
          anchors.top: parent.top
          anchors.bottom: appsTabs.top
          anchors.bottomMargin: Style.space(8)
          clip: true
          model: appsModel
          interactive: false                       // TouchScroll handles scrolling
          boundsBehavior: Flickable.StopAtBounds   // ends glow (TouchScroll)
          flickDeceleration: 900
          maximumFlickVelocity: 12000
          cellWidth: Math.floor(width / appsPanel.columns)
          cellHeight: Math.round(cellWidth * 0.95)

          delegate: Item {
            id: appCell
            required property string appId
            required property string label
            required property string appIcon
            width: appsGrid.cellWidth
            height: appsGrid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              radius: root.cornerRadius
              color: appCellArea.containsMouse ? root.selectedBackground : "transparent"
            }
            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(8)
              spacing: Style.space(6)

              Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(appsGrid.cellWidth * 0.42)
                height: width
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: root.appLibrary ? root.appLibrary.iconSource(appCell.appIcon) : root.appIconSource(appCell.appIcon)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: appCell.label
                color: appCellArea.containsMouse ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
            MouseArea {
              id: appCellArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.launchApp(appCell.appId, appCell.label)
            }
          }
        }

        TouchScroll { anchors.fill: appsGrid; view: appsGrid }

        // Scrollbar: cyan when hovered, dragged or the grid is moving.
        Item {
          id: appsScroll
          anchors.right: parent.right
          anchors.top: appsGrid.top
          anchors.bottom: appsGrid.bottom
          width: Style.space(8)
          visible: appsGrid.contentHeight > appsGrid.height
          readonly property bool lit: scrollArea.containsMouse || scrollArea.pressed || appsGrid.moving

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Util.alpha(root.foreground, 0.06)
          }
          Rectangle {
            id: scrollThumb
            width: parent.width
            radius: width / 2
            height: Math.max(Style.space(24), appsGrid.visibleArea.heightRatio * parent.height)
            y: appsGrid.visibleArea.yPosition * (parent.height - height) / Math.max(0.0001, 1 - appsGrid.visibleArea.heightRatio)
            color: appsScroll.lit ? appsPanel.accent : Util.alpha(root.foreground, 0.28)
            Behavior on color { ColorAnimation { duration: 120 } }
          }
          MouseArea {
            id: scrollArea
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            // Click or drag: jump the grid to that point.
            function seek(mouseY) {
              var t = Math.max(0, Math.min(1, (mouseY - scrollThumb.height / 2) / Math.max(1, appsScroll.height - scrollThumb.height)))
              appsGrid.contentY = t * Math.max(0, appsGrid.contentHeight - appsGrid.height)
            }
            onPressed: function(mouse) { seek(mouse.y) }
            onPositionChanged: function(mouse) { if (pressed) seek(mouse.y) }
          }
        }

        // The launcher's five categories, in capitals with thin dividers so they
        // read as a tab bar rather than labels for the columns above. The
        // dividers light up cyan in a quick left-to-right sweep and fade when
        // the panel opens or the category changes. ALL comes first; an active
        // category clicked again goes back to ALL.
        property real sweep: 2
        NumberAnimation {
          id: dividerSweep
          target: appsPanel
          property: "sweep"
          from: 0
          to: 2
          duration: 1300
        }
        onVisibleChanged: if (visible) dividerSweep.restart()
        Connections {
          target: root
          function onAppsCategoryChanged() { if (appsPanel.visible) dividerSweep.restart() }
        }

        Row {
          id: appsTabs
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.space(34)
          readonly property real dividerWidth: 1

          Repeater {
            model: root.appsCategoryTabs

            Rectangle {
              id: tab
              required property var modelData
              required property int index
              readonly property bool active: root.appsCategory === tab.modelData.id
              // COMMUNICATE gets a wider tab (weight 1.25) so it isn't crowded;
              // ALL is short, so it takes less (0.7).
              readonly property real weight: tab.modelData.id === "communicate" ? 1.25 : (tab.modelData.id === "" ? 0.7 : 1)
              width: (appsTabs.width - appsTabs.dividerWidth * (root.appsCategoryTabs.length - 1))
                * tab.weight / (root.appsCategoryTabs.length - 0.05)
              height: appsTabs.height
              radius: root.cornerRadius
              color: tabArea.containsMouse ? root.selectedBackground : "transparent"

              // Long labels (COMMUNICATE) shrink a little to keep clear of
              // their dividers; the rest stay at full size.
              Text {
                anchors.centerIn: parent
                width: parent.width - Style.space(20)
                horizontalAlignment: Text.AlignHCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Math.round(Style.font.body * 0.75)
                text: tab.modelData.label
                color: tab.active ? appsPanel.accent : (tabArea.containsMouse ? root.selectedText : root.foreground)
                opacity: tab.active || tabArea.containsMouse ? 1 : 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: tab.active ? Font.DemiBold : Font.Normal
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6
              }

              // Divider to the right of every tab but the last.
              Rectangle {
                visible: tab.index < root.appsCategoryTabs.length - 1
                x: parent.width
                anchors.verticalCenter: parent.verticalCenter
                width: appsTabs.dividerWidth
                height: parent.height * 0.5
                // 0..1 glow as the sweep passes this divider.
                readonly property real glow: {
                  var c = 0.3 + tab.index * 0.2, d = Math.abs(appsPanel.sweep - c)
                  return d >= 0.45 ? 0 : 0.5 + 0.5 * Math.cos(Math.PI * d / 0.45)
                }
                color: Qt.rgba(root.foreground.r + (appsPanel.accent.r - root.foreground.r) * glow,
                               root.foreground.g + (appsPanel.accent.g - root.foreground.g) * glow,
                               root.foreground.b + (appsPanel.accent.b - root.foreground.b) * glow,
                               0.16 + 0.7 * glow)
              }
              Rectangle {
                visible: tab.active
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.5
                height: 2
                radius: 1
                color: appsPanel.accent
              }
              MouseArea {
                id: tabArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.appsCategory = root.appsCategory === tab.modelData.id ? "" : tab.modelData.id
                  root.rebuildApps()
                  appsGrid.positionViewAtBeginning()
                }
              }
            }
          }
        }
      }

      // Keybinds panel (footer Keybinds): the SUPER+K list in the Go list +
      // dash space. Typing filters it, a click runs the binding
      // (~/.local/bin/keybind-run). Same cyan scrollbar as Apps.
      Item {
        id: keysPanel
        visible: root.goKeys && root.goLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: card.contentLeftInset + (root.showSidebar && root.sidebarLeft ? root.sidebarWidth + Style.space(12) : 0)
        anchors.rightMargin: card.contentRightInset
        anchors.topMargin: card.contentTopInset + root.headerHeight + root.contentSpacing
        anchors.bottomMargin: card.contentBottomInset + root.goFooterHeight + Style.space(6)

        readonly property color accent: Commons.Color.pick("tablet.accent", Commons.Color.accent)

        ListView {
          id: keysList
          anchors.left: parent.left
          anchors.right: keysScroll.left
          anchors.rightMargin: Style.space(8)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          clip: true
          model: keysModel
          interactive: false                       // TouchScroll handles scrolling
          boundsBehavior: Flickable.StopAtBounds   // ends glow (TouchScroll)
          flickDeceleration: 900
          maximumFlickVelocity: 12000

          delegate: Rectangle {
            id: keyRow
            required property string keys
            required property string desc
            required property string line
            required property int index
            width: keysList.width
            height: Style.font.body + Style.space(14)
            radius: root.cornerRadius
            color: keyRowArea.containsMouse ? root.selectedBackground
              : (keyRow.index % 2 ? Util.alpha(root.foreground, 0.03) : "transparent")

            Text {
              id: keyCombo
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width * 0.44
              text: keyRow.keys
              color: keyRowArea.containsMouse ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Text {
              anchors.left: keyCombo.right
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: keyRow.desc
              color: keyRowArea.containsMouse ? root.selectedText : root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            // Click runs the binding, like picking it in SUPER+K.
            MouseArea {
              id: keyRowArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.cancel()
                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/keybind-run", keyRow.line])
              }
            }
          }
        }

        TouchScroll { anchors.fill: keysList; view: keysList }

        Item {
          id: keysScroll
          anchors.right: parent.right
          anchors.top: keysList.top
          anchors.bottom: keysList.bottom
          width: Style.space(8)
          visible: keysList.contentHeight > keysList.height
          readonly property bool lit: keysScrollArea.containsMouse || keysScrollArea.pressed || keysList.moving

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Util.alpha(root.foreground, 0.06)
          }
          Rectangle {
            id: keysThumb
            width: parent.width
            radius: width / 2
            height: Math.max(Style.space(24), keysList.visibleArea.heightRatio * parent.height)
            y: keysList.visibleArea.yPosition * (parent.height - height) / Math.max(0.0001, 1 - keysList.visibleArea.heightRatio)
            color: keysScroll.lit ? keysPanel.accent : Util.alpha(root.foreground, 0.28)
            Behavior on color { ColorAnimation { duration: 120 } }
          }
          MouseArea {
            id: keysScrollArea
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            function seek(mouseY) {
              var t = Math.max(0, Math.min(1, (mouseY - keysThumb.height / 2) / Math.max(1, keysScroll.height - keysThumb.height)))
              keysList.contentY = t * Math.max(0, keysList.contentHeight - keysList.height)
            }
            onPressed: function(mouse) { seek(mouse.y) }
            onPositionChanged: function(mouse) { if (pressed) seek(mouse.y) }
          }
        }
      }

      // Easter egg duel (see duelOn): cyan sword vs coral sword, trading
      // lunges and parries with sparks when the blades meet.
      Canvas {
        id: duel
        readonly property bool shown: root.duelOn && root.goLayout && !root.filterText
          && (root.activeMenu === "root" || root.activeMenu === "tablet" || root.activeMenu === "system")
        // Under the Go list's last row, just above the footer, in the
        // list's column (not under the dash). Hidden if the rows reach down.
        anchors.left: goFooter.left
        anchors.bottom: goFooter.top
        anchors.bottomMargin: Style.space(4)
        width: goFooter.width - (root.showGoDash ? root.goDashWidth + root.goDashGap : 0)
        // Drawn over the menu (user asked): the fighters stand on the
        // footer line at their usual size (unit from a 64px strip), and the
        // canvas reaches up over the list so raised arms, hops and a flying
        // head are never clipped.
        z: 50
        readonly property real strip: Style.space(64)
        height: strip + Style.space(90)
        visible: shown
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }

        property real t: 0
        // Random fight state, advanced every frame (step()). Positions are in
        // "units" (1/64 of the canvas height) or fractions of the width.
        property var st: null
        function rnd(a, b) { return a + Math.random() * (b - a) }
        function freshState() {
          return {
            cx: 0.5, cxTarget: 0.5, cxSpeed: 0.4, nextMove: 0,
            gap: 32, gapTarget: 32, nextGap: 0,
            A: { attack: 0, atkT: -1, next: duel.rnd(0.2, 0.9), lvl: 0, nextLvl: duel.rnd(0.2, 0.7), jump: 0, jumpT: -1 },
            B: { attack: 0, atkT: -1, next: duel.rnd(0.2, 0.9), lvl: 0, nextLvl: duel.rnd(0.2, 0.7), jump: 0, jumpT: -1 },
            nextKill: duel.rnd(4, 9), killT: -1, loserA: Math.random() < 0.5, run: 0, nextHop: duel.rnd(2, 5),
            // Blood mode: no knockdowns; after 3 s the finale (finT counts up).
            blood: root.bloodMode, time: 0, finT: -1, finAt: 3,
            // The loser's head once it's off, in units: offset from the
            // loser's x, height of its centre above the ground, spin.
            head: null, wUnits: 200
          }
        }
        onVisibleChanged: if (visible) { duel.t = 0; duel.st = duel.freshState() }
        function stepFencer(f, dt, fighting) {
          // Thrust: 0.28 s in-and-out, then a random pause before the next.
          if (f.atkT >= 0) {
            f.atkT += dt
            f.attack = Math.sin(Math.min(1, f.atkT / 0.28) * Math.PI)
            if (f.atkT >= 0.28) { f.atkT = -1; f.attack = 0; f.next = duel.rnd(0.15, 1.1) }
          } else if (fighting) {
            f.next -= dt
            if (f.next <= 0) f.atkT = 0
          }
          // Stance: high / mid / low at random moments.
          f.nextLvl -= dt
          if (f.nextLvl <= 0) { f.lvl = Math.floor(Math.random() * 3) - 1; f.nextLvl = duel.rnd(0.15, 0.8) }
          // Hop: a quick 0.4 s arc.
          if (f.jumpT >= 0) {
            f.jumpT += dt
            f.jump = Math.sin(Math.min(1, f.jumpT / 0.4) * Math.PI)
            if (f.jumpT >= 0.4) { f.jumpT = -1; f.jump = 0 }
          }
        }
        function step(dt) {
          var st = duel.st
          if (!st) return
          dt = Math.min(dt, 0.05)
          st.time += dt
          if (st.blood) {
            st.nextKill = 99
            if (st.finT < 0 && st.time >= st.finAt) { st.finT = 0; st.cxTarget = st.cx; st.A.atkT = -1; st.B.atkT = -1; st.A.attack = 0; st.B.attack = 0 }
            if (st.finT >= 0) { duel.stepFinale(st, dt); return }
          }
          var fighting = st.killT < 0
          // Dash toward a random spot, at a random speed.
          st.nextMove -= dt
          if (st.nextMove <= 0) { st.cxTarget = duel.rnd(0.1, 0.9); st.cxSpeed = duel.rnd(0.25, 0.9); st.nextMove = duel.rnd(0.5, 2.0) }
          var prev = st.cx
          var dx = st.cxTarget - st.cx
          st.cx += Math.sign(dx) * Math.min(Math.abs(dx), st.cxSpeed * dt)
          st.run = Math.abs(st.cx - prev) / Math.max(dt, 0.001)
          // Distance between them wanders.
          st.nextGap -= dt
          if (st.nextGap <= 0) { st.gapTarget = duel.rnd(24, 42); st.nextGap = duel.rnd(0.3, 1.2) }
          st.gap += (st.gapTarget - st.gap) * Math.min(1, dt * 6)
          duel.stepFencer(st.A, dt, fighting)
          duel.stepFencer(st.B, dt, fighting)
          // Now and then someone hops.
          st.nextHop -= dt
          if (st.nextHop <= 0) {
            var f = Math.random() < 0.5 ? st.A : st.B
            if (f.jumpT < 0) f.jumpT = 0
            st.nextHop = duel.rnd(1.5, 5)
          }
          // Knockdown at a random time, random loser: fall, lie, get up.
          if (st.killT >= 0) {
            st.killT += dt
            if (st.killT >= 1.0) { st.killT = -1; st.nextKill = duel.rnd(4, 10) }
          } else {
            st.nextKill -= dt
            if (st.nextKill <= 0) { st.killT = 0; st.loserA = Math.random() < 0.5 }
          }
        }
        // The finale: the winner's high cut, the loser's head pops off and
        // bounces, then rolls away from the winner until it stops (or meets
        // the edge); the body falls back and stays down; the winner hops
        // with both arms up.
        function stepFinale(st, dt) {
          st.finT += dt
          st.run = 0
          var away = st.loserA ? -1 : 1      // the loser stands on the winner's left if loserA
          if (!st.head && st.finT >= 0.25)
            st.head = { x: 0, y: 44.5, vx: away * duel.rnd(26, 38), vy: duel.rnd(22, 32), spin: 0, rolling: false }
          var h = st.head
          if (h) {
            var r = 5.5
            if (!h.rolling) {
              h.vy -= 150 * dt
              h.x += h.vx * dt
              h.y += h.vy * dt
              h.spin += h.vx / r * dt
              if (h.y <= r) {
                h.y = r
                h.vy = -h.vy * 0.38
                h.vx *= 0.8
                if (Math.abs(h.vy) < 8) { h.vy = 0; h.rolling = true }
              }
            } else {
              h.vx *= Math.pow(0.35, dt)       // friction
              h.x += h.vx * dt
              h.spin += h.vx / r * dt
              if (Math.abs(h.vx) < 0.8) h.vx = 0
            }
            // Stop at the canvas edge (the loser's x isn't known here, so
            // onPaint clamps the drawn position too).
          }
          // Winner keeps hopping in celebration.
          var w = st.loserA ? st.B : st.A
          if (st.finT > 0.7 && w.jumpT < 0) w.jumpT = 0
          duel.stepFencer(w, dt, false)
        }

        FrameAnimation {
          running: duel.visible
          onTriggered: { duel.t += frameTime; duel.step(frameTime); duel.requestPaint() }
        }

        readonly property color ink: root.foreground
        readonly property color blueBlade: "#7dcfff"
        readonly property color coralBlade: "#f7768e"

        // 0..1 bump centred on c with half-width w.
        function bump(p, c, w) { var d = Math.abs(p - c); return d >= w ? 0 : 0.5 + 0.5 * Math.cos(Math.PI * d / w) }

        // Deterministic "random" 0..1 for integer n (stance changes).
        function hash(n) { var x = Math.sin(n * 12.9898) * 43758.5453; return x - Math.floor(x) }
        function level(n) { return Math.floor(hash(n) * 3) - 1 }   // -1 low, 0 mid, 1 high

        // One fighter drawn around its feet at (x, ground). dir: 1 faces
        // right. attack 0..1 (thrust), lvl -1..1 (sword height), run = how
        // fast it's travelling (legs scissor), fall 0..1 (stabbed, falls back).
        // Returns the sword tip.
        // extra (optional): { headless, cheer } for the blood-mode finale.
        function fighter(ctx, x, ground, dir, attack, lvl, bob, run, fall, blade, unit, extra) {
          var headless = !!(extra && extra.headless), cheer = extra ? (extra.cheer || 0) : 0
          var leg = 18 * unit, body = 20 * unit, head = 5.5 * unit
          ctx.save()
          ctx.translate(x, ground)
          ctx.rotate(-dir * fall * Math.PI / 2)
          var hipY = -leg + bob, shY = hipY - body
          ctx.strokeStyle = duel.ink
          ctx.lineWidth = 2 * unit
          ctx.lineCap = "round"
          // Legs: lunge stride plus a running scissor.
          var swing = Math.sin(duel.t * 22) * Math.min(1, run) * 7 * unit * (1 - fall)
          ctx.beginPath()
          ctx.moveTo(0, hipY); ctx.lineTo(dir * (8 * unit + 10 * unit * attack) + swing, 0)
          ctx.moveTo(0, hipY); ctx.lineTo(-dir * 9 * unit - swing, 0)
          var lean = dir * (5 * unit * attack + 2 * unit * Math.min(1, run))
          ctx.moveTo(0, hipY); ctx.lineTo(lean, shY)
          ctx.stroke()
          if (!headless) {
            ctx.beginPath()
            ctx.arc(lean * 1.2, shY - head - 1 * unit, head, 0, 2 * Math.PI)
            ctx.stroke()
          }
          if (cheer > 0) {
            // Both arms up in a wide V (clear of the head), the sword raised
            // in the leading hand, tilted out.
            var up = 8 * unit * cheer, out = 11 * unit
            ctx.beginPath()
            ctx.moveTo(lean, shY + 3 * unit); ctx.lineTo(lean - dir * out, shY - up)
            ctx.moveTo(lean, shY + 3 * unit); ctx.lineTo(lean + dir * out, shY - up)
            ctx.stroke()
            var cx2 = lean + dir * out, cy2 = shY - up
            ctx.strokeStyle = blade
            ctx.lineWidth = 2.2 * unit
            ctx.beginPath(); ctx.moveTo(cx2, cy2); ctx.lineTo(cx2 + dir * 5 * unit, cy2 - 13 * unit); ctx.stroke()
            ctx.restore()
            return { x: x + cx2, y: ground + cy2 - 13 * unit }
          }
          var noBlade = !!(extra && extra.dropped)
          // Back arm.
          ctx.beginPath()
          ctx.moveTo(lean, shY + 3 * unit)
          ctx.lineTo(lean - dir * 10 * unit, shY - 4 * unit - 4 * unit * attack)
          ctx.stroke()
          // Sword arm: hand height follows the stance, reaches out on a thrust.
          var hx = lean + dir * (9 * unit + 12 * unit * attack)
          var hy = shY + 7 * unit - lvl * 7 * unit
          ctx.beginPath()
          ctx.moveTo(lean, shY + 3 * unit); ctx.lineTo(hx, hy)
          ctx.stroke()
          // Blade: tilted by stance (high points up, low points down), level on a thrust.
          var ang = (lvl * 22 * (1 - attack) + 4) * Math.PI / 180
          var len = 24 * unit
          var tx = hx + dir * Math.cos(ang) * len, ty = hy - Math.sin(ang) * len
          if (!noBlade) {
            ctx.strokeStyle = blade
            ctx.lineWidth = 2.2 * unit
            ctx.beginPath(); ctx.moveTo(hx, hy); ctx.lineTo(tx, ty); ctx.stroke()
            ctx.strokeStyle = duel.ink
            ctx.lineWidth = 1.6 * unit
            ctx.beginPath()
            ctx.moveTo(hx - 3 * unit * Math.sin(ang) * dir, hy - 3 * unit * Math.cos(ang))
            ctx.lineTo(hx + 3 * unit * Math.sin(ang) * dir, hy + 3 * unit * Math.cos(ang))
            ctx.stroke()
          }
          // Tip in canvas coordinates (undo the fall rotation).
          var a = -dir * fall * Math.PI / 2
          var gx = x + tx * Math.cos(a) - ty * Math.sin(a), gy = ground + tx * Math.sin(a) + ty * Math.cos(a)
          ctx.restore()
          return { x: gx, y: gy }
        }

        function spark(ctx, x, y, size, unit) {
          ctx.strokeStyle = "#ffffff"
          ctx.lineWidth = 1.4 * unit
          ctx.beginPath()
          for (var i = 0; i < 6; i++) {
            var a = i * Math.PI / 3 + duel.t * 9
            ctx.moveTo(x + Math.cos(a) * 2 * unit, y + Math.sin(a) * 2 * unit)
            ctx.lineTo(x + Math.cos(a) * size, y + Math.sin(a) * size)
          }
          ctx.stroke()
        }

        // Nidhogg-ish, from the random state: the pair dashes about, each
        // fencer thrusts and changes stance at random moments, the odd hop, and
        // now and then someone is run through, drops, and pops back up.
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var st = duel.st
          if (!st) return
          var unit = Math.max(1, duel.strip / 64)
          var ground = height - 4 * unit
          var t = duel.t
          var travel = Math.max(0, width / 2 - 62 * unit)
          var cx = width / 2 + travel * (st.cx - 0.5) * 2
          var run = st.run * travel * 2 / (60 * unit)

          // Knockdown: fall 0.2 s, lie, get up in the last 0.2 s.
          var fall = 0
          if (st.killT >= 0) fall = Math.min(1, st.killT / 0.2) * Math.min(1, Math.max(0, (1.0 - st.killT) / 0.2))
          var aA = st.A.attack, aB = st.B.attack, lA = st.A.lvl, lB = st.B.lvl
          if (st.killT >= 0) {   // winner holds the thrust then a high guard
            if (st.loserA) { aB = st.killT < 0.35 ? 0.9 : 0; lB = 1 } else { aA = st.killT < 0.35 ? 0.9 : 0; lA = 1 }
          }
          var gap = st.gap * unit - 6 * unit * (aA + aB)
          var bobA = Math.sin(t * 9) * 1.2 * unit - st.A.jump * 12 * unit
          var bobB = Math.sin(t * 9 + 1.4) * 1.2 * unit - st.B.jump * 12 * unit

          ctx.strokeStyle = Qt.rgba(duel.ink.r, duel.ink.g, duel.ink.b, 0.18)
          ctx.lineWidth = 1 * unit
          ctx.beginPath(); ctx.moveTo(8 * unit, ground + 1 * unit); ctx.lineTo(width - 8 * unit, ground + 1 * unit); ctx.stroke()

          // Blood-mode finale: the cut, then beheading, slump and celebration.
          if (st.blood && st.finT >= 0) {
            var f = st.finT
            var winA = !st.loserA
            var cut = f < 0.35 ? 0.9 : 0
            var slump = Math.min(1, Math.max(0, (f - 0.45) / 0.35))
            var cheer = Math.min(1, Math.max(0, (f - 0.7) / 0.25))
            var xA = cx - gap, xB = cx + gap
            // Celebration hops.
            bobA = -st.A.jump * 9 * unit
            bobB = -st.B.jump * 9 * unit
            var dropped = slump > 0.6
            var tA2 = fighter(ctx, xA, ground, 1, winA ? cut : 0, 1, bobA, 0, winA ? 0 : slump, duel.blueBlade, unit,
              winA ? { cheer: cheer } : { headless: f >= 0.25, dropped: dropped })
            var tB2 = fighter(ctx, xB, ground, -1, winA ? 0 : cut, 1, bobB, 0, winA ? slump : 0, duel.coralBlade, unit,
              winA ? { headless: f >= 0.25, dropped: dropped } : { cheer: cheer })
            // The loser's sword, dropped flat on the ground beside them.
            if (dropped) {
              var lx0 = winA ? xB : xA, ldir = winA ? -1 : 1
              ctx.strokeStyle = winA ? duel.coralBlade : duel.blueBlade
              ctx.lineWidth = 2.2 * unit
              ctx.beginPath()
              ctx.moveTo(lx0 + ldir * 6 * unit, ground - 1.2 * unit); ctx.lineTo(lx0 + ldir * 30 * unit, ground - 1.2 * unit)
              ctx.stroke()
              ctx.strokeStyle = duel.ink
              ctx.lineWidth = 1.6 * unit
              ctx.beginPath(); ctx.moveTo(lx0 + ldir * 8 * unit, ground - 4 * unit); ctx.lineTo(lx0 + ldir * 8 * unit, ground + 1.5 * unit); ctx.stroke()
            }
            if (st.head) {
              var lx = winA ? xB : xA
              var hx = Math.max(6 * unit, Math.min(width - 6 * unit, lx + st.head.x * unit))
              var hy = ground - st.head.y * unit
              var r = 5.5 * unit
              ctx.strokeStyle = duel.ink
              ctx.lineWidth = 2 * unit
              ctx.beginPath(); ctx.arc(hx, hy, r, 0, 2 * Math.PI); ctx.stroke()
              // A dot for an eye, so the roll shows.
              ctx.fillStyle = duel.ink
              ctx.beginPath()
              ctx.arc(hx + Math.cos(st.head.spin) * r * 0.45, hy + Math.sin(st.head.spin) * r * 0.45, 1.2 * unit, 0, 2 * Math.PI)
              ctx.fill()
            }
            return
          }

          var tipA = fighter(ctx, cx - gap, ground, 1, aA, lA, bobA, run, st.killT >= 0 && st.loserA ? fall : 0, duel.blueBlade, unit)
          var tipB = fighter(ctx, cx + gap, ground, -1, aB, lB, bobB, run, st.killT >= 0 && !st.loserA ? fall : 0, duel.coralBlade, unit)

          var d = Math.hypot(tipA.x - tipB.x, tipA.y - tipB.y)
          if (st.killT < 0 && d < 10 * unit) spark(ctx, (tipA.x + tipB.x) / 2, (tipA.y + tipB.y) / 2, (4 + (10 * unit - d) / unit) * unit, unit)
        }
      }

      // Go menu bottom row: Apps / Tablet / System open their submenus.
      Item {
        id: goFooter
        visible: root.showGoFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // Under the list only; the sidebar fills the column to its left.
        anchors.leftMargin: card.contentLeftInset + (root.showSidebar && root.sidebarLeft ? root.sidebarWidth + Style.space(12) : 0)
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        height: root.goFooterButtonHeight

        // Card-dealer spread: the buttons start as a deck on Apps, each with a
        // card face, and peel off right one after another, the top card
        // (System) first, tilting as they slide, until Apps (the bottom card)
        // is uncovered; the faces fade once dealt.
        property real dealClock: 1
        readonly property int dealStagger: 70
        readonly property int dealTravel: 340
        readonly property int dealTotal: dealStagger * (root.goFooterItems.length - 1) + dealTravel
        function deal() { dealAnim.restart() }

        SequentialAnimation {
          id: dealAnim
          PropertyAction { target: goFooter; property: "dealClock"; value: 0 }
          PauseAnimation { duration: 160 }
          NumberAnimation { target: goFooter; property: "dealClock"; to: 1; duration: goFooter.dealTotal }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          y: -Math.round(root.contentSpacing / 2)
          height: Style.spacing.hairline
          color: Util.alpha(root.foreground, 0.2)
        }

        Row {
          anchors.fill: parent
          Repeater {
            model: root.goFooterItems

            Rectangle {
              id: footButton
              required property var modelData
              required property int index
              readonly property int count: root.goFooterItems.length
              // 0 = still in the deck under Apps, 1 = dealt into its place.
              readonly property real dealt: {
                var start = (count - 1 - index) * goFooter.dealStagger
                var t = Math.max(0, Math.min(1, (goFooter.dealClock * goFooter.dealTotal - start) / goFooter.dealTravel))
                return 1 - Math.pow(1 - t, 3)
              }
              width: goFooter.width / root.goFooterItems.length
              height: goFooter.height
              radius: root.cornerRadius
              readonly property bool lit: footArea.pressed || footArea.containsMouse || root.footFocus === footButton.index
              color: lit ? root.selectedBackground : "transparent"
              // Apps is the bottom card of the deck, so it never covers the others.
              z: index
              property point eggP: Qt.point(0, 0)
              readonly property var eggOff: root.eggPiece(footButton.eggP, 500 + footButton.index)
              Connections {
                target: root
                function onEggSnap() { footButton.eggP = footButton.mapToItem(card, footButton.width / 2, footButton.height / 2) }
              }
              transform: [
                Rotation { origin.x: footButton.width / 2; origin.y: footButton.height / 2; angle: footButton.eggOff.r },
                Translate { x: footButton.eggOff.x; y: footButton.eggOff.y },
                Translate { x: -footButton.index * footButton.width * (1 - footButton.dealt) },
                Rotation {
                  origin.x: footButton.width / 2
                  origin.y: footButton.height
                  angle: footButton.index > 0 ? (1 - footButton.dealt) * -7 : 0
                }
              ]

              // The card face, shown while the deck is being dealt.
              Rectangle {
                anchors.fill: parent
                z: -1
                radius: root.cornerRadius
                color: root.background
                border.width: Style.spacing.hairline
                border.color: Util.alpha(root.foreground, 0.1)
                opacity: goFooter.dealClock < 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
              }

              Column {
                anchors.centerIn: parent
                spacing: Style.space(4)
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: footButton.modelData.icon
                  color: footButton.lit ? root.selectedText : root.foreground
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Math.round(Style.font.heading * 1.5)
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: footButton.modelData.label
                  color: footButton.lit ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                id: footArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                  // Right click: the button's rightCommand, if it has one.
                  if (mouse.button === Qt.RightButton) {
                    if (footButton.modelData.rightCommand) {
                      root.cancel()
                      root.runAction(footButton.modelData.rightCommand)
                    }
                    return
                  }
                  // Apps toggles the app panel in place; the others are submenus.
                  if (footButton.modelData.apps) {
                    root.setGoApps(!root.goApps)
                  } else if (footButton.modelData.keys) {
                    root.setGoKeys(!root.goKeys)
                  } else if (footButton.modelData.command) {
                    root.cancel()
                    root.runAction(footButton.modelData.command)
                  } else {
                    root.setActiveMenu(footButton.modelData.target, true, true)
                  }
                }
              }
            }
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset + (root.showSidebar && !root.sidebarLeft ? root.sidebarWidth : 0)
          + (root.showGoDash ? root.goDashWidth + root.goDashGap : 0)
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset + (root.showSidebar && root.sidebarLeft ? root.sidebarWidth + Style.space(12) : 0)
        spacing: root.contentSpacing

        Rectangle {
          id: eggHeader
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          property point eggP: Qt.point(0, 0)
          readonly property var eggOff: root.eggPiece(eggHeader.eggP, 700)
          Connections {
            target: root
            function onEggSnap() { eggHeader.eggP = eggHeader.mapToItem(card, eggHeader.width / 2, eggHeader.height / 2) }
          }
          transform: [
            Rotation { origin.x: eggHeader.width / 2; origin.y: eggHeader.height / 2; angle: eggHeader.eggOff.r },
            Translate { x: eggHeader.eggOff.x; y: eggHeader.eggOff.y }
          ]
          color: "transparent"

          // Back arrow for touch: same as Backspace, shown inside submenus.
          readonly property bool canGoBack: !root.dmenuActive && !root.filterText
            && (root.goPanel || (root.activeMenu !== "root" && root.activeMenu !== root.homeMenu))

          Item {
            id: backButton
            visible: parent.canGoBack
            width: visible ? Style.font.heading + Style.space(12) : 0
            height: parent.height
            anchors.left: parent.left

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "󰁍"
              color: backArea.containsMouse ? Commons.Color.pick("tablet.accent", Commons.Color.accent) : root.foreground
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.heading
            }

            MouseArea {
              id: backArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              // In the app panel the arrow goes back to the Go list.
              onClicked: root.goPanel ? root.closeGoPanel() : root.goBack()
            }
          }

          Row {
            id: appsActions
            visible: root.goPanel && root.goLayout
            anchors.left: backButton.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            // What's typed filters the grid. Like a search box: the caret sits
            // before the "Go…" hint, then follows the typed text.
            Rectangle {
              visible: !root.filterText
              width: 2
              height: Style.font.heading
              anchors.verticalCenter: parent.verticalCenter
              color: Commons.Color.pick("tablet.accent", Commons.Color.accent)
              opacity: headerCaretBlink.on ? 1 : 0
            }
            Text {
              id: appsTitle
              text: root.filterText || "Go…"
              color: root.foreground
              opacity: root.filterText ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
              visible: !!root.filterText
              width: 2
              height: Style.font.heading
              anchors.verticalCenter: parent.verticalCenter
              color: Commons.Color.pick("tablet.accent", Commons.Color.accent)
              opacity: headerCaretBlink.on ? 1 : 0
            }
          }


          // Blinking caret: typing in the Go menu searches.
          Timer {
            id: headerCaretBlink
            property bool on: true
            interval: 530
            repeat: true
            running: root.opened && root.goLayout
            onRunningChanged: on = true
            onTriggered: on = !on
          }
          Rectangle {
            visible: goTitle.visible && root.goLayout && root.activeMenu === "root"
            x: root.filterText ? goTitle.x + Math.min(goTitle.contentWidth, goTitle.width) + Style.space(3)
                               : goTitle.x - Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: Style.font.heading
            color: Commons.Color.pick("tablet.accent", Commons.Color.accent)
            opacity: headerCaretBlink.on ? 1 : 0
          }

          Text {
            id: goTitle
            visible: !appsActions.visible
            textFormat: Text.PlainText
            anchors.left: backButton.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || (root.dmenuActive ? (root.dmenuPrompt + "…") : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "Go") + "…"))
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight
          visible: !root.goPanel

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: !root.egging
            spacing: root.rowSpacing
            interactive: false                       // TouchScroll handles scrolling
            boundsBehavior: Flickable.StopAtBounds   // ends glow (TouchScroll)
            flickDeceleration: 900
            maximumFlickVelocity: 12000

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.2)
              }
            }

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property string closeAction
              required property int childCount

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
              readonly property bool isApp: row.kind === "app"
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              property point eggP: Qt.point(0, 0)
              readonly property var eggOff: root.eggPiece(row.eggP, 200 + row.index)
              Connections {
                target: root
                function onEggSnap() { row.eggP = row.mapToItem(card, row.width / 2, row.height / 2) }
              }
              transform: [
                Rotation { origin.x: row.width / 2; origin.y: row.height / 2; angle: row.eggOff.r },
                Translate { x: row.eggOff.x; y: row.eggOff.y }
              ]
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Rectangle {
                visible: false
                width: Style.space(4)
                height: parent.height - Style.space(18)
                radius: Math.min(root.cornerRadius, Style.space(4))
                color: root.selectedBackground
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: iconText
                textFormat: Text.PlainText
                visible: row.hasIcon && !row.isApp
                text: row.icon
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: Style.font.iconLarge
                width: Style.space(36)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: Style.font.iconLarge
                height: Style.font.iconLarge
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: !row.isApp ? "" : root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : root.appIconSource(row.appIcon)
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8) + (Style.space(36) - width) / 2
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: row.hasIcon ? iconText.right : parent.left
                anchors.leftMargin: row.hasIcon ? Style.space(6) : root.rowReservedBorderLeft + Style.space(18)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  id: labelText
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.detail
                  visible: (root.filterText || row.kind === "dmenu") && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: root.rowReservedBorderRight + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: 0

                Text {
                  textFormat: Text.PlainText
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectFromPointer(row.index, row, {
                  x: mouseArea.mouseX,
                  y: mouseArea.mouseY
                })
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }

              // Close button for rows that carry a close action (the
              // workspace menu's windows). The menu stays open and the rows
              // reload once the window has had a moment to go.
              Rectangle {
                visible: row.closeAction.length > 0
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - Style.space(12)
                height: width
                radius: root.cornerRadius
                color: closeArea.pressed || closeArea.containsMouse ? Util.alpha(Commons.Color.urgent, 0.35) : Util.alpha(root.foreground, 0.08)

                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  color: root.foreground
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Style.font.heading
                }

                MouseArea {
                  id: closeArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.runAction(row.closeAction)
                    providerRefresh.restart()
                  }
                }
              }
            }
          }

          TouchScroll { anchors.fill: resultList; view: resultList }

          // Scroll scrims. The clipped row already marks the fold at rest;
          // these keep both edges honest once the list has been scrolled,
          // when content hides above the card top as well as below. Strength
          // tracks the distance still hidden past each edge rather than
          // animating on a clock, so a programmatic jump — wrapping from the
          // last row back to the first — lands with the fade already applied.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: root.background }
              GradientStop { position: 1; color: Util.alpha(root.background, 0) }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.background, 0) }
              GradientStop { position: 1; color: root.background }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input"

            Text {
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              textFormat: Text.PlainText
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }

    // Touch scroll rail (tablet mode, long lists only): drag the handle or tap
    // the rail to jump. Sits on the side of the card nearer the screen edge
    // (card.railLeft).
    Rectangle {
      id: rail
      readonly property real overflow: Math.max(0, resultList.contentHeight - resultList.height)
      readonly property real inset: Style.space(4)
      readonly property real trackHeight: height - inset * 2
      readonly property real handleHeight: overflow > 0
        ? Math.max(width * 2, trackHeight * resultList.height / resultList.contentHeight) : trackHeight
      readonly property real position: overflow > 0 ? (resultList.contentY - resultList.originY) / overflow : 0

      visible: panel.tabletOn && overflow > 0 && !root.dmenuActive
      width: Style.space(22)
      height: card.height
      x: card.railLeft ? card.x - Style.space(8) - width : card.x + card.width + Style.space(8)
      y: card.y
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
          resultList.contentY = resultList.originY + Math.max(0, Math.min(1, p)) * rail.overflow
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
