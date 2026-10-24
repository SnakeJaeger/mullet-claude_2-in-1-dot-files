// Infinity, rebuilt without Plasma: the look of l4k1's Infinity-SDDM-6
// (background, clock, round avatar, password pill, power buttons) in plain
// QtQuick, so it needs no plasma-workspace. Users are picked with the ‹ ›
// arrows, Left/Right/Up/Down or Tab, instead of Plasma's "Other…" list.
import QtQuick
import SddmComponents 2.0

Rectangle {
  id: root
  width: 1920
  height: 1080
  color: "#161925"

  readonly property string fontFamily: "Noto Sans"
  property string currentUser: userModel.lastUser
  property bool loginFailed: false

  // Prefer the Hyprland (uwsm) session, like Omarchy's own theme.
  // SessionModel roles: Qt.UserRole + 4 is the session's name.
  readonly property int sessionNameRole: Qt.UserRole + 4
  function sessionNameAt(i) {
    return (sessionModel.data(sessionModel.index(i, 0), sessionNameRole) || "").toString()
  }
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++)
      if (sessionNameAt(i).indexOf("uwsm") !== -1) return i
    return sessionModel.lastIndex
  }
  readonly property string sessionName: sessionNameAt(sessionIndex)

  // Users from SDDM's model: names, display names and avatars.
  property var users: []
  function userInfo(name) {
    for (var i = 0; i < users.length; i++) if (users[i].name === name) return users[i]
    return { name: name, realName: "", icon: "" }
  }
  readonly property var current: userInfo(currentUser)

  function cycleUser(step) {
    if (users.length < 2) return
    var i = 0
    for (var j = 0; j < users.length; j++) if (users[j].name === currentUser) i = j
    currentUser = users[(i + step + users.length) % users.length].name
    password.text = ""
    loginFailed = false
    password.forceActiveFocus()
  }

  function login() {
    sddm.login(root.currentUser, password.text, root.sessionIndex)
  }

  Repeater {
    model: userModel
    Item {
      required property string name
      required property string realName
      required property string icon
      Component.onCompleted: {
        root.users = root.users.concat([{ name: name, realName: realName, icon: icon }])
        if (!root.currentUser) root.currentUser = name
      }
    }
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      shake.restart()
      password.forceActiveFocus()
    }
    function onLoginSucceeded() { root.loginFailed = false }
  }

  Image {
    anchors.fill: parent
    source: "background.jpg"
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
  }

  // Clock and date.
  Column {
    id: clock
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.height * 0.11
    spacing: 4

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = new Date() }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatTime(clock.now, "hh:mm:ss")
      color: "white"
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.height * 0.058)
      font.weight: Font.Light
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDate(clock.now, "dddd, d MMMM yyyy")
      color: "white"
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.height * 0.024)
    }
  }

  // Avatar, name switcher and password.
  Column {
    id: loginBox
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.height * 0.35
    spacing: 14

    transform: Translate { id: shakeX }
    SequentialAnimation {
      id: shake
      NumberAnimation { target: shakeX; property: "x"; to: -14; duration: 50 }
      NumberAnimation { target: shakeX; property: "x"; to: 14; duration: 70 }
      NumberAnimation { target: shakeX; property: "x"; to: -8; duration: 60 }
      NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 50 }
    }

    // Round avatar: the user's face icon if SDDM has one, else their initial.
    Rectangle {
      id: avatar
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.round(root.height * 0.105)
      height: width
      radius: width / 2
      color: Qt.rgba(0.09, 0.1, 0.15, 0.85)
      border.color: "white"
      border.width: 3
      clip: true

      Image {
        id: face
        anchors.fill: parent
        anchors.margins: 3
        source: root.current.icon || ""
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
      }
      Text {
        anchors.centerIn: parent
        visible: !face.visible
        text: (root.current.realName || root.currentUser || "?").charAt(0).toUpperCase()
        color: "#b4a7ff"
        font.family: root.fontFamily
        font.pixelSize: avatar.width * 0.48
        font.weight: Font.DemiBold
      }
    }

    // ‹ name › — click the arrows, or Left/Right/Up/Down/Tab.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 16

      Text {
        visible: root.users.length > 1
        text: "‹"
        color: prevArea.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: Math.round(root.height * 0.03)
        anchors.verticalCenter: parent.verticalCenter
        MouseArea {
          id: prevArea
          anchors.fill: parent
          anchors.margins: -12
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cycleUser(-1)
        }
      }
      Text {
        text: root.current.realName || root.currentUser
        color: "white"
        font.family: root.fontFamily
        font.pixelSize: Math.round(root.height * 0.02)
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        visible: root.users.length > 1
        text: "›"
        color: nextArea.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: Math.round(root.height * 0.03)
        anchors.verticalCenter: parent.verticalCenter
        MouseArea {
          id: nextArea
          anchors.fill: parent
          anchors.margins: -12
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cycleUser(1)
        }
      }
    }

    // Password pill with the arrow button beside it.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 10

      Rectangle {
        width: Math.round(root.height * 0.17)
        height: Math.round(root.height * 0.03)
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.22)
        border.color: root.loginFailed ? "#f7768e" : (password.activeFocus ? Qt.rgba(1, 1, 1, 0.55) : "transparent")
        border.width: 1

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          passwordCharacter: "●"
          color: "white"
          font.family: root.fontFamily
          font.pixelSize: parent.height * 0.5
          clip: true
          focus: true
          onTextChanged: root.loginFailed = false

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.login()
              event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
              root.cycleUser(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
              root.cycleUser(1)
              event.accepted = true
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 14
          visible: password.text.length === 0
          text: root.loginFailed ? "Wrong password" : "Password"
          color: root.loginFailed ? "#f7768e" : Qt.rgba(1, 1, 1, 0.55)
          font.family: root.fontFamily
          font.pixelSize: parent.height * 0.42
        }
      }

      Image {
        source: "assets/login.svg"
        width: Math.round(root.height * 0.024)
        height: width
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        anchors.verticalCenter: parent.verticalCenter
        opacity: loginArea.containsMouse ? 1 : 0.75
        MouseArea {
          id: loginArea
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.login()
        }
      }
    }
  }

  // Sleep / Restart / Shut Down.
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.height * 0.72
    spacing: Math.round(root.height * 0.045)

    Repeater {
      model: [
        { label: "Sleep", icon: "assets/suspend.svg", action: "suspend" },
        { label: "Restart", icon: "assets/reboot.svg", action: "reboot" },
        { label: "Shut Down", icon: "assets/shutdown.svg", action: "powerOff" }
      ]

      // An Item around the Column: a MouseArea can't anchors.fill inside a Column.
      Item {
        id: powerButton
        required property var modelData
        width: powerColumn.implicitWidth
        height: powerColumn.implicitHeight
        opacity: powerArea.containsMouse ? 1 : 0.8

      Column {
        id: powerColumn
        spacing: 8

        Image {
          anchors.horizontalCenter: parent.horizontalCenter
          source: powerButton.modelData.icon
          width: Math.round(root.height * 0.034)
          height: width
          sourceSize.width: width * 2
          sourceSize.height: height * 2
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: powerButton.modelData.label
          color: "white"
          font.family: root.fontFamily
          font.pixelSize: Math.round(root.height * 0.0135)
        }
      }

        MouseArea {
          id: powerArea
          anchors.fill: parent
          anchors.margins: -8
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (powerButton.modelData.action === "suspend") sddm.suspend()
            else if (powerButton.modelData.action === "reboot") sddm.reboot()
            else sddm.powerOff()
          }
        }
      }
    }
  }

  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: 14
    text: "Desktop Session: " + root.sessionName
    color: Qt.rgba(1, 1, 1, 0.8)
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.height * 0.012)
  }

  Component.onCompleted: password.forceActiveFocus()
}
