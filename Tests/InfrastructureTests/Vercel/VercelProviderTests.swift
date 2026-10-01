import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
@MainActor
struct VercelProviderTests {
    private func makeSettingsRepository() -> UserDefaultsProviderSettingsRepository {
        let defaults = UserDefaults(suiteName: "VercelProviderTests.\(UUID().uuidString)")!
        let secureCredentials = UserDefaultsCredentialRepository(
            defaults: defaults,
            keyPrefix: "VercelProviderTests.secure."
        )
        return UserDefaultsProviderSettingsRepository(
            userDefaults: defaults,
            secureCredentials: secureCredentials
        )
    }

    @Test
    func `provider has correct identity and defaults to disabled`() {
        let provider = VercelProvider(
            probe: MockUsageProbe(),
            settingsRepository: makeSettingsRepository()
        )

        #expect(provider.id == "vercel-gateway")
        #expect(provider.name == "Vercel Gateway")
        #expect(provider.cliCommand.isEmpty)
        #expect(provider.dashboardURL != nil)
        #expect(provider.isEnabled == false)
        #expect(provider.snapshot == nil)
        #expect(provider.lastError == nil)
        #expect(provider.isSyncing == false)
    }

    @Test
    func `provider reflects and persists enabled state`() {
        let repository = makeSettingsRepository()
        repository.setEnabled(true, forProvider: "vercel-gateway")
        let provider = VercelProvider(probe: MockUsageProbe(), settingsRepository: repository)

        #expect(provider.isEnabled == true)

        provider.isEnabled = false
        #expect(repository.isEnabled(forProvider: "vercel-gateway") == false)
    }

    @Test
    func `isAvailable delegates to probe`() async {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        let provider = VercelProvider(probe: probe, settingsRepository: makeSettingsRepository())

        #expect(await provider.isAvailable() == true)
    }

    @Test
    func `refresh stores snapshot on success`() async throws {
        let probe = MockUsageProbe()
        let snapshot = UsageSnapshot(
            providerId: "vercel-gateway",
            quotas: [UsageQuota(
                percentRemaining: 100,
                quotaType: .timeLimit("AI Gateway Credits"),
                providerId: "vercel-gateway",
                dollarRemaining: Decimal(string: "10.50")
            )],
            capturedAt: Date()
        )
        given(probe).probe().willReturn(snapshot)
        let provider = VercelProvider(probe: probe, settingsRepository: makeSettingsRepository())

        let result = try await provider.refresh()

        #expect(result.quotas.first?.dollarRemaining == Decimal(string: "10.50"))
        #expect(provider.snapshot != nil)
        #expect(provider.lastError == nil)
        #expect(provider.isSyncing == false)
    }

    @Test
    func `refresh stores error on failure`() async {
        let probe = MockUsageProbe()
        given(probe).probe().willThrow(ProbeError.authenticationRequired)
        let provider = VercelProvider(probe: probe, settingsRepository: makeSettingsRepository())

        await #expect(throws: ProbeError.authenticationRequired) {
            try await provider.refresh()
        }

        #expect(provider.lastError != nil)
        #expect(provider.snapshot == nil)
        #expect(provider.isSyncing == false)
    }

    @Test
    func `refresh rejects overlapping requests without racing provider state`() async throws {
        let snapshot = UsageSnapshot(
            providerId: "vercel-gateway",
            quotas: [UsageQuota(
                percentRemaining: 100,
                quotaType: .timeLimit("AI Gateway Credits"),
                providerId: "vercel-gateway",
                dollarRemaining: Decimal(string: "10.50")
            )],
            capturedAt: Date()
        )
        let probe = DelayedUsageProbe(snapshot: snapshot)
        let provider = VercelProvider(probe: probe, settingsRepository: makeSettingsRepository())

        let firstRefresh = Task { try await provider.refresh() }
        var waitIterations = 0
        while await probe.probeCallCount == 0 {
            waitIterations += 1
            try #require(waitIterations < 10_000)
            await Task.yield()
        }

        #expect(provider.isSyncing == true)
        await #expect(throws: ProbeError.executionFailed("Vercel refresh already in progress")) {
            try await provider.refresh()
        }
        #expect(provider.isSyncing == true)

        let result = try await firstRefresh.value

        #expect(result == snapshot)
        #expect(provider.snapshot == snapshot)
        #expect(provider.isSyncing == false)
        #expect(await probe.probeCallCount == 1)
    }
}

private actor DelayedUsageProbe: UsageProbe {
    private(set) var probeCallCount = 0
    private let snapshot: UsageSnapshot

    init(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
    }

    func probe() async throws -> UsageSnapshot {
        probeCallCount += 1
        try await Task.sleep(for: .milliseconds(100))
        return snapshot
    }

    func isAvailable() async -> Bool {
        true
    }
}
