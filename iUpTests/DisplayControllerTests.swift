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
        #expect(b.internalBrightness == 0.7)
        #expect(b.externalOn == false)
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
        #expect(b.internalBrightness == 0.5)
        #expect(b.externalOn == false)
    }

    @Test func noInternalDisplayIsNoOp() {
        let (c, b, _) = make()
        b.hasInternalDisplay = false
        c.didLock()
        #expect(b.externalOn == true)
    }
}
