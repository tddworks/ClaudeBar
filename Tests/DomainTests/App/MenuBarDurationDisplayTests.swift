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
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )
    }

    // MARK: - Text formatting

    @Test
    func `should show hours and minutes when the reset is hours away`() {
        let q = quota(resetsAt: Date().addingTimeInterval(3.0 * 3600 + 58.0 * 60 + 30))
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "3:58")
    }

    @Test
    func `should show days when the reset is days away`() {
        let q = quota(resetsAt: Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30))
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "2d")
    }

    @Test
    func `should show minutes when the reset is minutes away`() {
        let q = quota(resetsAt: Date().addingTimeInterval(45.0 * 60 + 30))
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "45m")
    }

    @Test
    func `should show soon when the reset is under a minute away`() {
        let q = quota(resetsAt: Date().addingTimeInterval(30))
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "soon")
    }

    @Test
    func `should show a dash when the reset time is unknown`() {
        let q = quota(resetsAt: nil)
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "—")
    }

    // MARK: - From the provider's reset text, when it gives no date

    private func quota(resetText: String) -> UsageQuota {
        UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "kimi", resetText: resetText)
    }

    @Test
    func `should show the first two parts of the provider's reset text when it gives no reset date`() {
        #expect(MenuBarDurationDisplay(quota: quota(resetText: "Resets in 2d 5h 30m")).text == "2d 5h")
    }

    @Test
    func `should read the provider's reset text whatever its case and spacing`() {
        #expect(MenuBarDurationDisplay(quota: quota(resetText: "RESETS IN 4 H 12 M")).text == "4h 12m")
    }

    @Test
    func `should show a dash when the provider's text is not about a reset`() {
        #expect(MenuBarDurationDisplay(quota: quota(resetText: "12/50 credits")).text == "—")
    }

    @Test
    func `should show a dash when the provider's reset text has no time in it`() {
        #expect(MenuBarDurationDisplay(quota: quota(resetText: "Resets soon")).text == "—")
    }

    // MARK: - Status threading

    @Test
    func `should take the quota's own status when the burn-rate warning is off`() {
        let q = quota(percentRemaining: 15, resetsAt: Date().addingTimeInterval(3600))
        let display = MenuBarDurationDisplay(quota: q, burnRateWarningEnabled: false)
        #expect(display.status == .critical)
    }

    @Test
    func `should show an on-pace quota as healthy when the burn-rate warning is on`() {
        // 40% remaining would be .warning under absolute thresholds, but 4.5h
        // of a 5h session have elapsed (percentTimeElapsed = 90), so usage
        // projects to 60/90 = 0.67 — under the 0.70 warning line. Pace-aware
        // logic lifts the status back to .healthy.
        let q = quota(percentRemaining: 40, resetsAt: Date().addingTimeInterval(1800))
        let display = MenuBarDurationDisplay(quota: q, burnRateWarningEnabled: true, burnRateThreshold: 1.5)
        #expect(display.status == .healthy)
        // Sanity-check: the absolute-threshold path on the same quota returns .warning,
        // confirming this test actually exercises the pace-aware branch.
        #expect(q.status == .warning)
    }
}
