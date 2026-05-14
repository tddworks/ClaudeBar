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
    func `text shows compact hours when reset is hours away`() {
        let q = quota(resetsAt: Date().addingTimeInterval(3.0 * 3600 + 30))
        let display = MenuBarDurationDisplay(quota: q)
        #expect(display.text == "3h")
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
        let q = quota(percentRemaining: 35, resetsAt: nil)
        let display = MenuBarDurationDisplay(quota: q, burnRateWarningEnabled: true, burnRateThreshold: 1.5)
        #expect(display.status == .warning)
    }
}
