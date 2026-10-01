import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The Touch Bar gauge draws the same number the menu bar does (remaining or used,
/// per the display mode), but its colour must follow the quota's status, which is
/// computed from real usage. Thresholding the displayed number painted 93% remaining
/// red and 18% remaining blue in Remaining mode.
@Suite @MainActor
struct TouchBarProviderGaugeToneTests {

    private func gauge(percentRemaining: Double, mode: UsageDisplayMode) -> TouchBarProviderGauge {
        let quota = UsageQuota(percentRemaining: percentRemaining, quotaType: .session, providerId: "claude")
        return TouchBarProviderGauge(
            providerId: "claude",
            name: "Claude",
            percentUsed: quota.displayPercent(mode: mode),
            resetText: "3:29",
            status: quota.status,
            hasQuota: true
        )
    }

    @Test
    func `93 percent remaining is healthy in every display mode`() {
        for mode in [UsageDisplayMode.remaining, .used, .pace] {
            let g = gauge(percentRemaining: 93, mode: mode)
            #expect(g.tone == .healthy, "mode \(mode)")
            #expect(g.isAlarm == false, "mode \(mode)")
        }
    }

    @Test
    func `18 percent remaining is an alarm in every display mode`() {
        for mode in [UsageDisplayMode.remaining, .used, .pace] {
            let g = gauge(percentRemaining: 18, mode: mode)
            #expect(g.tone == .alarm, "mode \(mode)")
            #expect(g.isAlarm == true, "mode \(mode)")
        }
    }

    @Test
    func `tone follows status not the displayed number`() {
        #expect(gauge(percentRemaining: 35, mode: .remaining).tone == .warning)
        #expect(gauge(percentRemaining: 0, mode: .remaining).tone == .alarm)
        #expect(gauge(percentRemaining: 0, mode: .used).tone == .alarm)
    }

    @Test
    func `pace aware status drives the tone`() {
        // Same number, worse status: the driver passes a pace-aware status when burn-rate warning is on.
        let g = TouchBarProviderGauge(
            providerId: "claude", name: "Claude", percentUsed: 93, resetText: nil,
            status: .warning, hasQuota: true
        )
        #expect(g.tone == .warning)
    }

    @Test
    func `no quota has no tone`() {
        let g = TouchBarProviderGauge(
            providerId: "claude", name: "Claude", percentUsed: 0, resetText: nil,
            status: .healthy, hasQuota: false
        )
        #expect(g.tone == .none)
        #expect(g.isAlarm == false)
    }
}
