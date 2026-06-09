import AppKit
import os.log

private let appLog = Logger(subsystem: "moe.rewired.iUp", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()

    private lazy var monitor = ActivityMonitor()
    private lazy var awake = AwakeController(settings: settings, assertions: IOPMAssertions())
    private lazy var jiggle: JiggleController = {
        JiggleController(settings: settings, poster: BackgroundPoster(CGMovePoster(settings: settings)))
    }()
    private lazy var session = SessionController(settings: settings, awake: awake, jiggle: jiggle)
    private lazy var lock = LockController(settings: settings)
    private lazy var display = DisplayController(settings: settings, backend: BrightnessService())
    private lazy var hotkey = HotkeyManager()
    private let loginItem = LoginItem()
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
            self?.session.userBecameActive()
        }
        monitor.onTick = { [weak self] idle in
            guard let self, self.inputMonitoringActive else { return }
            self.session.tick(idle: idle)
        }

        lock.onDidLock = { [weak self] in
            // Dim 1s after the overlay appears, so the screen goes black first
            // then fades the backlight. Skip if the user already unlocked.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let self, self.lock.state == .locked else { return }
                self.display.didLock()
            }
        }
        lock.onWillUnlock = { [weak self] in self?.display.willUnlock() }

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

        // If an input tap can no longer be enabled (Accessibility revoked at runtime),
        // tear down and re-acquire — recovering automatically once it's re-granted.
        NotificationCenter.default.addObserver(
            forName: .iUpInputServicesStalled, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.handleInputServicesStalled() } }

        // Reflect the real login-item registration state into Settings (the user may
        // have removed it in System Settings).
        settings.launchAtLogin = loginItem.isEnabled

        menuBar = MenuBarController(session: session, lock: lock,
                                    onOpenSettings: { [weak self] in self?.settingsWindow.show() })

        startInputServicesIfPossible()

        if settings.autoStartSession { session.start() }
    }

    private func handleInputServicesStalled() {
        guard inputMonitoringActive else { return }
        inputMonitoringActive = false
        inputTap?.stop()
        hotkey.unregister()
        startInputServicesIfPossible()   // restarts if still trusted, else prompts + polls
    }

    /// Apply live settings changes to running features, resetting state where needed.
    private func reconcileSettings() {
        switch session.state {
        case .active:
            awake.reapply()
            jiggle.reset()
        case .pausedByIdle:
            // If the user just turned TempPause off, don't stay stuck paused.
            if !settings.tempPauseEnabled { session.resume() }
        case .off:
            break
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
            if accessibilityPoll == nil {
                appLog.info("Accessibility not granted — idle features disabled until it is; prompting + polling")
            }
            AccessibilityChecker.promptIfNeeded()
            startAccessibilityPolling()
            return
        }
        monitor.resetIdle()          // avoid a stale launch-time idle triggering an instant pause
        inputTap?.start()
        hotkey.register()
        inputMonitoringActive = true
        appLog.info("input services started; monitoring active")
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
