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
