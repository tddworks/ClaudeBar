import Foundation
import Testing
import Domain
@testable import ClaudeBar

@Suite
struct MenuBarPercentageDisplayTests {
    @Test
    func `should show a balance as money in the menu bar`() {
        let balance = UsageQuota(left: .money(Money(12.40, currency: "USD"), of: nil), quotaType: .timeLimit("Credits"), providerId: "x")

        #expect(MenuBarPercentageDisplay(quota: balance, mode: .remaining).text == "$12.40")
    }
}
