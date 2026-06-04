import Testing
@testable import iUp

struct LockStateTests {
    @Test func validTransitions() {
        #expect(LockState.unlocked.canTransition(to: .locking))
        #expect(LockState.locking.canTransition(to: .locked))
        #expect(LockState.locking.canTransition(to: .unlocked))
        #expect(LockState.locked.canTransition(to: .unlocking))
        #expect(LockState.unlocking.canTransition(to: .locked))
        #expect(LockState.unlocking.canTransition(to: .unlocked))
    }

    @Test func invalidTransitions() {
        #expect(!LockState.unlocked.canTransition(to: .locked))
        #expect(!LockState.unlocked.canTransition(to: .unlocking))
        #expect(!LockState.locked.canTransition(to: .unlocked))
        #expect(!LockState.locked.canTransition(to: .locking))
    }
}
