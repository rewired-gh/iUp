import Foundation

/// Abstracts a monotonic time source so timing logic is testable without real time.
///
/// `uptime` is monotonic seconds (never goes backwards, unaffected by wall-clock /
/// NTP changes), so idle measurement stays correct over very long runtimes. It is a
/// `Double`, so it does not overflow (unlike integer tick counters).
protocol Clock {
    var uptime: TimeInterval { get }
}

struct SystemClock: Clock {
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Test/double clock whose time is set manually.
final class ManualClock: Clock {
    var uptime: TimeInterval
    init(_ start: TimeInterval = 1_000) { uptime = start }
    func advance(_ seconds: TimeInterval) { uptime += seconds }
}
