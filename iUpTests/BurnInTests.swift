import Testing
import CoreGraphics
@testable import iUp

struct BurnInTests {
    private let container = CGSize(width: 1000, height: 800)
    private let label = CGSize(width: 200, height: 60)

    @Test func originKeepsLabelInside() {
        var rng = SeededRNG(seed: 5)
        for _ in 0..<500 {
            let o = BurnIn.nextOrigin(container: container, label: label, using: &rng)
            #expect(o.x >= 0 && o.x <= container.width - label.width)
            #expect(o.y >= 0 && o.y <= container.height - label.height)
        }
    }

    @Test func coversAllGridCells() {
        var rng = SeededRNG(seed: 123)
        let cols = 4, rows = 4
        var hit = Set<Int>()
        for _ in 0..<5000 {
            let o = BurnIn.nextOrigin(container: container, label: label, using: &rng)
            let cx = o.x + label.width / 2
            let cy = o.y + label.height / 2
            let col = min(cols - 1, Int(cx / (container.width / CGFloat(cols))))
            let row = min(rows - 1, Int(cy / (container.height / CGFloat(rows))))
            hit.insert(row * cols + col)
        }
        #expect(hit.count == cols * rows)
    }

    @Test func degenerateLabelLargerThanContainer() {
        var rng = SeededRNG(seed: 1)
        let o = BurnIn.nextOrigin(container: CGSize(width: 100, height: 100),
                                  label: CGSize(width: 200, height: 200), using: &rng)
        #expect(o == .zero)
    }
}
