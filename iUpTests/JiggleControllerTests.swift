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
        c.evaluate(idle: 60)
        #expect(c.isJiggling == true)
        #expect(p.burstCount == 1)
        c.evaluate(idle: 75)
        #expect(p.burstCount == 1)
        c.evaluate(idle: 90)
        #expect(p.burstCount == 2)
    }

    @Test func stopsAfterIdleStartPlusStopAfter() {
        let p = FakePoster()
        let c = JiggleController(settings: settings(), poster: p)
        c.evaluate(idle: 60)
        c.evaluate(idle: 360)
        #expect(c.isJiggling == false)
        let before = p.burstCount
        c.evaluate(idle: 400)
        #expect(p.burstCount == before)
    }

    @Test func resetReturnsToIdleState() {
        let p = FakePoster()
        let c = JiggleController(settings: settings(), poster: p)
        c.evaluate(idle: 90)
        c.reset()
        #expect(c.isJiggling == false)
        c.evaluate(idle: 60)
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
