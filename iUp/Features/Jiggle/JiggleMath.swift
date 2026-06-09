import CoreGraphics

/// Deterministic RNG for testable jiggle math (SplitMix64).
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum JiggleMath {
    /// Pick a new cursor point near `from`, stepping at most `tolerance` on each
    /// axis, while keeping the total per-axis displacement from `origin` within
    /// `radius` (so low jiggle levels stay near where the burst began). The point
    /// must sit inside one of `screens` (inset from edges) and never equal
    /// `avoiding`. Returns nil if no screens or no valid point found.
    static func nextPoint<R: RandomNumberGenerator>(
        from: CGPoint, avoiding: CGPoint, origin: CGPoint, screens: [CGRect],
        tolerance: CGFloat, radius: CGFloat, inset: CGFloat, using rng: inout R
    ) -> CGPoint? {
        guard !screens.isEmpty else { return nil }
        let insetScreens = screens.map { $0.insetBy(dx: inset, dy: inset) }
        // A single step can never need to exceed the radius it's confined to.
        let step = min(tolerance, radius)

        for attempt in 0..<100 {
            let t = attempt < 20 ? step : step + CGFloat(attempt - 20)
            let dx = CGFloat(Int.random(in: Int(-t)...Int(t), using: &rng))
            let dy = CGFloat(Int.random(in: Int(-t)...Int(t), using: &rng))
            let candidate = CGPoint(x: from.x + dx, y: from.y + dy)
            if candidate == avoiding { continue }
            if abs(candidate.x - origin.x) > radius || abs(candidate.y - origin.y) > radius { continue }
            if insetScreens.contains(where: { $0.contains(candidate) }) {
                return candidate
            }
        }
        return nil
    }
}
