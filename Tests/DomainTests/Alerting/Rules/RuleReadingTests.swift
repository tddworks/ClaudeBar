import Foundation
import Testing
@testable import Domain

/// What a rule judges: the login's worst quota, as the person sees it.
@MainActor
@Suite
struct RuleReadingTests {
    /// Usage of one product with the given lefts, one session quota each.
    private func usage(_ lefts: Left...) -> UsageSnapshot {
        UsageSnapshot(providerId: "claude",
                      quotas: lefts.map { UsageQuota(left: $0, quotaType: .session, providerId: "claude") },
                      capturedAt: Date())
    }

    /// A login named *Claude* with `usage`.
    private func login(usage: UsageSnapshot?) -> RuleLogin {
        RuleLogin(id: "claude", providerId: "claude", name: "Claude", usage: usage)
    }

    /// The lowest share leads, and its status comes with it.
    @Test func `should judge the login's lowest share`() {
        let reading = RuleReading.worst(of: login(usage: usage(.share(80), .share(20))), under: .absolute)

        #expect(reading?.percentLeft == 20)
        #expect(reading?.status == .warning)
    }

    /// Money with a ceiling is judged by the share it leaves.
    @Test func `should judge money with a ceiling by its share`() {
        let reading = RuleReading.worst(of: login(usage: usage(.money(Money(10), of: Money(50)))), under: .absolute)

        #expect(reading?.percentLeft == 20)
    }

    /// A more severe status leads even when it has no share.
    @Test func `should lead with the more severe status, even without a share`() {
        let reading = RuleReading.worst(
            of: login(usage: usage(.share(30), .money(Money(0), of: nil))),
            under: .absolute
        )

        #expect(reading?.percentLeft == nil)
        #expect(reading?.status == .depleted)
    }

    /// A balance with no ceiling has no share and stays healthy.
    @Test func `should have no share for a balance without a ceiling`() {
        let reading = RuleReading.worst(of: login(usage: usage(.money(Money(12.40), of: nil))), under: .absolute)

        #expect(reading?.percentLeft == nil)
        #expect(reading?.status == .healthy)
    }

    /// The percent is floored to the whole number the person sees.
    @Test func `should floor the percent the person sees`() {
        let reading = RuleReading.worst(of: login(usage: usage(.share(34.9))), under: .absolute)

        #expect(reading?.percentLeft == 34)
    }

    /// The status is read under the person's own policy.
    @Test func `should read the status under the person's policy`() {
        let reading = RuleReading.worst(of: login(usage: usage(.share(45))), under: .absolute)

        #expect(reading?.status == .warning)
    }

    /// A login with no usage, or no quotas, has no reading.
    @Test func `should report no reading for a login with nothing to judge`() {
        #expect(RuleReading.worst(of: login(usage: nil), under: .absolute) == nil)
        #expect(RuleReading.worst(of: login(usage: usage()), under: .absolute) == nil)
    }

    /// The reading names the login, its product and its window.
    @Test func `should name the login and its window`() {
        let reading = RuleReading.worst(of: login(usage: usage(.share(9))), under: .absolute)

        #expect(reading?.login == "Claude")
        #expect(reading?.providerId == "claude")
        #expect(reading?.window == "Session")
    }
}