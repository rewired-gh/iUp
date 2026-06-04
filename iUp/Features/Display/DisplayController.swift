import Foundation

protocol DisplayBackend: AnyObject {
    func getInternalBrightness() -> Float?   // nil if no internal display
    func setInternalBrightness(_ v: Float)
    func setExternalDisplays(on: Bool)
}

/// Manages displays while locked. Only acts when an internal display exists.
final class DisplayController {
    private let settings: Settings
    private let backend: DisplayBackend
    private var savedBrightness: Float?

    init(settings: Settings, backend: DisplayBackend) {
        self.settings = settings
        self.backend = backend
    }

    var isAvailable: Bool { backend.getInternalBrightness() != nil }

    func didLock() {
        guard settings.displayControlEnabled, isAvailable else { return }
        savedBrightness = backend.getInternalBrightness()
        if settings.displayInternalDim { backend.setInternalBrightness(0) }
        if settings.displayExternalOff { backend.setExternalDisplays(on: false) }
    }

    /// Real user input while locked → restore internal brightness only.
    func userActiveWhileLocked() {
        guard settings.displayControlEnabled, isAvailable, settings.displayInternalDim else { return }
        if let b = savedBrightness { backend.setInternalBrightness(b) }
    }

    /// Re-idle while locked → dim internal again.
    func lockedTick(idle: TimeInterval) {
        guard settings.displayControlEnabled, isAvailable, settings.displayInternalDim else { return }
        if idle >= settings.displayDimIdle { backend.setInternalBrightness(0) }
    }

    func willUnlock() {
        guard settings.displayControlEnabled, isAvailable else { return }
        if let b = savedBrightness { backend.setInternalBrightness(b) }
        if settings.displayExternalOff { backend.setExternalDisplays(on: true) }
        savedBrightness = nil
    }

    /// Reconcile displays to current settings while locked (e.g. user toggled
    /// display control or its sub-options from Settings mid-lock).
    func reapplyWhileLocked() {
        guard isAvailable else { return }
        if !settings.displayControlEnabled {
            if let b = savedBrightness { backend.setInternalBrightness(b) }
            backend.setExternalDisplays(on: true)
            savedBrightness = nil
            return
        }
        if settings.displayInternalDim {
            if savedBrightness == nil { savedBrightness = backend.getInternalBrightness() }
            backend.setInternalBrightness(0)
        } else if let b = savedBrightness {
            backend.setInternalBrightness(b)
            savedBrightness = nil
        }
        backend.setExternalDisplays(on: !settings.displayExternalOff)
    }
}
