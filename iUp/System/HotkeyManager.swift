import Cocoa
import Carbon
import os.log

/// Listen-only event tap on a dedicated thread. Fires `.iUpToggleLock` for the lock
/// hotkey (default ⌃⌥⌘L) and `.iUpToggleSession` for the session hotkey (default ⌃⌥⌘S).
/// Modifier matching is exact: extra modifiers do not trigger.
final class HotkeyManager {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Hotkey")
    private var eventTap: CFMachPort?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private(set) var isRegistered = false

    // Lock hotkey: ⌃⌥⌘L
    var lockKeyCode: Int = 37
    var lockModifiers: Int = cmdKey | optionKey | controlKey
    // Session-toggle hotkey: ⌃⌥⌘S
    var sessionKeyCode: Int = 1
    var sessionModifiers: Int = cmdKey | optionKey | controlKey

    private static func exactMatch(_ event: CGEvent, keyCode: Int, modifiers: Int) -> Bool {
        guard Int(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode else { return false }
        let f = event.flags
        func required(_ m: Int) -> Bool { modifiers & m != 0 }
        return f.contains(.maskCommand)   == required(cmdKey)
            && f.contains(.maskShift)     == required(shiftKey)
            && f.contains(.maskAlternate) == required(optionKey)
            && f.contains(.maskControl)   == required(controlKey)
    }

    func register() {
        if isRegistered { if AXIsProcessTrusted() { return }; unregister() }
        guard AXIsProcessTrusted() else { Self.log.warning("no accessibility"); return }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = me.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                if HotkeyManager.exactMatch(event, keyCode: me.lockKeyCode, modifiers: me.lockModifiers) {
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .iUpToggleLock, object: nil) }
                } else if HotkeyManager.exactMatch(event, keyCode: me.sessionKeyCode, modifiers: me.sessionModifiers) {
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .iUpToggleSession, object: nil) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard eventTap != nil else { Self.log.error("tap failed"); return }

        let thread = Thread { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "moe.rewired.iUp.hotkey"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
        isRegistered = true
    }

    func unregister() {
        guard isRegistered else { return }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        tapRunLoop = nil; tapThread = nil; eventTap = nil; isRegistered = false
    }

    deinit { unregister() }
}
