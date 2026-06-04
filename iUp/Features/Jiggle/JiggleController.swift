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
