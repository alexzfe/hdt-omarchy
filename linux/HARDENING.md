# Production-hardening checklist (branch `production-hardening`, merges into `omarchy`)

Review of the fork's additions as of `cfd18843` plus the uncommitted session-5 diagnostics.
Tick items here as they land; keep each fix a small commit so `omarchy` can take them one by one.

## A. Code (HDT source, all Wine-gated)

- [ ] **Gate matches the assumptions.** `Wine.IsWine` gates behaviour that only holds for Wine's X11
      driver under Hyprland (override-redirect always on top, pinned pass, WM_TRANSIENT_FOR raise).
      Add a `Wine.IsX11` (or Hyprland) check for those paths, or document Hyprland/Omarchy as the only
      supported target. (`Windows/OverlayWindow.Update.cs` SetTopmost/SendToBack, `Utility/Wine.cs` SetOwner)
- [ ] **One place computes overlay opacity.** `ShowOverlay`, `Update()` and the Wine "Behind" path all
      write `Opacity`; `Update()` runs outside the tick on settings changes and game reset, so a hidden
      overlay can flash for up to a tick. Fold the Wine behind-state into the same effective-opacity
      computation. (`Windows/OverlayWindow.Update.cs` UpdateVisibility, `OverlayWindow.xaml.cs` ShowOverlay)
- [ ] **Full-screen clamp per monitor.** `Wine.AvoidFullScreenHeight` only knows the primary monitor,
      so a fullscreen game on another monitor or at negative coordinates becomes a managed window.
      Use the monitor containing the game rect. (`Utility/Wine.cs`)
- [ ] **Bounded focus hand-back.** The poller calls `BringHsToForeground` every 250 ms without a cap
      while the overlay is active and the game rect differs. Add a retry cap or backoff.
      (`Windows/OverlayWindow.xaml.cs` StartGameRectPolling)
- [ ] **Diagnostic logging at Debug.** `Overlay rect set to`, `Game window moved to`, foreground
      descriptions and guides-tab lines are Info and fire on every move. Drop to Debug or rate-limit
      once the open issue is solved. (`OverlayWindow.xaml.cs`, `OverlayWindow.Update.cs`,
      `BattlegroundsGuidesTabsViewModel.cs`)
- [ ] **Decide the uncommitted session-5 experiments before merging.** `RaiseWithoutActivating`
      (a `SetWindowPos` on every game move and on every click-through toggle) contradicts the
      SetTopmost/SendToBack no-op rationale, and the 400 ms `DebounceWineBackground` targets a theory
      the 15:02 real-game test disproved for the Comps issue. Keep only what the live test shows is
      needed, with a comment naming the evidence.
- [ ] **Game-window owner lifecycle.** `Wine.SetOwner` relies on Wine clearing a cross-process owner
      when the game window dies. Verify the game-crash case (overlay survives, owner cleared, re-own on
      restart). (`Windows/OverlayWindow.xaml.cs` HookGameWindow/UnhookGameWindow)
- [ ] **csproj change is unconditional.** `ExecuteAsTool="false"` applies to Windows builds too,
      contradicting the "Windows build unchanged" claim. Make it `'$(OS)' != 'Windows_NT'`-conditional
      or restore a Windows build job that proves it is harmless. (`Hearthstone Deck Tracker.csproj`)

## B. Install and launcher (`linux/`)

- [ ] **Guard `rsync --delete`.** Refuse to sync into a non-empty `HDT_INSTALL_DIR` that does not
      contain a marker file from a previous install. (`install.sh`)
- [ ] **Check prerequisites up front.** rsync, curl, unzip, git, X11 headers (and 32-bit libX11 as
      optional) in `install.sh`; `umu-run` in `launch-hdt.in` with a clear error.
- [ ] **Hyprland step only on Omarchy.** Detect Omarchy's `default.hypr.require_optional` (or the
      Omarchy config dir) rather than any `hyprland.lua`; print what will be appended; make the reload
      opt-out. Document that `omarchy refresh hyprland` removes the line and re-running install restores it.
- [ ] **Shim scope and noise.** Only preload when the 32-bit build exists too, or point `LD_PRELOAD`
      at the 64-bit path when it does not, so 32-bit helpers stop printing ld.so errors. Note in the
      README that every Wine process under the launcher (Hearthstone included) gets the tolerant handler.
      Make the handler-discovery sequence in `hdt-xerror-shim.c` idempotent under concurrent first calls.
- [ ] **Version stamp, uninstall.** Write the built commit to `$HDT_INSTALL_DIR/VERSION` and log it at
      startup; add `install.sh --uninstall` (app dir, launcher, desktop entry, icon, shim, Hyprland file
      and require line).

## C. Verification (real game, record the result in `linux/README.md`)

- [x] Super+O (pinned game), moving, resizing (user, end of session 4)
- [x] Fullscreen -> windowed (user, session 5, 15:02)
- [ ] Battlegrounds Comps/Minions tabs at the 1300x900 pop-out size (still broken; X click routing is
      the leading theory, see project README section 2e.1)
- [ ] Background hide/show with the real game
- [ ] Overlay stays override-redirect after a real click on an overlay button
- [ ] Battle.net float rule
- [ ] Fresh `install.sh` on a clean Omarchy config (one appended line, backup, `configerrors` clean)
- [ ] Classic-syntax rules in `linux/README.md`
- [ ] Multi-monitor and DPI scaling
- [ ] A full match with HearthMirror reads (`ScryMemoryAccessException` on login still appears)

## D. Tests and CI

- [ ] Make `Wine.IsWine` injectable (e.g. `Wine.ForceForTests`) and unit-test `AvoidFullScreenHeight`,
      `IsForegroundOwnedBy` and the debounce in `HDTTests`.
- [ ] `shellcheck` on `linux/*.sh` and `launch-hdt.in` in the `linux-build` workflow.
- [ ] Install smoke test in a temp `HOME` (build skipped, fake `bin/` tree) checking the files written
      and the Hyprland append being idempotent.
- [ ] Restore a Windows build-and-test job (the upstream `main.yml` test step) so the 306 existing
      MSTest tests and the Windows build still run on the fork.

## E. Docs

- [ ] `linux/README.md` intro says no window-manager rules are needed; four are installed. Reword.
- [ ] `linux/README.md` "Known issues" still lists fullscreen exit as open; it is fixed as of session 5.
- [ ] Project README section 0 status table still says tracking and background hide are unconfirmed
      with the real game; reconcile with the session-4/5 results.
- [ ] State the supported target explicitly: Omarchy / Hyprland / XWayland via umu + GE-Proton.
