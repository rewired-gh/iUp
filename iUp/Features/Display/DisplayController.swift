import Foundation

protocol DisplayBackend: AnyObject {
    func getInternalBrightness() -> Float?   // nil if no internal display
    func setInternalBrightness(_ v: Float)
    func setExternalDisplays(on: Bool)
}

/// Manages displays while locked. Only acts when an internal display exists.
///
/// A single `isDimmed` flag is the source of truth so the built-in display is
/// dimmed and restored exactly once per idle cycle. Without it, the periodic
/// `lockedTick` (every 0.25s) would re-issue the dim continuously — flooding the
/// backlight with changes — and restore could fire when nothing was dimmed.
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

    /// Real user input while locked → restore internal brightness (once).
    func userActiveWhileLocked() {
        guard settings.displayControlEnabled, isAvailable, settings.displayInternalDim else { return }
        restore()
    }

    /// Re-idle while locked → dim again (only if not already dimmed).
    func lockedTick(idle: TimeInterval) {
        guard settings.displayControlEnabled, isAvailable, settings.displayInternalDim else { return }
        if idle >= settings.displayDimIdle { dim() }
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
