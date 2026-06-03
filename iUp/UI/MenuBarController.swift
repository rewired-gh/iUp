import AppKit

/// Status-bar menu. Session item label reflects state; shows manual Resume when paused.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let session: SessionController
    private let lock: LockController

    private let sessionItem = NSMenuItem()
    private let resumeItem = NSMenuItem()
    private let stateLabelItem = NSMenuItem()

    init(session: SessionController, lock: LockController) {
        self.session = session
        self.lock = lock
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "iUp")
        buildMenu()
        session.onStateChange = { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func buildMenu() {
        let menu = NSMenu()
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

    private func refresh() {
        switch session.state {
        case .off:
            stateLabelItem.title = "Session: Off"
            sessionItem.title = "Start Session"
            resumeItem.isHidden = true
        case .active:
            stateLabelItem.title = "Session: Active"
            sessionItem.title = "Stop Session"
            resumeItem.isHidden = true
        case .pausedByIdle:
            stateLabelItem.title = "Session: Paused (idle)"
            sessionItem.title = "Stop Session"
            resumeItem.isHidden = false
        }
    }

    @objc private func toggleSession() {
        if session.state == .off { session.start() } else { session.stop() }
    }
    @objc private func resumeSession() { session.resume() }
    @objc private func doLock() { lock.lock() }
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
