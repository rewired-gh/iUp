import CoreGraphics
import os.log

/// Real display backend using the private DisplayServices framework for internal
/// brightness, with external-display mirroring/disable as best-effort.
/// PRD allows external control to no-op if infeasible.
final class BrightnessService: DisplayBackend {
    private static let log = Logger(subsystem: "moe.rewired.iUp", category: "Brightness")
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let getFn: GetFn?
    private let setFn: SetFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getFn = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
        setFn = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
    }

    private var internalDisplayID: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    func getInternalBrightness() -> Float? {
        guard let id = internalDisplayID, let getFn else { return nil }
        var value: Float = 0
        return getFn(id, &value) == 0 ? value : nil
    }

    func setInternalBrightness(_ v: Float) {
        guard let id = internalDisplayID, let setFn else { return }
        _ = setFn(id, max(0, min(1, v)))
    }

    func setExternalDisplays(on: Bool) {
        Self.log.info("setExternalDisplays(on: \(on)) — best-effort no-op")
    }
}
