import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Scratchpad builder (Desktop settings → Scratchpads). Makes your own
// dropdowns without knowing window classes:
//   1. which app: point at an open window (the zap scope in pick mode),
//      launch a command and see which window appears, or type the class;
//   2. shape: size, where it sits, which way it slides in, a shortcut;
//   3. Test (it opens as a real dropdown; move / resize it, reopen settings,
//      Capture) and Save.
// Saved to ~/.config/hypr/dropdowns_user.json; ~/.local/bin/scratch-tool turns
// that into dropdowns_user.lua, which hypr/dropdowns.lua loads.
Column {
  id: page

  property var host: null       // the settings panel (Settings.qml root)
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property string jsonPath: Quickshell.env("HOME") + "/.config/hypr/dropdowns_user.json"

  spacing: Style.space(4)

  property var items: []
  property bool editing: false
  property int editIndex: -1      // -1 = new
  property string note: ""        // guidance under the form
  property string status: ""      // last action's result
  property var form: blank()

  function blank() {
    return { name: "", label: "", cmd: "", match: "", key: "", w: 900, h: 600, position: "center", x: 0,
      margin: 10, y: 50, slide: "top", preload: false, quitOnHide: false, terminal: false }
  }
  function setField(k, v) {
    var f = {}
    for (var key in page.form) f[key] = page.form[key]
    f[k] = v
    page.form = f
    page.guide()
  }
  function slug(s) { return String(s || "").toLowerCase().replace(/^.*\./, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 24) }

  // ---- storage ----
  FileView {
    id: store
    path: page.jsonPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { page.items = JSON.parse(text() || "[]") } catch (e) { page.items = [] } }
    onLoadFailed: page.items = []
  }
  Process {
    id: writer
    command: [Quickshell.env("HOME") + "/.local/bin/scratch-tool", "write"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(text) } catch (e) {}
        page.status = r.ok ? "Saved. Hyprland reloaded." : "Hyprland reported: " + (r.errors || "an error")
        if (r.ok && page.afterWrite) { var f = page.afterWrite; page.afterWrite = null; f() }
      }
    }
  }
  property var afterWrite: null
  // scratch-tool saves the JSON and regenerates the Lua in one go.
  function writeList(list) {
    writer.command = [Quickshell.env("HOME") + "/.local/bin/scratch-tool", "write", JSON.stringify(list)]
    writer.running = true
  }

  function entryFromForm() {
    var f = page.form
    var name = page.slug(f.name || f.label || f.match)
    var e = { name: name, label: f.label || name, cmd: f.cmd, match: f.match, key: f.key, w: Math.round(f.w), h: Math.round(f.h),
      position: f.position, margin: Math.round(f.margin), y: Math.round(f.y), slide: f.slide,
      preload: !!f.preload, quitOnHide: !!f.quitOnHide }
    if (f.position === "custom") e.x = Math.round(f.x)
    if (f.terminal) {
      // TUI apps: run in Alacritty with a class of their own to claim.
      e.cmd = "alacritty --class dropdown-user." + name + " -e " + f.cmd
      e.match = "dropdown-user." + name
    }
    return e
  }
  function problems() {
    var f = page.form
    if (!f.cmd) return "Needs a command to launch it."
    if (!f.terminal && !f.match) return "Needs the window class: pick a window, use Detect, or type it."
    var name = page.slug(f.name || f.label || f.match)
    if (!name) return "Needs a name."
    var builtin = ["terminal", "claude", "btop", "files", "search", "bitwarden", "weather", "vpn", "mullvad", "update"]
    if (builtin.indexOf(name) !== -1) return "\"" + name + "\" is a built-in dropdown's name; pick another."
    for (var i = 0; i < page.items.length; i++)
      if (i !== page.editIndex && page.items[i].name === name) return "You already have a scratchpad called \"" + name + "\"."
    return ""
  }
  function save(then) {
    var p = page.problems()
    if (p) { page.status = p; return }
    var list = page.items.slice()
    var e = page.entryFromForm()
    if (page.editIndex >= 0) list[page.editIndex] = e
    else { list.push(e); page.editIndex = list.length - 1 }
    page.items = list
    page.afterWrite = then || null
    page.writeList(list)
  }
  function remove(i) {
    var list = page.items.slice()
    list.splice(i, 1)
    page.items = list
    page.writeList(list)
  }
  function edit(i) {
    var e = page.items[i]
    var f = page.blank()
    for (var k in e) f[k] = e[k]
    f.terminal = false
    page.form = f
    page.editIndex = i
    page.editing = true
    page.status = ""
    page.guide()
  }
  function startNew() {
    page.form = page.blank()
    page.editIndex = -1
    page.editing = true
    page.status = ""
    page.note = "Start with the app: point at its window, or give a command and Detect."
  }

  // Test: save, close settings, show it. Reopen settings to Capture.
  function test() {
    page.save(function() {
      var name = page.entryFromForm().name
      if (page.host) page.host.dismiss()
      Quickshell.execDetached(["bash", "-c", "sleep 0.4; ~/.local/bin/scratch-tool show \"$1\"; notify-send -u low 'Scratchpad test' " +
        "'Move or resize it, then reopen Desktop settings (SUPER+CTRL+ALT+S) and press Capture.'", "--", name])
    })
  }

  // ---- finding the app ----
  function pick() {
    if (page.host) page.host.dismiss()
    Quickshell.execDetached(["bash", "-c", "sleep 0.3; omarchy-shell shell summon daa.zap '{\"mode\":\"pick\"}'"])
  }
  // Called by Settings.qml when the zap picker hands a window back.
  FileView {
    id: pickedFile
    path: Quickshell.env("HOME") + "/.local/state/daa/picked.json"
    printErrors: false
  }
  function loadPicked() {
    pickedFile.reload()
    pickTimer.restart()
  }
  Timer {
    id: pickTimer
    interval: 150
    onTriggered: {
      var r = {}
      try { r = JSON.parse(pickedFile.text() || "{}") } catch (e) {}
      if (!r.ok) { page.status = r.error || "Nothing was picked."; return }
      if (!page.editing) page.startNew()
      var f = page.form
      var next = {}
      for (var k in f) next[k] = f[k]
      next.match = r["class"]
      next.cmd = next.cmd || page.cleanCmd(r.cmd)
      next.label = next.label || r.title
      next.name = next.name || page.slug(r["class"])
      next.w = Math.min(r.w, 1400); next.h = Math.min(r.h, 900)
      page.form = next
      page.status = "Picked " + r["class"] + "."
      page.guide()
    }
  }
  // /usr/lib/... electron paths and the like are kept; only argv[0]'s path
  // is trimmed when it's an ordinary command on PATH.
  function cleanCmd(c) {
    c = String(c || "")
    return c.replace(/^\/usr\/bin\//, "")
  }
  Process {
    id: detector
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(text) } catch (e) {}
        if (!r.ok) { page.status = r.error || "Detect failed."; return }
        var f = {}
        for (var k in page.form) f[k] = page.form[k]
        f.match = r["class"]
        f.label = f.label || r.title
        f.name = f.name || page.slug(r["class"])
        page.form = f
        page.status = "Detected " + r["class"] + ". Its window is open now; Test will claim the next one it launches."
        page.guide()
      }
    }
  }
  function detect() {
    if (!page.form.cmd) { page.status = "Type the command first."; return }
    page.status = "Launching " + page.form.cmd + "…"
    detector.command = [Quickshell.env("HOME") + "/.local/bin/scratch-tool", "detect", page.form.cmd]
    detector.running = true
  }
  Process {
    id: capturer
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(text) } catch (e) {}
        if (!r.ok) { page.status = r.error || "Capture failed."; return }
        var f = {}
        for (var k in page.form) f[k] = page.form[k]
        f.w = r.w; f.h = r.h; f.y = r.y
        if (r.right <= 40) { f.position = "right"; f.margin = Math.max(0, r.right) }
        else { f.position = "custom"; f.x = r.x }
        page.form = f
        page.status = "Captured " + r.w + "×" + r.h + " at " + r.x + ", " + r.y + ". Save to keep it."
      }
    }
  }
  function capture() {
    var cls = page.form.terminal ? "dropdown-user." + page.slug(page.form.name || page.form.label) : page.form.match
    if (!cls) { page.status = "Needs the window class first."; return }
    capturer.command = [Quickshell.env("HOME") + "/.local/bin/scratch-tool", "capture", cls]
    capturer.running = true
  }

  // Plain-language hints for the tricky cases.
  readonly property var singleInstance: ["org.gnome.Nautilus", "org.gnome.Ptyxis", "Bitwarden", "firefox", "chromium",
    "brave-browser", "obsidian", "Spotify", "discord", "org.gnome.Calendar", "org.gnome.Weather"]
  readonly property var trayApps: ["Bitwarden", "mullvad-vpn", "discord", "steam", "org.telegram.desktop", "Signal", "Slack"]
  readonly property var tuiCommands: ["btop", "htop", "top", "nvim", "vim", "lazygit", "ncdu", "ranger", "yazi", "nmtui", "mullvad-tui", "ipcalc", "cmus", "ncmpcpp"]
  function guide() {
    var f = page.form
    var lines = []
    var bin = String(f.cmd || "").trim().split(/\s+/)[0].replace(/^.*\//, "")
    if (!f.terminal && page.tuiCommands.indexOf(bin) !== -1)
      lines.push(bin + " runs in a terminal: switch on \"Run in a terminal\" so it gets a window of its own.")
    if (f.match && bin && f.match.toLowerCase().indexOf(bin.toLowerCase()) === -1 && !f.terminal)
      lines.push("Its window class (" + f.match + ") isn't its command name. That's fine: the dropdown claims windows by class.")
    if (page.singleInstance.indexOf(f.match) !== -1)
      lines.push(f.match + " keeps one copy running: if it's already open when the dropdown first launches it, the existing window may be reused. Close it first.")
    if (page.trayApps.indexOf(f.match) !== -1)
      lines.push(f.match + " hides to the tray when closed: consider \"Quit when hidden\".")
    if (f.key && page.keyClash(f.key))
      lines.push("Shortcut " + f.key + " is already used by: " + page.keyClash(f.key) + ".")
    page.note = lines.join("\n")
  }

  // ---- shortcut clash check (hyprctl binds) ----
  property var binds: []
  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    running: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { try { page.binds = JSON.parse(text) } catch (e) {} } }
  }
  function refreshBinds() { if (!bindsProc.running) bindsProc.running = true }
  function keyClash(combo) {
    var parts = String(combo).split("+").map(function(p) { return p.trim().toUpperCase() })
    var mask = 0, key = ""
    var bits = { SUPER: 64, SHIFT: 1, CTRL: 4, CONTROL: 4, ALT: 8 }
    for (var i = 0; i < parts.length; i++) {
      if (bits[parts[i]] !== undefined) mask |= bits[parts[i]]
      else key = parts[i]
    }
    for (var j = 0; j < page.binds.length; j++) {
      var b = page.binds[j]
      if (b.modmask === mask && String(b.key).toUpperCase() === key && !b.submap)
        return b.description || b.arg || "another binding"
    }
    return ""
  }

  // ======================= UI =======================

  Heading { text: "YOUR SCRATCHPADS" }

  Text {
    visible: page.items.length === 0 && !page.editing
    width: parent.width
    leftPadding: Style.space(10)
    text: "None yet. The built-in dropdowns (terminal, Claude, files…) live in hypr/dropdowns.lua."
    color: page.fg
    opacity: 0.5
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: page.items
    Rectangle {
      id: itemRow
      required property var modelData
      required property int index
      width: page.width
      height: Style.space(40)
      radius: Style.space(8)
      color: itemHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
      HoverHandler { id: itemHover }
      Column {
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        Text { text: itemRow.modelData.label || itemRow.modelData.name; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
        Text {
          text: (itemRow.modelData.key || "no shortcut") + "  ·  " + itemRow.modelData.match
          color: page.fg; opacity: 0.5; font.family: page.font; font.pixelSize: Style.font.caption
        }
      }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        SmallButton { label: "Show"; onClicked: { if (page.host) page.host.dismiss(); Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/scratch-tool", "show", itemRow.modelData.name]) } }
        SmallButton { label: "Edit"; onClicked: page.edit(itemRow.index) }
        SmallButton { label: "Delete"; danger: true; onClicked: page.remove(itemRow.index) }
      }
    }
  }

  SmallButton {
    visible: !page.editing
    x: Style.space(10)
    label: "+  New scratchpad"
    onClicked: page.startNew()
  }

  // ---- the form ----
  Column {
    visible: page.editing
    width: page.width
    spacing: Style.space(4)
    topPadding: Style.space(6)

    Heading { text: page.editIndex >= 0 ? "EDIT SCRATCHPAD" : "NEW SCRATCHPAD" }

    // 1. Which app?
    SubHeading { text: "1  Which app?" }
    Row {
      x: Style.space(10)
      spacing: Style.space(6)
      SmallButton { label: "󰆾  Pick a window"; onClicked: page.pick() }
      SmallButton { label: "Detect from command"; onClicked: page.detect() }
    }
    Field { label: "Command"; hint: "what launches it, e.g. gnome-calculator"; value: page.form.cmd; onEdited: function(v) { page.setField("cmd", v) } }
    Field { label: "Window class"; hint: "filled by Pick / Detect"; value: page.form.match; onEdited: function(v) { page.setField("match", v) } }
    Toggle { label: "Run in a terminal"; hint: "for terminal apps like btop"; on: page.form.terminal; onToggled: page.setField("terminal", !page.form.terminal) }
    Field { label: "Name"; hint: "shown in lists"; value: page.form.label; onEdited: function(v) { page.setField("label", v); page.setField("name", page.slug(v)) } }

    // 2. Shape
    SubHeading { text: "2  Shape" }
    Row {
      x: Style.space(10)
      spacing: Style.space(10)
      NumberField { label: "Width"; value: page.form.w; onEdited: function(v) { page.setField("w", v) } }
      NumberField { label: "Height"; value: page.form.h; onEdited: function(v) { page.setField("h", v) } }
      NumberField { label: "From top"; value: page.form.y; onEdited: function(v) { page.setField("y", v) } }
    }
    Choice {
      label: "Position"
      value: page.form.position
      options: [["center", "Centre"], ["right", "Right edge"], ["custom", "Custom x"]]
      onPicked: function(v) { page.setField("position", v) }
    }
    Row {
      visible: page.form.position === "custom" || page.form.position === "right"
      x: Style.space(10)
      NumberField {
        label: page.form.position === "right" ? "Gap to edge" : "From left"
        value: page.form.position === "right" ? page.form.margin : page.form.x
        onEdited: function(v) { page.setField(page.form.position === "right" ? "margin" : "x", v) }
      }
    }
    Choice {
      label: "Slides in"
      value: page.form.slide
      options: [["top", "From top"], ["right", "From right"], ["left", "From left"], ["bottom", "Rises"], ["fade", "Fade"]]
      onPicked: function(v) { page.setField("slide", v) }
    }

    // 3. Behaviour
    SubHeading { text: "3  Behaviour" }
    KeyField { label: "Shortcut"; value: page.form.key; onCaptured: function(v) { page.setField("key", v) } }
    Toggle { label: "Preload at login"; hint: "hidden, so the first press is instant"; on: page.form.preload; onToggled: page.setField("preload", !page.form.preload) }
    Toggle { label: "Quit when hidden"; hint: "for apps that otherwise live in the tray"; on: page.form.quitOnHide; onToggled: page.setField("quitOnHide", !page.form.quitOnHide) }

    // Guidance and status.
    Text {
      visible: page.note !== ""
      width: page.width - Style.space(20)
      x: Style.space(10)
      topPadding: Style.space(4)
      text: page.note
      color: page.accent
      wrapMode: Text.Wrap
      font.family: page.font
      font.pixelSize: Style.font.caption
    }
    Text {
      visible: page.status !== ""
      width: page.width - Style.space(20)
      x: Style.space(10)
      text: page.status
      color: page.fg
      opacity: 0.75
      wrapMode: Text.Wrap
      font.family: page.font
      font.pixelSize: Style.font.caption
    }

    Row {
      x: Style.space(10)
      topPadding: Style.space(6)
      spacing: Style.space(6)
      SmallButton { label: "Test"; onClicked: page.test() }
      SmallButton { label: "Capture size"; onClicked: page.capture() }
      SmallButton { label: "Save"; primary: true; onClicked: page.save(function() { page.editing = false }) }
      SmallButton { label: "Cancel"; onClicked: { page.editing = false; page.status = "" } }
    }
  }

  // ======================= pieces =======================

  component Heading: Text {
    topPadding: Style.space(8)
    color: page.fg
    opacity: 0.5
    font.family: page.font
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }
  component SubHeading: Text {
    x: Style.space(10)
    topPadding: Style.space(8)
    color: page.accent
    font.family: page.font
    font.pixelSize: Style.font.body
    font.bold: true
  }

  component SmallButton: Rectangle {
    id: btn
    property string label: ""
    property bool danger: false
    property bool primary: false
    signal clicked()
    width: btnLabel.implicitWidth + Style.space(18)
    height: Style.space(26)
    radius: Style.space(8)
    color: primary ? page.accent
      : btnArea.containsMouse ? Util.alpha(danger ? Commons.Color.urgent : page.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: btn.primary ? Commons.Color.background : btnArea.containsMouse && btn.danger ? Commons.Color.urgent : page.fg
      font.family: page.font
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }

  component Field: Item {
    id: field
    property string label: ""
    property string hint: ""
    property string value: ""
    signal edited(string v)
    width: page.width
    height: Style.space(34)
    Text {
      x: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(120)
      text: field.label
      color: page.fg
      font.family: page.font
      font.pixelSize: Style.font.body
    }
    Rectangle {
      x: Style.space(130)
      width: parent.width - Style.space(140)
      height: Style.space(28)
      anchors.verticalCenter: parent.verticalCenter
      radius: Style.space(6)
      color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.1 : 0.06)
      TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: page.fg
        font.family: page.font
        font.pixelSize: Style.font.bodySmall
        text: field.value
        onTextEdited: field.edited(text)
        Keys.onEscapePressed: if (page.host) page.host.dismiss()
        Text {
          visible: input.text === ""
          anchors.verticalCenter: parent.verticalCenter
          text: field.hint
          color: page.fg
          opacity: 0.35
          font: input.font
        }
      }
    }
  }

  component NumberField: Row {
    id: nf
    property string label: ""
    property real value: 0
    signal edited(real v)
    spacing: Style.space(6)
    Text { anchors.verticalCenter: parent.verticalCenter; text: nf.label; color: page.fg; opacity: 0.7; font.family: page.font; font.pixelSize: Style.font.bodySmall }
    Rectangle {
      width: Style.space(64)
      height: Style.space(28)
      radius: Style.space(6)
      color: Qt.rgba(1, 1, 1, numIn.activeFocus ? 0.1 : 0.06)
      TextInput {
        id: numIn
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        verticalAlignment: TextInput.AlignVCenter
        color: page.fg
        font.family: page.font
        font.pixelSize: Style.font.bodySmall
        validator: IntValidator { bottom: 0; top: 9999 }
        text: String(Math.round(nf.value))
        onTextEdited: if (text !== "") nf.edited(Number(text))
      }
    }
  }

  component Toggle: Item {
    id: tg
    property string label: ""
    property string hint: ""
    property bool on: false
    signal toggled()
    width: page.width
    height: Style.space(hint ? 40 : 32)
    Column {
      x: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      Text { text: tg.label; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
      Text { visible: tg.hint !== ""; text: tg.hint; color: page.fg; opacity: 0.5; font.family: page.font; font.pixelSize: Style.font.caption }
    }
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(40); height: Style.space(22)
      radius: height / 2
      color: tg.on ? page.accent : Qt.rgba(1, 1, 1, 0.14)
      Rectangle {
        width: parent.height - Style.space(6); height: width; radius: width / 2
        y: Style.space(3)
        x: tg.on ? parent.width - width - Style.space(3) : Style.space(3)
        color: tg.on ? Commons.Color.background : page.fg
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
  }

  component Choice: Item {
    id: ch
    property string label: ""
    property string value: ""
    property var options: []
    signal picked(string v)
    width: page.width
    height: Style.space(34)
    Text { x: Style.space(10); anchors.verticalCenter: parent.verticalCenter; text: ch.label; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
      Repeater {
        model: ch.options
        Rectangle {
          id: pill
          required property var modelData
          readonly property bool current: ch.value === modelData[0]
          width: pillText.implicitWidth + Style.space(16)
          height: Style.space(24)
          radius: height / 2
          color: current ? page.accent : pillArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
          Text { id: pillText; anchors.centerIn: parent; text: pill.modelData[1]; color: pill.current ? Commons.Color.background : page.fg; font.family: page.font; font.pixelSize: Style.font.bodySmall }
          MouseArea { id: pillArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.picked(pill.modelData[0]) }
        }
      }
    }
  }

  // Shortcut capture: click, then press the combination. While it listens,
  // Hyprland's "capture" submap (hypr/bindings.lua) switches all bindings
  // off, so even a combination that's taken reaches here (and is flagged).
  component KeyField: Item {
    id: kf
    property string label: ""
    property string value: ""
    property bool listening: false
    signal captured(string v)
    width: page.width
    height: Style.space(34)
    function stop() {
      if (!kf.listening) return
      kf.listening = false
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"])
    }
    Text { x: Style.space(10); anchors.verticalCenter: parent.verticalCenter; text: kf.label; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
    Rectangle {
      id: keyBox
      x: Style.space(130)
      width: Style.space(220)
      height: Style.space(28)
      anchors.verticalCenter: parent.verticalCenter
      radius: Style.space(6)
      color: kf.listening ? Util.alpha(page.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
      border.width: kf.listening ? 1 : 0
      border.color: page.accent
      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(8)
        text: kf.listening ? "Press the keys…  (Esc cancels)" : (kf.value || "Click to set")
        color: page.fg
        opacity: kf.value || kf.listening ? 1 : 0.4
        font.family: page.font
        font.pixelSize: Style.font.bodySmall
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          kf.listening = true
          page.refreshBinds()
          Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"capture\")"])
          catcher.forceActiveFocus()
        }
      }
      Item {
        id: catcher
        focus: kf.listening
        onActiveFocusChanged: if (!activeFocus) kf.stop()
        Keys.onPressed: function(event) {
          event.accepted = true
          var k = event.key
          if (k === Qt.Key_Escape) { kf.stop(); return }
          if (k === Qt.Key_Backspace || k === Qt.Key_Delete) { kf.captured(""); kf.stop(); return }
          // Wait for a real key, not a lone modifier.
          if (k === Qt.Key_Shift || k === Qt.Key_Control || k === Qt.Key_Alt || k === Qt.Key_Meta || k === Qt.Key_Super_L || k === Qt.Key_Super_R) return
          var mods = []
          if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
          if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
          if (event.modifiers & Qt.AltModifier) mods.push("ALT")
          if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
          var names = {}
          names[Qt.Key_Space] = "SPACE"; names[Qt.Key_Return] = "RETURN"; names[Qt.Key_Enter] = "RETURN"; names[Qt.Key_Tab] = "TAB"
          names[Qt.Key_Left] = "LEFT"; names[Qt.Key_Right] = "RIGHT"; names[Qt.Key_Up] = "UP"; names[Qt.Key_Down] = "DOWN"
          names[Qt.Key_Comma] = "comma"; names[Qt.Key_Period] = "period"; names[Qt.Key_Slash] = "slash"; names[Qt.Key_Minus] = "minus"
          names[Qt.Key_Equal] = "equal"; names[Qt.Key_Semicolon] = "semicolon"; names[Qt.Key_Apostrophe] = "apostrophe"
          names[Qt.Key_BracketLeft] = "bracketleft"; names[Qt.Key_BracketRight] = "bracketright"; names[Qt.Key_Backslash] = "backslash"
          names[Qt.Key_QuoteLeft] = "grave"
          var key = names[k]
          if (!key && k >= Qt.Key_F1 && k <= Qt.Key_F12) key = "F" + (k - Qt.Key_F1 + 1)
          // Digits by keycode, like Omarchy's own workspace bindings.
          if (!key && k >= Qt.Key_0 && k <= Qt.Key_9) key = "code:" + (k === Qt.Key_0 ? 19 : k - Qt.Key_0 + 9)
          if (!key && k >= Qt.Key_A && k <= Qt.Key_Z) key = String.fromCharCode(k)
          if (!key) return
          kf.captured(mods.concat([key]).join(" + "))
          kf.stop()
        }
      }
    }
  }
}
