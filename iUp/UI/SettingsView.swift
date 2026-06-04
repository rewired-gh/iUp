import SwiftUI
import Combine

/// All per-feature toggles and thresholds. Backed by a shared Settings instance.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            awakeTab.tabItem { Text("Awake") }
            jiggleTab.tabItem { Text("Activity") }
            pauseTab.tabItem { Text("Pause") }
            lockTab.tabItem { Text("Lock") }
            appTab.tabItem { Text("General") }
        }
        .frame(width: 420, height: 320)
        .padding()
    }

    private var awakeTab: some View {
        Form {
            Toggle("Enable keep-awake", isOn: $model.awakeEnabled)
            Toggle("Keep display on", isOn: $model.awakeDisplayOn).disabled(!model.awakeEnabled)
            Toggle("Prevent system sleep", isOn: $model.awakeSystemSleep).disabled(!model.awakeEnabled)
            Toggle("Keep network alive", isOn: $model.awakeNetworkOn).disabled(!model.awakeEnabled)
        }
    }
    private var jiggleTab: some View {
        Form {
            Toggle("Enable activity simulation", isOn: $model.jiggleEnabled)
            secondsRow("Start after idle", $model.jiggleIdleStart)
            secondsRow("Move every", $model.jiggleInterval)
            secondsRow("Stop after extra idle", $model.jiggleStopAfter)
        }
    }
    private var pauseTab: some View {
        Form {
            Toggle("Enable temporary pause", isOn: $model.tempPauseEnabled)
            secondsRow("Pause after idle", $model.tempPauseIdle)
        }
    }
    private var lockTab: some View {
        Form {
            Toggle("Enable lock", isOn: $model.lockEnabled)
            secondsRow("Burn-in reposition interval", $model.burnInInterval)
            Toggle("Control displays while locked", isOn: $model.displayControlEnabled)
            Toggle("Dim built-in display", isOn: $model.displayInternalDim).disabled(!model.displayControlEnabled)
            Toggle("Turn off external displays", isOn: $model.displayExternalOff).disabled(!model.displayControlEnabled)
            secondsRow("Re-dim after idle", $model.displayDimIdle).disabled(!model.displayControlEnabled)
        }
    }
    private var appTab: some View {
        Form {
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Toggle("Auto-start session on launch", isOn: $model.autoStartSession)
        }
    }

    private func secondsRow(_ label: String, _ value: Binding<TimeInterval>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: .number).frame(width: 70).multilineTextAlignment(.trailing)
            Text("s")
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
        objectWillChange.send(); settings[keyPath: kp] = v
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
    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set { write(\.launchAtLogin, newValue); try? loginItem.apply(enabled: newValue) }
    }
}
