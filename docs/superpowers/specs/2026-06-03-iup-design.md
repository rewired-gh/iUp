# iUp Design

macOS menu-bar utility that keeps the Mac awake, simulates activity when idle, auto-pauses on prolonged idle, and provides a simulated lock screen with display dimming. Inspired by Amphetamine (awake + jiggle) and Lockpaw (lock overlay). Reference source studied: `lockpaw/` and `Jiggler/`.

## Scope

Full spec, all subsystems in one design. Implementation may be phased by the plan.

- Awake (keep-awake assertions)
- Activity simulation (mouse jiggle)
- Temp-pause (auto-pause the awake session on idle, auto/manual resume)
- Lock (simulated lock overlay)
- Display control (brightness/external displays while locked)
- Awake-session orchestration
- Menu bar + settings UI
- System integration (login item, dock hiding, accessibility, global hotkeys)

## Distribution & constraints

- **Direct / notarized** (Developer ID, outside App Store). **Not sandboxed.** Private APIs permitted.
- Requires **Accessibility** permission for event taps (monitoring, input blocking, jiggle).
- `LSUIElement` accessory app: no dock icon, menu-bar only.
- Target: macOS 26.5, Swift. Bundle id `moe.rewired.iUp`.
- Remove the SwiftData/`Item.swift`/`ContentView` template. Config persists in `UserDefaults` via a typed `Settings` wrapper.

## Variable naming (important)

Each user story owns **independent** timing variables. The same letter in different stories is a different value with its own default and its own settings control.

- Jiggle: `T_jiggle`, `U_jiggle`, `V_jiggle`
- TempPause: `T_pause`
- Display-dim while locked: `T_dim`

## Per-feature independence (hard requirement)

Every feature has its **own enable toggle** and its **own independent configuration** (thresholds, options), persisted separately in `Settings`. No feature's config is shared with or derived from another. Turning one off never disables another.

| Feature | Independent on/off | Independent config |
|---|---|---|
| Awake | master toggle | + each assertion toggles independently: display-on, system-sleep, network-on |
| Jiggle | toggle | `T_jiggle`, `U_jiggle`, `V_jiggle` |
| TempPause | toggle | `T_pause` |
| Lock | toggle (feature available/unavailable) | unlock hotkey, burn-in interval, auth requirement |
| Display control | toggle | `T_dim`; internal-dim and external-off each toggle independently |
| Hotkeys | per-hotkey toggle | each global hotkey configurable/disable-able |
| App options | each independent | launch-at-login, hide-dock, auto-start-session |

**Interaction with the session (no hidden coupling):** the session activates Awake / Jiggle / TempPause **only if that feature's own toggle is on**. A feature switched off is never activated, even inside an active session. Awake, Jiggle, and TempPause may each be on or off in any combination. Lock and Display control are fully independent of the session and of each other (Lock works with Display control off; Display control only acts while locked but is its own toggle).

## Architecture

`@main` SwiftUI `App` with `NSApplicationDelegateAdaptor`. AppKit owns the status item, overlay windows, and event taps. SwiftUI used for settings + lock-screen content.

### Layers

**`ActivityMonitor` — single source of truth for the activity clock.**
- Listen-only `CGEventTap` on a dedicated background thread with its own run loop (Lockpaw `HotkeyManager` pattern — avoids the LSUIElement main-run-loop activation issue).
- On any **real** input event, set `lastRealInputDate = now` and publish `.userBecameActive`.
- Ignores synthetic events: events posted by `JiggleController` are tagged `CGEventSetIntegerValueField(event, .eventSourceUserData, iUpSyntheticMagic)`. The monitor skips any event whose `.eventSourceUserData == iUpSyntheticMagic`. **This is the single place that enforces 「模拟的不算」 (simulated input does not count) across the entire app.**
- A 0.25s `DispatchSourceTimer` (Jiggler cadence) computes `idle = now - lastRealInputDate` and notifies subscribers each tick.
- `t0 = lastRealInputDate`. All thresholds compare against `idle`.
- Clock + event-source are injectable so logic is unit-testable without a real tap.

**Feature controllers** — each owns its own enable toggle and threshold overrides, subscribes to the monitor:

- **`AwakeController`** — `IOPMAssertion`s, each independently toggleable:
  - Display on (`kIOPMAssertionTypePreventUserIdleDisplaySleep`)
  - System sleep (`PreventUserIdleSystemSleep` / `PreventSystemSleep`)
  - Network on (`NetworkClientActive`, best-effort; lid-close still sleeps)
  - Periodic `IOPMAssertionDeclareUserActivity` refresh (Lockpaw `SleepPreventer` + Jiggler pattern).
- **`JiggleController`** — when `idle ≥ T_jiggle`, start jiggling; every `U_jiggle` post a 0.5s continuous synthetic move burst (multiple scheduled `CGEventCreateMouseEvent` → `CGEventPost(kCGHIDEventTap)`, suppression interval 0, drift-limited and avoid-point logic from Jiggler). Stop when `idle ≥ T_jiggle + V_jiggle`. All posted events tagged with `iUpSyntheticMagic` so they never reset t0.
- **`TempPauseController`** — policy inside the session (see SessionController). When enabled and `idle ≥ T_pause`, pause the session.
- **`LockController`** — Lockpaw state machine + overlay (see Lock section).
- **`DisplayController`** — brightness / external-display control while locked (see Display section).

**`SessionController` — owns the awake session.**
- States: `off → active ⇄ pausedByIdle`.
- `active`: activates `AwakeController` + `JiggleController`.
- `pausedByIdle` (entered by TempPause policy when `idle ≥ T_pause`, only if TempPause enabled): deactivates **both** Awake (release all assertions) and Jiggle. The Mac is then free to sleep naturally. The pause flag is held in memory and survives system sleep (the app keeps running).
- **Resume** (`pausedByIdle → active`) via any of: real user input (`.userBecameActive`), system wake (`NSWorkspace.didWakeNotification` / `screensDidWake`), or **manual "Resume session"** menu button (fallback if auto-resume fails). Resume reactivates Awake + Jiggle and resets t0.
- If TempPause disabled, session stays `active` regardless of idle.

**`MenuBarController`** — `NSStatusItem` dropdown bound to session state:
- `off` → "Start session"
- `active` → "Stop session"
- `pausedByIdle` → "Resume session" (manual) + "Stop session"
- Shows a current-state label (e.g. "Paused (idle)") so a failed auto-resume is visible, not silent.
- Plus: "Lock" (enter lock mode), "Settings…", "Quit".

**System glue:**
- `LoginItem` — `SMAppService` register/unregister for launch-at-login.
- `AccessibilityChecker` — `AXIsProcessTrusted` / prompt / open Settings pane (Lockpaw).
- `HotkeyManager` — global hotkeys (session toggle, lock/unlock) via listen-only tap on dedicated thread (Lockpaw). Default lock hotkey `⌃⌥⌘L`.
- `Settings` — typed `UserDefaults` wrapper; per-feature enable flags + thresholds; app options (launch-at-login, hide dock, auto-start session on launch).

## Data flow & timing

`ActivityMonitor` tap → real event → `lastRealInputDate = now`, publish `.userBecameActive`. 0.25s timer → compute `idle`, notify controllers. Each controller compares `idle` to **its own** thresholds:

| Feature | Variable | Condition | Action |
|---|---|---|---|
| Jiggle | `T_jiggle` | `idle ≥ T_jiggle` | start; every `U_jiggle` post 0.5s synthetic move burst |
| Jiggle | `V_jiggle` | `idle ≥ T_jiggle + V_jiggle` | stop jiggling |
| TempPause | `T_pause` | `idle ≥ T_pause` | session → `pausedByIdle` (deactivate Awake + Jiggle) |
| Display (locked) | `T_dim` | `idle ≥ T_dim` | internal brightness → 0 |
| all | — | real input / wake | reset to t0; resume session if `pausedByIdle`; restore brightness; stop jiggle |

Synthetic moves are tagged → do not touch `lastRealInputDate` → jiggle never resets itself.

**Defaults (all configurable, all independent):** `T_jiggle = 60s`, `U_jiggle = 30s`, `V_jiggle = 300s`, `T_pause = 60s`, `T_dim = 60s`.

## Lock

Lockpaw mechanism, maximally aggressive (within userland limits — Force-Quit and power button always escape).

- Borderless `NSWindow` per `NSScreen` at `CGShieldingWindowLevel`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`. Black mask.
- `InputBlocker`: `cgSessionEventTap` (`.headInsertEventTap`, `.defaultTap`) swallowing keyDown/keyUp/flagsChanged/scrollWheel/tablet events; lets the unlock hotkey through; re-enables on `tapDisabledByTimeout/UserInput`.
- Recreate windows on `didChangeScreenParametersNotification` (debounced). Re-arm tap on `screensDidWake` / `sessionDidBecomeActive`.
- Content: dim-grey thin custom text + unlock button.
- **Burn-in prevention:** a timer repositions text and unlock button every N seconds so every screen position has equal coverage probability. Applies to the button too.
- **Unlock:** Touch ID / macOS password via `LAContext` `.deviceOwnerAuthentication` (Lockpaw `Authenticator`), triggered by on-screen button; or via unlock hotkey (`⌃⌥⌘L`).
- **State machine:** `unlocked → locking → locked → unlocking → unlocked`. Force-unlock on accessibility revoked or input-blocker failure. Rate-limit auth after repeated failures.
- Independent of the awake session — lock works whether the session is on or off.

## Display control (while locked)

Guarded: if **no internal display**, this feature is disabled (lock still works). Each sub-behavior independently toggleable.

- On lock (if internal display present): save current internal brightness, set internal brightness → 0; turn external displays off (best-effort).
- Real user input while locked: restore internal brightness only (external stays off).
- Re-idle while locked: when `idle ≥ T_dim`, internal brightness → 0 again.
- On unlock: restore internal brightness and re-enable external displays.
- **Brightness API:** `DisplayServices` private framework (`DisplayServicesSetBrightness` / `DisplayServicesGetBrightness`) — permitted under direct/notarized distribution. Fallback: `IODisplaySetFloatParameter`. Save/restore prior value.
- **External off:** best-effort via `CGConfigureDisplayMirrorOfDisplay` / disable. PRD permits skipping if technically infeasible — feature degrades to a no-op gracefully rather than failing the lock.

## Error handling

- **No Accessibility permission** → taps/jiggle/lock fail. `AccessibilityChecker.promptIfNeeded`; menu shows a degraded indicator; block entering lock. Accessibility revoked mid-lock → force-unlock.
- **Tap disabled by timeout/userInput** → re-enable inside the callback.
- **IOPMAssertion create fails** → log, surface in menu, do not crash.
- **Brightness API fails** → skip dimming; lock proceeds.
- **No screens / no internal display** → guard; disable dependent features.
- **Session loss while locked** (`sessionDidResignActive`) → cancel pending auth, re-block input on return (Lockpaw).
- **Auto-resume failure after sleep** → manual "Resume session" button; state label makes the stuck state visible.

## Testing

Existing Lockpaw test target shows the pattern. Unit-test pure logic with injected clock + event-source (no real taps):

- `ActivityMonitor` idle/threshold math and synthetic-event filtering.
- `SessionController` state transitions (`off`/`active`/`pausedByIdle`, pause/resume rules, TempPause-disabled path).
- `LockController` `LockState` transition validity, force-unlock paths, auth rate-limiting.
- `JiggleController` drift-limiting / avoid-point / start-stop thresholds.
- Burn-in position distribution (equal coverage).
- `Settings` defaults + persistence round-trip.

Tap, overlay, brightness, and external-display control are thin side-effect shells — manually verified (global input + display state can't be reliably unit-tested).

## Components summary

| Unit | Responsibility | Depends on |
|---|---|---|
| `ActivityMonitor` | real-input clock, synthetic filtering | CGEventTap |
| `AwakeController` | power assertions | IOKit pwr_mgt |
| `JiggleController` | synthetic mouse movement | CGEvent, ActivityMonitor |
| `SessionController` | awake-session state + TempPause policy | Awake, Jiggle, ActivityMonitor |
| `LockController` | lock state machine | OverlayWindowManager, InputBlocker, Authenticator |
| `OverlayWindowManager` | per-screen overlay windows | AppKit |
| `InputBlocker` | swallow input while locked | CGEventTap |
| `Authenticator` | Touch ID / password | LocalAuthentication |
| `DisplayController` | brightness / external displays | DisplayServices (private), IOKit |
| `MenuBarController` | status item + menu | AppKit, SessionController, LockController |
| `HotkeyManager` | global hotkeys | CGEventTap |
| `LoginItem` | launch at login | SMAppService |
| `AccessibilityChecker` | permission state/prompt | ApplicationServices |
| `Settings` | typed config persistence | UserDefaults |
