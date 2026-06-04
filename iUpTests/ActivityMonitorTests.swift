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

    @Test func idleNeverNegativeIfClockGoesBackward() {
        let clock = ManualClock()
        let m = ActivityMonitor(clock: clock)
        m.record(isSynthetic: false)
        clock.advance(-50)   // defensive: clock should be monotonic, but never report negative idle
        #expect(m.idle == 0)
    }

    @Test func resetIdleClearsIdleWithoutFiringActive() {
        let clock = ManualClock()
        let m = ActivityMonitor(clock: clock)
        var activeCount = 0
        m.onUserBecameActive = { activeCount += 1 }
        clock.advance(120)
        #expect(m.idle == 120)
        m.resetIdle()
        #expect(m.idle == 0)
        #expect(activeCount == 0)
    }

    @Test func syntheticInputDoesNotResetIdle() {
        let clock = ManualClock()
        let m = ActivityMonitor(clock: clock)
        m.record(isSynthetic: false)
        clock.advance(10)
        m.record(isSynthetic: true)
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
