# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

iUp — a macOS menu-bar utility (Amphetamine + Lockpaw style): keeps the Mac awake, simulates cursor activity when idle, auto-pauses on prolonged idle, and provides a simulated lock screen with display dimming. Menu-bar accessory app (`LSUIElement`), non-sandboxed, distributed Developer ID / notarized. Target macOS 26.5, Swift 5, bundle id `moe.rewired.iUp`.

Reference source for the hard parts lives outside this repo at `../lockpaw/` (lock overlay, input blocking, Touch ID, hotkeys) and `../Jiggler/` (cursor jiggle, idle). When touching those subsystems, read the reference rather than guessing — the platform behavior is subtle.

## Commands

Use the `Makefile` (not Xcode ⌘R) — builds go to per-config dirs: `./build/Debug/iUp.app` / `./build/Release/iUp.app`.

- `make run` — build (Debug) and launch a fresh instance
- `make build` — build only (Debug)
- `make release` — optimized Release artifact: -O whole-module, thin LTO, cross-module optimization, dead-code + symbol stripping, no NS assertions
- `make run-release` — build Release and launch
- `make test` — full unit suite
- `make stop` — quit a running instance (safety net if the lock screen traps you)
- `make accessibility` / `make reveal` — open the Accessibility pane / reveal the app to grant permission
- `make signing-status` — shows whether builds use the dev identity or ad-hoc

**Accessibility grant persistence is keyed to the signing identity, not the path.** TCC binds the grant to the code-signing Designated Requirement; ad-hoc builds get a fresh cdhash each rebuild → grant silently dies → idle features (pause/jiggle/dim) stop working with no error. The Makefile signs with your Apple Development team (derived from the installed cert, `-allowProvisioningUpdates`) when a valid cert exists, else falls back to ad-hoc. After the first signed build, grant Accessibility once and it persists. The menu shows a "⚠︎ Grant Accessibility…" item whenever the current build isn't trusted.

Test commands directly:
- All tests: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests`
- One suite: append `/SuiteName`, e.g. `-only-testing:iUpTests/SessionControllerTests`
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest.

The project uses **`PBXFileSystemSynchronizedRootGroup`**: any `.swift` added under `iUp/` or `iUpTests/` joins the target automatically — do NOT edit `project.pbxproj` to register source files. Info.plist keys are set as `INFOPLIST_KEY_*` build settings (`GENERATE_INFOPLIST_FILE = YES`; no standalone Info.plist).

There is no separate linter/formatter configured — build warnings are the lint signal. Commit messages follow Conventional Commits (`fix:`, `feat:`, `docs:`, `chore:`).

Note: `xcodebuild` is authoritative for build/test status. In-editor SourceKit often shows stale "Cannot find type" errors across files in this project — ignore those if `xcodebuild` succeeds.

Debugging a running build: `defaults read moe.rewired.iUp` inspects persisted settings; for the unified log use `/usr/bin/log` (the bare `log` is shadowed by a shell function) with `--info --debug` (those levels are hidden otherwise), e.g. `/usr/bin/log show --last 2m --info --debug --predicate 'subsystem == "moe.rewired.iUp"'`.

## Architecture

`iUpApp` (`@main`) hosts only an empty `SwiftUI.Settings` scene and an `AppDelegate` adaptor. `AppDelegate` is the composition root: it builds every controller, wires them, owns the timers/observers, and is the only `@MainActor` glue layer.

**The spine is `Core/ActivityMonitor`** — the single source of truth for the user-idle clock. It exposes `idle` (seconds since last *real* input) driven by a monotonic `Clock` (`systemUptime`, not wall-clock — robust over long uptime / clock changes). Every timing feature reads its clock from here. Two callbacks (`onUserBecameActive`, `onTick`) fan out to controllers. A 0.25s `DispatchSourceTimer` in `AppDelegate` calls `tick()`.

**「Simulated input does not count」 is enforced in exactly one place.** Synthetic cursor events posted by `Jiggle/CGMovePoster` are tagged via `Core/SyntheticTag` (`eventSourceUserData == iUpSyntheticMagic`). `System/InputObservationTap` (listen-only session tap) reads that tag and passes `isSynthetic` to `ActivityMonitor.record`, which ignores tagged events. Do not add another idle/activity source — route everything through `ActivityMonitor`.

**Feature controllers** (each its own enable toggle + thresholds in `Core/Settings`; no shared config — per-feature independence is a hard requirement):
- `Features/Awake/AwakeController` — `IOPMAssertion`s; display/system/network each toggle independently. `reapply()` re-syncs assertions live when settings change.
- `Features/Jiggle/` — `JiggleMath` is pure, deterministic (seeded RNG), coordinate-agnostic and unit-tested; `JiggleController` decides start/stop/burst from idle; `CGMovePoster` posts the real events **in global CG/display coordinates** (`CGEvent(source:nil).location` + `CGDisplayBounds`) — mixing in Cocoa `NSScreen.frame` coords breaks jiggle (different origin).
- `Features/Session/SessionController` — owns the awake "session" state machine (`off → active ⇄ pausedByIdle`); TempPause policy releases everything at idle so the Mac may sleep, and resumes on input / system wake / manual menu action.
- `Features/Lock/` — `LockState` machine; `OverlayWindowManager` (per-screen black shield-level windows); `InputBlocker` (session tap swallowing input); `Authenticator` (Touch ID / password); `LockController` coordinates them.
- `Features/Display/DisplayController` — dims the built-in display while locked; single `isDimmed` flag (so the 0.25s tick can't re-issue the dim repeatedly). `BrightnessService` is best-effort: the private DisplayServices/CoreDisplay absolute-brightness APIs are no-ops for third-party apps on macOS 26, so it *also* simulates the brightness hardware key to actually move the backlight.

**System integration** (`System/`): `AccessibilityChecker`, `HotkeyManager` (global ⌃⌥⌘L lock / ⌃⌥⌘S session, listen-only tap on a dedicated thread), `InputObservationTap`, `LoginItem` (`SMAppService`). **UI** (`UI/`): `MenuBarController` (NSStatusItem), `SettingsView`/`SettingsModel`, `SettingsWindowController`.

### Cross-cutting things that bite

- **Accessibility-gated startup.** Event taps + hotkeys + jiggle need Accessibility. `AppDelegate.startInputServicesIfPossible()` prompts, then **polls (1.5s) + rechecks on `didBecomeActive`** so features start the moment permission is granted, no relaunch. Idle-driven logic is suppressed (`inputMonitoringActive`) until then, so a frozen clock can't false-trigger TempPause. Revocation mid-run is detected (`.iUpInputServicesStalled`) and re-acquired.
- **Lock unlock flow.** The overlay sits at `CGShieldingWindowLevel`. During authentication `LockController` lowers it to `.statusBar` (covers the menu bar but lets the Touch ID dialog show) and restores brightness — otherwise the auth dialog is hidden behind the black overlay and the user is trapped. There is a debug-only Esc force-unlock (gated by `Settings.debugMode`). A userland app cannot block the OS Force-Quit (⌘⌥⎋ held) or power button.
- **Live settings.** `SettingsModel.write` posts `.iUpSettingsChanged`; `AppDelegate.reconcileSettings()` re-applies to running features. Settings persist immediately via `UserDefaults`.
- **Name collision.** The app defines a `Settings` class; the SwiftUI `Settings` scene must be written fully-qualified as `SwiftUI.Settings`.
- **Lock screen colors** match Lockpaw: dim white on black (`.white.opacity(...)`), no bright/prominent controls.
- **Settings window chrome.** The SwiftUI `Settings` scene won't open from the accessory app's AppKit status menu (`showSettingsWindow:` is a no-op; don't toggle activation policy to `.regular` to force it — that adds a Dock icon). `SettingsWindowController` hosts the panes in its own `NSWindow`. Do NOT use a SwiftUI `TabView` for the tabs there: outside the `Settings` scene it renders the tab strip with wrong insets (mismatched background band, misaligned focus rings). Tabs are a native `NSToolbar` in `.preference` style; each pane is an isolated SwiftUI view keyed by the `SettingsPane` enum, swapped on toolbar selection. In grouped-Form rows, give numeric `TextField`s enough width that values don't wrap (wrapping grows row height) and center-align label vs control manually — `LabeledContent` baseline-aligns the label too high.

- **Debug-only UI.** `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG"` is set only in the Debug Xcode config. Use `#if DEBUG` to gate any UI or behavior that must not ship in Release (e.g. the Esc force-unlock toggle in `SettingsView`).
- **Release packaging.** `ditto -c -k --keepParent build/Release/iUp.app /tmp/iUp-vX.Y.Z.zip` preserves the code-signature for distribution. `gh auth login` is interactive (device-flow only — cannot be automated; user must open github.com/login/device with the one-time code).

Side-effecting units (event taps, overlay, brightness, auth, login item) are thin shells verified by build + manual run; pure logic (`ActivityMonitor`, `SessionController`, `JiggleMath`, `LockState`, `BurnIn`, `Awake`/`Display`/`Jiggle` controllers, `Settings`, `LoginItem`) is unit-tested with injected fakes/clock.

## Docs

Design spec, implementation plan, and open follow-ups live in `docs/superpowers/` (`specs/`, `plans/`, `iup-known-issues.md`). Read `iup-known-issues.md` before changing display/brightness or accessibility recovery — it records deliberate limitations (e.g. brightness manual-override can't be detected on macOS 26).
