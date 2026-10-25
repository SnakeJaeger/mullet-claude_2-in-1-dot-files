import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Go menu server card, between the lab and phone cards: the self-hosted
// services on the lab box (~/.config/lab-services/services: Jellyfin, Immich,
// calendar) plus Remmina (VNC port), each a tile with an up/down dot. Polls ~/.local/bin/server-status
// every 4s while `active` (menu open). Click a tile: open its web page.
Item {
  id: card

  property bool active: false
  property color foreground: "white"
  property color hoverBackground: "transparent"
  property string fontFamily: ""
  property int radius: 0
  readonly property color accent: Commons.Color.pick("tablet.accent", Commons.Color.accent)
  readonly property color down: Commons.Color.urgent

  property var status: null
  readonly property var services: status && status.services ? status.services : []
  readonly property bool remoteUp: !!(status && status.remote)
  // The services plus the Remmina tile (VNC port open).
  readonly property int total: services.length + 1
  readonly property int upCount: {
    var n = remoteUp ? 1 : 0
    for (var i = 0; i < services.length; i++) if (services[i].up) n++
    return n
  }

  implicitHeight: Style.space(100)

  Process {
    id: poll
    command: [Quickshell.env("HOME") + "/.local/bin/server-status"]
    stdout: SplitParser {
      onRead: function(line) {
        try { card.status = JSON.parse(line) } catch (e) {}
      }
    }
  }

  Timer {
    interval: 4000
    repeat: true
    triggeredOnStart: true
    running: card.active
    onTriggered: if (!poll.running) poll.running = true
  }

  Rectangle {
    anchors.fill: parent
    radius: card.radius
    color: "transparent"
    border.width: Style.spacing.hairline
    border.color: Util.alpha(card.foreground, 0.15)
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(6)

    // Server              1 of 4 up
    Item {
      width: parent.width
      height: Style.font.body + Style.space(4)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Server"
        color: card.foreground
        opacity: 0.58
        font.family: card.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: !card.status ? "checking…"
          : card.upCount + " of " + card.total + " up"
        color: card.foreground
        font.family: card.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    // 󰎁 Jellyfin ●   󰋩 Immich ●   󰃭 Calendar ●   󰍹 Remmina
    Row {
      id: tileRow
      width: parent.width
      // The services plus the Remmina tile.
      readonly property real tileWidth: width / Math.max(1, card.services.length + 1)

      Repeater {
        model: card.services

        Rectangle {
          id: serviceTile
          required property var modelData
          width: tileRow.tileWidth
          height: serviceColumn.implicitHeight + Style.space(8)
          radius: card.radius
          color: serviceArea.containsMouse ? card.hoverBackground : "transparent"

          Column {
            id: serviceColumn
            anchors.centerIn: parent
            spacing: Style.space(3)

            Item {
              anchors.horizontalCenter: parent.horizontalCenter
              width: serviceIcon.implicitWidth
              height: serviceIcon.implicitHeight

              Text {
                id: serviceIcon
                text: serviceTile.modelData.icon
                color: serviceArea.containsMouse ? card.accent : card.foreground
                opacity: serviceTile.modelData.up ? 1 : 0.45
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.round(Style.font.heading * 1.15)
              }

              // Up / down dot on the icon's corner.
              Rectangle {
                x: parent.width - width / 2
                y: -height / 4
                width: Style.space(7)
                height: width
                radius: width / 2
                color: serviceTile.modelData.up ? card.accent : "transparent"
                border.width: serviceTile.modelData.up ? 0 : 1
                border.color: Util.alpha(card.foreground, 0.45)
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: serviceTile.modelData.name
              color: card.foreground
              opacity: serviceTile.modelData.up ? 0.9 : 0.58
              font.family: card.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: serviceArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.opened(serviceTile.modelData.name)
          }
        }
      }

      // Remmina (remote desktop to the lab), moved here from the tray.
      Rectangle {
        width: tileRow.tileWidth
        height: remminaColumn.implicitHeight + Style.space(8)
        radius: card.radius
        color: remminaArea.containsMouse ? card.hoverBackground : "transparent"

        Column {
          id: remminaColumn
          anchors.centerIn: parent
          spacing: Style.space(3)

          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: remminaIcon.implicitWidth
            height: remminaIcon.implicitHeight

            Text {
              id: remminaIcon
              text: "󰍹"
              color: remminaArea.containsMouse ? card.accent : card.foreground
              opacity: card.remoteUp ? 1 : 0.45
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Math.round(Style.font.heading * 1.15)
            }

            Rectangle {
              x: parent.width - width / 2
              y: -height / 4
              width: Style.space(7)
              height: width
              radius: width / 2
              color: card.remoteUp ? card.accent : "transparent"
              border.width: card.remoteUp ? 0 : 1
              border.color: Util.alpha(card.foreground, 0.45)
            }
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Remmina"
            color: card.foreground
            opacity: card.remoteUp ? 0.9 : 0.58
            font.family: card.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          id: remminaArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: card.remminaRequested()
        }
      }
    }
  }

  // Menu.qml closes itself and runs `server-status open <name>`.
  signal opened(string name)
  signal remminaRequested()
}
