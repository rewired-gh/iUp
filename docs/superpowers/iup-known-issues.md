# iUp — Known Issues / Follow-ups

Non-blocking items surfaced during code review. Implementation is functional and all unit tests pass; these are quality/robustness improvements for a later pass.

## Fixed (2026-06-04 reliability/quality pass)
- Accessibility revocation mid-run now recovers: taps detect a failed re-enable and post `.iUpInputServicesStalled`; `AppDelegate` tears down and re-acquires (re-polls until re-granted).
- Login-item failure no longer swallowed: `SettingsModel.launchAtLogin` only persists on successful `SMAppService` registration and reverts the toggle otherwise; startup syncs `Settings.launchAtLogin` to the real `SMAppService` status.
- `DisplayController` single `isDimmed` state — `lockedTick` no longer floods brightness changes; dim/restore happen once per idle cycle.
- `InputBlocker` exact unlock-modifier match; named Escape constant.
- `HotkeyManager` key codes are `let` (no tap-thread data race); exact modifier match already present.
- `BrightnessService` `dlclose`s its handles; brightness key codes named.
- `SettingsModel` is `@MainActor`.
- Magic numbers extracted (brightness keys, Esc, jiggle burst params).

## Fixed (2026-06-04 — pause/dimming/crash pass)
- **TempPause never fired**: idle features are gated behind Accessibility (`inputMonitoringActive`). With an ad-hoc signature the grant is keyed to the binary's cdhash, so every `make build` silently invalidated it → tap never started → no pause/jiggle/dim. Added a menu warning ("⚠︎ Grant Accessibility…") so the missing permission is visible instead of failing silently.
- **Lock→unlock→lock crash** (`EXC_BAD_ACCESS` in `objc_release`): overlay `NSWindow`s had `isReleasedWhenClosed = true` while ARC also retained them in `windows`; `close()` over-released → crash on a later cycle. Now set `isReleasedWhenClosed = false`.
- Removed redundant `jiggle.stopAfter` (jiggle now stops only on input/pause) and `display.dimIdle` re-dim cycle (dim once on lock, restore once on unlock; brighten for auth, re-dim on auth fail).
- Brightness restore now targets a fixed 50% (the prior level is unreadable on macOS 26) instead of stepping to max.

## Dev gotcha — Accessibility grant dies on every rebuild
Ad-hoc signing (no Developer ID / `0 valid identities`) means TCC binds Accessibility to the cdhash. **Every `make build` produces a new cdhash and drops the grant** — you must re-grant after each rebuild (remove + re-add iUp in System Settings ▸ Privacy & Security ▸ Accessibility). The Makefile's stable *path* does not help here; only a stable signing identity would. The menu warning surfaces when the current build isn't trusted.

## Still open (by design or low-value)
- **Backlight can't reach true 0**: the brightness hardware keys bottom out at the panel's hardware minimum (a dim glow, ~"1%"), not off. The absolute-set private APIs (DisplayServices/CoreDisplay set 0) are no-ops on macOS 26, so true 0 is unreachable for a third-party app. The black lock overlay covers the screen regardless; only residual backlight glow remains.
- **Brightness manual-override**: while locked-and-dimmed, if the user presses a brightness key (system-defined events aren't blocked), iUp can't detect it (no reliable brightness read on macOS 26), so unlock restores toward the saved level and may override the user's manual change. Best-effort by design.
- **`InputObservationTap`/`HotkeyManager` run-loop reference** is written on the tap thread and read on main during teardown. A `cancelled`/`isRunning` guard was added; the residual window is benign because teardown only happens on stall-recovery or app exit. A lingering empty run loop after re-register is possible (harmless; tap disabled).
- **Hotkeys not user-configurable**: hardcoded ⌃⌥⌘L (lock) / ⌃⌥⌘S (session). No rebinding UI yet.
- **NSWorkspace/NotificationCenter observer tokens discarded** in `AppDelegate`: fine for an immortal delegate; prevents clean teardown.

## Manual verification still required
The side-effecting units (event taps, overlay windows, brightness control, Touch ID, login item) are unit-test-light by design. Run the manual checklist in `docs/superpowers/plans/2026-06-04-iup-implementation.md` (Task 21, Step 4) on real hardware after granting Accessibility permission.
