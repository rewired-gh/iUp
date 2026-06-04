import AppKit
import SwiftUI

/// Hosts the settings panes in a standalone window with a native `NSToolbar` in
/// `.preference` style — the same chrome the system Settings app uses. We can't
/// use the SwiftUI `Settings` scene (its `showSettingsWindow:` opener is a no-op
/// from an accessory app's AppKit status menu), and a SwiftUI `TabView` renders
/// its tab strip incorrectly outside that scene, so the toolbar is built in
/// AppKit while each pane's body stays in SwiftUI.
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    private var window: NSWindow?
    private let hosting: NSHostingController<SettingsView>
    private let model: SettingsModel
    private var pane: SettingsPane = .awake

    init(model: SettingsModel) {
        self.model = model
        self.hosting = NSHostingController(rootView: SettingsView(model: model, pane: .awake))
        super.init()
    }

    func show() {
        if window == nil { buildWindow() }
        select(pane)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false

        let toolbar = NSToolbar(identifier: "iUpSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = pane.itemID
        toolbar.allowsUserCustomization = false
        w.toolbar = toolbar
        w.toolbarStyle = .preference

        w.center()
        window = w
    }

    /// Swaps the displayed pane and resizes the window to fit its content.
    private func select(_ pane: SettingsPane) {
        self.pane = pane
        window?.title = pane.title
        window?.toolbar?.selectedItemIdentifier = pane.itemID
        hosting.rootView = SettingsView(model: model, pane: pane)
        // Let SwiftUI lay out the new pane, then size the window to it so each
        // pane shows fully without scrolling or clipping.
        hosting.view.layoutSubtreeIfNeeded()
        window?.setContentSize(hosting.view.fittingSize)
    }

    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(pane)
    }

    // MARK: NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(toolbarItemSelected(_:))
        return item
    }

    private var paneIdentifiers: [NSToolbarItem.Identifier] { SettingsPane.allCases.map(\.itemID) }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { paneIdentifiers }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { paneIdentifiers }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { paneIdentifiers }
}
