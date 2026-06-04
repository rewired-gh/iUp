import SwiftUI

@main
struct iUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings are shown via AppDelegate's own window (SettingsWindowController),
        // not the SwiftUI Settings scene — its `showSettingsWindow:` opener is a
        // no-op from an accessory app's AppKit status menu. This empty scene
        // satisfies the App protocol.
        SwiftUI.Settings { EmptyView() }
    }
}
