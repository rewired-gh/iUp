import Foundation

/// Typed wrapper over UserDefaults. Every feature owns its own keys;
/// no key is shared or derived from another (per-feature independence).
final class Settings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private enum Key {
        static let awakeEnabled = "awake.enabled"
        static let awakeDisplayOn = "awake.displayOn"
        static let awakeSystemSleep = "awake.systemSleep"
        static let awakeNetworkOn = "awake.networkOn"
        static let jiggleEnabled = "jiggle.enabled"
        static let jiggleIdleStart = "jiggle.idleStart"
        static let jiggleInterval = "jiggle.interval"
        static let jiggleStopAfter = "jiggle.stopAfter"
        static let tempPauseEnabled = "tempPause.enabled"
        static let tempPauseIdle = "tempPause.idle"
        static let displayControlEnabled = "display.enabled"
        static let displayDimIdle = "display.dimIdle"
        static let displayInternalDim = "display.internalDim"
        static let displayExternalOff = "display.externalOff"
        static let lockEnabled = "lock.enabled"
        static let burnInInterval = "lock.burnInInterval"
        static let launchAtLogin = "app.launchAtLogin"
        static let autoStartSession = "app.autoStartSession"
        static let debugMode = "app.debugMode"
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.awakeEnabled: true,
            Key.awakeDisplayOn: true,
            Key.awakeSystemSleep: true,
            Key.awakeNetworkOn: true,
            Key.jiggleEnabled: true,
            Key.jiggleIdleStart: 60.0,
            Key.jiggleInterval: 30.0,
            Key.jiggleStopAfter: 300.0,
            Key.tempPauseEnabled: true,
            Key.tempPauseIdle: 60.0,
            Key.displayControlEnabled: true,
            Key.displayDimIdle: 60.0,
            Key.displayInternalDim: true,
            Key.displayExternalOff: true,
            Key.lockEnabled: true,
            Key.burnInInterval: 30.0,
            Key.launchAtLogin: false,
            Key.autoStartSession: false,
            Key.debugMode: false,
        ])
    }

    private func bool(_ k: String) -> Bool { defaults.bool(forKey: k) }
    private func setBool(_ v: Bool, _ k: String) { defaults.set(v, forKey: k) }
    private func dbl(_ k: String) -> TimeInterval { defaults.double(forKey: k) }
    private func setDbl(_ v: TimeInterval, _ k: String) { defaults.set(v, forKey: k) }

    var awakeEnabled: Bool { get { bool(Key.awakeEnabled) } set { setBool(newValue, Key.awakeEnabled) } }
    var awakeDisplayOn: Bool { get { bool(Key.awakeDisplayOn) } set { setBool(newValue, Key.awakeDisplayOn) } }
    var awakeSystemSleep: Bool { get { bool(Key.awakeSystemSleep) } set { setBool(newValue, Key.awakeSystemSleep) } }
    var awakeNetworkOn: Bool { get { bool(Key.awakeNetworkOn) } set { setBool(newValue, Key.awakeNetworkOn) } }

    var jiggleEnabled: Bool { get { bool(Key.jiggleEnabled) } set { setBool(newValue, Key.jiggleEnabled) } }
    var jiggleIdleStart: TimeInterval { get { dbl(Key.jiggleIdleStart) } set { setDbl(newValue, Key.jiggleIdleStart) } }
    var jiggleInterval: TimeInterval { get { dbl(Key.jiggleInterval) } set { setDbl(newValue, Key.jiggleInterval) } }
    var jiggleStopAfter: TimeInterval { get { dbl(Key.jiggleStopAfter) } set { setDbl(newValue, Key.jiggleStopAfter) } }

    var tempPauseEnabled: Bool { get { bool(Key.tempPauseEnabled) } set { setBool(newValue, Key.tempPauseEnabled) } }
    var tempPauseIdle: TimeInterval { get { dbl(Key.tempPauseIdle) } set { setDbl(newValue, Key.tempPauseIdle) } }

    var displayControlEnabled: Bool { get { bool(Key.displayControlEnabled) } set { setBool(newValue, Key.displayControlEnabled) } }
    var displayDimIdle: TimeInterval { get { dbl(Key.displayDimIdle) } set { setDbl(newValue, Key.displayDimIdle) } }
    var displayInternalDim: Bool { get { bool(Key.displayInternalDim) } set { setBool(newValue, Key.displayInternalDim) } }
    var displayExternalOff: Bool { get { bool(Key.displayExternalOff) } set { setBool(newValue, Key.displayExternalOff) } }

    var lockEnabled: Bool { get { bool(Key.lockEnabled) } set { setBool(newValue, Key.lockEnabled) } }
    var burnInInterval: TimeInterval { get { dbl(Key.burnInInterval) } set { setDbl(newValue, Key.burnInInterval) } }

    var launchAtLogin: Bool { get { bool(Key.launchAtLogin) } set { setBool(newValue, Key.launchAtLogin) } }
    var autoStartSession: Bool { get { bool(Key.autoStartSession) } set { setBool(newValue, Key.autoStartSession) } }
    var debugMode: Bool { get { bool(Key.debugMode) } set { setBool(newValue, Key.debugMode) } }
}
