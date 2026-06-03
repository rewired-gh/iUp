import SwiftUI
import Combine

/// Full-black lock content with dim-grey thin text + unlock button, both repositioned
/// every `burnInInterval` seconds for burn-in protection (BurnIn generator).
struct LockScreenView: View {
    let message: String
    let burnInInterval: TimeInterval
    let onUnlock: () -> Void

    @State private var textOrigin: CGPoint = .zero
    @State private var buttonOrigin: CGPoint = .zero
    private let textSize = CGSize(width: 360, height: 80)
    private let buttonSize = CGSize(width: 160, height: 44)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                Text(message)
                    .font(.system(size: 28, weight: .thin))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(width: textSize.width, height: textSize.height)
                    .position(x: textOrigin.x + textSize.width / 2,
                              y: textOrigin.y + textSize.height / 2)

                Button(action: onUnlock) {
                    Text("Unlock").frame(width: buttonSize.width, height: buttonSize.height)
                }
                .buttonStyle(.borderedProminent)
                .position(x: buttonOrigin.x + buttonSize.width / 2,
                          y: buttonOrigin.y + buttonSize.height / 2)
            }
            .onAppear { reposition(in: geo.size) }
            .onReceive(Timer.publish(every: burnInInterval, on: .main, in: .common).autoconnect()) { _ in
                reposition(in: geo.size)
            }
        }
    }

    private func reposition(in size: CGSize) {
        var rng = SystemRandomNumberGenerator()
        textOrigin = BurnIn.nextOrigin(container: size, label: textSize, using: &rng)
        buttonOrigin = BurnIn.nextOrigin(container: size, label: buttonSize, using: &rng)
    }
}
