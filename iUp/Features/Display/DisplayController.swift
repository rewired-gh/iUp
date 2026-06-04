import Foundation

protocol DisplayBackend: AnyObject {
    func getInternalBrightness() -> Float?   // nil if no internal display
    func setInternalBrightness(_ v: Float)
}

/// Dims the built-in display while locked, when "Dim built-in display" is on.
///
/// Brightness is a one-way action: dim once on lock. It is never auto-restored —
/// the user raises brightness manually after unlocking (the level can't be read
/// back reliably on macOS 26, so any "restore" would be a guess). A single
/// `isDimmed` flag guards the dim so it is issued at most once per lock.
final class DisplayController {
    private let settings: Settings
    private let backend: DisplayBackend
    private(set) var isDimmed = false

    init(settings: Settings, backend: DisplayBackend) {
        self.settings = settings
        self.backend = backend
    }

    var isAvailable: Bool { backend.getInternalBrightness() != nil }

    func didLock() {
        guard settings.displayInternalDim, isAvailable else { return }
        dim()
    }

    func willUnlock() {
        isDimmed = false   // brightness left as-is; user restores manually
    }

    /// Reconcile to current settings while locked (e.g. user toggled dimming from
    /// Settings mid-lock). Brightness is only ever driven down — turning dimming
    /// off does not auto-raise it.
    func reapplyWhileLocked() {
        guard settings.displayInternalDim, isAvailable else { return }
        dim()
    }

    // MARK: - Private

    private func dim() {
        guard !isDimmed else { return }
        backend.setInternalBrightness(0)
        isDimmed = true
    }
}
