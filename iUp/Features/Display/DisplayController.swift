import Foundation

protocol DisplayBackend: AnyObject {
    func getInternalBrightness() -> Float?   // nil if no internal display
    func setInternalBrightness(_ v: Float)
    func setExternalDisplays(on: Bool)
}

/// Manages displays while locked. Only acts when an internal display exists.
///
/// Lifecycle is simple: dim once on lock, restore once on unlock. The only other
/// transitions are around authentication — brightness is restored so the Touch ID /
/// password dialog is visible, and re-dimmed if authentication fails and the screen
/// stays locked. A single `isDimmed` flag guards each transition so brightness is
/// never driven more than once per state change.
final class DisplayController {
    private let settings: Settings
    private let backend: DisplayBackend
    private var savedBrightness: Float?
    private(set) var isDimmed = false

    init(settings: Settings, backend: DisplayBackend) {
        self.settings = settings
        self.backend = backend
    }

    var isAvailable: Bool { backend.getInternalBrightness() != nil }

    func didLock() {
        guard settings.displayControlEnabled, isAvailable else { return }
        savedBrightness = backend.getInternalBrightness()
        if settings.displayInternalDim { dim() }
        if settings.displayExternalOff { backend.setExternalDisplays(on: false) }
    }

    /// Authentication is starting → restore brightness so the Touch ID / password
    /// dialog is visible. Keeps `savedBrightness` so a failed attempt can re-dim.
    func prepareForAuth() {
        guard settings.displayControlEnabled, isAvailable, settings.displayInternalDim else { return }
        restore()
    }

    /// Authentication failed and the screen stays locked → dim again.
    func authDidFail() {
        guard settings.displayControlEnabled, isAvailable, settings.displayInternalDim else { return }
        dim()
    }

    func willUnlock() {
        guard settings.displayControlEnabled, isAvailable else { return }
        restore()
        if settings.displayExternalOff { backend.setExternalDisplays(on: true) }
        savedBrightness = nil
    }

    /// Reconcile displays to current settings while locked (e.g. user toggled
    /// display control or its sub-options from Settings mid-lock).
    func reapplyWhileLocked() {
        guard isAvailable else { return }
        guard settings.displayControlEnabled else {
            restore()
            backend.setExternalDisplays(on: true)
            return
        }
        if settings.displayInternalDim {
            if savedBrightness == nil { savedBrightness = backend.getInternalBrightness() }
            dim()
        } else {
            restore()
        }
        backend.setExternalDisplays(on: !settings.displayExternalOff)
    }

    // MARK: - Private

    private func dim() {
        guard !isDimmed else { return }
        backend.setInternalBrightness(0)
        isDimmed = true
    }

    private func restore() {
        guard isDimmed else { return }
        if let b = savedBrightness { backend.setInternalBrightness(b) }
        isDimmed = false
    }
}
