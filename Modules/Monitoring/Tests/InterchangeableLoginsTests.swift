import Foundation
import Testing
import Quotas
import DataSources
@testable import Providers
@testable import Monitoring

/// A product's logins are interchangeable (CANONICAL §5): a product has room
/// while one of its logins does, and only products are judged against each
/// other — the menu bar reads the worst product.
@MainActor
@Suite
struct InterchangeableLoginsTests {
    /// Codex with two logins (*personal* and *work*), then Claude with one.
    private func twoLogins() throws -> (QuotaMonitor, codex: Provider, claude: Provider) {
        let settings = InMemoryProviderSettings()
        let work = ProviderAccountConfig(accountId: "work", label: "work", probeConfig: ["folder": "/tmp/work", "accountId": "work"])
        let codex = try ProviderFactory.make("codex", settings: settings, accounts: [work])
        let claude = try ProviderFactory.make("claude", settings: settings)
        return (QuotaMonitor(providers: kept([codex, claude]), clock: SystemClock()), codex, claude)
    }

    private func usage(_ left: Double) -> UsageSnapshot {
        UsageSnapshot(providerId: "p", quotas: [UsageQuota(percentRemaining: left, quotaType: .weekly, providerId: "p")],
                      capturedAt: Date())
    }

    @Test
    func `should keep Codex's header healthy while one of its logins has room`() throws {
        let (monitor, codex, _) = try twoLogins()
        codex.accounts[0].snapshot = usage(0)
        codex.accounts[1].snapshot = usage(62)
        monitor.selectedProviderId = "codex"

        #expect(monitor.selectedTabStatus == .healthy)
        #expect(monitor.selectedBadge == .quota(.healthy))
    }

    @Test
    func `should read Codex's header depleted only when every login is empty`() throws {
        let (monitor, codex, _) = try twoLogins()
        codex.accounts[0].snapshot = usage(0)
        codex.accounts[1].snapshot = usage(0)
        monitor.selectedProviderId = "codex"

        #expect(monitor.selectedBadge == .quota(.depleted))
    }

    @Test
    func `should read the worst product, each by its healthiest login`() throws {
        let (monitor, codex, claude) = try twoLogins()
        codex.accounts[0].snapshot = usage(0)
        codex.accounts[1].snapshot = usage(62)
        claude.defaultAccount.snapshot = usage(15)

        #expect(monitor.overallStatus == .critical)

        claude.defaultAccount.snapshot = usage(80)

        #expect(monitor.overallStatus == .healthy)
    }

    @Test
    func `should lead with the lowest quota among each product's best login`() throws {
        let (monitor, codex, claude) = try twoLogins()
        codex.accounts[0].snapshot = usage(0)
        codex.accounts[1].snapshot = usage(62)
        claude.defaultAccount.snapshot = usage(40)

        #expect(monitor.lowestQuota()?.percentRemaining == 40)
    }

    // MARK: - The login the popover names, under pace-aware

    private func twoLogins(policy: StatusPolicy) throws -> (QuotaMonitor, codex: Provider) {
        let settings = InMemoryProviderSettings()
        let work = ProviderAccountConfig(accountId: "work", label: "work", probeConfig: ["folder": "/tmp/work", "accountId": "work"])
        let codex = try ProviderFactory.make("codex", settings: settings, accounts: [work])
        return (QuotaMonitor(providers: kept([codex]), clock: SystemClock(), statusPolicy: { policy }), codex)
    }

    /// A 5-hour quota with `left` percent left and `elapsed` percent of its window gone.
    private func paced(left: Double, elapsed: Double) -> UsageSnapshot {
        let length: TimeInterval = 5 * 3600
        return UsageSnapshot(providerId: "p", quotas: [
            UsageQuota(percentRemaining: left, quotaType: .session, providerId: "p",
                       resetsAt: Date().addingTimeInterval(length * (100 - elapsed) / 100), windowDuration: length),
        ], capturedAt: Date())
    }

    @Test
    func `should name no login while one login lasts, even when another with more left runs out soon`() throws {
        let (monitor, codex) = try twoLogins(policy: .paceAware)
        codex.accounts[0].snapshot = paced(left: 40, elapsed: 10)   // empty in 20 minutes: critical
        codex.accounts[1].snapshot = paced(left: 35, elapsed: 90)   // lasts: healthy

        #expect(monitor.status(of: codex) == .healthy)
        #expect(monitor.cause(of: codex) == nil)
    }

    @Test
    func `should name the login that sets the product's status under pace-aware, not the one with the most left`() throws {
        let (monitor, codex) = try twoLogins(policy: .paceAware)
        codex.accounts[0].snapshot = paced(left: 40, elapsed: 10)   // empty in 20 minutes: critical
        codex.accounts[1].snapshot = paced(left: 30, elapsed: 50)   // empty in about an hour: warning

        #expect(monitor.status(of: codex) == .warning)
        #expect(monitor.cause(of: codex) === codex.accounts[1])
    }
}
