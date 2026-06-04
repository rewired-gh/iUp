import Testing
import Foundation
@testable import iUp

private final class FakeDisplay: DisplayBackend {
    var hasInternalDisplay = true
    var internalBrightness: Float = 0.8
    func getInternalBrightness() -> Float? { hasInternalDisplay ? internalBrightness : nil }
    func setInternalBrightness(_ v: Float) { internalBrightness = v }
}

struct DisplayControllerTests {
    private func make(internalDim: Bool = true) -> (DisplayController, FakeDisplay, Settings) {
        let s = Settings(defaults: UserDefaults(suiteName: "iup.disp.\(UUID().uuidString)")!)
        s.displayInternalDim = internalDim
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

    @Test func lockDimsToZero() {
        let (c, b, _) = make()
        b.internalBrightness = 0.7
        c.didLock()
        #expect(b.internalBrightness == 0)
        #expect(c.isDimmed == true)
    }

    @Test func dimDisabledDoesNotDim() {
        let (c, b, _) = make(internalDim: false)
        b.internalBrightness = 0.5
        c.didLock()
        #expect(b.internalBrightness == 0.5)
        #expect(c.isDimmed == false)
    }

    @Test func unlockDoesNotRestoreBrightness() {
        let (c, b, _) = make()
        b.internalBrightness = 0.6
        c.didLock()
        #expect(b.internalBrightness == 0)
        c.willUnlock()
        #expect(b.internalBrightness == 0)   // left dimmed; user restores manually
        #expect(c.isDimmed == false)
    }

    @Test func noInternalDisplayIsNoOp() {
        let (c, b, _) = make()
        b.hasInternalDisplay = false
        b.internalBrightness = 0.9
        c.didLock()
        #expect(b.internalBrightness == 0.9)
        #expect(c.isDimmed == false)
    }

    @Test func dimIssuedAtMostOnce() {
        let (c, b, _) = make()
        c.didLock()
        b.internalBrightness = 0.4   // simulate user nudging brightness while locked
        c.reapplyWhileLocked()
        #expect(b.internalBrightness == 0.4)   // already dimmed → not re-driven
    }

    @Test func reapplyEnablingDimMidLockDims() {
        let (c, b, s) = make(internalDim: false)
        b.internalBrightness = 0.5
        c.didLock()                 // dim off → untouched
        #expect(b.internalBrightness == 0.5)
        s.displayInternalDim = true
        c.reapplyWhileLocked()
        #expect(b.internalBrightness == 0)
    }
}
