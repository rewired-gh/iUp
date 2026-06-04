import Foundation

extension Notification.Name {
    static let iUpToggleLock = Notification.Name("iUp.toggleLock")
    static let iUpToggleSession = Notification.Name("iUp.toggleSession")
    static let iUpInputBlockerFailed = Notification.Name("iUp.inputBlockerFailed")
    /// Debug-only: unlock immediately without authentication (Esc escape hatch).
    static let iUpForceUnlock = Notification.Name("iUp.forceUnlock")
}
