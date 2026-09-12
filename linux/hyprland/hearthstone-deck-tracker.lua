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

-- Hearthstone: never tile the game window.
o.window({ class = "^steam_app_(hdt|battlenet)$", title = "^Hearthstone$" }, { float = true, center = true })

-- Battle.net launcher and its login window.
o.window({ class = "^steam_app_(hdt|battlenet)$", title = "^Battle\\.net" }, { float = true, center = true })

-- In-game overlay: pin it, nothing else. Hyprland draws pinned windows in a final pass above all
-- other windows, so the overlay stays visible over a pinned game (Omarchy's Super+O "pop out") and
-- over a fullscreen game, whose fullscreen transition otherwise hides every unpinned window on the
-- workspace. The overlay is override-redirect and click-through; HDT hides it (opacity 0) whenever
-- the game is not focused, so pinning does not show it on other workspaces in practice.
-- Do not add center/size (they displace it) or no_focus (it blocks keyboard focus to the game).
o.window({ class = "^steam_app_hdt$", title = "^HearthstoneOverlay$" }, { pin = true })
