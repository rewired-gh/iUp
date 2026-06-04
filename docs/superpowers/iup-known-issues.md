# iUp — Known Issues / Follow-ups

Non-blocking items surfaced during code review. Implementation is functional and all unit tests pass; these are quality/robustness improvements for a later pass.

## From reliability-pass review (2026-06-04, still open)
- **Accessibility revocation mid-run isn't recovered** (`AppDelegate.startInputServicesIfPossible` guards `!inputMonitoringActive`): if the user revokes Accessibility while running, taps silently stop and there's no path back without relaunch. Fix: have `InputObservationTap`/`HotkeyManager` detect a failed tap re-enable and post a notification so `AppDelegate` resets `inputMonitoringActive` and re-polls.
- **`InputObservationTap` uses an unretained `self` pointer for the tap callback** — `CFRunLoopStop` is async, so one callback could fire after dealloc. In practice the tap lives for the whole app, so it's latent. Fix: pass a retained pointer and release in `stop()`, or guard with a cancelled flag.
- **`BrightnessService` doesn't `dlclose` its framework handles** (process-lifetime, benign).
- **Brightness manual-override**: while locked-and-dimmed, if the user presses a brightness key (system-defined events aren't blocked), iUp can't detect it (no reliable brightness read on macOS 26), so unlock restores toward the saved level and may override the user's manual change. Best-effort by design.
- **Magic numbers**: brightness key codes (2/3), Esc (53), jiggle step count/sleep, lock panel size — could be named constants.

## Important
- **Login-item failure is swallowed** (`iUp/UI/SettingsView.swift`, `SettingsModel.launchAtLogin`): the setter uses `try?` and persists the preference even if `SMAppService.register()` throws, so the toggle can show "On" while the OS login item is not registered. Fix: only persist on success, surface the error in the UI, and reconcile `Settings.launchAtLogin` against `SMAppService.mainApp.status` at startup.
- **Thread-start data race on the run-loop reference** (`HotkeyManager.tapRunLoop`, `InputObservationTap.runLoop`): the property is written inside the spawned thread and read from the calling thread in `unregister()`/`deinit` without synchronization. In practice these objects are created once at launch and torn down at process exit, so the race effectively never fires (this mirrors the lockpaw reference pattern). Fix if teardown ever becomes dynamic: synchronize or signal the run loop is ready before allowing `unregister()`.

## Minor
- **`dlopen` handle not retained** (`BrightnessService.init`): handle is discarded; framework stays resident via dyld so this is benign, but non-idiomatic.
- **Double `getInternalBrightness()` in `DisplayController.didLock()`**: `isAvailable` then save — tiny TOCTOU window on hot-unplug. Collapse into a single read.
- **NSWorkspace/NotificationCenter observer tokens discarded** (`AppDelegate`): fine for an immortal delegate; prevents clean teardown.
- **Hotkeys are not user-configurable**: key codes/modifiers are hardcoded defaults (⌃⌥⌘L lock, ⌃⌥⌘S session). Spec mentioned configurability; no settings UI for rebinding was built. Add later if desired.

## Manual verification still required
The side-effecting units (event taps, overlay windows, brightness control, Touch ID, login item) are unit-test-light by design. Run the manual checklist in `docs/superpowers/plans/2026-06-04-iup-implementation.md` (Task 21, Step 4) on real hardware after granting Accessibility permission.
