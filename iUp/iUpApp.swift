import SwiftUI

@main
struct iUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No primary window — menu-bar accessory app.
        // SwiftUI.Settings is fully qualified to avoid colliding with our Settings config class.
        SwiftUI.Settings {
            EmptyView()
        }
    }
}
