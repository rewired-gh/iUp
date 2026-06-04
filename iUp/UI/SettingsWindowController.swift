import AppKit
import SwiftUI

/// Hosts SettingsView in a standalone window. Used instead of the SwiftUI
/// `Settings` scene, whose legacy `showSettingsWindow:` opener is a no-op when
/// invoked from an AppKit status-bar menu on recent macOS.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: SettingsModel

    init(model: SettingsModel) { self.model = model }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let w = NSWindow(contentViewController: hosting)
            w.title = "iUp Settings"
            w.styleMask = [.titled, .closable]
            // Drop the bold title text so the TabView's tab strip reads as the single
            // header instead of sitting under a second one.
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
