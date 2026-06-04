import AppKit
import SwiftUI
import os.log

@MainActor
final class LockController {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Lock")

    private(set) var state: LockState = .unlocked
    private let settings: Settings
    private let overlay = OverlayWindowManager()
    private let inputBlocker = InputBlocker()
    private let authenticator = Authenticator()

    /// Display hooks — bound by DisplayController in app wiring (Display phase).
    var onDidLock: (() -> Void)?
    var onWillUnlock: (() -> Void)?

    private var toggleObserver: Any?
    private var blockerFailObserver: Any?

    init(settings: Settings) {
        self.settings = settings
        toggleObserver = NotificationCenter.default.addObserver(
            forName: .iUpToggleLock, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
        }
        blockerFailObserver = NotificationCenter.default.addObserver(
            forName: .iUpInputBlockerFailed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forceUnlock() }
        }
    }

    deinit {
        if let o = toggleObserver { NotificationCenter.default.removeObserver(o) }
        if let o = blockerFailObserver { NotificationCenter.default.removeObserver(o) }
    }

    func toggle() {
        switch state {
        case .unlocked: lock()
        case .locked: requestUnlock()
        default: break
        }
    }

    func lock() {
        guard settings.lockEnabled else { return }
        guard state.canTransition(to: .locking) else { return }
        guard AccessibilityChecker.isEnabled else {
            AccessibilityChecker.promptIfNeeded(); return
        }
        state = .locking

        let msg = "iUp"
        let interval = settings.burnInInterval
        guard overlay.showOverlay(contentFactory: { [weak self] _ in
            AnyView(LockScreenView(message: msg, burnInInterval: interval) {
                self?.requestUnlock()
            })
        }) else {
            state = .unlocked
            return
        }
        inputBlocker.startBlocking()
        state = .locked
        onDidLock?()
    }

    func requestUnlock() {
        guard state == .locked, state.canTransition(to: .unlocking) else { return }
        state = .unlocking
        inputBlocker.stopBlocking()
        Task { @MainActor in
            let ok = await authenticator.authenticate()
            if ok { completeUnlock() }
            else {
                inputBlocker.startBlocking()
                state = .locked
            }
        }
    }

    private func completeUnlock() {
        onWillUnlock?()
        overlay.dismissOverlay()
        inputBlocker.stopBlocking()
        state = .unlocked
    }

    private func forceUnlock() {
        onWillUnlock?()
        overlay.dismissOverlay()
        inputBlocker.stopBlocking()
        state = .unlocked
    }
}
