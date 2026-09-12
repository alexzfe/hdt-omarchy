# Production-hardening checklist (branch `production-hardening`, merges into `omarchy`)

Review of the fork's additions as of `cfd18843` plus the session-5 diagnostics. Tick items as they
land; keep each fix a small commit so `omarchy` can take them one by one.

**Status (2026-09-12, session 6):** sections A, B, D and E are done except where noted; C needs the
user with the real game. Commits are listed next to each item. Everything on this
branch builds (`linux/build.sh Release`, `dotnet build HDTTests`), passes shellcheck and the install
smoke test. The Windows CI job has not run yet.

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
      a game crash should leave the overlay unowned, and the poller re-owns on the next game window.
      Documented in `Wine.SetOwner`; **not yet exercised** (kill Hearthstone while HDT runs, then
      restart it: expect `Game window changed, remapping the overlay under the new owner`).
- [x] **csproj change is conditional.** `ExecuteAsTool="$(HdtStringsResGenAsTool)"`, false only when
      `$(OS) != Windows_NT`. (`a9483ae5`)
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

## C. Verification (real game, record the result in `linux/README.md`)

- [x] Super+O (pinned game), moving, resizing (user, end of session 4)
- [x] Fullscreen -> windowed (user, session 5, 15:02)
- [x] Battlegrounds tabs at ordinary windowed sizes, e.g. 1541x1110 (user, session 5, 15:33, with the raise)
- [ ] Battlegrounds tabs at the 1299x899 pop-out size: still dead even with the raise (no `ToggleTab`
      logged), so the remaining limit is in HDT's own layout or hit testing at that scale, not X
      stacking. User accepts it for now.
- [ ] **This branch's HEAD with the real game.** The installed build at the time of writing is the
      session-5 15:27 build (raise, old gating). Install HEAD (`linux/install.sh`) and re-check:
      tabs at windowed size, Super+O, fullscreen both ways, background hide/show, and that the log
      shows `Wine X11 driver detected` and `hdt-omarchy build: ...`.
- [ ] Background hide/show with the real game (works in practice per session-5 logs, never
      recorded as a check)
- [ ] Overlay stays override-redirect after a real click on an overlay button
- [ ] Battle.net float rule
- [ ] Fresh `install.sh` on a clean Omarchy config (smoke test covers the logic; one real run after
      `omarchy refresh hyprland` still worth doing)
- [ ] Classic-syntax rules in `linux/README.md`
- [ ] Multi-monitor and DPI scaling
- [ ] A full match with HearthMirror reads (`ScryMemoryAccessException` on login still appears)
- [ ] Game-window owner lifecycle (see A)

## D. Tests and CI

- [x] `Wine.OverrideDetection` test hook; `HDTTests/Utility/WineTests.cs` covers `ClampToMonitor`
      and the detection override. (`bf9dc691`)
- [x] shellcheck, the install smoke test and a shim compile run in `linux-build`; HDTTests is
      compiled there. (`d6989bd3`)
- [x] `windows-build.yml` restores upstream's build + MSTest steps (HearthWatcher.Test, HDTTests).
      **Unverified until its first run on GitHub**: watch the Actions tab after the next push. (`d6989bd3`)
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
