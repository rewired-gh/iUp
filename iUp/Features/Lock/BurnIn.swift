import CoreGraphics

enum BurnIn {
    /// Uniform-random top-left origin so the label stays fully inside the container.
    /// Clamps to .zero when the label does not fit.
    static func nextOrigin<R: RandomNumberGenerator>(
        container: CGSize, label: CGSize, using rng: inout R
    ) -> CGPoint {
        let maxX = container.width - label.width
        let maxY = container.height - label.height
        guard maxX > 0, maxY > 0 else { return .zero }
        let x = CGFloat.random(in: 0...maxX, using: &rng)
        let y = CGFloat.random(in: 0...maxY, using: &rng)
        return CGPoint(x: x, y: y)
    }
}
