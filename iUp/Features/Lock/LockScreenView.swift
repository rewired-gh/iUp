import SwiftUI
import Combine

/// Full-black lock content with dim-grey thin text + unlock button, both repositioned
/// every `burnInInterval` seconds for burn-in protection (BurnIn generator).
struct LockScreenView: View {
    let message: String
    let burnInInterval: TimeInterval
    var debugEscape: Bool = false
    let onUnlock: () -> Void

    /// Top-left origin of the (single) panel; nil until first laid out (centered).
    @State private var panelOrigin: CGPoint?
    private let panelSize = CGSize(width: 380, height: 220)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                panel
                    .frame(width: panelSize.width, height: panelSize.height)
                    .position(x: origin(in: geo.size).x + panelSize.width / 2,
                              y: origin(in: geo.size).y + panelSize.height / 2)
            }
            .onReceive(Timer.publish(every: burnInInterval, on: .main, in: .common).autoconnect()) { _ in
                reposition(in: geo.size)
            }
        }
    }

    /// Message, instructions, and the Unlock button kept together so the unlock
    /// control is always visible alongside the text.
    private var panel: some View {
        VStack(spacing: 18) {
            Text(message)
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(Color(white: 0.6))

            Button(action: onUnlock) {
                Text("Unlock").frame(width: 160, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text(debugEscape ? "Click Unlock, or press ⌃⌥⌘L  ·  Esc force-unlocks (debug)"
                             : "Click Unlock, or press ⌃⌥⌘L")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Color(white: 0.4))
        }
    }

    /// Centered until the burn-in timer first moves it.
    private func origin(in size: CGSize) -> CGPoint {
        panelOrigin ?? CGPoint(x: (size.width - panelSize.width) / 2,
                               y: (size.height - panelSize.height) / 2)
    }

    private func reposition(in size: CGSize) {
        var rng = SystemRandomNumberGenerator()
        panelOrigin = BurnIn.nextOrigin(container: size, label: panelSize, using: &rng)
    }
}
