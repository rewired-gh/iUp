import Foundation

/// Single source of truth for the user-activity clock.
/// Real input updates `lastRealInputDate`; synthetic (iUp-generated) input is ignored.
/// A periodic `tick()` (driven by a DispatchSourceTimer in production) recomputes idle
/// and notifies subscribers. The real CGEventTap installation lives in app wiring; here
/// `record(isSynthetic:)` is the testable entry point the tap callback calls.
final class ActivityMonitor {
    private let clock: Clock
    private(set) var lastRealInputUptime: TimeInterval

    /// Called once each time real user input arrives after a period (every real event).
    var onUserBecameActive: (() -> Void)?
    /// Called each tick with the current idle interval.
    var onTick: ((TimeInterval) -> Void)?

    init(clock: Clock = SystemClock()) {
        self.clock = clock
        self.lastRealInputUptime = clock.uptime
    }

    /// Seconds since the last real input. Clamped to ≥ 0 (monotonic clock should
    /// never go backwards, but stay defensive).
    var idle: TimeInterval { max(0, clock.uptime - lastRealInputUptime) }

    /// Entry point invoked by the event-tap callback for every observed event.
    func record(isSynthetic: Bool) {
        guard !isSynthetic else { return }
        lastRealInputUptime = clock.uptime
        onUserBecameActive?()
    }

    func tick() { onTick?(idle) }

    /// Reset the idle clock to now without firing callbacks. Used when input
    /// monitoring begins (e.g. Accessibility just granted) so a stale
    /// launch-time timestamp doesn't make the session look idle immediately.
    func resetIdle() { lastRealInputUptime = clock.uptime }
}
