import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()

    private lazy var monitor = ActivityMonitor()
    private lazy var awake = AwakeController(settings: settings, assertions: IOPMAssertions())
    private lazy var jiggle: JiggleController = {
        JiggleController(settings: settings, poster: BackgroundPoster(CGMovePoster()))
    }()
    private lazy var session = SessionController(settings: settings, awake: awake, jiggle: jiggle)
    private lazy var lock = LockController(settings: settings)
    private lazy var display = DisplayController(settings: settings, backend: BrightnessService())
    private lazy var hotkey = HotkeyManager()
    private lazy var settingsModel = SettingsModel(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(model: settingsModel)
    private var menuBar: MenuBarController?

    private var inputTap: InputObservationTap?
    private var tickTimer: DispatchSourceTimer?

    /// True once the Accessibility-gated input tap + hotkeys are running. Until then,
    /// idle-based logic is suppressed so a frozen clock can't false-trigger TempPause.
    private var inputMonitoringActive = false
    private var accessibilityPoll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        monitor.onUserBecameActive = { [weak self] in
            guard let self else { return }
            self.session.userBecameActive()
            if self.lock.state == .locked { self.display.userActiveWhileLocked() }
        }
        monitor.onTick = { [weak self] idle in
            guard let self, self.inputMonitoringActive else { return }
            self.session.tick(idle: idle)
            if self.lock.state == .locked { self.display.lockedTick(idle: idle) }
        }

        lock.onDidLock = { [weak self] in self?.display.didLock() }
        lock.onWillUnlock = { [weak self] in self?.display.willUnlock() }
        lock.onAuthBegin = { [weak self] in self?.display.userActiveWhileLocked() }

        inputTap = InputObservationTap { [weak self] isSynthetic in
            DispatchQueue.main.async { self?.monitor.record(isSynthetic: isSynthetic) }
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.monitor.tick() }
        timer.resume()
        tickTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.session.systemDidWake() } }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.session.systemDidWake() } }

        NotificationCenter.default.addObserver(
            forName: .iUpToggleSession, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.session.state == .off { self.session.start() } else { self.session.stop() }
            }
        }

        // Re-check Accessibility whenever the app is reactivated (e.g. user returns
        // from System Settings after granting permission).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.startInputServicesIfPossible() } }

        NotificationCenter.default.addObserver(
            forName: .iUpSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reconcileSettings() } }

        menuBar = MenuBarController(session: session, lock: lock,
                                    onOpenSettings: { [weak self] in self?.settingsWindow.show() })

        startInputServicesIfPossible()

        if settings.autoStartSession { session.start() }
    }

    /// Apply live settings changes to running features, resetting state where needed.
    private func reconcileSettings() {
        if session.state == .active {
            awake.reapply()
            jiggle.reset()
        }
        if lock.state == .locked {
            display.reapplyWhileLocked()
        }
    }

    /// Starts the input tap + global hotkeys once Accessibility is granted. If not yet
    /// granted, prompts and polls until it is, so the user need not relaunch the app.
    private func startInputServicesIfPossible() {
        guard !inputMonitoringActive else { return }
        guard AccessibilityChecker.isEnabled else {
            AccessibilityChecker.promptIfNeeded()
            startAccessibilityPolling()
            return
        }
        monitor.resetIdle()          // avoid a stale launch-time idle triggering an instant pause
        inputTap?.start()
        hotkey.register()
        inputMonitoringActive = true
        accessibilityPoll?.invalidate()
        accessibilityPoll = nil
    }

    private func startAccessibilityPolling() {
        guard accessibilityPoll == nil else { return }
        accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.startInputServicesIfPossible() }
        }
    }
}

/// Runs a MovePosting on a background queue so the ~0.5s burst never stalls the main thread.
final class BackgroundPoster: MovePosting {
    private let wrapped: MovePosting
    private let queue = DispatchQueue(label: "moe.rewired.iUp.jiggle", qos: .userInitiated)
    init(_ wrapped: MovePosting) { self.wrapped = wrapped }
    func postBurst() { queue.async { self.wrapped.postBurst() } }
}
