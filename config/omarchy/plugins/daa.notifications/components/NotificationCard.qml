// Notification card. Pure presentational — no service, Notification, or
// ListModel references. The popup container drives lifetime; the history
// panel drives static rendering. Both use the same component.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../NotificationLogic.js" as NotificationLogic

BorderSurface {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  // Nerd Font glyph rendered in the icon slot when no real icon is set.
  // Used by omarchy-notification-send so user-action toasts (`Silenced
  // notifications` etc.) show their bell/lock/etc. glyph without leaking
  // into the summary text.
  property string glyph: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2 (upstream).
  property int urgency: 1
  property double timestamp: 0
  property int cornerRadius: 0
  // daa: share of the on-screen time used up (0..1), or -1 for no countdown
  // (critical toasts, history). Drives the border countdown below.
  property real elapsed: -1

  // System monospace font injected by the container.
  property string fontFamily: ""

  readonly property bool hovered: hoverTracker.hovered

  signal closeRequested()
  signal cardClicked()
  // Prefer per-notification media/avatar data, then fall back to the app icon.
  // The `check` flag avoids Qt's missing-texture placeholder for unknown names.
  readonly property string smallIconSource: image.length > 0 ? image : iconSource(appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool compactGlyph: NotificationLogic.shouldRenderCompactGlyph(glyph, smallIconSource, singleLineToast)
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property bool summaryStartsWithGlyph: NotificationLogic.summaryStartsWithGlyph(summary)
  readonly property bool singleLineToast: sanitizedBody.length === 0
  readonly property bool collapseRedundantIcon: singleLineToast && !hasGlyph && summaryStartsWithGlyph
  readonly property string sanitizedBody: sanitizeBody(body)
  readonly property string styledBody: NotificationLogic.styledBody(body, app, appIcon)

  readonly property color dimColor: Qt.darker(Commons.Color.notifications.text, 1.4)
  readonly property color bodyColor: Qt.darker(Commons.Color.notifications.text, 1.15)
  readonly property color accentColor: urgency === 2 ? Commons.Color.urgent : (urgency === 0 ? dimColor : Commons.Color.notifications.countdown)
  readonly property var cardBorderSpec: Border.surfaceSpec("notifications", "border", Commons.Color.notifications.border, 1)  // daa: 1px like window borders

  function sanitizeBody(s) {
    return NotificationLogic.sanitizeBody(s, app, appIcon)
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  implicitWidth: Style.space(380)
  // Add vertical border insets so mainColumn (inset by border on top/left/right)
  // doesn't push content under the bottom edge.
  implicitHeight: mainColumn.implicitHeight + borderTop + borderBottom
  radius: cornerRadius
  // daa: mildly see-through (blurred by a layer rule in looknfeel.lua).
  color: Qt.alpha(Commons.Color.notifications.background, 0.85)
  borderSpec: cardBorderSpec
  clip: true

  HoverHandler { id: hoverTracker }

  // daa: countdown border. The border starts cyan. A whitish head about
  // 50 px long sets off clockwise from 9 o'clock with coral filling in behind
  // it; the head stops when it gets back to 9 o'clock and the coral closes
  // the loop as the toast's time runs out. Drawn over the regular border, on
  // the centre line of its stroke.
  component CountdownStroke: ShapePath {
    // Where along the outline this stroke starts and how long it is (px).
    property real from: 0
    property real length: 0
    strokeWidth: countdown.bw
    fillColor: "transparent"
    capStyle: ShapePath.FlatCap
    strokeStyle: ShapePath.DashLine
    // Dash units are stroke widths: nothing, a gap up to `from`, the dash,
    // then a gap past the end of the outline.
    dashPattern: [0, from / countdown.bw, Math.max(0.001, length) / countdown.bw,
                  countdown.perimeter / countdown.bw + 1]
    PathSvg { path: countdown.outline }
  }

  Shape {
    id: countdown
    z: 3
    anchors.fill: parent
    visible: root.elapsed >= 0
    preferredRendererType: Shape.CurveRenderer

    // The window border's gradient (looknfeel.lua): accent -> second accent.
    readonly property color cyan: Commons.Color.accent
    readonly property color coral: Commons.Color.urgent
    readonly property color head: "#fff3ee"
    readonly property real headLength: 50

    readonly property real bw: Math.max(1, root.borderTop)
    readonly property real inset: bw / 2
    readonly property real w: width - bw
    readonly property real h: height - bw
    readonly property real r: Math.max(0, Math.min(root.radius - inset, w / 2, h / 2))
    readonly property real perimeter: 2 * (w - 2 * r) + 2 * (h - 2 * r) + 2 * Math.PI * r
    // Clockwise from 9 o'clock (the middle of the left edge).
    readonly property string outline: {
      var i = inset, x1 = i + w, y1 = i + h, rr = r, mid = i + h / 2
      return "M " + i + " " + mid
        + " L " + i + " " + (i + rr)
        + " A " + rr + " " + rr + " 0 0 1 " + (i + rr) + " " + i
        + " L " + (x1 - rr) + " " + i
        + " A " + rr + " " + rr + " 0 0 1 " + x1 + " " + (i + rr)
        + " L " + x1 + " " + (y1 - rr)
        + " A " + rr + " " + rr + " 0 0 1 " + (x1 - rr) + " " + y1
        + " L " + (i + rr) + " " + y1
        + " A " + rr + " " + rr + " 0 0 1 " + i + " " + (y1 - rr)
        + " L " + i + " " + mid
    }

    // The head travels perimeter + headLength in the toast's lifetime, so
    // the coral behind it reaches the end exactly when time is up.
    readonly property real travel: Math.max(0, root.elapsed) * (perimeter + headLength)
    readonly property real headEnd: Math.min(perimeter, travel)
    readonly property real coralEnd: Math.max(0, travel - headLength)
    readonly property real headSpan: Math.max(0, headEnd - coralEnd)

    function mix(t) {
      return Qt.rgba(coral.r + (head.r - coral.r) * t, coral.g + (head.g - coral.g) * t,
                     coral.b + (head.b - coral.b) * t, 1)
    }

    ShapePath {
      strokeColor: countdown.cyan
      strokeWidth: countdown.bw
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathSvg { path: countdown.outline }
    }

    CountdownStroke { strokeColor: countdown.coral; length: countdown.coralEnd }

    // The head, coral at the back fading to whitish at the front.
    CountdownStroke { strokeColor: countdown.mix(0.2); from: countdown.coralEnd; length: countdown.headSpan / 5 }
    CountdownStroke { strokeColor: countdown.mix(0.4); from: countdown.coralEnd + countdown.headSpan / 5; length: countdown.headSpan / 5 }
    CountdownStroke { strokeColor: countdown.mix(0.6); from: countdown.coralEnd + countdown.headSpan * 2 / 5; length: countdown.headSpan / 5 }
    CountdownStroke { strokeColor: countdown.mix(0.8); from: countdown.coralEnd + countdown.headSpan * 3 / 5; length: countdown.headSpan / 5 }
    CountdownStroke { strokeColor: countdown.mix(1.0); from: countdown.coralEnd + countdown.headSpan * 4 / 5; length: countdown.headSpan / 5 }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.closeRequested()
      } else {
        root.cardClicked()
      }
    }
  }

  // daa: close button (same as a right click on the card).
  Rectangle {
    id: closeButton
    z: 2
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.borderTop + Style.space(6)
    anchors.rightMargin: root.borderRight + Style.space(6)
    width: Style.space(20)
    height: width
    radius: width / 2
    color: closeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: "󰅖"
      color: closeArea.containsMouse ? Commons.Color.notifications.text : root.dimColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }

    MouseArea {
      id: closeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
  }

  ColumnLayout {
    id: mainColumn
    // Inset by the card border so the content doesn't paint over the card's
    // outer border.
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.borderTop
    anchors.leftMargin: root.borderLeft
    anchors.rightMargin: root.borderRight
    spacing: 0

    // Text content.
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      // daa: room for the close button in the top-right corner.
      Layout.rightMargin: Style.space(30)
      Layout.topMargin: root.singleLineToast ? Style.space(7) : Style.space(10)
      Layout.bottomMargin: root.singleLineToast ? Style.space(7) : Style.space(10)
      spacing: root.collapseRedundantIcon ? 0 : (root.compactGlyph ? Style.space(8) : Style.space(12))

      Item {
        id: smallIconSlot
        Layout.preferredWidth: visible ? Style.space(40) : 0
        Layout.preferredHeight: visible ? Style.space(40) : 0
        Layout.alignment: Qt.AlignVCenter
        // Hide the slot when the icon failed to resolve (themed-icon name
        // not in the user's icon theme) AND we don't have a glyph fallback
        // — prevents rendering Qt's pink broken-image placeholder.
        visible: !root.collapseRedundantIcon && !root.compactGlyph && (root.hasSmallIcon || root.hasGlyph) && (root.hasGlyph || smallIconImage.status !== Image.Error)

        Image {
          id: smallIconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
          sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          visible: !root.hasGlyph || smallIconImage.status === Image.Ready
        }

        // Glyph fallback (Nerd Font character) when no image icon is
        // available. Used by omarchy-notification-send's `-g` flag.
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: root.hasGlyph && smallIconImage.status !== Image.Ready
          text: root.glyph
          color: Commons.Color.notifications.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignVCenter
        visible: root.compactGlyph
        text: root.glyph
        color: Commons.Color.notifications.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(2)

        Text {
          // The spec defines the summary as a single line of plain text, so
          // AutoText could only ever promote a hostile string to rich text.
          // The body below is StyledText on purpose — see Service.qml's
          // bodyMarkupSupported — and is stripped in NotificationLogic.
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: root.summary.length > 0
          text: root.summary
          font.family: "Liberation Sans"
          color: Commons.Color.notifications.text
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: 2
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          visible: root.sanitizedBody.length > 0
          text: root.styledBody
          textFormat: Text.StyledText
          font.family: "Liberation Sans"
          color: root.bodyColor
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: 3
        }
      }
    }
  }

}
