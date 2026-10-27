-- Collapse workspaces left: whenever a numbered workspace (1-10) empties out,
-- shift every occupied workspace after it down so they stay packed from 1.
-- e.g. 1 empty, 2 = nvim, 3 = terminal  ->  1 = nvim, 2 = terminal.
-- If the workspace you're on gets renumbered, focus follows it.

local collapsing = false
local pending = false

local function occupied_workspaces()
  local by_id = {}
  for _, window in ipairs(hl.get_windows()) do
    local ws = window.workspace
    if ws and not ws.special and ws.id >= 1 and ws.id <= 10 then
      by_id[ws.id] = by_id[ws.id] or {}
      table.insert(by_id[ws.id], window)
    end
  end

  local ids = {}
  for id in pairs(by_id) do table.insert(ids, id) end
  table.sort(ids)
  return ids, by_id
end

-- Desktop settings (daa.settings): "workspaceCollapse": false turns this off.
local function enabled()
  local f = io.open((os.getenv("HOME") or "") .. "/.config/omarchy/daa-ui.json", "r")
  if not f then return true end
  local text = f:read("a") or ""
  f:close()
  return not text:find('"workspaceCollapse"%s*:%s*false')
end

local function collapse()
  if not enabled() then return end
  local active = hl.get_active_workspace()
  -- Standing on an empty workspace usually means you're about to open
  -- something there; don't shuffle windows into it from under you.
  if active and not active.special and active.windows == 0 then return end

  local ids, by_id = occupied_workspaces()
  local focus_target = nil

  collapsing = true
  for slot, id in ipairs(ids) do
    if id ~= slot then
      for _, window in ipairs(by_id[id]) do
        hl.dispatch(hl.dsp.window.move({
          workspace = tostring(slot),
          follow = false,
          window = "address:" .. window.address,
        }))
      end
      if active and active.id == id then focus_target = slot end
    end
  end
  if focus_target then
    hl.dispatch(hl.dsp.focus({ workspace = tostring(focus_target) }))
  end
  collapsing = false
end

-- Debounced so a burst of events (or our own moves) triggers one pass.
local function schedule()
  if collapsing or pending then return end
  pending = true
  hl.timer(function()
    pending = false
    collapse()
  end, { timeout = 150, type = "oneshot" })
end

for _, event in ipairs({
  "window.open",
  "window.destroy",
  "window.move_to_workspace",
  "workspace.active",
  "workspace.removed",
}) do
  hl.on(event, schedule)
end
