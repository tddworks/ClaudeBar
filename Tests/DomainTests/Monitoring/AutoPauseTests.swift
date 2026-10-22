import Foundation
import Testing
@testable import Domain

/// *Auto-pause on empty*: a product whose every counted login is depleted
/// turns its own switch off — once — and back on at the first refresh that
/// shows room again, telling the person both times. The person's own off is
/// never touched (docs/features/monitoring/auto-pause/design.md).
@MainActor
@Suite
struct AutoPauseTests {
    /// A clock the quiet loop never wakes from: a test that starts one parks
    /// it on the first sleep instead of refreshing in the background forever.
    private struct HangingClock: Clock {
        func sleep(for duration: Duration) async throws { try await Task.sleep(for: .seconds(3_600)) }
        func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
    }

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private let temp = FileManager.default.temporaryDirectory.appendingPathComponent("auto-pause-\(UUID().uuidString)")

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
    private final class Announced: AutoPauseAnnouncer, @unchecked Sendable {
        var notices: [AutoPauseNotice] = []
        func announce(_ notice: AutoPauseNotice) async { notices.append(notice) }
    }

    private struct Rig {
        let monitor: QuotaMonitor
        let product: Provider
        let pause: AutoPause
        let told: Announced
        let probe: ScriptedProbe
        /// The settings the instruction and the marker are saved in — read
        /// directly, so a test asserts what was persisted.
        let settings: any ProviderSettingsRepository

        var marker: Bool { settings.isOn("autoPaused", forProvider: product.id) == true }
        func turnInstruction(_ on: Bool) { pause.turn(on, product: product) }
    }

    /// One product with one login — Mia's one Claude is the main case — real
    /// settings on disk, and the watcher attached as the app does, minus the
    /// loops: tests drive `review` and `sweep` by hand.
    private func rig(_ id: String = "claude", secondLogin: Bool = false) throws -> Rig {
        let probe = ScriptedProbe()
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("settings.json")))
        let saved = secondLogin ? [ProviderAccountConfig(accountId: "work", label: "work",
                                                         probeConfig: ["folder": "/tmp/auto-pause-work", "accountId": "work"])] : []
        let product = stubbedProduct(id, probe: probe, settings: settings, accounts: saved)
        let told = Announced()
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock())
        let pause = AutoPause(settings: settings, announcer: told, clock: HangingClock())
        pause.attach(monitor)
        monitor.onRefreshed { [weak pause] login in await pause?.review(login) }
        return Rig(monitor: monitor, product: product, pause: pause, told: told, probe: probe, settings: settings)
    }

    private func tab(_ rig: Rig) -> ProductTab {
        rig.monitor.productTabs.first { $0.id == rig.product.id }!
    }

    /// A refresh that sees the product empty: every counted login out.
    private func deplete(_ rig: Rig) async {
        await rig.probe.answer(with: usage(0))
        await rig.monitor.refresh(providerId: rig.product.id)
    }

    private func usage(_ left: Double) -> UsageSnapshot {
        UsageSnapshot(providerId: "p", quotas: [UsageQuota(percentRemaining: left, quotaType: .session, providerId: "p")],
                      capturedAt: Date())
    }

    // MARK: - The crossing

    @Test
    func `should turn an empty product off and say so when the person asked`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)

        await deplete(rig)

        #expect(rig.product.isEnabled == false)
        #expect(rig.marker)
        #expect(rig.told.notices.count == 1)
        let notice = try #require(rig.told.notices.first)
        #expect(notice.kind == .turnedOff)
        #expect(notice.productName == "Claude")
        #expect(notice.link == URL(string: "claudebar://enable?provider=claude"))
    }

    @Test
    func `should leave a product on when the person never asked`() async throws {
        let rig = try rig()

        await deplete(rig)

        #expect(rig.product.isEnabled)
        #expect(!rig.marker)
        #expect(rig.told.notices.isEmpty)
    }

    @Test
    func `should leave an armed product alone while it has no usage to judge`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)

        // The fetch fails: nothing is seen, and nothing seen is not empty.
        await rig.probe.answer(with: nil)
        await rig.monitor.refresh(providerId: rig.product.id)

        #expect(rig.product.isEnabled)
        #expect(!rig.marker)
        #expect(rig.told.notices.isEmpty)
    }

    @Test
    func `should stay quiet while the product stays empty`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)
        await deplete(rig)

        await rig.monitor.refresh(providerId: rig.product.id)
        await rig.monitor.refresh(providerId: rig.product.id)

        #expect(rig.told.notices.count == 1)
    }

    @Test
    func `should not pause again after the person turns it back on while still empty`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)
        await deplete(rig)

        rig.monitor.setProductEnabled(tab(rig), enabled: true)
        await deplete(rig)

        #expect(rig.product.isEnabled)
        #expect(rig.told.notices.count == 1)
    }

    // MARK: - What counts

    @Test
    func `should count only the unpaused logins when a product empties`() async throws {
        let rig = try rig("codex", secondLogin: true)
        rig.turnInstruction(true)
        // Both logins seen: the plain one with room, *work* out. Then she
        // pauses *work*, and the plain one empties.
        await rig.probe.answer(with: usage(80))
        await rig.monitor.refresh(providerIds: [rig.product.id, "codex.work"])
        rig.monitor.pause(rig.monitor.login(id: "codex.work")!)

        await deplete(rig)

        #expect(rig.product.isEnabled == false)
        #expect(rig.marker)
    }

    @Test
    func `should keep a product on while its only out login is paused`() async throws {
        let rig = try rig("codex", secondLogin: true)
        rig.turnInstruction(true)
        await rig.probe.answer(with: usage(80))
        await rig.monitor.refresh(providerIds: [rig.product.id, "codex.work"])

        // *Work* is out, but she paused it: it is out of every judgement, as ever.
        rig.monitor.pause(rig.monitor.login(id: "codex.work")!)
        await rig.monitor.refresh(providerId: rig.product.id)

        #expect(rig.product.isEnabled)
        #expect(rig.told.notices.isEmpty)
    }

    // MARK: - The reset

    @Test
    func `should turn a waiting product back on and say so when a refresh shows room`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)
        await deplete(rig)

        // The reset is observed, not inferred: a refresh lands — reaching the
        // product although it is off — and shows room.
        await rig.probe.answer(with: usage(72))
        await rig.pause.sweep(rig.product)

        #expect(rig.product.isEnabled)
        #expect(!rig.marker)
        #expect(rig.product.defaultAccount.snapshot?.quotas.first?.percentRemaining == 72)
        #expect(rig.told.notices.map(\.kind) == [.turnedOff, .turnedOn])
    }

    @Test
    func `should keep waiting when a refresh fails while off`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)
        await deplete(rig)

        await rig.probe.answer(with: nil)
        await rig.pause.sweep(rig.product)

        // The last usage is kept on a failure, so the product still reads
        // depleted: no recovery is invented from a failed look.
        #expect(rig.product.isEnabled == false)
        #expect(rig.marker)
        #expect(rig.told.notices.count == 1)
    }

    // MARK: - The person's own off

    @Test
    func `should leave a product the person turned off alone however empty it is`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)
        rig.monitor.setProductEnabled(tab(rig), enabled: false)

        await deplete(rig)

        #expect(rig.product.isEnabled == false)
        #expect(!rig.marker)
        #expect(rig.told.notices.isEmpty)
    }

    @Test
    func `should put the product back on without a word when the person withdraws the instruction`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)
        await deplete(rig)

        rig.turnInstruction(false)

        #expect(rig.product.isEnabled)
        #expect(!rig.marker)
        #expect(rig.pause.isWaiting(rig.product) == false)
        #expect(rig.told.notices.count == 1)
    }

    @Test
    func `should leave the person's own off alone when the instruction is withdrawn`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)
        rig.monitor.setProductEnabled(tab(rig), enabled: false)

        rig.turnInstruction(false)

        // The off was hers: ClaudeBar doesn't turn it on.
        #expect(rig.product.isEnabled == false)
        #expect(rig.told.notices.isEmpty)
    }

    @Test
    func `should turn the product back on from the notice's one click without re-pausing`() async throws {
        let rig = try rig()
        rig.turnInstruction(true)
        await deplete(rig)

        rig.pause.turnBackOn(rig.product)

        #expect(rig.product.isEnabled)
        #expect(!rig.marker)
        await deplete(rig)
        #expect(rig.product.isEnabled)
        #expect(rig.told.notices.count == 1)
    }

    // MARK: - A relaunch

    /// A monitor over one off product, and a watcher following it the way the
    /// app does — markers already on disk say what the last launch left.
    private func relaunchedRig(instruction: Bool, marker: Bool) throws -> (Rig, String) {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("relaunch-\(UUID().uuidString).json")))
        if instruction { settings.setOn(true, "autoPause", forProvider: "claude") }
        if marker { settings.setOn(true, "autoPaused", forProvider: "claude") }
        let probe = ScriptedProbe()
        let product = stubbedProduct("claude", probe: probe, settings: settings)
        product.isEnabled = false
        let told = Announced()
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock())
        let pause = AutoPause(settings: settings, announcer: told, clock: HangingClock())
        pause.follow(monitor)
        return (Rig(monitor: monitor, product: product, pause: pause, told: told, probe: probe, settings: settings), "claude")
    }

    @Test
    func `should keep waiting for a reset across a relaunch`() async throws {
        let (rig, _) = try relaunchedRig(instruction: true, marker: true)

        #expect(rig.pause.isWaiting(rig.product))

        await rig.probe.answer(with: usage(64))
        await rig.pause.sweep(rig.product)

        #expect(rig.product.isEnabled)
        #expect(rig.told.notices.map(\.kind) == [.turnedOn])
    }

    @Test
    func `should clean up a stale marker when the instruction was withdrawn before the relaunch`() throws {
        let (rig, id) = try relaunchedRig(instruction: false, marker: true)

        // Left off — the person's off now — and never announced.
        #expect(rig.product.isEnabled == false)
        #expect(rig.pause.isWaiting(rig.product) == false)
        #expect(rig.told.notices.isEmpty)
        #expect(rig.settings.isOn("autoPaused", forProvider: id) == false)
    }

    @Test
    func `should clean up a stale marker quietly when the person turned the product on before the relaunch`() async throws {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("reenabled.json")))
        settings.setOn(true, "autoPause", forProvider: "claude")
        settings.setOn(true, "autoPaused", forProvider: "claude")
        let probe = ScriptedProbe()
        let product = stubbedProduct("claude", probe: probe, settings: settings)
        let told = Announced()
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock())
        let pause = AutoPause(settings: settings, announcer: told, clock: HangingClock())
        pause.follow(monitor)

        // Still empty — and it stays on: her re-enable is not undone behind
        // her back, and the next crossing needs a recovery first.
        await probe.answer(with: usage(0))
        await monitor.refresh(providerId: "claude")

        #expect(product.isEnabled)
        #expect(told.notices.isEmpty)
    }
}
