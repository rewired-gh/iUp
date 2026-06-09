import CoreGraphics

/// How far simulated cursor activity may roam from where the cursor sat when a
/// burst began. The walk is confined to a per-axis radius around that origin;
/// `.full` is effectively unbounded — the classic whole-screen wander, and the
/// default (matching the original behavior).
enum JiggleLevel: String, CaseIterable, Identifiable {
    case slightest, low, medium, high, full

    var id: String { rawValue }

    /// Per-axis radius, in points, the cursor stays within during a burst.
    /// `.full` returns an effectively unbounded radius so the walk roams the
    /// whole screen (bounded only by the display edges).
    var radius: CGFloat {
        switch self {
        case .slightest: 1
        case .low:       10
        case .medium:    40
        case .high:      120
        case .full:      .greatestFiniteMagnitude
        }
    }

    var title: String {
        switch self {
        case .slightest: "Slightest (1 px)"
        case .low:       "Low"
        case .medium:    "Medium"
        case .high:      "High"
        case .full:      "Maximum (full screen)"
        }
    }
}
