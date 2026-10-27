import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

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

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    // Settings: "visibleWorkspaces" (2-10) always shown; others when in use.
    var shown = Math.max(1, Math.min(10, Math.round(root.uiOpt("visibleWorkspaces", 5))))
    var ids = []
    for (var n = 1; n <= shown; n++) ids.push(n)
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // The button for the focused workspace; the indicator springs to it.
  readonly property Item focusedButton: {
    var count = repeater.count
    var focused = Hyprland.focusedWorkspace
    if (!focused || count === 0) return null
    var index = root.workspaceIds().indexOf(focused.id)
    return index < 0 ? null : repeater.itemAt(index)
  }

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  // One shared indicator behind the numbers, centred on the painted digit
  // (not the button box, which leaves it looking off). It's a stadium like
  // the island around it: corner radius is half its height, so both share
  // the same fully rounded ends.
  //
  // Switching workspace: the trailing edge squeezes in toward the direction
  // of travel, then both edges spring over to the new workspace.
  //
  // Easter egg ("magellanic desktop selection"): when the switch
  // comes from SUPER+ALT+digit, the indicator goes "around the world" -- it
  // leaves the island AWAY from the new workspace, runs the whole length of
  // the top bar, wraps at the screen edge, and comes back round to land on
  // it -- never passing over the landing spot on the way (lapOverlay below). The SUPER+ALT+digit
  // binding (hypr/bindings.lua) calls `omarchy-shell daa.workspaces lap`
  // right after the switch: that turns the switch that just started into a
  // lap, or, if the call beat the switch here, makes the next one a lap.
  // workspace_collapse.lua may renumber the target mid-lap; the lap aims at
  // wherever the focused workspace is, so it still lands right.
  property real lapUntil: 0
  property real recentFrom: 0
  property bool recentRight: true
  property real recentAt: 0

  function lap() {
    // Settings: "magellanic" off = a plain switch.
    if (!root.uiOpt("magellanic", true)) return
    if (lapOverlay.running) return
    if (Date.now() - root.recentAt < 500) {
      switchAnimation.stop()
      indicator.leftEdge = indicator.targetLeft
      indicator.rightEdge = indicator.targetRight
      root.startLap(root.recentFrom, root.recentRight)
    } else {
      root.lapUntil = Date.now() + 500
    }
  }

  // `movingRight` is where the new workspace lies; the lap sets off the
  // other way, so it only meets the landing spot at the very end.
  function startLap(fromX, movingRight) {
    var rightward = !movingRight
    var here = root.mapToItem(null, 0, 0)
    var top = root
    while (top.parent) top = top.parent
    lapOverlay.offsetX = here.x
    lapOverlay.barWidth = top.width
    lapOverlay.from = fromX
    lapOverlay.rightward = rightward
    lapOverlay.pillWidth = indicator.restWidth
    lapOverlay.pillHeight = indicator.height
    lapOverlay.pillY = indicator.centerY
    lapOverlay.start()
  }

  IpcHandler {
    target: "daa.workspaces"
    function lap(): void { root.lap() }
  }

  Item {
    id: track
    anchors.fill: grid
    z: -1
    clip: true

  Rectangle {
    id: indicator

    readonly property real targetCenterX: root.focusedButton ? root.focusedButton.x + root.focusedButton.glyphCenterX : 0
    readonly property real centerY: root.focusedButton ? root.focusedButton.y + root.focusedButton.glyphCenterY : 0
    readonly property real restWidth: Math.round(height * 1.45)

    // Edges are animated independently so the shape can squeeze and stretch.
    property real leftEdge: 0
    property real rightEdge: 0
    property int shownId: -1
    property bool placed: false

    // Animation endpoints, set by moveTo() before each run.
    property real squeezeLeft: 0
    property real squeezeRight: 0
    property real targetLeft: 0
    property real targetRight: 0

    height: root.focusedButton ? Math.round(Math.min(root.focusedButton.width, root.focusedButton.height) * 0.62) : 0
    width: rightEdge - leftEdge
    x: leftEdge
    y: centerY - height / 2
    radius: height / 2
    color: Color.accent
    // Hidden while it's out doing its lap of the bar.
    visible: root.focusedButton !== null && placed && !lapOverlay.running

    function moveTo() {
      if (!root.focusedButton) return
      var id = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
      targetLeft = targetCenterX - restWidth / 2
      targetRight = targetCenterX + restWidth / 2

      // First placement, or the layout shifted under the same workspace: snap.
      if (!placed || id === shownId) {
        if (switchAnimation.running) return
        leftEdge = targetLeft
        rightEdge = targetRight
        shownId = id
        placed = true
        return
      }

      shownId = id
      switchAnimation.stop()
      var movingRight = targetCenterX > (leftEdge + rightEdge) / 2

      // Mid-lap (the collapse renumbered the target): the lap already aims at
      // the focused workspace, just keep the resting indicator in step.
      if (lapOverlay.running) {
        leftEdge = targetLeft
        rightEdge = targetRight
        return
      }

      // Around the world, armed by a lap() call that arrived first.
      if (Date.now() < root.lapUntil) {
        root.lapUntil = 0
        var startX = root.mapToItem(null, 0, 0).x + (leftEdge + rightEdge) / 2
        leftEdge = targetLeft
        rightEdge = targetRight
        root.startLap(startX, movingRight)
        return
      }

      // Remember where this switch started, in case lap() follows.
      root.recentFrom = root.mapToItem(null, 0, 0).x + (leftEdge + rightEdge) / 2
      root.recentRight = movingRight
      root.recentAt = Date.now()

      // Settings: "workspaceSpring" off = the indicator jumps straight there.
      if (!root.uiOpt("workspaceSpring", true)) {
        leftEdge = targetLeft
        rightEdge = targetRight
        return
      }

      var squeeze = (rightEdge - leftEdge) * 0.4
      squeezeLeft = movingRight ? leftEdge + squeeze : leftEdge
      squeezeRight = movingRight ? rightEdge : rightEdge - squeeze
      switchAnimation.start()
    }

    onTargetCenterXChanged: moveTo()
    onRestWidthChanged: moveTo()
    Connections {
      target: Hyprland
      function onFocusedWorkspaceChanged() { indicator.moveTo() }
    }

    SequentialAnimation {
      id: switchAnimation

      ParallelAnimation {
        NumberAnimation { target: indicator; property: "leftEdge"; to: indicator.squeezeLeft; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: indicator; property: "rightEdge"; to: indicator.squeezeRight; duration: 90; easing.type: Easing.OutQuad }
      }
      ParallelAnimation {
        NumberAnimation { target: indicator; property: "leftEdge"; to: indicator.targetLeft; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        NumberAnimation { target: indicator; property: "rightEdge"; to: indicator.targetRight; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
      }
    }
  }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      id: repeater
      model: root.workspaceIds()

      WidgetButton {
        id: button
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        // Centre of the digit's ink within this button. Text is centred by
        // line height, which leaves digits sitting 1px high (and a touch
        // right) of the box centre at this font/size; measured on screen.
        readonly property real glyphCenterX: width / 2 + 0.5
        readonly property real glyphCenterY: height / 2 - 1

        bar: root.bar
        text: modelData === 10 ? "0" : String(modelData)
        // The focused workspace keeps its number, in black on the indicator.
        foreground: focused ? "black" : (root.bar ? root.bar.barForeground : Color.foreground)
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }

  // The lap: a see-through, click-through strip over the whole bar. The pill
  // runs from where it was to the screen edge in the direction of travel,
  // wraps to the other edge and runs on to the new workspace, stretching
  // with speed and trailing two fading ghosts.
  PopupWindow {
    id: lapOverlay
    property bool running: false
    property real offsetX: 0
    property real barWidth: 1440
    property real from: 0
    // Where it lands: the focused workspace's digit, live.
    readonly property real to: offsetX + indicator.targetCenterX
    property bool rightward: true
    property real pillWidth: 20
    property real pillHeight: 12
    property real pillY: 0
    // Progress 0..1 and the distance it stands for (total can change mid-lap
    // if the target moves).
    property real p: 0
    readonly property real s: p * total
    readonly property real firstLeg: rightward ? barWidth + pillWidth - from : from + pillWidth
    readonly property real total: firstLeg + (rightward ? to + pillWidth : barWidth + pillWidth - to)

    function start() {
      lapRun.stop()
      p = 0
      running = true
      // Settings: "magellanicSpeed" multiplier.
      lapRun.duration = Math.round((650 + total * 0.22) / Math.max(0.1, root.uiOpt("magellanicSpeed", 1)))
      lapRun.start()
    }

    // Centre of the pill at distance d along the lap, in bar coordinates.
    function centerAt(d) {
      if (d < firstLeg) return rightward ? from + d : from - d
      var rest = d - firstLeg
      return rightward ? -pillWidth + rest : barWidth + pillWidth - rest
    }

    NumberAnimation {
      id: lapRun
      target: lapOverlay
      property: "p"
      from: 0
      to: 1
      easing.type: Easing.InOutCubic
      onFinished: lapOverlay.running = false
    }

    visible: running
    color: "transparent"
    implicitWidth: Math.max(1, Math.round(barWidth))
    implicitHeight: Math.max(1, Math.round(root.height))
    mask: Region {}

    anchor {
      item: root
      adjustment: PopupAdjustment.None
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.x: -Math.round(lapOverlay.offsetX)
      rect.y: 0
      rect.width: 1
      rect.height: 1
    }

    Repeater {
      model: [0.36, 0.18, 0]
      Rectangle {
        required property real modelData
        readonly property real lag: modelData === 0 ? 0 : (modelData === 0.18 ? 14 : 30)
        // Longest mid-lap, where it's fastest.
        readonly property real stretch: 1 + 1.6 * Math.sin(Math.PI * Math.min(1, lapOverlay.s / Math.max(1, lapOverlay.total)))
        width: lapOverlay.pillWidth * stretch
        height: lapOverlay.pillHeight
        radius: height / 2
        x: lapOverlay.centerAt(Math.max(0, lapOverlay.s - lag * stretch)) - width / 2
        y: lapOverlay.pillY - height / 2
        color: Color.accent
        opacity: modelData === 0 ? 1 : modelData
      }
    }
  }
}
