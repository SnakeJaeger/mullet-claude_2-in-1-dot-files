-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Bar islands: blur behind the translucent pills drawn by the daa.desktop-bar plugin.
-- ignore_alpha keeps the fully clear gaps between pills unblurred; blur_popups
-- covers the right island's stats flyout.
hl.layer_rule({ match = { namespace = "omarchy-bar" }, blur = true, blur_popups = true, ignore_alpha = 0.1 })

-- Volume/brightness OSD (daa.osd draws it at 85%): frost what's behind it.
hl.layer_rule({ match = { namespace = "omarchy-osd" }, blur = true, ignore_alpha = 0.1 })
hl.layer_rule({ match = { namespace = "daa-infobar" }, blur = true, ignore_alpha = 0.1 })
hl.layer_rule({ match = { namespace = "omarchy-notifications" }, blur = true, ignore_alpha = 0.1 })

-- App grid and Omarchy menu cards (85%, [menu] in ~/.config/omarchy/themed/
-- shell.toml.tpl). ignore_alpha 0.6 skips their 50% full-screen dim scrim, so
-- only the card itself is frosted.
hl.layer_rule({ match = { namespace = "omarchy-launcher" }, blur = true, ignore_alpha = 0.6 })
hl.layer_rule({ match = { namespace = "omarchy-menu" }, blur = true, ignore_alpha = 0.6 })

-- Bar panels (volume, Wi-Fi, clock, ...) draw their 85% card on a full-screen
-- transparent layer; ignore_alpha keeps the empty rest of it unblurred.
hl.layer_rule({ match = { namespace = "omarchy-keyboard-panel" }, blur = true, ignore_alpha = 0.1 })

-- Cursor: Bibata Modern Ice (installed to ~/.local/share/icons).
hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")

-- Qt/KDE apps take their style, palette and icons from qt6ct (Omarchy's
-- default is gtk3, which gives KDE apps little more than light/dark). The
-- theme-set hook kde-qt-theme fills qt6ct and kdeglobals from the theme.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Slightly rounded window corners. Blur is on so the layer rules above can
-- frost the bar, popups and menus; app windows opt out just below.
hl.config({
  decoration = {
    rounding = 6,
    blur = {
      enabled = true,
      -- Needed for the bar's flyouts and panels, which are popups of the bar.
      popups = true,
    },
  },
})

-- Keep app windows unblurred: they're only slightly translucent (0.93 / 0.90).
o.window(".*", { no_blur = true })

-- A touch more see-through than Omarchy's 0.985 / 0.96 (focused / unfocused).
-- Browsers opt out of this tag, so they stay opaque.
o.window({ tag = "default-opacity" }, { opacity = "0.93 0.90" })
-- Remote desktops stay opaque, or the local wallpaper bleeds through.
o.window("^org.remmina.Remmina$", { opacity = "1 1" })

-- Window border: 1px (default 2). Its colour comes from the theme accent
-- (cyan, set in ~/.config/omarchy/themes/tokyo-night/colors.toml).
hl.config({
  general = {
    border_size = 1,
  },
})

-- Outer gap: top is 6 instead of 10 because the bar's pills stop ~4px above
-- the bar's reserved edge, so the visible gap (pill bottom -> window) matches
-- the 10px gap at the bottom of the screen.
hl.config({
  general = {
    gaps_out = { top = 6, right = 10, bottom = 10, left = 10 },
  },
})

-- Window border: 45deg cyan -> coral gradient (theme accent + theme red).
-- Firefox's selected tab runs the same diagonal the opposite way
-- (~/.config/omarchy/themed/firefox-userChrome.css.tpl).
hl.config({
  general = {
    col = {
      active_border = { colors = { "rgb(7dcfff)", "rgb(f7768e)" }, angle = 45 },
    },
  },
})

-- GNOME Weather (SUPER+ALT+W / bar weather click): borderless.
o.window("^org.gnome.Weather$", { border_size = 0 })
