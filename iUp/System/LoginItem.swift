import Foundation
import ServiceManagement

protocol LoginRegistrar {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

struct SMLoginRegistrar: LoginRegistrar {
    var isRegistered: Bool { SMAppService.mainApp.status == .enabled }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

struct LoginItem {
    private let registrar: LoginRegistrar
    init(registrar: LoginRegistrar = SMLoginRegistrar()) { self.registrar = registrar }

    /// The actual current registration state (may differ from a stored preference
    /// if the user changed it in System Settings).
    var isEnabled: Bool { registrar.isRegistered }

    func apply(enabled: Bool) throws {
        if enabled { try registrar.register() } else { try registrar.unregister() }
    }
}
