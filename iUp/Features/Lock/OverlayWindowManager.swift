import AppKit
import SwiftUI

/// Borderless window that can still become key/main so the on-screen Unlock
/// button and any focused controls receive events.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Creates one borderless shield-level window per screen and recreates them on
/// screen-parameter changes. `contentFactory` builds SwiftUI content per screen index.
final class OverlayWindowManager {
    private var windows: [NSWindow] = []
    private var screenObserver: Any?
    private var contentFactory: ((Int) -> AnyView)?
    private let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

    @discardableResult
    func showOverlay(contentFactory factory: @escaping (Int) -> AnyView) -> Bool {
        contentFactory = factory
        dismissOverlay()
        createWindows()
        guard !windows.isEmpty else { return false }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.recreate() }
        return true
    }

    func dismissOverlay() {
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        for w in windows { w.orderOut(nil); w.contentView = nil; w.close() }
        windows.removeAll()
    }

    /// Drop the overlay below system panels so the Touch ID / password dialog is
    /// visible, but stay above the menu bar (statusBar level) so it isn't revealed.
    func lowerForAuth() {
        for w in windows { w.level = .statusBar }
    }

    /// Raise the overlay back to shield level (e.g. after a failed unlock).
    func raiseShield() {
        for w in windows { w.level = shieldLevel }
    }

    private func recreate() {
        for w in windows { w.orderOut(nil); w.contentView = nil }
        windows.removeAll()
        createWindows()
    }

    private func createWindows() {
        guard let factory = contentFactory else { return }
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let w = KeyableWindow(contentRect: frame, styleMask: .borderless,
                                  backing: .buffered, defer: false, screen: screen)
            // NSWindow defaults isReleasedWhenClosed = true; with ARC also retaining
            // it in `windows`, close() would over-release → crash on a later lock cycle.
            w.isReleasedWhenClosed = false
            w.setFrame(frame, display: true)
            w.level = shieldLevel
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            let host = NSHostingView(rootView: factory(index))
            host.autoresizingMask = [.width, .height]
            host.frame = w.contentLayoutRect
            w.contentView = host
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    deinit { dismissOverlay() }
}
