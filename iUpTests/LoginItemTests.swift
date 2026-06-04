import Testing
@testable import iUp

private final class FakeRegistrar: LoginRegistrar {
    var registered = false
    var isRegistered: Bool { registered }
    func register() throws { registered = true }
    func unregister() throws { registered = false }
}

private struct FailingRegistrar: LoginRegistrar {
    var isRegistered: Bool { false }
    struct Boom: Error {}
    func register() throws { throw Boom() }
    func unregister() throws { throw Boom() }
}

struct LoginItemTests {
    @Test func enableRegisters() throws {
        let r = FakeRegistrar()
        let item = LoginItem(registrar: r)
        try item.apply(enabled: true)
        #expect(r.registered == true)
        #expect(item.isEnabled == true)
    }
    @Test func disableUnregisters() throws {
        let r = FakeRegistrar()
        let item = LoginItem(registrar: r)
        try item.apply(enabled: true)
        try item.apply(enabled: false)
        #expect(r.registered == false)
        #expect(item.isEnabled == false)
    }
    @Test func applyPropagatesErrors() {
        let item = LoginItem(registrar: FailingRegistrar())
        #expect(throws: (any Error).self) { try item.apply(enabled: true) }
    }
}
