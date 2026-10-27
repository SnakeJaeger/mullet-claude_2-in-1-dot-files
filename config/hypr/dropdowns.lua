-- Dropdown apps: one key summons an app from the top of the screen and the
-- same key hides it again. Each app lives on its own special workspace; the
-- first press launches it if it isn't running yet.

-- Optional w/h are fractions of the monitor (default 0.7 x 0.6) and y is the
-- top edge in px (default 50, just below the bar). The terminal tucks under the
-- bar and is taller so the fastfetch greeting fits without scrolling.
-- px = { w, h } sets an exact pixel size instead (centred horizontally unless
-- x gives the left edge in px).
-- right = px pins the window that far from the right edge instead of centring.
-- slide = the special workspace animation style for just this dropdown, e.g.
-- "slide" to come in from the right instead of down from the top.
-- rise = fraction of the screen height, measured up from the bottom, where the
-- window's centre rests; the window rises from below the screen to get there.
-- preload = true launches the app hidden at login so the first press is instant.
-- key may be left out for a dropdown that's only summoned by name.
local dropdowns = {
  -- Geometry copied from where it was hand-placed (119x35 cells at font 10)
  { key = "SUPER + T", name = "terminal", title = "Dropdown terminal", cmd = [[alacritty --class dropdown.terminal -o font.size=10 -o 'env.DROPDOWN_TERMINAL="1"']], px = { 990, 667 }, y = -22, preload = true },
  -- In Ptyxis rather than Alacritty: GTK4 gives it kinetic touchpad scrolling.
  -- Ptyxis can't set its own class either (see `match` below); -s keeps it a
  -- separate instance from any regular Ptyxis window.
  { key = "SUPER + C", name = "claude", title = "Dropdown Claude Code", cmd = "ptyxis -s -- claude", match = "org.gnome.Ptyxis",
    -- Hand-placed with the header bar pushed up off the top of the screen.
    px = { 1107, 685 }, x = 181, y = -45, preload = true },
  { key = "SUPER + I", name = "btop", title = "Dropdown btop", cmd = "alacritty --class dropdown.btop -e btop", preload = true },
  -- Nautilus can't set its own class, so `match` claims the next window of
  -- that class instead (see below).
  { key = "SUPER + E", name = "files", title = "Dropdown files", cmd = "nautilus --new-window", match = "org.gnome.Nautilus", preload = true },
  -- Whole-filesystem search (Catfish searches from / instead of home), with
  -- its own GTK theme (omarchy/themed/catfish-gtk3.css.tpl).
  { key = "SUPER + D", name = "search", title = "Dropdown file search", cmd = "env GTK_THEME=Omarchy-Catfish catfish --path=/", match = "catfish", px = { 1000, 700 }, preload = true },
  -- Hangs off the upper right corner and slides in from the right.
  { key = "SUPER + P", name = "bitwarden", title = "Dropdown Bitwarden", cmd = "bitwarden-desktop", match = "Bitwarden", px = { 819, 713 }, right = 10, slide = "slide", preload = true },
  -- Hangs under the bar's weather button; clicking the button toggles it.
  { key = "SUPER + ALT + W", name = "weather", title = "Dropdown weather", cmd = "gnome-weather", match = "org.gnome.Weather", px = { 840, 620 }, preload = true },
  -- Rises from the bottom and rests a third of the way up. Mullvad's window is
  -- a fixed 320x568.
  -- Mullvad in a terminal (status + menu, ~/.local/bin/mullvad-tui); the full app is SUPER+SHIFT+M.
  { key = "SUPER + M", name = "vpn", title = "Dropdown Mullvad (terminal)", cmd = "alacritty --class dropdown.vpn -e mullvad-tui", px = { 760, 440 }, preload = true },
  { key = "SUPER + SHIFT + M", name = "mullvad", title = "Dropdown Mullvad VPN app", cmd = "mullvad-vpn", match = "mullvad-vpn", px = { 320, 568 }, rise = 1 / 3,
    -- Closing its window only sends it to the tray, so quit the app itself.
    quit_on_hide = [[pkill -TERM -f 'electron --ozone-platform=x11 /usr/lib/mullvad-vpn/app\.asar$']] },
  -- System update, from the bar's update count (daa.updates): hangs in the
  -- upper right corner and slides in from the right. Not preloaded (it would
  -- start updating at login); recounts the bar as soon as the update ends.
  { name = "update", title = "Dropdown system update",
    cmd = [[alacritty --class dropdown.update --title Omarchy -e bash -c 'omarchy-show-logo; omarchy-update; s=$?; omarchy-shell -q daa.updates refresh; (( s != 130 )) && omarchy-show-done']],
    px = { 760, 520 }, right = 10, slide = "slide" },
}

-- Scratchpads made with the builder (Desktop settings → Scratchpads,
-- daa.settings) live in their own file, generated from
-- ~/.config/hypr/dropdowns_user.json, so they can't break the list above.
-- Each is a `match` dropdown (claims the first window of its class).
do
  local path = (os.getenv("HOME") or "") .. "/.config/hypr/dropdowns_user.lua"
  local ok, extra = pcall(dofile, path)
  if ok and type(extra) == "table" then
    local taken = {}
    for _, d in ipairs(dropdowns) do taken[d.name] = true end
    for _, d in ipairs(extra) do
      if type(d) == "table" and d.name and d.cmd and not taken[d.name] then
        d.user = true
        table.insert(dropdowns, d)
        taken[d.name] = true
      end
    end
  end
end

-- Desktop settings → Startup can switch preloading off per dropdown: one
-- name per line in ~/.config/hypr/preload_off.
do
  local f = io.open((os.getenv("HOME") or "") .. "/.config/hypr/preload_off", "r")
  if f then
    local off = {}
    for line in f:lines() do off[line:match("^%s*(.-)%s*$")] = true end
    f:close()
    for _, d in ipairs(dropdowns) do
      if off[d.name] then d.preload = false end
    end
  end
end

-- Bitwarden reloads its window and asks for focus every time the vault locks;
-- with Omarchy's focus_on_activate that pulled the hidden dropdown into view.
o.window("^Bitwarden$", { focus_on_activate = false })

-- The update dropdown has no window border (user asked).
o.window("^dropdown\\.update$", { border_size = 0 })

local function dims(dropdown)
  local w, h = dropdown.w or 0.7, dropdown.h or 0.6
  return w, h, (1 - w) / 2, dropdown.y or 50
end

-- Slide special workspaces down from the top instead of fading them in
-- ("top": plain slidevert comes up from the bottom since Hyprland 0.56).
-- Workspace rules can't override this for one special workspace, so each
-- toggle sets the style first; the hide that follows (here or from
-- scratchpads.lua) reuses it and slides back out the same way.
local function slide_style(dropdown)
  hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "easeOutQuint", style = dropdown and dropdown.slide or "slidevert top" })
end
slide_style()

-- Size and top-left position in layout px on a w x h (logical) monitor.
local function place(dropdown, w, h)
  local fw, fh, fx, fy = dims(dropdown)
  local ww, wh = math.floor(w * fw), math.floor(h * fh)
  if dropdown.px then
    ww, wh = math.min(dropdown.px[1], math.floor(w * 0.96)), dropdown.px[2]
  end
  local x = (w - ww) // 2
  -- A fixed x only while it fits (not in portrait after a rotation).
  if dropdown.x and dropdown.x + ww <= w then x = dropdown.x end
  if dropdown.right then x = w - ww - dropdown.right end
  if dropdown.rise then fy = math.floor(h * (1 - dropdown.rise) - wh / 2) end
  return ww, wh, x, fy
end

-- Where a rise dropdown waits while hidden: just under the bottom edge.
local function parked_y(h)
  return h + 20
end

local function running(class)
  for _, window in ipairs(hl.get_windows()) do
    if window.class == class then return true end
  end
  return false
end

-- Claimed dropdown windows by address, so scratchpads.lua can leave them be.
dropdown_windows = {}

-- SUPER+SHIFT+M was Omarchy's Music; it opens the Mullvad app now.
hl.unbind("SUPER + SHIFT + M")

local claimed = {} -- dropdown name -> window address
local pending = {} -- class -> dropdown waiting for its window
local silent = {} -- class -> true when its pending window is a preload
local lowering = {} -- rise dropdown name -> true while it slides down

local function alive(address)
  for _, window in ipairs(hl.get_windows()) do
    if window.address == address then return true end
  end
  return false
end

-- Special workspaces can only slide in from the top or the side, so a rise
-- dropdown shows and hides without the workspace animation and moves its
-- window instead: parked under the bottom edge while hidden, slid up on show,
-- and slid back down before the workspace hides.
local function rise_move(dropdown, up)
  local address = claimed[dropdown.name]
  if not (address and alive(address)) then return end
  local monitor = hl.get_active_monitor()
  local w, h = monitor.width / monitor.scale, monitor.height / monitor.scale
  local _, _, x, y = place(dropdown, w, h)
  if not up then y = parked_y(h) end
  hl.dispatch(hl.dsp.window.move({ window = "address:" .. address, x = monitor.x + x, y = monitor.y + y }))
end

local function rise_toggle(dropdown)
  if lowering[dropdown.name] then return end
  local workspace = "dropdown-" .. dropdown.name
  local monitor = hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  hl.animation({ leaf = "specialWorkspace", enabled = false })
  if shown and shown.name == "special:" .. workspace then
    lowering[dropdown.name] = true
    rise_move(dropdown, false)
    -- Hide once the window has (nearly) finished sliding down.
    hl.timer(function()
      lowering[dropdown.name] = nil
      hl.animation({ leaf = "specialWorkspace", enabled = false })
      hl.dispatch(hl.dsp.workspace.toggle_special(workspace))
      slide_style()
    end, { timeout = 300, type = "oneshot" })
  else
    rise_move(dropdown, false)
    hl.dispatch(hl.dsp.workspace.toggle_special(workspace))
    rise_move(dropdown, true)
  end
end

local function toggle_special(dropdown)
  -- Summoning beats an open bar panel (scratchpads.lua closes it).
  local monitor = hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  if scratchpad_summoned and not (shown and shown.name == "special:dropdown-" .. dropdown.name) then
    scratchpad_summoned("special:dropdown-" .. dropdown.name)
  end
  if dropdown.rise then return rise_toggle(dropdown) end
  slide_style(dropdown)
  hl.dispatch(hl.dsp.workspace.toggle_special("dropdown-" .. dropdown.name))
end

-- scratchpads.lua hides a showing special workspace (click away, SUPER+X)
-- through this first, so a rise dropdown slides down instead of vanishing.
-- Returns true when it handled the hide.
function dropdown_hide(special_name)
  for _, dropdown in ipairs(dropdowns) do
    if dropdown.rise and special_name == "special:dropdown-" .. dropdown.name then
      rise_toggle(dropdown)
      return true
    end
  end
  return false
end

-- Give a claimed window what the o.window rule above gives the others, then
-- park it on its special workspace and show it.
hl.on("window.open", function(window)
  local dropdown = window and pending[window.class]
  if not dropdown then return end
  pending[window.class] = nil
  claimed[dropdown.name] = window.address
  dropdown_windows[window.address] = true

  -- Monitor width/height are in pixels; layout coords are scaled.
  local monitor = window.monitor or hl.get_active_monitor()
  local w, h = monitor.width / monitor.scale, monitor.height / monitor.scale
  local ww, wh, x, y = place(dropdown, w, h)
  if dropdown.rise then y = parked_y(h) end
  hl.dispatch(hl.dsp.window.float({ window = window, action = "enable" }))
  hl.dispatch(hl.dsp.window.resize({ window = window, x = ww, y = wh }))
  hl.dispatch(hl.dsp.window.move({ window = window, x = monitor.x + x, y = monitor.y + y }))
  hl.dispatch(hl.dsp.window.move({ window = window, workspace = "special:dropdown-" .. dropdown.name, follow = false }))
  -- Changing workspace pulls a window that hangs off the screen (y < 0) back
  -- on, so place it again, and once more after it has settled.
  local function reposition()
    if alive(window.address) then
      hl.dispatch(hl.dsp.window.move({ window = "address:" .. window.address, x = monitor.x + x, y = monitor.y + y }))
    end
  end
  reposition()
  hl.timer(reposition, { timeout = 300, type = "oneshot" })
  if silent[window.class] then
    silent[window.class] = nil
    return
  end
  toggle_special(dropdown)
end)

-- Floating windows keep their size when the screen rotates, so tablet-mode
-- calls this after each rotation (transform 0-3) to fit dropdowns to the new
-- shape. Pixel-sized ones shrink to fit a portrait screen.
function dropdown_refit(transform)
  local monitor = hl.get_active_monitor()
  local long = math.max(monitor.width, monitor.height) / monitor.scale
  local short = math.min(monitor.width, monitor.height) / monitor.scale
  local w, h = long, short
  if transform % 2 == 1 then w, h = short, long end
  for _, dropdown in ipairs(dropdowns) do
    local class = dropdown.match or ("dropdown." .. dropdown.name)
    for _, window in ipairs(hl.get_windows()) do
      if window.class == class and (not dropdown.match or window.address == claimed[dropdown.name]
          or (window.workspace and window.workspace.name == "special:dropdown-" .. dropdown.name)) then
        local ww, wh, x, y = place(dropdown, w, h)
        local shown = monitor.active_special_workspace
        if dropdown.rise and not (shown and shown.name == "special:dropdown-" .. dropdown.name) then
          y = parked_y(h)
        end
        hl.dispatch(hl.dsp.window.resize({ window = window, x = ww, y = wh }))
        hl.dispatch(hl.dsp.window.move({ window = window, x = monitor.x + x, y = monitor.y + y }))
      end
    end
  end
end

-- Toggle functions by dropdown name. Exposed as dropdown_toggle(name) and
-- dropdown_show(name) so menus and the tablet app grid can summon a dropdown
-- (hyprctl eval 'dropdown_show("files")'); show never hides one already up.
local toggles = {}

function dropdown_toggle(name)
  if toggles[name] then toggles[name]() end
end

function dropdown_show(name)
  local monitor = hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  if shown and shown.name == "special:dropdown-" .. name then return end
  dropdown_toggle(name)
end

-- Restart a match-based dropdown with extra (already shell-quoted) arguments
-- and show it. ~/.local/bin/file-search uses this so the Omarchy menu can open
-- Catfish already searching:
--   hyprctl eval 'dropdown_relaunch("search", [==[--start 'notes']==])'
function dropdown_relaunch(name, args)
  for _, dropdown in ipairs(dropdowns) do
    if dropdown.name == name and dropdown.match then
      local workspace = "special:dropdown-" .. name
      local monitor = hl.get_active_monitor()
      local shown = monitor and monitor.active_special_workspace
      if shown and shown.name == workspace then toggle_special(dropdown) end
      for _, window in ipairs(hl.get_windows()) do
        if window.class == dropdown.match and (window.address == claimed[name]
            or (window.workspace and window.workspace.name == workspace)) then
          dropdown_windows[window.address] = nil
          hl.dispatch(hl.dsp.window.close({ window = window }))
        end
      end
      claimed[name] = nil
      pending[dropdown.match] = dropdown
      silent[dropdown.match] = nil
      hl.dispatch(hl.dsp.exec_cmd("uwsm-app -- " .. dropdown.cmd .. " " .. (args or "")))
      return
    end
  end
end

for _, dropdown in ipairs(dropdowns) do
  if dropdown.match then
    toggles[dropdown.name] = function()
      local address = claimed[dropdown.name]
      -- The claim lives only in this Lua state, which a config reload wipes.
      -- Re-adopt a window still parked on the dropdown's workspace rather
      -- than launching a second one.
      if not (address and alive(address)) then
        for _, window in ipairs(hl.get_windows()) do
          if window.class == dropdown.match and window.workspace
            and window.workspace.name == "special:dropdown-" .. dropdown.name then
            address = window.address
            claimed[dropdown.name] = address
            dropdown_windows[address] = true
            break
          end
        end
      end
      if address and alive(address) then
        toggle_special(dropdown)
      else
        if address then dropdown_windows[address] = nil end
        claimed[dropdown.name] = nil
        pending[dropdown.match] = dropdown
        silent[dropdown.match] = nil
        hl.dispatch(hl.dsp.exec_cmd("uwsm-app -- " .. dropdown.cmd))
      end
    end
    if dropdown.key then o.bind(dropdown.key, dropdown.title, toggles[dropdown.name]) end
    -- Claim the first window of the class at login, but leave it hidden.
    if dropdown.preload then
      hl.on("hyprland.start", function()
        pending[dropdown.match] = dropdown
        silent[dropdown.match] = true
        hl.exec_cmd("uwsm-app -- " .. dropdown.cmd)
      end)
    end
    goto continue
  end

  local class = "dropdown." .. dropdown.name
  local workspace = "special:dropdown-" .. dropdown.name

  -- Floating, centred horizontally, hanging just below the bar.
  local fw, fh, fx, fy = dims(dropdown)
  -- Silent so preloaded windows open hidden; the bind toggles it into view.
  local size = { "(monitor_w*" .. fw .. ")", "(monitor_h*" .. fh .. ")" }
  local move = { "(monitor_w*" .. fx .. ")", tostring(fy) }
  if dropdown.px then
    size = { tostring(dropdown.px[1]), tostring(dropdown.px[2]) }
    local x = dropdown.x and tostring(dropdown.x) or "(monitor_w*0.5-" .. dropdown.px[1] // 2 .. ")"
    if dropdown.right then x = "(monitor_w-" .. dropdown.px[1] + dropdown.right .. ")" end
    move = { x, tostring(fy) }
  end
  o.window("^" .. class:gsub("%.", "\\.") .. "$", {
    workspace = workspace .. " silent",
    float = true,
    size = size,
    move = move,
  })

  toggles[dropdown.name] = function()
    if not running(class) then
      hl.dispatch(hl.dsp.exec_cmd("uwsm-app -- " .. dropdown.cmd))
    end
    toggle_special(dropdown)
  end
  if dropdown.key then o.bind(dropdown.key, dropdown.title, toggles[dropdown.name]) end

  if dropdown.preload then o.launch_on_start(dropdown.cmd) end

  ::continue::
end

-- quit_on_hide: the app only runs while it's on screen. Hiding it (its key,
-- a click outside, SUPER+X) closes the window -- or runs quit_on_hide when it's
-- a command -- so it isn't running at logout.
-- The Mullvad GUI crash-reported whenever logout killed it. Connecting and
-- disconnecting go through the mullvad CLI (bar toggle, Go menu), not the app.
local shown_special = nil
hl.on("workspace.special_active", function(ws)
  local name = ws and ws.name or nil
  local was = shown_special
  shown_special = name
  if not was or was == name then return end
  for _, dropdown in ipairs(dropdowns) do
    if dropdown.quit_on_hide and was == "special:dropdown-" .. dropdown.name then
      for _, window in ipairs(hl.get_windows()) do
        if window.class == dropdown.match and window.workspace and window.workspace.name == was then
          dropdown_windows[window.address] = nil
          if type(dropdown.quit_on_hide) ~= "string" then
            hl.dispatch(hl.dsp.window.close({ window = window }))
          end
        end
      end
      if type(dropdown.quit_on_hide) == "string" then hl.exec_cmd(dropdown.quit_on_hide) end
      claimed[dropdown.name] = nil
    end
  end
end)


-- Whenever a scratchpad (any special workspace) comes up, put the cursor in
-- the middle of its window, clamped to the screen for ones that hang off the
-- top. A beat later, so rise dropdowns have their target position set.
-- Settings (daa.settings): "cursorCenterDropdowns": false turns this off.
local function center_enabled()
  local f = io.open((os.getenv("HOME") or "") .. "/.config/omarchy/daa-ui.json", "r")
  if not f then return true end
  local text = f:read("a") or ""
  f:close()
  return not text:find('"cursorCenterDropdowns"%s*:%s*false')
end

hl.on("workspace.special_active", function(ws)
  local name = ws and ws.name or nil
  if not name or not center_enabled() then return end
  hl.timer(function()
    local monitor = hl.get_active_monitor()
    local shown = monitor and monitor.active_special_workspace
    if not (shown and shown.name == name) then return end
    local target
    for _, window in ipairs(hl.get_windows()) do
      if window.mapped and not window.hidden and window.workspace and window.workspace.name == name then
        if not target or window.focus_history_id < target.focus_history_id then target = window end
      end
    end
    if not target then return end
    local mx, my = monitor.x, monitor.y
    local mw, mh = monitor.width / monitor.scale, monitor.height / monitor.scale
    local x = math.max(mx, math.min(mx + mw - 1, target.at.x + target.size.x / 2))
    local y = math.max(my, math.min(my + mh - 1, target.at.y + target.size.y / 2))
    hl.dispatch(hl.dsp.cursor.move({ x = math.floor(x), y = math.floor(y) }))
  end, { timeout = 60, type = "oneshot" })
end)
