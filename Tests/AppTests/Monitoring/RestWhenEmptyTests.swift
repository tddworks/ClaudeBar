import Foundation
import Infrastructure
import Testing
@testable import Domain

/// *Rest when empty*: a product whose every counted login is depleted rests,
/// dimmed, until the first refresh that shows room, telling the person both
/// times. Its switch is never touched, and where it is survives a relaunch
/// (docs/features/monitoring/rest-when-empty/design.md).
@MainActor
@Suite
struct RestWhenEmptyTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private let temp = FileManager.default.temporaryDirectory.appendingPathComponent("rest-when-empty-\(UUID().uuidString)")
    private let noon = Date(timeIntervalSince1970: 1_761_220_000)

    /// A connection whose answer the test rewrites between refreshes: usage,
    /// or nothing — a failed fetch is never empty and never recovery.
    private actor ScriptedProbe: UsageProbe {
        var usage: UsageSnapshot?

        func answer(with usage: UsageSnapshot?) { self.usage = usage }

        func isAvailable() async -> Bool { true }

        func probe() async throws -> UsageSnapshot {
            guard let usage else { throw UsageError.executionFailed("scripted failure") }
            return usage
        }
    }

    /// What the person was told, so a test can read it.
    private final class Announced: RestWhenEmptyAnnouncer, @unchecked Sendable {
        var notices: [RestNotice] = []
        func announce(_ notice: RestNotice) async { notices.append(notice) }
    }

    /// Everything a test drives, together.
    @MainActor
    private struct Rig {
        let monitor: QuotaMonitor
        let product: Provider
        let rest: RestWhenEmpty
        let told: Announced
        let probe: ScriptedProbe
        /// The settings the state is saved in, read directly, so a test
        /// asserts what was persisted.
        let settings: JSONSettingsRepository

        var saved: WhenEmpty? { settings.whenEmpty(forProvider: product.id) }
    }

    /// One product with one login (Mia's one Claude is the main case), real
    /// settings on disk, and the follower following the Monitor as the app does.
    private func rig(_ id: String = "claude", secondLogin: Bool = false, file: String = "settings.json",
                     saved: WhenEmpty? = nil) -> Rig {
        let probe = ScriptedProbe()
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent(file)))
        if let saved { settings.setWhenEmpty(saved, forProvider: id) }
        let logins = secondLogin ? [ProviderAccountConfig(accountId: "work", label: "work",
                                                          probeConfig: ["folder": "/tmp/rest-work", "accountId": "work"])] : []
        let product = stubbedProduct(id, probe: probe, settings: settings, accounts: logins)
        let told = Announced()
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock())
        let rest = RestWhenEmpty(repository: settings, announcer: told, now: { [noon] in noon })
        rest.follow(monitor)
        return Rig(monitor: monitor, product: product, rest: rest, told: told, probe: probe, settings: settings)
    }

    private func refresh(_ rig: Rig, left: Double?) async {
        await rig.probe.answer(with: left.map(usage))
        await rig.monitor.refresh(providerId: rig.product.id)
    }

    private func usage(_ left: Double) -> UsageSnapshot {
        UsageSnapshot(providerId: "p", quotas: [UsageQuota(percentRemaining: left, quotaType: .session, providerId: "p")],
                      capturedAt: Date())
    }

    // MARK: - Resting

    @Test
    func `should rest an empty product and say so when the person asked`() async throws {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)

        await refresh(rig, left: 0)

        #expect(rig.rest.isResting(rig.product))
        #expect(rig.saved == .resting(since: noon))
        let notice = try #require(rig.told.notices.first)
        #expect(notice == RestNotice(kind: .resting, productName: "Claude", providerId: "claude"))
    }

    @Test
    func `should leave the product's switch on while it rests`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)

        await refresh(rig, left: 0)

        #expect(rig.product.isEnabled)
        #expect(rig.monitor.tabs.map(\.id) == ["claude"])
    }

    @Test
    func `should leave an empty product as it is when the person never asked`() async {
        let rig = rig()

        await refresh(rig, left: 0)

        #expect(!rig.rest.isResting(rig.product))
        #expect(rig.saved == nil)
        #expect(rig.told.notices.isEmpty)
    }

    @Test
    func `should not rest a product whose refresh failed`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)

        await refresh(rig, left: nil)

        #expect(rig.saved == .watching)
        #expect(rig.told.notices.isEmpty)
    }

    @Test
    func `should say it rests once while the product stays empty`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)
        await refresh(rig, left: 0)

        await refresh(rig, left: 0)
        await refresh(rig, left: 0)

        #expect(rig.told.notices.count == 1)
    }

    // MARK: - What counts

    @Test
    func `should rest a product only when its every unpaused login is out`() async {
        let rig = rig("codex", secondLogin: true)
        rig.rest.turn(true, product: rig.product)
        await rig.probe.answer(with: usage(80))
        await rig.monitor.refresh(providerIds: [rig.product.id, "codex.work"])
        // She pauses *work*, which still has room; the plain one empties.
        rig.monitor.pause(rig.monitor.login(id: "codex.work")!)

        await refresh(rig, left: 0)

        #expect(rig.rest.isResting(rig.product))
    }

    // MARK: - The reset

    @Test
    func `should stop resting and say so at the first refresh that shows room`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)
        await refresh(rig, left: 0)

        await refresh(rig, left: 72)

        #expect(!rig.rest.isResting(rig.product))
        #expect(rig.saved == .watching)
        #expect(rig.told.notices.map(\.kind) == [.resting, .back])
    }

    @Test
    func `should keep resting when a refresh fails`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)
        await refresh(rig, left: 0)

        await refresh(rig, left: nil)

        // The last usage is kept on a failure, so the product still reads
        // depleted: no recovery is invented from a failed look.
        #expect(rig.rest.isResting(rig.product))
        #expect(rig.told.notices.count == 1)
    }

    // MARK: - Show anyway

    @Test
    func `should draw a resting product as usual when the person shows it anyway`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)
        await refresh(rig, left: 0)

        rig.rest.showAnyway(rig.product)

        #expect(!rig.rest.isResting(rig.product))
        #expect(rig.saved == .shownAnyway)
    }

    @Test
    func `should not rest a product shown anyway again while it stays empty`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)
        await refresh(rig, left: 0)
        rig.rest.showAnyway(rig.product)

        await refresh(rig, left: 0)

        #expect(!rig.rest.isResting(rig.product))
        #expect(rig.told.notices.count == 1)
    }

    @Test
    func `should rest again after a product shown anyway had room and emptied`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)
        await refresh(rig, left: 0)
        rig.rest.showAnyway(rig.product)

        await refresh(rig, left: 50)
        await refresh(rig, left: 0)

        #expect(rig.rest.isResting(rig.product))
        // Back from *shown anyway* is not back from resting: nothing to say.
        #expect(rig.told.notices.map(\.kind) == [.resting, .resting])
    }

    // MARK: - The person's switches

    @Test
    func `should forget the rest and draw the product as usual when the person turns the card off`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)
        await refresh(rig, left: 0)

        rig.rest.turn(false, product: rig.product)

        #expect(!rig.rest.isOn(rig.product))
        #expect(!rig.rest.isResting(rig.product))
        #expect(rig.saved == nil)
        #expect(rig.told.notices.count == 1)
    }

    @Test
    func `should keep resting when the person turns the product off and on again`() async {
        let rig = rig()
        rig.rest.turn(true, product: rig.product)
        await refresh(rig, left: 0)
        let tab = rig.monitor.productTabs.first { $0.id == "claude" }!

        rig.monitor.setProductEnabled(tab, enabled: false)
        rig.monitor.setProductEnabled(tab, enabled: true)

        // The switch and the rest are two facts: neither writes the other.
        #expect(rig.product.isEnabled)
        #expect(rig.saved == .resting(since: noon))
    }

    // MARK: - A relaunch

    @Test
    func `should still be resting after a relaunch`() async {
        let rig = rig(saved: .resting(since: noon))

        #expect(rig.rest.isResting(rig.product))

        await refresh(rig, left: 64)

        #expect(rig.told.notices.map(\.kind) == [.back])
    }

    @Test
    func `should not rest a product shown anyway again after a relaunch while still empty`() async {
        let rig = rig(saved: .shownAnyway)

        await refresh(rig, left: 0)

        #expect(!rig.rest.isResting(rig.product))
        #expect(rig.told.notices.isEmpty)
    }
}
