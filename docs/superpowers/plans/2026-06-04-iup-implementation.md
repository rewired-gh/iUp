# iUp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build iUp, a macOS menu-bar utility that keeps the Mac awake, simulates activity when idle, auto-pauses on prolonged idle, and provides a simulated lock screen with display dimming.

**Architecture:** LSUIElement accessory app. A single `ActivityMonitor` owns the real-input clock (excluding synthetic events) and drives independent feature controllers (Awake, Jiggle, TempPause, Lock, Display). `SessionController` orchestrates the awake session. Each feature has its own enable toggle and config in `Settings`. Side-effecting units (event taps, overlay windows, brightness, menu) are thin shells around unit-tested logic.

**Tech Stack:** Swift, SwiftUI (`@main` + `NSApplicationDelegateAdaptor`), AppKit, IOKit (`IOPMAssertion`), CoreGraphics event taps, LocalAuthentication, SMAppService, Swift Testing (`import Testing`). Distribution: Developer ID / notarized, non-sandboxed.

**Reference source (read, do not copy blindly):** `../lockpaw/` (lock overlay, input blocker, authenticator, hotkey, sleep preventer) and `../Jiggler/` (mouse-move + idle).

**Spec:** `docs/superpowers/specs/2026-06-03-iup-design.md`

**Test command (whole suite):** `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests`
**Build command:** `xcodebuild build -scheme iUp -destination 'platform=macOS'`
**Single suite:** append `/SuiteName`, e.g. `-only-testing:iUpTests/SettingsTests`

**Conventions:**
- Source files under `iUp/`. Group by responsibility: `iUp/Core/`, `iUp/Features/`, `iUp/System/`, `iUp/UI/`.
- Tests under `iUpTests/`, one suite file per logic unit.
- Commit after every passing task. Use Conventional Commits.
- New `.swift` files must be added to the `iUp` (or `iUpTests`) target in `project.pbxproj`. After creating a file, verify with a build before moving on. If using Xcode-less workflow, edit `project.pbxproj` to register the file in the target's `PBXBuildFile`/`PBXFileReference`/`Sources` phase, OR keep files in a folder reference if the project uses synchronized groups (check whether `project.pbxproj` contains `PBXFileSystemSynchronizedRootGroup` — macOS 15+/Xcode 16 default; if so, files dropped into the group are auto-included and no pbxproj edit is needed).

---

## File Structure

**Create:**
- `iUp/Core/Clock.swift` — `Clock` protocol + `SystemClock`.
- `iUp/Core/Settings.swift` — typed `UserDefaults` config wrapper, all feature toggles + thresholds.
- `iUp/Core/SyntheticTag.swift` — `iUpSyntheticMagic` constant + helpers.
- `iUp/Core/ActivityMonitor.swift` — real-input clock, synthetic filtering, idle ticks.
- `iUp/Features/Awake/AwakeController.swift` — IOPMAssertions.
- `iUp/Features/Jiggle/JiggleMath.swift` — pure target-point math.
- `iUp/Features/Jiggle/JiggleController.swift` — start/stop + posting.
- `iUp/Features/Session/SessionState.swift` — session enum.
- `iUp/Features/Session/SessionController.swift` — session + TempPause policy.
- `iUp/Features/Lock/LockState.swift` — lock state machine enum.
- `iUp/Features/Lock/BurnIn.swift` — anti-burn-in position generator.
- `iUp/Features/Lock/OverlayWindowManager.swift` — per-screen windows.
- `iUp/Features/Lock/InputBlocker.swift` — swallow input.
- `iUp/Features/Lock/Authenticator.swift` — Touch ID / password.
- `iUp/Features/Lock/LockController.swift` — wiring.
- `iUp/Features/Lock/LockScreenView.swift` — overlay content.
- `iUp/Features/Display/BrightnessService.swift` — private brightness API shell.
- `iUp/Features/Display/DisplayController.swift` — dim/restore logic.
- `iUp/System/AccessibilityChecker.swift` — permission state/prompt.
- `iUp/System/HotkeyManager.swift` — global hotkeys.
- `iUp/System/LoginItem.swift` — SMAppService.
- `iUp/UI/MenuBarController.swift` — status item + menu.
- `iUp/UI/SettingsView.swift` — settings UI.
- `iUp/AppDelegate.swift` — top-level wiring.
- Test suites under `iUpTests/` per logic unit.

**Modify:**
- `iUp/iUpApp.swift` — strip SwiftData, accessory app, attach AppDelegate.
- `iUp/Info.plist` (or build settings) — `LSUIElement = YES`.

**Delete:**
- `iUp/Item.swift`, `iUp/ContentView.swift` (SwiftData template).

---

## Phase 0 — Project shell

### Task 1: Convert template to an LSUIElement accessory app

**Files:**
- Modify: `iUp/iUpApp.swift`
- Create: `iUp/AppDelegate.swift`
- Delete: `iUp/Item.swift`, `iUp/ContentView.swift`
- Modify: `iUp/Info.plist` or target build settings (add `LSUIElement`)

- [ ] **Step 1: Delete template files**

```bash
rm iUp/Item.swift iUp/ContentView.swift
```

- [ ] **Step 2: Replace `iUpApp.swift`**

```swift
import SwiftUI

@main
struct iUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No primary window. Settings scene added in Task 19.
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 3: Create `iUp/AppDelegate.swift`**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, menu-bar only.
        NSApp.setActivationPolicy(.accessory)
        // Wiring of controllers added in later tasks.
    }
}
```

- [ ] **Step 4: Set `LSUIElement`**

Add `LSUIElement` = `YES` (Boolean) to `iUp/Info.plist`. If the target uses generated Info.plist (`GENERATE_INFOPLIST_FILE = YES`), add build setting `INFOPLIST_KEY_LSUIElement = YES` to both Debug and Release for the `iUp` target in `project.pbxproj`.

- [ ] **Step 5: Build and launch**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED. Launch the built app; verify no Dock icon, no window.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: convert template to LSUIElement accessory app"
```

---

### Task 2: Settings — typed UserDefaults config

**Files:**
- Create: `iUp/Core/Settings.swift`
- Test: `iUpTests/SettingsTests.swift`

Independence requirement: every feature toggle and threshold is its own key, persisted separately. `Settings` takes an injectable `UserDefaults` so tests use an isolated suite.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import iUp

struct SettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "iup.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func defaultsMatchSpec() {
        let s = Settings(defaults: makeDefaults())
        // Awake + sub-assertions default ON
        #expect(s.awakeEnabled == true)
        #expect(s.awakeDisplayOn == true)
        #expect(s.awakeSystemSleep == true)
        #expect(s.awakeNetworkOn == true)
        // Jiggle
        #expect(s.jiggleEnabled == true)
        #expect(s.jiggleIdleStart == 60)
        #expect(s.jiggleInterval == 30)
        #expect(s.jiggleStopAfter == 300)
        // TempPause
        #expect(s.tempPauseEnabled == true)
        #expect(s.tempPauseIdle == 60)
        // Display
        #expect(s.displayControlEnabled == true)
        #expect(s.displayDimIdle == 60)
        #expect(s.displayInternalDim == true)
        #expect(s.displayExternalOff == true)
        // Lock
        #expect(s.lockEnabled == true)
        #expect(s.burnInInterval == 30)
        // App options
        #expect(s.launchAtLogin == false)
        #expect(s.autoStartSession == false)
    }

    @Test func persistsAcrossInstances() {
        let d = makeDefaults()
        let a = Settings(defaults: d)
        a.jiggleIdleStart = 120
        a.awakeNetworkOn = false
        let b = Settings(defaults: d)
        #expect(b.jiggleIdleStart == 120)
        #expect(b.awakeNetworkOn == false)
    }

    @Test func togglesAreIndependent() {
        let s = Settings(defaults: makeDefaults())
        s.awakeEnabled = false
        #expect(s.jiggleEnabled == true)
        #expect(s.tempPauseEnabled == true)
        #expect(s.lockEnabled == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/SettingsTests`
Expected: FAIL — `Settings` not found.

- [ ] **Step 3: Implement `Settings`**

```swift
import Foundation

/// Typed wrapper over UserDefaults. Every feature owns its own keys;
/// no key is shared or derived from another (per-feature independence).
final class Settings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private enum Key {
        static let awakeEnabled = "awake.enabled"
        static let awakeDisplayOn = "awake.displayOn"
        static let awakeSystemSleep = "awake.systemSleep"
        static let awakeNetworkOn = "awake.networkOn"
        static let jiggleEnabled = "jiggle.enabled"
        static let jiggleIdleStart = "jiggle.idleStart"
        static let jiggleInterval = "jiggle.interval"
        static let jiggleStopAfter = "jiggle.stopAfter"
        static let tempPauseEnabled = "tempPause.enabled"
        static let tempPauseIdle = "tempPause.idle"
        static let displayControlEnabled = "display.enabled"
        static let displayDimIdle = "display.dimIdle"
        static let displayInternalDim = "display.internalDim"
        static let displayExternalOff = "display.externalOff"
        static let lockEnabled = "lock.enabled"
        static let burnInInterval = "lock.burnInInterval"
        static let launchAtLogin = "app.launchAtLogin"
        static let autoStartSession = "app.autoStartSession"
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.awakeEnabled: true,
            Key.awakeDisplayOn: true,
            Key.awakeSystemSleep: true,
            Key.awakeNetworkOn: true,
            Key.jiggleEnabled: true,
            Key.jiggleIdleStart: 60.0,
            Key.jiggleInterval: 30.0,
            Key.jiggleStopAfter: 300.0,
            Key.tempPauseEnabled: true,
            Key.tempPauseIdle: 60.0,
            Key.displayControlEnabled: true,
            Key.displayDimIdle: 60.0,
            Key.displayInternalDim: true,
            Key.displayExternalOff: true,
            Key.lockEnabled: true,
            Key.burnInInterval: 30.0,
            Key.launchAtLogin: false,
            Key.autoStartSession: false,
        ])
    }

    private func bool(_ k: String) -> Bool { defaults.bool(forKey: k) }
    private func setBool(_ v: Bool, _ k: String) { defaults.set(v, forKey: k) }
    private func dbl(_ k: String) -> TimeInterval { defaults.double(forKey: k) }
    private func setDbl(_ v: TimeInterval, _ k: String) { defaults.set(v, forKey: k) }

    var awakeEnabled: Bool { get { bool(Key.awakeEnabled) } set { setBool(newValue, Key.awakeEnabled) } }
    var awakeDisplayOn: Bool { get { bool(Key.awakeDisplayOn) } set { setBool(newValue, Key.awakeDisplayOn) } }
    var awakeSystemSleep: Bool { get { bool(Key.awakeSystemSleep) } set { setBool(newValue, Key.awakeSystemSleep) } }
    var awakeNetworkOn: Bool { get { bool(Key.awakeNetworkOn) } set { setBool(newValue, Key.awakeNetworkOn) } }

    var jiggleEnabled: Bool { get { bool(Key.jiggleEnabled) } set { setBool(newValue, Key.jiggleEnabled) } }
    var jiggleIdleStart: TimeInterval { get { dbl(Key.jiggleIdleStart) } set { setDbl(newValue, Key.jiggleIdleStart) } }
    var jiggleInterval: TimeInterval { get { dbl(Key.jiggleInterval) } set { setDbl(newValue, Key.jiggleInterval) } }
    var jiggleStopAfter: TimeInterval { get { dbl(Key.jiggleStopAfter) } set { setDbl(newValue, Key.jiggleStopAfter) } }

    var tempPauseEnabled: Bool { get { bool(Key.tempPauseEnabled) } set { setBool(newValue, Key.tempPauseEnabled) } }
    var tempPauseIdle: TimeInterval { get { dbl(Key.tempPauseIdle) } set { setDbl(newValue, Key.tempPauseIdle) } }

    var displayControlEnabled: Bool { get { bool(Key.displayControlEnabled) } set { setBool(newValue, Key.displayControlEnabled) } }
    var displayDimIdle: TimeInterval { get { dbl(Key.displayDimIdle) } set { setDbl(newValue, Key.displayDimIdle) } }
    var displayInternalDim: Bool { get { bool(Key.displayInternalDim) } set { setBool(newValue, Key.displayInternalDim) } }
    var displayExternalOff: Bool { get { bool(Key.displayExternalOff) } set { setBool(newValue, Key.displayExternalOff) } }

    var lockEnabled: Bool { get { bool(Key.lockEnabled) } set { setBool(newValue, Key.lockEnabled) } }
    var burnInInterval: TimeInterval { get { dbl(Key.burnInInterval) } set { setDbl(newValue, Key.burnInInterval) } }

    var launchAtLogin: Bool { get { bool(Key.launchAtLogin) } set { setBool(newValue, Key.launchAtLogin) } }
    var autoStartSession: Bool { get { bool(Key.autoStartSession) } set { setBool(newValue, Key.autoStartSession) } }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/SettingsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/Core/Settings.swift iUpTests/SettingsTests.swift
git commit -m "feat: typed Settings wrapper with per-feature keys"
```

---

## Phase 1 — Activity clock

### Task 3: Clock + SyntheticTag

**Files:**
- Create: `iUp/Core/Clock.swift`
- Create: `iUp/Core/SyntheticTag.swift`

No dedicated test (trivial). Covered indirectly by Task 4.

- [ ] **Step 1: Create `iUp/Core/Clock.swift`**

```swift
import Foundation

/// Abstracts "now" so timing logic is testable without real time.
protocol Clock {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}

/// Test/double clock whose time is set manually.
final class ManualClock: Clock {
    var now: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { now = start }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
```

- [ ] **Step 2: Create `iUp/Core/SyntheticTag.swift`**

```swift
import CoreGraphics

/// Magic value written to a synthetic event's `.eventSourceUserData` field so
/// `ActivityMonitor` can tell iUp-generated input from real user input.
/// This is the single mechanism enforcing "simulated input does not count".
let iUpSyntheticMagic: Int64 = 0x6955_7000  // "iUp\0"

extension CGEvent {
    func tagAsSynthetic() {
        setIntegerValueField(.eventSourceUserData, value: iUpSyntheticMagic)
    }

    var isSyntheticFromiUp: Bool {
        getIntegerValueField(.eventSourceUserData) == iUpSyntheticMagic
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add iUp/Core/Clock.swift iUp/Core/SyntheticTag.swift
git commit -m "feat: Clock abstraction and synthetic-event tagging"
```

---

### Task 4: ActivityMonitor — idle clock + synthetic filtering

**Files:**
- Create: `iUp/Core/ActivityMonitor.swift`
- Test: `iUpTests/ActivityMonitorTests.swift`

The monitor's *logic* (record real input, ignore synthetic, compute idle, notify subscribers on tick) is fully tested with a `ManualClock` and a manual `record(...)` entry point. The real `CGEventTap` is a thin shell that calls `record` — installed only in Task 18 wiring, not unit-tested.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import iUp

struct ActivityMonitorTests {
    @Test func idleStartsAtZeroAfterRealInput() {
        let clock = ManualClock()
        let m = ActivityMonitor(clock: clock)
        m.record(isSynthetic: false)
        #expect(m.idle == 0)
        clock.advance(5)
        #expect(m.idle == 5)
    }

    @Test func syntheticInputDoesNotResetIdle() {
        let clock = ManualClock()
        let m = ActivityMonitor(clock: clock)
        m.record(isSynthetic: false)
        clock.advance(10)
        m.record(isSynthetic: true)   // simulated — must NOT reset
        #expect(m.idle == 10)
        clock.advance(5)
        #expect(m.idle == 15)
    }

    @Test func realInputResetsIdleAndFiresActive() {
        let clock = ManualClock()
        let m = ActivityMonitor(clock: clock)
        var activeCount = 0
        m.onUserBecameActive = { activeCount += 1 }
        m.record(isSynthetic: false)
        clock.advance(30)
        m.record(isSynthetic: false)
        #expect(m.idle == 0)
        #expect(activeCount == 2)
    }

    @Test func syntheticDoesNotFireActive() {
        let clock = ManualClock()
        let m = ActivityMonitor(clock: clock)
        var activeCount = 0
        m.onUserBecameActive = { activeCount += 1 }
        m.record(isSynthetic: true)
        #expect(activeCount == 0)
    }

    @Test func tickNotifiesSubscribersWithIdle() {
        let clock = ManualClock()
        let m = ActivityMonitor(clock: clock)
        m.record(isSynthetic: false)
        var ticks: [TimeInterval] = []
        m.onTick = { ticks.append($0) }
        clock.advance(3)
        m.tick()
        clock.advance(2)
        m.tick()
        #expect(ticks == [3, 5])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/ActivityMonitorTests`
Expected: FAIL — `ActivityMonitor` not found.

- [ ] **Step 3: Implement `ActivityMonitor`**

```swift
import Foundation

/// Single source of truth for the user-activity clock.
/// Real input updates `lastRealInputDate`; synthetic (iUp-generated) input is ignored.
/// A periodic `tick()` (driven by a DispatchSourceTimer in production) recomputes idle
/// and notifies subscribers. The real CGEventTap installation lives in app wiring; here
/// `record(isSynthetic:)` is the testable entry point the tap callback calls.
final class ActivityMonitor {
    private let clock: Clock
    private(set) var lastRealInputDate: Date

    /// Called once each time real user input arrives after a period (every real event).
    var onUserBecameActive: (() -> Void)?
    /// Called each tick with the current idle interval.
    var onTick: ((TimeInterval) -> Void)?

    init(clock: Clock = SystemClock()) {
        self.clock = clock
        self.lastRealInputDate = clock.now
    }

    var idle: TimeInterval { clock.now.timeIntervalSince(lastRealInputDate) }

    /// Entry point invoked by the event-tap callback for every observed event.
    func record(isSynthetic: Bool) {
        guard !isSynthetic else { return }
        lastRealInputDate = clock.now
        onUserBecameActive?()
    }

    func tick() { onTick?(idle) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/ActivityMonitorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/Core/ActivityMonitor.swift iUpTests/ActivityMonitorTests.swift
git commit -m "feat: ActivityMonitor idle clock with synthetic filtering"
```

---

## Phase 2 — Awake

### Task 5: AwakeController — power assertions

**Files:**
- Create: `iUp/Features/Awake/AwakeController.swift`
- Test: `iUpTests/AwakeControllerTests.swift`

The IOKit calls sit behind an `AssertionManaging` protocol. The controller's logic — which assertion kinds to hold based on the independent sub-toggles, and releasing all on deactivate — is tested with a fake. The real IOKit-backed implementation is a shell verified by build + manual run.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import iUp

private final class FakeAssertions: AssertionManaging {
    var held: Set<AwakeAssertion> = []
    func hold(_ kind: AwakeAssertion) { held.insert(kind) }
    func release(_ kind: AwakeAssertion) { held.remove(kind) }
    func releaseAll() { held.removeAll() }
}

struct AwakeControllerTests {
    private func settings() -> Settings {
        Settings(defaults: UserDefaults(suiteName: "iup.awake.\(UUID().uuidString)")!)
    }

    @Test func activateHoldsAllEnabledAssertions() {
        let fake = FakeAssertions()
        let s = settings()
        let c = AwakeController(settings: s, assertions: fake)
        c.activate()
        #expect(fake.held == [.displaySleep, .systemSleep, .network])
    }

    @Test func subTogglesAreIndependent() {
        let fake = FakeAssertions()
        let s = settings()
        s.awakeNetworkOn = false
        s.awakeSystemSleep = false
        let c = AwakeController(settings: s, assertions: fake)
        c.activate()
        #expect(fake.held == [.displaySleep])
    }

    @Test func deactivateReleasesAll() {
        let fake = FakeAssertions()
        let c = AwakeController(settings: settings(), assertions: fake)
        c.activate()
        c.deactivate()
        #expect(fake.held.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/AwakeControllerTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement `AwakeController` + real assertion backend**

```swift
import Foundation
import IOKit.pwr_mgt
import os.log

enum AwakeAssertion: Hashable {
    case displaySleep   // PreventUserIdleDisplaySleep
    case systemSleep    // PreventUserIdleSystemSleep
    case network        // NetworkClientActive
}

protocol AssertionManaging {
    func hold(_ kind: AwakeAssertion)
    func release(_ kind: AwakeAssertion)
    func releaseAll()
}

/// Decides which assertions to hold from the independent sub-toggles and
/// keeps a periodic user-activity declaration alive while active.
final class AwakeController {
    private let settings: Settings
    private let assertions: AssertionManaging
    private(set) var isActive = false

    init(settings: Settings, assertions: AssertionManaging) {
        self.settings = settings
        self.assertions = assertions
    }

    func activate() {
        guard settings.awakeEnabled else { return }
        isActive = true
        if settings.awakeDisplayOn { assertions.hold(.displaySleep) }
        if settings.awakeSystemSleep { assertions.hold(.systemSleep) }
        if settings.awakeNetworkOn { assertions.hold(.network) }
    }

    func deactivate() {
        isActive = false
        assertions.releaseAll()
    }
}

/// Real IOKit-backed assertions. Shell: verified by build + manual run, not unit-tested.
final class IOPMAssertions: AssertionManaging {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Awake")
    private var ids: [AwakeAssertion: IOPMAssertionID] = [:]

    private func typeName(_ kind: AwakeAssertion) -> CFString {
        switch kind {
        case .displaySleep: return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        case .systemSleep:  return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .network:      return "NetworkClientActive" as CFString
        }
    }

    func hold(_ kind: AwakeAssertion) {
        guard ids[kind] == nil else { return }
        var id = IOPMAssertionID(0)
        let r = IOPMAssertionCreateWithName(typeName(kind),
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "iUp keeping Mac awake" as CFString, &id)
        if r == kIOReturnSuccess { ids[kind] = id }
        else { Self.log.error("assertion \(String(describing: kind)) failed: \(r)") }
    }

    func release(_ kind: AwakeAssertion) {
        if let id = ids[kind] { IOPMAssertionRelease(id); ids[kind] = nil }
    }

    func releaseAll() { for k in Array(ids.keys) { release(k) } }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/AwakeControllerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/Features/Awake/AwakeController.swift iUpTests/AwakeControllerTests.swift
git commit -m "feat: AwakeController with independent assertion toggles"
```

---

## Phase 3 — Activity simulation (jiggle)

### Task 6: JiggleMath — pure target-point selection

**Files:**
- Create: `iUp/Features/Jiggle/JiggleMath.swift`
- Test: `iUpTests/JiggleMathTests.swift`

Pure function: given current point, a list of screen rects, a seeded RNG, and a tolerance, return a new point that is inside some screen (inset from edges) and not equal to the avoid point. Mirrors Jiggler's drift-limited search, made deterministic + testable via an injected RNG.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import CoreGraphics
@testable import iUp

struct JiggleMathTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    @Test func resultIsInsideScreenInset() {
        var rng = SeededRNG(seed: 42)
        for _ in 0..<200 {
            let p = JiggleMath.nextPoint(from: CGPoint(x: 500, y: 500),
                                         avoiding: CGPoint(x: -1, y: -1),
                                         screens: [screen], tolerance: 30,
                                         inset: 3, using: &rng)!
            #expect(p.x >= 3 && p.x <= 997)
            #expect(p.y >= 3 && p.y <= 997)
        }
    }

    @Test func resultNeverEqualsAvoidPoint() {
        var rng = SeededRNG(seed: 7)
        let avoid = CGPoint(x: 500, y: 500)
        for _ in 0..<200 {
            let p = JiggleMath.nextPoint(from: CGPoint(x: 500, y: 500),
                                         avoiding: avoid, screens: [screen],
                                         tolerance: 30, inset: 3, using: &rng)!
            #expect(!(p.x == avoid.x && p.y == avoid.y))
        }
    }

    @Test func staysWithinToleranceDrift() {
        var rng = SeededRNG(seed: 99)
        let from = CGPoint(x: 500, y: 500)
        let p = JiggleMath.nextPoint(from: from, avoiding: .zero,
                                     screens: [screen], tolerance: 30,
                                     inset: 3, using: &rng)!
        #expect(abs(p.x - from.x) <= 30)
        #expect(abs(p.y - from.y) <= 30)
    }

    @Test func returnsNilWhenNoScreens() {
        var rng = SeededRNG(seed: 1)
        let p = JiggleMath.nextPoint(from: .zero, avoiding: .zero,
                                     screens: [], tolerance: 30, inset: 3, using: &rng)
        #expect(p == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/JiggleMathTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement `JiggleMath` + `SeededRNG`**

```swift
import CoreGraphics

/// Deterministic RNG for testable jiggle math (SplitMix64).
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum JiggleMath {
    /// Pick a new cursor point near `from`, within `tolerance` on each axis,
    /// inside one of `screens` (inset from edges), never equal to `avoiding`.
    /// Returns nil if no screens or no valid point found.
    static func nextPoint<R: RandomNumberGenerator>(
        from: CGPoint, avoiding: CGPoint, screens: [CGRect],
        tolerance: CGFloat, inset: CGFloat, using rng: inout R
    ) -> CGPoint? {
        guard !screens.isEmpty else { return nil }
        let insetScreens = screens.map { $0.insetBy(dx: inset, dy: inset) }

        for attempt in 0..<100 {
            let t = attempt < 20 ? tolerance : tolerance + CGFloat(attempt - 20)
            let dx = CGFloat(Int.random(in: Int(-t)...Int(t), using: &rng))
            let dy = CGFloat(Int.random(in: Int(-t)...Int(t), using: &rng))
            let candidate = CGPoint(x: from.x + dx, y: from.y + dy)
            if candidate == avoiding { continue }
            if insetScreens.contains(where: { $0.contains(candidate) }) {
                return candidate
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/JiggleMathTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/Features/Jiggle/JiggleMath.swift iUpTests/JiggleMathTests.swift
git commit -m "feat: deterministic jiggle target-point math"
```

---

### Task 7: JiggleController — start/stop thresholds

**Files:**
- Create: `iUp/Features/Jiggle/JiggleController.swift`
- Test: `iUpTests/JiggleControllerTests.swift`

Decides, given an idle value and settings, whether jiggling should be running and whether a move burst is due. Posting bursts goes through a `MovePosting` protocol so logic is tested with a fake. The CGEvent-posting implementation is a shell.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import iUp

private final class FakePoster: MovePosting {
    var burstCount = 0
    func postBurst() { burstCount += 1 }
}

struct JiggleControllerTests {
    private func settings() -> Settings {
        let s = Settings(defaults: UserDefaults(suiteName: "iup.jig.\(UUID().uuidString)")!)
        s.jiggleIdleStart = 60; s.jiggleInterval = 30; s.jiggleStopAfter = 300
        return s
    }

    @Test func noBurstBeforeIdleStart() {
        let p = FakePoster()
        let c = JiggleController(settings: settings(), poster: p)
        c.evaluate(idle: 59)
        #expect(p.burstCount == 0)
        #expect(c.isJiggling == false)
    }

    @Test func startsAndburstsAtInterval() {
        let p = FakePoster()
        let c = JiggleController(settings: settings(), poster: p)
        c.evaluate(idle: 60)            // start → first burst
        #expect(c.isJiggling == true)
        #expect(p.burstCount == 1)
        c.evaluate(idle: 75)            // < interval since last burst → none
        #expect(p.burstCount == 1)
        c.evaluate(idle: 90)            // 30s since start → second burst
        #expect(p.burstCount == 2)
    }

    @Test func stopsAfterIdleStartPlusStopAfter() {
        let p = FakePoster()
        let c = JiggleController(settings: settings(), poster: p)
        c.evaluate(idle: 60)
        c.evaluate(idle: 360)           // 60 + 300 → stop, no burst
        #expect(c.isJiggling == false)
        let before = p.burstCount
        c.evaluate(idle: 400)
        #expect(p.burstCount == before)
    }

    @Test func resetReturnsToIdleState() {
        let p = FakePoster()
        let c = JiggleController(settings: settings(), poster: p)
        c.evaluate(idle: 90)
        c.reset()                       // user became active
        #expect(c.isJiggling == false)
        c.evaluate(idle: 60)            // fresh start bursts again
        #expect(p.burstCount >= 1)
    }

    @Test func disabledNeverJiggles() {
        let p = FakePoster()
        let s = settings(); s.jiggleEnabled = false
        let c = JiggleController(settings: s, poster: p)
        c.evaluate(idle: 120)
        #expect(p.burstCount == 0)
        #expect(c.isJiggling == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/JiggleControllerTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement `JiggleController` + posting shell**

```swift
import CoreGraphics
import AppKit

protocol MovePosting {
    /// Post a single ~0.5s continuous synthetic move burst (tagged synthetic).
    func postBurst()
}

/// Drives jiggling from the shared idle clock.
/// Start at idle >= jiggleIdleStart; burst every jiggleInterval; stop at
/// idle >= jiggleIdleStart + jiggleStopAfter. `reset()` is called on real input.
final class JiggleController {
    private let settings: Settings
    private let poster: MovePosting
    private(set) var isJiggling = false
    private var lastBurstIdle: TimeInterval = 0

    init(settings: Settings, poster: MovePosting) {
        self.settings = settings
        self.poster = poster
    }

    func evaluate(idle: TimeInterval) {
        guard settings.jiggleEnabled else { isJiggling = false; return }
        let start = settings.jiggleIdleStart
        let stop = start + settings.jiggleStopAfter

        if idle >= stop { isJiggling = false; return }
        guard idle >= start else { isJiggling = false; return }

        if !isJiggling {
            isJiggling = true
            poster.postBurst()
            lastBurstIdle = idle
            return
        }
        if idle - lastBurstIdle >= settings.jiggleInterval {
            poster.postBurst()
            lastBurstIdle = idle
        }
    }

    func reset() {
        isJiggling = false
        lastBurstIdle = 0
    }
}

/// Real CGEvent-posting burst. Shell: verified by build + manual run.
final class CGMovePoster: MovePosting {
    func postBurst() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let old = source.localEventsSuppressionInterval
        source.localEventsSuppressionInterval = 0
        var rng = SystemRandomNumberGenerator()
        let screens = NSScreen.screens.map { $0.frame }
        var current = currentCursorCG()
        // ~0.5s of motion: 35 steps spaced ~14ms.
        for i in 0..<35 {
            guard let next = JiggleMath.nextPoint(from: current, avoiding: current,
                                                  screens: screens, tolerance: 30,
                                                  inset: 3, using: &rng) else { break }
            let e = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                            mouseCursorPosition: next, mouseButton: .left)
            e?.tagAsSynthetic()
            e?.post(tap: .cghidEventTap)
            current = next
            if i < 34 { usleep(14_000) }
        }
        source.localEventsSuppressionInterval = old
    }

    /// Current cursor in CG (top-left origin) coordinates.
    private func currentCursorCG() -> CGPoint {
        let loc = NSEvent.mouseLocation
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: loc.x, y: h - loc.y)
    }
}
```

> Note: `postBurst()` blocks ~0.5s; in wiring it is dispatched on a background queue so the main thread is not stalled.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/JiggleControllerTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/Features/Jiggle/JiggleController.swift iUpTests/JiggleControllerTests.swift
git commit -m "feat: JiggleController start/stop threshold logic"
```

---

## Phase 4 — Session orchestration + TempPause

### Task 8: SessionState + SessionController

**Files:**
- Create: `iUp/Features/Session/SessionState.swift`
- Create: `iUp/Features/Session/SessionController.swift`
- Test: `iUpTests/SessionControllerTests.swift`

Orchestrates the awake session over Awake + Jiggle via protocols (`AwakeDriving`, `JiggleDriving`). Implements the TempPause policy and auto/manual resume. Fully unit-tested with fakes.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import iUp

private final class FakeAwake: AwakeDriving {
    private(set) var active = false
    func activate() { active = true }
    func deactivate() { active = false }
}
private final class FakeJiggle: JiggleDriving {
    var lastIdle: TimeInterval?
    var resets = 0
    func evaluate(idle: TimeInterval) { lastIdle = idle }
    func reset() { resets += 1 }
}

struct SessionControllerTests {
    private func make(tempPause: Bool = true, tPause: TimeInterval = 60)
        -> (SessionController, FakeAwake, FakeJiggle, Settings) {
        let s = Settings(defaults: UserDefaults(suiteName: "iup.sess.\(UUID().uuidString)")!)
        s.tempPauseEnabled = tempPause; s.tempPauseIdle = tPause
        let a = FakeAwake(); let j = FakeJiggle()
        return (SessionController(settings: s, awake: a, jiggle: j), a, j, s)
    }

    @Test func startsActiveAndActivatesAwake() {
        let (c, a, _, _) = make()
        #expect(c.state == .off)
        c.start()
        #expect(c.state == .active)
        #expect(a.active == true)
    }

    @Test func tickDrivesJiggleWhileActive() {
        let (c, _, j, _) = make()
        c.start()
        c.tick(idle: 45)
        #expect(j.lastIdle == 45)
    }

    @Test func tempPausePausesAtThreshold() {
        let (c, a, _, _) = make(tPause: 60)
        c.start()
        c.tick(idle: 60)
        #expect(c.state == .pausedByIdle)
        #expect(a.active == false)        // awake released → Mac may sleep
    }

    @Test func tempPauseDisabledNeverPauses() {
        let (c, a, _, _) = make(tempPause: false)
        c.start()
        c.tick(idle: 9999)
        #expect(c.state == .active)
        #expect(a.active == true)
    }

    @Test func userActivityResumesFromPause() {
        let (c, a, _, _) = make()
        c.start(); c.tick(idle: 60)
        #expect(c.state == .pausedByIdle)
        c.userBecameActive()
        #expect(c.state == .active)
        #expect(a.active == true)
    }

    @Test func systemWakeResumesFromPause() {
        let (c, a, _, _) = make()
        c.start(); c.tick(idle: 60)
        c.systemDidWake()
        #expect(c.state == .active)
        #expect(a.active == true)
    }

    @Test func manualResumeWorks() {
        let (c, a, _, _) = make()
        c.start(); c.tick(idle: 60)
        c.resume()
        #expect(c.state == .active)
        #expect(a.active == true)
    }

    @Test func stopGoesOffAndReleases() {
        let (c, a, j, _) = make()
        c.start()
        c.stop()
        #expect(c.state == .off)
        #expect(a.active == false)
        #expect(j.resets >= 1)
    }

    @Test func userActivityWhileActiveResetsJiggle() {
        let (c, _, j, _) = make(tempPause: false)
        c.start()
        let before = j.resets
        c.userBecameActive()
        #expect(j.resets == before + 1)
    }

    @Test func tickIgnoredWhenOffOrPaused() {
        let (c, _, j, _) = make()
        c.tick(idle: 30)                  // off
        #expect(j.lastIdle == nil)
        c.start(); c.tick(idle: 60)       // now paused
        j.lastIdle = nil
        c.tick(idle: 70)                  // paused → ignored
        #expect(j.lastIdle == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/SessionControllerTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement `SessionState` and `SessionController`**

`iUp/Features/Session/SessionState.swift`:

```swift
enum SessionState: Equatable {
    case off
    case active
    case pausedByIdle
}
```

`iUp/Features/Session/SessionController.swift`:

```swift
import Foundation

protocol AwakeDriving: AnyObject {
    func activate()
    func deactivate()
}
protocol JiggleDriving: AnyObject {
    func evaluate(idle: TimeInterval)
    func reset()
}

extension AwakeController: AwakeDriving {}
extension JiggleController: JiggleDriving {}

/// Owns the awake session. When active, drives Awake + Jiggle.
/// TempPause policy: at idle >= tempPauseIdle (if enabled) release everything so
/// the Mac may sleep; resume on user input, system wake, or manual button.
final class SessionController {
    private let settings: Settings
    private let awake: AwakeDriving
    private let jiggle: JiggleDriving

    private(set) var state: SessionState = .off
    var onStateChange: ((SessionState) -> Void)?

    init(settings: Settings, awake: AwakeDriving, jiggle: JiggleDriving) {
        self.settings = settings
        self.awake = awake
        self.jiggle = jiggle
    }

    private func set(_ new: SessionState) {
        guard new != state else { return }
        state = new
        onStateChange?(new)
    }

    func start() {
        guard state == .off else { return }
        awake.activate()
        jiggle.reset()
        set(.active)
    }

    func stop() {
        awake.deactivate()
        jiggle.reset()
        set(.off)
    }

    /// Manual or automatic resume from pause.
    func resume() {
        guard state == .pausedByIdle else { return }
        awake.activate()
        jiggle.reset()
        set(.active)
    }

    func tick(idle: TimeInterval) {
        guard state == .active else { return }
        if settings.tempPauseEnabled && idle >= settings.tempPauseIdle {
            awake.deactivate()
            jiggle.reset()
            set(.pausedByIdle)
            return
        }
        jiggle.evaluate(idle: idle)
    }

    func userBecameActive() {
        switch state {
        case .pausedByIdle: resume()
        case .active: jiggle.reset()
        case .off: break
        }
    }

    func systemDidWake() {
        if state == .pausedByIdle { resume() }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/SessionControllerTests`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/Features/Session/ iUpTests/SessionControllerTests.swift
git commit -m "feat: SessionController with TempPause auto/manual resume"
```

---

## Phase 5 — Lock

### Task 9: LockState — transition machine

**Files:**
- Create: `iUp/Features/Lock/LockState.swift`
- Test: `iUpTests/LockStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import iUp

struct LockStateTests {
    @Test func validTransitions() {
        #expect(LockState.unlocked.canTransition(to: .locking))
        #expect(LockState.locking.canTransition(to: .locked))
        #expect(LockState.locking.canTransition(to: .unlocked))   // e.g. no accessibility
        #expect(LockState.locked.canTransition(to: .unlocking))
        #expect(LockState.unlocking.canTransition(to: .locked))   // auth failed
        #expect(LockState.unlocking.canTransition(to: .unlocked)) // auth ok
    }

    @Test func invalidTransitions() {
        #expect(!LockState.unlocked.canTransition(to: .locked))
        #expect(!LockState.unlocked.canTransition(to: .unlocking))
        #expect(!LockState.locked.canTransition(to: .unlocked))   // must go via unlocking
        #expect(!LockState.locked.canTransition(to: .locking))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/LockStateTests`
Expected: FAIL — `LockState` not found.

- [ ] **Step 3: Implement `LockState`**

```swift
enum LockState: Equatable {
    case unlocked
    case locking
    case locked
    case unlocking

    func canTransition(to next: LockState) -> Bool {
        switch (self, next) {
        case (.unlocked, .locking),
             (.locking, .locked),
             (.locking, .unlocked),
             (.locked, .unlocking),
             (.unlocking, .locked),
             (.unlocking, .unlocked):
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/LockStateTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/Features/Lock/LockState.swift iUpTests/LockStateTests.swift
git commit -m "feat: LockState transition machine"
```

---

### Task 10: BurnIn — anti-burn-in position generator

**Files:**
- Create: `iUp/Features/Lock/BurnIn.swift`
- Test: `iUpTests/BurnInTests.swift`

Given a container size and a label size, return a random top-left origin keeping the label fully inside. Distribution test: over many samples the centers should cover all cells of a coarse grid (equal-probability coverage of the screen).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import CoreGraphics
@testable import iUp

struct BurnInTests {
    private let container = CGSize(width: 1000, height: 800)
    private let label = CGSize(width: 200, height: 60)

    @Test func originKeepsLabelInside() {
        var rng = SeededRNG(seed: 5)
        for _ in 0..<500 {
            let o = BurnIn.nextOrigin(container: container, label: label, using: &rng)
            #expect(o.x >= 0 && o.x <= container.width - label.width)
            #expect(o.y >= 0 && o.y <= container.height - label.height)
        }
    }

    @Test func coversAllGridCells() {
        var rng = SeededRNG(seed: 123)
        let cols = 4, rows = 4
        var hit = Set<Int>()
        for _ in 0..<5000 {
            let o = BurnIn.nextOrigin(container: container, label: label, using: &rng)
            let cx = o.x + label.width / 2
            let cy = o.y + label.height / 2
            let col = min(cols - 1, Int(cx / (container.width / CGFloat(cols))))
            let row = min(rows - 1, Int(cy / (container.height / CGFloat(rows))))
            hit.insert(row * cols + col)
        }
        // Every cell reachable by the label center should be hit.
        #expect(hit.count == cols * rows)
    }

    @Test func degenerateLabelLargerThanContainer() {
        var rng = SeededRNG(seed: 1)
        let o = BurnIn.nextOrigin(container: CGSize(width: 100, height: 100),
                                  label: CGSize(width: 200, height: 200), using: &rng)
        #expect(o == .zero)   // clamp, never negative
    }
}
```

> Note: the `coversAllGridCells` expectation holds because the label (200×60) center can reach across the full available range on both axes for a 4×4 grid of a 1000×800 container. If label/grid constants change, re-derive.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/BurnInTests`
Expected: FAIL — `BurnIn` not found.

- [ ] **Step 3: Implement `BurnIn`**

```swift
import CoreGraphics

enum BurnIn {
    /// Uniform-random top-left origin so the label stays fully inside the container.
    /// Clamps to .zero when the label does not fit.
    static func nextOrigin<R: RandomNumberGenerator>(
        container: CGSize, label: CGSize, using rng: inout R
    ) -> CGPoint {
        let maxX = container.width - label.width
        let maxY = container.height - label.height
        guard maxX > 0, maxY > 0 else { return .zero }
        let x = CGFloat.random(in: 0...maxX, using: &rng)
        let y = CGFloat.random(in: 0...maxY, using: &rng)
        return CGPoint(x: x, y: y)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/BurnInTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/Features/Lock/BurnIn.swift iUpTests/BurnInTests.swift
git commit -m "feat: anti-burn-in position generator"
```

---

### Task 11: Authenticator (shell)

**Files:**
- Create: `iUp/Features/Lock/Authenticator.swift`

Touch ID / password via `LAContext`. Ported from `lockpaw/Lockpaw/Controllers/Authenticator.swift`. No unit test (system dialog); build + manual verify.

- [ ] **Step 1: Create `iUp/Features/Lock/Authenticator.swift`**

```swift
import LocalAuthentication
import os.log

@MainActor
final class Authenticator {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Auth")
    private var activeContext: LAContext?

    /// Touch ID with password fallback. Returns true on success.
    func authenticate(reason: String = "Unlock iUp") async -> Bool {
        cancelPending()
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password\u{2026}"
        activeContext = context
        defer { activeContext = nil }

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            Self.log.error("auth unavailable: \(error?.localizedDescription ?? "?")")
            return false
        }
        return await Task.detached { [context] in
            (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                               localizedReason: reason)) ?? false
        }.value
    }

    func cancelPending() {
        activeContext?.invalidate()
        activeContext = nil
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add iUp/Features/Lock/Authenticator.swift
git commit -m "feat: Touch ID / password authenticator"
```

---

### Task 12: InputBlocker (shell)

**Files:**
- Create: `iUp/Features/Lock/InputBlocker.swift`

Swallows key/scroll/tablet input while locked; lets the unlock hotkey through (posts `.iUpToggleLock`). Ported from `lockpaw/Lockpaw/Controllers/InputBlocker.swift`. Requires Accessibility. Build + manual verify.

- [ ] **Step 1: Create notification names file `iUp/Core/Notifications.swift`**

```swift
import Foundation

extension Notification.Name {
    static let iUpToggleLock = Notification.Name("iUp.toggleLock")
    static let iUpToggleSession = Notification.Name("iUp.toggleSession")
    static let iUpInputBlockerFailed = Notification.Name("iUp.inputBlockerFailed")
}
```

- [ ] **Step 2: Create `iUp/Features/Lock/InputBlocker.swift`**

```swift
import Cocoa
import Carbon
import os.log

/// Installs a cgSession event tap that swallows all key/scroll/tablet events while
/// active. The configured unlock hotkey is allowed through and posts .iUpToggleLock.
final class InputBlocker {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "InputBlocker")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isBlocking = false

    /// Unlock hotkey, refreshed before each block. keyCode + Carbon modifier mask.
    var unlockKeyCode: Int64 = 37          // 'L'
    var unlockModifiers: Int = cmdKey | optionKey | controlKey

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .scrollWheel,
                                    .tabletPointer, .tabletProximity]
        return types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    }()

    func startBlocking() {
        guard !isBlocking else { return }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return nil }
                let me = Unmanaged<InputBlocker>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = me.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return nil
                }
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    var match = keyCode == me.unlockKeyCode
                    let m = me.unlockModifiers
                    if m & cmdKey != 0 { match = match && flags.contains(.maskCommand) }
                    if m & shiftKey != 0 { match = match && flags.contains(.maskShift) }
                    if m & optionKey != 0 { match = match && flags.contains(.maskAlternate) }
                    if m & controlKey != 0 { match = match && flags.contains(.maskControl) }
                    if match {
                        NotificationCenter.default.post(name: .iUpToggleLock, object: nil)
                    }
                }
                return nil   // swallow everything
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let eventTap else {
            Self.log.error("event tap creation failed")
            NotificationCenter.default.post(name: .iUpInputBlockerFailed, object: nil)
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isBlocking = true
    }

    func stopBlocking() {
        guard isBlocking else { return }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        eventTap = nil; runLoopSource = nil; isBlocking = false
    }

    deinit { stopBlocking() }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add iUp/Core/Notifications.swift iUp/Features/Lock/InputBlocker.swift
git commit -m "feat: InputBlocker event tap with unlock-hotkey passthrough"
```

---

### Task 13: OverlayWindowManager + LockScreenView (shell)

**Files:**
- Create: `iUp/Features/Lock/OverlayWindowManager.swift`
- Create: `iUp/Features/Lock/LockScreenView.swift`

Per-screen black borderless windows at shield level; recreate on screen-parameter changes. Ported/adapted from `lockpaw/Lockpaw/Controllers/OverlayWindowManager.swift`. Build + manual verify.

- [ ] **Step 1: Create `iUp/Features/Lock/LockScreenView.swift`**

```swift
import SwiftUI

/// Full-black lock content with dim-grey thin text + unlock button, both repositioned
/// every `burnInInterval` seconds for burn-in protection (BurnIn generator).
struct LockScreenView: View {
    let message: String
    let burnInInterval: TimeInterval
    let onUnlock: () -> Void

    @State private var textOrigin: CGPoint = .zero
    @State private var buttonOrigin: CGPoint = .zero
    private let textSize = CGSize(width: 360, height: 80)
    private let buttonSize = CGSize(width: 160, height: 44)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                Text(message)
                    .font(.system(size: 28, weight: .thin))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(width: textSize.width, height: textSize.height)
                    .position(x: textOrigin.x + textSize.width / 2,
                              y: textOrigin.y + textSize.height / 2)

                Button(action: onUnlock) {
                    Text("Unlock").frame(width: buttonSize.width, height: buttonSize.height)
                }
                .buttonStyle(.borderedProminent)
                .position(x: buttonOrigin.x + buttonSize.width / 2,
                          y: buttonOrigin.y + buttonSize.height / 2)
            }
            .onAppear { reposition(in: geo.size) }
            .onReceive(Timer.publish(every: burnInInterval, on: .main, in: .common).autoconnect()) { _ in
                reposition(in: geo.size)
            }
        }
    }

    private func reposition(in size: CGSize) {
        var rng = SystemRandomNumberGenerator()
        textOrigin = BurnIn.nextOrigin(container: size, label: textSize, using: &rng)
        buttonOrigin = BurnIn.nextOrigin(container: size, label: buttonSize, using: &rng)
    }
}
```

- [ ] **Step 2: Create `iUp/Features/Lock/OverlayWindowManager.swift`**

```swift
import AppKit
import SwiftUI

/// Creates one borderless shield-level window per screen and recreates them on
/// screen-parameter changes. `contentFactory` builds SwiftUI content per screen index.
final class OverlayWindowManager {
    private var windows: [NSWindow] = []
    private var screenObserver: Any?
    private var contentFactory: ((Int) -> AnyView)?
    private let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

    @discardableResult
    func showOverlay(contentFactory factory: @escaping (Int) -> AnyView) -> Bool {
        contentFactory = factory
        dismissOverlay()
        createWindows()
        guard !windows.isEmpty else { return false }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.recreate() }
        return true
    }

    func dismissOverlay() {
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        for w in windows { w.orderOut(nil); w.contentView = nil; w.close() }
        windows.removeAll()
    }

    private func recreate() {
        for w in windows { w.orderOut(nil); w.contentView = nil }
        windows.removeAll()
        createWindows()
    }

    private func createWindows() {
        guard let factory = contentFactory else { return }
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let w = NSWindow(contentRect: frame, styleMask: .borderless,
                             backing: .buffered, defer: false, screen: screen)
            w.setFrame(frame, display: true)
            w.level = shieldLevel
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            let host = NSHostingView(rootView: factory(index))
            host.autoresizingMask = [.width, .height]
            host.frame = w.contentLayoutRect
            w.contentView = host
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    deinit { dismissOverlay() }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add iUp/Features/Lock/OverlayWindowManager.swift iUp/Features/Lock/LockScreenView.swift
git commit -m "feat: overlay windows + lock screen view with burn-in repositioning"
```

---

### Task 14: AccessibilityChecker (shell)

**Files:**
- Create: `iUp/System/AccessibilityChecker.swift`

Reports/prompts Accessibility permission. Ported from `lockpaw/Lockpaw/Utilities/AccessibilityChecker.swift`. Build + manual verify.

- [ ] **Step 1: Create `iUp/System/AccessibilityChecker.swift`**

```swift
import Cocoa

enum AccessibilityChecker {
    static var isEnabled: Bool { AXIsProcessTrusted() }

    static func promptIfNeeded() {
        guard !isEnabled else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add iUp/System/AccessibilityChecker.swift
git commit -m "feat: AccessibilityChecker permission helper"
```

---

### Task 15: LockController (shell)

**Files:**
- Create: `iUp/Features/Lock/LockController.swift`

Coordinates lock/unlock using `LockState`, `OverlayWindowManager`, `InputBlocker`, `Authenticator`. Exposes hooks (`onDidLock`, `onWillUnlock`, `onLockedIdle`) so `DisplayController` can plug in later without a forward dependency. Adapted from `lockpaw/Lockpaw/Controllers/LockController.swift` (trimmed). Build + manual verify.

- [ ] **Step 1: Create `iUp/Features/Lock/LockController.swift`**

```swift
import AppKit
import SwiftUI
import os.log

@MainActor
final class LockController {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Lock")

    private(set) var state: LockState = .unlocked
    private let settings: Settings
    private let overlay = OverlayWindowManager()
    private let inputBlocker = InputBlocker()
    private let authenticator = Authenticator()

    /// Display hooks — bound by DisplayController in app wiring (Display phase).
    var onDidLock: (() -> Void)?
    var onWillUnlock: (() -> Void)?

    private var toggleObserver: Any?
    private var blockerFailObserver: Any?

    init(settings: Settings) {
        self.settings = settings
        toggleObserver = NotificationCenter.default.addObserver(
            forName: .iUpToggleLock, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
        }
        blockerFailObserver = NotificationCenter.default.addObserver(
            forName: .iUpInputBlockerFailed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forceUnlock() }
        }
    }

    deinit {
        if let o = toggleObserver { NotificationCenter.default.removeObserver(o) }
        if let o = blockerFailObserver { NotificationCenter.default.removeObserver(o) }
    }

    func toggle() {
        switch state {
        case .unlocked: lock()
        case .locked: requestUnlock()
        default: break
        }
    }

    func lock() {
        guard settings.lockEnabled else { return }
        guard state.canTransition(to: .locking) else { return }
        guard AccessibilityChecker.isEnabled else {
            AccessibilityChecker.promptIfNeeded(); return
        }
        state = .locking

        let msg = "iUp"
        let interval = settings.burnInInterval
        guard overlay.showOverlay(contentFactory: { [weak self] _ in
            AnyView(LockScreenView(message: msg, burnInInterval: interval) {
                self?.requestUnlock()
            })
        }) else {
            state = .unlocked
            return
        }
        inputBlocker.startBlocking()
        state = .locked
        onDidLock?()
    }

    func requestUnlock() {
        guard state == .locked, state.canTransition(to: .unlocking) else { return }
        state = .unlocking
        inputBlocker.stopBlocking()   // allow system auth dialog interaction
        Task { @MainActor in
            let ok = await authenticator.authenticate()
            if ok { completeUnlock() }
            else {
                inputBlocker.startBlocking()
                state = .locked
            }
        }
    }

    private func completeUnlock() {
        onWillUnlock?()
        overlay.dismissOverlay()
        inputBlocker.stopBlocking()
        state = .unlocked
    }

    private func forceUnlock() {
        onWillUnlock?()
        overlay.dismissOverlay()
        inputBlocker.stopBlocking()
        state = .unlocked
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED. (`AccessibilityChecker` from Task 14 must exist.)

- [ ] **Step 3: Commit**

```bash
git add iUp/Features/Lock/LockController.swift
git commit -m "feat: LockController coordinating overlay, input blocking, auth"
```

---

## Phase 6 — Display control (while locked)

### Task 16: DisplayController + BrightnessService

**Files:**
- Create: `iUp/Features/Display/DisplayController.swift`
- Create: `iUp/Features/Display/BrightnessService.swift`
- Test: `iUpTests/DisplayControllerTests.swift`

The controller's logic (guard on internal display, save/restore brightness, dim on lock + locked-idle, restore internal on activity, restore all on unlock, respect independent sub-toggles) is tested against a `DisplayBackend` fake. The private-API brightness/external implementation is a shell.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import iUp

private final class FakeDisplay: DisplayBackend {
    var hasInternalDisplay = true
    var internalBrightness: Float = 0.8
    var externalOn = true
    func getInternalBrightness() -> Float? { hasInternalDisplay ? internalBrightness : nil }
    func setInternalBrightness(_ v: Float) { internalBrightness = v }
    func setExternalDisplays(on: Bool) { externalOn = on }
}

struct DisplayControllerTests {
    private func make(internalDim: Bool = true, externalOff: Bool = true, dimIdle: TimeInterval = 60)
        -> (DisplayController, FakeDisplay, Settings) {
        let s = Settings(defaults: UserDefaults(suiteName: "iup.disp.\(UUID().uuidString)")!)
        s.displayInternalDim = internalDim; s.displayExternalOff = externalOff; s.displayDimIdle = dimIdle
        let b = FakeDisplay()
        return (DisplayController(settings: s, backend: b), b, s)
    }

    @Test func availableOnlyWithInternalDisplay() {
        let (c, b, _) = make()
        b.hasInternalDisplay = true
        #expect(c.isAvailable == true)
        b.hasInternalDisplay = false
        #expect(c.isAvailable == false)
    }

    @Test func lockSavesAndDimsAndTurnsOffExternal() {
        let (c, b, _) = make()
        b.internalBrightness = 0.7
        c.didLock()
        #expect(b.internalBrightness == 0)
        #expect(b.externalOn == false)
    }

    @Test func activityWhileLockedRestoresInternalOnly() {
        let (c, b, _) = make()
        b.internalBrightness = 0.7
        c.didLock()
        c.userActiveWhileLocked()
        #expect(b.internalBrightness == 0.7)   // restored
        #expect(b.externalOn == false)          // external stays off
    }

    @Test func lockedIdleReDims() {
        let (c, b, _) = make(dimIdle: 60)
        b.internalBrightness = 0.7
        c.didLock()
        c.userActiveWhileLocked()
        c.lockedTick(idle: 60)
        #expect(b.internalBrightness == 0)
    }

    @Test func unlockRestoresInternalAndExternal() {
        let (c, b, _) = make()
        b.internalBrightness = 0.6
        c.didLock()
        c.willUnlock()
        #expect(b.internalBrightness == 0.6)
        #expect(b.externalOn == true)
    }

    @Test func subTogglesIndependent() {
        let (c, b, _) = make(internalDim: false, externalOff: true)
        b.internalBrightness = 0.5
        c.didLock()
        #expect(b.internalBrightness == 0.5)   // internal dim disabled
        #expect(b.externalOn == false)          // external off still applies
    }

    @Test func noInternalDisplayIsNoOp() {
        let (c, b, _) = make()
        b.hasInternalDisplay = false
        c.didLock()
        #expect(b.externalOn == true)           // feature unavailable → nothing happens
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/DisplayControllerTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement `DisplayController` + `BrightnessService` shell**

`iUp/Features/Display/DisplayController.swift`:

```swift
import Foundation

protocol DisplayBackend: AnyObject {
    func getInternalBrightness() -> Float?   // nil if no internal display
    func setInternalBrightness(_ v: Float)
    func setExternalDisplays(on: Bool)
}

/// Manages displays while locked. Only acts when an internal display exists.
final class DisplayController {
    private let settings: Settings
    private let backend: DisplayBackend
    private var savedBrightness: Float?

    init(settings: Settings, backend: DisplayBackend) {
        self.settings = settings
        self.backend = backend
    }

    var isAvailable: Bool { backend.getInternalBrightness() != nil }

    func didLock() {
        guard settings.displayControlEnabled, isAvailable else { return }
        savedBrightness = backend.getInternalBrightness()
        if settings.displayInternalDim { backend.setInternalBrightness(0) }
        if settings.displayExternalOff { backend.setExternalDisplays(on: false) }
    }

    /// Real user input while locked → restore internal brightness only.
    func userActiveWhileLocked() {
        guard settings.displayControlEnabled, isAvailable, settings.displayInternalDim else { return }
        if let b = savedBrightness { backend.setInternalBrightness(b) }
    }

    /// Re-idle while locked → dim internal again.
    func lockedTick(idle: TimeInterval) {
        guard settings.displayControlEnabled, isAvailable, settings.displayInternalDim else { return }
        if idle >= settings.displayDimIdle { backend.setInternalBrightness(0) }
    }

    func willUnlock() {
        guard settings.displayControlEnabled, isAvailable else { return }
        if let b = savedBrightness { backend.setInternalBrightness(b) }
        if settings.displayExternalOff { backend.setExternalDisplays(on: true) }
        savedBrightness = nil
    }
}
```

`iUp/Features/Display/BrightnessService.swift` (shell — private API, manual verify):

```swift
import CoreGraphics
import os.log

/// Real display backend using the private DisplayServices framework for internal
/// brightness, with external-display mirroring/disable as best-effort.
/// PRD allows external control to no-op if infeasible.
///
/// DisplayServices is loaded dynamically (dlopen) to avoid a hard link dependency.
/// Symbols:
///   int DisplayServicesGetBrightness(CGDirectDisplayID, float*)
///   int DisplayServicesSetBrightness(CGDirectDisplayID, float)
final class BrightnessService: DisplayBackend {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Brightness")
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let getFn: GetFn?
    private let setFn: SetFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getFn = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
        setFn = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
    }

    private var internalDisplayID: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    func getInternalBrightness() -> Float? {
        guard let id = internalDisplayID, let getFn else { return nil }
        var value: Float = 0
        return getFn(id, &value) == 0 ? value : nil
    }

    func setInternalBrightness(_ v: Float) {
        guard let id = internalDisplayID, let setFn else { return }
        _ = setFn(id, max(0, min(1, v)))
    }

    func setExternalDisplays(on: Bool) {
        // Best-effort. PRD permits no-op if technically infeasible.
        // Implementation note: attempt CGConfigureDisplayMirrorOfDisplay or skip.
        Self.log.info("setExternalDisplays(on: \(on)) — best-effort no-op")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/DisplayControllerTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/Features/Display/ iUpTests/DisplayControllerTests.swift
git commit -m "feat: DisplayController dim/restore logic + brightness service shell"
```

---

## Phase 7 — System glue

### Task 17: HotkeyManager (shell)

**Files:**
- Create: `iUp/System/HotkeyManager.swift`

Global hotkey listener on a dedicated background-thread run loop (avoids LSUIElement main-runloop activation issue). Posts `.iUpToggleLock` for the lock hotkey. Ported from `lockpaw/Lockpaw/Controllers/HotkeyManager.swift`. Requires Accessibility. Build + manual verify.

- [ ] **Step 1: Create `iUp/System/HotkeyManager.swift`**

```swift
import Cocoa
import Carbon
import os.log

/// Listen-only event tap on a dedicated thread. Fires .iUpToggleLock when the
/// configured lock hotkey is pressed. Default: control+option+command+L.
final class HotkeyManager {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Hotkey")
    private var eventTap: CFMachPort?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private(set) var isRegistered = false

    var keyCode: Int = 37                                   // 'L'
    var modifiers: Int = cmdKey | optionKey | controlKey

    func register() {
        if isRegistered { if AXIsProcessTrusted() { return }; unregister() }
        guard AXIsProcessTrusted() else { Self.log.warning("no accessibility"); return }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: { _, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let me = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = me.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                guard keyCode == me.keyCode else { return Unmanaged.passUnretained(event) }
                var match = true
                let m = me.modifiers
                if m & cmdKey != 0 { match = match && flags.contains(.maskCommand) }
                if m & shiftKey != 0 { match = match && flags.contains(.maskShift) }
                if m & optionKey != 0 { match = match && flags.contains(.maskAlternate) }
                if m & controlKey != 0 { match = match && flags.contains(.maskControl) }
                if match {
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .iUpToggleLock, object: nil) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard eventTap != nil else { Self.log.error("tap failed"); return }

        let thread = Thread { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "moe.rewired.iUp.hotkey"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
        isRegistered = true
    }

    func unregister() {
        guard isRegistered else { return }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        tapRunLoop = nil; tapThread = nil; eventTap = nil; isRegistered = false
    }

    deinit { unregister() }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add iUp/System/HotkeyManager.swift
git commit -m "feat: global hotkey manager on dedicated thread"
```

---

### Task 18: LoginItem (shell)

**Files:**
- Create: `iUp/System/LoginItem.swift`
- Test: `iUpTests/LoginItemTests.swift`

Wraps `SMAppService.mainApp`. Pure mapping (`shouldBeEnabled` → register/unregister decision) is unit-tested; the actual `SMAppService` call is a shell guarded behind a protocol.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import iUp

private final class FakeRegistrar: LoginRegistrar {
    var registered = false
    func register() throws { registered = true }
    func unregister() throws { registered = false }
}

struct LoginItemTests {
    @Test func enableRegisters() throws {
        let r = FakeRegistrar()
        let item = LoginItem(registrar: r)
        try item.apply(enabled: true)
        #expect(r.registered == true)
    }
    @Test func disableUnregisters() throws {
        let r = FakeRegistrar()
        let item = LoginItem(registrar: r)
        try item.apply(enabled: true)
        try item.apply(enabled: false)
        #expect(r.registered == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/LoginItemTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement `LoginItem`**

```swift
import Foundation
import ServiceManagement

protocol LoginRegistrar {
    func register() throws
    func unregister() throws
}

struct SMLoginRegistrar: LoginRegistrar {
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

struct LoginItem {
    private let registrar: LoginRegistrar
    init(registrar: LoginRegistrar = SMLoginRegistrar()) { self.registrar = registrar }

    func apply(enabled: Bool) throws {
        if enabled { try registrar.register() } else { try registrar.unregister() }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests/LoginItemTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add iUp/System/LoginItem.swift iUpTests/LoginItemTests.swift
git commit -m "feat: launch-at-login via SMAppService"
```

---

## Phase 8 — UI + wiring

### Task 19: MenuBarController (shell)

**Files:**
- Create: `iUp/UI/MenuBarController.swift`

`NSStatusItem` dropdown bound to `SessionController.state`. Build + manual verify.

- [ ] **Step 1: Create `iUp/UI/MenuBarController.swift`**

```swift
import AppKit

/// Status-bar menu. Session item label reflects state; shows manual Resume when paused.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let session: SessionController
    private let lock: LockController

    private let sessionItem = NSMenuItem()
    private let resumeItem = NSMenuItem()
    private let stateLabelItem = NSMenuItem()

    init(session: SessionController, lock: LockController) {
        self.session = session
        self.lock = lock
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "iUp")
        buildMenu()
        session.onStateChange = { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func buildMenu() {
        let menu = NSMenu()
        stateLabelItem.isEnabled = false
        menu.addItem(stateLabelItem)
        menu.addItem(.separator())

        sessionItem.target = self
        sessionItem.action = #selector(toggleSession)
        menu.addItem(sessionItem)

        resumeItem.title = "Resume Session"
        resumeItem.target = self
        resumeItem.action = #selector(resumeSession)
        menu.addItem(resumeItem)

        let lockItem = NSMenuItem(title: "Lock", action: #selector(doLock), keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit iUp", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refresh() {
        switch session.state {
        case .off:
            stateLabelItem.title = "Session: Off"
            sessionItem.title = "Start Session"
            resumeItem.isHidden = true
        case .active:
            stateLabelItem.title = "Session: Active"
            sessionItem.title = "Stop Session"
            resumeItem.isHidden = true
        case .pausedByIdle:
            stateLabelItem.title = "Session: Paused (idle)"
            sessionItem.title = "Stop Session"
            resumeItem.isHidden = false
        }
    }

    @objc private func toggleSession() {
        if session.state == .off { session.start() } else { session.stop() }
    }
    @objc private func resumeSession() { session.resume() }
    @objc private func doLock() { lock.lock() }
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add iUp/UI/MenuBarController.swift
git commit -m "feat: status-bar menu bound to session state"
```

---

### Task 20: SettingsView (shell)

**Files:**
- Create: `iUp/UI/SettingsView.swift`
- Modify: `iUp/iUpApp.swift` (host SettingsView in the Settings scene)

SwiftUI form exposing every independent toggle + threshold. Reads/writes `Settings`. Build + manual verify.

- [ ] **Step 1: Create `iUp/UI/SettingsView.swift`**

```swift
import SwiftUI

/// All per-feature toggles and thresholds. Backed by a shared Settings instance.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            awakeTab.tabItem { Text("Awake") }
            jiggleTab.tabItem { Text("Activity") }
            pauseTab.tabItem { Text("Pause") }
            lockTab.tabItem { Text("Lock") }
            appTab.tabItem { Text("General") }
        }
        .frame(width: 420, height: 320)
        .padding()
    }

    private var awakeTab: some View {
        Form {
            Toggle("Enable keep-awake", isOn: $model.awakeEnabled)
            Toggle("Keep display on", isOn: $model.awakeDisplayOn).disabled(!model.awakeEnabled)
            Toggle("Prevent system sleep", isOn: $model.awakeSystemSleep).disabled(!model.awakeEnabled)
            Toggle("Keep network alive", isOn: $model.awakeNetworkOn).disabled(!model.awakeEnabled)
        }
    }
    private var jiggleTab: some View {
        Form {
            Toggle("Enable activity simulation", isOn: $model.jiggleEnabled)
            secondsRow("Start after idle", $model.jiggleIdleStart)
            secondsRow("Move every", $model.jiggleInterval)
            secondsRow("Stop after extra idle", $model.jiggleStopAfter)
        }
    }
    private var pauseTab: some View {
        Form {
            Toggle("Enable temporary pause", isOn: $model.tempPauseEnabled)
            secondsRow("Pause after idle", $model.tempPauseIdle)
        }
    }
    private var lockTab: some View {
        Form {
            Toggle("Enable lock", isOn: $model.lockEnabled)
            secondsRow("Burn-in reposition interval", $model.burnInInterval)
            Toggle("Control displays while locked", isOn: $model.displayControlEnabled)
            Toggle("Dim built-in display", isOn: $model.displayInternalDim).disabled(!model.displayControlEnabled)
            Toggle("Turn off external displays", isOn: $model.displayExternalOff).disabled(!model.displayControlEnabled)
            secondsRow("Re-dim after idle", $model.displayDimIdle).disabled(!model.displayControlEnabled)
        }
    }
    private var appTab: some View {
        Form {
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Toggle("Auto-start session on launch", isOn: $model.autoStartSession)
        }
    }

    private func secondsRow(_ label: String, _ value: Binding<TimeInterval>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: .number).frame(width: 70).multilineTextAlignment(.trailing)
            Text("s")
        }
    }
}
```

- [ ] **Step 2: Create `SettingsModel` (ObservableObject bridge) in `iUp/UI/SettingsView.swift`**

Append to the same file:

```swift
import Combine

/// Bridges Settings (UserDefaults) to SwiftUI bindings and applies side effects
/// (login item) on change.
final class SettingsModel: ObservableObject {
    private let settings: Settings
    private let loginItem: LoginItem

    init(settings: Settings, loginItem: LoginItem = LoginItem()) {
        self.settings = settings
        self.loginItem = loginItem
    }

    private func write<T>(_ kp: ReferenceWritableKeyPath<Settings, T>, _ v: T) {
        objectWillChange.send(); settings[keyPath: kp] = v
    }

    var awakeEnabled: Bool { get { settings.awakeEnabled } set { write(\.awakeEnabled, newValue) } }
    var awakeDisplayOn: Bool { get { settings.awakeDisplayOn } set { write(\.awakeDisplayOn, newValue) } }
    var awakeSystemSleep: Bool { get { settings.awakeSystemSleep } set { write(\.awakeSystemSleep, newValue) } }
    var awakeNetworkOn: Bool { get { settings.awakeNetworkOn } set { write(\.awakeNetworkOn, newValue) } }
    var jiggleEnabled: Bool { get { settings.jiggleEnabled } set { write(\.jiggleEnabled, newValue) } }
    var jiggleIdleStart: TimeInterval { get { settings.jiggleIdleStart } set { write(\.jiggleIdleStart, newValue) } }
    var jiggleInterval: TimeInterval { get { settings.jiggleInterval } set { write(\.jiggleInterval, newValue) } }
    var jiggleStopAfter: TimeInterval { get { settings.jiggleStopAfter } set { write(\.jiggleStopAfter, newValue) } }
    var tempPauseEnabled: Bool { get { settings.tempPauseEnabled } set { write(\.tempPauseEnabled, newValue) } }
    var tempPauseIdle: TimeInterval { get { settings.tempPauseIdle } set { write(\.tempPauseIdle, newValue) } }
    var displayControlEnabled: Bool { get { settings.displayControlEnabled } set { write(\.displayControlEnabled, newValue) } }
    var displayDimIdle: TimeInterval { get { settings.displayDimIdle } set { write(\.displayDimIdle, newValue) } }
    var displayInternalDim: Bool { get { settings.displayInternalDim } set { write(\.displayInternalDim, newValue) } }
    var displayExternalOff: Bool { get { settings.displayExternalOff } set { write(\.displayExternalOff, newValue) } }
    var lockEnabled: Bool { get { settings.lockEnabled } set { write(\.lockEnabled, newValue) } }
    var burnInInterval: TimeInterval { get { settings.burnInInterval } set { write(\.burnInInterval, newValue) } }
    var autoStartSession: Bool { get { settings.autoStartSession } set { write(\.autoStartSession, newValue) } }
    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set { write(\.launchAtLogin, newValue); try? loginItem.apply(enabled: newValue) }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED. (Wired into the Settings scene in Task 21.)

- [ ] **Step 4: Commit**

```bash
git add iUp/UI/SettingsView.swift
git commit -m "feat: settings UI exposing all independent feature toggles"
```

---

### Task 21: AppDelegate integration + monitoring tap + run loop

**Files:**
- Create: `iUp/System/InputObservationTap.swift`
- Modify: `iUp/AppDelegate.swift`
- Modify: `iUp/iUpApp.swift`

Wires the whole graph: builds controllers, installs the listen-only monitoring tap feeding `ActivityMonitor.record`, runs a 0.25s `DispatchSourceTimer` calling `monitor.tick()`, observes system sleep/wake, binds Display hooks into Lock, registers the hotkey, applies launch-options. Shell — end-to-end manual verification.

- [ ] **Step 1: Create `iUp/System/InputObservationTap.swift`**

```swift
import Cocoa
import os.log

/// Listen-only session tap observing all mouse/keyboard input. For each event it
/// calls `onEvent(isSynthetic:)`. Synthetic = events iUp itself posted (tagged).
/// Runs on a dedicated thread to avoid the LSUIElement main-runloop activation issue.
final class InputObservationTap {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "InputObs")
    private var eventTap: CFMachPort?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private let onEvent: (_ isSynthetic: Bool) -> Void

    init(onEvent: @escaping (_ isSynthetic: Bool) -> Void) { self.onEvent = onEvent }

    private static let mask: CGEventMask = {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                    .leftMouseDragged, .rightMouseDragged, .scrollWheel,
                                    .keyDown, .flagsChanged, .tabletPointer]
        return types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    }()

    func start() {
        guard AXIsProcessTrusted() else { Self.log.warning("no accessibility"); return }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: Self.mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<InputObservationTap>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = me.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                me.onEvent(event.isSyntheticFromiUp)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard eventTap != nil else { Self.log.error("tap failed"); return }
        let t = Thread { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            self.runLoop = CFRunLoopGetCurrent()
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        t.name = "moe.rewired.iUp.inputobs"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = runLoop { CFRunLoopStop(rl) }
        eventTap = nil; runLoop = nil; thread = nil
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Replace `iUp/AppDelegate.swift` with full wiring**

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()

    private lazy var monitor = ActivityMonitor()
    private lazy var awake = AwakeController(settings: settings, assertions: IOPMAssertions())
    private lazy var jiggle: JiggleController = {
        // Bursts run off the main thread (postBurst blocks ~0.5s).
        JiggleController(settings: settings, poster: BackgroundPoster(CGMovePoster()))
    }()
    private lazy var session = SessionController(settings: settings, awake: awake, jiggle: jiggle)
    private lazy var lock = LockController(settings: settings)
    private lazy var display = DisplayController(settings: settings, backend: BrightnessService())
    private lazy var hotkey = HotkeyManager()
    private var menuBar: MenuBarController?

    private var inputTap: InputObservationTap?
    private var tickTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AccessibilityChecker.promptIfNeeded()

        // Activity clock callbacks.
        monitor.onUserBecameActive = { [weak self] in
            guard let self else { return }
            self.session.userBecameActive()
            if self.lock.state == .locked { self.display.userActiveWhileLocked() }
        }
        monitor.onTick = { [weak self] idle in
            guard let self else { return }
            self.session.tick(idle: idle)
            if self.lock.state == .locked { self.display.lockedTick(idle: idle) }
        }

        // Bind display into lock lifecycle.
        lock.onDidLock = { [weak self] in self?.display.didLock() }
        lock.onWillUnlock = { [weak self] in self?.display.willUnlock() }

        // Monitoring tap feeds the clock.
        inputTap = InputObservationTap { [weak self] isSynthetic in
            DispatchQueue.main.async { self?.monitor.record(isSynthetic: isSynthetic) }
        }
        inputTap?.start()

        // 0.25s tick.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.monitor.tick() }
        timer.resume()
        tickTimer = timer

        // Sleep/wake → resume session if it was paused.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.session.systemDidWake() } }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.session.systemDidWake() } }

        // Session toggle from hotkey.
        NotificationCenter.default.addObserver(
            forName: .iUpToggleSession, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.session.state == .off { self.session.start() } else { self.session.stop() }
            }
        }

        hotkey.register()
        menuBar = MenuBarController(session: session, lock: lock)

        if settings.autoStartSession { session.start() }
    }
}

/// Runs a MovePosting on a background queue so the ~0.5s burst never stalls the main thread.
final class BackgroundPoster: MovePosting {
    private let wrapped: MovePosting
    private let queue = DispatchQueue(label: "moe.rewired.iUp.jiggle", qos: .userInitiated)
    init(_ wrapped: MovePosting) { self.wrapped = wrapped }
    func postBurst() { queue.async { self.wrapped.postBurst() } }
}
```

- [ ] **Step 3: Wire SettingsView into the Settings scene in `iUp/iUpApp.swift`**

```swift
import SwiftUI

@main
struct iUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: SettingsModel(settings: appDelegate.settings))
        }
    }
}
```

- [ ] **Step 4: Build and run end-to-end**

Run: `xcodebuild build -scheme iUp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

Manual verification checklist (grant Accessibility when prompted, then relaunch):
- Menu bar icon appears; no Dock icon.
- "Start Session" → Mac stays awake (check `pmset -g assertions` shows iUp assertions).
- Idle past `jiggleIdleStart` → cursor jiggles; real mouse move stops reset; jiggle stops after `jiggleIdleStart + jiggleStopAfter`.
- Idle past `tempPauseIdle` → menu shows "Paused (idle)", assertions released; moving mouse or waking resumes; "Resume Session" works.
- "Lock" or `⌃⌥⌘L` → black overlay on all screens, input blocked, text + button reposition; Touch ID / `⌃⌥⌘L` unlocks; built-in brightness drops to 0 and restores.
- Toggle each feature off in Settings → that feature stops, others keep working.
- "Launch at login" → appears in System Settings > General > Login Items.

- [ ] **Step 5: Commit**

```bash
git add iUp/System/InputObservationTap.swift iUp/AppDelegate.swift iUp/iUpApp.swift
git commit -m "feat: wire full controller graph, monitoring tap, tick timer"
```

---

## Final verification

- [ ] Run the whole suite: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests` — all suites PASS.
- [ ] Build clean: `xcodebuild build -scheme iUp -destination 'platform=macOS'` — BUILD SUCCEEDED.
- [ ] Complete the manual checklist in Task 21 Step 4.
- [ ] Verify code signing / notarization settings for Developer ID distribution (out of scope for tasks; confirm before release).


