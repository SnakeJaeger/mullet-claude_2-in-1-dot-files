-- Retract scratchpads (any special workspace: the Omarchy scratchpad and the
-- dropdowns) when focus moves to a regular window, e.g. by clicking off one,
-- or with SUPER + X.

-- Hiding is a toggle, and a quick double click can arrive before Hyprland has
-- registered the first hide, so the second would toggle the scratchpad back
-- open. Ignore further hides for a moment after one.
local hiding = false

-- Debug log (2026-10-24): scratchpads occasionally pop up on their own and it
-- won't reproduce on demand. Every show/hide, bar panel open/close and guard
-- decision goes to ~/.local/state/scratchpad-debug.log (capped at ~256 KB).
-- Remove this block and the dbg() calls once the cause is found.
local DBG_PATH = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/scratchpad-debug.log"
local function dbg(...)
  local f = io.open(DBG_PATH, "a")
  if not f then return end
  if f:seek("end") > 262144 then
    f:close()
    os.rename(DBG_PATH, DBG_PATH .. ".old")
    f = io.open(DBG_PATH, "a")
    if not f then return end
  end
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  f:write(os.date("%m-%d %H:%M:%S"), " ", table.concat(parts, " "), "\n")
  f:close()
end

-- After hiding, hand focus to the most recently used window on the regular
-- workspace underneath. Otherwise focus stays on the hidden scratchpad window
-- and Hyprland restores it (re-showing the scratchpad) as soon as a bar panel
-- or menu that took the keyboard closes.
local function focus_regular(monitor)
  local regular = monitor and monitor.active_workspace
  if not regular then return end
  local best
  for _, window in ipairs(hl.get_windows()) do
    if window.workspace and window.workspace.id == regular.id and window.mapped and not window.hidden
      and (not best or window.focus_history_id < best.focus_history_id) then
      best = window
    end
  end
  if best then hl.dispatch(hl.dsp.focus({ window = "address:" .. best.address })) end
end

-- With no regular window to take focus (e.g. an empty workspace), Hyprland's
-- last-focused window stays the hidden scratchpad, and it hands focus back
-- (re-showing the scratchpad) when a bar panel is clicked away. A scratchpad
-- can't sensibly be summoned while a bar panel is up, so any that appears
-- while one is open, or within a moment of it closing, is hidden again --
-- except one that was already showing when the panel opened: bar panels open
-- on hover, so that one stays on screen, dimmed, until the panel closes.
local PANEL_NS = "omarchy-keyboard-panel"
local DIM_TAG = "scratchpad-dimmed"
local panel_open = false
local panel_grace = false
local kept_special = nil
local panel_gen = 0
local summoned = nil

-- dropdowns.lua calls this when one is deliberately shown (click or key).
-- That beats the panel: let it through the guard below and close the panel
-- (the bar's yieldPopout also stops the hovered icon from reopening it).
function scratchpad_summoned(name)
  dbg("summon", name, "panel_open=" .. tostring(panel_open), "grace=" .. tostring(panel_grace))
  if not (panel_open or panel_grace) then return end
  summoned = name
  hl.exec_cmd("omarchy-shell -q omarchy.bar yieldPopout")
end

o.window({ tag = DIM_TAG }, { opacity = "0.45 0.45" })

local function dim_special(name, on)
  for _, window in ipairs(hl.get_windows()) do
    if window.workspace and window.workspace.name == name then
      hl.dispatch(hl.dsp.window.tag({ tag = (on and "+" or "-") .. DIM_TAG, window = "address:" .. window.address }))
    end
  end
end

local function toggle_special_named(name)
  hl.dispatch(hl.dsp.workspace.toggle_special((name:gsub("^special:", ""))))
end

local function hide_special(monitor)
  local special = monitor and monitor.active_special_workspace
  if not special or hiding then return end
  dbg("hide_special", special.name)
  hiding = true
  hl.timer(function() hiding = false end, { timeout = 400, type = "oneshot" })
  -- Dropdowns that rise from the bottom slide back down before hiding.
  if not (dropdown_hide and dropdown_hide(special.name)) then
    toggle_special_named(special.name)
  end
  focus_regular(monitor)
end

-- Keyboard-grabbing overlays (Go menu, launcher, clipboard, pickers): when
-- one closes, Hyprland gives focus back to the last focused window. If that's
-- a window in a HIDDEN dropdown, its dropdown pops open. Park focus on a
-- regular window as the overlay opens, so there's nothing hidden to go back to.
local FOCUS_OVERLAYS = {
  ["omarchy-menu"] = true, ["omarchy-launcher"] = true, ["omarchy-clipboard"] = true,
  ["omarchy-image-selector"] = true, ["omarchy-emojis"] = true,
}
-- On an empty workspace there's nothing to park on, so as a backstop: for
-- half a second after one of these overlays closes, a dropdown that appears
-- unasked (not the one showing when it opened, not summoned on purpose)
-- is hidden again.
local overlay_grace, overlay_kept, overlay_gen = false, nil, 0
hl.on("layer.closed", function(layer)
  if not (layer and FOCUS_OVERLAYS[layer.namespace]) then return end
  overlay_grace = true
  overlay_gen = overlay_gen + 1
  local gen = overlay_gen
  hl.timer(function()
    if gen ~= overlay_gen then return end
    overlay_grace = false
    overlay_kept = nil
  end, { timeout = 500, type = "oneshot" })
end)
hl.on("layer.opened", function(layer)
  if not (layer and FOCUS_OVERLAYS[layer.namespace]) then return end
  local monitor = hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  overlay_kept = shown and shown.name or nil
  local active = hl.get_active_window()
  if active and active.workspace and active.workspace.special
    and not (shown and shown.name == active.workspace.name) then
    dbg("overlay open: parking focus off hidden", active.workspace.name, layer.namespace)
    focus_regular(monitor)
  end
end)

hl.on("layer.opened", function(layer)
  if not (layer and layer.namespace == PANEL_NS) or panel_open then return end
  panel_open = true
  -- Hovering from one bar widget to the next closes and reopens the panel;
  -- keep the scratchpad from the first open through the whole run.
  panel_gen = panel_gen + 1
  local monitor = hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  kept_special = kept_special or (shown and shown.name)
  if kept_special then dim_special(kept_special, true) end
  -- If focus is still on a window in a HIDDEN dropdown/scratchpad (e.g. it
  -- was hidden with its own key), park it on a regular window now. Otherwise
  -- closing this panel hands focus back to that window and Hyprland shows its
  -- dropdown, which flashed open while hovering from one bar menu to the next.
  local active = hl.get_active_window()
  if active and active.workspace and active.workspace.special
    and not (shown and shown.name == active.workspace.name) then
    dbg("panel open: parking focus off hidden", active.workspace.name)
    focus_regular(monitor)
  end
  dbg("panel open", "gen=" .. panel_gen, "kept=" .. tostring(kept_special))
end)

hl.on("layer.closed", function(layer)
  if not (layer and layer.namespace == PANEL_NS) then return end
  panel_open = false
  panel_grace = true
  dbg("panel close", "gen=" .. panel_gen, "kept=" .. tostring(kept_special), "summoned=" .. tostring(summoned))
  local gen = panel_gen
  hl.timer(function()
    if gen ~= panel_gen then return end
    panel_grace = false
    if kept_special then dim_special(kept_special, false) end
    kept_special = nil
    summoned = nil
  end, { timeout = 500, type = "oneshot" })   -- half a second: moving to the next menu
end)

hl.on("window.active", function(window)
  window = window or hl.get_active_window()
  if not window or not window.workspace then return end
  if window.workspace.special then
    dbg("active special window", window.class, window.workspace.name,
      "panel_open=" .. tostring(panel_open), "grace=" .. tostring(panel_grace),
      "kept=" .. tostring(kept_special), "summoned=" .. tostring(summoned))
    if ((panel_open or panel_grace) and window.workspace.name ~= kept_special
        and window.workspace.name ~= summoned)
      or (overlay_grace and window.workspace.name ~= overlay_kept
        and window.workspace.name ~= summoned) then
      -- Checked a moment later (window.active fires before the monitor
      -- reports the special as shown), and only toggled if it really is
      -- showing, so this can never toggle one open.
      local name = window.workspace.name
      hl.timer(function()
        local monitor = hl.get_active_monitor()
        local shown = monitor and monitor.active_special_workspace
        dbg("guard check", name, "shown=" .. tostring(shown and shown.name))
        if shown and shown.name == name then toggle_special_named(name) end
      end, { timeout = 30, type = "oneshot" })
    end
    return
  end
  hide_special(window.monitor)
end)

-- Clicking a regular window while a scratchpad is showing doesn't move focus
-- (Hyprland keeps input on the special workspace), so the hook above never
-- fires. Watch left clicks without swallowing them, and hide the scratchpad
-- when the click lands outside all of its windows.
local function xy(v)
  if type(v) ~= "table" then return nil end
  return v.x or v[1], v.y or v[2]
end

local function inside(window, pos)
  local x, y = xy(window.at)
  local w, h = xy(window.size)
  if not (x and y and w and h) then return false end
  return pos.x >= x and pos.x < x + w and pos.y >= y and pos.y < y + h
end

-- Notification toasts report when the pointer is over them (daa.notifications)
-- so clicking one, or its close button, leaves the scratchpad up.
notification_hovered = false
function set_notification_hover(on)
  notification_hovered = on and true or false
end

hl.bind("mouse:272", function()
  -- Clicks in (or dismissing) a bar panel leave the dimmed scratchpad be.
  if panel_open or notification_hovered then return end
  local pos = hl.get_cursor_pos()
  local monitor = pos and hl.get_monitor_at(pos)
  local special = monitor and monitor.active_special_workspace
  if not special then return end

  for _, window in ipairs(hl.get_windows()) do
    if window.workspace and window.workspace.name == special.name
      and window.mapped and not window.hidden and inside(window, pos) then
      return
    end
  end

  hide_special(monitor)
end, { non_consuming = true })

-- Unbind existing SUPER + X (was: Universal cut)
hl.unbind("SUPER + X")
o.bind("SUPER + X", "Hide scratchpad", function()
  hide_special(hl.get_active_monitor())
end)

-- New windows open on the focused workspace, which is the scratchpad while
-- it's showing. Send them to the regular workspace underneath instead, so
-- they don't get hidden along with the scratchpad. Dropdowns are placed on
-- their special workspace by rule, so leave those alone.
hl.on("window.open", function(window)
  if not window or not window.workspace or not window.workspace.special then return end
  if window.class and window.class:match("^dropdown%.") then return end
  if dropdown_windows and dropdown_windows[window.address] then return end

  local monitor = window.monitor
  local regular = monitor and monitor.active_workspace
  if not regular then return end

  hl.dispatch(hl.dsp.window.move({
    workspace = tostring(regular.id),
    follow = false,
    window = "address:" .. window.address,
  }))
  hide_special(monitor)
  hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
end)

-- Debug: every special workspace shown or hidden, with what had focus and
-- where the cursor was.
hl.on("workspace.special_active", function(ws)
  -- A summoned dropdown that's been hidden again is no longer "on purpose".
  if not (ws and ws.name) and not panel_open and not panel_grace then summoned = nil end
  local active = hl.get_active_window()
  local pos = hl.get_cursor_pos()
  dbg(ws and ws.name and ("SHOW " .. ws.name) or "HIDE",
    "active=" .. tostring(active and active.class),
    "cursor=" .. (pos and (math.floor(pos.x or 0) .. "," .. math.floor(pos.y or 0)) or "?"),
    "panel_open=" .. tostring(panel_open), "grace=" .. tostring(panel_grace))
end)
