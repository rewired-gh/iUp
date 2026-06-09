import Testing
import CoreGraphics
@testable import iUp

struct JiggleMathTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    // Effectively unbounded radius — exercises the classic whole-screen wander.
    private let unbounded = CGFloat.greatestFiniteMagnitude

    @Test func resultIsInsideScreenInset() {
        var rng = SeededRNG(seed: 42)
        for _ in 0..<200 {
            let p = JiggleMath.nextPoint(from: CGPoint(x: 500, y: 500),
                                         avoiding: CGPoint(x: -1, y: -1),
                                         origin: CGPoint(x: 500, y: 500),
                                         screens: [screen], tolerance: 30,
                                         radius: unbounded, inset: 3, using: &rng)!
            #expect(p.x >= 3 && p.x <= 997)
            #expect(p.y >= 3 && p.y <= 997)
        }
    }

    @Test func resultNeverEqualsAvoidPoint() {
        var rng = SeededRNG(seed: 7)
        let avoid = CGPoint(x: 500, y: 500)
        for _ in 0..<200 {
            let p = JiggleMath.nextPoint(from: CGPoint(x: 500, y: 500),
                                         avoiding: avoid, origin: avoid, screens: [screen],
                                         tolerance: 30, radius: unbounded, inset: 3, using: &rng)!
            #expect(!(p.x == avoid.x && p.y == avoid.y))
        }
    }

    @Test func staysWithinToleranceDrift() {
        var rng = SeededRNG(seed: 99)
        let from = CGPoint(x: 500, y: 500)
        let p = JiggleMath.nextPoint(from: from, avoiding: .zero, origin: from,
                                     screens: [screen], tolerance: 30,
                                     radius: unbounded, inset: 3, using: &rng)!
        #expect(abs(p.x - from.x) <= 30)
        #expect(abs(p.y - from.y) <= 30)
    }

    @Test func returnsNilWhenNoScreens() {
        var rng = SeededRNG(seed: 1)
        let p = JiggleMath.nextPoint(from: .zero, avoiding: .zero, origin: .zero,
                                     screens: [], tolerance: 30, radius: unbounded,
                                     inset: 3, using: &rng)
        #expect(p == nil)
    }

    @Test func confinesWalkWithinRadiusOfOrigin() {
        var rng = SeededRNG(seed: 123)
        let origin = CGPoint(x: 500, y: 500)
        var current = origin
        // Walk many steps; every point must stay within the radius of the origin,
        // not merely within a per-step tolerance of the previous point.
        for _ in 0..<200 {
            let p = JiggleMath.nextPoint(from: current, avoiding: current, origin: origin,
                                         screens: [screen], tolerance: 30,
                                         radius: 1, inset: 3, using: &rng)!
            #expect(abs(p.x - origin.x) <= 1)
            #expect(abs(p.y - origin.y) <= 1)
            current = p
        }
    }
}
