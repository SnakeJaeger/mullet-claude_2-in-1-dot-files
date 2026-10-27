-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Keybinding registry (Desktop settings → Keys): must come before any binds.
dofile((os.getenv("HOME") or "") .. "/.config/hypr/keys_registry.lua")

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
require("hypr.workspace_collapse")
require("hypr.dropdowns")
require("hypr.scratchpads")
require("hypr.screensaver_brightness")
require("hypr.tablet_mode")
require("hypr.lid")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- wdisplays (left click on the bar's monitor icon): float it centred.
o.window("^network\\.cycles\\.wdisplays$", { tag = "+floating-window" })

-- Desktop settings in window mode (daa.settings): opens floating and centred,
-- its own size; its tile button tiles it.
o.window({ class = "^org\\.quickshell$", title = "^Desktop settings$" }, { float = true, center = true, size = { 960, 720 } })

-- Window rules made in Desktop settings → Rules (windowrules_user.json).
do
  local ok, rules = pcall(dofile, (os.getenv("HOME") or "") .. "/.config/hypr/windowrules_user.lua")
  if ok and type(rules) == "table" then
    for _, rule in ipairs(rules) do hl.window_rule(rule) end
  end
end

-- Keybinding changes made in Desktop settings → Keys (last, so they win).
daa_apply_key_overrides()
