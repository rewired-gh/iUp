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

## Still open (by design or low-value)
- **Brightness manual-override**: while locked-and-dimmed, if the user presses a brightness key (system-defined events aren't blocked), iUp can't detect it (no reliable brightness read on macOS 26), so unlock restores toward the saved level and may override the user's manual change. Best-effort by design.
- **`InputObservationTap`/`HotkeyManager` run-loop reference** is written on the tap thread and read on main during teardown. A `cancelled`/`isRunning` guard was added; the residual window is benign because teardown only happens on stall-recovery or app exit. A lingering empty run loop after re-register is possible (harmless; tap disabled).
- **Hotkeys not user-configurable**: hardcoded ⌃⌥⌘L (lock) / ⌃⌥⌘S (session). No rebinding UI yet.
- **NSWorkspace/NotificationCenter observer tokens discarded** in `AppDelegate`: fine for an immortal delegate; prevents clean teardown.

## Manual verification still required
The side-effecting units (event taps, overlay windows, brightness control, Touch ID, login item) are unit-test-light by design. Run the manual checklist in `docs/superpowers/plans/2026-06-04-iup-implementation.md` (Task 21, Step 4) on real hardware after granting Accessibility permission.
