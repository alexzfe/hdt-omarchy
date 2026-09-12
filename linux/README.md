# Hearthstone Deck Tracker on Linux (hdt-omarchy)

This is a fork of [Hearthstone Deck Tracker](https://github.com/HearthSim/Hearthstone-Deck-Tracker)
that runs on Linux under Wine/Proton with a **working transparent in-game overlay**. Upstream HDT is
a Windows/WPF app; its overlay renders as an opaque black rectangle under Wine on Wayland. This fork
fixes that in HDT's own code, adds a `dotnet`-based Linux build, and ships the four Hyprland window
rules the tracker needs on Omarchy (installed by `install.sh`, see below).

**Supported target:** Omarchy (Hyprland on Wayland, XWayland) with the Battle.net prefix run through
umu-launcher and GE-Proton. That is the only setup this fork is tested on. The code paths that assume
the X11 window model and Hyprland's handling of it are gated on Wine's X11 driver being loaded
(`Wine.UsesX11Driver`); under Wine's own Wayland or macOS drivers HDT falls back to upstream window
handling, and other X11 compositors (KWin, Mutter, ...) are untested.

All changes are gated behind runtime Wine checks, so the Windows build and behaviour are unchanged;
the `windows-build` CI job builds and tests on Windows to keep it that way.

## Contents

- **The overlay fix** — [`Hearthstone Deck Tracker/Utility/Wine.cs`](../Hearthstone%20Deck%20Tracker/Utility/Wine.cs)
  plus small edits to the transparent windows. See [Why the overlay was black](#why-the-overlay-was-black).
- **Linux build** — `linux/build.sh`, `linux/fetch-deps.sh`, and two csproj changes so the project
  builds with the .NET SDK on Linux.
- **Install & run** — `linux/install.sh`, `linux/launch-hdt.in`, `linux/hearthstone-deck-tracker.desktop.in`,
  the app icon, and `linux/hdt-xerror-shim.c` (keeps Proton's Wine alive across an XInput error, see below).

## Requirements

- The **.NET SDK 8 or newer** for building (`dotnet` on `PATH`). A user-local SDK in `~/.dotnet`
  works; add it with `export PATH="$HOME/.dotnet:$PATH"`.
- A **Battle.net Wine prefix** with Hearthstone installed, launched via umu-launcher + a recent
  GE-Proton (wine 10/11 Staging). On Omarchy this is what `omarchy-launch-battlenet` sets up.
- `curl`, `git`, `unzip`, `rsync`; `umu-launcher` at run time.
- Optional: a C compiler with the X11 headers (`libx11`) for the X error shim, plus `gcc -m32` with
  `lib32-libx11` for its 32-bit half.

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
| Icon | `~/.local/share/icons/hicolor/256x256/apps/hearthstone-deck-tracker.png` |
| X error shim | `~/.local/share/hearthstone-deck-tracker/lib/<arch>/libhdt-xerror-shim.so` (see below) |

Then launch HDT (from the menu or `launch-hdt`), start Battle.net, and Play Hearthstone. HDT and the
game share one Wine session, so HDT sees the game and the overlay tracks it.

`install.sh` also writes a `VERSION` file (git describe, branch, date) next to the binaries; HDT logs
it at startup as `hdt-omarchy build: ...`. It never deletes a directory that is not an HDT install
(marker file, or the exe from an older install.sh), and `install.sh --uninstall` removes everything it
installed, including the Hyprland require line, and leaves the Wine prefix alone.

| Variable | Effect |
|---|---|
| `HDT_INSTALL_DIR` | install directory for the binaries |
| `HDT_SKIP_BUILD=1` | install the existing build output instead of building (`HDT_BUILD_OUTPUT` selects it) |
| `HDT_SKIP_SHIM=1` | do not build/install the X error shim |
| `HDT_NO_HYPR_RELOAD=1` | do not run `hyprctl reload` after installing the Hyprland rules |
| `OMARCHY_PATH` | Omarchy installation to take the Lua module loader from (default `~/.local/share/omarchy`, then `/usr/share/omarchy`) |

To just build without installing: `linux/build.sh [Debug|Release]`. Output lands in
`Hearthstone Deck Tracker/bin/x64/<Config>/`.

The launcher assumes the prefix at `~/Games/battlenet` and the `GE-Proton` umu runner. Override with
`HDT_WINEPREFIX`, `HDT_PROTONPATH`, `HDT_GAMEID`. The umu game id defaults to `umu-hdt`; it only
names this app (Proton turns it into the X11 window class `steam_app_hdt`, which the menu entry's
`StartupWMClass` and any compositor rules match on). The prefix is selected by `WINEPREFIX`, so HDT
still shares the game's Wine session.

## Running on Hyprland / Omarchy

`install.sh` installs a window-rules file, `~/.config/hypr/hearthstone-deck-tracker.lua` (source:
`linux/hyprland/hearthstone-deck-tracker.lua`), and appends one line to `~/.config/hypr/hyprland.lua`
that loads it through Omarchy's `require_optional` (a backup of `hyprland.lua` is kept next to it).
Re-running `install.sh` overwrites the rules file and leaves `hyprland.lua` alone once the line is
there. To customise, add your own `o.window` rules below that line; they run later and win.

What the rules do, and why every one of them matches **class and title** (all of HDT's windows share
the class `steam_app_hdt`, and Hearthstone/Battle.net inherit it when HDT launches them, or get
`steam_app_battlenet` when Battle.net does):

- **Main window floats** (`^Hearthstone Deck Tracker$`): Hyprland tiles it by default, and resizing
  the WPF window to a tile breaks its layout.
- **Hearthstone floats and fills the screen** (`^Hearthstone$`: `float`, `suppress_event` for
  `fullscreen maximize`, and a `window.open` handler): the game opens as a floating window covering
  the monitor minus the bar (the monitor's reserved area). It is not pinned, so it stays on its
  workspace when you switch away. Its own fullscreen and maximize requests are ignored, so set
  Hearthstone to windowed mode (Options > Graphics); `Super+F` still fullscreens it.
- **Battle.net floats** (`^Battle\.net`): launcher and login window.
- **The overlay is excluded from focus and kept on the game's workspace** (`^HearthstoneOverlay$`:
  `no_focus`, plus Lua event handlers):
  - `no_focus`: Hyprland's window hit test works on window boxes and ignores X11 input shapes, so the
    overlay covering the game would otherwise be what the pointer "hits": focus-follows-mouse
    activates it, `Super+O` pops *it* out, `Super`+drag moves it, and border resizing of the game
    stops working (Hyprland refuses resize handles when the window under the pointer is
    override-redirect). With `no_focus` the hit test skips the overlay and the game underneath gets
    all of that; keyboard focus reaches the game, and clicks still reach the overlay's buttons because
    Wine gives the click-through overlay an empty X11 input shape, which Xwayland honours.
  - Workspace: Hyprland puts an override-redirect window on whichever workspace is active when it maps
    or its X geometry changes by more than 2 px, never on its owner's. The overlay used to be pinned,
    which kept it above a pinned or fullscreen game but also showed it on every workspace. The
    handlers now move it to the game's workspace (`window.open`, `window.move_to_workspace`,
    `workspace.active`, `config.reloaded`) and pin it only while the game is pinned (`Super+O`). After
    the game's fullscreen state changes they raise it (`alter_zorder top`), because a fullscreen
    transition clears an "allowed over fullscreen" flag on every unpinned window on the workspace
    and only a raise sets it again.
  Do **not** add `center`/`size` (they displace the override-redirect window) or `pin`.
- **Why the overlay stays above a pinned game after clicks** (HDT source, not a rule): Hyprland raises
  a floating window on every click, and among pinned windows the last-raised one is drawn on top,
  so a pinned game would cover the pinned overlay after its first click. Under Wine the overlay now
  makes the game window its Win32 *owner* when it hooks the game (`Wine.SetOwner`); Wine writes that
  as the X11 `WM_TRANSIENT_FOR` hint when the overlay is mapped, and Hyprland moves an X11 window
  together with its transients on every raise, so the game can never end up above its overlay. If the
  game window handle changes (quick restart), the overlay re-owns and remaps itself (log:
  `Game window changed, remapping the overlay under the new owner`).

Plain (non-Lua) Hyprland config equivalent of the rules. The fill-the-screen and workspace handlers
need the Lua config; without them the game opens centred at its own size and the overlay stays on the
workspace that was active when it appeared:

```
windowrule = float on, center on, size 1400 900, match:class ^steam_app_hdt$, match:title ^Hearthstone Deck Tracker$
windowrule = float on, suppress_event fullscreen maximize, match:class ^steam_app_(hdt|battlenet)$, match:title ^Hearthstone$
windowrule = float on, center on, match:class ^steam_app_(hdt|battlenet)$, match:title ^Battle\.net
windowrule = no_focus on, match:class ^steam_app_hdt$, match:title ^HearthstoneOverlay$
```

- **Icon.** The desktop entry uses the `hearthstone-deck-tracker` icon that `install.sh` installs, and
  `StartupWMClass=steam_app_hdt` lets bars and docks match the running window to it.

## "X Error of failed request: XI_BadDevice" — HDT disappears mid-session

Proton's Wine (`winex11.drv/mouse.c`, `update_device_mapping`) reads the XInput 1 button mapping of
the pointer slave device that last sent an event. Under XWayland, the compositor dropping the seat's
pointer capability for a moment (an input device toggled or unplugged, for example) makes XWayland
*disable* its pointer devices. `XOpenDevice` still accepts a disabled device, but
`X_GetDeviceButtonMapping` answers `XI_BadDevice`. Wine hands unexpected X errors to Xlib's default
handler, which prints the error and calls `exit(1)` — the app just vanishes. Upstream Wine does not
have this code; it is Proton-specific. In the journal it looks like:

```
X Error of failed request:  XI_BadDevice (invalid Device parameter)
  Major opcode of failed request:  131 (XInputExtension)
  Minor opcode of failed request:  28 (X_GetDeviceButtonMapping)
```

`linux/hdt-xerror-shim.c` is a tiny `LD_PRELOAD` library that wraps `XSetErrorHandler` so the fallback
Wine remembers is a logging, non-fatal handler instead of Xlib's exiting default. Errors Wine expects
or ignores are untouched. `install.sh` builds it for 64- and 32-bit and `launch-hdt` preloads it via
`$LIB` so each Wine process picks the right one. Set `HDT_NO_XERROR_SHIM=1` to run without it. Any
other Proton app in the same session (Hearthstone itself) is exposed to the same bug; the shim can
be added to its launcher the same way (`LD_PRELOAD=<dir>/\$LIB/libhdt-xerror-shim.so`).

### Build dependencies

HDT references externally-hosted libraries (HearthDb, **HearthMirror**, HSReplay, BobsBuddy) and the
HDT-Localization strings. On Windows the upstream `Bootstrap` project downloads these; on Linux,
`linux/fetch-deps.sh` does the same from `https://libs.hearthsim.net/hdt/`. These libraries are **not
redistributable** and are gitignored — they are fetched fresh at build time, never committed.

## Overlay tracking and background handling under Wine

Three more Wine/Wayland differences are handled in `OverlayWindow` (all Wine-gated or harmless on
Windows):

- **The overlay never followed the game window.** HDT tracks the game window with an out-of-context
  `SetWinEventHook` on the game's thread without a module handle. Windows allows that; wineserver
  rejects it (`server/hook.c`, `set_hook`: "module is optional only if hook is in current process"),
  so the hook handle is `NULL` and no `EVENT_OBJECT_LOCATIONCHANGE` ever arrives. Any later move or
  resize of the game window (fullscreen toggles, resolution changes, the window being restored after
  losing focus) left the overlay where it was. The overlay now falls back to polling the game
  rectangle every 250 ms when the hook cannot be installed; the log says
  `Could not hook the Hearthstone window, polling its position instead`.
- **"Hide overlay when Hearthstone is in the background" did nothing.** On Windows that setting sends
  the overlay behind the game window. Hyprland draws override-redirect X11 windows above everything,
  so the overlay stayed on top, including over HDT's own settings window. Under Wine the overlay now
  hides its content (opacity 0) while the game is in the background and shows it again when the game
  is focused. Note that Hyprland's default focus-follows-mouse means merely hovering HDT's floating
  main window over the game counts as "background" until the pointer returns to the game.
- **Focus on the overlay or its popups is not "background".** Focus given to the overlay window
  itself, or to a tooltip/popup it owns, no longer counts as Hearthstone losing the foreground, which
  avoided a hide/show cycle on every hover.
- **The overlay must never become a "managed" window.** Wine re-decides on every `SetWindowPos`
  whether a popup is override-redirect or managed (`winex11.drv/window.c`, `is_window_managed`): it
  becomes managed, permanently, if it is the thread's active window at that moment, if the call
  activates it, or if it owns a managed popup. Clicking a button on the overlay makes WPF focus it,
  i.e. activates it, so a position update or z-order change right after a click turned the overlay
  into a normal window that Hyprland tiled at the screen edge. Under Wine the overlay now answers
  `WM_MOUSEACTIVATE` with `MA_NOACTIVATE`, skips the topmost/send-to-back `SetWindowPos` calls (the
  compositor stacks it anyway), and, if it is the active window when the game window moves, first
  hands the foreground back to the game and moves on the next tick. With HDT's `LogLevel` setting above 0
  (Debug) the log shows every applied rectangle (`Overlay rect set to ...`, `Game window moved to ...`),
  which makes misplacement reports easy to read.

## Overlay buttons and X stacking

XWayland hands every click to the topmost X window under the pointer, in the X server's own stacking
order, which is not the order Hyprland draws windows in. Hyprland moves a managed X11 window to the top
of that order whenever it activates it. After the game window was focused, moved or resized, the game
therefore sat above the override-redirect overlay in X: the overlay was still drawn on top and its
buttons still showed hover effects, but every click went to the game. This showed up as dead
Battlegrounds tabs (Comps, Minions) whenever the game was not fullscreen.

Under Wine's X11 driver HDT raises the overlay again without activating it
(`Wine.RaiseWithoutActivating`): `SetWindowPos` to `HWND_NOTOPMOST`, then back to `HWND_TOPMOST`, with
`SWP_NOACTIVATE`. A single `HWND_TOPMOST` does nothing because Wine sees the overlay as already on top of
the Win32 z-order and never restacks the X window. It runs when the pointer enters an overlay button,
after the game window moves or resizes, and when the game regains focus. It is skipped while the
overlay is Wine's active window, the condition that would make Wine hand it to the window manager.

## Known issues

- **Overlay buttons at the smallest pop-out size.** With the X stacking fix above, the Battlegrounds
  Comps/Minions tabs work fullscreen and with a windowed game down to at least 1541x1110 (real-game
  test). At Omarchy's `Super+O` pop-out size (1300x900) they still do not respond: the click never
  reaches the button. X stacking is not the cause at that size; it is probably HDT's own click-through
  detection or layout at that scale. Workaround: make the game window larger, or fullscreen.
- **Overlay after leaving fullscreen.** Reported once (the overlay stayed gone after fullscreen →
  windowed); it no longer reproduces with the real game or in the test bench, and no specific fix was
  identified. If it comes back, the `hyprctl clients -j` fields `pinned`, `allowedOverFullscreen` and
  `mapped` for `HearthstoneOverlay` are the first thing to check while it is gone.
- **Settings while in game.** The report was: opening HDT's settings while Hearthstone is running
  stops the overlay being placed over the game and it occasionally flickers. Two causes were found and
  fixed (the window hook above, and the class-only Hyprland rule floating/centring the overlay); the
  scenario now behaves in an isolated test bench with a fake game window, but has not been re-tested
  against the real game yet.
- The overlay's visibility state changes are logged under Wine (`Overlay Visible -> Behind (game
  foreground: False, foreground window: ...)`), next to the position lines, so "the overlay is gone" reports can be read from
  `hdt_log.txt`: no state change means the compositor stopped drawing it (see the pin rule above).
- Closing the main window quits HDT, overlay included, unless *Close to tray* is enabled in HDT's
  settings (`CloseToTray` in `config.xml`).

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

## Development: tests, CI, hardening status

- `HDTTests/Utility/WineTests.cs` covers the pure parts of `Wine.cs` (the per-monitor full-screen
  clamp, the detection override). The MSTest suites need Windows to run: the `windows-build` workflow
  runs them on GitHub, and `linux/tests/run-tests-wine.sh` runs them inside the Wine prefix with
  vstest (session 6: all 8 Wine tests pass there).
- `linux-build` compiles HDT and HDTTests on Linux, shellchecks the scripts, runs
  `linux/tests/install-smoke.sh` (install.sh against a throwaway HOME) and compiles the shim.
- `linux/HARDENING.md` is the production-readiness checklist: what was found in review, what has
  landed, and which real-game checks are still open.

## Relationship to upstream

This fork tracks `master` from HearthSim/Hearthstone-Deck-Tracker. Linux changes live on the
`omarchy` branch. Upstream HDT is © HearthSim, All Rights Reserved; this fork redistributes only
source, never the closed-source libraries or built binaries.
