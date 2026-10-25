# Desktop / tablet setup map

Everything here is user config; nothing under /usr/share/omarchy is modified.
Tablet mode is switched by the fold sensor via `~/.local/bin/tablet-mode`,
which swaps the desktop bar for the tablet bar and back.

## Shell plugins (`~/.config/omarchy/plugins/`)

### Desktop only — `daa.desktop-*`
| Plugin | What it is |
|---|---|
| `daa.desktop-bar` | Desktop bar (islands; status icons, clock and weather open their panels on hover; app island window list) |
| `daa.desktop-arch-menu` | Arch logo button → Go menu |
| `daa.desktop-workspaces` | Workspace dots; SUPER+ALT+digit goes to a workspace with the indicator lapping the whole bar ("magellanic desktop selection", IPC `daa.workspaces lap` from hypr/bindings.lua) |
| `daa.desktop-shortcuts` | Omarchy logo on its own island (Bar.qml logoEntries) after the left island; grows on hover; hover drops a stem-and-bloom card with a theme-gradient border trace and split-flap tiles of white shortcuts (Go menu Network column + Jellyfin/Firefox/Immich; Home/Documents/Downloads open the Files dropdown there) |
| `daa.updates` | Left end of the right island: pending updates (checkupdates + yay -Qua) with count; hidden at 0, white ≤20, cyan ≤30, slow coral blink above; click toggles the "update" dropdown (hypr/dropdowns.lua, upper right, slides from the right; recounts when the update ends) |
| `daa.notify-bell` | Right end of the right island: bell + notification count (live toasts + history files), slow coral pulse while any; hover/click slides a panel in from the right — click a notification to run its action/focus its app, × removes, Clear all |
| `daa.desktop-app-name` | Focused-app island next to the workspaces |
| `daa.desktop-media` | Now-playing island (only while playing) |
| `daa.desktop-indicators` | Clock island indicators (active ones beside the clock); shares its toggles with the sound / display / calendar panels via PanelToggles.qml; the tablet bar keeps the clock drop-down |

### Tablet only — `daa.tablet-*`
| Plugin | What it is |
|---|---|
| `daa.tablet-bar` | Touch bar shown in tablet mode |
| `daa.tablet-menu` | Arch button → tablet menu |
| `daa.tablet-workspace` | Current workspace / window list |
| `daa.tablet-apps` | App-grid button |
| `daa.tablet-apps-grid` | Touch app grid (list in `~/.config/tablet-mode/apps`) |
| `daa.tablet-keyboard` | On-screen keyboard button |
| `daa.tablet-rotate` | Rotate / rotation-lock button |
| `daa.tablet-quick` | Quick toggles button |
| `daa.tablet-media` | Play/pause button |

### Shared — plain `daa.*` (behave differently in tablet mode)
| Plugin | What it is |
|---|---|
| `daa.menu` | All menus (Go menu — Go menu: system (StatsCard.qml) / lab / server (ServerCard.qml: Jellyfin, Immich, calendar from ~/.config/lab-services/services via ~/.local/bin/server-status, plus Remmina counted up when the VNC port answers) / phone (PhoneCard.qml, KDE Connect via ~/.local/bin/phone-status) cards on the right that slide into the right wall and bounce; Apps / Terminal / Keys / Tablet / System footer dealt out like a card spread; the menu swings down from the Arch button —, tablet menu, quick toggles…); Go menu's Apps / Tablet / System bottom row stays in every Go submenu (hidden while searching); typing in the root menu adds a "Search all files" row (→ ~/.local/bin/file-search → Catfish dropdown); system (shutdown) menu is borderless, bottom-left, slides in from the left; menu keys go through ~/.local/bin/menu-toggle (re-press closes, other key switches); SUPER+K keybindings list is borderless, 600x720, top-left (10px in, 50px down), slides in from the left |
| `daa.clipboard` | Clipboard manager (SUPER+V, SUPER+CTRL+V), borderless, bottom-right, slides in from the right; header Clear button (= Shift+Delete, asks first) |
| `daa.launcher` | App launcher: search + Web/Utility/Create/Communicate/Entertain tabs (scroll rail in tablet mode) |
| `daa.search` | Quick search box (tap SUPER alone; release bind in hypr/bindings.lua): apps, then Search files (Catfish dropdown) / Search the web |
| `daa.osd` | On-screen display |
| `daa.background` | Wallpaper (tap = dismiss in tablet mode) |
| `daa.tray` | System tray, clone of omarchy.tray: the collapsed drawer takes no width; click the arrow to keep the drawer open (tablet bar: tap-only, wallpaper tap folds it); both BarModel.js files treat it as the tray |
| `daa.polkit` | Password (polkit) dialog, clone of omarchy.polkit: rises from the bottom, rests with its centre 1/3 up, drops on close |
| `daa.audio` | Sound panel, clone of omarchy.audio: + Do not disturb / Dictation chips |
| `daa.monitor` | Display panel, clone of omarchy.monitor: + Night light / Stay awake / Recording chips |
| `daa.clock` | Clock + calendar, clone of omarchy.clock: + Reminder chip; shell.json centerAnchor is daa.clock |
| `daa.weather` | Bar weather button, clone of omarchy.weather: left click toggles the GNOME Weather dropdown (SUPER+ALT+W, hypr/dropdowns.lua) instead of the popup; SUPER+CTRL+ALT+W still opens the popup |
| `daa.lock` | Lock screen, clone of omarchy.lock: adds the Mullet Claude outline avatar (avatar.png) above the password field |

## Other files

| File | Mode | What |
|---|---|---|
| `~/.local/bin/cursor-to-tray` | desktop | Glides the cursor to a bar icon (omarchy.bar `iconPos` IPC) and opens its panel; the info bar's Wi-Fi / Bluetooth / battery rows use it |
| `~/.local/bin/phone-status` | desktop | KDE Connect status JSON / actions (ring, clipboard, browse, settings) for the Go menu phone card; Nautilus right-click Scripts → Send to phone |
| `~/.local/bin/tablet-mode` | tablet | The switcher: devices, bar swap, gestures, keyboard, rotation, per-mode wallpaper, `dismiss` |
| `~/.config/tablet-mode/gestures` | tablet | Edge-swipe gestures (lisgd) |
| `~/.config/tablet-mode/apps` | tablet | Apps shown in the tablet app grid |
| `~/.config/hypr/tablet_mode.lua` | tablet | Fold switch → `tablet-mode on/off` |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | both | Menu entries; `tablet.*` entries are tablet only |
| `~/.config/omarchy/shell.json` | both | Bar layout + enabled plugins (tablet mode switches `bar.id`) |
| `~/.config/omarchy/shell.toml` | both | Theme overrides (borderless popups). Tablet mode appends `[tablet]` / bigger font while on and restores the file on exit |
| `~/.config/hypr/*.lua` (rest) | both | Hyprland config (scratchpads, dropdowns, looknfeel…) |

Runtime state (don't edit): `~/.local/state/tablet-mode/`
(`state`, `rotation`, `sensor`, per-mode `background-laptop` / `background-tablet`).

## Backups

All old `.bak` files: `~/.local/state/config-backups/`
(`config/` mirrors `~/.config`, `tablet-mode-state/` holds old tablet-mode
backups, `pre-reorg-*.tar.gz` is a full snapshot taken before the
`daa.desktop-*` rename, `unused-clone-files/` holds the bars' never-loaded
`widgets/` + `indicators/` copies and the retired `daa.tablet` button).
