import QtQuick
import qs.Commons
import qs.Commons as Commons

// Touchpad scrolling for scrollable grids and lists (Go menu, SUPER+R). Qt treats a
// two-finger scroll as a finger drag: content follows the fingers (the
// opposite of the rest of the desktop) and there's no momentum, since
// libinput sends none. This takes over the wheel: fingers down moves the
// items up, lifting off hands the speed to the view's flick so it coasts
// (fingers back down brake it), and the ends flash a GTK-style accent glow.
// Give the view interactive: false and StopAtBounds.
// Sits on top of the view; clicks pass through to the items.
Item {
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
