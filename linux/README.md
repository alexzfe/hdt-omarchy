# Hearthstone Deck Tracker on Linux (hdt-omarchy)

This is a fork of [Hearthstone Deck Tracker](https://github.com/HearthSim/Hearthstone-Deck-Tracker)
that runs on Linux under Wine/Proton with a **working transparent in-game overlay**, tested on
Omarchy (Hyprland / XWayland). Upstream HDT is a Windows/WPF app; its overlay renders as an opaque
black rectangle under Wine on Wayland. This fork fixes that in HDT's own code, with no window-manager
rules required, and adds a `dotnet`-based Linux build.

All changes are gated behind a runtime Wine check, so the Windows build and behaviour are unchanged.

## Contents

- **The overlay fix** — [`Hearthstone Deck Tracker/Utility/Wine.cs`](../Hearthstone%20Deck%20Tracker/Utility/Wine.cs)
  plus small edits to the transparent windows. See [Why the overlay was black](#why-the-overlay-was-black).
- **Linux build** — `linux/build.sh`, `linux/fetch-deps.sh`, and two csproj changes so the project
  builds with the .NET SDK on Linux.
- **Install & run** — `linux/install.sh`, `linux/launch-hdt.in`, `linux/hearthstone-deck-tracker.desktop.in`.

## Requirements

- The **.NET SDK 8 or newer** for building (`dotnet` on `PATH`). A user-local SDK in `~/.dotnet`
  works; add it with `export PATH="$HOME/.dotnet:$PATH"`.
- A **Battle.net Wine prefix** with Hearthstone installed, launched via umu-launcher + a recent
  GE-Proton (wine 10/11 Staging). On Omarchy this is what `omarchy-launch-battlenet` sets up.
- `curl`, `git`, `unzip`, `rsync`.

## Build & install

```bash
git clone https://github.com/<you>/hdt-omarchy.git
cd hdt-omarchy
linux/install.sh
```

`install.sh` fetches the build dependencies, builds Release, and installs:

| | Path |
|---|---|
| Binary | `~/.local/share/hearthstone-deck-tracker/app/` (override with `HDT_INSTALL_DIR`) |
| Launcher | `~/.local/bin/launch-hdt` |
| Menu entry | `~/.local/share/applications/hearthstone-deck-tracker.desktop` |

Then launch HDT (from the menu or `launch-hdt`), start Battle.net, and Play Hearthstone. HDT and the
game share one Wine session, so HDT sees the game and the overlay tracks it.

To just build without installing: `linux/build.sh [Debug|Release]`. Output lands in
`Hearthstone Deck Tracker/bin/x64/<Config>/`.

The launcher assumes the prefix at `~/Games/battlenet` and the `GE-Proton`/`umu-battlenet` umu ids.
Override with `HDT_WINEPREFIX`, `HDT_PROTONPATH`, `HDT_GAMEID`.

### Build dependencies

HDT references externally-hosted libraries (HearthDb, **HearthMirror**, HSReplay, BobsBuddy) and the
HDT-Localization strings. On Windows the upstream `Bootstrap` project downloads these; on Linux,
`linux/fetch-deps.sh` does the same from `https://libs.hearthsim.net/hdt/`. These libraries are **not
redistributable** and are gitignored — they are fetched fresh at build time, never committed.

## One-time Wine prefix setup

The overlay fix is code, but HDT still needs a prefix that can run a .NET Framework 4.8 WPF app.
On Omarchy, starting from `omarchy-launch-battlenet`'s prefix (`~/Games/battlenet`):

1. **Back up the prefix first** (e.g. `cp --reflink=auto -r ~/Games/battlenet ~/Games/battlenet.bak`).
2. Install .NET Framework 4.8, then restore Windows 10 (dotnet48 flips the prefix to Win7, which
   Battle.net rejects):
   ```bash
   env WINEPREFIX=~/Games/battlenet PROTONPATH=GE-Proton GAMEID=umu-battlenet PROTON_VERB=run \
     umu-run winetricks -q dotnet48
   env WINEPREFIX=~/Games/battlenet PROTONPATH=GE-Proton GAMEID=umu-battlenet PROTON_VERB=run \
     umu-run winetricks -q win10
   ```
3. Registry (same as the Lutris HDT installer):
   - `HKCU\Software\Microsoft\Avalon.Graphics` `DisableHWAcceleration` = dword `1` (WPF software rendering)
   - `HKCU\Software\Wine\X11 Driver` `UseTakeFocus` = `"N"`
4. `Hearthstone/client.config` containing `[Log]` / `FileSizeLimit.Int=-1` so Wine doesn't hit
   Hearthstone's per-session log cap (HDT also maintains this file).

## Why the overlay was black

Two behaviours of Wine's X11 driver, both confirmed by test (the compositor side was fine):

1. **Alpha-0 pixels are cut out of the window shape.** Wine turns a layered window's per-pixel alpha
   (`UpdateLayeredWindow`) into an X11 bounding *shape*: any fully-transparent pixel is removed from
   the window. XWayland never paints those pixels and the compositor shows them as opaque **black**.
   WPF's transparent areas are `(0,0,0,0)`, so the whole empty overlay came out black.
   *Fix:* paint transparent backgrounds with an alpha of `1/255` instead of `0`. Every pixel stays
   inside the shape; the colour is invisible on screen.

2. **Managed vs override-redirect windows.** Wine makes a `WS_POPUP` window *override-redirect*
   (unmanaged: the compositor won't tile, focus, or decorate it, and it stacks above a fullscreen
   game) only if it is never activated, has no caption, and does **not** cover a whole monitor.
   *Fix:* don't activate the overlay on show (`ShowActivated = false`) and keep it one pixel short of
   full-screen height. Wine then hands the compositor an override-redirect window that already
   behaves exactly like an overlay — no window-manager rules needed.

Click-through is unaffected: WPF's `WS_EX_TRANSPARENT` maps to an empty X11 *input* shape, so clicks
fall through the transparent overlay to the game, while clicks on visible HDT panels hit the overlay.

The same transparent-background fix is applied to HDT's splash and toast windows so they don't render
black either. See `Utility/Wine.cs` for the (Wine-only) implementation.

## Relationship to upstream

This fork tracks `master` from HearthSim/Hearthstone-Deck-Tracker. Linux changes live on the
`omarchy` branch. Upstream HDT is © HearthSim, All Rights Reserved; this fork redistributes only
source, never the closed-source libraries or built binaries.
