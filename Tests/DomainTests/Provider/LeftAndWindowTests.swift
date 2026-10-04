import Foundation
import Testing
@testable import Domain

/// The kernel's two laws (CANONICAL_MODEL §5):
/// `left` is ONE OF TWO — a share, or money; a balance with no ceiling has NO
/// percentage. A window's length is the provider's word, never guessed.
@Suite
struct LeftAndWindowTests {
    // MARK: - Left

    @Test
    func `a balance with no ceiling is money, not 100 percent`() {
        let balance = UsageQuota(
            percentRemaining: 100, quotaType: .timeLimit("AI Gateway Credits"), providerId: "vercel-gateway",
            dollarRemaining: 12.40, currency: "USD"
        )

        #expect(balance.left == .money(Money(12.40, currency: "USD"), of: nil))
        #expect(balance.percentLeft == nil)
        #expect(balance.status == .healthy)
        #expect(balance.pace == .unknown)
    }

    @Test
    func `an empty balance is depleted`() {
        let balance = UsageQuota(left: .money(Money(0, currency: "USD"), of: nil), quotaType: .timeLimit("Credits"), providerId: "x")

        #expect(balance.status == .depleted)
    }

    @Test
    func `money with a ceiling has the share it implies`() {
        let credits = UsageQuota(
            left: .money(Money(12.40, currency: "USD"), of: Money(50, currency: "USD")),
            quotaType: .timeLimit("Credits"), providerId: "openrouter"
        )

        #expect(credits.percentLeft == 24.8)
        #expect(credits.percentRemaining == 24.8)
        #expect(credits.dollarRemaining == 12.40)
        #expect(credits.dollarCap == 50)
        #expect(credits.status == .warning)
    }

    @Test
    func `a share is a percentage`() {
        let session = UsageQuota(percentRemaining: 62, quotaType: .session, providerId: "claude")

        #expect(session.left == .share(62))
        #expect(session.percentLeft == 62)
    }

    @Test
    func `a balance marked unavailable stays a depleted share`() {
        // DeepSeek writes 0 with its balance when `is_available` is false.
        let unavailable = UsageQuota(percentRemaining: 0, quotaType: .modelSpecific("Balance"), providerId: "deepseek", dollarRemaining: 5)

        #expect(unavailable.left == .share(0))
        #expect(unavailable.status == .depleted)
    }

    @Test
    func `the lowest quota is never a balance while a share exists`() {
        let usage = UsageSnapshot(providerId: "x", quotas: [
            UsageQuota(percentRemaining: 100, quotaType: .timeLimit("Credits"), providerId: "x", dollarRemaining: 1),
            UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "x"),
        ], capturedAt: Date())

        #expect(usage.lowestQuota?.quotaType == .session)
    }

    // MARK: - Window

    @Test
    func `pace needs a stated window — the name is never a guess`() {
        let unstated = UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "x",
                                  resetsAt: Date().addingTimeInterval(3600))
        let stated = UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "x",
                                resetsAt: Date().addingTimeInterval(3600), windowDuration: 5 * 3600)

        #expect(unstated.window?.length == nil)
        #expect(unstated.percentTimeElapsed == nil)
        #expect(unstated.pace == .unknown)
        #expect(stated.window?.length == 18_000)
        #expect(stated.percentTimeElapsed != nil)
    }

    @Test
    func `the conventional window is a source's to state`() {
        #expect(QuotaType.session.conventionalWindow == .hours(5))
        #expect(QuotaType.timeLimit("Monthly").conventionalWindow == .days(30))
    }

    // MARK: - The menu bar

    @Test
    func `the menu bar shows a balance as money`() {
        let balance = UsageQuota(left: .money(Money(12.40, currency: "USD"), of: nil), quotaType: .timeLimit("Credits"), providerId: "x")

        #expect(MenuBarPercentageDisplay(quota: balance, mode: .remaining).text == "$12.40")
    }
}
