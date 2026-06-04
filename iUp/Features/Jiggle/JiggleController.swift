import CoreGraphics
import AppKit

protocol MovePosting {
    /// Post a single ~0.5s continuous synthetic move burst (tagged synthetic).
    func postBurst()
}

/// Drives jiggling from the shared idle clock.
/// Start at idle >= jiggleIdleStart; burst every jiggleInterval thereafter.
/// Jiggling stops only on real input or when the session pauses — both call `reset()`.
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
        guard idle >= settings.jiggleIdleStart else { isJiggling = false; return }

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

/// Real CGEvent-posting burst, in global display (CG, top-left origin) coordinates
/// throughout — matching how mouse events are posted. Mirrors Jiggler's approach.
/// Shell: verified by build + manual run.
final class CGMovePoster: MovePosting {
    /// A burst is ~0.5s of motion: `stepCount` moves spaced `stepDelay` apart.
    private static let stepCount = 35
    private static let stepDelayMicros: UInt32 = 14_000
    private static let driftTolerance: CGFloat = 30   // max per-axis drift per step (points)
    private static let screenInset: CGFloat = 3       // keep off the very edge

    func postBurst() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let old = source.localEventsSuppressionInterval
        source.localEventsSuppressionInterval = 0
        defer { source.localEventsSuppressionInterval = old }

        let screens = Self.activeDisplayBounds()
        guard !screens.isEmpty else { return }
        var rng = SystemRandomNumberGenerator()
        var current = CGEvent(source: nil)?.location ?? CGPoint(x: screens[0].midX, y: screens[0].midY)

        for i in 0..<Self.stepCount {
            guard let next = JiggleMath.nextPoint(from: current, avoiding: current,
                                                  screens: screens, tolerance: Self.driftTolerance,
                                                  inset: Self.screenInset, using: &rng) else { break }
            let e = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                            mouseCursorPosition: next, mouseButton: .left)
            e?.tagAsSynthetic()
            e?.post(tap: .cghidEventTap)
            current = next
            if i < Self.stepCount - 1 { usleep(Self.stepDelayMicros) }
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
