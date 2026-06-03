# iUp — Known Issues / Follow-ups

Non-blocking items surfaced during final code review (2026-06-04). Implementation is functional and all unit tests pass; these are quality/robustness improvements for a later pass.

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
