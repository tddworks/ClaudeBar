import Testing
import Foundation
@testable import Domain

@Suite
struct MenuBarDurationDisplayTests {

    private func quota(
        percentRemaining: Double = 50,
        resetsAt: Date? = nil
    ) -> UsageQuota {
        UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
    }

    // MARK: - Text formatting

    @Test
    func `text shows hours with minutes when reset is hours away`() {
        let q = quota(resetsAt: Date().addingTimeInterval(3.0 * 3600 + 58.0 * 60 + 30))
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "3:58")
    }

    @Test
    func `text shows compact days when reset is days away`() {
        let q = quota(resetsAt: Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30))
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "2d")
    }

    @Test
    func `text shows compact minutes when reset is minutes away`() {
        let q = quota(resetsAt: Date().addingTimeInterval(45.0 * 60 + 30))
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "45m")
    }

    @Test
    func `text shows soon when reset is under a minute`() {
        let q = quota(resetsAt: Date().addingTimeInterval(30))
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "soon")
    }

    @Test
    func `text falls back to em dash when reset is unknown`() {
        let q = quota(resetsAt: nil)
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "—")
    }

    // MARK: - Status threading

    @Test
    func `status reflects underlying quota status when burn rate warning disabled`() {
        let q = quota(percentRemaining: 15, resetsAt: Date().addingTimeInterval(3600))
        let display = MenuBarDurationDisplay(quota: q, burnRateWarningEnabled: false)
        #expect(display.status == .critical)
    }

    @Test
    func `status uses pace aware logic when burn rate warning enabled`() {
        // 35% remaining would be .warning under absolute thresholds, but 4h
        // of a 5h session have elapsed (percentTimeElapsed = 80), so the burn
        // rate is 65/80 = 0.81 — well under the 1.5 threshold. Pace-aware
        // logic lifts the status back to .healthy.
        let q = quota(percentRemaining: 35, resetsAt: Date().addingTimeInterval(3600))
        let display = MenuBarDurationDisplay(quota: q, burnRateWarningEnabled: true, burnRateThreshold: 1.5)
        #expect(display.status == .healthy)
        // Sanity-check: the absolute-threshold path on the same quota returns .warning,
        // confirming this test actually exercises the pace-aware branch.
        #expect(q.status == .warning)
    }
}
