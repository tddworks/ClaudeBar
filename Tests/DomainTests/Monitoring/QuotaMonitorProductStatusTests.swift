import Foundation
import Mockable
import Testing
@testable import Domain

/// A product's status as the person sees it — the one read the popover,
/// the menu-bar icon and *Rest when empty* share: its healthiest counted login's — depleted only when
/// every counted login is —, under the policy, with paused logins and logins
/// without usage left out
/// (docs/features/monitoring/rest-when-empty/design.md §2).
@MainActor
@Suite
struct QuotaMonitorProductStatusTests {
    private func quota(_ left: Double) -> UsageQuota {
        UsageQuota(percentRemaining: left, quotaType: .session, providerId: "p")
    }

    private func snapshot(_ quotas: UsageQuota...) -> UsageSnapshot {
        UsageSnapshot(providerId: "p", quotas: quotas, capturedAt: Date())
    }

    private func product(_ id: String, probe: any UsageProbe) -> (QuotaMonitor, Provider) {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let product = stubbedProduct(id, probe: probe, settings: settings)
        return (QuotaMonitor(providers: kept([product])), product)
    }

    @Test
    func `should read a product by its login's worst quota`() async throws {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(snapshot(quota(80), quota(3)))
        let (monitor, product) = product("claude", probe: probe)

        await monitor.refresh(providerId: "claude")

        // One login holds a session with room and one nearly out: the login
        // reads the worst of its quotas (CANONICAL §1), and the product
        // reads its one login. A login with room beside an emptier one is
        // the pool law — InterchangeableLoginsTests.
        #expect(monitor.status(of: product) == .critical)
    }

    @Test
    func `should read a product as depleted when every login with usage is out`() async throws {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(snapshot(quota(0)))
        let (monitor, product) = product("claude", probe: probe)

        await monitor.refresh(providerId: "claude")

        #expect(monitor.status(of: product) == .depleted)
    }

    @Test
    func `should count a single login's product as depleted when it is out`() async throws {
        // Mia's one Claude login is a whole product: it alone decides.
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(snapshot(quota(0), quota(0)))
        let (monitor, product) = product("claude", probe: probe)

        await monitor.refresh(providerId: "claude")

        #expect(monitor.status(of: product) == .depleted)
    }

    @Test
    func `should read no status for a product none of whose logins has usage`() async throws {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willThrow(UsageError.executionFailed("not set up"))
        let (monitor, product) = product("claude", probe: probe)

        await monitor.refresh(providerId: "claude")

        // *Not set up* — or a fetch that failed — is not *empty*.
        #expect(monitor.status(of: product) == nil)
    }

    @Test
    func `should leave a paused login out of the product's status`() async throws {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(snapshot(quota(80)))
        let (monitor, product) = product("claude", probe: probe)
        await monitor.refresh(providerId: "claude")

        monitor.pause(product.defaultAccount)

        #expect(monitor.status(of: product) == nil)
    }
}
