import Quickshell
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Device settings (Settings hub → System): the shell's own panels (Wi-Fi,
// sound, display, Bluetooth, power) and other apps that control the device,
// grouped by category. Apps whose desktop file says Settings / HardwareSettings
// / Printing… show up on their own; "Add an app" brings in any other app.
// Each can be moved to another category or hidden. All kept in daa-ui.json
// (hubApps, hubAppsHidden, hubAppCats); the lists themselves live in
// Settings.qml so the Home page and its search share them.
Column {
  id: page

  property var host: null
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string font: Style.font.menuFamily

  spacing: Style.space(4)

  property bool showHidden: false
  property string addQuery: ""
  // The item whose category pills are open.
  property string movingId: ""

  readonly property var items: page.host ? (page.showHidden ? page.host.allDeviceItems : page.host.deviceItems) : []
  readonly property var groups: {
    var out = []
    var cats = page.host ? page.host.deviceCats : []
    for (var i = 0; i < cats.length; i++) {
      var list = page.items.filter(function(d) { return d.cat === cats[i][0] })
      if (list.length) out.push({ id: cats[i][0], name: cats[i][1], glyph: cats[i][2], items: list })
    }
    return out
  }
  readonly property var addCandidates: {
    var q = page.addQuery.trim().toLowerCase()
    if (q.length < 2 || !page.host) return []
    var have = {}
    for (var i = 0; i < page.host.allDeviceItems.length; i++) have[page.host.allDeviceItems[i].id] = true
    var apps = DesktopEntries.applications.values || []
    var out = []
    for (var j = 0; j < apps.length && out.length < 8; j++) {
      var a = apps[j]
      if (!a || a.noDisplay || have[a.id]) continue
      if ((String(a.name) + " " + a.id + " " + (a.genericName || "")).toLowerCase().indexOf(q) === -1) continue
      out.push({ id: String(a.id), name: String(a.name), icon: page.host.appIcon(a),
                 cat: page.host.guessDeviceCat(a.id + " " + a.name + " " + (a.categories || []).join(" ")) })
    }
    return out
  }

  component SmallButton: Rectangle {
    id: btn
    property string label: ""
    property bool selected: false
    property bool danger: false
    signal clicked()
    width: btnLabel.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.space(7)
    color: selected ? Util.alpha(page.accent, 0.3) : btnArea.containsMouse ? Util.alpha(danger ? Commons.Color.urgent : page.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: btn.selected ? page.accent : btnArea.containsMouse && btn.danger ? Commons.Color.urgent : page.fg
      font.family: page.font
      font.pixelSize: Style.font.caption
    }
    MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }
  component AppIcon: Item {
    property string icon: ""
    property string glyph: ""
    width: Style.space(26)
    height: width
    Image { anchors.fill: parent; visible: parent.icon !== ""; source: parent.icon; sourceSize.width: width * 2; sourceSize.height: height * 2 }
    Text { anchors.centerIn: parent; visible: parent.icon === ""; text: parent.glyph; color: page.accent; font.family: Style.font.family; font.pixelSize: Style.font.title }
  }

  Text {
    width: page.width
    text: "Open a panel or an app from here, the Home page or its search. Apps that call themselves settings tools appear on their own; add any other below."
    color: page.fg
    opacity: 0.55
    wrapMode: Text.Wrap
    font.family: page.font
    font.pixelSize: Style.font.caption
  }
  Row {
    topPadding: Style.space(4)
    spacing: Style.space(6)
    SmallButton { label: page.showHidden ? "Hide hidden" : "Show hidden"; selected: page.showHidden; onClicked: page.showHidden = !page.showHidden }
  }

  Repeater {
    model: page.groups
    Column {
      id: grp
      required property var modelData
      width: page.width
      spacing: Style.space(2)
      topPadding: Style.space(10)
      Row {
        spacing: Style.space(8)
        bottomPadding: Style.space(2)
        Text { text: grp.modelData.glyph; color: page.accent; font.family: Style.font.family; font.pixelSize: Style.font.body }
        Text { text: grp.modelData.name.toUpperCase(); color: page.fg; opacity: 0.55; font.family: page.font; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.2; anchors.verticalCenter: parent.verticalCenter }
      }
      Repeater {
        model: grp.modelData.items
        Column {
          id: entry
          required property var modelData
          width: page.width
          Rectangle {
            width: page.width
            height: Style.space(42)
            radius: Style.space(8)
            color: entryArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
            opacity: entry.modelData.hidden ? 0.45 : 1
            MouseArea {
              id: entryArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: page.host.launchDevice(entry.modelData)
            }
            AppIcon {
              id: eIcon
              x: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              icon: entry.modelData.icon
              glyph: entry.modelData.glyph
            }
            Column {
              anchors.left: eIcon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: eButtons.left
              anchors.verticalCenter: parent.verticalCenter
              Text { width: parent.width; elide: Text.ElideRight; text: entry.modelData.name; color: page.fg; font.family: page.font; font.pixelSize: Style.font.body }
              Text {
                width: parent.width
                elide: Text.ElideRight
                text: entry.modelData.builtin ? "Shell panel (opens from the bar)" : entry.modelData.added ? "Added by you" : "Found automatically"
                color: page.fg
                opacity: 0.45
                font.family: page.font
                font.pixelSize: Style.font.caption
              }
            }
            Row {
              id: eButtons
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)
              SmallButton { label: "Category"; selected: page.movingId === entry.modelData.id; onClicked: page.movingId = page.movingId === entry.modelData.id ? "" : entry.modelData.id }
              SmallButton {
                label: entry.modelData.hidden ? "Show" : "Hide"
                onClicked: page.host.setListKey("hubAppsHidden", entry.modelData.id, !entry.modelData.hidden)
              }
              SmallButton {
                visible: entry.modelData.added
                label: "Remove"
                danger: true
                onClicked: page.host.setListKey("hubApps", entry.modelData.id, false)
              }
            }
          }
          Flow {
            visible: page.movingId === entry.modelData.id
            x: Style.space(48)
            width: page.width - Style.space(56)
            spacing: Style.space(4)
            bottomPadding: Style.space(6)
            Repeater {
              model: page.host ? page.host.deviceCats : []
              SmallButton {
                required property var modelData
                label: modelData[1]
                selected: entry.modelData.cat === modelData[0]
                onClicked: { page.host.setDeviceCat(entry.modelData.id, modelData[0]); page.movingId = "" }
              }
            }
          }
        }
      }
    }
  }

  // ---- Add an app ----
  Text {
    topPadding: Style.space(14)
    text: "ADD AN APP"
    color: page.fg
    opacity: 0.55
    font.family: page.font
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }
  Rectangle {
    width: page.width
    height: Style.space(32)
    radius: Style.space(8)
    color: Qt.rgba(1, 1, 1, 0.06)
    TextInput {
      id: addInput
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      text: page.addQuery
      color: page.fg
      font.family: page.font
      font.pixelSize: Style.font.bodySmall
      onTextEdited: page.addQuery = text
      Keys.onEscapePressed: { if (page.addQuery !== "") page.addQuery = ""; else page.host.dismiss() }
      Text { visible: addInput.text === ""; text: "Search installed apps, e.g. pavucontrol, Mullvad, Disks…"; color: page.fg; opacity: 0.4; font: addInput.font }
    }
  }
  Repeater {
    model: page.addCandidates
    Item {
      id: cand
      required property var modelData
      width: page.width
      height: Style.space(40)
      AppIcon { id: cIcon; x: Style.space(10); anchors.verticalCenter: parent.verticalCenter; icon: cand.modelData.icon }
      Text {
        anchors.left: cIcon.right
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: cand.modelData.name + "   " + cand.modelData.id
        color: page.fg
        font.family: page.font
        font.pixelSize: Style.font.bodySmall
      }
      SmallButton {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        label: "Add"
        onClicked: {
          page.host.setListKey("hubApps", cand.modelData.id, true)
          page.addQuery = ""
        }
      }
    }
  }
  Item { width: 1; height: Style.space(10) }
}
