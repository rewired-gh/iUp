import SwiftUI

@main
struct iUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No primary window. Settings scene added in a later task.
        WindowGroup { EmptyView() }
    }
}
