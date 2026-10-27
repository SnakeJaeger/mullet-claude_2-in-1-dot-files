import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Desktop settings hub: a sidebar of categories, a Home page (search across
// every setting, category tiles, device-settings apps), and the pages below.
// Originally: a switch for every animation "cluster" and sliders for
// their speeds. Writes ~/.config/omarchy/daa-ui.json, which the plugins (and
// hypr/dropdowns.lua, ~/.local/bin/cursor-to-tray) watch, so changes apply
// live. A key that isn't in the file means its default (on, 1×).
// Open with SUPER + CTRL + ALT + S or "/settings" in the quick search.
// The Favorites tab picks the Omarchy logo card's shortcuts
// (daa.desktop-shortcuts): top-row order, any installed app, and which
// bottom-row shortcuts show.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string path: Quickshell.env("HOME") + "/.config/omarchy/daa-ui.json"
  property var ui: ({})

  // Sections of rows. A row is a switch, a slider (min..max, shown as
  // ×speed) that dims while its `dep` switch is off, or a choice (pill
  // buttons; `options` are [value, label] pairs).
  readonly property var sections: [
    { title: "Go menu", page: "gomenu", rows: [
      { key: "goMenuStyle", label: "Entrance", choice: true, def: "swing",
        options: [["off", "Off"], ["fade", "Fade"], ["slide", "Slide"], ["swing", "Swing"]] },
      { key: "goMenuAnimations", label: "Extras", hint: "Bouncing cards, slinky sidebar, dealt footer" },
      { key: "duel", label: "Sword fight", hint: "The stick-figure duel under the list" } ] },
    { title: "Go menu contents", page: "gomenu", rows: [
      { key: "goCardStats", label: "System card", hint: "CPU, memory, disk, temperature, internet" },
      { key: "goCardLab", label: "Lab card", hint: "Tailscale heartbeat to the lab" },
      { key: "goCardServer", label: "Server card", hint: "Lab services (Desktop settings → Lab)" },
      { key: "goCardPhone", label: "Phone card", hint: "KDE Connect" },
      { key: "goSidebarHidden", label: "Network buttons", hint: "Lit = shown", multi: true, invert: true,
        options: [["Terminal", "Terminal"], ["Lab server", "Lab"], ["GNS3", "GNS3"], ["Tailscale", "Tailscale"], ["Mullvad VPN", "Mullvad"]] },
      { key: "goFooterHidden", label: "Footer buttons", hint: "Lit = shown", multi: true, invert: true,
        options: [["Apps", "Apps"], ["Keybinds", "Keybinds"], ["Tablet", "Tablet"], ["Settings", "Settings"], ["System", "System"]] } ] },
    { title: "App launcher (SUPER + R)", page: "motion", rows: [
      { key: "launcherTrails", label: "Light trails", hint: "Round the Omarchy logo frame" },
      { key: "launcherTrailSpeed", label: "Trail speed", slider: true, min: 0.25, max: 3, def: 1, dep: "launcherTrails" } ] },
    { title: "Omarchy logo card", page: "motion", rows: [
      { key: "shortcutCardAnimations", label: "Bloom", hint: "Logo grows, stem drops, card blooms, tiles flip" },
      { key: "shortcutCardTrails", label: "Comet trails", hint: "Round the island, stem and card" },
      { key: "shortcutCardTrailSpeed", label: "Comet speed", slider: true, min: 0.25, max: 3, def: 1, dep: "shortcutCardTrails" } ] },
    { title: "Workspaces", page: "windows", rows: [
      { key: "workspaceSpring", label: "Indicator spring", hint: "Squeeze and spring between workspaces" },
      { key: "magellanic", label: "Magellanic lap", hint: "SUPER + ALT + number goes round the whole bar" },
      { key: "magellanicSpeed", label: "Lap speed", slider: true, min: 0.5, max: 2.5, def: 1, dep: "magellanic" },
      { key: "visibleWorkspaces", label: "Workspaces shown", hint: "Always in the bar; more appear when in use", slider: true, min: 2, max: 10, def: 5, step: 1, unit: "" },
      { key: "workspaceCollapse", label: "Close gaps between workspaces", hint: "Fix: an emptied workspace's neighbours shift down" } ] },
    { title: "Windows", page: "windows", rows: [
      { key: "windowGapsIn", label: "Gap between windows", slider: true, min: 0, max: 20, def: 5, step: 1, unit: " px" },
      { key: "windowGapsOut", label: "Gap to screen edge", slider: true, min: 0, max: 30, def: 10, step: 1, unit: " px" },
      { key: "windowBorder", label: "Border width", slider: true, min: 0, max: 5, def: 1, step: 1, unit: " px" },
      { key: "windowRounding", label: "Corner rounding", slider: true, min: 0, max: 20, def: 6, step: 1, unit: " px" } ] },
    { title: "Notifications", page: "notifications", rows: [
      { key: "notificationSeconds", label: "Shown for", hint: "Hover still pauses; critical ones stay", slider: true, min: 3, max: 60, def: 10, step: 1, unit: " s" },
      { key: "notificationHistory", label: "History kept", hint: "In the bell's panel", slider: true, min: 10, max: 200, def: 50, step: 5, unit: "" },
      { key: "quietHours", label: "Quiet hours", hint: "Do Not Disturb every day between these hours" },
      { key: "quietFrom", label: "From", slider: true, min: 0, max: 23, def: 22, step: 1, unit: ":00", dep: "quietHours" },
      { key: "quietTo", label: "Until", slider: true, min: 0, max: 23, def: 7, step: 1, unit: ":00", dep: "quietHours" },
      { key: "mutedApps", label: "Muted apps", hint: "Straight to the bell's history, no toast", multi: true } ] },
    { title: "Quick search and info bar", page: "motion", rows: [
      { key: "infoBarStyle", label: "Info bar entrance", choice: true, def: "fade",
        options: [["off", "Off"], ["fade", "Fade"], ["rise", "Rise"], ["pop", "Pop"]] },
      { key: "breathingBorders", label: "Breathing borders", hint: "Cyan-to-coral borders that fade in and out" },
      { key: "breathingSpeed", label: "Breathing speed", slider: true, min: 0.25, max: 3, def: 1, dep: "breathingBorders" } ] },
    { title: "Power bar (SUPER + ESC)", page: "power", rows: [
      { key: "powerScreensaver", label: "Screensaver", hint: "S" },
      { key: "powerLock", label: "Lock", hint: "L" },
      { key: "powerSuspend", label: "Suspend", hint: "U" },
      { key: "powerHibernate", label: "Hibernate", hint: "H (needs a swap file or partition)" },
      { key: "powerReboot", label: "Reboot", hint: "R" },
      { key: "powerLogout", label: "Logout", hint: "O" },
      { key: "powerShutdown", label: "Shutdown", hint: "D" },
      { key: "powerOrder", label: "Order", choice: true, def: "gentleFirst",
        options: [["gentleFirst", "Screensaver first"], ["shutdownFirst", "Shutdown first"]] } ] },
    { title: "Battery", page: "power", rows: [
      { key: "batteryCalm", label: "Calm on power-saver", hint: "Pause decorative animations on the power-saver profile" } ] },
    { title: "Claude terminal shade", page: "bar", rows: [
      { key: "termShade", label: "Shade under the bar", hint: "Darkens the top of the SUPER + C terminal while it's open" },
      { key: "termShadePercent", label: "Height", slider: true, min: 3, max: 15, def: 6, step: 1, unit: " %", dep: "termShade" },
      { key: "termShadeStrength", label: "Darkness", slider: true, min: 0.2, max: 1, def: 0.6, dep: "termShade" } ] },
    { title: "Bar", page: "bar", rows: [
      { key: "barAlertPulse", label: "Pulsing alerts", hint: "Notification bell and update count" } ] },
    { title: "Cursor", page: "motion", rows: [
      { key: "cursorGlide", label: "Glide to the tray", hint: "From the info bar's Wi-Fi, battery, Bluetooth" },
      { key: "cursorCenterDropdowns", label: "Centre on dropdowns", hint: "Jump to the middle of a dropdown when it shows" } ] },
    { title: "Greeter", page: "tablet", rows: [
      { key: "tabletGreeter", label: "Greet tablet mode", hint: "Tiles for what you came to do, when the screen folds back" },
      { key: "tabletContinue", label: "Continue tiles", hint: "Pick up the last book, comic, drawing or show where you left off" },
      { key: "tabletTurnstile", label: "Turnstile", hint: "Tiles swing in and out" },
      { key: "tabletGreeterOpacity", label: "Background opacity", hint: "The box behind the tiles, and the dimming", slider: true, min: 15, max: 100, def: 85, step: 5, unit: " %" },
      { key: "tabletTileColors", label: "Tile colour", choice: true, def: "accent",
        options: [["accent", "Tablet colour"], ["palette", "Theme colours"], ["dark", "Dark"]] },
      { key: "tabletTileIcons", label: "Icons", choice: true, def: "colour",
        options: [["colour", "Full colour"], ["mono", "White"]] } ] },
    { title: "Tablet bar", page: "tablet", rows: [
      { key: "tabletBarStyle", label: "Style", choice: true, def: "solid",
        options: [["solid", "Solid"], ["floating", "Floating"], ["glass", "Glass"], ["clear", "Clear"]] },
      { key: "tabletBarSize", label: "Size", hint: "Bigger is easier to hit", slider: true, min: 0.7, max: 1.8, def: 1 } ] },
    { title: "Tablet text", page: "tablet", rows: [
      { key: "tabletTextScale", label: "Text size", hint: "Bar, menus and pop-ups while in tablet mode (laptop is 1×)", slider: true, min: 1, max: 2, def: 1.5 } ] },
    { title: "Easter eggs", page: "motion", rows: [
      { key: "konami", label: "Konami code", hint: "Comet storm in the quick search" },
      { key: "abacabb", label: "ABACABB", hint: "A minute of coral, and a decisive duel" } ] }
  ]

  // Switches that start off (the rest start on).
  readonly property var offByDefault: ["quietHours", "powerSuspend", "powerHibernate"]
  // The apps that sent the most notifications (from the bell's history),
  // plus any already muted: the choices for "Muted apps".
  property var recentApps: []
  Process {
    id: appsProc
    running: root.opened
    command: ["bash", "-c", "cat ~/.local/state/omarchy/notifications/history/*.json 2>/dev/null | jq -r '.app // empty' | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn | head -4 | awk '{print $2}'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var apps = String(text || "").split("\n").filter(function(a) { return a.length > 0 })
        var muted = root.ui.mutedApps || []
        for (var i = 0; i < muted.length; i++) if (apps.indexOf(muted[i]) === -1) apps.push(muted[i])
        root.recentApps = apps
      }
    }
  }

  function value(row) {
    var v = root.ui[row.key]
    if (v === undefined || v === null) return row.slider || row.choice ? row.def : row.multi ? [] : root.offByDefault.indexOf(row.key) === -1
    return v
  }

  function set(key, v) {
    var next = {}
    for (var k in root.ui) next[k] = root.ui[k]
    next[key] = v
    root.ui = next
    saveTimer.restart()
  }

  // Reset this page's settings only: its sections' keys (and the colours on
  // the Themes page), or the favourites on the logo-card page.
  function reset() {
    var next = {}
    for (var k in root.ui) next[k] = root.ui[k]
    if (root.page === "favorites") {
      delete next.favorites; delete next.shortcutsHidden; delete next.favoriteIconColor
    } else {
      for (var i = 0; i < root.sections.length; i++) {
        if (root.sections[i].page !== root.page) continue
        for (var j = 0; j < root.sections[i].rows.length; j++) delete next[root.sections[i].rows[j].key]
      }
      if (root.page === "look") { delete next.accentColor; delete next.accent2Color }
      if (root.page === "tablet") { delete next.tabletTiles; delete next.tabletAccent }
    }
    root.ui = next
    saveTimer.restart()
  }
  readonly property bool pageResettable: root.page === "favorites" || root.page === "look"
    || root.sections.some(function(sec) { return sec.page === root.page })

  // ---- Hub navigation ----
  // Sidebar: groups of pages. `keywords` feed the Home search.
  readonly property var nav: [
    { page: "home", icon: "󰋜", label: "Home" },
    { group: "Look and feel" },
    { page: "look", icon: "󰏘", label: "Themes and colours", keywords: "icons cursor accent colour color theme" },
    { page: "motion", icon: "󰄄", label: "Motion", keywords: "animations speed trails comets launcher cursor easter eggs" },
    { page: "bar", icon: "󰕮", label: "Top bar", keywords: "islands widgets clock info bar quotes" },
    { page: "favorites", icon: "󰣇", label: "Logo card", keywords: "favorites favourites shortcuts icons" },
    { page: "tablet", icon: "󰓶", label: "Tablet", keywords: "tablet mode greeter tiles touch bar size style floating glass wallpaper accent colour text" },
    { group: "Desktop" },
    { page: "windows", icon: "󰖯", label: "Windows and workspaces", keywords: "gaps border rounding workspaces magellanic" },
    { page: "rules", icon: "󰖲", label: "Window rules", keywords: "opacity float pin always on top" },
    { page: "scratchpads", icon: "󰘔", label: "Dropdowns", keywords: "scratchpad builder dropdown" },
    { page: "keys", icon: "󰌌", label: "Keyboard shortcuts", keywords: "keybindings binds rebind hotkeys" },
    { page: "gomenu", icon: "󰮫", label: "Go menu", keywords: "cards sidebar footer entrance sword" },
    { group: "System" },
    { page: "devices", icon: "󰒓", label: "Device settings", keywords: "apps display sound network bluetooth printer disks phone" },
    { page: "notifications", icon: "󰂚", label: "Notifications", keywords: "quiet hours mute toast history" },
    { page: "power", icon: "󰐥", label: "Power", keywords: "power bar suspend hibernate battery" },
    { page: "startup", icon: "󰐊", label: "Startup", keywords: "login apps autostart preload" },
    { page: "login", icon: "󰍂", label: "Login screen", keywords: "sddm avatar background greeter" },
    { page: "backups", icon: "󰁯", label: "Backups", keywords: "checkpoint restore snapshot" },
    { group: "Network" },
    { page: "lab", icon: "󰒋", label: "Lab", keywords: "gns3 tailscale vnc ssh server services api" }
  ]
  readonly property var navPage: {
    for (var i = 0; i < root.nav.length; i++) if (root.nav[i].page === root.page) return root.nav[i]
    return root.nav[0]
  }
  function isPage(p) {
    if (!p) return false
    for (var i = 0; i < root.nav.length; i++) if (root.nav[i].page === p) return true
    return false
  }
  // Open a page; `key` flashes and scrolls to that setting, `filter` searches
  // the Keys page.
  property string highlightKey: ""
  function go(p, key, filter) {
    root.page = root.isPage(p) ? p : "home"
    flick.contentY = 0
    root.highlightKey = key || ""
    if (key) highlightTimer.restart()
    if (p === "keys" && filter !== undefined) Qt.callLater(function() {
      if (!keysLoader.item) return
      keysLoader.item.filter = filter
      keysLoader.item.reload()
    })
  }
  Timer { id: highlightTimer; interval: 2600; onTriggered: root.highlightKey = "" }

  // ---- Device settings: the shell's own panels plus other apps that control
  // the hardware. Apps are found by their desktop-file categories (or a known
  // list); hubApps adds any app, hubAppsHidden hides one, hubAppCats moves one.
  readonly property var deviceCats: [
    ["display", "Display", "󰍹"], ["sound", "Sound", "󰕾"], ["network", "Network", "󰖩"],
    ["bluetooth", "Bluetooth", "󰂯"], ["input", "Keyboard and input", "󰌌"], ["power", "Power", "󰂄"],
    ["storage", "Storage", "󰋊"], ["printing", "Printing", "󰐪"], ["phone", "Phone", "󰄜"],
    ["appearance", "Appearance", "󰏘"], ["other", "Other", "󰒓"]
  ]
  readonly property string trayTool: Quickshell.env("HOME") + "/.local/bin/cursor-to-tray"
  readonly property var devicePanels: [
    { id: "panel:network", name: "Wi-Fi and network", glyph: "󰖩", cat: "network", panel: ["daa.network", "omarchy.network"] },
    { id: "panel:audio", name: "Sound", glyph: "󰕾", cat: "sound", panel: ["daa.audio", "omarchy.audio"] },
    { id: "panel:monitor", name: "Display and brightness", glyph: "󰍹", cat: "display", panel: ["daa.monitor", "omarchy.monitor"] },
    { id: "panel:bluetooth", name: "Bluetooth", glyph: "󰂯", cat: "bluetooth", panel: ["daa.bluetooth", "omarchy.bluetooth"] },
    { id: "panel:power", name: "Battery and power profile", glyph: "󰂄", cat: "power", panel: ["daa.power", "omarchy.power"] }
  ]
  readonly property var knownDeviceApps: ({
    "org.gnome.DiskUtility": "storage", "org.kde.kdeconnect.app": "phone", "mullvad-vpn": "network",
    "pavucontrol": "sound", "org.pulseaudio.pavucontrol": "sound", "com.saivert.pwvucontrol": "sound",
    "blueman-manager": "bluetooth", "nm-connection-editor": "network", "gparted": "storage",
    "org.gnome.baobab": "storage", "nwg-displays": "display", "network.cycles.wdisplays": "display",
    "org.gnome.Settings": "other", "systemsettings": "other"
  })
  readonly property var deviceAppCategories: ["Settings", "HardwareSettings", "DesktopSettings", "Printing", "X-GNOME-NetworkSettings"]
  function guessDeviceCat(text) {
    var t = text.toLowerCase()
    var rules = [["display", /display|monitor|wdisplay|arandr|screen/], ["sound", /audio|sound|pulse|pipewire|pavu|volume|easyeffects/],
      ["bluetooth", /blue/], ["printing", /print|cups/], ["network", /network|wifi|nm-|vpn|tailscale|mullvad|remmina/],
      ["input", /fcitx|input|keyboard|mouse|voxtype|ibus|tablet/], ["power", /power|battery|tlp/],
      ["storage", /disk|partition|storage|gparted|baobab/], ["phone", /kdeconnect|phone/],
      ["appearance", /qt6ct|qt5ct|theme|kvantum|aether|appearance|desktopsettings|look/]]
    for (var i = 0; i < rules.length; i++) if (rules[i][1].test(t)) return rules[i][0]
    return "other"
  }
  function appIcon(app) {
    var icon = String(app.icon || "")
    return icon.charAt(0) === "/" ? "file://" + icon : Quickshell.iconPath(icon || "application-x-executable", true)
  }
  // Every device control, hidden ones included (flagged).
  readonly property var allDeviceItems: {
    var hidden = root.ui.hubAppsHidden || [], added = root.ui.hubApps || [], cats = root.ui.hubAppCats || {}
    var out = []
    for (var i = 0; i < root.devicePanels.length; i++) {
      var d = root.devicePanels[i]
      out.push({ id: d.id, name: d.name, glyph: d.glyph, icon: "", cat: cats[d.id] || d.cat, panel: d.panel,
                 builtin: true, added: false, hidden: hidden.indexOf(d.id) !== -1 })
    }
    var apps = DesktopEntries.applications.values || []
    for (var j = 0; j < apps.length; j++) {
      var a = apps[j]
      if (!a || a.noDisplay) continue
      var id = String(a.id), appCats = a.categories || []
      var auto = root.knownDeviceApps[id] !== undefined
      for (var c = 0; c < appCats.length && !auto; c++) auto = root.deviceAppCategories.indexOf(String(appCats[c])) !== -1
      var isAdded = added.indexOf(id) !== -1
      if (!auto && !isAdded) continue
      out.push({ id: id, name: String(a.name), glyph: "", icon: root.appIcon(a), builtin: false, added: isAdded,
                 cat: cats[id] || root.knownDeviceApps[id] || root.guessDeviceCat(id + " " + a.name + " " + appCats.join(" ")),
                 hidden: hidden.indexOf(id) !== -1 })
    }
    return out
  }
  readonly property var deviceItems: root.allDeviceItems.filter(function(d) { return !d.hidden })
  function launchDevice(d) {
    root.dismiss()
    if (d.panel) Quickshell.execDetached([root.trayTool, d.panel[0], d.panel[1]])
    else Quickshell.execDetached(["uwsm-app", "--", d.id + ".desktop"])
  }
  function setListKey(key, id, on) {
    var list = (root.ui[key] || []).filter(function(x) { return x !== id })
    if (on) list.push(id)
    root.set(key, list)
  }
  function setDeviceCat(id, cat) {
    var m = {}
    var cur = root.ui.hubAppCats || {}
    for (var k in cur) m[k] = cur[k]
    m[id] = cat
    root.set("hubAppCats", m)
  }

  // ---- Favorites: the Omarchy logo card (daa.desktop-shortcuts) ----
  property string page: "home"
  property string favFilter: ""
  // Built-in shortcuts the card knows (labels here, the rest lives there).
  readonly property var builtinLabels: ({
    firefox: "Firefox", obsidian: "Obsidian", sublime: "Sublime", jellyfin: "Jellyfin",
    immich: "Immich", gns3: "GNS3", esde: "ES-DE"
  })
  readonly property var bottomShortcuts: [
    ["terminal", "Terminal"], ["tailscale", "Tailscale"], ["lab", "Lab"], ["mullvad", "Mullvad"],
    ["home", "Home"], ["documents", "Documents"], ["downloads", "Downloads"]
  ]
  readonly property var defaultFavorites: ["firefox", "obsidian", "sublime", "jellyfin", "immich", "gns3", "esde"]
  readonly property var favorites: root.ui.favorites || root.defaultFavorites
  readonly property var hiddenShortcuts: root.ui.shortcutsHidden || []

  // Same check as the card (daa.desktop-shortcuts `needs`): built-ins whose
  // app isn't installed are marked, and the card skips them.
  readonly property var needs: ({
    obsidian: "obsidian", sublime: "subl", jellyfin: "jellyfin-desktop", gns3: "gns3",
    immich: "~/.local/bin/server-status", esde: "es-de|retroarch", tailscale: "tailscale",
    lab: "remmina", mullvad: "mullvad"
  })
  property var missing: []
  Process {
    id: missingProc
    command: ["bash", "-c",
      "while read -r key alts; do ok=; IFS='|' read -ra opts <<<\"$alts\"; " +
      "for o in \"${opts[@]}\"; do o=${o/#\\~/$HOME}; " +
      "if [[ $o == /* ]]; then [[ -x $o ]] && ok=1; else command -v \"$o\" >/dev/null && ok=1; " +
      "[[ -x $HOME/.local/bin/$o ]] && ok=1; fi; done; [[ $ok ]] || echo \"$key\"; done"]
    stdinEnabled: true
    onStarted: {
      var lines = []
      for (var k in root.needs) lines.push(k + " " + root.needs[k])
      write(lines.join("\n") + "\n")
      stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.missing = String(text || "").split("\n").filter(function(l) { return l.length > 0 })
    }
  }
  function notInstalled(key) { return root.missing.indexOf(key) !== -1 }

  function favLabel(key) {
    if (root.builtinLabels[key]) return root.builtinLabels[key]
    var app = DesktopEntries.byId(key)
    return app ? String(app.name) : key
  }
  function favIcon(key) {
    var app = root.builtinLabels[key] ? null : DesktopEntries.byId(key)
    var icon = app ? String(app.icon || "") : ""
    if (!app) return ""
    return icon.charAt(0) === "/" ? "file://" + icon : Quickshell.iconPath(icon || "application-x-executable", true)
  }
  function moveFav(i, d) {
    var list = root.favorites.slice()
    var j = i + d
    if (j < 0 || j >= list.length) return
    var t = list[i]; list[i] = list[j]; list[j] = t
    root.set("favorites", list)
  }
  function removeFav(i) {
    var list = root.favorites.slice()
    list.splice(i, 1)
    root.set("favorites", list)
  }
  function addFav(key) {
    if (root.favorites.indexOf(key) !== -1) return
    root.set("favorites", root.favorites.concat([key]))
  }
  function toggleHidden(key) {
    var list = root.hiddenShortcuts.slice()
    var at = list.indexOf(key)
    if (at === -1) list.push(key)
    else list.splice(at, 1)
    root.set("shortcutsHidden", list)
  }
  // Apps (and unused built-ins) matching the filter, not already favourites.
  readonly property var favCandidates: {
    var q = root.favFilter.trim().toLowerCase()
    var out = []
    for (var k in root.builtinLabels)
      if (root.favorites.indexOf(k) === -1 && (!q || root.builtinLabels[k].toLowerCase().indexOf(q) !== -1))
        out.push({ key: k, label: root.builtinLabels[k] + (root.notInstalled(k) ? "  (built-in, not installed)" : "  (built-in)"), icon: "" })
    if (q) {
      var apps = DesktopEntries.applications.values || []
      for (var i = 0; i < apps.length && out.length < 8; i++) {
        var a = apps[i]
        if (!a || a.noDisplay || !a.name) continue
        var id = String(a.id || "")
        if (!id || root.favorites.indexOf(id) !== -1) continue
        if (String(a.name).toLowerCase().indexOf(q) === -1) continue
        var ic = String(a.icon || "")
        out.push({ key: id, label: String(a.name),
          icon: ic.charAt(0) === "/" ? "file://" + ic : Quickshell.iconPath(ic || "application-x-executable", true) })
      }
    }
    return out.slice(0, 8)
  }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      if (!saveTimer.running) { try { root.ui = JSON.parse(text() || "{}") } catch (e) {} }
      applyTimer.restart()
    }
    onLoadFailed: { root.ui = ({}); applyTimer.restart() }   // file deleted: all defaults
  }

  // Sliders write as they move; batch the writes.
  Timer {
    id: saveTimer
    interval: 150
    onTriggered: { file.setText(JSON.stringify(root.ui, null, 2) + "\n"); applyTimer.restart() }
  }

  // ---- Accent colours (whole shell + window border) ----
  // "accentColor" / "accent2Color" override the theme's accent and red (the
  // second accent: the coral role). Applied to the shell's colour singleton
  // (so every widget follows) and the Hyprland border; re-applied after a
  // theme switch, since the theme reload resets the singleton.
  property color themeAccent: Commons.Color.accent
  property color themeRed: Commons.Color.urgent
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var t = String(text())
      function pick(key) {
        var m = t.match(new RegExp("^\\s*" + key + "\\s*=\\s*[\"']?(#[0-9a-fA-F]{6})", "m"))
        return m ? m[1] : null
      }
      root.themeAccent = pick("accent") || pick("color4") || "#7dcfff"
      root.themeRed = pick("red") || pick("color1") || "#f7768e"
      applyTimer.restart()
    }
  }
  Timer {
    id: applyTimer
    interval: 400
    onTriggered: root.applyColors()
  }
  function applyColors() {
    // Leave ABACABB blood mode (daa.search) alone; it restores on its own.
    if (Qt.colorEqual(Commons.Color.accent, "#e0607a") && root.ui.accentColor !== "#e0607a") return
    Quickshell.execDetached(["hyprctl", "eval", "daa_apply_window_settings()"])
    Commons.Color.accent = root.ui.accentColor || root.themeAccent
    Commons.Color.urgent = root.ui.accent2Color || root.themeRed
    Quickshell.execDetached(["hyprctl", "eval",
      'local a, b = daa_accent_colors(); hl.config({ general = { col = { active_border = { colors = { "rgb(" .. a .. ")", "rgb(" .. b .. ")" }, angle = 45 } } } })'])
  }
  // ---- Calm mode: pause decorative animations on the power-saver profile ----
  // ("batteryCalm", default on). Writes ~/.local/state/daa/calm (1 / 0),
  // which every animated plugin watches.
  property string powerProfile: ""
  Process {
    id: profileProbe
    command: ["powerprofilesctl", "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { root.powerProfile = String(text).trim(); root.writeCalm() }
    }
  }
  Timer { interval: 15000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!profileProbe.running) profileProbe.running = true }
  FileView { id: calmFile; path: Quickshell.env("HOME") + "/.local/state/daa/calm"; printErrors: false }
  property string lastCalm: ""
  function writeCalm() {
    var on = root.ui.batteryCalm !== false && root.powerProfile === "power-saver" ? "1" : "0"
    if (on !== root.lastCalm) { root.lastCalm = on; calmFile.setText(on + "\n") }
  }
  onUiChanged: writeCalm()

  readonly property var swatches: ["#7dcfff", "#7aa2f7", "#bb9af7", "#ff79c6", "#f7768e", "#ff9e64", "#e0af68", "#9ece6a", "#73daca", "#e6e6e6"]

  function open(payloadJson) {
    // {"page": "favorites"} opens straight on that tab.
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    // Old tab names still work ("animations" is Motion now).
    var p = payload.page === "animations" ? "motion" : payload.page
    root.go(p, payload.key || "")
    // {"page":"keys","filter":"Firefox"}: open the Keys menu searching for it.
    if (payload.page === "keys") Qt.callLater(function() {
      if (!keysLoader.item) return
      keysLoader.item.filter = payload.filter || ""
      keysLoader.item.reload()
    })
    // The zap scope in pick mode hands a window back to the builder.
    if (payload.picked) Qt.callLater(function() {
      var l = payload.page === "rules" ? rulesLoader : scratchLoader
      if (l.item) l.item.loadPicked()
    })
    root.favFilter = ""
    missingProc.stdinEnabled = true
    missingProc.running = true
    root.opened = true
    // Home focuses its own search box.
    if (root.page !== "home") Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "daa.settings")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.menuFamily

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: if (visible) popIn.restart()
    ParallelAnimation {
      id: popIn
      NumberAnimation { target: dim; property: "opacity"; from: 0; to: 1; duration: 160 }
      NumberAnimation { target: box; property: "opacity"; from: 0; to: 1; duration: 140 }
      NumberAnimation { target: box; property: "scale"; from: 0.96; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }

    Rectangle {
      id: dim
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    // Clicks outside the box are swallowed rather than closing it; the hub
    // closes from its own close button or Escape.
    MouseArea {
      anchors.fill: parent
      onClicked: keys.forceActiveFocus()
    }

    Rectangle {
      id: closeButton
      z: 10
      anchors.top: box.top
      anchors.right: box.right
      anchors.margins: Style.space(12)
      width: Style.space(32)
      height: width
      radius: width / 2
      scale: box.scale
      opacity: box.opacity
      color: closeArea.containsMouse ? Util.alpha(Commons.Color.urgent, 0.25) : Qt.rgba(1, 1, 1, 0.06)
      Text {
        anchors.centerIn: parent
        text: "󰅖"
        color: closeArea.containsMouse ? Commons.Color.urgent : root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      MouseArea {
        id: closeArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keys
      focus: true
      Keys.onEscapePressed: root.dismiss()
    }

    Rectangle {
      id: box
      width: Math.min(parent.width - Style.space(40), Style.space(960))
      height: Math.min(parent.height - Style.space(40), Style.space(720))
      anchors.centerIn: parent
      radius: Style.space(14)
      color: root.background
      clip: true

      // Clicks inside don't close it.
      MouseArea { anchors.fill: parent }

      // Sidebar: Home, then the groups of pages.
      Rectangle {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(220)
        color: Qt.rgba(1, 1, 1, 0.03)

        Text {
          id: hubTitle
          x: Style.space(16)
          y: Style.space(16)
          text: "Settings"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Flickable {
          anchors.top: hubTitle.bottom
          anchors.topMargin: Style.space(10)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(10)
          contentHeight: navCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          clip: true

          Column {
            id: navCol
            width: parent.width
            Repeater {
              model: root.nav
              Item {
                id: navItem
                required property var modelData
                readonly property bool current: !!modelData.page && root.page === modelData.page
                width: navCol.width
                height: modelData.group ? Style.space(30) : Style.space(32)
                Text {
                  visible: !!navItem.modelData.group
                  x: Style.space(16)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(4)
                  text: (navItem.modelData.group || "").toUpperCase()
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }
                Rectangle {
                  visible: !navItem.modelData.group
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  radius: Style.space(8)
                  color: navItem.current ? Util.alpha(root.accent, 0.18) : navArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                  Rectangle {
                    visible: navItem.current
                    width: Style.space(3)
                    height: parent.height - Style.space(12)
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.accent
                  }
                  Text {
                    id: navIcon
                    x: Style.space(12)
                    width: Style.space(20)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: navItem.modelData.icon || ""
                    color: navItem.current ? root.accent : root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    anchors.left: navIcon.right
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: navItem.modelData.label || ""
                    elide: Text.ElideRight
                    color: navItem.current ? root.accent : root.foreground
                    opacity: navItem.current ? 1 : 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  MouseArea {
                    id: navArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.go(navItem.modelData.page)
                  }
                }
              }
            }
          }
        }
      }

      Flickable {
        id: flick
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(18)
        anchors.rightMargin: Style.space(54)   // room for the close button
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
          id: content
          width: flick.width
          spacing: Style.space(4)

          // Page title (with its icon) and, where it applies, Reset.
          Item {
            width: parent.width
            height: Style.space(40)
            visible: root.page !== "home"

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.navPage.icon || ""
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.navPage.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }

            Rectangle {
              id: resetButton
              visible: root.pageResettable
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: resetLabel.implicitWidth + Style.space(20)
              height: resetLabel.implicitHeight + Style.space(8)
              radius: Style.space(8)
              color: resetArea.containsMouse ? Util.alpha(root.accent, 0.2) : Qt.rgba(1, 1, 1, 0.06)
              Text {
                id: resetLabel
                anchors.centerIn: parent
                text: "Reset this page"
                color: resetArea.containsMouse ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                id: resetArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.reset()
              }
            }
          }

          // ---- Home page (HomePage.qml): search, categories, device apps ----
          Loader {
            id: homeLoader
            visible: root.page === "home"
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/HomePage.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
          }

          // ---- Device settings page (DevicesPage.qml) ----
          Loader {
            id: devicesLoader
            visible: root.page === "devices"
            active: root.page === "devices" || item !== null
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/DevicesPage.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
          }

          // ---- Bar page (BarPage.qml) ----
          Loader {
            id: barLoader
            visible: root.page === "bar"
            active: root.page === "bar" || item !== null
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/BarPage.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
            onVisibleChanged: if (visible && item) item.reload()
          }

          // ---- Rules page (WindowRules.qml) ----
          Loader {
            id: rulesLoader
            visible: root.page === "rules"
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/WindowRules.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
            onVisibleChanged: if (visible && item) item.reload()
          }

          // ---- Startup page (StartupPage.qml) ----
          Loader {
            id: startupLoader
            visible: root.page === "startup"
            active: root.page === "startup" || item !== null
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/StartupPage.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
            onVisibleChanged: if (visible && item) item.reload()
          }

          // ---- Lab page (LabPage.qml) ----
          Loader {
            id: labLoader
            visible: root.page === "lab"
            active: root.page === "lab" || item !== null
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/LabPage.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
            onVisibleChanged: if (visible && item && !item.dirty) item.reload()
          }

          // ---- Backups page (BackupsPage.qml) ----
          Loader {
            id: backupsLoader
            visible: root.page === "backups"
            active: root.page === "backups" || item !== null
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/BackupsPage.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
            onVisibleChanged: if (visible && item) item.reload()
          }

          // ---- Look page (LookPage.qml) ----
          Loader {
            id: lookLoader
            visible: root.page === "look"
            active: root.page === "look" || item !== null
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/LookPage.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
            onVisibleChanged: if (visible && item) item.reload()
          }

          // ---- Tablet page (TabletPage.qml): greeter tiles, colour, wallpaper ----
          Loader {
            id: tabletLoader
            visible: root.page === "tablet"
            active: root.page === "tablet" || item !== null
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/TabletPage.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
            onVisibleChanged: if (visible && item) item.reload()
          }

          // ---- Login page (LoginPage.qml) ----
          Loader {
            id: loginLoader
            visible: root.page === "login"
            active: root.page === "login" || item !== null
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/LoginPage.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
            onVisibleChanged: if (visible && item) item.reload()
          }

          // ---- Keys page (Keys.qml) ----
          Loader {
            id: keysLoader
            visible: root.page === "keys"
            active: root.page === "keys" || item !== null
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/Keys.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
          }

          // ---- Scratchpads page (Scratchpads.qml, the builder) ----
          Loader {
            id: scratchLoader
            visible: root.page === "scratchpads"
            width: content.width
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/daa.settings/Scratchpads.qml"
            onLoaded: { item.host = root; item.width = Qt.binding(function() { return content.width }) }
          }

          // ---- Favorites page ----
          Column {
            visible: root.page === "favorites"
            width: content.width
            spacing: Style.space(2)

            // Icon colour for app favourites (built-ins are already white).
            Item {
              width: content.width
              height: Style.space(44)
              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                Text { text: "Icon colour"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                Text { text: "Accent recolours everything; apps use their symbolic icon, a glyph or a badge"; color: root.foreground; opacity: 0.5
                  font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }
              Row {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Repeater {
                  model: [["original", "Original"], ["white", "White"], ["accent", "Accent"]]
                  Rectangle {
                    id: icPill
                    required property var modelData
                    readonly property bool current: (root.ui.favoriteIconColor || "original") === modelData[0]
                    width: icLabel.implicitWidth + Style.space(18)
                    height: Style.space(24)
                    radius: height / 2
                    color: current ? root.accent : icArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                    Text {
                      id: icLabel
                      anchors.centerIn: parent
                      text: icPill.modelData[1]
                      color: icPill.current ? Commons.Color.background : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea {
                      id: icArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.set("favoriteIconColor", icPill.modelData[0])
                    }
                  }
                }
              }
            }

            FavHeading { text: "TOP ROW (IN ORDER)" }

            Repeater {
              model: root.page === "favorites" ? root.favorites : []
              Rectangle {
                id: favRow
                required property var modelData
                required property int index
                width: content.width
                height: Style.space(36)
                radius: Style.space(8)
                color: favHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                HoverHandler { id: favHover }

                Image {
                  id: favImg
                  x: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(20); height: width
                  sourceSize.width: width * 2; sourceSize.height: height * 2
                  source: root.favIcon(favRow.modelData)
                  visible: source != ""
                }
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(40)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (favRow.index + 1) + ".  " + root.favLabel(favRow.modelData)
                    + (root.notInstalled(favRow.modelData) ? "   (not installed)" : "")
                  opacity: root.notInstalled(favRow.modelData) ? 0.45 : 1
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Row {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)
                  FavButton { glyph: "󰁝"; enabledButton: favRow.index > 0; onClicked: root.moveFav(favRow.index, -1) }
                  FavButton { glyph: "󰁅"; enabledButton: favRow.index < root.favorites.length - 1; onClicked: root.moveFav(favRow.index, 1) }
                  FavButton { glyph: "󰅖"; danger: true; onClicked: root.removeFav(favRow.index) }
                }
              }
            }

            FavHeading { text: "ADD"; topPadding: Style.space(10) }

            Rectangle {
              width: content.width
              height: Style.space(34)
              radius: Style.space(8)
              color: Qt.rgba(1, 1, 1, 0.06)
              Text {
                x: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍉"
                color: root.foreground
                opacity: 0.6
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.body
              }
              TextInput {
                id: favInput
                anchors.left: parent.left
                anchors.leftMargin: Style.space(34)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                clip: true
                onTextEdited: root.favFilter = text
                Keys.onEscapePressed: root.dismiss()
                Text {
                  visible: favInput.text === ""
                  text: "Type to find an app…"
                  color: root.foreground
                  opacity: 0.4
                  font: favInput.font
                }
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: favInput.forceActiveFocus() }
            }

            Repeater {
              model: root.page === "favorites" ? root.favCandidates : []
              Rectangle {
                id: candRow
                required property var modelData
                width: content.width
                height: Style.space(34)
                radius: Style.space(8)
                color: candArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                Image {
                  x: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(20); height: width
                  sourceSize.width: width * 2; sourceSize.height: height * 2
                  source: candRow.modelData.icon
                  visible: source != ""
                }
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(40)
                  anchors.verticalCenter: parent.verticalCenter
                  text: candRow.modelData.label
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰐕"
                  color: candArea.containsMouse ? root.accent : root.foreground
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Style.font.body
                }
                MouseArea {
                  id: candArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.addFav(candRow.modelData.key)
                }
              }
            }

            FavHeading { text: "BOTTOM ROW"; topPadding: Style.space(10) }

            Repeater {
              model: root.page === "favorites" ? root.bottomShortcuts : []
              Rectangle {
                id: botRow
                required property var modelData
                readonly property bool on: root.hiddenShortcuts.indexOf(modelData[0]) === -1
                width: content.width
                height: Style.space(36)
                radius: Style.space(8)
                color: botArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                Text {
                  x: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: botRow.modelData[1] + (root.notInstalled(botRow.modelData[0]) ? "   (not installed)" : "")
                  opacity: root.notInstalled(botRow.modelData[0]) ? 0.45 : 1
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Rectangle {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(40); height: Style.space(22)
                  radius: height / 2
                  color: botRow.on ? root.accent : Qt.rgba(1, 1, 1, 0.14)
                  Rectangle {
                    width: parent.height - Style.space(6); height: width; radius: width / 2
                    y: Style.space(3)
                    x: botRow.on ? parent.width - width - Style.space(3) : Style.space(3)
                    color: botRow.on ? Commons.Color.background : root.foreground
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                  }
                }
                MouseArea {
                  id: botArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleHidden(botRow.modelData[0])
                }
              }
            }
          }

          // ---- Colours (Animations tab) ----
          Column {
            visible: root.page === "look"
            width: content.width
            spacing: Style.space(2)
            topPadding: Style.space(8)

            FavHeading { text: "COLOURS" }

            Repeater {
              model: root.page === "look" ? [
                { key: "accentColor", label: "Accent", hint: "Highlights, indicators, borders" },
                { key: "accent2Color", label: "Second accent", hint: "Coral: alerts, gradients, comets" } ] : []

              Column {
                id: colRow
                required property var modelData
                readonly property string current: root.ui[modelData.key] || ""
                width: content.width
                spacing: Style.space(6)
                bottomPadding: Style.space(8)

                Item {
                  width: parent.width
                  height: Style.space(30)
                  Column {
                    x: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: colRow.modelData.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                    Text { text: colRow.modelData.hint; color: root.foreground; opacity: 0.5; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                  }
                  // Theme | #hex
                  Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)
                    Rectangle {
                      width: themeLabel.implicitWidth + Style.space(18)
                      height: Style.space(24)
                      radius: height / 2
                      color: colRow.current === "" ? root.accent : themeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                      Text {
                        id: themeLabel
                        anchors.centerIn: parent
                        text: "Theme"
                        color: colRow.current === "" ? Commons.Color.background : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                      MouseArea {
                        id: themeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          var next = {}
                          for (var k in root.ui) if (k !== colRow.modelData.key) next[k] = root.ui[k]
                          root.ui = next
                          saveTimer.restart()
                        }
                      }
                    }
                    Rectangle {
                      width: Style.space(84)
                      height: Style.space(24)
                      radius: Style.space(6)
                      color: Qt.rgba(1, 1, 1, 0.06)
                      TextInput {
                        id: hexInput
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(8)
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        maximumLength: 7
                        text: colRow.current
                        onEditingFinished: {
                          var v = text.trim()
                          if (v.charAt(0) !== "#") v = "#" + v
                          if (/^#[0-9a-fA-F]{6}$/.test(v)) root.set(colRow.modelData.key, v.toLowerCase())
                        }
                        Keys.onEscapePressed: root.dismiss()
                        Text {
                          visible: hexInput.text === ""
                          anchors.verticalCenter: parent.verticalCenter
                          text: "#hex"
                          color: root.foreground
                          opacity: 0.4
                          font: hexInput.font
                        }
                      }
                    }
                  }
                }

                // Swatches.
                Row {
                  x: Style.space(10)
                  spacing: Style.space(8)
                  Repeater {
                    model: root.swatches
                    Rectangle {
                      id: sw
                      required property string modelData
                      readonly property bool chosen: colRow.current === modelData
                      width: Style.space(26)
                      height: width
                      radius: width / 2
                      color: modelData
                      border.width: chosen ? 3 : swArea.containsMouse ? 2 : 0
                      border.color: root.foreground
                      MouseArea {
                        id: swArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.set(colRow.modelData.key, sw.modelData)
                      }
                    }
                  }
                }
              }
            }
          }

          Repeater {
            model: root.sections.filter(function(sec) { return sec.page === root.page })

            Column {
              id: section
              required property var modelData
              width: content.width
              spacing: Style.space(2)
              topPadding: Style.space(8)

              Text {
                text: section.modelData.title.toUpperCase()
                color: root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                bottomPadding: Style.space(2)
              }

              Repeater {
                model: section.modelData.rows

                Rectangle {
                  id: row
                  required property var modelData
                  readonly property bool isSlider: !!modelData.slider
                  readonly property bool isChoice: !!modelData.choice || !!modelData.multi
                  readonly property bool enabledRow: !modelData.dep || root.value({ key: modelData.dep }) !== false
                  width: section.width
                  height: Style.space(modelData.hint ? 44 : 36)
                  radius: Style.space(8)
                  readonly property bool flashed: root.highlightKey !== "" && root.highlightKey === modelData.key
                  color: flashed ? Util.alpha(root.accent, 0.2) : rowArea.containsMouse && !isSlider && !isChoice ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                  Behavior on color { ColorAnimation { duration: 300 } }
                  opacity: enabledRow ? 1 : 0.4
                  // A search result for this setting scrolls it into view.
                  function reveal() {
                    if (!flashed) return
                    Qt.callLater(function() {
                      var y = row.mapToItem(content, 0, 0).y
                      flick.contentY = Math.max(0, Math.min(y - Style.space(80), flick.contentHeight - flick.height))
                    })
                  }
                  onFlashedChanged: reveal()
                  Component.onCompleted: reveal()

                  Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.right: control.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(1)

                    Text {
                      text: row.modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      visible: !!row.modelData.hint
                      width: parent.width
                      text: row.modelData.hint || ""
                      color: root.foreground
                      opacity: 0.5
                      elide: Text.ElideRight
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // Whole row toggles a switch.
                  MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    enabled: !row.isSlider && !row.isChoice
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.set(row.modelData.key, !root.value(row.modelData))
                  }

                  Item {
                    id: control
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: row.isSlider ? Style.space(220) : row.isChoice ? choices.implicitWidth : Style.space(40)
                    height: Style.space(22)

                    // Choice: pills, the current one filled.
                    Row {
                      id: choices
                      visible: row.isChoice
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(4)
                      Repeater {
                        model: row.modelData.multi && !row.modelData.options ? root.recentApps.map(function(a) { return [a, a] })
                          : row.isChoice ? row.modelData.options : []
                        Rectangle {
                          id: pill
                          required property var modelData
                          readonly property bool current: row.modelData.multi ? (root.value(row.modelData).indexOf(modelData[0]) !== -1) !== !!row.modelData.invert
                            : root.value(row.modelData) === modelData[0]
                          width: pillLabel.implicitWidth + Style.space(18)
                          height: Style.space(24)
                          radius: height / 2
                          color: current ? root.accent : pillArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                          Behavior on color { ColorAnimation { duration: 120 } }
                          Text {
                            id: pillLabel
                            anchors.centerIn: parent
                            text: pill.modelData[1]
                            color: pill.current ? Commons.Color.background : root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                          }
                          MouseArea {
                            id: pillArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              if (!row.modelData.multi) return root.set(row.modelData.key, pill.modelData[0])
                              var list = root.value(row.modelData).slice()
                              var at = list.indexOf(pill.modelData[0])
                              if (at === -1) list.push(pill.modelData[0]); else list.splice(at, 1)
                              root.set(row.modelData.key, list)
                            }
                          }
                        }
                      }
                    }

                    // Switch.
                    Rectangle {
                      visible: !row.isSlider && !row.isChoice
                      readonly property bool on: root.value(row.modelData) === true
                      anchors.fill: parent
                      radius: height / 2
                      color: on ? root.accent : Qt.rgba(1, 1, 1, 0.14)
                      Behavior on color { ColorAnimation { duration: 120 } }
                      Rectangle {
                        width: parent.height - Style.space(6)
                        height: width
                        radius: width / 2
                        y: Style.space(3)
                        x: parent.on ? parent.width - width - Style.space(3) : Style.space(3)
                        color: parent.on ? Commons.Color.background : root.foreground
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                      }
                    }

                    // Slider: track, fill, knob, value.
                    Item {
                      id: slider
                      visible: row.isSlider
                      anchors.fill: parent
                      readonly property real v: row.isSlider ? Number(root.value(row.modelData)) : 0
                      readonly property real frac: row.isSlider ? (v - row.modelData.min) / (row.modelData.max - row.modelData.min) : 0
                      readonly property real trackWidth: width - valueText.width - Style.space(10)

                      Rectangle {
                        id: track
                        width: slider.trackWidth
                        height: Style.space(4)
                        radius: height / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.14)
                        Rectangle {
                          width: Math.max(height, parent.width * slider.frac)
                          height: parent.height
                          radius: parent.radius
                          color: root.accent
                        }
                      }
                      Rectangle {
                        width: Style.space(14)
                        height: width
                        radius: width / 2
                        x: track.width * slider.frac - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.foreground
                      }
                      Text {
                        id: valueText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(44)
                        horizontalAlignment: Text.AlignRight
                        text: row.modelData.unit !== undefined ? Math.round(slider.v) + row.modelData.unit
                          : slider.v.toFixed(2).replace(/0$/, "") + "×"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                      MouseArea {
                        width: track.width
                        height: parent.height
                        enabled: row.isSlider && row.enabledRow
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true
                        function apply(mx) {
                          var f = Math.max(0, Math.min(1, mx / track.width))
                          var v = row.modelData.min + f * (row.modelData.max - row.modelData.min)
                          var st = row.modelData.step || 0.05
                          root.set(row.modelData.key, Math.round(Math.round(v / st) * st * 100) / 100)
                        }
                        onPressed: function(mouse) { apply(mouse.x) }
                        onPositionChanged: function(mouse) { if (pressed) apply(mouse.x) }
                        onDoubleClicked: root.set(row.modelData.key, row.modelData.def)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component FavHeading: Text {
    color: root.foreground
    opacity: 0.5
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
    bottomPadding: Style.space(2)
  }

  component FavButton: Rectangle {
    property string glyph: ""
    property bool enabledButton: true
    property bool danger: false
    signal clicked()
    width: Style.space(26); height: width
    radius: Style.space(6)
    opacity: enabledButton ? 1 : 0.25
    color: favBtnArea.containsMouse && enabledButton ? Util.alpha(danger ? Commons.Color.urgent : root.accent, 0.2) : "transparent"
    Text {
      anchors.centerIn: parent
      text: parent.glyph
      color: favBtnArea.containsMouse && parent.enabledButton ? (parent.danger ? Commons.Color.urgent : root.accent) : root.foreground
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Style.font.body
    }
    MouseArea {
      id: favBtnArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: parent.enabledButton
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.clicked()
    }
  }
}
