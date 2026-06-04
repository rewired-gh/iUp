import CoreGraphics

/// Magic value written to a synthetic event's `.eventSourceUserData` field so
/// `ActivityMonitor` can tell iUp-generated input from real user input.
/// This is the single mechanism enforcing "simulated input does not count".
let iUpSyntheticMagic: Int64 = 0x6955_7000  // "iUp\0"

extension CGEvent {
    func tagAsSynthetic() {
        setIntegerValueField(.eventSourceUserData, value: iUpSyntheticMagic)
    }

    var isSyntheticFromiUp: Bool {
        getIntegerValueField(.eventSourceUserData) == iUpSyntheticMagic
    }
}
