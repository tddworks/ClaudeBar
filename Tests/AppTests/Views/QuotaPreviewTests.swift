import Kit
import Foundation
import Testing
@testable import ClaudeBar

/// Map fields' live card speaks the popover's words.
@Suite
struct QuotaPreviewTests {
    @Test func `should preview a share as percent left`() {
        #expect(QuotaPreview.text(UsageQuota(percentRemaining: 62, quotaType: .session, providerId: "x")) == "62% left")
    }

    @Test func `should preview money against a limit as what is left of the limit`() {
        let quota = UsageQuota(left: .money(Money(Decimal(string: "12.4")!, currency: "USD"), of: Money(50, currency: "USD")),
                               quotaType: .timeLimit("Credits"), providerId: "x")
        #expect(QuotaPreview.text(quota) == "$12.40 of $50.00")
    }

    @Test func `should preview a balance as what remains, with no percentage`() {
        let quota = UsageQuota(left: .money(Money(Decimal(string: "7.5")!, currency: "USD"), of: nil),
                               quotaType: .timeLimit("Balance"), providerId: "x")
        #expect(QuotaPreview.text(quota) == "$7.50 remaining")
    }
}

/// A clicked CLI line names its number by what comes before it.
@Suite
struct TextLineLabelTests {
    @Test func `should label a clicked CLI line by the words before its number`() {
        #expect(AddProviderSheet.label(of: "Quota: 42% left") == "Quota")
        #expect(AddProviderSheet.label(of: "5h limit = 80% left") == "5h limit")
        #expect(AddProviderSheet.label(of: "Weekly usage 35%") == "Weekly usage")
    }
}
