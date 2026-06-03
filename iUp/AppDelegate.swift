import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, menu-bar only.
        NSApp.setActivationPolicy(.accessory)
        // Wiring of controllers added in later tasks.
    }
}
