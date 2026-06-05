import AppKit

/// Status-bar menu. Session item label reflects state; shows manual Resume when paused.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let session: SessionController
    private let lock: LockController
    private let onOpenSettings: () -> Void

    private let sessionItem = NSMenuItem()
    private let resumeItem = NSMenuItem()
    private let stateLabelItem = NSMenuItem()
    private let accessibilityItem = NSMenuItem()

    init(session: SessionController, lock: LockController, onOpenSettings: @escaping () -> Void) {
        self.session = session
        self.lock = lock
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "apple.meditate", accessibilityDescription: "iUp")
        super.init()
        buildMenu()
        session.onStateChange = { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        accessibilityItem.title = "⚠︎ Grant Accessibility to enable features"
        accessibilityItem.target = self
        accessibilityItem.action = #selector(openAccessibility)
        menu.addItem(accessibilityItem)

        stateLabelItem.isEnabled = false
        menu.addItem(stateLabelItem)
        menu.addItem(.separator())

        sessionItem.target = self
        sessionItem.action = #selector(toggleSession)
        menu.addItem(sessionItem)

        resumeItem.title = "Resume Session"
        resumeItem.target = self
        resumeItem.action = #selector(resumeSession)
        menu.addItem(resumeItem)

        let lockItem = NSMenuItem(title: "Lock", action: #selector(doLock), keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit iUp", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        accessibilityItem.isHidden = AccessibilityChecker.isEnabled
        switch session.state {
        case .off:
            stateLabelItem.title = "Session: Off"
            sessionItem.title = "Start Session"
            resumeItem.isHidden = true
            statusItem.button?.contentTintColor = .tertiaryLabelColor
        case .active:
            stateLabelItem.title = "Session: Active"
            sessionItem.title = "Stop Session"
            resumeItem.isHidden = true
            statusItem.button?.contentTintColor = nil
        case .pausedByIdle:
            stateLabelItem.title = "Session: Paused (idle)"
            sessionItem.title = "Stop Session"
            resumeItem.isHidden = false
            statusItem.button?.contentTintColor = .tertiaryLabelColor
        }
    }

    @objc private func toggleSession() {
        if session.state == .off { session.start() } else { session.stop() }
    }
    @objc private func resumeSession() { session.resume() }
    @objc private func doLock() { lock.lock() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func openAccessibility() {
        AccessibilityChecker.promptIfNeeded()
        AccessibilityChecker.openSystemSettings()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
