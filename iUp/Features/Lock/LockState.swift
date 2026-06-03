enum LockState: Equatable {
    case unlocked
    case locking
    case locked
    case unlocking

    func canTransition(to next: LockState) -> Bool {
        switch (self, next) {
        case (.unlocked, .locking),
             (.locking, .locked),
             (.locking, .unlocked),
             (.locked, .unlocking),
             (.unlocking, .locked),
             (.unlocking, .unlocked):
            return true
        default:
            return false
        }
    }
}
