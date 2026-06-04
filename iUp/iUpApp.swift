import SwiftUI

@main
struct iUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings are shown via AppDelegate's own window (SettingsWindowController),
        // not the SwiftUI Settings scene. This empty scene satisfies the App protocol.
        SwiftUI.Settings { EmptyView() }
    }
}
