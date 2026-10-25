import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Small search box near the top of the screen, summoned by tapping SUPER on
// its own (hypr/bindings.lua). Typing lists matching apps, then "Search
// files" (Catfish dropdown via ~/.local/bin/file-search) and "Search the
// web". The screen dims behind it and the info bar (daa.infobar) shows at
// the bottom while it's open. Starting with "/" switches to commands: the built-ins below, filtered
// by name, plus "Run … in a terminal" for anything else. Up/Down move, Enter
// runs, Tab / Shift+Tab switch desktop, Escape or a click outside closes.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property bool opened: false
  property string query: ""
  property int selected: 0
  property var results: []
  property bool grabKeys: false

  // Easter egg: the Konami code (or the unlisted "/comets") sets off a comet
  // storm across the dimmed screen -- the shortcut card's border comets
  // broken loose.
  readonly property var konami: [Qt.Key_Up, Qt.Key_Up, Qt.Key_Down, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right,
    Qt.Key_Left, Qt.Key_Right, Qt.Key_B, Qt.Key_A]
  property int konamiAt: 0
  // Easter egg #2 (Mortal Kombat's blood code): typing "abacabb"
  // turns the UI to blood for a minute -- every cyan (the accent) a slightly
  // darker coral, every white (the foreground) a light coral, the window
  // border coral to coral -- then fades back. Typing it again ends it early.
  // Widgets with hard-coded white (shortcut card, update count) watch for
  // the blood accent and follow.
  readonly property color bloodAccent: "#e0607a"
  readonly property color bloodWhite: "#ffb8c6"
  property bool bloodOn: false
  property color savedAccent: "black"
  property color savedForeground: "black"

  function blood() {
    if (root.bloodOn) return root.unblood()
    root.savedAccent = Commons.Color.accent
    root.savedForeground = Commons.Color.foreground
    root.bloodOn = true
    bloodFade.stop()
    bloodFade.toAccent = root.bloodAccent
    bloodFade.toForeground = root.bloodWhite
    bloodFade.start()
    Quickshell.execDetached(["hyprctl", "eval",
      'hl.config({ general = { col = { active_border = { colors = { "rgb(e0607a)", "rgb(ffb8c6)" }, angle = 45 } } } })'])
    bloodTimer.restart()
  }

  function unblood() {
    if (!root.bloodOn) return
    root.bloodOn = false
    bloodTimer.stop()
    bloodFade.stop()
    bloodFade.toAccent = root.savedAccent
    bloodFade.toForeground = root.savedForeground
    bloodFade.start()
    // Back to what hypr/looknfeel.lua sets.
    Quickshell.execDetached(["hyprctl", "eval",
      'hl.config({ general = { col = { active_border = { colors = { "rgb(7dcfff)", "rgb(f7768e)" }, angle = 45 } } } })'])
  }

  Timer { id: bloodTimer; interval: 60000; onTriggered: root.unblood() }

  // `omarchy-shell daa.search comets "<text>"`: open the box showing <text>
  // (no results listed) and set off the storm, without typing anything
  // (screenshots, demos).
  IpcHandler {
    target: "daa.search"
    function comets(text: string): void {
      if (root.shell && typeof root.shell.summon === "function") root.shell.summon("daa.search", "{}")
      else root.open("{}")
      stormKick.caption = String(text || "")
      stormKick.restart()
    }
  }
  Timer {
    id: stormKick
    property string caption: ""
    interval: 250
    onTriggered: {
      input.text = caption
      storm.start()
    }
  }

  ParallelAnimation {
    id: bloodFade
    property color toAccent: "black"
    property color toForeground: "black"
    ColorAnimation { target: Commons.Color; property: "accent"; to: bloodFade.toAccent; duration: 700; easing.type: Easing.InOutQuad }
    ColorAnimation { target: Commons.Color; property: "foreground"; to: bloodFade.toForeground; duration: 700; easing.type: Easing.InOutQuad }
  }

  function konamiKey(key) {
    if (key === root.konami[root.konamiAt]) root.konamiAt++
    else root.konamiAt = key === root.konami[0] ? 1 : 0
    if (root.konamiAt === root.konami.length) {
      root.konamiAt = 0
      // Drop the "ba" that went into the box -- after this keypress lands
      // (Keys sees the "a" before the box does).
      Qt.callLater(function() {
        root.query = root.query.replace(/ba$/i, "")
        input.text = root.query
        root.rebuild()
        storm.start()
      })
    }
  }

  function takeKeys() {
    root.grabKeys = true
    keyPulse.restart()
  }
  Timer { id: keyPulse; interval: 120; onTriggered: root.grabKeys = false }

  // Re-grab after losing focus, at most 4 times a second so a fight with
  // something that keeps taking focus can't loop.
  property var regrabs: []
  Timer {
    id: refocus
    interval: 120
    onTriggered: {
      if (!root.opened || input.activeFocus) return
      var now = Date.now()
      root.regrabs = root.regrabs.filter(function(t) { return now - t < 1000 }).concat([now])
      if (root.regrabs.length > 4) return
      root.takeKeys()
      input.forceActiveFocus()
    }
  }

  readonly property int focusedWorkspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
  onFocusedWorkspaceChanged: if (root.opened) root.takeKeys()

  readonly property int maxApps: 6
  readonly property bool guest: Quickshell.env("USER") === "guest"

  // Slash commands: name, what it does, glyph, shell command.
  readonly property var commands: [
    { name: "lock", desc: "Lock the screen", glyph: "󰌾", command: "omarchy-system-lock" },
    { name: "sleep", desc: "Suspend", glyph: "󰒲", command: "systemctl suspend" },
    { name: "logout", desc: "Log out", glyph: "󰍃", command: "omarchy-system-logout" },
    { name: "reboot", desc: "Restart", glyph: "󰜉", command: "omarchy-system-reboot" },
    { name: "shutdown", desc: "Shut down", glyph: "󰐥", command: "omarchy-system-shutdown" },
    { name: "screensaver", desc: "Start the screensaver", glyph: "󱄄", command: "omarchy-launch-screensaver force" },
    { name: "update", desc: "System update (dropdown)", glyph: "󰚰", command: "hyprctl eval 'dropdown_show(\"update\")'" },
    { name: "terminal", desc: "Terminal dropdown", glyph: "\uf120", command: "hyprctl eval 'dropdown_show(\"terminal\")'" },
    { name: "claude", desc: "Claude dropdown", glyph: "󰚩", command: "hyprctl eval 'dropdown_show(\"claude\")'" },
    { name: "files", desc: "Files dropdown", glyph: "󰉋", command: "hyprctl eval 'dropdown_show(\"files\")'" },
    { name: "btop", desc: "System monitor dropdown", glyph: "󰄨", command: "hyprctl eval 'dropdown_show(\"btop\")'" },
    { name: "screenshot", desc: "Screenshot a region", glyph: "󰹑", command: "sleep 0.3; omarchy-capture-screenshot region" },
    { name: "dnd", desc: "Toggle Do Not Disturb", glyph: "󰂛", command: "omarchy-shell notifications toggleDnd" },
    { name: "clear", desc: "Clear all notifications", glyph: "󰎟", command: "omarchy-shell -q notifications dismissAll; sleep 0.6; omarchy-shell -q notifications clear" },
    { name: "tailscale", desc: "Toggle Tailscale", glyph: "󰖂", command: "~/.local/bin/tailscale-toggle" },
    { name: "vpn", desc: "Mullvad dropdown", glyph: "󰦝", command: "hyprctl eval 'dropdown_show(\"vpn\")'" },
    { name: "lab", desc: "Remote desktop (Remmina)", glyph: "󰢹", command: "uwsm-app -- remmina", lab: true },
    { name: "keys", desc: "Keybindings", glyph: "󰌌", command: "omarchy-shell shell summon omarchy.menu '{\"menu\":\"root\",\"keys\":true}'" },
    { name: "restart-shell", desc: "Restart the Omarchy shell", glyph: "󰑓", command: "omarchy-restart-shell" }
  ].filter(function(c) { return !(c.lab && root.guest) })
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  // Hidden the same way the launcher hides them.
  property var configuredHidden: ({})
  property var sessionHidden: ({})

  function open(payloadJson) {
    root.query = ""
    root.selected = 0
    root.rebuild()
    root.opened = true
    root.takeKeys()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  // The info bar (daa.infobar) sits at the bottom of the screen for as long
  // as the box is open, above the dimmed backdrop (mapped after it).
  onOpenedChanged: Quickshell.execDetached(["omarchy-shell", "-q", "daa.infobar", opened ? "pin" : "hide"])

  function close() {
    root.opened = false
  }

  // Something else took over (a keybind or another launcher opened an app
  // or showed a dropdown): get out of the way, info bar and all. Switching
  // workspace doesn't count -- Tab does that from here.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.opened) return
      var name = event.name, data = String(event.data || "")
      if (name === "openwindow" || (name === "activespecialv2" && data.charAt(0) !== ","))
        root.dismiss()
    }
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "daa.search")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
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

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.charAt(0) === "/") return "file://" + value
    var themed = value ? Quickshell.iconPath(value, true) : ""
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  // Apps whose name starts with the query first, then name contains, then
  // generic name / keywords; alphabetical within each.
  function rebuild() {
    var q = root.query.trim().toLowerCase()
    var list = []
    if (q.charAt(0) === "/") {
      // Commands: name prefix first, then name or description contains.
      var term = q.slice(1)
      var hits = []
      for (var c = 0; c < root.commands.length; c++) {
        var cmd = root.commands[c]
        var r = cmd.name.indexOf(term) === 0 ? 0 : cmd.name.indexOf(term) !== -1 ? 1
          : cmd.desc.toLowerCase().indexOf(term) !== -1 ? 2 : -1
        if (r >= 0) hits.push({ kind: "command", label: "/" + cmd.name, detail: cmd.desc, glyph: cmd.glyph, command: cmd.command, rank: r, order: c })
      }
      // Ties keep the order of the list above.
      hits.sort(function(a, b) { return a.rank !== b.rank ? a.rank - b.rank : a.order - b.order })
      list = hits
      var typed = root.query.trim().slice(1).trim()
      // Anything that isn't exactly a built-in can run as a shell command.
      var exact = hits.length && hits[0].label === "/" + term
      if (typed && !exact) list.push({ kind: "shell", label: "Run “" + typed + "” in a terminal", glyph: "\uf120", command: typed })
    } else if (q) {
      var apps = []
      var values = DesktopEntries.applications.values || []
      for (var i = 0; i < values.length; i++) {
        var e = values[i]
        if (!e || e.noDisplay || !e.name) continue
        var id = String(e.id || "")
        if (!id || root.configuredHidden[id] || root.sessionHidden[id]) continue
        var name = String(e.name), lower = name.toLowerCase()
        var extra = (String(e.genericName || "") + " " + (e.keywords || []).join(" ")).toLowerCase()
        var rank = lower.indexOf(q) === 0 ? 0 : lower.indexOf(q) !== -1 ? 1 : extra.indexOf(q) !== -1 ? 2 : -1
        if (rank < 0) continue
        apps.push({ kind: "app", id: id, label: name, icon: String(e.icon || ""), rank: rank, key: lower,
          detail: String(e.genericName || "") })
      }
      apps.sort(function(a, b) { return a.rank !== b.rank ? a.rank - b.rank : (a.key < b.key ? -1 : a.key > b.key ? 1 : 0) })
      list = apps.slice(0, root.maxApps)
      var text = root.query.trim()
      list.push({ kind: "files", label: "Search files for “" + text + "”", glyph: "󰍉" })
      list.push({ kind: "web", label: "Search the web for “" + text + "”", glyph: "󰖟" })
    }
    root.results = list
    root.selected = 0
  }

  function run(index) {
    if (root.query.trim().toLowerCase() === "/comets") {
      root.query = ""; input.text = ""; root.rebuild(); storm.start(); return
    }
    if (index < 0 || index >= root.results.length) return
    var row = root.results[index]
    var text = root.query.trim()
    root.dismiss()
    if (row.kind === "app")
      Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", row.id + ".desktop"])
    else if (row.kind === "files")
      Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/file-search", text])
    else if (row.kind === "command")
      Quickshell.execDetached(["bash", "-lc", row.command])
    else if (row.kind === "shell")
      Quickshell.execDetached(["uwsm-app", "--", "alacritty", "--hold", "-e", "bash", "-lc", row.command])
    else if (row.kind === "web")
      Quickshell.execDetached(["omarchy-launch-browser", "https://duckduckgo.com/?q=" + encodeURIComponent(text)])
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

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-search"
    WlrLayershell.layer: WlrLayer.Overlay
    // On demand, so the info bar under the box still gets the mouse (an
    // exclusive layer takes all pointer input). Exclusive only in short
    // pulses to (re)take the keyboard: on open, and after a workspace switch
    // hands focus to a window there.
    WlrLayershell.keyboardFocus: root.grabKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: if (visible) popIn.restart()

    // Drops a little and fades in, the screen dimming behind it.
    ParallelAnimation {
      id: popIn
      NumberAnimation { target: dim; property: "opacity"; from: 0; to: 1; duration: 160 }
      NumberAnimation { target: box; property: "opacity"; from: 0; to: 1; duration: 120 }
      NumberAnimation { target: boxShift; property: "y"; from: -Style.space(10); to: 0; duration: 180; easing.type: Easing.OutCubic }
    }

    Rectangle {
      id: dim
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    // The comet storm: 16 comets fly in from the edges on curving paths
    // (each turns at its own rate, wobbling), white heads, coloured tails
    // fading behind, for ~4.5 s; then they fade out.
    Canvas {
      id: storm
      anchors.fill: parent
      visible: running || fade > 0
      property bool running: false
      property real t: 0
      property real fade: 0
      property var comets: []
      readonly property var palette: [Commons.Color.accent, Commons.Color.urgent, "#9ece6a", "#bb9af7", "#e0af68", "#7aa2f7", "#73daca"]

      function start() {
        var list = []
        for (var i = 0; i < 16; i++) {
          var edge = Math.floor(Math.random() * 4)
          var x = edge === 0 ? -20 : edge === 1 ? width + 20 : Math.random() * width
          var y = edge === 2 ? -20 : edge === 3 ? height + 20 : Math.random() * height
          // Aimed roughly at the middle, so they cross the screen.
          var aim = Math.atan2(height / 2 - y, width / 2 - x) + (Math.random() - 0.5) * 1.2
          list.push({ x: x, y: y, a: aim, speed: 520 + Math.random() * 420,
            turn: (Math.random() - 0.5) * 3.2, wob: Math.random() * 6, delay: Math.random() * 1.4,
            color: Qt.color(palette[i % palette.length]), trail: [] })
        }
        comets = list
        t = 0
        fade = 1
        running = true
      }

      FrameAnimation {
        running: storm.running && root.opened
        onTriggered: {
          var dt = Math.min(0.05, frameTime)
          storm.t += dt
          for (var i = 0; i < storm.comets.length; i++) {
            var c = storm.comets[i]
            if (storm.t < c.delay) continue
            c.a += (c.turn + Math.sin((storm.t + c.wob) * 3) * 1.4) * dt
            c.x += Math.cos(c.a) * c.speed * dt
            c.y += Math.sin(c.a) * c.speed * dt
            c.trail.push({ x: c.x, y: c.y })
            if (c.trail.length > 26) c.trail.shift()
          }
          if (storm.t > 4.5) storm.fade = Math.max(0, 1 - (storm.t - 4.5) / 0.6)
          if (storm.t > 5.1) storm.running = false
          storm.requestPaint()
        }
      }
      onRunningChanged: if (!running) { fade = 0; requestPaint() }

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (!running) return
        ctx.lineCap = "round"
        for (var i = 0; i < comets.length; i++) {
          var c = comets[i], tr = c.trail, n = tr.length
          for (var j = 1; j < n; j++) {
            var k = j / n                       // 0 tail .. 1 head
            var w = k > 0.92 ? 1 : 0             // white tip
            var r = c.color.r + (1 - c.color.r) * w, g = c.color.g + (1 - c.color.g) * w, b = c.color.b + (1 - c.color.b) * w
            // Glow, then the beam.
            ctx.lineWidth = 9
            ctx.strokeStyle = Qt.rgba(r, g, b, 0.12 * k * fade)
            ctx.beginPath(); ctx.moveTo(tr[j - 1].x, tr[j - 1].y); ctx.lineTo(tr[j].x, tr[j].y); ctx.stroke()
            ctx.lineWidth = 1 + 2.5 * k
            ctx.strokeStyle = Qt.rgba(r, g, b, Math.pow(k, 1.4) * fade)
            ctx.beginPath(); ctx.moveTo(tr[j - 1].x, tr[j - 1].y); ctx.lineTo(tr[j].x, tr[j].y); ctx.stroke()
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: box
      width: Style.space(460)
      height: column.implicitHeight + Style.space(16)
      x: Math.round((parent.width - width) / 2)
      y: Math.round(parent.height * 0.18)
      radius: Style.space(14)
      color: root.background
      transform: Translate { id: boxShift }

      // Clicks inside the box don't close it.
      MouseArea { anchors.fill: parent }

      // Breathing border: the window border's accent → coral gradient, drawn
      // once, its opacity slowly rising and falling.
      Canvas {
        anchors.fill: parent
        z: 10
        property real breath: 0.35
        SequentialAnimation on breath {
          running: root.opened
          loops: Animation.Infinite
          NumberAnimation { to: 1; duration: 1700; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0.35; duration: 1700; easing.type: Easing.InOutSine }
        }
        opacity: breath
        // Repaint when the palette changes (theme switch, ABACABB blood mode).
        property color from: Commons.Color.accent
        property color to: Commons.Color.urgent
        onFromChanged: requestPaint()
        onToChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var lw = 1.5, o = lw / 2, r = Math.max(0, box.radius - o)
          var w = width - lw, h = height - lw
          var grad = ctx.createLinearGradient(0, 0, width, height)
          grad.addColorStop(0, from)
          grad.addColorStop(1, to)
          ctx.strokeStyle = grad
          ctx.lineWidth = lw
          ctx.beginPath()
          ctx.moveTo(o + r, o)
          ctx.arcTo(o + w, o, o + w, o + h, r)
          ctx.arcTo(o + w, o + h, o, o + h, r)
          ctx.arcTo(o, o + h, o, o, r)
          ctx.arcTo(o, o, o + w, o, r)
          ctx.closePath()
          ctx.stroke()
        }
      }

      Column {
        id: column
        x: Style.space(8)
        y: Style.space(8)
        width: parent.width - Style.space(16)
        spacing: Style.space(4)

        // 󰍉 search…
        Item {
          width: parent.width
          height: Style.space(36)

          Text {
            id: lens
            x: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            color: root.foreground
            opacity: 0.6
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.heading
          }

          TextInput {
            id: input
            anchors.left: lens.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            selectionColor: root.selectedBackground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            clip: true
            focus: true
            text: root.query
            onTextEdited: {
              if (text.trim().toLowerCase() === "abacabb") {
                text = ""
                root.query = ""
                root.rebuild()
                root.blood()
                return
              }
              root.query = text
              root.rebuild()
            }

            Text {
              visible: input.text === ""
              anchors.verticalCenter: parent.verticalCenter
              text: "Search apps, files, the web…  / for commands"
              color: root.foreground
              opacity: 0.4
              font: input.font
            }

            // Something took the keyboard while the box is open (an app
            // asking for attention, a focus change from elsewhere): take it
            // back, unless the box is closing.
            onActiveFocusChanged: if (!activeFocus && root.opened) refocus.restart()
            Keys.onPressed: function(event) {
              root.konamiKey(event.key)
              if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
              // Tab / Shift+Tab: next / previous desktop (the info bar
              // below shows which); the box stays open.
              else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                var back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
                Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + (back ? "e-1" : "e+1") + "\" })"])
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                if (root.results.length) root.selected = (root.selected + 1) % root.results.length
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                if (root.results.length) root.selected = (root.selected - 1 + root.results.length) % root.results.length
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.run(root.selected)
                event.accepted = true
              }
            }
          }
        }

        Rectangle {
          visible: root.results.length > 0
          width: parent.width
          height: 1
          color: Qt.rgba(1, 1, 1, 0.08)
        }

        Repeater {
          model: root.results

          Rectangle {
            id: rowItem
            required property var modelData
            required property int index
            readonly property bool current: index === root.selected
            width: column.width
            height: Style.space(34)
            radius: Style.space(8)
            color: current ? root.selectedBackground : rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

            Image {
              id: appIcon
              visible: rowItem.modelData.kind === "app"
              x: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              height: width
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              source: visible ? root.iconSource(rowItem.modelData.icon) : ""
              asynchronous: true
            }
            Text {
              visible: rowItem.modelData.kind !== "app"
              x: Style.space(8)
              width: Style.space(20)
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignHCenter
              text: rowItem.modelData.glyph || ""
              color: rowItem.current ? root.selectedText : root.foreground
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.heading
            }

            Text {
              id: detail
              visible: !!rowItem.modelData.detail && rowItem.modelData.kind === "command"
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: rowItem.modelData.detail || ""
              color: rowItem.current ? root.selectedText : root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.left: appIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.right: detail.visible ? detail.left : parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: rowItem.modelData.label
              color: rowItem.current ? root.selectedText : root.foreground
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: rowArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.run(rowItem.index)
            }
          }
        }
      }
    }
  }
}
