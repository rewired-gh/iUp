import CoreGraphics

/// How far simulated cursor activity may roam from where the cursor sat when a
/// burst began. The walk is confined to a per-axis radius around that origin,
/// from the slightest 1 px nudge up to a wide — but still bounded — wander.
enum JiggleLevel: String, CaseIterable, Identifiable {
    case slightest, low, medium, high, full

    var id: String { rawValue }

    /// Per-axis radius, in points, the cursor stays within during a burst.
    var radius: CGFloat {
        switch self {
        case .slightest: 1
        case .low:       10
        case .medium:    20
        case .high:      30
        case .full:      40
        }
    }

    var title: String {
        switch self {
        case .slightest: "Slightest"
        case .low:       "Low"
        case .medium:    "Medium"
        case .high:      "High"
        case .full:      "Maximum"
        }
    }
}
