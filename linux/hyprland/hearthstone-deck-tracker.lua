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

-- Hearthstone: a floating window with the geometry of a lone tile (monitor minus bar, gaps and
-- border, see tile_box), not pinned, so it stays on its workspace. Floating rather than tiled because
-- Hyprland draws floating windows above tiled ones: a tiled game could never cover HDT's floating main
-- window, while a floating game is raised above it whenever it is clicked. The game's own
-- fullscreen/maximize requests are ignored; set Hearthstone to windowed mode (Options > Graphics).
-- Super+F still fullscreens it. Super+O (Omarchy's pop toggle) tiles an already floating window on the
-- first press and pops it out (float + pin, 1300x900) on the second.
o.window({ class = "^steam_app_(hdt|battlenet)$", title = "^Hearthstone$" }, { float = true, suppress_event = "fullscreen maximize" })

-- Battle.net launcher and its login window.
o.window({ class = "^steam_app_(hdt|battlenet)$", title = "^Battle\\.net" }, { float = true, center = true })

-- In-game overlay: keep it out of the focus/hit test, nothing else. Hyprland's hit test works on window
-- boxes, so without no_focus the full-size overlay (click-through at the X11 level) would take pointer
-- focus, drags, border resizing and Super+O from the game. Keyboard focus still reaches the game.
-- Do not add center/size (they displace the override-redirect window) or a static pin (it would show
-- the overlay on every workspace); the handlers below pin it only while the game's workspace is active.
o.window({ class = "^steam_app_hdt$", title = "^HearthstoneOverlay$" }, { no_focus = true })

local function is_game(w)
  return w ~= nil and w.title == "Hearthstone" and (w.class == "steam_app_hdt" or w.class == "steam_app_battlenet")
end

local function is_overlay(w)
  return w ~= nil and w.title == "HearthstoneOverlay" and w.class == "steam_app_hdt"
end

-- The box a window tiled alone on this monitor would get: x, y, width, height. Lua monitor
-- width/height are pixels, x/y and reserved are logical units.
local function tile_box(m)
  local r, g, b = m.reserved, hl.get_config("general:gaps_out"), hl.get_config("general:border_size")
  return m.x + r.left + g.left + b, m.y + r.top + g.top + b,
    m.width / m.scale - r.left - r.right - g.left - g.right - 2 * b,
    m.height / m.scale - r.top - r.bottom - g.top - g.bottom - 2 * b
end

-- resize keeps a floating window centred, so move afterwards.
local function place_game(game)
  local m = game.monitor
  if not m then
    return
  end
  local x, y, w, h = tile_box(m)
  hl.dispatch(hl.dsp.window.resize({ window = game, x = w, y = h }))
  hl.dispatch(hl.dsp.window.move({ window = game, x = x, y = y }))
end

local function game_placed(game)
  local m = game.monitor
  if not m then
    return true
  end
  local x, y, w, h = tile_box(m)
  local function near(a, b)
    return math.abs(a - b) <= 1
  end
  return near(game.at.x, x) and near(game.at.y, y) and near(game.size.x, w) and near(game.size.y, h)
end

local function find_game()
  for _, w in ipairs(hl.get_windows()) do
    if is_game(w) then
      return w
    end
  end
end

-- Wine reserves room for the title bar and borders it expects the window manager to draw around a
-- decorated window (Hearthstone in windowed mode is one). Hyprland draws no frame, so when the game
-- applies its own saved window size, typically a second or two after the window maps, Wine
-- re-positions the client area by that phantom frame and the window ends up hanging off the screen
-- (observed at (12,56) and (4,73) instead of the intended origin). A move from the compositor is
-- honoured, so re-check the placement for a while after the game opens. Skipped once the game is
-- pinned (Omarchy's Super+O pop-out), which is the user's own placement.
local PLACE_RECHECK_MS = 500
local PLACE_RECHECK_FOR_MS = 30000

local keep_placed

-- The overlay is an override-redirect window: Hyprland puts it on whatever workspace is active when it
-- maps or its X geometry changes, never on the game's, and draws the focused floating game above it
-- whenever the game is (re)focused, which makes it invisible until its geometry changes again. Pinned
-- windows are drawn in a final pass above everything else, so the overlay is pinned while the game's
-- workspace is active (or the game itself is pinned by Super+O; among pinned windows the game's owner
-- link keeps the overlay on top). A pinned window shows on every workspace, so when another workspace
-- is active it is unpinned and parked on the game's workspace instead.
-- raise: a fullscreen transition hides every unpinned window on the workspace until it is raised again.
local function sync_overlay(raise, active_ws)
  local game = find_game()
  if not game or not game.workspace then
    return
  end
  if type(active_ws) ~= "table" or active_ws.id == nil then
    active_ws = hl.get_active_workspace()
  end
  local show = game.pinned or (active_ws ~= nil and active_ws.id == game.workspace.id)
  for _, overlay in ipairs(hl.get_windows({ class = "steam_app_hdt", title = "HearthstoneOverlay" })) do
    local was_pinned = overlay.pinned
    if was_pinned ~= show then
      hl.dispatch(hl.dsp.window.pin({ window = overlay, action = show and "on" or "off" }))
    end
    if not show and (was_pinned or not overlay.workspace or overlay.workspace.id ~= game.workspace.id) then
      hl.dispatch(hl.dsp.window.move({ window = overlay, workspace = game.workspace, follow = false }))
    end
    if raise then
      hl.dispatch(hl.dsp.window.alter_zorder({ window = overlay, mode = "top" }))
    end
  end
end

function keep_placed(elapsed)
  hl.timer(function()
    local game = find_game()
    if not game or game.pinned then
      return
    end
    if not game_placed(game) then
      place_game(game)
    end
    -- HDT moves the overlay up to 250 ms after the game moved; a moved override-redirect window
    -- lands on the active workspace, so keep syncing it while the game may still be moving.
    sync_overlay(false)
    if elapsed + PLACE_RECHECK_MS < PLACE_RECHECK_FOR_MS then
      keep_placed(elapsed + PLACE_RECHECK_MS)
    end
  end, { timeout = PLACE_RECHECK_MS, type = "oneshot" })
end

hl.on("window.open", function(w)
  if is_game(w) then
    place_game(w)
    sync_overlay(false)
    keep_placed(0)
  elseif is_overlay(w) then
    sync_overlay(true)
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

-- Pin the overlay on the game's workspace, park it there unpinned everywhere else.
hl.on("workspace.active", function(ws)
  sync_overlay(false, ws)
end)

hl.on("config.reloaded", function()
  sync_overlay(true)
end)
