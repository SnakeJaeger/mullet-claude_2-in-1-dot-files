import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Info bar: a tap of Super (~/.config/hypr/bindings.lua) fades it in at the
// top of the screen; another tap hides it at once, otherwise it fades out
// after `holdMs`. Mostly for when the top bar is hidden.
// Data: ~/.local/bin/infobar-status (one JSON snapshot per show).
Item {
  id: root

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

  readonly property int holdMs: 4000
  readonly property int pad: Style.space(16)
  readonly property int iconSize: Style.space(18)
  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.darker(Commons.Color.popups.text, 1.5)
  readonly property color accent: Commons.Color.accent

  property bool opened: false
  // Hide-by-tap skips the fade; the timeout fades out.
  property bool snap: false
  property var info: ({ active: 0, workspaces: [], wifi: "", ethernet: false,
                        bluetooth: { powered: false, connected: [] },
                        battery: { percent: -1, state: "" }, weather: null })
  property var quotes: []
  property date now: new Date()
  property bool barHidden: false

  // ---- Next calendar event (refreshed every 5 min in the background, since
  // reading the calendars takes a few seconds) ----
  property var nextEvent: ({})
  Process {
    id: eventProc
    command: [Quickshell.env("HOME") + "/.local/bin/next-event"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.nextEvent = JSON.parse(String(text).trim() || "{}") } catch (e) {} }
    }
  }
  Timer { interval: 300000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!eventProc.running) eventProc.running = true }
  readonly property string eventText: {
    var e = root.nextEvent
    if (!e || !e.start) return ""
    var mins = Math.round((e.start * 1000 - root.now.getTime()) / 60000)
    var when = e.all_day ? "today"
      : mins <= 0 ? "now"
      : mins < 60 ? "in " + mins + " min"
      : mins < 24 * 60 ? "at " + Qt.formatTime(new Date(e.start * 1000), "HH:mm")
      : ""
    if (mins < -60) return ""
    return "󰃭  " + e.summary + (when ? "  ·  " + when : "")
  }

  function toggle() {
    if (opened) hide()
    else show()
  }

  function show() {
    snap = false
    refresh()
    now = new Date()
    opened = true
    holdTimer.restart()
  }

  // Shown without the auto-fade, for as long as the quick search box
  // (daa.search) is open; it hides it again on close.
  function pin() {
    show()
    holdTimer.stop()
  }

  function hide() {
    snap = true
    opened = false
    holdTimer.stop()
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!barProbe.running) barProbe.running = true
  }

  // ---------- Workspace flash ----------
  // With the bar hidden nothing shows which workspace you landed on, so a
  // switch (swipe, keys, anything) flashes its number mid-screen.
  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
  property bool flashReady: false
  property bool flashOn: false
  property int flashId: 0

  onFocusedIdChanged: {
    if (root.opened) root.refresh()
    if (!flashReady || focusedId <= 0) return
    flashId = focusedId
    if (!flashProbe.running) flashProbe.running = true
  }

  // Ignore the workspace the session starts on.
  Timer { interval: 2000; running: true; onTriggered: root.flashReady = true }

  Process {
    id: flashProbe
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() !== "yes") return
        root.flashOn = true
        flashHold.restart()
      }
    }
  }

  Timer {
    id: flashHold
    interval: 650
    onTriggered: root.flashOn = false
  }

  PanelWindow {
    id: flashWindow
    // No anchors: the layer sits centred on the screen.
    visible: root.flashOn || flashCard.opacity > 0
    implicitWidth: flashCard.width
    implicitHeight: flashCard.height
    color: "transparent"
    WlrLayershell.namespace: "daa-infobar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Rectangle {
      id: flashCard
      width: Style.space(150)
      height: Style.space(150)
      radius: 24
      color: Util.alpha(Commons.Color.background, 0.77)
      opacity: root.flashOn ? 1 : 0
      scale: root.flashOn ? 1 : 0.92
      Behavior on opacity { NumberAnimation { duration: root.flashOn ? 90 : 260; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Style.space(8)
        text: root.flashId
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.space(72)
        font.bold: true
      }

      // Workspaces that exist, the current one lit.
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(18)
        spacing: Style.space(6)

        Repeater {
          model: Hyprland.workspaces.values.filter(function(w) { return w.id > 0 }).map(function(w) { return w.id }).sort(function(a, b) { return a - b })
          Rectangle {
            required property var modelData
            readonly property bool current: modelData === root.flashId
            anchors.verticalCenter: parent.verticalCenter
            width: current ? Style.space(16) : Style.space(6)
            height: Style.space(6)
            radius: height / 2
            color: current ? root.accent : Util.alpha(root.fg, 0.35)
          }
        }
      }
    }
  }

  IpcHandler {
    target: "daa.infobar"
    function toggle(): void { root.toggle() }
    function show(): void { root.show() }
    function hide(): void { root.hide() }
    function pin(): void { root.pin() }
  }

  Timer {
    id: holdTimer
    interval: root.holdMs
    onTriggered: { root.snap = false; root.opened = false }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: root.now = new Date()
  }

  Process {
    id: statusProc
    command: ["infobar-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.info = JSON.parse(text) } catch (e) {}
      }
    }
  }

  Process {
    id: barProbe
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.barHidden = text.trim() === "yes"
    }
  }

  // quotes.txt: one per line, "#" comments skipped. A new one every 6 hours.
  // Edited in Desktop settings → Bar.
  FileView {
    path: Qt.resolvedUrl("quotes.txt")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.quotes = text().split("\n").map(function(l) { return l.trim() })
      .filter(function(l) { return l.length > 0 && l.charAt(0) !== "#" })
  }

  readonly property string quote: {
    if (quotes.length === 0) return ""
    var slot = Math.floor(now.getTime() / (6 * 3600 * 1000))
    return quotes[slot % quotes.length]
  }

  function appIcon(cls) {
    var entry = DesktopEntries.heuristicLookup(cls)
    var name = entry && entry.icon ? entry.icon : String(cls || "").toLowerCase()
    if (name.charAt(0) === "/") return "file://" + name
    var themed = Quickshell.iconPath(name, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  function weatherGlyph(w) {
    if (!w) return ""
    var c = String(w.condition || "").toLowerCase()
    var t = Qt.formatTime(now, "HH:mm:ss")
    var night = w.sunrise && w.sunset && (t < w.sunrise || t > w.sunset)
    if (c.indexOf("thunder") >= 0) return "󰖓"
    if (c.indexOf("snow") >= 0 || c.indexOf("sleet") >= 0 || c.indexOf("ice") >= 0 || c.indexOf("blizzard") >= 0) return "󰖘"
    if (c.indexOf("rain") >= 0 || c.indexOf("drizzle") >= 0 || c.indexOf("shower") >= 0) return "󰖗"
    if (c.indexOf("fog") >= 0 || c.indexOf("mist") >= 0 || c.indexOf("haze") >= 0) return "󰖑"
    if (c.indexOf("partly") >= 0) return night ? "󰼱" : "󰖕"
    if (c.indexOf("cloud") >= 0 || c.indexOf("overcast") >= 0) return "󰖐"
    return night ? "󰖔" : "󰖙"
  }

  function batteryGlyph(b) {
    if (!b || b.percent < 0) return ""
    if (b.state === "charging" || b.state === "fully-charged") return "󰂄"
    var levels = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    return levels[Math.max(0, Math.min(10, Math.round(b.percent / 10)))]
  }

  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
    // Bottom middle of the screen (user's choice, 2026-10-24).
    // Only as wide as the card (centred by the layer shell), so clicks
    // anywhere else never reach it -- an input mask on a full-width window
    // never let clicks onto the card.
    anchors { bottom: true }
    implicitWidth: Math.ceil(card.width)
    implicitHeight: card.height + card.y + 4

    // Which edge the bar is on (as daa.osd reads it): only a visible bottom
    // bar pushes the card up.
    property string barEdge: "top"
    FileView {
      path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoaded: {
        try { panel.barEdge = String((JSON.parse(text() || "{}").bar || {}).position || "top") } catch (e) {}
      }
    }
    color: "transparent"
    WlrLayershell.namespace: "daa-infobar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    margins.bottom: panel.barEdge === "bottom" && !root.barHidden ? Style.bar.sizeHorizontal + Style.space(4) + 6 : 10

    Rectangle {
      id: card
      // Wraps the content: both flanks take the wider flank's width so the
      // time and weather stay centred (fixed widths let a long wifi name and
      // the bluetooth item run past the card's right edge).
      readonly property real flankWidth: Math.max(leftFlank.implicitWidth, rightFlank.implicitWidth)
      width: Math.min((panel.screen ? panel.screen.width : 1440) - 20,
        flankWidth * 2 + centerStage.implicitWidth + topRow.spacing * 4 + root.pad * 2)
      height: content.implicitHeight + root.pad * 2
      x: 0
      // The window hugs the bottom edge and is card + gap tall, so y is the
      // gap above the card; the gap below is set by the window's margin.
      y: 4
      radius: 14
      // Frosted like the OSD (daa-infobar blur rule in hypr/looknfeel.lua).
      color: Util.alpha(Commons.Color.background, 0.77)
      // Entrance (Desktop settings → Quick search and info bar): off, fade,
      // rise (up from the screen edge) or pop (springs out of a smaller card).
      readonly property string entrance: root.uiOpt("infoBarStyle", "fade")
      readonly property bool animated: !root.snap && entrance !== "off"
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : entrance === "pop" ? 0.85 : 0.97
      transform: Translate {
        y: card.entrance === "rise" && !root.opened ? card.height + 10 : 0
        Behavior on y { enabled: card.animated; NumberAnimation { duration: root.opened ? 260 : 200; easing.type: root.opened ? Easing.OutCubic : Easing.InCubic } }
      }
      Behavior on opacity { enabled: card.animated; NumberAnimation { duration: root.opened ? 140 : 300; easing.type: Easing.OutCubic } }
      Behavior on scale {
        enabled: card.animated
        NumberAnimation { duration: card.entrance === "pop" ? 260 : 160; easing.type: card.entrance === "pop" && root.opened ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 2 }
      }

      // Breathing border: the window border's accent → coral gradient, drawn
      // once, its opacity slowly rising and falling.
      Canvas {
        anchors.fill: parent
        z: 10
        property real breath: 0.35
        SequentialAnimation on breath {
          running: root.opened && root.uiOpt("breathingBorders", true)
          loops: Animation.Infinite
          NumberAnimation { to: 1; duration: 1700 / Math.max(0.1, root.uiOpt("breathingSpeed", 1)); easing.type: Easing.InOutSine }
          NumberAnimation { to: 0.35; duration: 1700 / Math.max(0.1, root.uiOpt("breathingSpeed", 1)); easing.type: Easing.InOutSine }
        }
        // Settings: "breathingBorders" off = a steady border; "breathingSpeed".
        opacity: root.uiOpt("breathingBorders", true) ? breath : 0.8
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
          var lw = 1.5, o = lw / 2, r = Math.max(0, card.radius - o)
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

      // Placed rather than anchored to fill: the card takes its height from
      // this layout, and filling the card made it under-report its height
      // (the card's background stopped short of the quote).
      ColumnLayout {
        id: content
        x: root.pad
        y: root.pad
        width: card.width - root.pad * 2
        spacing: Style.space(10)

        RowLayout {
          id: topRow
          Layout.fillWidth: true
          spacing: Style.space(24)

          // Workspaces in use: the current one highlighted, each with its apps.
          Row {
            id: leftFlank
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: card.flankWidth
            spacing: Style.space(6)

            Repeater {
              model: root.info.workspaces
              Rectangle {
                id: pill
                required property var modelData
                // Live from Hyprland, so Tab-switching (daa.search) moves it at once.
                readonly property bool current: modelData.id === (root.focusedId > 0 ? root.focusedId : root.info.active)
                height: Style.space(30)
                width: wsRow.implicitWidth + Style.space(14)
                radius: height / 2
                color: current ? Util.alpha(root.accent, 0.22)
                  : pillArea.containsMouse ? Util.alpha(root.fg, 0.16) : Util.alpha(root.fg, 0.07)
                Behavior on color { ColorAnimation { duration: 90 } }

                // Click: go to that workspace (closing the quick search if
                // it's what brought the info bar up).
                MouseArea {
                  id: pillArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + pill.modelData.id + "\" })"])
                    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "hide", "daa.search"])
                    root.hide()
                  }
                }
                border.width: current ? 1 : 0
                border.color: Util.alpha(root.accent, 0.7)

                Row {
                  id: wsRow
                  anchors.centerIn: parent
                  spacing: Style.space(5)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: current ? root.accent : root.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Repeater {
                    model: modelData.classes.slice(0, 4)
                    Image {
                      required property var modelData
                      anchors.verticalCenter: parent.verticalCenter
                      width: root.iconSize
                      height: root.iconSize
                      sourceSize.width: root.iconSize * 2
                      sourceSize.height: root.iconSize * 2
                      source: root.appIcon(modelData)
                      asynchronous: true
                      smooth: true
                    }
                  }

                  Text {
                    visible: modelData.classes.length > 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+" + (modelData.classes.length - 4)
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          Item { Layout.fillWidth: true }

          // Centre stage: time and date beside the weather.
          Row {
            id: centerStage
            Layout.alignment: Qt.AlignVCenter
            spacing: Style.space(18)

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(root.now, "HH:mm")
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                font.bold: true
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(root.now, "dddd d MMMM").toUpperCase()
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }

              // Next calendar event within 24 h (~/.local/bin/next-event).
              Text {
                visible: text !== "" && root.uiOpt("infoEvent", true)
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: Style.space(3)
                text: root.eventText
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Style.space(260))
              }
            }

            Rectangle {
              visible: !!root.info.weather && root.uiOpt("infoWeather", true)
              anchors.verticalCenter: parent.verticalCenter
              width: 1
              height: Style.space(36)
              color: Util.alpha(root.fg, 0.15)
            }

            Row {
              visible: !!root.info.weather && root.uiOpt("infoWeather", true)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.weatherGlyph(root.info.weather)
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  text: root.info.weather ? String(root.info.weather.temp).replace(/^\+/, "") : ""
                  color: root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.display
                  font.bold: true
                }

                Text {
                  text: root.info.weather ? String(root.info.weather.condition).trim().toUpperCase() : ""
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }

                Text {
                  visible: text !== ""
                  text: root.info.weather && root.info.weather.place ? "󰍎 " + root.info.weather.place : ""
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Item { Layout.fillWidth: true }

          // Battery, network, bluetooth: one per line, glyphs in a column,
          // longest value first.
          Column {
            id: rightFlank
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: card.flankWidth
            spacing: Style.space(3)

            Repeater {
              model: root.statusRows
              Item {
                id: statusRow
                required property var modelData
                width: statusLine.implicitWidth
                height: statusLine.implicitHeight

                Row {
                  id: statusLine
                  spacing: Style.space(8)
                  opacity: statusArea.containsMouse ? 1 : 0.9
                  StatusGlyph { glyph: statusRow.modelData.glyph; lit: statusRow.modelData.lit || statusArea.containsMouse }
                  StatusValue { text: statusRow.modelData.text }
                }

                // Click: close up, then the cursor glides to the matching bar
                // icon and its panel opens (~/.local/bin/cursor-to-tray).
                MouseArea {
                  id: statusArea
                  anchors.fill: parent
                  anchors.margins: -Style.space(2)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "hide", "daa.search"])
                    root.hide()
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/cursor-to-tray",
                      statusRow.modelData.widget, statusRow.modelData.panel])
                  }
                }
              }

            }
          }
        }

        // Quote of the (quarter) day.
        Text {
          visible: root.quote !== "" && root.uiOpt("infoQuote", true)
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          text: root.quote
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.italic: true
          elide: Text.ElideRight
        }
      }
    }
  }

  readonly property var statusRows: {
    var rows = []
    var b = info.battery, bt = info.bluetooth
    // Each line can be switched off in Desktop settings → Bar.
    if (b.percent >= 0 && root.uiOpt("infoBattery", true))
      rows.push({ glyph: batteryGlyph(b), lit: b.state === "charging", widget: "daa.power", panel: "omarchy.power",
        text: b.percent + "%" + (b.state === "charging" ? "  charging" : "") })
    if (root.uiOpt("infoNetwork", true))
      rows.push({ glyph: info.wifi !== "" ? "󰖩" : info.ethernet ? "󰈀" : "󰖪", lit: info.wifi !== "" || info.ethernet,
      widget: "daa.network", panel: "omarchy.network",
      text: info.wifi !== "" ? info.wifi : info.ethernet ? "Wired" : "Offline" })
    if (root.uiOpt("infoBluetooth", true))
      rows.push({ glyph: !bt.powered ? "󰂲" : bt.connected.length > 0 ? "󰂱" : "󰂯", lit: bt.connected.length > 0,
      widget: "daa.bluetooth", panel: "omarchy.bluetooth",
      text: !bt.powered ? "Off" : bt.connected.length > 0 ? bt.connected[0] : "On" })
    // Longest first (stable for equal lengths).
    return rows.map(function(r, i) { r.i = i; return r })
      .sort(function(x, y) { return y.text.length - x.text.length || x.i - y.i })
  }

  component StatusGlyph: Text {
    property string glyph: ""
    property bool lit: false
    width: Style.space(18)
    horizontalAlignment: Text.AlignHCenter
    text: glyph
    color: lit ? root.accent : root.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  component StatusValue: Text {
    color: root.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    width: Math.min(implicitWidth, Style.space(130))
  }

}
