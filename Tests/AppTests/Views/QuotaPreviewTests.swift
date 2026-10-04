import Domain
import Foundation
import Testing
@testable import ClaudeBar

/// Map fields' live card speaks the popover's words.
@Suite
struct QuotaPreviewTests {
    @Test func `a share reads as percent left`() {
        #expect(QuotaPreview.text(UsageQuota(percentRemaining: 62, quotaType: .session, providerId: "x")) == "62% left")
    }

    @Test func `money of a limit reads as remaining of limit`() {
        let quota = UsageQuota(left: .money(Money(Decimal(string: "12.4")!, currency: "USD"), of: Money(50, currency: "USD")),
                               quotaType: .timeLimit("Credits"), providerId: "x")
        #expect(QuotaPreview.text(quota) == "$12.40 of $50.00")
    }

    @Test func `a balance reads as remaining, with no percentage`() {
        let quota = UsageQuota(left: .money(Money(Decimal(string: "7.5")!, currency: "USD"), of: nil),
                               quotaType: .timeLimit("Balance"), providerId: "x")
        #expect(QuotaPreview.text(quota) == "$7.50 remaining")
    }
}

/// A clicked CLI line names its number by what comes before it.
@Suite
struct TextLineLabelTests {
    @Test func `a line's label is what stays once its number goes`() {
        #expect(AddProviderSheet.label(of: "Quota: 42% left") == "Quota")
        #expect(AddProviderSheet.label(of: "5h limit = 80% left") == "5h limit")
        #expect(AddProviderSheet.label(of: "Weekly usage 35%") == "Weekly usage")
    }
}
