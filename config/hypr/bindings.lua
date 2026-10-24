-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Freed for dropdowns (see dropdowns.lua). SUPER+C was: Universal copy
hl.unbind("SUPER + C")

-- SUPER+T was: Toggle window floating/tiling
hl.unbind("SUPER + T")
o.bind("SUPER + SHIFT + T", "Alacritty", { launch = "alacritty" })

-- SUPER+O pop-out skips scratchpads and dropdowns (special workspaces): it
-- floated them, then they came back as a tile.
hl.unbind("SUPER + O")
o.bind("SUPER + O", "Pop window out (float & pin)",
  [[sh -c 'hyprctl activewindow -j | jq -e ".workspace.name | startswith(\"special:\")" >/dev/null || omarchy-hyprland-window-pop']])

-- SUPER+Z dismisses the newest notification (same as SUPER + comma).
o.bind("SUPER + Z", "Dismiss last notification", "omarchy-shell notifications dismissOne")

-- Google web apps removed; drop their default shortcuts too.
hl.unbind("SUPER + SHIFT + Y")        -- was: YouTube
hl.unbind("SUPER + SHIFT + CTRL + G") -- was: Google Messages
hl.unbind("SUPER + SHIFT + P")        -- was: Google Photos
hl.unbind("SUPER + SHIFT + S")        -- was: Google Maps

-- Browsers and close.
hl.unbind("SUPER + W")         -- was: Close window
hl.unbind("SUPER + SHIFT + W") -- was: Omawrite
o.bind("SUPER + W", "Firefox", { launch = "firefox" })
o.bind("SUPER + SHIFT + W", "Brave Origin", { launch = "brave-origin" })
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())

-- SUPER+E is the dropdown file manager (see dropdowns.lua).
-- SUPER+SHIFT+F still opens a regular one.
hl.unbind("SUPER + E")

hl.unbind("SUPER + SHIFT + E") -- was: Email (HEY)
o.bind("SUPER + SHIFT + E", "Dolphin", { launch = "dolphin" })

-- HEY removed; drop its remaining default shortcuts too.
hl.unbind("SUPER + SHIFT + ALT + E") -- was: New email (HEY)
hl.unbind("SUPER + SHIFT + C")       -- was: Calendar (HEY)

-- SUPER+P is the dropdown Bitwarden (see dropdowns.lua).
hl.unbind("SUPER + P") -- was: Pseudo window

-- Bar and launcher.
o.bind_toggle("SUPER + B", "Toggle top bar", "bar")
o.bind("SUPER + R", "App grid", "omarchy-shell shell toggle daa.launcher")

-- PRINT was: Smart screenshot. Always drag-select a region instead.
hl.unbind("PRINT")
o.bind("PRINT", "Screenshot region", "omarchy-capture-screenshot region")
-- Yoga PrtSc key sends XF86SelectiveScreenshot, not PRINT.
o.bind("XF86SelectiveScreenshot", "Screenshot region", "omarchy-capture-screenshot region")
o.bind("SUPER + SHIFT + S", "Screenshot region", "omarchy-capture-screenshot region")

-- X and WhatsApp web apps were removed; drop their default shortcuts too.
hl.unbind("SUPER + SHIFT + ALT + G")
hl.unbind("SUPER + SHIFT + X")
hl.unbind("SUPER + SHIFT + ALT + X")

-- SUPER + V opens the clipboard manager (was: Universal paste).
hl.unbind("SUPER + V")
o.bind("SUPER + V", "Clipboard manager", "omarchy-shell shell toggle daa.clipboard")
-- The default SUPER+CTRL+V still names the packaged plugin, which the clone disabled.
hl.unbind("SUPER + CTRL + V")
o.bind("SUPER + CTRL + V", "Clipboard manager", "omarchy-shell shell toggle daa.clipboard")

-- Menu keys: pressing a menu's key again closes it, but pressing another
-- menu's key while one is open switches to that menu (see menu-toggle).
local menu_keys = {
  { "SUPER + SPACE", "Omarchy menu", "root" },
  { "SUPER + SHIFT + code:201", "Omarchy menu", "root" },
  { "SUPER + ALT + SPACE", "Apps menu", "apps" },
  { "SUPER + CTRL + C", "Capture menu", "capture" },
  { "SUPER + CTRL + O", "Toggle menu", "toggle" },
  { "SUPER + CTRL + H", "Hardware menu", "hardware" },
  { "SUPER + ESCAPE", "System menu", "system" },
  { "SUPER + CTRL + SPACE", "Background switcher", "background" },
  { "SUPER + SHIFT + CTRL + SPACE", "Theme menu", "theme" },
  { "SUPER + CTRL + S", "Share", "share" },
  { "SUPER + CTRL + R", "Set reminder", "reminder-set" },
  -- SUPER+K: the Go menu's Keybinds panel; SUPER+SHIFT+K: the big list.
  { "SUPER + K", "Keybindings", "go:keys" },
  { "SUPER + SHIFT + K", "Keybindings (full list)", "'dmenu:Keybindings' omarchy-menu-keybindings" },
  { "SUPER + ALT + K", "Tmux keybindings", "'dmenu:Tmux keybindings' omarchy-menu-tmux-keybindings" },
  { "SUPER + CTRL + K", "Herdr keybindings", "'dmenu:Herdr keybindings' omarchy-menu-herdr-keybindings" },
}
for _, menu in ipairs(menu_keys) do
  hl.unbind(menu[1])
  o.bind(menu[1], menu[2], "~/.local/bin/menu-toggle " .. menu[3])
end
hl.unbind("XF86PowerOff")
o.bind("XF86PowerOff", "Power menu", "~/.local/bin/menu-toggle system", { locked = true })

-- Easter egg: SUPER + CTRL + ALT + SPACE opens the Go menu so hard it swings
-- into the left edge, the hinge snaps and everything falls off the screen
-- (daa.menu Menu.qml, eggAnim). Plain SUPER + SPACE is Omarchy's default.
o.bind("SUPER + CTRL + ALT + SPACE", "Super duper menu",
  [[omarchy-shell shell toggle omarchy.menu '{"menu":"root","egg":true}']])

-- Tap SUPER on its own: info bar (daa.infobar). Fires on release; a second
-- tap hides it, otherwise it fades after 4 s.
o.bind("SUPER + Super_L", "Info bar", "omarchy-shell -q daa.infobar toggle", { release = true })

-- Brightness keys on ~/.local/bin/brightness-step's scale: 100% = raw 4054
-- (the panel's full 4095 is a much brighter jump, kept for SHIFT + up only),
-- 2% steps between 90 and 100, 5% below.
for _, key in ipairs({ "XF86MonBrightnessUp", "XF86MonBrightnessDown",
  "SHIFT + XF86MonBrightnessUp", "SHIFT + XF86MonBrightnessDown",
  "ALT + XF86MonBrightnessUp", "ALT + XF86MonBrightnessDown" }) do
  hl.unbind(key)
end
o.bind("XF86MonBrightnessUp", "Brightness up", "brightness-step up", { locked = true, repeating = true })
o.bind("XF86MonBrightnessDown", "Brightness down", "brightness-step down", { locked = true, repeating = true })
o.bind("SHIFT + XF86MonBrightnessUp", "Brightness boost (panel maximum)", "brightness-step boost", { locked = true })
o.bind("SHIFT + XF86MonBrightnessDown", "Brightness minimum", "brightness-step min", { locked = true })
o.bind("ALT + XF86MonBrightnessUp", "Brightness up precise", "brightness-step +1", { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessDown", "Brightness down precise", "brightness-step -1", { locked = true, repeating = true })
