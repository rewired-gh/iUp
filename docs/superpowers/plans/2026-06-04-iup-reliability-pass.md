# iUp Reliability Pass — Plan

Fixes from user testing. Three independent areas. TDD where logic is testable; build + manual verify for shells. Test cmd: `xcodebuild test -scheme iUp -destination 'platform=macOS' -only-testing:iUpTests`.

---

## Task A — Cursor jiggle is broken (coordinate space). Learn from Jiggler.

**Root cause:** `CGMovePoster` feeds `NSScreen.frame` (Cocoa coords: origin bottom-left, y-up) into `JiggleMath`, but posts `CGEvent` mouse positions in **global display coords** (origin top-left, y-down). Containment checks and posted points are in the wrong space → moves land wrong / off-screen / get rejected (worst on multi-monitor and vertically). `currentCursorCG()` flips using `screens.first.frame.height`, which isn't necessarily the main display and double-confuses things.

**Jiggler reference** (`Jiggler/AppDelegate.m` `_jiggleMouse`): works entirely in CG coords (`kCGEventSourceStateHIDSystemState`, suppression interval 0, `CGEventPost(kCGHIDEventTap, ...)`, positions kept inside screen rects converted to CG space, avoids exact same point).

**Fix:** operate entirely in CG/global-display coordinates — no Cocoa conversion at all.
- Current cursor: `CGEvent(source: nil)?.location` (already CG top-left).
- Screen rects: `CGGetActiveDisplayList` + `CGDisplayBounds(id)` (already CG top-left) — not `NSScreen.frame`.
- Feed those to `JiggleMath.nextPoint` (pure, coordinate-agnostic — unchanged).
- Post `mouseMoved` via `CGEvent(mouseEventSource:)`, tag synthetic, suppression 0, `.cghidEventTap`.

**File:** `iUp/Features/Jiggle/JiggleController.swift` — rewrite `CGMovePoster` only. `JiggleMath` + `JiggleController` + tests unchanged. Shell → build + manual verify (no unit test; `JiggleMath` already tested).

Replacement `CGMovePoster`:

```swift
import CoreGraphics
import AppKit

/// Real CGEvent-posting burst, in global display (CG, top-left origin) coordinates
/// throughout — matching how mouse events are posted. Mirrors Jiggler's approach.
/// Shell: verified by build + manual run.
final class CGMovePoster: MovePosting {
    func postBurst() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let old = source.localEventsSuppressionInterval
        source.localEventsSuppressionInterval = 0
        defer { source.localEventsSuppressionInterval = old }

        let screens = Self.activeDisplayBounds()
        guard !screens.isEmpty else { return }
        var rng = SystemRandomNumberGenerator()
        var current = CGEvent(source: nil)?.location ?? CGPoint(x: screens[0].midX, y: screens[0].midY)

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
    }

    /// Active displays' bounds in global CG coordinates (top-left origin) — the same
    /// space CGEvent mouse positions use.
    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map { CGDisplayBounds($0) }
    }
}
```

---

## Task B — Touch ID prompt reveals the menu bar. Learn from Lockpaw.

**Root cause:** `OverlayWindowManager.lowerForAuth()` drops windows to `.normal`, which is **below the menu bar**, so the menu bar appears during authentication. Lockpaw lowers to `.statusBar` (`OverlayWindowManager.allowSystemDialogs`), which still covers the menu bar while the Touch ID/password panel renders above it.

**Fix:** in `iUp/Features/Lock/OverlayWindowManager.swift`, `lowerForAuth()` set `w.level = .statusBar` instead of `.normal`. `raiseShield()` unchanged (back to shield level).

```swift
func lowerForAuth() {
    for w in windows { w.level = .statusBar }
}
```

Shell → build + manual verify.

---

## Task C — Settings must auto-save and apply immediately, resetting state where needed.

Settings already persist immediately (UserDefaults). Gap: live features don't re-read until their next natural cycle, and some hold state. Make changes apply now.

### C1 — Broadcast changes
`iUp/Core/Notifications.swift`: add `static let iUpSettingsChanged = Notification.Name("iUp.settingsChanged")`.

`iUp/UI/SettingsView.swift` `SettingsModel.write(_:_:)`: after writing, post it:
```swift
private func write<T>(_ kp: ReferenceWritableKeyPath<Settings, T>, _ v: T) {
    objectWillChange.send()
    settings[keyPath: kp] = v
    NotificationCenter.default.post(name: .iUpSettingsChanged, object: nil)
}
```

### C2 — AwakeController can re-apply live (TDD)
`iUp/Features/Awake/AwakeController.swift`: add
```swift
/// Re-apply assertions to match the current toggles, while active. Releases all
/// if keep-awake was turned off. No-op when inactive.
func reapply() {
    guard isActive else { return }
    assertions.releaseAll()
    guard settings.awakeEnabled else { return }
    if settings.awakeDisplayOn { assertions.hold(.displaySleep) }
    if settings.awakeSystemSleep { assertions.hold(.systemSleep) }
    if settings.awakeNetworkOn { assertions.hold(.network) }
}
```
Tests in `iUpTests/AwakeControllerTests.swift`:
- `reapplyAddsNewlyEnabledAssertion`: activate with network off → held == [display,system]; set awakeNetworkOn true; reapply → held == [display,system,network].
- `reapplyRemovesDisabledAssertion`: activate all; set awakeDisplayOn false; reapply → held == [system,network].
- `reapplyWhenInactiveIsNoOp`: don't activate; set toggles; reapply → held empty.

### C3 — DisplayController can reconcile during a lock (TDD)
`iUp/Features/Display/DisplayController.swift`: add
```swift
/// Reconcile displays to current settings while locked (e.g. user toggled
/// display control or its sub-options from Settings mid-lock).
func reapplyWhileLocked() {
    guard isAvailable else { return }
    if !settings.displayControlEnabled {
        if let b = savedBrightness { backend.setInternalBrightness(b) }
        backend.setExternalDisplays(on: true)
        savedBrightness = nil
        return
    }
    if settings.displayInternalDim {
        if savedBrightness == nil { savedBrightness = backend.getInternalBrightness() }
        backend.setInternalBrightness(0)
    } else if let b = savedBrightness {
        backend.setInternalBrightness(b)
        savedBrightness = nil
    }
    backend.setExternalDisplays(on: !settings.displayExternalOff)
}
```
Tests in `iUpTests/DisplayControllerTests.swift`:
- `reapplyDisablingControlRestores`: didLock (dim+ext off); set displayControlEnabled false; reapplyWhileLocked → brightness restored, external on.
- `reapplyTurningInternalDimOffRestores`: didLock; set displayInternalDim false; reapplyWhileLocked → brightness restored; external still off.
- `reapplyEnablingInternalDimDims`: settings internalDim false at lock (brightness untouched, saved); then set true; reapplyWhileLocked → brightness 0.

### C4 — Coordinator reconciles on change
`iUp/AppDelegate.swift`: observe `.iUpSettingsChanged` (main queue, weak self, MainActor.assumeIsolated) and:
```swift
private func reconcileSettings() {
    if session.state == .active {
        awake.reapply()
        jiggle.reset()   // pick up new thresholds cleanly on next tick
    }
    if lock.state == .locked || lock.state == .unlocking {
        display.reapplyWhileLocked()
    }
}
```
Register the observer in `applicationDidFinishLaunching` alongside the others. Remove-on-deinit not required (immortal delegate), consistent with existing observers.

---

## Verification
- `xcodebuild test ... -only-testing:iUpTests` → all suites pass (new Awake + Display tests included).
- `xcodebuild build` → BUILD SUCCEEDED.
- Manual: jiggle visibly moves cursor when idle (single + multi-monitor); Touch ID prompt shows no menu bar; toggling awake sub-options / display options live takes effect immediately.
