import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Keys menu (Desktop settings → Keys): every keybinding, searchable. Click a
// shortcut and press the new keys to move it; a clash is flagged before it's
// applied. Reset puts one back, Disable switches one off.
// Bindings come from the registry in hypr/keys_registry.lua (via
// ~/.local/bin/keys-tool list); changes are saved to hypr/keys_user.json and
// re-bound by daa_apply_key_overrides() at the end of hyprland.lua.
// keys-tool rolls a change back if Hyprland rejects it or loses bindings.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily

  spacing: Style.space(4)

  property var rows: []
  property var overrides: []
  property string filter: ""
  property string status: ""
  property bool loading: false
  // Pending clash: { row, keys, clashWith } waiting for Replace / Cancel.
  property var pending: null

  function norm(keys) {
    var mods = [], key = ""
    var parts = String(keys).split("+")
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim().toUpperCase()
      if (p === "SUPER" || p === "SHIFT" || p === "CTRL" || p === "CONTROL" || p === "ALT") mods.push(p === "CONTROL" ? "CTRL" : p)
      else if (p) key = p
    }
    mods.sort()
    return mods.concat([key]).join("+")
  }
  // "SUPER + code:10" reads as "SUPER + 1".
  function pretty(keys) {
    return String(keys).replace(/code:(\d+)/, function(m, n) { n = Number(n); return n >= 10 && n <= 18 ? String(n - 9) : n === 19 ? "0" : m })
  }

  function reload() {
    if (lister.running) return
    page.loading = true
    lister.running = true
    if (!overridesFile.loaded) overridesFile.reload()
  }
  Component.onCompleted: reload()

  Process {
    id: lister
    command: [Quickshell.env("HOME") + "/.local/bin/keys-tool", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { page.loading = false; try { page.rows = JSON.parse(text) } catch (e) {} }
    }
  }
  FileView {
    id: overridesFile
    path: Quickshell.env("HOME") + "/.config/hypr/keys_user.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { page.overrides = JSON.parse(text() || "[]") } catch (e) { page.overrides = [] } }
    onLoadFailed: page.overrides = []
  }
  Process {
    id: writer
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(text) } catch (e) {}
        page.status = r.ok ? "Done. Hyprland reloaded (" + r.binds + " bindings)." : (r.error || "Something went wrong.")
        page.reload()
      }
    }
  }
  function save(list) {
    page.overrides = list
    page.status = "Applying…"
    writer.command = [Quickshell.env("HOME") + "/.local/bin/keys-tool", "write", JSON.stringify(list)]
    writer.running = true
  }

  // The binding's original keys (before any change made here).
  function originalOf(row) { return row.from || row.keys }

  function clashFor(keys, exceptRow) {
    var n = page.norm(keys)
    for (var i = 0; i < page.rows.length; i++) {
      var r = page.rows[i]
      if (r === exceptRow || r.disabled) continue
      if (page.norm(r.keys) === n) return r
    }
    return null
  }
  function requestMove(row, keys) {
    if (!keys) return
    var c = page.clashFor(keys, row)
    if (c) { page.pending = { row: row, keys: keys, clashWith: c }; return }
    page.move(row, keys)
  }
  function move(row, keys) {
    page.pending = null
    var orig = page.originalOf(row)
    var list = page.overrides.filter(function(o) { return o.from !== orig })
    if (page.norm(keys) !== page.norm(orig)) list.push({ from: orig, to: keys, description: row.description })
    page.save(list)
  }
  function reset(row) {
    var orig = page.originalOf(row)
    page.save(page.overrides.filter(function(o) { return o.from !== orig }))
  }
  function disable(row) {
    var orig = page.originalOf(row)
    var list = page.overrides.filter(function(o) { return o.from !== orig })
    list.push({ from: orig, disable: true, description: row.description })
    page.save(list)
  }

  readonly property var shown: {
    var f = page.filter.trim().toLowerCase()
    var out = []
    for (var i = 0; i < page.rows.length; i++) {
      var r = page.rows[i]
      if (f && (r.description + " " + page.pretty(r.keys) + " " + r.keys).toLowerCase().indexOf(f) === -1) continue
      out.push(r)
      if (out.length >= 80) break
    }
    return out
  }

  // ======================= UI =======================

  // Search + Reset all
  Item {
    width: page.width
    height: Style.space(40)
    Rectangle {
      x: Style.space(10)
      width: parent.width - resetAll.width - Style.space(30)
      height: Style.space(32)
      anchors.verticalCenter: parent.verticalCenter
      radius: Style.space(8)
      color: Qt.rgba(1, 1, 1, 0.06)
      Text { x: Style.space(10); anchors.verticalCenter: parent.verticalCenter; text: "󰍉"; color: page.fg; opacity: 0.6; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.body }
      TextInput {
        id: search
        anchors.left: parent.left
        anchors.leftMargin: Style.space(34)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        color: page.fg
        font.family: page.font
        font.pixelSize: Style.font.body
        clip: true
        text: page.filter
        onTextEdited: page.filter = text
        Keys.onEscapePressed: if (page.host) page.host.dismiss()
        Text { visible: search.text === ""; text: "Search " + page.rows.length + " bindings…"; color: page.fg; opacity: 0.4; font: search.font }
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: search.forceActiveFocus() }
    }
    SmallButton {
      id: resetAll
      visible: page.overrides.length > 0
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      label: "Reset all (" + page.overrides.length + ")"
      danger: true
      onClicked: page.save([])
    }
  }

  Text {
    visible: page.status !== ""
    x: Style.space(10)
    width: page.width - Style.space(20)
    text: page.status
    color: page.fg
    opacity: 0.75
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.caption
  }

  // Clash confirmation.
  Rectangle {
    visible: page.pending !== null
    x: Style.space(10)
    width: page.width - Style.space(20)
    height: clashCol.implicitHeight + Style.space(16)
    radius: Style.space(8)
    color: Util.alpha(Commons.Color.urgent, 0.12)
    border.width: 1
    border.color: Util.alpha(Commons.Color.urgent, 0.6)
    Column {
      id: clashCol
      x: Style.space(10)
      y: Style.space(8)
      width: parent.width - Style.space(20)
      spacing: Style.space(6)
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: page.pending ? page.pretty(page.pending.keys) + " is already \"" + (page.pending.clashWith.description || "another binding")
          + "\". Use it for \"" + page.pending.row.description + "\" instead? (\"" + (page.pending.clashWith.description || "the other one") + "\" loses its shortcut.)" : ""
        color: page.fg
        font.family: page.font
        font.pixelSize: Style.font.bodySmall
      }
      Row {
        spacing: Style.space(6)
        SmallButton { label: "Replace"; danger: true; onClicked: page.move(page.pending.row, page.pending.keys) }
        SmallButton { label: "Cancel"; onClicked: page.pending = null }
      }
    }
  }

  Text {
    visible: page.loading && page.rows.length === 0
    x: Style.space(10)
    text: "Reading bindings…"
    color: page.fg
    opacity: 0.5
    font.family: page.font
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: page.shown
    Rectangle {
      id: row
      required property var modelData
      readonly property bool moved: !!modelData.from && !modelData.disabled
      width: page.width
      height: Style.space(40)
      radius: Style.space(8)
      color: rowHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
      HoverHandler { id: rowHover }

      Column {
        x: Style.space(10)
        width: parent.width - keyBox.width - actions.width - Style.space(40)
        anchors.verticalCenter: parent.verticalCenter
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: row.modelData.description || "(no description)"
          color: page.fg
          opacity: row.modelData.disabled ? 0.45 : 1
          font.family: page.font
          font.pixelSize: Style.font.body
        }
        Text {
          visible: row.moved || !!row.modelData.disabled
          text: row.modelData.disabled ? "disabled (was " + page.pretty(row.modelData.from) + ")" : "was " + page.pretty(row.modelData.from)
          color: page.accent
          font.family: page.font
          font.pixelSize: Style.font.caption
        }
      }

      KeyField {
        id: keyBox
        anchors.right: actions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        value: row.modelData.disabled ? "" : page.pretty(row.modelData.keys)
        onCaptured: function(v) { page.requestMove(row.modelData, v) }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        SmallButton { visible: row.moved || !!row.modelData.disabled; label: "Reset"; onClicked: page.reset(row.modelData) }
        SmallButton { visible: !row.modelData.disabled; label: "Off"; danger: true; onClicked: page.disable(row.modelData) }
      }
    }
  }

  Text {
    visible: page.rows.length > 0 && page.shown.length >= 80
    x: Style.space(10)
    text: "Showing the first 80; search to narrow it down."
    color: page.fg
    opacity: 0.5
    font.family: page.font
    font.pixelSize: Style.font.caption
  }

  // ======================= pieces =======================

  component SmallButton: Rectangle {
    id: btn
    property string label: ""
    property bool danger: false
    signal clicked()
    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.space(7)
    color: btnArea.containsMouse ? Util.alpha(danger ? Commons.Color.urgent : page.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: btnArea.containsMouse && btn.danger ? Commons.Color.urgent : page.fg
      font.family: page.font
      font.pixelSize: Style.font.caption
    }
    MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }

  // Same capture as the scratchpad builder: Hyprland's "capture" submap
  // switches bindings off while it listens, so taken keys arrive too.
  component KeyField: Rectangle {
    id: kf
    property string value: ""
    property bool listening: false
    signal captured(string v)
    width: Style.space(190)
    height: Style.space(28)
    radius: Style.space(6)
    color: listening ? Util.alpha(page.accent, 0.2) : kfArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.06)
    border.width: listening ? 1 : 0
    border.color: page.accent
    function stop() {
      if (!kf.listening) return
      kf.listening = false
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"])
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      x: Style.space(8)
      width: parent.width - Style.space(16)
      elide: Text.ElideRight
      text: kf.listening ? "Press keys… (Esc cancels)" : (kf.value || "—")
      color: page.fg
      font.family: page.font
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: kfArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        kf.listening = true
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
        if (!key && k >= Qt.Key_0 && k <= Qt.Key_9) key = "code:" + (k === Qt.Key_0 ? 19 : k - Qt.Key_0 + 9)
        if (!key && k >= Qt.Key_A && k <= Qt.Key_Z) key = String.fromCharCode(k)
        if (!key) return
        if (!mods.length) { page.status = "Use at least one modifier (SUPER, CTRL, ALT or SHIFT)."; kf.stop(); return }
        kf.stop()
        kf.captured(mods.concat([key]).join(" + "))
      }
    }
  }
}
