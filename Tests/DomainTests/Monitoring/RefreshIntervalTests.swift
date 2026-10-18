import Testing
import Foundation
@testable import Domain

@Suite
struct RefreshIntervalTests {
    /// Each cadence exposes its poll interval in seconds, and `.off` has none.
    @Test
    func `should poll every 1, 5, 10 or 15 minutes, and never when refresh is off`() {
        #expect(RefreshInterval.off.seconds == nil)
        #expect(RefreshInterval.oneMinute.seconds == 60)
        #expect(RefreshInterval.fiveMinutes.seconds == 300)
        #expect(RefreshInterval.tenMinutes.seconds == 600)
        #expect(RefreshInterval.fifteenMinutes.seconds == 900)
    }

    /// Only `.off` disables background refresh; every timed option enables it.
    @Test
    func `should refresh in the background for every option except off`() {
        #expect(RefreshInterval.off.isEnabled == false)
        #expect(RefreshInterval.oneMinute.isEnabled == true)
        #expect(RefreshInterval.fiveMinutes.isEnabled == true)
        #expect(RefreshInterval.tenMinutes.isEnabled == true)
        #expect(RefreshInterval.fifteenMinutes.isEnabled == true)
    }

    /// Each option's picker label matches the exact copy shown in Settings.
    @Test
    func `should label each option as Settings' picker shows it`() {
        #expect(RefreshInterval.off.label == "Off")
        #expect(RefreshInterval.oneMinute.label == "1 min")
        #expect(RefreshInterval.fiveMinutes.label == "5 min")
        #expect(RefreshInterval.tenMinutes.label == "10 min")
        #expect(RefreshInterval.fifteenMinutes.label == "15 min")
    }

    /// A disabled legacy `backgroundSyncEnabled` flag migrates to `.off`
    /// regardless of the stored interval.
    @Test
    func `should turn refresh off when the old background sync was disabled`() {
        #expect(RefreshInterval.migrating(enabled: false, storedSeconds: 60) == .off)
        #expect(RefreshInterval.migrating(enabled: false, storedSeconds: 900) == .off)
    }

    /// An enabled legacy interval snaps to the nearest supported option, with
    /// retired and below-floor values rounding up to the 1-minute floor.
    @Test
    func `should move an old saved interval to the nearest offered one, never below one minute`() {
        // Retired 30s / 2m options and below-floor values snap up to 1 minute.
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 30) == .oneMinute)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 60) == .oneMinute)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 120) == .oneMinute)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 300) == .fiveMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 600) == .tenMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 700) == .tenMinutes)
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 900) == .fifteenMinutes)
    }

    /// The persisted default cadence (600s, issue #204) migrates to the 10-minute
    /// option, so a freshly-enabled background sync lands on the power-conscious
    /// default rather than the old 1-minute poll.
    @Test
    func `should move the old 600-second default to ten minutes (#204)`() {
        #expect(RefreshInterval.migrating(enabled: true, storedSeconds: 600) == .tenMinutes)
    }

    /// `allCases` is ordered exactly as the segmented picker renders the options.
    @Test
    func `should offer the options in picker order, from off to fifteen minutes`() {
        #expect(RefreshInterval.allCases == [.off, .oneMinute, .fiveMinutes, .tenMinutes, .fifteenMinutes])
    }
}
