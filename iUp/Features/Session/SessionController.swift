import Foundation
import os.log

private let sessionLog = Logger(subsystem: "moe.rewired.iUp", category: "Session")

protocol AwakeDriving: AnyObject {
    func activate()
    func deactivate()
}
protocol JiggleDriving: AnyObject {
    func evaluate(idle: TimeInterval)
    func reset()
}

extension AwakeController: AwakeDriving {}
extension JiggleController: JiggleDriving {}

/// Owns the awake session. When active, drives Awake + Jiggle.
/// TempPause policy: at idle >= tempPauseIdle (if enabled) release everything so
/// the Mac may sleep; resume on user input, system wake, or manual button.
final class SessionController {
    private let settings: Settings
    private let awake: AwakeDriving
    private let jiggle: JiggleDriving

    private(set) var state: SessionState = .off
    var onStateChange: ((SessionState) -> Void)?

    init(settings: Settings, awake: AwakeDriving, jiggle: JiggleDriving) {
        self.settings = settings
        self.awake = awake
        self.jiggle = jiggle
    }

    private func set(_ new: SessionState) {
        guard new != state else { return }
        sessionLog.info("state \(String(describing: self.state), privacy: .public) -> \(String(describing: new), privacy: .public)")
        state = new
        onStateChange?(new)
    }

    func start() {
        guard state == .off else { return }
        awake.activate()
        jiggle.reset()
        set(.active)
    }

    func stop() {
        awake.deactivate()
        jiggle.reset()
        set(.off)
    }

    /// Manual or automatic resume from pause.
    func resume() {
        guard state == .pausedByIdle else { return }
        awake.activate()
        jiggle.reset()
        set(.active)
    }

    func tick(idle: TimeInterval) {
        guard state == .active else { return }
        if settings.tempPauseEnabled && idle >= settings.tempPauseIdle {
            awake.deactivate()
            jiggle.reset()
            set(.pausedByIdle)
            return
        }
        jiggle.evaluate(idle: idle)
    }

    func userBecameActive() {
        switch state {
        case .pausedByIdle: resume()
        case .active: jiggle.reset()
        case .off: break
        }
    }

    func systemDidWake() {
        if state == .pausedByIdle { resume() }
    }
}
