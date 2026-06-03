import Foundation
import ServiceManagement

protocol LoginRegistrar {
    func register() throws
    func unregister() throws
}

struct SMLoginRegistrar: LoginRegistrar {
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

struct LoginItem {
    private let registrar: LoginRegistrar
    init(registrar: LoginRegistrar = SMLoginRegistrar()) { self.registrar = registrar }

    func apply(enabled: Bool) throws {
        if enabled { try registrar.register() } else { try registrar.unregister() }
    }
}
