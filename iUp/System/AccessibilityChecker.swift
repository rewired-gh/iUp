import Cocoa

enum AccessibilityChecker {
    static var isEnabled: Bool { AXIsProcessTrusted() }

    static func promptIfNeeded() {
        guard !isEnabled else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
