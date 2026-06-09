import SwiftUI
import AppKit
import Combine

/// One pane of the settings window. The window chrome is a native `NSToolbar`
/// in `.preference` style (see `SettingsWindowController`); this enum is the
/// single source of truth for the panes' identity, order, title, and icon.
enum SettingsPane: String, CaseIterable, Identifiable {
    case awake, activity, pause, lock, general

    var id: String { rawValue }
    var itemID: NSToolbarItem.Identifier { .init(rawValue) }

    var title: String {
        switch self {
        case .awake:    "Awake"
        case .activity: "Activity"
        case .pause:    "Pause"
        case .lock:     "Lock"
        case .general:  "General"
        }
    }

    var symbol: String {
        switch self {
        case .awake:    "cup.and.saucer"
        case .activity: "cursorarrow.motionlines"
        case .pause:    "pause.circle"
        case .lock:     "lock"
        case .general:  "gearshape"
        }
    }
}

/// Renders a single settings pane. The hosting window swaps which pane is shown
/// as the toolbar selection changes, so there is no SwiftUI `TabView` — its
/// macOS tab-strip chrome renders incorrectly outside the `Settings` scene
/// (mismatched background, misaligned focus rings).
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let pane: SettingsPane

    /// Fixed so the window width stays stable across panes; height is intrinsic.
    private let paneWidth: CGFloat = 460

    /// Bridges the discrete `JiggleLevel` enum to the slider's continuous value.
    private var jiggleLevelIndex: Binding<Double> {
        Binding(
            get: { Double(JiggleLevel.allCases.firstIndex(of: model.jiggleLevel) ?? 0) },
            set: { model.jiggleLevel = JiggleLevel.allCases[Int($0.rounded())] }
        )
    }

    var body: some View {
        content
            .formStyle(.grouped)
            .frame(width: paneWidth)
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .awake:    awakeForm
        case .activity: activityForm
        case .pause:    pauseForm
        case .lock:     lockForm
        case .general:  generalForm
        }
    }

    private var awakeForm: some View {
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
    }

    private var activityForm: some View {
        Form {
            Section {
                Toggle("Simulate activity when idle", isOn: $model.jiggleEnabled)
            } footer: {
                Text("Moves the cursor in short bursts so the Mac registers activity. Real input is never counted as simulated.")
            }
            Section("Timing") {
                DurationRow("Start after idle", seconds: $model.jiggleIdleStart, range: 5...3600, step: 5)
                DurationRow("Move every", seconds: $model.jiggleInterval, range: 5...600, step: 5)
            }
            .disabled(!model.jiggleEnabled)
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Movement amount")
                        Spacer()
                        Text(model.jiggleLevel.title)
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: jiggleLevelIndex,
                        in: 0...Double(JiggleLevel.allCases.count - 1),
                        step: 1
                    ) {
                        Text("Movement amount")
                    } minimumValueLabel: {
                        Text("Slightest")
                    } maximumValueLabel: {
                        Text("Maximum")
                    }
                }
            } footer: {
                Text("How far the cursor roams from where it sat. The slightest level keeps motion within 1 px; the maximum is a wide but bounded wander.")
            }
            .disabled(!model.jiggleEnabled)
        }
    }

    private var pauseForm: some View {
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
    }

    private var lockForm: some View {
        Form {
            Section {
                Toggle("Enable lock screen", isOn: $model.lockEnabled)
                DurationRow("Burn-in reposition interval", seconds: $model.burnInInterval, range: 5...600, step: 5)
                    .disabled(!model.lockEnabled)
            } footer: {
                Text("Lock with the menu or ⌃⌥⌘L. Unlock with Touch ID, password, or the same shortcut.")
            }
            Section {
                Toggle("Dim built-in display while locked", isOn: $model.displayInternalDim)
            } footer: {
                Text("Lowers the built-in display to its minimum while the lock screen is shown. Brightness is not changed back on unlock — raise it yourself.")
            }
        }
    }

    private var generalForm: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Toggle("Auto-start session on launch", isOn: $model.autoStartSession)
            }
            #if DEBUG
            // Debug-only escape hatch — never exposed in Release builds.
            Section {
                Toggle("Debug mode", isOn: $model.debugMode)
            } footer: {
                Text("Allows pressing Esc on the lock screen to unlock immediately without authentication. For testing only.")
            }
            #endif
        }
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
        // A manual centered HStack rather than LabeledContent: LabeledContent
        // baseline-aligns its label to the control, leaving the text visibly
        // high next to the taller field+stepper.
        HStack(alignment: .center, spacing: 6) {
            Text(title)
            Spacer(minLength: 12)
            // Wide enough that 4-digit values never wrap; wrapping was what
            // pushed the row taller on certain numbers.
            TextField("", value: $seconds, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 88)
            Text("sec").foregroundStyle(.secondary)
            Stepper("", value: $seconds, in: range, step: step)
                .labelsHidden()
        }
    }
}

/// Bridges Settings (UserDefaults) to SwiftUI bindings and applies side effects
/// (login item) on change.
@MainActor
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
    var jiggleLevel: JiggleLevel { get { settings.jiggleLevel } set { write(\.jiggleLevel, newValue) } }
    var tempPauseEnabled: Bool { get { settings.tempPauseEnabled } set { write(\.tempPauseEnabled, newValue) } }
    var tempPauseIdle: TimeInterval { get { settings.tempPauseIdle } set { write(\.tempPauseIdle, newValue) } }
    var displayInternalDim: Bool { get { settings.displayInternalDim } set { write(\.displayInternalDim, newValue) } }
    var lockEnabled: Bool { get { settings.lockEnabled } set { write(\.lockEnabled, newValue) } }
    var burnInInterval: TimeInterval { get { settings.burnInInterval } set { write(\.burnInInterval, newValue) } }
    var autoStartSession: Bool { get { settings.autoStartSession } set { write(\.autoStartSession, newValue) } }
    var debugMode: Bool { get { settings.debugMode } set { write(\.debugMode, newValue) } }
    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set {
            do {
                try loginItem.apply(enabled: newValue)
                write(\.launchAtLogin, newValue)
            } catch {
                // Registration failed — don't persist a misleading value; revert the toggle.
                objectWillChange.send()
            }
        }
    }
}
