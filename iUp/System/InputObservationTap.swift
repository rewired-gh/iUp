import Cocoa
import os.log

/// Listen-only session tap observing all mouse/keyboard input. For each event it
/// calls `onEvent(isSynthetic:)`. Synthetic = events iUp itself posted (tagged).
/// Runs on a dedicated thread to avoid the LSUIElement main-runloop activation issue.
final class InputObservationTap {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "InputObs")
    private var eventTap: CFMachPort?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private(set) var isRunning = false
    private let onEvent: (_ isSynthetic: Bool) -> Void

    init(onEvent: @escaping (_ isSynthetic: Bool) -> Void) { self.onEvent = onEvent }

    private static let mask: CGEventMask = {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                    .leftMouseDragged, .rightMouseDragged, .scrollWheel,
                                    .keyDown, .flagsChanged, .tabletPointer]
        return types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    }()

    func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else { Self.log.warning("no accessibility"); return }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: Self.mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<InputObservationTap>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = me.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        if !CGEvent.tapIsEnabled(tap: tap) {
                            // Could not re-enable — Accessibility likely revoked.
                            NotificationCenter.default.post(name: .iUpInputServicesStalled, object: nil)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
                me.onEvent(event.isSyntheticFromiUp)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard eventTap != nil else { Self.log.error("tap failed"); return }
        let t = Thread { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            self.runLoop = CFRunLoopGetCurrent()
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        t.name = "moe.rewired.iUp.inputobs"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
        isRunning = true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = runLoop { CFRunLoopStop(rl) }
        eventTap = nil; runLoop = nil; thread = nil
        isRunning = false
    }

    deinit { stop() }
}
