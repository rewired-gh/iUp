import Cocoa
import Carbon
import os.log

/// Listen-only event tap on a dedicated thread. Fires .iUpToggleLock when the
/// configured lock hotkey is pressed. Default: control+option+command+L.
final class HotkeyManager {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Hotkey")
    private var eventTap: CFMachPort?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private(set) var isRegistered = false

    var keyCode: Int = 37                                   // 'L'
    var modifiers: Int = cmdKey | optionKey | controlKey

    func register() {
        if isRegistered { if AXIsProcessTrusted() { return }; unregister() }
        guard AXIsProcessTrusted() else { Self.log.warning("no accessibility"); return }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: { _, type, event, refcon in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let me = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = me.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                guard keyCode == me.keyCode else { return Unmanaged.passUnretained(event) }
                var match = true
                let m = me.modifiers
                if m & cmdKey != 0 { match = match && flags.contains(.maskCommand) }
                if m & shiftKey != 0 { match = match && flags.contains(.maskShift) }
                if m & optionKey != 0 { match = match && flags.contains(.maskAlternate) }
                if m & controlKey != 0 { match = match && flags.contains(.maskControl) }
                if match {
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .iUpToggleLock, object: nil) }
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
