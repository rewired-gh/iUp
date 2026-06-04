import Cocoa
import Carbon
import os.log

/// Installs a cgSession event tap that swallows all key/scroll/tablet events while
/// active. The configured unlock hotkey is allowed through and posts .iUpToggleLock.
final class InputBlocker {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "InputBlocker")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isBlocking = false

    /// Unlock hotkey, refreshed before each block. keyCode + Carbon modifier mask.
    var unlockKeyCode: Int64 = 37          // 'L'
    var unlockModifiers: Int = cmdKey | optionKey | controlKey
    /// Debug-only Escape escape hatch: when true, Esc force-unlocks without auth.
    var debugEscapeEnabled = false

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .scrollWheel,
                                    .tabletPointer, .tabletProximity]
        return types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    }()

    func startBlocking() {
        guard !isBlocking else { return }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return nil }
                let me = Unmanaged<InputBlocker>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = me.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return nil
                }
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    var match = keyCode == me.unlockKeyCode
                    let m = me.unlockModifiers
                    if m & cmdKey != 0 { match = match && flags.contains(.maskCommand) }
                    if m & shiftKey != 0 { match = match && flags.contains(.maskShift) }
                    if m & optionKey != 0 { match = match && flags.contains(.maskAlternate) }
                    if m & controlKey != 0 { match = match && flags.contains(.maskControl) }
                    if match {
                        NotificationCenter.default.post(name: .iUpToggleLock, object: nil)
                    } else if keyCode == 53 && me.debugEscapeEnabled {
                        // Debug escape hatch: Escape force-unlocks without authentication.
                        NotificationCenter.default.post(name: .iUpForceUnlock, object: nil)
                    }
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let eventTap else {
            Self.log.error("event tap creation failed")
            NotificationCenter.default.post(name: .iUpInputBlockerFailed, object: nil)
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isBlocking = true
    }

    func stopBlocking() {
        guard isBlocking else { return }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        eventTap = nil; runLoopSource = nil; isBlocking = false
    }

    deinit { stopBlocking() }
}
