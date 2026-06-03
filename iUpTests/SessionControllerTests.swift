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
        #expect(a.active == false)
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
        c.tick(idle: 30)
        #expect(j.lastIdle == nil)
        c.start(); c.tick(idle: 60)
        j.lastIdle = nil
        c.tick(idle: 70)
        #expect(j.lastIdle == nil)
    }
}
