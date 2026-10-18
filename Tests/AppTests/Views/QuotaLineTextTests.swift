import Domain
import Foundation
import Testing
@testable import ClaudeBar

/// The words a quota line prints, on the ring card and the *Bars* page alike.
@Suite
struct QuotaLineTextTests {
    @Test
    func `should name a quota by its compact title`() {
        let quota = UsageQuota(percentRemaining: 62, quotaType: .timeLimit("Premium requests"), providerId: "x")
        #expect(QuotaLineText.title(quota) == "Premium requests")
    }

    @Test
    func `should put the login first when lines need telling apart`() {
        let quota = UsageQuota(percentRemaining: 62, quotaType: .session, providerId: "x")
        #expect(QuotaLineText.title(quota, login: "a@b.com", shown: { $0 }) == "a@b.com · Session")
    }

    @Test
    func `should read a percentage in the display mode asked`() {
        let quota = UsageQuota(percentRemaining: 62, quotaType: .session, providerId: "x")
        #expect(QuotaLineText.value(quota, mode: .remaining) == "62%")
        #expect(QuotaLineText.value(quota, mode: .used) == "38%")
    }

    @Test
    func `should read a balance as its amount, with no percentage`() {
        let quota = UsageQuota(left: .money(Money(Decimal(string: "7.5")!, currency: "USD"), of: nil),
                               quotaType: .timeLimit("Balance"), providerId: "x")
        #expect(QuotaLineText.value(quota, mode: .remaining) == "$7.50")
    }
}
