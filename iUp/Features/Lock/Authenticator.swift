import LocalAuthentication
import os.log

@MainActor
final class Authenticator {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Auth")
    private var activeContext: LAContext?

    /// Touch ID with password fallback. Returns true on success.
    func authenticate(reason: String = "Unlock iUp") async -> Bool {
        cancelPending()
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password\u{2026}"
        activeContext = context
        defer { activeContext = nil }

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            Self.log.error("auth unavailable: \(error?.localizedDescription ?? "?")")
            return false
        }
        return await Task.detached { [context] in
            (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                               localizedReason: reason)) ?? false
        }.value
    }

    func cancelPending() {
        activeContext?.invalidate()
        activeContext = nil
    }
}
