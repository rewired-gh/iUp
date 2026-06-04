import Testing
import Foundation
@testable import iUp

struct SettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "iup.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func defaultsMatchSpec() {
        let s = Settings(defaults: makeDefaults())
        #expect(s.awakeEnabled == true)
        #expect(s.awakeDisplayOn == true)
        #expect(s.awakeSystemSleep == true)
        #expect(s.awakeNetworkOn == true)
        #expect(s.jiggleEnabled == true)
        #expect(s.jiggleIdleStart == 60)
        #expect(s.jiggleInterval == 30)
        #expect(s.tempPauseEnabled == true)
        #expect(s.tempPauseIdle == 60)
        #expect(s.displayControlEnabled == true)
        #expect(s.displayInternalDim == true)
        #expect(s.displayExternalOff == true)
        #expect(s.lockEnabled == true)
        #expect(s.burnInInterval == 30)
        #expect(s.launchAtLogin == false)
        #expect(s.autoStartSession == false)
        #expect(s.debugMode == false)
    }

    @Test func persistsAcrossInstances() {
        let d = makeDefaults()
        let a = Settings(defaults: d)
        a.jiggleIdleStart = 120
        a.awakeNetworkOn = false
        let b = Settings(defaults: d)
        #expect(b.jiggleIdleStart == 120)
        #expect(b.awakeNetworkOn == false)
    }

    @Test func togglesAreIndependent() {
        let s = Settings(defaults: makeDefaults())
        s.awakeEnabled = false
        #expect(s.jiggleEnabled == true)
        #expect(s.tempPauseEnabled == true)
        #expect(s.lockEnabled == true)
    }
}
