# Production-hardening checklist (`omarchy` branch)

Review of the fork's additions as of `cfd18843` plus the session-5 diagnostics, done on the
`production-hardening` branch, which was merged into `omarchy` at `770cfe53` and deleted. Tick items
as they land; keep each fix a small commit.

**Status (2026-09-13):** sections A, B, D and E are done except where noted. Section C lists the
real-game checks: what has been confirmed, with the session and evidence, and what is still missing,
with the exact steps. Everything on `omarchy` builds (`linux/build.sh Release`, `dotnet build
HDTTests`), passes shellcheck and the install smoke test, and both CI jobs pass on GitHub.

## A. Code (HDT source, all Wine-gated)

- [x] **Gate matches the assumptions.** `Wine.UsesX11Driver` (winex11.drv loaded as a PE module,
      verified with a probe under GE-Proton 11) now gates the X11/Hyprland assumptions: the
      SetTopmost/SendToBack no-ops, the owner link, WM_MOUSEACTIVATE, the full-screen clamp, the
      opacity hide and the X raise. `Wine.IsWine` keeps the harmless alpha-1 background and
      diagnostics. Wine's Wayland/macOS drivers fall back to upstream behaviour. (`10f2e15b`)
- [x] **One place computes overlay opacity.** `OverlayWindow.ApplyOpacity` is the only writer of
      `Opacity`; the Behind state feeds it through `_hiddenBehindGame`. (`10f2e15b`)
- [x] **Full-screen clamp per monitor.** `Wine.AvoidFullScreenHeight` uses the monitor containing
      the game rect (`System.Windows.Forms.Screen`); pure part `ClampToMonitor`, unit-tested. (`10f2e15b`)
- [x] **Bounded focus hand-back.** At most 8 `BringHsToForeground` calls (2 s), then a single Warn
      and waiting. (`10f2e15b`)
- [x] **Diagnostic logging at Debug.** Per-move lines (`Game window moved`, `Overlay rect set`,
      guides tab) are Debug (visible with `LogLevel=1` in config.xml); state changes stay Info and
      name the foreground window. (`10f2e15b`)
- [x] **Session-5 experiments decided.** Committed as one unit (`e8ed56ec`), then: the 400 ms
      background debounce dropped (disproved for the Comps issue by the 15:02 test; it only damped
      34-736 ms foreground flips to HDT's main window); `RaiseWithoutActivating` kept and restored
      with the evidence in its doc comment: the 15:19 query_pointer probe showed X stacking flip to
      OVERLAY < GAME after the game is clicked/dragged/focused, and Battlegrounds tab clicks were
      logged only with the raise (15:33). (`10f2e15b`, `5240c7e9`)
- [ ] **Game-window owner lifecycle.** Wine clears a cross-process owner when the owner window is
      destroyed (win32u `NtUserDestroyWindow` sets the owner of other-thread owned windows to 0), so
      a game crash leaves the overlay unowned, and the next game window is owned afresh. Documented
      in `Wine.SetOwner`. Kill half done (session 8, 2026-09-12 18:28: `Exited game`, owner cleared by
      `UnhookGameWindow` without a warning, HDT kept running and shut down cleanly). Restart half
      still open: see C.
- [x] **csproj change is conditional.** `ExecuteAsTool="$(HdtStringsResGenAsTool)"`, false only when
      `$(OS) != Windows_NT`. (`a9483ae5`)
- [x] **No crash reports to HearthSim.** The Release build used to bake upstream's production Sentry DSN
      (csproj fallback when `SENTRY_DSN` is empty), so Wine crashes were reported into HearthSim's
      project as "Portable". `HdtDisableSentry=true`, passed by `linux/build.sh`, leaves the DSN empty
      and the SDK disabled; `HDT_SENTRY_DSN` points the build at a project of your own. (session 8)
- [x] **Build version in the log.** `install.sh` writes `VERSION`; HDT logs `hdt-omarchy build: ...`
      at Wine detection. (`35308dc5`, `33279681`)

## B. Install and launcher (`linux/`)

- [x] **Guard `rsync --delete`.** Marker file `.hdt-omarchy-install`; non-empty foreign directories
      are refused. (`35308dc5`)
- [x] **Check prerequisites up front.** rsync always; curl/git/unzip when dependencies must be
      fetched; C compiler warning; `launch-hdt` errors clearly without `umu-run` or the prefix. (`35308dc5`)
- [x] **Hyprland step only on Omarchy.** Requires Omarchy's `default/hypr/require_optional.lua`
      (`OMARCHY_PATH`, `~/.local/share/omarchy`, `/usr/share/omarchy`); prints the appended line;
      `HDT_NO_HYPR_RELOAD=1`. `omarchy refresh hyprland` still removes the line; re-run install.sh. (`35308dc5`)
- [x] **Shim scope and noise.** Decision: keep preloading via `$LIB` whenever the 64-bit build
      exists. Pointing at the 64-bit file when the 32-bit one is missing would produce the same
      per-process ld.so line ("wrong ELF class"), so nothing is gained; install.sh now says which
      packages give the 32-bit half. The launcher comment and README say the shim reaches every
      process umu starts. Shim init is now safe under concurrent first calls. (`35308dc5`)
- [x] **Version stamp, uninstall.** `VERSION` file; `install.sh --uninstall`. (`35308dc5`)
- [ ] **Upgrades wipe the install directory's `Plugins/`.** HDT creates `Plugins/` next to the exe and
      loads plugins from there as well as from `%AppData%\HearthstoneDeckTracker\Plugins`; `rsync
      --delete` removes it on every re-install (same for decks/config if a user turns off "save in
      AppData"). Fix: exclude `Plugins/` from the delete, or document the AppData folder as the place.

## C. Verification (real game, record the result in `linux/README.md`)

Layout under test since session 8 (2026-09-13, commit `a66a12ea`): the game floats at the geometry of
a lone tile, unpinned; the overlay is pinned only while the game's workspace is active. Anything
ticked before session 7 was verified with the older pinned-overlay or float-and-fill layouts and is
kept for the record.

### Confirmed

- [x] Super+O (pinned game), moving, resizing (user, end of session 4). Re-confirmed with the current
      layout: Super+O pins game and overlay together and the overlay is visible afterwards (user,
      session 8, 2026-09-13 02:37; note Omarchy's toggle tiles an already floating window on the
      first press and pops it out on the second).
- [x] Fullscreen -> windowed (user, session 5, 15:02).
- [x] Battlegrounds tabs at ordinary windowed sizes, e.g. 1541x1110 (user, session 5, 15:33, with the
      raise). Tab clicks and an hour of Battlegrounds (session 7, 2026-09-12 17:11-18:11, BobsBuddy
      combat lines and game results in the log) with the overlay staying override-redirect: no
      "overlay turned into a tiled window" report since the WM_MOUSEACTIVATE fix.
- [x] Background hide/show with the real game (part of the 087341a5 confirmation, session 6).
- [x] Battle.net float rule: login window 362x693 and main window 1000x1150 both floating and centred
      (compositor event log, session 8, 2026-09-12 19:26 and 2026-09-13 02:36).
- [x] A full match with HearthMirror reads: the session-7 Battlegrounds hour ran BobsBuddy on every
      combat (needs board reads) and recorded results. `ScryInitializationException` /
      `ScryMemoryAccessException` bursts appear only at login and at game exit and are harmless.
- [x] Game opens floating at the lone-tile geometry and stays there: 12,38 1896x1150 for 45 s after
      the window opened, no Wine drift (session 8, 2026-09-13 03:06).
- [x] Overlay pinned on map and drawn over the game in the Battlegrounds lobby without any user
      action; HDT's main window covered by the game (screenshot, session 8, 2026-09-13 03:07).
- [x] Workspace switch away and back: overlay unpinned and parked on the game's workspace while
      workspaces 1 and 3 were active, pinned again on return (session 8, 2026-09-13 03:07:31-35).
- [x] Game killed while HDT runs: clean unhook, no warnings, HDT keeps running (session 8, 18:28).

### Missing (steps, and what to look for)

- [ ] **Game restart while HDT keeps running.** Close or kill Hearthstone, launch it again from
      Battle.net without restarting HDT. Expect a second `Game window set as the overlay owner` line
      in `hdt_log.txt`, the game back at the tile geometry, and the overlay visible over it.
      Also quit **Battle.net** and start it again from the menu (now `hdt-launch-battlenet`): there
      must be no `ScryInitializationException` flood after the new game's `Hidden -> Visible` line and
      Battlegrounds hovers/tabs must work. Before `hdt-wineserver` this failed every time (logs of
      2026-09-17 and 2026-09-19: tens of thousands of Scry errors after a Battle.net relaunch; the
      Battle.net-kept-open restarts of 2026-09-12 worked). Cause and fix: `linux/README.md`,
      "One wineserver outside the sandbox". Verified with test programs in the real prefix, not yet
      with the game.
- [ ] **HDT restart while the game keeps running.** Quit HDT (or kill it), start it again with the game
      open. Expect `Overlay Hidden -> Visible`, the owner line, the overlay pinned and visible.
- [ ] **Super+F with the pinned overlay.** With the game focused press Super+F, play a few seconds,
      press Super+F again. Expect the overlay drawn over the fullscreen game both ways
      (`hyprctl clients -j`: overlay `pinned` true while on the game's workspace) and back over the
      windowed game; no `Overlay ... -> Hidden` in the log.
- [ ] **In-game resolution change.** Options > Graphics, pick another resolution, then back. Expect the
      game to stay inside the screen (the placement re-check runs only for 30 s after open, so a
      later change may leave it offset by Wine's phantom frame: note the position if so).
- [ ] **Fresh `install.sh` after `omarchy refresh hyprland`.** Run `omarchy refresh hyprland`
      (rewrites `~/.config/hypr/hyprland.lua`), then `linux/install.sh`. Expect exactly one
      `hypr.hearthstone-deck-tracker` require line appended, a `.bak.*` backup next to it,
      `hyprctl configerrors` clean, and the rules active on the next game launch.
- [ ] **Classic-syntax rules** in `linux/README.md`: on a Hyprland with a `hyprland.conf` (no Lua),
      paste the four `windowrule` lines; expect the main window and Battle.net floating and the game
      floating. The placement and overlay handlers do not exist there (documented).
- [ ] **Multi-monitor and DPI scaling.** With a second monitor: launch the game on each monitor;
      expect the tile geometry of that monitor (`tile_box` uses the game's monitor) and the overlay
      following it. With `monitor` scale 1.25 or 1.5: expect the overlay aligned with the game
      (`Wine.AvoidFullScreenHeight` and `tile_box` both divide by scale) and the tabs clickable.
- [ ] **Battlegrounds tabs at the 1299x899 pop-out size.** Known limit: no `ToggleTab` logged even
      with the X raise, so the cause is HDT's own layout or hit testing at that scale. User accepts it.

## D. Tests and CI

- [x] `Wine.OverrideDetection` test hook; `HDTTests/Utility/WineTests.cs` covers `ClampToMonitor`
      and the detection override. (`bf9dc691`)
- [x] shellcheck, the install smoke test and a shim compile run in `linux-build`; HDTTests is
      compiled there. (`d6989bd3`)
- [x] `windows-build.yml` restores upstream's build + MSTest steps (HearthWatcher.Test, HDTTests).
      First run on GitHub (2026-09-12, `770cfe53` on `omarchy`): build succeeded, 21 + 306 tests
      passed, 3m26s. `linux-build` passed too (build 1m51s, scripts 17s). (`d6989bd3`)
- [x] `linux/tests/run-tests-wine.sh` runs the MSTest suites inside the Wine prefix with
      vstest.console (Microsoft.TestPlatform downloaded once to the cache). Session 6: the 8
      WineTests passed there (`/Tests:WineTests`); the full suites have not been run this way yet.

## E. Docs

- [x] `linux/README.md` intro no longer claims that no window-manager rules are needed.
- [x] `linux/README.md` "Known issues" and the "Overlay buttons and X stacking" section (`b6263a0c`,
      session hdt-linux-fe).
- [x] Project README section 0, status table, section 2f and bench gotchas (session hdt-linux-fe,
      not in git: `~/Projects/hdt-linux/README.md`).
- [x] Supported target stated in the `linux/README.md` intro: Omarchy / Hyprland / XWayland via
      umu + GE-Proton; X11-driver gate explained.
- [x] `install.sh` environment variables, `VERSION`, marker and `--uninstall` documented; new
      "Development: tests, CI, hardening status" section.
