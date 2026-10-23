import Foundation
import Quotas
import Testing
@testable import Providers

/// The pool — a product's logins as one sum of shares: *340% left across
/// 3 logins*. Each unpaused login brings the share it already shows; a
/// paused, never-refreshed or balance-only login brings nothing, and the sum
/// is never corrected by the page (docs/features/providers/quota-pools/design.md).
@MainActor
@Suite
struct PoolTests {
    private let settings = InMemoryProviderSettings()

    /// Codex with the plain login and `added` logins beside it.
    private func codex(withAdded added: Int) throws -> Provider {
        let accounts = (0..<added).map { i in
            ProviderAccountConfig(accountId: "login\(i)", label: "login\(i)",
                                  probeConfig: ["folder": "/tmp/pool-login\(i)", "accountId": "login\(i)"])
        }
        return try ProviderFactory.make("codex", settings: settings, accounts: accounts)
    }

    /// A login's usage whose quotas carry these shares left.
    private func seen(_ quotas: UsageQuota...) -> UsageSnapshot {
        UsageSnapshot(providerId: "codex", quotas: quotas, capturedAt: Date())
    }

    /// A window quota with this share left.
    private func window(_ percent: Double) -> UsageQuota {
        UsageQuota(percentRemaining: percent, quotaType: .weekly, providerId: "codex")
    }

    /// A prepaid balance — money with no ceiling, so no percentage.
    private func balance(_ dollars: Decimal) -> UsageQuota {
        UsageQuota(left: .money(Money(dollars), of: nil), quotaType: .modelSpecific("Credits"), providerId: "codex")
    }

    @Test
    func `should offer no pool while the product has one login`() throws {
        let codex = try codex(withAdded: 0)
        codex.accounts[0].snapshot = seen(window(62))

        #expect(codex.accounts.pool == nil)
    }

    @Test
    func `should sum the logins' shares past a hundred when the family has room`() throws {
        let codex = try codex(withAdded: 2)
        codex.accounts[0].snapshot = seen(window(95))
        codex.accounts[1].snapshot = seen(window(90))
        codex.accounts[2].snapshot = seen(window(88))

        let pool = try #require(codex.accounts.pool)
        #expect(pool.percent == 273)
        #expect(pool.count == 3)
    }

    @Test
    func `should leave a paused login out of the pool`() throws {
        let codex = try codex(withAdded: 2)
        codex.accounts[0].snapshot = seen(window(62))
        codex.accounts[1].snapshot = seen(window(88))
        codex.accounts[2].snapshot = seen(window(90))
        codex.accounts[2].pause()

        let pool = try #require(codex.accounts.pool)
        #expect(pool.percent == 150)
        #expect(pool.count == 2)
    }

    @Test
    func `should leave a login with no usage out rather than guess its share`() throws {
        let codex = try codex(withAdded: 2)
        codex.accounts[0].snapshot = seen(window(62))
        codex.accounts[1].snapshot = seen(window(88))

        let pool = try #require(codex.accounts.pool)
        #expect(pool.percent == 150)
        #expect(pool.count == 2)
    }

    @Test
    func `should leave a balance with no ceiling out, for it has no share`() throws {
        let codex = try codex(withAdded: 1)
        codex.accounts[0].snapshot = seen(window(62))
        codex.accounts[1].snapshot = seen(balance(12))

        let pool = try #require(codex.accounts.pool)
        #expect(pool.percent == 62)
        #expect(pool.count == 1)
    }

    @Test
    func `should say no pool when no login has a share to bring`() throws {
        let codex = try codex(withAdded: 1)
        codex.accounts[0].snapshot = seen(balance(12))
        codex.accounts[1].snapshot = seen(balance(40))

        #expect(codex.accounts.pool == nil)
    }

    @Test
    func `should count each login once, by the tightest window it shows`() throws {
        let codex = try codex(withAdded: 1)
        codex.accounts[0].snapshot = seen(window(62), window(88))
        codex.accounts[1].snapshot = seen(window(40))

        let pool = try #require(codex.accounts.pool)
        #expect(pool.percent == 102)
    }

    @Test
    func `should name the counted logins in the person's order`() throws {
        let codex = try codex(withAdded: 2)
        codex.accounts[0].snapshot = seen(window(62))
        codex.accounts[1].snapshot = seen(window(88))
        codex.accounts[2].snapshot = seen(window(90))

        #expect(codex.accounts.pool?.shares.map(\.loginId) == [
            codex.accounts[0].id, codex.accounts[1].id, codex.accounts[2].id,
        ])
    }
}
