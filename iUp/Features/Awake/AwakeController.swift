import Foundation
import IOKit.pwr_mgt
import os.log

enum AwakeAssertion: Hashable {
    case displaySleep   // PreventUserIdleDisplaySleep
    case systemSleep    // PreventUserIdleSystemSleep
    case network        // NetworkClientActive
}

protocol AssertionManaging {
    func hold(_ kind: AwakeAssertion)
    func release(_ kind: AwakeAssertion)
    func releaseAll()
}

/// Decides which assertions to hold from the independent sub-toggles and
/// keeps a periodic user-activity declaration alive while active.
final class AwakeController {
    private let settings: Settings
    private let assertions: AssertionManaging
    private(set) var isActive = false

    init(settings: Settings, assertions: AssertionManaging) {
        self.settings = settings
        self.assertions = assertions
    }

    func activate() {
        guard settings.awakeEnabled else { return }
        isActive = true
        if settings.awakeDisplayOn { assertions.hold(.displaySleep) }
        if settings.awakeSystemSleep { assertions.hold(.systemSleep) }
        if settings.awakeNetworkOn { assertions.hold(.network) }
    }

    func deactivate() {
        isActive = false
        assertions.releaseAll()
    }
}

/// Real IOKit-backed assertions. Shell: verified by build + manual run, not unit-tested.
final class IOPMAssertions: AssertionManaging {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Awake")
    private var ids: [AwakeAssertion: IOPMAssertionID] = [:]

    private func typeName(_ kind: AwakeAssertion) -> CFString {
        switch kind {
        case .displaySleep: return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        case .systemSleep:  return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .network:      return "NetworkClientActive" as CFString
        }
    }

    func hold(_ kind: AwakeAssertion) {
        guard ids[kind] == nil else { return }
        var id = IOPMAssertionID(0)
        let r = IOPMAssertionCreateWithName(typeName(kind),
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "iUp keeping Mac awake" as CFString, &id)
        if r == kIOReturnSuccess { ids[kind] = id }
        else { Self.log.error("assertion \(String(describing: kind)) failed: \(r)") }
    }

    func release(_ kind: AwakeAssertion) {
        if let id = ids[kind] { IOPMAssertionRelease(id); ids[kind] = nil }
    }

    func releaseAll() { for k in Array(ids.keys) { release(k) } }
}
