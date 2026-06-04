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
    private var menuBar: MenuBarController?

    private var inputTap: InputObservationTap?
    private var tickTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AccessibilityChecker.promptIfNeeded()

        monitor.onUserBecameActive = { [weak self] in
            guard let self else { return }
            self.session.userBecameActive()
            if self.lock.state == .locked { self.display.userActiveWhileLocked() }
        }
        monitor.onTick = { [weak self] idle in
            guard let self else { return }
            self.session.tick(idle: idle)
            if self.lock.state == .locked { self.display.lockedTick(idle: idle) }
        }

        lock.onDidLock = { [weak self] in self?.display.didLock() }
        lock.onWillUnlock = { [weak self] in self?.display.willUnlock() }

        inputTap = InputObservationTap { [weak self] isSynthetic in
            DispatchQueue.main.async { self?.monitor.record(isSynthetic: isSynthetic) }
        }
        inputTap?.start()

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

        hotkey.register()
        menuBar = MenuBarController(session: session, lock: lock)

        if settings.autoStartSession { session.start() }
    }
}

/// Runs a MovePosting on a background queue so the ~0.5s burst never stalls the main thread.
final class BackgroundPoster: MovePosting {
    private let wrapped: MovePosting
    private let queue = DispatchQueue(label: "moe.rewired.iUp.jiggle", qos: .userInitiated)
    init(_ wrapped: MovePosting) { self.wrapped = wrapped }
    func postBurst() { queue.async { self.wrapped.postBurst() } }
}
