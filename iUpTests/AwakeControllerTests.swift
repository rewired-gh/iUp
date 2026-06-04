import Foundation
import Testing
@testable import iUp

private final class FakeAssertions: AssertionManaging {
    var held: Set<AwakeAssertion> = []
    func hold(_ kind: AwakeAssertion) { held.insert(kind) }
    func release(_ kind: AwakeAssertion) { held.remove(kind) }
    func releaseAll() { held.removeAll() }
}

struct AwakeControllerTests {
    private func settings() -> Settings {
        Settings(defaults: UserDefaults(suiteName: "iup.awake.\(UUID().uuidString)")!)
    }

    @Test func activateHoldsAllEnabledAssertions() {
        let fake = FakeAssertions()
        let s = settings()
        let c = AwakeController(settings: s, assertions: fake)
        c.activate()
        #expect(fake.held == [.displaySleep, .systemSleep, .network])
    }

    @Test func subTogglesAreIndependent() {
        let fake = FakeAssertions()
        let s = settings()
        s.awakeNetworkOn = false
        s.awakeSystemSleep = false
        let c = AwakeController(settings: s, assertions: fake)
        c.activate()
        #expect(fake.held == [.displaySleep])
    }

    @Test func deactivateReleasesAll() {
        let fake = FakeAssertions()
        let c = AwakeController(settings: settings(), assertions: fake)
        c.activate()
        c.deactivate()
        #expect(fake.held.isEmpty)
    }
}
