import Foundation

extension Notification.Name {
    static let iUpToggleLock = Notification.Name("iUp.toggleLock")
    static let iUpToggleSession = Notification.Name("iUp.toggleSession")
    static let iUpInputBlockerFailed = Notification.Name("iUp.inputBlockerFailed")
    /// Debug-only: unlock immediately without authentication (Esc escape hatch).
    static let iUpForceUnlock = Notification.Name("iUp.forceUnlock")
    /// Posted whenever a setting changes, so live features can reconcile.
    static let iUpSettingsChanged = Notification.Name("iUp.settingsChanged")
    /// Posted when an input event tap can no longer be enabled (e.g. Accessibility
    /// was revoked at runtime), so the app can tear down and re-acquire on re-grant.
    static let iUpInputServicesStalled = Notification.Name("iUp.inputServicesStalled")
}
