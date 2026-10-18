import Testing
import Foundation
import Observation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Issue #141: the popover pills, the overview and ⌘1–⌘9 must follow the
/// user's persisted provider order instead of the fixed registration order.
@Suite
@MainActor
struct QuotaMonitorProviderOrderTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// Settings mock: every provider enabled, persisting the given order.
    private func makeSettingsRepository(order: [String] = []) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        given(mock).providerOrder().willReturn(order)
        given(mock).setProviderOrder(.any).willReturn()
        given(mock).hiddenQuotaKeys(forProvider: .any).willReturn([])
        given(mock).setHiddenQuotaKeys(.any, forProvider: .any).willReturn()
        return mock
    }

    /// Registration order [claude, codex, gemini], as ClaudeBarApp registers
    /// them; the order is `Providers`' (TARGET §2.1) and the
    /// Monitor shows it.
    private func makeProviders(settings: any ProviderSettingsRepository) -> Providers {
        kept([
            stubbedProduct("claude", probe: MockUsageProbe(), settings: settings),
            stubbedProduct("codex", probe: MockUsageProbe(), settings: settings),
            stubbedProduct("gemini", probe: MockUsageProbe(), settings: settings),
        ], settings: settings)
    }

    private func makeMonitor(
        providers: Providers,
        settings: (any ProviderSettingsRepository)? = nil
    ) -> QuotaMonitor {
        QuotaMonitor(
            providers: providers,
            alerter: nil,
            clock: TestClock(),
            settingsRepository: settings
        )
    }

    // MARK: - Reading the persisted order

    @Test
    func `should list the providers in registration order when the person never reordered them`() {
        let settings = makeSettingsRepository(order: [])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.lineup.map(\.id) == ["claude", "codex", "gemini"])
        #expect(monitor.logins.map(\.id) == ["claude", "codex", "gemini"])
    }

    @Test
    func `should show the lineup in the person's saved order (#141)`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.lineup.map(\.id) == ["gemini", "claude", "codex"])
    }

    @Test
    func `should list every login in the person's saved order (#141)`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.logins.map(\.id) == ["gemini", "claude", "codex"])
    }

    @Test
    func `should place a provider missing from the saved order at its registration position`() {
        // "gone" was removed from the app; claude and codex are not listed, so
        // they keep their registration order behind the listed gemini.
        let settings = makeSettingsRepository(order: ["gemini", "gone"])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.logins.map(\.id) == ["gemini", "claude", "codex"])
    }

    @Test
    func `should leave a disabled provider out of the lineup while still listing its login in the saved order`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        repository.provider(id: "codex")?.isEnabled = false
        let monitor = makeMonitor(providers: repository, settings: settings)

        #expect(monitor.lineup.map(\.id) == ["gemini", "claude"])
        // ... while allProviders still shows the full persisted order
        #expect(monitor.logins.map(\.id) == ["gemini", "claude", "codex"])
    }

    // MARK: - Keyboard selection follows the persisted order

    @Test
    func `should select providers with ⌘1–⌘3 in the person's saved order`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        monitor.selectProvider(atPosition: 1)
        #expect(monitor.selectedProviderId == "gemini")

        monitor.selectProvider(atPosition: 2)
        #expect(monitor.selectedProviderId == "claude")

        monitor.selectProvider(atPosition: 3)
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `should land ⌘1 on the first enabled provider when the first saved one is disabled`() {
        let settings = makeSettingsRepository(order: ["gemini", "claude", "codex"])
        let repository = makeProviders(settings: settings)
        repository.provider(id: "gemini")?.isEnabled = false
        let monitor = makeMonitor(providers: repository, settings: settings)

        // ⌘1 lands on the first *enabled* provider in the persisted order.
        monitor.selectProvider(atPosition: 1)
        #expect(monitor.selectedProviderId == "claude")
    }

    // MARK: - Reordering

    @Test
    func `should show and select a moved provider at its new position`() {
        let settings = makeSettingsRepository()
        let repository = makeProviders(settings: settings)
        let monitor = makeMonitor(providers: repository, settings: settings)

        monitor.providers.move("gemini", by: -2)

        #expect(monitor.lineup.map(\.id) == ["gemini", "claude", "codex"])
        monitor.selectProvider(atPosition: 1)
        #expect(monitor.selectedProviderId == "gemini")
    }
}
