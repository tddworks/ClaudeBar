import Foundation
import Testing
@testable import Quotas

@Suite
struct QuotaLabelTests {
    private func quota(_ type: QuotaType, window: TimeInterval? = nil) -> UsageQuota {
        UsageQuota(percentRemaining: 50, quotaType: type, providerId: "any", windowDuration: window)
    }

    private static let stated: [(QuotaType, TimeInterval, String)] = [
        (.session, 18_000, "5h"),
        (.weekly, 604_800, "7d"),
        (.session, 1_800, "30m"),
        (.weekly, 2_592_000, "30d"),
    ]

    @Test(arguments: stated)
    func `should print a window's length when the provider stated it`(_ type: QuotaType, _ window: TimeInterval, _ expected: String) {
        #expect(QuotaLabel(quota(type, window: window)).short == expected)
    }

    @Test
    func `should say Session, not 5h, when the provider never stated the window`() {
        #expect(QuotaLabel(quota(.session)).short == "Session")
        #expect(QuotaLabel(quota(.weekly)).short == "Weekly")
    }

    @Test
    func `should keep a named quota's name even when its window is stated`() {
        #expect(QuotaLabel(quota(.modelSpecific("opus"), window: 7 * 86400)).short == "Opus")
        #expect(QuotaLabel(quota(.timeLimit("Monthly"), window: 30 * 86400)).short == "Monthly")
    }

    @Test
    func `should keep the name when a window is no whole number of minutes`() {
        #expect(QuotaLabel(quota(.session, window: 90)).short == "Session")
    }

    @Test
    func `should name a quota by what the person calls it`() {
        #expect(QuotaLabel(quota(.session, window: 5 * 3600)).name == "Session")
        #expect(QuotaLabel(quota(.modelSpecific("opus"))).name == "Opus")
    }
}
