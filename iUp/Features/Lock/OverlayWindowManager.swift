import AppKit
import SwiftUI

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

    private func recreate() {
        for w in windows { w.orderOut(nil); w.contentView = nil }
        windows.removeAll()
        createWindows()
    }

    private func createWindows() {
        guard let factory = contentFactory else { return }
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let w = NSWindow(contentRect: frame, styleMask: .borderless,
                             backing: .buffered, defer: false, screen: screen)
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
