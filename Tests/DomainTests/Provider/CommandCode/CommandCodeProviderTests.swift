import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("CommandCodeProvider Tests")
@MainActor
struct CommandCodeProviderTests {

    private func makeProvider(probe: MockUsageProbe = MockUsageProbe()) -> CommandCodeProvider {
        CommandCodeProvider(probe: probe, settingsRepository: MockRepositoryFactory.makeSettingsRepository())
    }

    // MARK: - Identity Tests

    @Test
    func `provider identity`() {
        let provider = makeProvider()

        #expect(provider.id == "commandcode")
        #expect(provider.name == "Command Code")
        #expect(provider.cliCommand == "cmd")
    }

    @Test
    func `dashboard URL points to commandcode ai`() {
        let provider = makeProvider()

        #expect(provider.dashboardURL?.host?.contains("commandcode.ai") == true)
    }

    @Test
    func `provider is enabled by default`() {
        #expect(makeProvider().isEnabled == true)
    }

    @Test
    func `provider starts with no snapshot`() {
        let provider = makeProvider()

        #expect(provider.snapshot == nil)
        #expect(provider.lastError == nil)
        #expect(provider.isSyncing == false)
    }

    // MARK: - Refresh Tests

    @Test
    func `isAvailable delegates to probe`() async {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(false)

        #expect(await makeProvider(probe: probe).isAvailable() == false)
    }

    @Test
    func `refresh updates snapshot on success`() async throws {
        let probe = MockUsageProbe()
        let expected = UsageSnapshot(
            providerId: "commandcode",
            quotas: [
                UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "commandcode")
            ],
            capturedAt: Date()
        )
        given(probe).probe().willReturn(expected)
        let provider = makeProvider(probe: probe)

        let result = try await provider.refresh()

        #expect(result == expected)
        #expect(provider.snapshot == expected)
        #expect(provider.lastError == nil)
    }

    @Test
    func `refresh records error on failure`() async {
        let probe = MockUsageProbe()
        given(probe).probe().willThrow(ProbeError.authenticationRequired)
        let provider = makeProvider(probe: probe)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await provider.refresh()
        }
        #expect(provider.snapshot == nil)
        #expect(provider.lastError as? ProbeError == .authenticationRequired)
    }
}
