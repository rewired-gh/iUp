import SwiftUI
import Combine

/// All per-feature toggles and thresholds. Backed by a shared Settings instance.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            awakeTab.tabItem { Label("Awake", systemImage: "cup.and.saucer") }
            jiggleTab.tabItem { Label("Activity", systemImage: "cursorarrow.motionlines") }
            pauseTab.tabItem { Label("Pause", systemImage: "pause.circle") }
            lockTab.tabItem { Label("Lock", systemImage: "lock") }
            appTab.tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 500, height: 420)
    }

    private var awakeTab: some View {
        Form {
            Section {
                Toggle("Keep the Mac awake", isOn: $model.awakeEnabled)
            } footer: {
                Text("Holds power assertions during an active session.")
            }
            Section("Prevent") {
                Toggle("Display sleep", isOn: $model.awakeDisplayOn)
                Toggle("System sleep", isOn: $model.awakeSystemSleep)
                Toggle("Network sleep", isOn: $model.awakeNetworkOn)
            }
            .disabled(!model.awakeEnabled)
        }
        .formStyle(.grouped)
    }

    private var jiggleTab: some View {
        Form {
            Section {
                Toggle("Simulate activity when idle", isOn: $model.jiggleEnabled)
            } footer: {
                Text("Moves the cursor in short bursts so the Mac registers activity. Real input is never counted as simulated.")
            }
            Section("Timing") {
                DurationRow("Start after idle", seconds: $model.jiggleIdleStart, range: 5...3600, step: 5)
                DurationRow("Move every", seconds: $model.jiggleInterval, range: 5...600, step: 5)
                DurationRow("Stop after extra idle", seconds: $model.jiggleStopAfter, range: 0...86_400, step: 30)
            }
            .disabled(!model.jiggleEnabled)
        }
        .formStyle(.grouped)
    }

    private var pauseTab: some View {
        Form {
            Section {
                Toggle("Pause the session when idle", isOn: $model.tempPauseEnabled)
            } footer: {
                Text("Releases keep-awake so the Mac may sleep. Resumes automatically on input or wake, or from the menu.")
            }
            Section("Timing") {
                DurationRow("Pause after idle", seconds: $model.tempPauseIdle, range: 5...3600, step: 5)
            }
            .disabled(!model.tempPauseEnabled)
        }
        .formStyle(.grouped)
    }

    private var lockTab: some View {
        Form {
            Section {
                Toggle("Enable lock screen", isOn: $model.lockEnabled)
                DurationRow("Burn-in reposition interval", seconds: $model.burnInInterval, range: 5...600, step: 5)
                    .disabled(!model.lockEnabled)
            } footer: {
                Text("Lock with the menu or ⌃⌥⌘L. Unlock with Touch ID, password, or the same shortcut.")
            }
            Section("Displays while locked") {
                Toggle("Control displays", isOn: $model.displayControlEnabled)
                Toggle("Dim built-in display", isOn: $model.displayInternalDim)
                    .disabled(!model.displayControlEnabled)
                Toggle("Turn off external displays", isOn: $model.displayExternalOff)
                    .disabled(!model.displayControlEnabled)
                DurationRow("Re-dim after idle", seconds: $model.displayDimIdle, range: 5...3600, step: 5)
                    .disabled(!model.displayControlEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var appTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Toggle("Auto-start session on launch", isOn: $model.autoStartSession)
            }
            Section {
                Toggle("Debug mode", isOn: $model.debugMode)
            } footer: {
                Text("Allows pressing Esc on the lock screen to unlock immediately without authentication. For testing only.")
            }
        }
        .formStyle(.grouped)
    }
}

/// A grouped-form row: label on the left, a numeric seconds field + stepper on the right.
private struct DurationRow: View {
    let title: String
    @Binding var seconds: TimeInterval
    let range: ClosedRange<Double>
    let step: Double

    init(_ title: String, seconds: Binding<TimeInterval>, range: ClosedRange<Double>, step: Double) {
        self.title = title
        self._seconds = seconds
        self.range = range
        self.step = step
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", value: $seconds, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text("sec").foregroundStyle(.secondary)
                Stepper("", value: $seconds, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

/// Bridges Settings (UserDefaults) to SwiftUI bindings and applies side effects
/// (login item) on change.
final class SettingsModel: ObservableObject {
    private let settings: Settings
    private let loginItem: LoginItem

    init(settings: Settings, loginItem: LoginItem = LoginItem()) {
        self.settings = settings
        self.loginItem = loginItem
    }

    private func write<T>(_ kp: ReferenceWritableKeyPath<Settings, T>, _ v: T) {
        objectWillChange.send()
        settings[keyPath: kp] = v
        NotificationCenter.default.post(name: .iUpSettingsChanged, object: nil)
    }

    var awakeEnabled: Bool { get { settings.awakeEnabled } set { write(\.awakeEnabled, newValue) } }
    var awakeDisplayOn: Bool { get { settings.awakeDisplayOn } set { write(\.awakeDisplayOn, newValue) } }
    var awakeSystemSleep: Bool { get { settings.awakeSystemSleep } set { write(\.awakeSystemSleep, newValue) } }
    var awakeNetworkOn: Bool { get { settings.awakeNetworkOn } set { write(\.awakeNetworkOn, newValue) } }
    var jiggleEnabled: Bool { get { settings.jiggleEnabled } set { write(\.jiggleEnabled, newValue) } }
    var jiggleIdleStart: TimeInterval { get { settings.jiggleIdleStart } set { write(\.jiggleIdleStart, newValue) } }
    var jiggleInterval: TimeInterval { get { settings.jiggleInterval } set { write(\.jiggleInterval, newValue) } }
    var jiggleStopAfter: TimeInterval { get { settings.jiggleStopAfter } set { write(\.jiggleStopAfter, newValue) } }
    var tempPauseEnabled: Bool { get { settings.tempPauseEnabled } set { write(\.tempPauseEnabled, newValue) } }
    var tempPauseIdle: TimeInterval { get { settings.tempPauseIdle } set { write(\.tempPauseIdle, newValue) } }
    var displayControlEnabled: Bool { get { settings.displayControlEnabled } set { write(\.displayControlEnabled, newValue) } }
    var displayDimIdle: TimeInterval { get { settings.displayDimIdle } set { write(\.displayDimIdle, newValue) } }
    var displayInternalDim: Bool { get { settings.displayInternalDim } set { write(\.displayInternalDim, newValue) } }
    var displayExternalOff: Bool { get { settings.displayExternalOff } set { write(\.displayExternalOff, newValue) } }
    var lockEnabled: Bool { get { settings.lockEnabled } set { write(\.lockEnabled, newValue) } }
    var burnInInterval: TimeInterval { get { settings.burnInInterval } set { write(\.burnInInterval, newValue) } }
    var autoStartSession: Bool { get { settings.autoStartSession } set { write(\.autoStartSession, newValue) } }
    var debugMode: Bool { get { settings.debugMode } set { write(\.debugMode, newValue) } }
    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set { write(\.launchAtLogin, newValue); try? loginItem.apply(enabled: newValue) }
    }
}
