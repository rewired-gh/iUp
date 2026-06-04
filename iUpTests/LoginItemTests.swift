import Testing
@testable import iUp

private final class FakeRegistrar: LoginRegistrar {
    var registered = false
    func register() throws { registered = true }
    func unregister() throws { registered = false }
}

struct LoginItemTests {
    @Test func enableRegisters() throws {
        let r = FakeRegistrar()
        let item = LoginItem(registrar: r)
        try item.apply(enabled: true)
        #expect(r.registered == true)
    }
    @Test func disableUnregisters() throws {
        let r = FakeRegistrar()
        let item = LoginItem(registrar: r)
        try item.apply(enabled: true)
        try item.apply(enabled: false)
        #expect(r.registered == false)
    }
}
