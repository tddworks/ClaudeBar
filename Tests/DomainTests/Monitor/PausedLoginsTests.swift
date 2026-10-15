import Foundation
import Testing
import Mockable
@testable import Domain
@testable import Infrastructure

/// A login paused from the popover: it stays on its product's page with a
/// *Resume*, and is out of every judgement
/// (docs/features/multi-account/design.md §3.5).
@MainActor
@Suite
struct PausedLoginsTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private let temp = FileManager.default.temporaryDirectory.appendingPathComponent("paused-logins-\(UUID().uuidString)")

    /// Codex with two logins (*personal* and *work*), then Claude with one.
    private func twoLogins() throws -> (QuotaMonitor, codex: Provider, claude: Provider) {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("settings.json")))
        let work = ProviderAccountConfig(accountId: "work", label: "work", probeConfig: ["codexHome": "/tmp/work", "chatgptAccountId": "work"])
        let codex = try ProviderFactory.make("codex", settings: settings, accounts: [work])
        let claude = try ProviderFactory.make("claude", settings: settings)
        return (QuotaMonitor(providers: kept([codex, claude])), codex, claude)
    }

    private func quota(_ left: Double) -> UsageQuota {
        UsageQuota(percentRemaining: left, quotaType: .session, providerId: "p")
    }

    private func snapshot(_ quotas: UsageQuota...) -> UsageSnapshot {
        UsageSnapshot(providerId: "p", quotas: quotas, capturedAt: Date())
    }

    /// What the person was told, so a test can read it.
    private actor RecordingAlerter: QuotaAlerter {
        private(set) var alerts: [String] = []

        func requestPermission() async -> Bool { true }

        func alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) async {
            alerts.append(providerId)
        }
    }

    /// A fetch that waits for `open()` — so a test can pause a login while its
    /// refresh is still in flight.
    private actor GatedProbe: UsageProbe {
        private let usage: UsageSnapshot
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(_ usage: UsageSnapshot) { self.usage = usage }

        func isAvailable() async -> Bool { true }

        func probe() async throws -> UsageSnapshot {
            if !isOpen { await withCheckedContinuation { waiters.append($0) } }
            return usage
        }

        func open() {
            isOpen = true
            let waiting = waiters
            waiters = []
            waiting.forEach { $0.resume() }
        }
    }

    /// A product whose fetch answers `usage`, watched until the person pauses it.
    private func watchedProduct(_ id: String, _ usage: UsageSnapshot) -> (QuotaMonitor, Provider) {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(usage)
        let product = stubbedProduct(id, probe: probe, settings: settings)
        return (QuotaMonitor(providers: kept([product])), product)
    }

    // MARK: - The page

    @Test
    func `should keep a paused login on the product's page with its last numbers`() async throws {
        let (monitor, product) = watchedProduct("codex", snapshot(quota(18)))
        await monitor.refresh(providerId: "codex")

        monitor.pause(product.defaultAccount)

        let tab = try #require(monitor.tabs.first)
        #expect(tab.logins.map(\.id) == ["codex"])
        #expect(tab.paused.map(\.id) == ["codex"])
        #expect(tab.watched.isEmpty)
        #expect(product.defaultAccount.snapshot?.quotas.first?.percentRemaining == 18)
    }

    @Test
    func `should take a paused login out of a product's chips while its siblings stay`() throws {
        let (monitor, codex, _) = try twoLogins()

        monitor.pause(codex.accounts[1])

        let tab = try #require(monitor.tabs.first { $0.id == "codex" })
        #expect(tab.logins.map(\.id) == ["codex", "codex.work"])
        #expect(tab.watched.map(\.id) == ["codex"])
        #expect(tab.paused.map(\.id) == ["codex.work"])
    }

    @Test
    func `should watch a login again when the person resumes it`() throws {
        let (monitor, codex, _) = try twoLogins()

        monitor.pause(codex.accounts[1])
        monitor.resume(codex.accounts[1])

        let tab = try #require(monitor.tabs.first { $0.id == "codex" })
        #expect(tab.paused.isEmpty)
        #expect(monitor.lineup.map(\.id) == ["codex", "codex.work", "claude"])
    }

    // MARK: - Pause and the product's switch are two facts

    @Test
    func `should keep the product's tab while every one of its logins is paused`() throws {
        let (monitor, codex, _) = try twoLogins()

        monitor.pause(codex.defaultAccount)
        monitor.pause(codex.accounts[1])

        let tab = try #require(monitor.tabs.first { $0.id == "codex" })
        #expect(tab.watched.isEmpty)
        #expect(tab.paused.count == 2)
        #expect(tab.showsAccountPages)
    }

    @Test
    func `should take the product's tab away when the person turns the product off`() throws {
        let (monitor, codex, _) = try twoLogins()
        monitor.pause(codex.accounts[1])

        monitor.setProductEnabled(monitor.productTabs[0], enabled: false)

        #expect(monitor.tabs.map(\.id) == ["claude"])
    }

    @Test
    func `should show a product's page as its logins when none of them is watched`() throws {
        let (monitor, _, _) = try twoLogins()
        let claude = try #require(monitor.tabs.first { $0.id == "claude" })
        #expect(!claude.showsAccountPages)

        monitor.pause(claude.watched[0])

        #expect(monitor.tabs.first { $0.id == "claude" }?.showsAccountPages == true)
    }

    // MARK: - The selection

    @Test
    func `should stay on the product whose login the person paused`() throws {
        let (monitor, codex, _) = try twoLogins()
        monitor.selectedProviderId = "codex.work"

        monitor.pause(codex.accounts[1])

        #expect(monitor.selectedTab?.id == "codex")
    }

    @Test
    func `should leave a paused login out of the page's badge`() async throws {
        let (monitor, product) = watchedProduct("claude", snapshot(quota(9)))
        await monitor.refresh(providerId: "claude")
        #expect(monitor.selectedBadge == .quota(.critical))

        monitor.pause(product.defaultAccount)

        #expect(monitor.selectedTabStatus == nil)
        #expect(monitor.selectedBadge == .paused)
    }

    // MARK: - The other pages

    @Test
    func `should leave a paused login out of the All page`() async throws {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(snapshot(quota(9)))
        let claude = stubbedProduct("claude", probe: probe, settings: settings)
        let gemini = stubbedProduct("gemini", probe: probe, settings: settings)
        let monitor = QuotaMonitor(providers: kept([claude, gemini]))
        await monitor.refresh(providerId: "claude")
        #expect(Overview(monitor).cards.map(\.id) == ["claude", "gemini"])

        monitor.pause(claude.defaultAccount)

        #expect(Overview(monitor).cards.map(\.id) == ["gemini"])
    }

    @Test
    func `should stop refreshing a login the person paused`() async throws {
        let (monitor, product) = watchedProduct("claude", snapshot(quota(62)))
        await monitor.refresh(providerId: "claude")
        let seen = product.defaultAccount.snapshot?.capturedAt

        monitor.pause(product.defaultAccount)
        await monitor.refreshAll()

        #expect(monitor.lineup.isEmpty)
        #expect(product.defaultAccount.snapshot?.capturedAt == seen)
    }

    @Test
    func `should publish nothing for a login paused while its refresh is in flight`() async throws {
        // Given — a fetch held open, so the login can be paused while it runs
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let probe = GatedProbe(snapshot(quota(9)))
        let product = stubbedProduct("claude", probe: probe, settings: settings)
        let alerter = RecordingAlerter()
        let monitor = QuotaMonitor(providers: kept([product]), alerter: alerter, clock: TestClock())

        // When — she pauses the login, and only then lets the fetch land
        let inFlight = Task { await monitor.refreshAll() }
        try await Task.sleep(for: .milliseconds(50))
        monitor.pause(product.defaultAccount)
        await probe.open()
        await inFlight.value

        // Then — nothing was fetched into it, and nobody was paged about it
        #expect(product.defaultAccount.snapshot == nil)
        #expect(await alerter.alerts.isEmpty)
    }
}
