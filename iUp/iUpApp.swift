import SwiftUI

@main
struct iUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            SettingsView(model: SettingsModel(settings: appDelegate.settings))
        }
    }
}
