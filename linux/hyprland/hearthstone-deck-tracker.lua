-- Hearthstone Deck Tracker (hdt-omarchy): Hyprland window rules for Omarchy.
--
-- linux/install.sh copies this file to ~/.config/hypr/hearthstone-deck-tracker.lua and loads it from
-- ~/.config/hypr/hyprland.lua. Re-running install.sh overwrites the copy; keep local edits in
-- hyprland.lua instead (rules there run later and win).
--
-- Every rule matches class AND title. All of HDT's windows share the class steam_app_hdt, and
-- Hearthstone/Battle.net inherit it when HDT launches them (steam_app_battlenet when Battle.net does).

-- Main window: floating. Tiling resizes the WPF window and breaks its layout.
o.window({ class = "^steam_app_hdt$", title = "^Hearthstone Deck Tracker$" }, { float = true, center = true, size = { 1400, 900 } })

-- Hearthstone: a floating window that fills the monitor's usable area (fill_work_area below), not
-- pinned, so it stays on its workspace. The game's own fullscreen/maximize requests are ignored so it
-- stays that way; set Hearthstone to windowed mode (Options > Graphics). Super+F still fullscreens it.
o.window({ class = "^steam_app_(hdt|battlenet)$", title = "^Hearthstone$" }, { float = true, suppress_event = "fullscreen maximize" })

-- Battle.net launcher and its login window.
o.window({ class = "^steam_app_(hdt|battlenet)$", title = "^Battle\\.net" }, { float = true, center = true })

-- In-game overlay: keep it out of the focus/hit test, nothing else. Hyprland's hit test works on window
-- boxes, so without no_focus the full-size overlay (click-through at the X11 level) would take pointer
-- focus, drags, border resizing and Super+O from the game. Keyboard focus still reaches the game.
-- Do not add center/size (they displace the override-redirect window) or pin (it shows the overlay on
-- every workspace); the handlers below keep it with the game instead.
o.window({ class = "^steam_app_hdt$", title = "^HearthstoneOverlay$" }, { no_focus = true })

local function is_game(w)
  return w ~= nil and w.title == "Hearthstone" and (w.class == "steam_app_hdt" or w.class == "steam_app_battlenet")
end

local function is_overlay(w)
  return w ~= nil and w.title == "HearthstoneOverlay" and w.class == "steam_app_hdt"
end

local function find_game()
  for _, w in ipairs(hl.get_windows()) do
    if is_game(w) then
      return w
    end
  end
end

-- Size and place the game on the monitor minus the bar and other reserved space.
local function fill_work_area(game)
  local m = game.monitor
  if not m then
    return
  end
  local r = m.reserved
  hl.dispatch(hl.dsp.window.resize({
    window = game,
    x = m.width / m.scale - r.left - r.right,
    y = m.height / m.scale - r.top - r.bottom,
  }))
  hl.dispatch(hl.dsp.window.move({ window = game, x = m.x + r.left, y = m.y + r.top }))
end

-- The overlay is an override-redirect window: Hyprland puts it on whatever workspace is active when it
-- maps or moves, never on the game's. Keep it on the game's workspace, pinned only while the game is
-- pinned (Omarchy's Super+O "pop out" pins it; a pinned game is drawn above an unpinned overlay).
-- raise: a fullscreen transition hides every unpinned window on the workspace until it is raised again.
local function sync_overlay(raise)
  local game = find_game()
  if not game or not game.workspace then
    return
  end
  for _, overlay in ipairs(hl.get_windows({ class = "steam_app_hdt", title = "HearthstoneOverlay" })) do
    if overlay.pinned ~= game.pinned then
      hl.dispatch(hl.dsp.window.pin({ window = overlay, action = game.pinned and "on" or "off" }))
    end
    if not game.pinned and (not overlay.workspace or overlay.workspace.id ~= game.workspace.id) then
      hl.dispatch(hl.dsp.window.move({ window = overlay, workspace = game.workspace, follow = false }))
    end
    if raise then
      hl.dispatch(hl.dsp.window.alter_zorder({ window = overlay, mode = "top" }))
    end
  end
end

hl.on("window.open", function(w)
  if is_game(w) then
    fill_work_area(w)
    sync_overlay(false)
  elseif is_overlay(w) then
    sync_overlay(false)
  end
end)

hl.on("window.move_to_workspace", function(w)
  if is_game(w) then
    sync_overlay(false)
  end
end)

hl.on("window.pin", function(w)
  if is_game(w) then
    sync_overlay(false)
  end
end)

hl.on("window.fullscreen", function(w)
  if is_game(w) then
    sync_overlay(true)
  end
end)

-- Safety net for the overlay being moved to the active workspace by a geometry change.
hl.on("workspace.active", function()
  sync_overlay(false)
end)

hl.on("config.reloaded", function()
  sync_overlay(true)
end)
