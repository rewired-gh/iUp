import AppKit
import CoreGraphics
import os.log

/// Built-in display brightness control.
///
/// On current macOS the private absolute-brightness APIs (DisplayServices /
/// CoreDisplay) are unreliable for third-party apps, so this combines two paths:
///  1. Best-effort absolute set via DisplayServices + CoreDisplay (works in some
///     signed contexts; harmless no-op otherwise).
///  2. Brightness hardware-key simulation, which reliably drives the real backlight.
///
/// Restore only bumps the backlight up if we previously dimmed it (so it never
/// raises brightness that was already at its minimum). External-display control is
/// best-effort (PRD allows it to no-op).
final class BrightnessService: DisplayBackend {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Brightness")

    private typealias DSGet = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSet = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CDGet = @convention(c) (CGDirectDisplayID) -> Double
    private typealias CDSet = @convention(c) (CGDirectDisplayID, Double) -> Void

    private let dsGet: DSGet?
    private let dsSet: DSSet?
    private let cdGet: CDGet?
    private let cdSet: CDSet?
    private let dsHandle: UnsafeMutableRawPointer?
    private let cdHandle: UnsafeMutableRawPointer?

    /// macOS exposes 16 coarse brightness steps via the hardware keys.
    private static let keySteps = 16
    private static let minFraction: Float = 1.0 / Float(keySteps)
    /// The real backlight level can't be read on macOS 26, so restore goes to a
    /// fixed, comfortable mid-level (50%) rather than a remembered value.
    private static let restoreFraction: Float = 0.5
    /// NX_KEYTYPE_BRIGHTNESS_UP / _DOWN from <IOKit/hidsystem/ev_keymap.h>.
    private static let keyBrightnessUp = 2
    private static let keyBrightnessDown = 3
    /// True while we have driven the backlight down and not yet restored it.
    private var didKeyDim = false

    init() {
        let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        let cd = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW)
        dsHandle = ds
        cdHandle = cd
        dsGet = dlsym(ds, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: DSGet.self) }
        dsSet = dlsym(ds, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: DSSet.self) }
        cdGet = dlsym(cd, "CoreDisplay_Display_GetUserBrightness").map { unsafeBitCast($0, to: CDGet.self) }
        cdSet = dlsym(cd, "CoreDisplay_Display_SetUserBrightness").map { unsafeBitCast($0, to: CDSet.self) }
    }

    deinit {
        if let dsHandle { dlclose(dsHandle) }
        if let cdHandle { dlclose(cdHandle) }
    }

    /// The built-in display, or nil if this Mac has none (feature unavailable).
    private var internalDisplayID: CGDirectDisplayID? {
        let main = CGMainDisplayID()
        if CGDisplayIsBuiltin(main) != 0 { return main }
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// Best-effort read. Returns a value whenever a built-in display exists (so the
    /// feature is considered available), falling back to 1.0 if the read is blocked.
    func getInternalBrightness() -> Float? {
        guard let id = internalDisplayID else { return nil }
        if let dsGet {
            var v: Float = 0
            if dsGet(id, &v) == 0 { return v }
        }
        if let cdGet { return Float(cdGet(id)) }
        return 1.0
    }

    func setInternalBrightness(_ v: Float) {
        guard let id = internalDisplayID else { return }
        let clamped = max(0, min(1, v))

        // 1. Best-effort absolute private API.
        _ = dsSet?(id, clamped)
        cdSet?(id, Double(clamped))

        // 2. Reliable hardware-key simulation.
        if clamped <= Self.minFraction {
            // Dim to the hardware floor: press brightness-down a full sweep (plus a
            // margin) so the backlight bottoms out from any starting level.
            pressBrightnessKey(up: false, times: Self.keySteps + 2)
            didKeyDim = true
        } else if didKeyDim {
            // Restore: only bump up if we actually dimmed. The prior level is
            // unreadable, so step up from the floor to a fixed 50%.
            let steps = max(1, Int((Self.restoreFraction * Float(Self.keySteps)).rounded()))
            pressBrightnessKey(up: true, times: steps)
            didKeyDim = false
        }
    }

    func setExternalDisplays(on: Bool) {
        Self.log.info("setExternalDisplays(on: \(on)) — best-effort no-op")
    }

    // MARK: - Brightness key simulation

    /// Post N brightness up/down hardware key presses via NSSystemDefined events.
    private func pressBrightnessKey(up: Bool, times: Int) {
        let key = up ? Self.keyBrightnessUp : Self.keyBrightnessDown
        for _ in 0..<times {
            postAuxKey(key, keyDown: true)
            postAuxKey(key, keyDown: false)
        }
    }

    private func postAuxKey(_ key: Int, keyDown: Bool) {
        let data1 = (key << 16) | ((keyDown ? 0xA : 0xB) << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyDown ? 0xA00 : 0xB00)),
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, subtype: 8, data1: data1, data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
