import QtQuick
import qs.Commons

// Two comets ride three quarters of the way round a rounded rectangle, once,
// then fade (the Go menu keybindings' Gestures button style). Fill the item
// it rims and call start(). Copies live in daa.power, daa.monitor, daa.gns3-note and daa.weather (keep them the same).
Canvas {
  id: rim
  anchors.margins: -3
  property real radius: height / 2
  property color first: Color.accent
  property color second: Color.urgent
  property real t: -1
  // Hidden between runs: an empty last paint can leave a sliver behind.
  visible: t >= 0
  readonly property real dur: 1.25
  function start() { t = 0; requestPaint() }

  FrameAnimation {
    running: rim.t >= 0
    onTriggered: {
      rim.t += frameTime
      if (rim.t > rim.dur + 0.4) rim.t = -1
      rim.requestPaint()
    }
  }

  // A point on the outline, s along it clockwise from top centre.
  function at(s) {
    var w = width, h = height, r = Math.min(radius + 3, h / 2, w / 2)
    var top = w - 2 * r, side = h - 2 * r, arc = Math.PI * r / 2
    var P = 2 * top + 2 * side + 4 * arc
    s = ((s % P) + P) % P
    var segs = [
      function(u) { return { x: w / 2 + u, y: 0 } }, top / 2,
      function(u) { var a = -Math.PI / 2 + u / r; return { x: w - r + r * Math.cos(a), y: r + r * Math.sin(a) } }, arc,
      function(u) { return { x: w, y: r + u } }, side,
      function(u) { var a = u / r; return { x: w - r + r * Math.cos(a), y: h - r + r * Math.sin(a) } }, arc,
      function(u) { return { x: w - r - u, y: h } }, top,
      function(u) { var a = Math.PI / 2 + u / r; return { x: r + r * Math.cos(a), y: h - r + r * Math.sin(a) } }, arc,
      function(u) { return { x: 0, y: h - r - u } }, side,
      function(u) { var a = Math.PI + u / r; return { x: r + r * Math.cos(a), y: r + r * Math.sin(a) } }, arc,
      function(u) { return { x: r + u, y: 0 } }, top / 2
    ]
    for (var i = 0; i < segs.length; i += 2) {
      if (s <= segs[i + 1]) return segs[i](s)
      s -= segs[i + 1]
    }
    return { x: w / 2, y: 0 }
  }
  function perimeter() {
    var w = width, h = height, r = Math.min(radius + 3, h / 2, w / 2)
    return 2 * (w - 2 * r) + 2 * (h - 2 * r) + 2 * Math.PI * r
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    if (t < 0) return
    var P = perimeter()
    var k = Math.min(1, t / dur)
    var head = (1 - Math.pow(1 - k, 3)) * P * 0.75
    var fade = Math.min(1, t / 0.15) * Math.max(0, 1 - Math.max(0, t - dur * 0.75) / (dur * 0.25 + 0.4))
    var trail = Math.min(head, P * 0.22), steps = 22
    var cols = [first, second]
    ctx.lineCap = "round"
    for (var c = 0; c < 2; c++) {
      var base = c * P / 2, col = cols[c]
      for (var i = 0; i < steps; i++) {
        var a0 = i / steps, a1 = (i + 1) / steps
        var p0 = at(base + head - a0 * trail), p1 = at(base + head - a1 * trail)
        var alpha = fade * Math.pow(1 - a0, 1.6)
        ctx.strokeStyle = i < 2 ? Qt.rgba(1, 1, 1, alpha) : Qt.rgba(col.r, col.g, col.b, alpha)
        ctx.lineWidth = 2.5 * (1 - a0) + 0.8
        ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(p1.x, p1.y); ctx.stroke()
      }
    }
  }
}
